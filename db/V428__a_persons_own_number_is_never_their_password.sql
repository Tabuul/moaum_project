-- ═══════════════════════════════════════
-- V428 — a person's own number is never their password (portal gap audit, critical)
--
--   Students signed in with their own matriculation (or admission) number as the password until they chose one: on the
--   live-shaped copy 47,916 of 48,327 student accounts still opened that way, to anyone who knew the number. Migrated applicants
--   opened with their JAMB number (12,647), and lecturers loaded from the teaching-staff list with their staff number P<PNO> (618,
--   able to enter marks). The numbers are printed on lists and documents, and the staff numbers run in sequence.
--
--   The doors now refuse a person's own number as the password (StudentAuthService, ApplicantService, AuthService), whether it
--   was granted at the door or stored as a hash. A first password is the one-hour, single-use link the portal already sends to the
--   email or phone on record ("First sign-in or forgotten password", PasswordResetService, V058/V346), or a temporary password
--   ICT Support gives at the desk (V346), or one the Registry sets — never the number itself. This migration:
--   1. retires the migration desk's "set default passwords" (iam.set_migrated_default_passwords), which wrote each student's own
--      number as their password: it now refuses, with the way in;
--   2. gives each lecturer the teaching-staff upload creates a random first password nobody knows (iam.import_lecturers).
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V428: a person''s own number is never their password', true);

-- ── 1 · the default passwords retired ──
CREATE OR REPLACE FUNCTION iam.set_migrated_default_passwords()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'iam', 'people'
AS $function$
BEGIN
    RAISE EXCEPTION 'AUTH_DEFAULT_PASSWORD_RETIRED: a student''s own number is never a password. A migrated student signs in first through the link sent to the email or phone on record (First sign-in or forgotten password), or with a temporary password ICT Support gives at the desk'
        USING ERRCODE = '23514';
END $function$;
COMMENT ON FUNCTION iam.set_migrated_default_passwords() IS
  'V122, retired by V428: once set every migrated student''s password to their own number; now refuses — the first sign-in is the reset link to the contact on record, or ICT Support''s temporary password.';

