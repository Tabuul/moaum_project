-- ═══════════════════════════════════════
-- V395 — a student's payment reference is drawn until a free one is found
--
--   A student's reference reads MOAUM-FEE-<the last seven characters of the matriculation or admission number>-<four random
--   digits>, unique across finance.payment_reference. Students whose numbers end alike share the first part, and one draw in
--   ten thousand repeated a reference already taken: the student met a unique-key failure instead of a reference, and the
--   property suite met it too (CI's Database job failed on a175cd16 and ee07dc31 at the V367 GST refund property, and passed
--   on the run between). V390 fixed the same draw for an applicant's reference; this does it for the student's, in both
--   generators — finance.new_reference (school fees) and finance.new_purpose_reference (GST/EPS and every other purpose):
--   the reference is inserted ON CONFLICT DO NOTHING and drawn again when taken, up to fifty times. The old-portal applicant
--   import (admissions.import_applicant_row) draws its application-fee reference until free as well; there a taken reference
--   was caught by the row's unique_violation handler and the applicant skipped as already migrated.
--   The format, the amounts, the windows and every refusal stand; nothing else in the three functions changes.
--   jupeb.import_old_portal_payments is left as it is: it keeps the old portal's own reference and adds random digits only
--   when that reference was imported before, so it clashes only on a third copy of the same old reference.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V395: student fee references drawn until free', true);

