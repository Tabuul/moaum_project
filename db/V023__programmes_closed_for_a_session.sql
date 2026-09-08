-- ═══════════════════════════════════════════════════════════════════════════
-- V023 — a programme closed for a session
--
-- Not every programme the University runs admits every session. Rather than
-- leave such a programme standing with no rule — which reads as an omission
-- — the Academic Office closes it for the session, with the reason on the
-- record. A closed programme needs no rule, is not admitted into, and a
-- candidate JAMB sends for it is told so at registration instead of being
-- let through to nowhere. Reopening it is a second act, on the record too.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE admissions.programme_closed (
    policy_id      uuid NOT NULL REFERENCES admissions.session_policy(id),
    programme_code text NOT NULL REFERENCES ref.programme(code),
    reason         text NOT NULL,
    closed_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (policy_id, programme_code),
    CONSTRAINT ck_closed_reason CHECK (btrim(reason) <> '')
);
SELECT audit.attach('admissions.programme_closed');

-- whether a programme is closed for a session
CREATE OR REPLACE FUNCTION admissions.programme_is_closed(p_session text, p_programme text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_programme IS NOT NULL AND EXISTS (
        SELECT 1 FROM admissions.programme_closed c
          JOIN admissions.session_policy p ON p.id = c.policy_id
         WHERE p.session = p_session AND c.programme_code = p_programme);
$$;

-- the lookup (V021), now answering 'closed' for a candidate JAMB sent for a programme the session does not admit into
CREATE OR REPLACE FUNCTION admissions.applicant_lookup(p_session text, p_jamb_key text)
RETURNS TABLE (state text, row_id uuid, surname text, other_names text, programme_code text, programme text,
               list_kind text, entry_mode text, sex text, state_of_origin text, lga text, aggregate int)
LANGUAGE plpgsql STABLE AS $$
DECLARE key text := upper(btrim(p_jamb_key)); r record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admissions.caps_row_live x WHERE x.session = p_session) THEN
        RETURN QUERY SELECT 'nolist'::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::int;
        RETURN;
    END IF;
    SELECT x.id, x.surname, x.other_names, x.jamb_code, p.name AS programme, b.list_kind, x.entry_mode,
           x.sex, x.state_of_origin, x.lga, x.aggregate
      INTO r
      FROM admissions.caps_row_live x
      JOIN admissions.caps_batch b ON b.id = x.batch_id
      LEFT JOIN ref.programme p ON p.code = x.jamb_code
     WHERE x.session = p_session AND x.jamb_key = key
     ORDER BY b.uploaded_at DESC LIMIT 1;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'none'::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::int;
        RETURN;
    END IF;
    RETURN QUERY SELECT CASE WHEN EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE a.session = p_session AND a.jamb_key = key)
                                 THEN 'registered'
                             WHEN admissions.programme_is_closed(p_session, r.jamb_code) THEN 'closed'
                             ELSE 'found' END,
                        r.id, r.surname, r.other_names, r.jamb_code, r.programme, r.list_kind, r.entry_mode, r.sex, r.state_of_origin, r.lga, r.aggregate;
END $$;

-- registering (V021): a closed programme is refused with the reason, not let through
CREATE OR REPLACE FUNCTION admissions.register_applicant(p_session text, p_jamb_key text, p_email text, p_phone text, p_hash text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE key text := upper(btrim(p_jamb_key)); f record; v_candidate uuid; v_account uuid := gen_random_uuid();
        v_app uuid := gen_random_uuid(); v_no text; v_yy text := substr(p_session, 3, 2);
BEGIN
    SELECT * INTO f FROM admissions.applicant_lookup(p_session, key);
    IF f.state = 'nolist' THEN
        RAISE EXCEPTION 'nobody can be verified: no admission list is loaded for %', p_session
        USING ERRCODE = '23514', HINT = 'The Academic Office loads the list JAMB sent on the JAMB admission lists screen. Until it does, this screen will not guess.';
    ELSIF f.state = 'none' THEN
        RAISE EXCEPTION 'the number % is not on the list JAMB sent the University for %', key, p_session
        USING ERRCODE = '23514', HINT = 'A digit may be wrong, the University may not have been chosen on CAPS, or the tranche has not reached us yet. Do not travel to the campus over this.';
    ELSIF f.state = 'registered' THEN
        RAISE EXCEPTION 'an application account already exists for %', key
        USING ERRCODE = '23505', HINT = 'Sign in with the email and password you chose. A second account would invalidate both.';
    ELSIF f.state = 'closed' THEN
        RAISE EXCEPTION 'the University is not admitting into % this session', coalesce(f.programme, f.programme_code)
        USING ERRCODE = '23514', HINT = 'Change your programme with JAMB to one the University admits into this session.';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = lower(btrim(p_email))) THEN
        RAISE EXCEPTION 'the address % already belongs to an application account', btrim(p_email)
        USING ERRCODE = '23505', HINT = 'Sign in with it, or use another address.';
    END IF;

    SELECT c.id INTO v_candidate FROM admissions.candidate c WHERE c.session = p_session AND c.jamb_key = key;
    IF v_candidate IS NULL THEN
        v_candidate := gen_random_uuid();
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
        VALUES (v_candidate, p_session, key, f.surname, f.other_names, coalesce(f.programme, f.programme_code),
                CASE WHEN f.entry_mode IN ('UTME','DIRECT_ENTRY','TRANSFER') THEN f.entry_mode ELSE 'UTME' END,
                CASE WHEN f.entry_mode = 'UTME' THEN 100 ELSE 200 END, 'PROPOSED', f.row_id);
    END IF;

    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
    VALUES (v_account, p_session, v_candidate, key, btrim(p_email), p_phone, p_hash);

    v_no := 'APP/' || v_yy || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', p_session)::text, 6, '0');
    INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no)
    VALUES (v_app, v_account, v_candidate, p_session, v_no);
    RETURN v_account;
END $$;

COMMIT;
