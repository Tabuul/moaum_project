-- ═══════════════════════════════════════════════════════════
-- V744 — a staff number is one person whatever its case
--
--   The University's word of 12 November 2026: "fix the duplicate staff number issue". The Chief Security Officer's desk could not
--   issue a staff identity card to P2016: the portal held two people under that number, `p2016` (the account the portal was opened
--   with, its offices and sign-in) and `P2016` (the same officer, made a second time when the HR register of non-teaching staff was
--   uploaded). Every desk and the sign-on look a staff number up without regard to case and expected one person, so the card desk
--   failed (and the University's sign-on, given that number, would have failed the same way).
--
--   What stood: iam.person.staff_number unique as typed (person_staff_number_key), so `p2016` and `P2016` were two numbers to the
--   database and one to every reader; the two uploads (iam.import_staff, V253, and iam.import_lecturers, V428) found an existing
--   person by the number as typed, so a register writing P2016 never found the account written p2016 and made a second person.
--   HR's appointment (hrm.appointment_check, V510) already compared without case.
--
--   1 · iam.merge_staff_number_duplicates(): the people whose staff numbers differ only by case or spaces are made one. The person
--       kept is the one who signs in (a credential), else the one holding offices, else the one on the HR register, else the first.
--       Everything that points at the other — every column with a foreign key to iam.person — is moved to the person kept, row by
--       row; where the person kept already has the one row a person may have (a sign-in, an HR record, a photograph…), that row
--       stands, and the HR record alone is merged: the other record's particulars fill what the kept one lacks. The kept person's
--       e-mail and phone are filled the same way and the number is written in capitals, as every other staff number on the portal
--       is. The other person is then deleted, or, where something still points at them that could not be moved, closed (ended,
--       with the reason) and their number cleared. Each merge is written once to iam.person_merge, with what moved and what stayed.
--   2 · Run now. On the copy of the live database of late October one number is shared: P2016 (Okpali), merged into the account.
--   3 · A staff number is one person whatever its case: a unique index on upper(staff_number), and no number with spaces around it
--       or blank. A number typed again in another case is refused (409 ALREADY_EXISTS on the API) instead of becoming a second
--       person, and every lookup by number (the card desk, the sign-on, the library, attendance, appraisal, movement) finds one.
--   4 · The two uploads find an existing person by the number whatever its case (the rest of each function as it stood).
-- ═══════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V744: a staff number is one person whatever its case', true);

-- ── 1 · the merge, and its record ───────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE iam.person_merge (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_number  text NOT NULL,
    kept_id       uuid NOT NULL REFERENCES iam.person (id) ON DELETE CASCADE,
    merged_id     uuid NOT NULL,          -- no foreign key: the person merged is usually deleted
    merged_name   text NOT NULL,
    merged_number text NOT NULL,
    outcome       text NOT NULL CHECK (outcome IN ('DELETED', 'CLOSED')),
    moved         int  NOT NULL DEFAULT 0 CHECK (moved >= 0),
    stayed        jsonb NOT NULL DEFAULT '{}'::jsonb,
    merged_at     timestamptz NOT NULL DEFAULT now(),
    merged_by     uuid,
    reason        text NOT NULL
);
COMMENT ON TABLE iam.person_merge IS
  'V744: one row for each person merged into another because their staff numbers differed only by case or spaces — who was kept, who was merged (their name and number as they stood), how many rows moved across, what stayed with the person merged (by table) and whether that person was deleted or closed';

CREATE FUNCTION iam.merge_staff_number_duplicates()
RETURNS TABLE (staff_number text, kept_id uuid, merged_id uuid, outcome text, moved int, stayed jsonb)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
    g record; dup record; fk record; rw record;
    v_keep uuid; v_moved int; v_stayed jsonb; v_left int; v_n int; v_outcome text; v_number text;
    v_reason text := coalesce(nullif(current_setting('moaum.reason', true), ''), 'V744: the same person under one staff number');
BEGIN
    FOR g IN
        SELECT upper(btrim(p.staff_number)) AS k
          FROM iam.person p
         WHERE nullif(btrim(p.staff_number), '') IS NOT NULL
         GROUP BY 1 HAVING count(*) > 1
         ORDER BY 1
    LOOP
        -- the person kept: who signs in, else who holds offices, else who is on the HR register, else the first
        SELECT p.id INTO v_keep
          FROM iam.person p
         WHERE upper(btrim(p.staff_number)) = g.k
         ORDER BY EXISTS (SELECT 1 FROM iam.credential c WHERE c.person_id = p.id) DESC,
                  (SELECT count(*) FROM iam.office_assignment o WHERE o.person_id = p.id) DESC,
                  EXISTS (SELECT 1 FROM hrm.staff_record s WHERE s.person_id = p.id) DESC,
                  (p.ended_on IS NULL) DESC,
                  p.staff_number = upper(btrim(p.staff_number)) DESC,
                  p.id
         LIMIT 1;

        FOR dup IN SELECT p.* FROM iam.person p WHERE upper(btrim(p.staff_number)) = g.k AND p.id <> v_keep ORDER BY p.id LOOP
            v_moved := 0; v_stayed := '{}'::jsonb;

            -- the HR record: the other's particulars fill what the kept one lacks (the kept one's stand)
            IF EXISTS (SELECT 1 FROM hrm.staff_record s WHERE s.person_id = v_keep)
               AND EXISTS (SELECT 1 FROM hrm.staff_record s WHERE s.person_id = dup.id) THEN
                UPDATE hrm.staff_record k SET
                    pno = coalesce(k.pno, d.pno), sex = coalesce(k.sex, d.sex),
                    date_first_appointment = coalesce(k.date_first_appointment, d.date_first_appointment),
                    present_rank = coalesce(k.present_rank, d.present_rank), conuass_step = coalesce(k.conuass_step, d.conuass_step),
                    home_department = coalesce(k.home_department, d.home_department), category = coalesce(k.category, d.category),
                    salary_scale = coalesce(k.salary_scale, d.salary_scale), contiss_step = coalesce(k.contiss_step, d.contiss_step),
                    home_unit = coalesce(k.home_unit, d.home_unit), home_faculty = coalesce(k.home_faculty, d.home_faculty),
                    unit_as_given = coalesce(k.unit_as_given, d.unit_as_given), updated_at = now()
                  FROM hrm.staff_record d
                 WHERE k.person_id = v_keep AND d.person_id = dup.id;
                DELETE FROM hrm.staff_record WHERE person_id = dup.id;
                v_moved := v_moved + 1;
            END IF;

            -- every row that points at the other person, moved row by row; a row the kept person already has its own of stays
            FOR fk IN
                SELECT c.conrelid::regclass AS tbl, a.attname AS col
                  FROM pg_constraint c
                  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
                 WHERE c.contype = 'f' AND c.confrelid = 'iam.person'::regclass AND array_length(c.conkey, 1) = 1
                   AND c.conrelid <> 'iam.person_merge'::regclass
                 ORDER BY 1, 2
            LOOP
                v_left := 0;
                FOR rw IN EXECUTE format('SELECT ctid AS t FROM %s WHERE %I = $1', fk.tbl, fk.col) USING dup.id LOOP
                    BEGIN
                        EXECUTE format('UPDATE %s SET %I = $1 WHERE ctid = $2', fk.tbl, fk.col) USING v_keep, rw.t;
                        v_moved := v_moved + 1;
                    EXCEPTION WHEN OTHERS THEN
                        v_left := v_left + 1;
                    END;
                END LOOP;
                IF v_left > 0 THEN v_stayed := v_stayed || jsonb_build_object(fk.tbl::text || '.' || fk.col, v_left); END IF;
            END LOOP;

            -- the kept person's e-mail and phone filled from the other's
            UPDATE iam.person SET email = coalesce(email, dup.email), phone = coalesce(phone, dup.phone)
             WHERE id = v_keep AND (email IS NULL AND dup.email IS NOT NULL OR phone IS NULL AND dup.phone IS NOT NULL);

            -- the other person: deleted when nothing points at them any more, else closed with their number cleared
            v_outcome := 'DELETED';
            IF v_stayed = '{}'::jsonb THEN
                BEGIN
                    DELETE FROM iam.person WHERE id = dup.id;
                EXCEPTION WHEN OTHERS THEN
                    v_outcome := 'CLOSED';
                END;
            ELSE
                v_outcome := 'CLOSED';
            END IF;
            IF v_outcome = 'CLOSED' THEN
                SELECT p.staff_number INTO v_number FROM iam.person p WHERE p.id = v_keep;
                UPDATE iam.person
                   SET staff_number = NULL,
                       ended_on = coalesce(ended_on, current_date),
                       ended_reason = 'The same person as ' || upper(btrim(v_number)) || ', merged into that record (V744)'
                                      || coalesce('; before: ' || ended_reason, '')
                 WHERE id = dup.id;
            END IF;

            INSERT INTO iam.person_merge (staff_number, kept_id, merged_id, merged_name, merged_number, outcome, moved, stayed, merged_by, reason)
            VALUES (g.k, v_keep, dup.id, dup.surname || ', ' || dup.given_names, dup.staff_number, v_outcome, v_moved, v_stayed,
                    nullif(current_setting('moaum.actor_id', true), '')::uuid, v_reason);

            staff_number := g.k; kept_id := v_keep; merged_id := dup.id; outcome := v_outcome; moved := v_moved; stayed := v_stayed;
            RETURN NEXT;
        END LOOP;

        -- the number kept in capitals, as every other staff number on the portal is written
        UPDATE iam.person SET staff_number = g.k WHERE id = v_keep AND staff_number IS DISTINCT FROM g.k;
    END LOOP;
