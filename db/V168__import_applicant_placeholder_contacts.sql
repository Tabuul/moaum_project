-- ═══════════════════════════════════════════════════════════════════════════
-- V168 — import_applicant: fill placeholder contacts when email/phone are absent
--
--   The office does not yet hold an email and phone for every old-portal
--   applicant, but every one still needs to come across. The account table
--   requires both (NOT NULL, strict formats), so a row without them cannot make
--   an account — and without an account there is no paid application.
--
--   So: use the email/phone given when they are valid; otherwise fill a
--   placeholder — email '<jambnumber>@migrate.moau.local', phone '00000000000'.
--   Sign-in already accepts the JAMB number as the username, so a placeholder
--   email does not lock anyone out: they sign in with their JAMB number and the
--   JAMB number as the initial password, and add their real email and phone in
--   their profile afterwards. Nothing is emailed to a placeholder — the import
--   writes the fee directly and sends no notification. If a real email given is
--   already on another account, the placeholder is used instead, so the row
--   still imports. Everything else is V167. V167 is applied, so this is new.
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
    placeholder_email text;
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

    -- the JAMB number and a name are the only truly required fields
    IF key !~ '^[0-9]{6,}[A-Z]{0,3}$' THEN RETURN 'skip: bad JAMB number'; END IF;
    IF btrim(coalesce(p_surname, '')) = '' OR btrim(coalesce(p_other_names, '')) = '' THEN RETURN 'skip: missing name'; END IF;

    placeholder_email := lower(key) || '@migrate.moau.local';

    -- phone: normalise (234XXXXXXXXXX -> 0XXXXXXXXXX), else a placeholder
    IF length(phone) = 13 AND left(phone, 3) = '234' THEN phone := '0' || right(phone, 10); END IF;
    IF length(phone) = 10 AND left(phone, 1) <> '0' THEN phone := '0' || phone; END IF;
    IF phone !~ '^0[0-9]{10}$' THEN phone := '00000000000'; END IF;

    -- email: use it when valid, else a placeholder on the JAMB number
    IF email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN email := placeholder_email; END IF;

    -- entry mode; UTME enters at 100, everything else at 200
    mode := CASE WHEN mode IN ('DE', 'DIRECT ENTRY', 'DIRECT-ENTRY', 'DIRECT_ENTRY') THEN 'DIRECT_ENTRY'
                 WHEN mode = 'TRANSFER' THEN 'TRANSFER' ELSE 'UTME' END;
    lvl := CASE WHEN mode = 'UTME' THEN 100 ELSE 200 END;

    -- idempotent: an account already exists for this number this session
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE a.session = p_session AND a.jamb_key = key) THEN
        RETURN 'exists';
    END IF;
    -- the chosen address is already on another account: fall back to the placeholder so the row still imports
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = email) THEN
        email := placeholder_email;
        IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = email) THEN
            RETURN 'skip: duplicate account';
        END IF;
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

        -- tell the caller when a placeholder stood in, so the office can chase the real contacts
        IF email = placeholder_email AND phone = '00000000000' THEN RETURN 'imported (no contacts)';
        ELSIF email = placeholder_email THEN RETURN 'imported (no email)';
        ELSIF phone = '00000000000' THEN RETURN 'imported (no phone)';
        ELSE RETURN 'imported';
        END IF;
    EXCEPTION
        WHEN unique_violation THEN RETURN 'exists';
        WHEN OTHERS THEN RETURN 'error: ' || SQLERRM;
    END;
END $$;

COMMIT;
