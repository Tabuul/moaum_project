-- ═══════════════════════════════════════════════════════════════════════════
-- V296 — the old-portal applicants come with their email and phone
--
--   The migration of the applicants who applied and paid on the old portal
--   (V167–V179) needed only the JAMB number: it read an email and a phone when
--   a file happened to carry them, and only for an applicant not yet migrated.
--   An applicant already on the portal was answered 'exists' and left as the
--   first run made them, so the placeholders those runs left
--   ('<jamb>@migrate.moau.local', '00000000000') could never be replaced: no
--   password reset by email and no notice by email or SMS reached them. The
--   office now holds every applicant's email and phone number:
--
--   · a cell is read as people write it — the first usable email in it (a
--     second address, "mailto:", a name in angle brackets or stray punctuation
--     set aside) and the first Nigerian mobile number (070, 080, 081, 090, 091;
--     written 0803…, 803… as a spreadsheet keeps it, +234 803…, 234803… or 2340803…,
--     with spaces or dashes, the first of several): admissions.first_email and
--     admissions.first_mobile;
--   · a new applicant is imported with them, as before;
--   · an applicant already migrated takes the file's email and phone: the
--     office's contacts replace the placeholders and whatever an earlier file
--     gave. An account the applicant opened themselves keeps the contacts they
--     chose — only a placeholder, which such an account cannot hold, is filled;
--   · an email is a way to sign in and to reset the password, so it stays on
--     one account: an address already on another applicant's account is not
--     taken (a placeholder stands in on a new account), and the row says so;
--   · every row answers what happened to it (admissions.import_applicant_row):
--     IMPORTED, UPDATED (contacts), EXISTS (nothing to change), SKIPPED or
--     ERROR — with the email and phone now on the account and, where the
--     file's could not be used, why, for the office to correct and upload
--     again. A contact changed on an existing account is noted on the
--     applicant's event log with the office that made it;
--   · admissions.migrated_contacts(session) lists every migrated applicant with
--     the contacts on the account, so the desk shows who is still without one.
--
--   admissions.import_applicant (the text answer) stays, as a wrapper, for the
--   API of the release before this one.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V296: the old-portal applicants come with their email and phone', true);

-- ── 1 · a contact cell, read as people write it ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.first_email(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT z.t
      FROM (SELECT lower(regexp_replace(regexp_replace(x, '^mailto:', '', 'i'), '[.,;:]+$', '')) AS t, ord
              FROM regexp_split_to_table(coalesce(p, ''), '[\s,;/|<>()"'']+') WITH ORDINALITY AS s(x, ord)) z
     WHERE z.t ~ '^[^\s@]+@[^\s@]+\.[a-z]{2,}$' AND z.t !~ '@migrate\.moau\.local$'
     ORDER BY z.ord
     LIMIT 1
$fn$;
COMMENT ON FUNCTION admissions.first_email(text) IS
  'The first usable email address in a cell, lower-cased (V296): a second address, mailto:, a name in angle brackets and trailing punctuation set aside; never the migration''s placeholder. NULL when there is none.';

CREATE OR REPLACE FUNCTION admissions.first_mobile(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT '0' || right(regexp_replace(r.m[1], '[^0-9]', '', 'g'), 10)
      FROM regexp_matches(coalesce(p, ''), '(?<![0-9])((?:\+?234[\s-]*0?|0)?[\s-]*[789][01](?:[\s-]*[0-9]){8})(?![0-9])', 'g') WITH ORDINALITY AS r(m, ord)
     ORDER BY r.ord
     LIMIT 1
$fn$;
COMMENT ON FUNCTION admissions.first_mobile(text) IS
  'The first Nigerian mobile number in a cell as 0XXXXXXXXXX (V296): 070, 080, 081, 090 or 091, written with or without the 0, as +234 or 234, with spaces or dashes; the first of several. NULL when there is none.';

-- ── 2 · one row of the migration file: imported, its contacts updated, or said why not ─────
CREATE OR REPLACE FUNCTION admissions.import_applicant_row(
    p_session text, p_jamb_reg_no text, p_email text, p_phone text)
RETURNS TABLE (o_outcome text, o_detail text, o_email text, o_phone text, o_email_note text, o_phone_note text)
LANGUAGE plpgsql AS $fn$
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
            v_ref := 'MOAUM-APP-' || right(v_no, 6) || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
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
END $fn$;
COMMENT ON FUNCTION admissions.import_applicant_row(text, text, text, text) IS
  'One row of the old-portal migration file (V296): a new applicant imported from the JAMB CAPS list with the file''s email and phone (a placeholder where there is none usable); an applicant already migrated given the file''s contacts; an account the applicant opened keeps theirs. IMPORTED, UPDATED, EXISTS, SKIPPED or ERROR, with the contacts on the account and why the file''s were not used.';

-- the text answer of V167–V179, for the API of the release before
CREATE OR REPLACE FUNCTION admissions.import_applicant(p_session text, p_jamb_reg_no text, p_email text, p_phone text)
RETURNS text LANGUAGE sql AS $fn$
    SELECT CASE r.o_outcome
             WHEN 'IMPORTED' THEN CASE WHEN r.o_email ~ '@migrate\.moau\.local$' AND r.o_phone = '00000000000' THEN 'imported (no contacts)'
                                       WHEN r.o_email ~ '@migrate\.moau\.local$' THEN 'imported (no email)'
                                       WHEN r.o_phone = '00000000000' THEN 'imported (no phone)'
                                       ELSE 'imported' END
             WHEN 'UPDATED' THEN 'exists'
             WHEN 'EXISTS' THEN 'exists'
             WHEN 'SKIPPED' THEN 'skip: ' || r.o_detail
             ELSE 'error: ' || coalesce(r.o_detail, 'unknown') END
      FROM admissions.import_applicant_row(p_session, p_jamb_reg_no, p_email, p_phone) r
$fn$;

-- ── 3 · who came over, and with what contacts ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.migrated_contacts(p_session text)
RETURNS TABLE (application_id uuid, jamb text, application_no text, full_name text, programme_name text,
               cur_email text, cur_phone text, has_email boolean, has_phone boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT ap.id, acc.jamb_key, ap.application_no, c.surname || ', ' || c.other_names, c.programme,
           acc.email, acc.phone, acc.email !~ '@migrate\.moau\.local$', acc.phone <> '00000000000'
      FROM admissions.application ap
      JOIN admissions.applicant_account acc ON acc.id = ap.account_id
      JOIN admissions.candidate c ON c.id = ap.candidate_id
     WHERE ap.session = p_session
       AND EXISTS (SELECT 1 FROM admissions.fee_reference fr WHERE fr.application_id = ap.id AND fr.channel = 'Old-portal migration')
$fn$;
COMMENT ON FUNCTION admissions.migrated_contacts(text) IS
  'Every applicant of a session migrated from the old portal (V296), with the email and phone on the account and whether each is real or the migration''s placeholder.';

COMMIT;