END $$;
COMMENT ON FUNCTION iam.merge_staff_number_duplicates() IS
  'V744: makes one person of the people whose staff numbers differ only by case or spaces (the one who signs in kept; every row pointing at the other moved across where the kept person has not their own; the HR record merged; the other deleted, or closed with the number cleared); records each merge in iam.person_merge and returns them';

-- ── 2 · run now ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT * FROM iam.merge_staff_number_duplicates() LOOP
        n := n + 1;
        RAISE NOTICE 'V744: % — % merged into % (%; % rows moved; stayed: %)', r.staff_number, r.merged_id, r.kept_id, r.outcome, r.moved, r.stayed;
    END LOOP;
    RAISE NOTICE 'V744: % people merged into the person who shares their staff number', n;
END $$;

-- ── 3 · one person a staff number, whatever its case ────────────────────────────────────────────────────────────────────────
UPDATE iam.person SET staff_number = NULL WHERE staff_number IS NOT NULL AND btrim(staff_number) = '';
UPDATE iam.person SET staff_number = btrim(staff_number) WHERE staff_number <> btrim(staff_number);
CREATE UNIQUE INDEX person_staff_number_any_case ON iam.person (upper(staff_number));
ALTER TABLE iam.person ADD CONSTRAINT ck_person_staff_number_trimmed
    CHECK (staff_number IS NULL OR (staff_number = btrim(staff_number) AND staff_number <> ''));
