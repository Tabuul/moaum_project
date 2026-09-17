-- ═══════════════════════════════════════════════════════════════════════════
-- V167 — admissions.import_applicant: bring paid applicants over from the old portal
--
--   ~13,000 candidates applied and paid the application fee on the previous
--   portal. This imports one such applicant, idempotently, without any of the
--   things the live flow would trip over:
--     * register_applicant requires the candidate to be on a loaded CAPS list —
--       these are not, so this creates the candidate itself (offer_state
--       PROPOSED, no CAPS row), from the row uploaded.
--     * confirm_fee sends an email and an SMS — firing that 13,000 times would
--       be a catastrophe — so this writes the confirmed APPLICATION fee_reference
--       directly, with no notification.
--   Per the office's decision: the application is marked BOTH paid
--   (fee_confirmed_at) AND submitted (submitted_at), and the confirmed amount is
--   the application fee plus the portal charge, as stated for the session. The
--   initial password is the candidate's JAMB number (bcrypt, cost 12).
--
--   Returns a status per row: 'imported', 'exists' (already has an account this
--   session — safe to re-run), or 'skip: <reason>' / 'error: <message>' so a bad
--   row never aborts the batch. It is a function only; the office triggers it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.import_applicant(
    p_session text, p_jamb_reg_no text, p_surname text, p_other_names text,
    p_programme text, p_entry_mode text, p_email text, p_phone text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    key   text := upper(btrim(coalesce(p_jamb_reg_no, '')));
    email text := lower(btrim(coalesce(p_email, '')));
    phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
    mode  text := upper(btrim(coalesce(p_entry_mode, 'UTME')));
    prog  text;
    lvl   int;
    v_candidate uuid;
    v_account   uuid;
    v_app       uuid;
    v_no        text;
    v_yy        text := substr(p_session, 3, 2);
    v_ref       text;
    v_rct       text;
    fee         record;
    v_amount    numeric;
BEGIN
    IF admissions.acting_person() IS NULL THEN
        RAISE EXCEPTION 'an import is made by a person' USING ERRCODE = '23514';
    END IF;

    -- normalise the phone: 0XXXXXXXXXX, or 234XXXXXXXXXX -> 0XXXXXXXXXX
    IF length(phone) = 13 AND left(phone, 3) = '234' THEN phone := '0' || right(phone, 10); END IF;
    IF length(phone) = 10 AND left(phone, 1) <> '0' THEN phone := '0' || phone; END IF;

    -- normalise the entry mode; UTME enters at 100, everything else at 200
    mode := CASE WHEN mode IN ('DE', 'DIRECT ENTRY', 'DIRECT-ENTRY', 'DIRECT_ENTRY') THEN 'DIRECT_ENTRY'
                 WHEN mode = 'TRANSFER' THEN 'TRANSFER' ELSE 'UTME' END;
    lvl := CASE WHEN mode = 'UTME' THEN 100 ELSE 200 END;

    -- validate what the constraints will otherwise reject one row at a time
    IF key !~ '^[0-9]{6,}[A-Z]{0,3}$' THEN RETURN 'skip: bad JAMB number'; END IF;
    IF email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN RETURN 'skip: bad email'; END IF;
    IF phone !~ '^0[0-9]{10}$' THEN RETURN 'skip: bad phone'; END IF;
    IF btrim(coalesce(p_surname, '')) = '' OR btrim(coalesce(p_other_names, '')) = '' THEN RETURN 'skip: missing name'; END IF;

    -- idempotent: an account already exists for this number this session
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE a.session = p_session AND a.jamb_key = key) THEN
        RETURN 'exists';
    END IF;
    -- the address is already on another account (unique across the portal)
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = email) THEN
        RETURN 'skip: email already in use';
    END IF;

    -- store the programme by NAME (a code or a name may be given)
    prog := coalesce((SELECT p.name FROM ref.programme p
                       WHERE upper(p.code) = upper(btrim(p_programme)) OR upper(p.name) = upper(btrim(p_programme))
                       ORDER BY p.archived, p.code LIMIT 1), nullif(btrim(p_programme), ''));
    IF prog IS NULL THEN RETURN 'skip: missing programme'; END IF;

    BEGIN
        SELECT c.id INTO v_candidate FROM admissions.candidate c WHERE c.session = p_session AND c.jamb_key = key;
        IF v_candidate IS NULL THEN
            v_candidate := gen_random_uuid();
            INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state)
            VALUES (v_candidate, p_session, key, btrim(p_surname), btrim(p_other_names), prog, mode, lvl, 'PROPOSED');
        END IF;

        v_account := gen_random_uuid();
        INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
        VALUES (v_account, p_session, v_candidate, key, email, phone, crypt(key, gen_salt('bf', 12)));

        v_app := gen_random_uuid();
        v_no  := 'APP/' || v_yy || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', p_session)::text, 6, '0');
        INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at)
        VALUES (v_app, v_account, v_candidate, p_session, v_no, now(), now());

        SELECT * INTO fee FROM admissions.applicant_fee_rule(p_session);
        v_amount := fee.application_fee + fee.portal_charge;
        v_ref := 'MOAUM-APP-' || right(v_no, 6) || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
        v_rct := 'RCT-' || left(p_session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', p_session)::text, 5, '0');
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at, confirmed_at, confirmed_by, channel, note, receipt_no)
        VALUES (gen_random_uuid(), v_app, 'APPLICATION', v_ref, v_amount, now(), now(), admissions.acting_person(),
                'Old-portal migration', 'Migrated: applied and paid on the previous portal', v_rct);

        RETURN 'imported';
    EXCEPTION
        WHEN unique_violation THEN RETURN 'exists';
        WHEN OTHERS THEN RETURN 'error: ' || SQLERRM;
    END;
END $$;

COMMIT;