-- ── 2 · the teaching-staff upload: a random first password ──
CREATE OR REPLACE FUNCTION iam.import_lecturers(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, existing integer, credentialed integer, granted integer, records integer, no_department integer, skipped integer, first_error text, missing_departments text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    r jsonb;
    v_pno text; v_staff text; v_full text; v_clean text; v_parts text[];
    v_surname text; v_given text; v_sex text; v_rank text; v_phone text; v_email text;
    v_deptin text; v_dept text; v_date date; v_conuass int; v_pid uuid;
    n int := 0; c_created int := 0; c_exist int := 0; c_cred int := 0; c_grant int := 0; c_rec int := 0;
    c_nodept int := 0; c_skip int := 0; v_err text := NULL; v_missing text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'lecturers are loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'the file is rows: PNO, full names, sex, date of first appointment, department, rank' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        -- PNO → staff number 'P' + digits
        v_pno := btrim(coalesce(r->>'pno', r->>'PNO', r->>'staff_number', r->>'staffNumber', r->>'staffno', ''));
        v_pno := regexp_replace(v_pno, '[^0-9]', '', 'g');    -- keep the digits only
        CONTINUE WHEN v_pno = '';                              -- blank line or header
        v_full := btrim(coalesce(r->>'full_names', r->>'fullNames', r->>'name', r->>'names', r->>'fullname', ''));
        CONTINUE WHEN v_full = '' OR v_full ~* '^(full\s*names?|names?)$';
        n := n + 1;
        v_staff := 'P' || v_pno;

        -- split the name: strip a leading run of titles, surname = last word, given = the rest
        v_clean := btrim(regexp_replace(v_full,
            '^((PROF|PROFESSOR|ASSOC|ASSOCIATE|DR|MR|MRS|MISS|MS|ENGR|ENGINEER|REV|REVD|REVEREND|BARR|ARC|ARCH|SIR|CHIEF|PASTOR|VEN|VENERABLE|ALHAJI|HAJIA)\.?\s+)+',
            '', 'i'));
        v_clean := btrim(regexp_replace(v_clean, '\s+', ' ', 'g'));
        IF v_clean = '' THEN v_clean := v_full; END IF;
        v_parts := string_to_array(v_clean, ' ');
        IF array_length(v_parts, 1) = 1 THEN
            v_surname := v_parts[1]; v_given := v_parts[1];
        ELSE
            v_surname := v_parts[array_upper(v_parts, 1)];
            v_given := array_to_string(v_parts[1:array_upper(v_parts, 1) - 1], ' ');
        END IF;

        v_deptin := btrim(coalesce(r->>'department', r->>'dept', r->>'departmentName', r->>'department_code', ''));
        -- match a department by code, or by name tolerant of case / spacing / & vs AND
        SELECT d.code INTO v_dept FROM ref.department d
         WHERE d.ended_on IS NULL
           AND ( upper(d.code) = upper(v_deptin)
              OR regexp_replace(replace(upper(d.name), '&', 'AND'), '[^A-Z0-9]', '', 'g')
               = regexp_replace(replace(upper(v_deptin), '&', 'AND'), '[^A-Z0-9]', '', 'g') )
         LIMIT 1;
        IF v_dept IS NULL THEN
            c_nodept := c_nodept + 1;
            IF NOT (upper(v_deptin) = ANY(SELECT upper(x) FROM unnest(v_missing) x)) AND v_deptin <> '' THEN
                v_missing := v_missing || v_deptin;
            END IF;
            IF v_err IS NULL THEN v_err := 'Row ' || n || ' (' || v_staff || '): no department matching ' || coalesce(nullif(v_deptin, ''), '(blank)'); END IF;
            CONTINUE;
        END IF;

        v_sex := upper(left(nullif(btrim(coalesce(r->>'sex', '')), ''), 1));
        IF v_sex NOT IN ('M', 'F') THEN v_sex := NULL; END IF;
        v_rank := nullif(btrim(coalesce(r->>'rank', r->>'present_rank', r->>'presentRank', r->>'presentrank', '')), '');
        v_phone := nullif(btrim(coalesce(r->>'phone', r->>'phone_no', r->>'phoneNo', r->>'phone_number', '')), '');
        v_email := nullif(btrim(coalesce(r->>'email', '')), '');
        v_conuass := nullif(regexp_replace(coalesce(r->>'conuass', r->>'connuas', r->>'conuas', r->>'conuass_step', ''), '[^0-9]', '', 'g'), '')::int;
        v_date := NULL;
        BEGIN
            v_date := to_date(nullif(btrim(coalesce(r->>'date_first_appointment', r->>'date_of_1st_appt', r->>'dateOf1stAppt',
                       r->>'date_first_appt', r->>'first_appointment', r->>'appointment', '')), ''), 'DD/MM/YYYY');
        EXCEPTION WHEN OTHERS THEN v_date := NULL; END;

        BEGIN
            -- 1. the person, by staff number
            SELECT id INTO v_pid FROM iam.person WHERE staff_number = v_staff;
            IF v_pid IS NULL THEN
                v_pid := gen_random_uuid();
                INSERT INTO iam.person (id, staff_number, surname, given_names, email, phone)
                VALUES (v_pid, v_staff, v_surname, v_given, v_email, v_phone);
                c_created := c_created + 1;
            ELSE
                c_exist := c_exist + 1;
                UPDATE iam.person
                   SET email = coalesce(email, v_email), phone = coalesce(phone, v_phone)
                 WHERE id = v_pid AND (email IS NULL OR phone IS NULL);
            END IF;

            -- 2. the sign-in — the username is the staff number; the first password is random and nobody knows it (V428: a person's own
            --    number is never a password). The lecturer signs in first through the reset link sent to the email or phone on record
            --    ("Forgot password"), or with a first password the Registry gives on Users & roles. Never reset on re-upload.
            IF NOT EXISTS (SELECT 1 FROM iam.credential WHERE person_id = v_pid) THEN
                INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by)
                VALUES (v_pid, lower(v_staff), crypt(gen_random_uuid()::text || gen_random_uuid()::text, gen_salt('bf', 12)), true, v_actor);
                INSERT INTO iam.credential_event (id, person_id, kind, by_person, note)
                VALUES (gen_random_uuid(), v_pid, 'SET', v_actor, 'Bulk teaching-staff upload');
                c_cred := c_cred + 1;
            END IF;

            -- 3. the lecturer office, scoped to the home department
            IF NOT EXISTS (SELECT 1 FROM iam.office_assignment
                            WHERE person_id = v_pid AND office_code = 'lecturer'
                              AND scope_kind = 'department' AND scope_id = v_dept AND valid_to IS NULL) THEN
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), v_pid, 'lecturer', 'department', v_dept,
                        'Teaching-staff upload (Users & roles)', v_actor, coalesce(v_date, current_date));
                c_grant := c_grant + 1;
            END IF;

            -- 4. the establishment record (sex, first appointment, rank, CONUASS, home department)
            INSERT INTO hrm.staff_record (person_id, pno, sex, date_first_appointment, present_rank, conuass_step, home_department)
            VALUES (v_pid, v_pno, v_sex, v_date, v_rank, v_conuass, v_dept)
            ON CONFLICT (person_id) DO UPDATE SET
                pno = excluded.pno,
                sex = coalesce(excluded.sex, hrm.staff_record.sex),
                date_first_appointment = coalesce(excluded.date_first_appointment, hrm.staff_record.date_first_appointment),
                present_rank = coalesce(excluded.present_rank, hrm.staff_record.present_rank),
                conuass_step = coalesce(excluded.conuass_step, hrm.staff_record.conuass_step),
                home_department = excluded.home_department,
                updated_at = now();
            c_rec := c_rec + 1;
        EXCEPTION WHEN OTHERS THEN
            c_skip := c_skip + 1;
            IF v_err IS NULL THEN v_err := 'Row ' || n || ' (' || v_staff || '): ' || SQLERRM; END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT n, c_created, c_exist, c_cred, c_grant, c_rec, c_nodept, c_skip, v_err,
                        nullif(array_to_string(v_missing, ', '), '');
END $function$;

COMMIT;