COMMENT ON INDEX iam.person_staff_number_any_case IS
  'V744: a staff number is one person whatever its case — P2016 and p2016 are one number, as every lookup by staff number reads them';

-- ── 4 · the two uploads find an existing person whatever the case of the number ─────────────────────────────────────────────

-- iam.import_staff (V253): the non-teaching staff register, as it stood, but for the lookup
CREATE OR REPLACE FUNCTION iam.import_staff(p_rows jsonb, p_dry_run boolean DEFAULT false)
 RETURNS TABLE(rows integer, created integer, existing integer, records integer, unplaced integer, skipped integer, first_error text, unplaced_units text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    r jsonb;
    v_pno text; v_staff text; v_full text; v_clean text; v_parts text[];
    v_surname text; v_given text; v_sex text; v_rank text; v_phone text; v_email text;
    v_unitin text; v_unit text; v_dept text; v_fac text; v_date date; v_scale text; v_step int; v_stepin text; v_pid uuid;
    n int := 0; c_created int := 0; c_exist int := 0; c_rec int := 0; c_unplaced int := 0; c_skip int := 0;
    v_err text := NULL; v_missing text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'staff are loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'the file is rows: PNO, full names, sex, date of first appointment, department or unit, present rank, phone, CONTISS' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_pno := regexp_replace(btrim(coalesce(r->>'pno', r->>'PNO', r->>'staff_number', r->>'staffNumber', '')), '[^0-9]', '', 'g');
        CONTINUE WHEN v_pno = '';
        v_full := btrim(coalesce(r->>'full_names', r->>'fullNames', r->>'name', r->>'names', ''));
        CONTINUE WHEN v_full = '' OR v_full ~* '^(full\s*names?|names?)$';
        n := n + 1;
        v_staff := 'P' || v_pno;

        v_clean := btrim(regexp_replace(v_full,
            '^((PROF|PROFESSOR|ASSOC|ASSOCIATE|DR|MR|MRS|MISS|MS|ENGR|ENGINEER|REV|REVD|REVEREND|BARR|ARC|ARCH|SIR|CHIEF|PASTOR|VEN|VENERABLE|ALHAJI|HAJIA|COMRADE)\.?\s+)+', '', 'i'));
        v_clean := btrim(regexp_replace(v_clean, '\s+', ' ', 'g'));
        IF v_clean = '' THEN v_clean := v_full; END IF;
        v_parts := string_to_array(v_clean, ' ');
        IF array_length(v_parts, 1) = 1 THEN
            v_surname := v_parts[1]; v_given := v_parts[1];
        ELSE
            -- as the teaching-staff upload reads it: the surname is the last word, the given names the rest
            v_surname := v_parts[array_upper(v_parts, 1)];
            v_given := array_to_string(v_parts[1:array_upper(v_parts, 1) - 1], ' ');
        END IF;

        v_unitin := btrim(coalesce(r->>'unit', r->>'department', r->>'dept', r->>'department_or_unit', ''));
        SELECT u.unit_code, u.dept_code, u.faculty_code INTO v_unit, v_dept, v_fac FROM ref.resolve_unit(v_unitin) u LIMIT 1;
        IF v_unit IS NULL AND v_dept IS NULL AND v_fac IS NULL THEN
            c_unplaced := c_unplaced + 1;
            IF v_unitin <> '' AND NOT (upper(v_unitin) = ANY(SELECT upper(x) FROM unnest(v_missing) x)) THEN v_missing := v_missing || v_unitin; END IF;
            IF v_err IS NULL THEN v_err := 'Row ' || n || ' (' || v_staff || '): no unit matching ' || coalesce(nullif(v_unitin, ''), '(blank)'); END IF;
            CONTINUE;
        END IF;

        v_sex := upper(left(nullif(btrim(coalesce(r->>'sex', '')), ''), 1));
        IF v_sex NOT IN ('M', 'F') THEN v_sex := NULL; END IF;
        v_rank := nullif(btrim(coalesce(r->>'rank', r->>'present_rank', r->>'presentRank', '')), '');
        v_phone := nullif(btrim(coalesce(r->>'phone', r->>'phone_no', r->>'phoneNo', '')), '');
        v_email := nullif(lower(btrim(coalesce(r->>'email', ''))), '');
        v_stepin := upper(btrim(coalesce(r->>'contiss', r->>'scale', r->>'grade', r->>'conuass', '')));
        v_scale := CASE WHEN v_stepin LIKE 'CONSOL%' THEN 'CONSOLIDATED' WHEN v_stepin LIKE 'CONUASS%' THEN 'CONUASS' WHEN v_stepin LIKE 'CONUNASS%' THEN 'CONUNASS'
                        WHEN v_stepin LIKE 'CONMESS%' THEN 'CONMESS' WHEN v_stepin LIKE 'CONHESS%' THEN 'CONHESS' WHEN v_stepin <> '' THEN 'CONTISS' END;
        v_step := nullif(regexp_replace(v_stepin, '[^0-9]', '', 'g'), '')::int;
        v_date := NULL;
        BEGIN
            v_date := to_date(nullif(btrim(coalesce(r->>'date_first_appointment', r->>'date_of_1st_appt', r->>'dateOf1stAppt', r->>'first_appointment', '')), ''), 'DD/MM/YYYY');
        EXCEPTION WHEN OTHERS THEN v_date := NULL; END;

        SELECT id INTO v_pid FROM iam.person WHERE upper(staff_number) = upper(v_staff);   -- V744: the number whatever its case
        IF v_pid IS NULL THEN c_created := c_created + 1; ELSE c_exist := c_exist + 1; END IF;
        c_rec := c_rec + 1;
        CONTINUE WHEN p_dry_run;

        BEGIN
            IF v_pid IS NULL THEN
                v_pid := gen_random_uuid();
                INSERT INTO iam.person (id, staff_number, surname, given_names, email, phone) VALUES (v_pid, v_staff, v_surname, v_given, v_email, v_phone);
            ELSE
                UPDATE iam.person SET email = coalesce(email, v_email), phone = coalesce(phone, v_phone) WHERE id = v_pid AND (email IS NULL OR phone IS NULL);
            END IF;
            INSERT INTO hrm.staff_record (person_id, pno, sex, date_first_appointment, present_rank, category, salary_scale, contiss_step, home_unit, home_department, home_faculty, unit_as_given)
            VALUES (v_pid, v_pno, v_sex, v_date, v_rank, 'NON_ACADEMIC', v_scale, CASE WHEN v_scale = 'CONSOLIDATED' THEN NULL ELSE v_step END, v_unit, v_dept, v_fac, v_unitin)
            ON CONFLICT (person_id) DO UPDATE SET
                pno = excluded.pno,
                sex = coalesce(excluded.sex, hrm.staff_record.sex),
                date_first_appointment = coalesce(excluded.date_first_appointment, hrm.staff_record.date_first_appointment),
                present_rank = coalesce(excluded.present_rank, hrm.staff_record.present_rank),
                category = coalesce(hrm.staff_record.category, 'NON_ACADEMIC'),
                salary_scale = coalesce(excluded.salary_scale, hrm.staff_record.salary_scale),
                contiss_step = coalesce(excluded.contiss_step, hrm.staff_record.contiss_step),
                home_unit = coalesce(excluded.home_unit, CASE WHEN excluded.home_department IS NULL AND excluded.home_faculty IS NULL THEN hrm.staff_record.home_unit END),
                home_department = coalesce(excluded.home_department, CASE WHEN excluded.home_unit IS NULL AND excluded.home_faculty IS NULL THEN hrm.staff_record.home_department END),
                home_faculty = coalesce(excluded.home_faculty, CASE WHEN excluded.home_unit IS NULL AND excluded.home_department IS NULL THEN hrm.staff_record.home_faculty END),
                unit_as_given = excluded.unit_as_given,
                updated_at = now();
        EXCEPTION WHEN OTHERS THEN
            c_skip := c_skip + 1; c_rec := c_rec - 1;
            IF v_err IS NULL THEN v_err := 'Row ' || n || ' (' || v_staff || '): ' || SQLERRM; END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT n, c_created, c_exist, c_rec, c_unplaced, c_skip, v_err, nullif(array_to_string(v_missing, ', '), '');
END $function$;

-- iam.import_lecturers (V428): the teaching staff, as it stood, but for the lookup
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
            SELECT id INTO v_pid FROM iam.person WHERE upper(staff_number) = upper(v_staff);   -- V744: the number whatever its case
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

COMMENT ON FUNCTION iam.import_staff(jsonb, boolean) IS
  'V253: the non-teaching staff register loaded (PNO → staff number P + digits); V744: an existing person found by the number whatever its case, never made twice';
COMMENT ON FUNCTION iam.import_lecturers(jsonb) IS
  'V135/V137/V428: the teaching staff loaded (PNO → staff number P + digits); V744: an existing person found by the number whatever its case, never made twice';

COMMIT;
