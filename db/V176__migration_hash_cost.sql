-- ═══════════════════════════════════════════════════════════════════════════
-- V176 — the migration's initial password hashes at cost 10, not 12
--
--   import_applicant bcrypt-hashes each initial password, and at cost 12 that is
--   the slow step of a 13,000-row migration (bcrypt is deliberately expensive).
--   The initial password is only the applicant's JAMB number, and they are
--   forced to change it on first sign-in — a temporary, low-value secret — so
--   cost 12 is overkill here. Cost 10 (the OWASP minimum for bcrypt) is ~4x
--   faster and still strong for a password that lives until first login. The
--   real password the applicant then sets is hashed by the normal path,
--   unchanged. bcrypt records its cost in the hash, so verifying a cost-10 and a
--   cost-12 hash side by side just works.
--
--   Only the salt cost changes from V174; everything else in import_applicant is
--   identical (CAPS-driven candidate, login, confirmed application fee).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.import_applicant(
    p_session text, p_jamb_reg_no text, p_email text, p_phone text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    key     text := upper(btrim(coalesce(p_jamb_reg_no, '')));
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
    placeholder_email text;
    caps    record;
    prog    text;
    lvl     int;
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

    IF key !~ '^[0-9]{6,}[A-Z]{0,3}$' THEN RETURN 'skip: bad JAMB number'; END IF;

    SELECT r.id, r.surname, r.other_names, r.jamb_code, r.entry_mode
      INTO caps
      FROM admissions.caps_row_live r
     WHERE r.session = p_session AND upper(btrim(r.jamb_reg_no)) = key
     LIMIT 1;
    IF caps.id IS NULL THEN
        RETURN 'skip: not on the JAMB CAPS list';
    END IF;

    placeholder_email := lower(key) || '@migrate.moau.local';

    IF length(v_phone) = 13 AND left(v_phone, 3) = '234' THEN v_phone := '0' || right(v_phone, 10); END IF;
    IF length(v_phone) = 10 AND left(v_phone, 1) <> '0' THEN v_phone := '0' || v_phone; END IF;
    IF v_phone !~ '^0[0-9]{10}$' THEN v_phone := '00000000000'; END IF;

    IF v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN v_email := placeholder_email; END IF;

    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE a.session = p_session AND a.jamb_key = key) THEN
        RETURN 'exists';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = v_email) THEN
        v_email := placeholder_email;
        IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = v_email) THEN
            RETURN 'skip: duplicate account';
        END IF;
    END IF;

    prog := coalesce((SELECT p.name FROM ref.programme p WHERE upper(p.code) = upper(caps.jamb_code) ORDER BY p.archived, p.code LIMIT 1),
                     caps.jamb_code);
    lvl  := CASE WHEN caps.entry_mode = 'UTME' THEN 100 ELSE 200 END;

    BEGIN
        SELECT c.id INTO v_candidate FROM admissions.candidate c WHERE c.session = p_session AND c.jamb_key = key;
        IF v_candidate IS NULL THEN
            v_candidate := gen_random_uuid();
            INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
            VALUES (v_candidate, p_session, key, caps.surname, caps.other_names, prog,
                    CASE WHEN caps.entry_mode IN ('UTME','DIRECT_ENTRY','TRANSFER') THEN caps.entry_mode ELSE 'UTME' END,
                    lvl, 'PROPOSED', caps.id);
        ELSE
            UPDATE admissions.candidate SET admitted_from = caps.id WHERE id = v_candidate AND admitted_from IS NULL;
        END IF;

        v_account := gen_random_uuid();
        INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
        VALUES (v_account, p_session, v_candidate, key, v_email, v_phone, crypt(key, gen_salt('bf', 10)));

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

        IF v_email = placeholder_email AND v_phone = '00000000000' THEN RETURN 'imported (no contacts)';
        ELSIF v_email = placeholder_email THEN RETURN 'imported (no email)';
        ELSIF v_phone = '00000000000' THEN RETURN 'imported (no phone)';
        ELSE RETURN 'imported';
        END IF;
    EXCEPTION
        WHEN unique_violation THEN RETURN 'exists';
        WHEN OTHERS THEN RETURN 'error: ' || SQLERRM;
    END;
END $$;

COMMIT;
