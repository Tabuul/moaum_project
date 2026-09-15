-- ═══════════════════════════════════════════════════════════════════════════
-- V137 — lecturer import for the real "List of teaching staff" sheet
--
--   The sheet's columns: PNO, FULL NAMES, SEX, DATE OF 1ST APPT, DEPARTMENT,
--   PRESENT RANK, PHONE NO, CONUASS. This reworks iam.import_lecturers to carry
--   them and adds hrm.staff_record to hold the establishment facts iam.person
--   does not (sex, first-appointment date, present rank, CONUASS step).
--
--   Identity: PNO is the personnel/staff number. It is stored as 'P' + the
--   number (29 → P29) and is BOTH the username and the first password (must be
--   changed on first sign-in). Username is lower-cased ('p29') to satisfy the
--   credential check; the one-door sign-in lower-cases what is typed, so P29
--   and p29 both work, with the password P29.
--
--   Department: matched by NAME (or code), tolerant of case, spacing and & / AND
--   ("Arts & Social Sciences Education" = "ARTS AND SOCIAL SCIENCES EDUCATION").
--   The lecturer gets the lecturer office scoped to that department's CODE — the
--   home department. Teaching another department's course does NOT need a second
--   home: the department assigns its course to the lecturer (teaching
--   allocation), and the lecturer's one dashboard shows every course assigned to
--   them, from any department, for score entry. A department that is not on the
--   register is reported back (missing_departments) so it can be created first.
--
--   Resilient (per-row savepoint) and idempotent (existing person/credential/
--   grant kept; a password already set is never reset). Runs as the caller in
--   the request's audit context; bcrypt cost 12.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- establishment facts from the teaching-staff sheet that iam.person has no room for
CREATE TABLE IF NOT EXISTS hrm.staff_record (
    person_id              uuid PRIMARY KEY REFERENCES iam.person(id) ON DELETE CASCADE,
    pno                    text NULL,               -- the personnel number as given (e.g. '29')
    sex                    text NULL,
    date_first_appointment date NULL,
    present_rank           text NULL,               -- PROFESSOR, SENIOR LECTURER, …
    conuass_step           int  NULL,               -- CONUASS grade/step (e.g. 7)
    home_department        text NULL,               -- ref.department.code
    updated_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_staffrec_sex CHECK (sex IS NULL OR sex IN ('M', 'F'))
);

DO $attach$ BEGIN
    PERFORM audit.attach('hrm.staff_record');
EXCEPTION WHEN OTHERS THEN NULL;   -- attach is idempotent-ish; ignore if already attached
END $attach$;

-- V135 returned 7 columns; this returns 10. Changing a function's OUT columns is a
-- change of return type, which CREATE OR REPLACE cannot do, so drop it first.
DROP FUNCTION IF EXISTS iam.import_lecturers(jsonb);

CREATE OR REPLACE FUNCTION iam.import_lecturers(p_rows jsonb)
RETURNS TABLE (rows int, created int, existing int, credentialed int, granted int,
               records int, no_department int, skipped int, first_error text, missing_departments text)
LANGUAGE plpgsql AS $$
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

            -- 2. the sign-in — username & first password are the staff number (P29); never reset on re-upload
            IF NOT EXISTS (SELECT 1 FROM iam.credential WHERE person_id = v_pid) THEN
                INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by)
                VALUES (v_pid, lower(v_staff), crypt(v_staff, gen_salt('bf', 12)), true, v_actor);
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
END $$;

COMMENT ON FUNCTION iam.import_lecturers(jsonb) IS
  'Bulk-onboard teaching staff from the List of teaching staff sheet: person + '
  'sign-in (username/first password = P<PNO>) + lecturer office scoped to the '
  'home department + hrm.staff_record (sex, first appointment, rank, CONUASS). '
  'Cross-department teaching is by course allocation, not a second home. '
  'Resilient and idempotent; reports departments not on the register.';

COMMIT;