CREATE OR REPLACE FUNCTION finance.new_reference(p_student uuid, p_session text, p_amount numeric, p_purpose text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE pos record; v_ref text; v_matric text; win record;
BEGIN
    -- school fees wait for a successful online screening where the session requires one (V269)
    PERFORM admissions.screening_refuse_student(p_student, 'SCHOOL FEES');
    -- the portal's school-fees window (V288): a new reference is generated only while it is open; one already generated is paid and verified as before
    SELECT * INTO win FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL);
    IF win.state <> 'OPEN' THEN
        RAISE EXCEPTION 'SCHOOL_FEES_PAYMENT_CLOSED: school fees payment is currently % for %', lower(win.state), p_session USING ERRCODE = '23514',
            HINT = CASE WHEN win.state = 'SCHEDULED' THEN 'It opens on ' || to_char(win.opens_at AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.' ELSE 'The Directorate of ICT opens the payment window.' END;
    END IF;
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    IF pos.due = 0 THEN
        RAISE EXCEPTION 'no charge is stated for % yet', p_session USING ERRCODE = '23514',
            HINT = 'The Bursar states the session''s fee schedule before anything is paid against it.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'a payment is for an amount' USING ERRCODE = '23514';
    END IF;
    IF p_amount > pos.balance THEN
        RAISE EXCEPTION 'the amount % is more than the balance of %', p_amount, pos.balance USING ERRCODE = '23514',
            HINT = 'Pay the balance, or part of it; nothing is taken beyond what is owed.';
    END IF;
    SELECT coalesce(matric_no, admission_no, 'X') INTO v_matric FROM people.student WHERE id = p_student;
    -- V395: the four random digits may repeat a reference another student drew (students whose numbers end alike share the
    -- first part); a taken reference is drawn again, never answered as a clash
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
        VALUES (p_student, p_session, v_ref, coalesce(p_purpose, 'School fees ' || p_session), p_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free payment reference was found for % in fifty draws', v_matric USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, the Directorate of ICT widens the reference.';
END $function$;

CREATE OR REPLACE FUNCTION finance.new_purpose_reference(p_student uuid, p_session text, p_amount numeric, p_purpose text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_ref text; v_matric text;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'a payment is for an amount' USING ERRCODE = '23514'; END IF;
    SELECT coalesce(matric_no, admission_no, 'X') INTO v_matric FROM people.student WHERE id = p_student;
    -- V395: drawn again when taken, as finance.new_reference
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
        VALUES (p_student, p_session, v_ref, p_purpose, p_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free payment reference was found for % in fifty draws', v_matric USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, the Directorate of ICT widens the reference.';
END $function$;

CREATE OR REPLACE FUNCTION admissions.import_applicant_row(p_session text, p_jamb_reg_no text, p_email text, p_phone text)
 RETURNS TABLE(o_outcome text, o_detail text, o_email text, o_phone text, o_email_note text, o_phone_note text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    key         text := upper(btrim(coalesce(p_jamb_reg_no, '')));
    raw_email   text := btrim(coalesce(p_email, ''));
    raw_phone   text := btrim(coalesce(p_phone, ''));
    f_email     text := admissions.first_email(p_email);
    f_phone     text := admissions.first_mobile(p_phone);
    ph_email    text;
    ph_phone    constant text := '00000000000';
    e_note      text;
    p_note      text;
    acc         record;
    n_email     text;
    n_phone     text;
    changed     text[] := ARRAY[]::text[];
    caps        record;
    prog        text;
    lvl         int;
    v_candidate uuid;
    v_account   uuid;
    v_app       uuid;
    v_no        text;
    v_yy        text := substr(p_session, 3, 2);
    v_ref       text;
    v_rct       text;
    fee         record;
    v_amount    numeric;
    v_con       text;
BEGIN
    IF admissions.acting_person() IS NULL THEN
        RAISE EXCEPTION 'an import is made by a person' USING ERRCODE = '23514';
    END IF;
    IF key !~ '^[0-9]{6,}[A-Z]{0,3}$' THEN
        RETURN QUERY SELECT 'SKIPPED'::text, 'bad JAMB number'::text, NULL::text, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;
    ph_email := lower(key) || '@migrate.moau.local';
    -- the file's contacts, where they cannot be used, and why
    e_note := CASE WHEN raw_email = '' THEN 'no email in the file'
                   WHEN f_email IS NULL THEN 'not a usable email address: ' || left(raw_email, 80) END;
    p_note := CASE WHEN raw_phone = '' THEN 'no phone number in the file'
                   WHEN f_phone IS NULL THEN 'not a Nigerian mobile number: ' || left(raw_phone, 40) END;

    -- ── already on the portal ──
    SELECT a.id, a.email, a.phone,
           EXISTS (SELECT 1 FROM admissions.application ap JOIN admissions.fee_reference fr ON fr.application_id = ap.id
                    WHERE ap.account_id = a.id AND fr.channel = 'Old-portal migration') AS migrated
      INTO acc
      FROM admissions.applicant_account a
     WHERE a.session = p_session AND a.jamb_key = key;
    IF acc.id IS NOT NULL THEN
        n_email := acc.email;
        n_phone := acc.phone;
        IF f_email IS NOT NULL AND f_email <> lower(acc.email) THEN
            IF NOT acc.migrated AND acc.email !~ '@migrate\.moau\.local$' THEN
                e_note := 'kept the email the applicant chose: ' || acc.email;
            ELSIF EXISTS (SELECT 1 FROM admissions.applicant_account x WHERE lower(x.email) = f_email AND x.id <> acc.id) THEN
                e_note := 'already on another applicant''s account: ' || f_email;
            ELSE
                n_email := f_email;
                changed := changed || 'email'::text;
            END IF;
        END IF;
        IF f_phone IS NOT NULL AND f_phone <> acc.phone THEN
            IF NOT acc.migrated AND acc.phone <> ph_phone THEN
                p_note := 'kept the phone number the applicant chose: ' || acc.phone;
            ELSE
                n_phone := f_phone;
                changed := changed || 'phone'::text;
            END IF;
        END IF;
        -- a contact missing from the file matters only while the account still waits for one
        IF e_note = 'no email in the file' AND n_email !~ '@migrate\.moau\.local$' THEN e_note := NULL; END IF;
        IF p_note = 'no phone number in the file' AND n_phone <> ph_phone THEN p_note := NULL; END IF;
        IF cardinality(changed) > 0 THEN
            BEGIN
                UPDATE admissions.applicant_account SET email = n_email, phone = n_phone WHERE id = acc.id;
            EXCEPTION WHEN unique_violation THEN
                -- the address went to another account a moment ago: the phone still goes on
                n_email := acc.email;
                e_note := 'already on another applicant''s account: ' || f_email;
                changed := array_remove(changed, 'email');
                IF cardinality(changed) > 0 THEN
                    UPDATE admissions.applicant_account SET phone = n_phone WHERE id = acc.id;
                END IF;
            END;
        END IF;
        IF cardinality(changed) > 0 THEN
            INSERT INTO admissions.applicant_event (account_id, identifier, outcome, ip)
            VALUES (acc.id, key, 'CONTACTS_UPDATED (' || array_to_string(changed, ', ') || ') from the old-portal migration file by '
                                 || coalesce(current_setting('moaum.actor_office', true), 'an office') || ' ' || admissions.acting_person()::text, NULL);
            RETURN QUERY SELECT 'UPDATED'::text, array_to_string(changed, ' and ') || ' updated', n_email, n_phone, e_note, p_note;
        ELSE
            RETURN QUERY SELECT 'EXISTS'::text, NULL::text, n_email, n_phone, e_note, p_note;
        END IF;
        RETURN;
    END IF;

    -- ── a new applicant: verified on the JAMB CAPS list, which gives the name, programme and UTME ──
    SELECT r.id, r.surname, r.other_names, r.jamb_code, r.entry_mode
      INTO caps
      FROM admissions.caps_row_live r
     WHERE r.session = p_session AND r.jamb_key = key
     LIMIT 1;
    IF caps.id IS NULL THEN
        RETURN QUERY SELECT 'SKIPPED'::text, 'not on the JAMB CAPS list'::text, NULL::text, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;
    n_email := coalesce(f_email, ph_email);
    n_phone := coalesce(f_phone, ph_phone);
    IF f_email IS NOT NULL AND EXISTS (SELECT 1 FROM admissions.applicant_account x WHERE lower(x.email) = f_email) THEN
        e_note := 'already on another applicant''s account: ' || f_email;
        n_email := ph_email;
    END IF;
    IF n_email = ph_email AND EXISTS (SELECT 1 FROM admissions.applicant_account x WHERE lower(x.email) = ph_email) THEN
        RETURN QUERY SELECT 'SKIPPED'::text, 'duplicate account'::text, NULL::text, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;

    prog := coalesce((SELECT p.name FROM ref.programme p WHERE upper(p.code) = upper(caps.jamb_code) ORDER BY p.archived, p.code LIMIT 1),
                     caps.jamb_code);
    lvl  := CASE WHEN caps.entry_mode = 'UTME' THEN 100 ELSE 200 END;

    FOR attempt IN 1..2 LOOP
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
            VALUES (v_account, p_session, v_candidate, key, n_email, n_phone, 'SET_ON_FIRST_LOGIN');

            v_app := gen_random_uuid();
            v_no  := 'APP/' || v_yy || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', p_session)::text, 6, '0');
            INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at)
            VALUES (v_app, v_account, v_candidate, p_session, v_no, now(), now());

            SELECT * INTO fee FROM admissions.applicant_fee_rule(p_session);
            v_amount := fee.application_fee + fee.portal_charge;
            -- V395: drawn until free — a taken reference raised unique_violation, which the handler below reads as the applicant
            -- already migrated, and the row was skipped as a duplicate it was not
            FOR v_try IN 1..50 LOOP
                v_ref := 'MOAUM-APP-' || right(v_no, 6) || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
                EXIT WHEN NOT EXISTS (SELECT 1 FROM admissions.fee_reference r WHERE r.reference = v_ref);
            END LOOP;
            v_rct := 'RCT-' || left(p_session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', p_session)::text, 5, '0');
            INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at, confirmed_at, confirmed_by, channel, note, receipt_no)
            VALUES (gen_random_uuid(), v_app, 'APPLICATION', v_ref, v_amount, now(), now(), admissions.acting_person(),
                    'Old-portal migration', 'Migrated: applied and paid on the previous portal', v_rct);

            RETURN QUERY SELECT 'IMPORTED'::text, NULL::text, n_email, n_phone, e_note, p_note;
            RETURN;
        EXCEPTION
            WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
                IF v_con = 'uq_applicant_email' AND n_email <> ph_email AND attempt = 1 THEN
                    -- the address went to another account a moment ago: the applicant comes over on the placeholder
                    e_note := 'already on another applicant''s account: ' || n_email;
                    n_email := ph_email;
                ELSE
                    RETURN QUERY SELECT 'EXISTS'::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text;
                    RETURN;
                END IF;
            WHEN OTHERS THEN
                RETURN QUERY SELECT 'ERROR'::text, SQLERRM::text, NULL::text, NULL::text, NULL::text, NULL::text;
                RETURN;
        END;
    END LOOP;
    RETURN QUERY SELECT 'EXISTS'::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text;
END $function$;

COMMENT ON FUNCTION finance.new_reference(uuid, text, numeric, text) IS
    'A student''s school-fee payment reference (V027, V269, V288): MOAUM-FEE, the end of the student''s number and four random digits, drawn again when the reference is already taken (V395)';
COMMENT ON FUNCTION finance.new_purpose_reference(uuid, text, numeric, text) IS
    'A student''s payment reference for a purpose other than school fees (V027) — the GST/EPS fee among them: drawn again when the reference is already taken (V395)';

COMMIT;
