-- ═══════════════════════════════════════════════════════════════════════════
-- V174 — the migration is CAPS-driven: JAMB CAPS is the applicant's data,
--        the old-portal file only confirms payment and makes the login
--
--   Best practice (the University's): the uploaded JAMB CAPS list is the main
--   record — name, programme, sex, state, LGA, UTME aggregate and subjects. The
--   old-portal migration exists only to say "this applicant applied and paid",
--   and to give them a login. So import_applicant is rebuilt to build the
--   candidate FROM the CAPS row (exactly as normal portal registration does,
--   admitted_from set), take only the email/phone from the old-portal file, and
--   confirm the application fee. A JAMB number not on the CAPS list is skipped
--   and reported — an applicant with no JAMB data is not created from a spreadsheet.
--
--   reset_migrated_applicants clears ONLY what the migration made — the migrated
--   candidate, account and application (marked by the 'Old-portal migration' fee
--   channel) — so the migration can be re-run cleanly against the CAPS list. It
--   KEEPS the CAPS rows, the O'Level results, and the passports: a passport is
--   unlinked (candidate_id set back to NULL), not deleted, so it re-attaches by
--   JAMB number when the candidate is re-created (attach_pending / link-held).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- the migration importer, rebuilt: candidate from CAPS, login + paid from the file
DROP FUNCTION IF EXISTS admissions.import_applicant(text, text, text, text, text, text, text, text, text);

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

    -- CAPS is the authoritative source: the applicant must be on the live JAMB CAPS list
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

    -- the account already exists → nothing to do (idempotent)
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
        -- the candidate FROM the CAPS row: its data is JAMB's, and admitted_from carries the demographics
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

-- ── the safe reset: clear only the migration's records, keep CAPS / O'Level / passports ──
CREATE OR REPLACE FUNCTION admissions.reset_migrated_applicants(p_session text)
RETURNS TABLE (candidates int, applications int, accounts int, passports_kept int)
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        n_cand int; n_app int; n_acc int; n_pass int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'the migration is reset by a person' USING ERRCODE = '23514'; END IF;
    IF p_session IS NULL OR btrim(p_session) = '' THEN RAISE EXCEPTION 'a reset names the session it clears' USING ERRCODE = '23514'; END IF;

    -- the migration-origin applications: marked by the 'Old-portal migration' fee channel
    CREATE TEMP TABLE _mig ON COMMIT DROP AS
        SELECT DISTINCT a.id AS app_id, a.account_id, a.candidate_id
          FROM admissions.application a
          JOIN admissions.fee_reference fr ON fr.application_id = a.id
         WHERE a.session = p_session AND fr.channel = 'Old-portal migration';

    -- preserve passports: unlink (do not delete) so they re-attach by JAMB number after re-migration
    UPDATE admissions.attachment SET candidate_id = NULL, matched_at = NULL
     WHERE candidate_id IN (SELECT candidate_id FROM _mig);
    GET DIAGNOSTICS n_pass = ROW_COUNT;

    DELETE FROM finance.gateway_event WHERE reference IN (SELECT reference FROM admissions.fee_reference WHERE application_id IN (SELECT app_id FROM _mig));
    DELETE FROM finance.gateway_attempt WHERE reference IN (SELECT reference FROM admissions.fee_reference WHERE application_id IN (SELECT app_id FROM _mig));
    DELETE FROM finance.payment_reconciliation WHERE reference IN (SELECT reference FROM admissions.fee_reference WHERE application_id IN (SELECT app_id FROM _mig));

    DELETE FROM admissions.application_document_blob
     WHERE document_id IN (SELECT id FROM admissions.application_document WHERE application_id IN (SELECT app_id FROM _mig));
    DELETE FROM admissions.application_document WHERE application_id IN (SELECT app_id FROM _mig);
    DELETE FROM admissions.clearance_document WHERE application_id IN (SELECT app_id FROM _mig);
    DELETE FROM admissions.fee_reference WHERE application_id IN (SELECT app_id FROM _mig);
    DELETE FROM admissions.applicant_event WHERE account_id IN (SELECT account_id FROM _mig);
    DELETE FROM admissions.password_reset WHERE account_id IN (SELECT account_id FROM _mig);
    DELETE FROM admissions.application WHERE id IN (SELECT app_id FROM _mig);
    GET DIAGNOSTICS n_app = ROW_COUNT;
    DELETE FROM admissions.applicant_account WHERE id IN (SELECT account_id FROM _mig);
    GET DIAGNOSTICS n_acc = ROW_COUNT;

    -- candidate_photo has a NOT NULL candidate FK; the real passport lives in attachment (kept above)
    DELETE FROM admissions.candidate_photo WHERE candidate_id IN (SELECT candidate_id FROM _mig);

    -- delete the candidate only when nothing else hangs on it (a purely migration-made candidate)
    DELETE FROM admissions.candidate c
     WHERE c.id IN (SELECT candidate_id FROM _mig)
       AND NOT EXISTS (SELECT 1 FROM admissions.application a2 WHERE a2.candidate_id = c.id)
       AND NOT EXISTS (SELECT 1 FROM admissions.applicant_account ac2 WHERE ac2.candidate_id = c.id)
       AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = c.id);
    GET DIAGNOSTICS n_cand = ROW_COUNT;

    RETURN QUERY SELECT n_cand, n_app, n_acc, n_pass;
END $$;

COMMENT ON FUNCTION admissions.reset_migrated_applicants(text) IS
'Clear only the old-portal migration''s records (marked by the Old-portal migration fee channel) for a '
'session — candidate, account, application — so the migration can be re-run against the CAPS list. Keeps '
'the CAPS rows, O''Level results and passports (a passport is unlinked, not deleted, and re-attaches by JAMB number).';

COMMIT;
