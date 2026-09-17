-- ═══════════════════════════════════════════════════════════════════════════
-- V169 — import_applicant: fix "column reference email is ambiguous"
--
--   V168 declared local variables named `email` and `phone`, which collide with
--   the columns of admissions.applicant_account. In the check
--       WHERE lower(a.email) = email
--   PostgreSQL cannot tell the column `email` from the variable `email`, and
--   (variable_conflict = error, the default) raises "column reference \"email\"
--   is ambiguous" at RUN time — caught by the function's EXCEPTION block and
--   returned as an error, so every migrated row was skipped as an email error.
--   CI only proves the migration applies, not that the function runs against
--   data, so it was not caught there. The fix is to rename the locals to
--   v_email / v_phone; the logic is otherwise identical to V168.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.import_applicant(
    p_session text, p_jamb_reg_no text, p_surname text, p_other_names text,
    p_programme text, p_entry_mode text, p_email text, p_phone text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    key     text := upper(btrim(coalesce(p_jamb_reg_no, '')));
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
    mode    text := upper(btrim(coalesce(p_entry_mode, 'UTME')));
    placeholder_email text;
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
    IF btrim(coalesce(p_surname, '')) = '' OR btrim(coalesce(p_other_names, '')) = '' THEN RETURN 'skip: missing name'; END IF;

    placeholder_email := lower(key) || '@migrate.moau.local';

    IF length(v_phone) = 13 AND left(v_phone, 3) = '234' THEN v_phone := '0' || right(v_phone, 10); END IF;
    IF length(v_phone) = 10 AND left(v_phone, 1) <> '0' THEN v_phone := '0' || v_phone; END IF;
    IF v_phone !~ '^0[0-9]{10}$' THEN v_phone := '00000000000'; END IF;

    IF v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN v_email := placeholder_email; END IF;

    mode := CASE WHEN mode IN ('DE', 'DIRECT ENTRY', 'DIRECT-ENTRY', 'DIRECT_ENTRY') THEN 'DIRECT_ENTRY'
                 WHEN mode = 'TRANSFER' THEN 'TRANSFER' ELSE 'UTME' END;
    lvl := CASE WHEN mode = 'UTME' THEN 100 ELSE 200 END;

    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE a.session = p_session AND a.jamb_key = key) THEN
        RETURN 'exists';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = v_email) THEN
        v_email := placeholder_email;
        IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = v_email) THEN
            RETURN 'skip: duplicate account';
        END IF;
    END IF;

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
        VALUES (v_account, p_session, v_candidate, key, v_email, v_phone, crypt(key, gen_salt('bf', 12)));

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
