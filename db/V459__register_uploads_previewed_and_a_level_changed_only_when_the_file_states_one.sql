-- ═══════════════════════════════════════
-- V459 — An old-portal register upload previewed before it changes anyone, and a level changed only when the file states one
--
-- Both postgraduate-level faults of 14 Oct 2026 (V455, V458) came from an old-portal upload quietly rewriting students
-- already on the portal. The three register uploads — the Students register, the student biodata and the postgraduate
-- students — upsert on the matriculation number, so a file carried every student it named over whatever the portal held.
--
--   1 · A student's level is changed only when the file states one. The rule is one function every upload reads
--       (people.upload_kept_level): a student re-filed as postgraduate is at the row's postgraduate level; otherwise a row
--       with no level of its kind leaves the student's level as it stands, and a postgraduate student is never moved below
--       700. Until now a blank level set an undergraduate to 100 (200 for Direct Entry), and the postgraduate upload with no
--       level set every student it carried to 800 — a PhD student included. The postgraduate upload now reads
--       people.upload_levels (V455): the file's 700/800/900, else its entry level, else the programme's. The entry mode
--       kept is people.upload_kept_mode. The Students register and biodata uploads are restated from V455 with the two
--       functions in place of the expressions they carried; the postgraduate upload from V294; the changes marked V459.
--   2 · people.preview_register_upload(kind, rows): what an upload would do, without doing it — read set-based from the same
--       rules (the programme as the uploads resolve it, people.upload_levels, people.upload_kept_level/mode): the rows, the
--       numbers and programmes refused, the new students, and for the students already on the portal how many keep
--       everything and how many would change level (lowered or raised), programme or entry mode, each change listed. The
--       Records migration screen shows it, and the office confirms before the file goes up.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V459: register uploads previewed; a level changed only when the file states one', true);

-- ── 1 · the rules every register upload reads ──────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.upload_kept_level(p_old_mode text, p_old_level integer, p_new_mode text, p_new_level integer, p_stated boolean)
RETURNS integer LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE
        WHEN p_old_level IS NULL THEN p_new_level
        -- a student re-filed as postgraduate is at the row's postgraduate level
        WHEN p_new_mode = 'POSTGRADUATE' AND p_old_mode IS DISTINCT FROM 'POSTGRADUATE' AND p_old_mode IS DISTINCT FROM 'CCE' THEN p_new_level
        -- the file states no level of the row's kind: the student's stands
        WHEN NOT coalesce(p_stated, false) THEN p_old_level
        -- a postgraduate student is never moved below 700
        WHEN (p_old_mode = 'POSTGRADUATE' OR p_new_mode = 'POSTGRADUATE') AND p_new_level < 700 THEN p_old_level
        ELSE p_new_level END
$fn$;
COMMENT ON FUNCTION people.upload_kept_level(text, integer, text, integer, boolean) IS
  'V459: the level an old-portal register upload leaves a student already on the portal at — the row''s when it states one '
  '(or re-files the student as postgraduate), never a postgraduate below 700; otherwise the student''s own.';

CREATE FUNCTION people.upload_kept_mode(p_old_mode text, p_new_mode text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN p_new_mode = 'POSTGRADUATE' AND p_old_mode IS DISTINCT FROM 'POSTGRADUATE' AND p_old_mode IS DISTINCT FROM 'CCE'
                THEN 'POSTGRADUATE' ELSE p_old_mode END
$fn$;
COMMENT ON FUNCTION people.upload_kept_mode(text, text) IS
  'V459: the entry mode the Students register and biodata uploads leave a student at — re-filed POSTGRADUATE by a postgraduate '
  'programme''s row (never a CCE student), otherwise as it stands.';

-- ── 1 · the three uploads read them (restated from V455 and V294, the changes marked V459) ─────────────────────────────
CREATE OR REPLACE FUNCTION people.import_students_rows(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, updated integer, no_programme integer, bad_number integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_mode text; v_es text; v_el int; v_cl int; v_stated boolean;
        v_surname text; v_others text; v_exists boolean; v_state text; v_school text;
        n int := 0; nc int := 0; nu int := 0; nnp int := 0; nbn int := 0; ns int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, name, programme, level' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_matric !~ '^MOAUM/[A-Z]{2,4}/[0-9]{2}/[0-9]{4}$'
           AND v_matric !~ '^[A-Z]{2,6}(/[A-Z0-9]{2,6}){1,4}/[0-9]{2,7}$' THEN nbn := nbn + 1; CONTINUE; END IF;

        v_prog := btrim(coalesce(r->>'programme', r->>'programmeCode', r->>'programme_code', r->>'course', ''));
        SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
        IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived, code LIMIT 1; END IF;
        IF v_prog_code IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;

        BEGIN
            v_surname := nullif(btrim(coalesce(r->>'surname', '')), '');
            v_others := nullif(btrim(coalesce(r->>'otherNames', r->>'other_names', r->>'othernames', '')), '');
            IF v_surname IS NULL THEN
                DECLARE nm text := btrim(coalesce(r->>'name', r->>'fullName', ''));
                BEGIN
                    IF position(',' IN nm) > 0 THEN v_surname := btrim(split_part(nm, ',', 1)); v_others := btrim(substr(nm, position(',' IN nm) + 1));
                    ELSE v_surname := split_part(nm, ' ', 1); v_others := nullif(btrim(substr(nm, length(split_part(nm, ' ', 1)) + 1)), ''); END IF;
                END;
            END IF;
            IF v_surname IS NULL OR v_surname = '' THEN v_surname := 'UNKNOWN'; END IF;
            v_others := coalesce(v_others, '');

            v_sex := upper(left(btrim(coalesce(r->>'sex', r->>'gender', '')), 1));
            IF v_sex NOT IN ('F','M') THEN v_sex := NULL; END IF;
            BEGIN v_dob := (r->>'dob')::date; EXCEPTION WHEN OTHERS THEN BEGIN v_dob := (r->>'dateOfBirth')::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END; END;
            v_state := nullif(btrim(coalesce(r->>'state', r->>'stateOfOrigin', r->>'state_of_origin', '')), '');
            v_school := upper(nullif(btrim(coalesce(r->>'schoolId', r->>'school_id', r->>'schoolid', '')), ''));
            v_mode := upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', 'UTME')));
            -- V381: a student of the Centre for Continuing Education (the route, the study mode or the entry mode says so) comes over as CCE
            IF v_mode IN ('CCE', 'PART TIME', 'PART-TIME', 'PART_TIME') OR v_mode LIKE '%CONTINUING%'
               OR upper(coalesce(r->>'route', r->>'admissionRoute', r->>'admission_route', '')) ~ '(CCE|CONTINUING)'
               OR upper(coalesce(r->>'studyMode', r->>'study_mode', '')) ~ 'PART' THEN
                v_mode := 'CCE';
            END IF;
            IF v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH','CCE') THEN v_mode := 'UTME'; END IF;

            v_es := nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', '')), '');
            IF v_es IS NULL OR v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN
                IF v_matric ~ '^MOAUM/' THEN
                    v_es := '20' || split_part(v_matric, '/', 3) || '/20' || lpad(((split_part(v_matric, '/', 3))::int + 1)::text, 2, '0');
                ELSE
                    v_es := coalesce(v_es, '2000/2001');
                END IF;
            END IF;
            IF v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN v_es := '2000/2001'; END IF;

            -- V455: a postgraduate programme's row is filed POSTGRADUATE at 700/800/900 (people.upload_levels)
            SELECT u.mode, u.entry_level, u.current_level, u.level_stated INTO v_mode, v_el, v_cl, v_stated
              FROM people.upload_levels(v_prog_code, v_mode, coalesce(r->>'entryLevel', r->>'entry_level', ''),
                                        coalesce(r->>'level', r->>'currentLevel', r->>'current_level', '')) u;

            SELECT true INTO v_exists FROM people.student WHERE upper(matric_no) = v_matric;
            INSERT INTO people.student (id, matric_no, surname, other_names, sex, date_of_birth, state_of_origin, programme_code, entry_mode,
                                        entry_session, entry_level, current_level, status, matriculated_at, school_id, study_mode)
            VALUES (gen_random_uuid(), v_matric, v_surname, v_others, v_sex, v_dob, v_state, v_prog_code, v_mode, v_es, v_el, v_cl, 'ACTIVE', now(), v_school,
                    CASE WHEN v_mode = 'CCE' THEN 'PART_TIME' ELSE 'FULL_TIME' END)
            ON CONFLICT (matric_no) DO UPDATE SET surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
                sex = coalesce(EXCLUDED.sex, people.student.sex), date_of_birth = coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth),
                state_of_origin = coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                programme_code = EXCLUDED.programme_code,
                -- V459: the level changes only when the file states one (people.upload_kept_level: never a postgraduate
                -- below 700); a postgraduate programme's row re-files a student wrongly filed as undergraduate (people.upload_kept_mode)
                current_level = people.upload_kept_level(people.student.entry_mode, people.student.current_level, EXCLUDED.entry_mode, EXCLUDED.current_level, v_stated),
                entry_mode = people.upload_kept_mode(people.student.entry_mode, EXCLUDED.entry_mode),
                entry_level = CASE WHEN EXCLUDED.entry_mode = 'POSTGRADUATE' AND people.student.entry_mode NOT IN ('POSTGRADUATE', 'CCE')
                                        AND coalesce(people.student.entry_level, 0) < 700
                                   THEN EXCLUDED.entry_level ELSE people.student.entry_level END,
                school_id = coalesce(EXCLUDED.school_id, people.student.school_id);
            IF coalesce(v_exists, false) THEN nu := nu + 1; ELSE nc := nc + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, nu, nnp, nbn, ns, v_firsterr;
END $function$;

CREATE OR REPLACE FUNCTION people.import_biography_rows(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, updated integer, no_programme integer, bad_number integer, contacts integer, biography integer, accounts integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    r jsonb;
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_jamb text;
    v_mode text; v_es text; v_el int; v_cl int; v_stated boolean; v_surname text; v_others text;
    v_state text; v_phone text; v_email text; v_addr text; v_student uuid; v_exists boolean;
    bf text; bv text; l_contact int; l_bio int; l_acct int;
    v_sealed text;   -- one hash per upload, made when the first account is opened (V294)
    n int := 0; nc int := 0; nu int := 0; nnp int := 0; nbn int := 0;
    ncontact int := 0; nbio int := 0; nacct int := 0; nerr int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, name, programme, level, and the biography'
            USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;

        IF v_matric !~ '^MOAUM/[A-Z]{2,4}/[0-9]{2}/[0-9]{4}$'
           AND v_matric !~ '^[A-Z]{2,6}(/[A-Z0-9]{2,6}){1,4}/[0-9]{2,7}$' THEN
            nbn := nbn + 1; CONTINUE;
        END IF;

        v_prog := btrim(coalesce(r->>'programme', r->>'programmeCode', r->>'programme_code', r->>'course', ''));
        SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
        IF v_prog_code IS NULL THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived, code LIMIT 1;
        END IF;
        IF v_prog_code IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;

        l_contact := 0; l_bio := 0; l_acct := 0;
        BEGIN
            v_surname := nullif(btrim(coalesce(r->>'surname', '')), '');
            v_others  := nullif(btrim(coalesce(r->>'otherNames', r->>'other_names', r->>'othernames', '')), '');
            IF v_surname IS NULL THEN
                DECLARE nm text := btrim(coalesce(r->>'name', r->>'fullName', ''));
                BEGIN
                    IF position(',' IN nm) > 0 THEN
                        v_surname := btrim(split_part(nm, ',', 1));
                        v_others  := btrim(substr(nm, position(',' IN nm) + 1));
                    ELSE
                        v_surname := split_part(nm, ' ', 1);
                        v_others  := nullif(btrim(substr(nm, length(split_part(nm, ' ', 1)) + 1)), '');
                    END IF;
                END;
            END IF;
            IF v_surname IS NULL OR v_surname = '' THEN v_surname := 'UNKNOWN'; END IF;
            v_others := coalesce(v_others, '');

            v_sex := upper(left(btrim(coalesce(r->>'sex', r->>'gender', '')), 1));
            IF v_sex NOT IN ('F', 'M') THEN v_sex := NULL; END IF;

            BEGIN v_dob := (r->>'dob')::date;
            EXCEPTION WHEN OTHERS THEN
                BEGIN v_dob := (r->>'dateOfBirth')::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END;
            END;

            v_state := nullif(btrim(coalesce(r->>'state', r->>'stateOfOrigin', r->>'state_of_origin', '')), '');
            v_jamb := nullif(upper(btrim(coalesce(r->>'jamb', r->>'jambNo', r->>'jamb_no', r->>'jambRegNo', r->>'jamb_reg_no', ''))), '');

            v_mode := upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', r->>'mode_entry', 'UTME')));
            v_mode := CASE v_mode
                          WHEN 'DE' THEN 'DIRECT_ENTRY'
                          WHEN 'DIRECT ENTRY' THEN 'DIRECT_ENTRY'
                          WHEN 'PG' THEN 'POSTGRADUATE'
                          ELSE v_mode END;
            IF v_mode NOT IN ('UTME', 'DIRECT_ENTRY', 'TRANSFER', 'POSTGRADUATE', 'JUPEB', 'SANDWICH') THEN v_mode := 'UTME'; END IF;

            v_es := nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', r->>'yoe', '')), '');
            IF v_es IS NULL OR v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN
                IF v_matric ~ '^MOAUM/' THEN
                    v_es := '20' || split_part(v_matric, '/', 3) || '/20'
                            || lpad(((split_part(v_matric, '/', 3))::int + 1)::text, 2, '0');
                ELSE
                    v_es := coalesce(v_es, '2000/2001');
                END IF;
            END IF;
            IF v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN v_es := '2000/2001'; END IF;

            -- V455: a postgraduate programme's row is filed POSTGRADUATE at 700/800/900 (people.upload_levels)
            SELECT u.mode, u.entry_level, u.current_level, u.level_stated INTO v_mode, v_el, v_cl, v_stated
              FROM people.upload_levels(v_prog_code, v_mode, coalesce(r->>'entryLevel', r->>'entry_level', ''),
                                        coalesce(r->>'level', r->>'currentLevel', r->>'current_level', '')) u;

            SELECT true INTO v_exists FROM people.student WHERE upper(matric_no) = v_matric;
            INSERT INTO people.student (id, matric_no, surname, other_names, sex, date_of_birth, state_of_origin,
                                        jamb_reg_no, programme_code, entry_mode, entry_session, entry_level, current_level,
                                        status, matriculated_at)
            VALUES (gen_random_uuid(), v_matric, v_surname, v_others, v_sex, v_dob, v_state, v_jamb, v_prog_code, v_mode,
                    v_es, v_el, v_cl, 'ACTIVE', now())
            ON CONFLICT (matric_no) DO UPDATE SET
                surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
                sex = coalesce(EXCLUDED.sex, people.student.sex),
                date_of_birth = coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth),
                state_of_origin = coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                jamb_reg_no = coalesce(EXCLUDED.jamb_reg_no, people.student.jamb_reg_no),
                programme_code = EXCLUDED.programme_code,
                -- V459: the level changes only when the file states one (people.upload_kept_level: never a postgraduate
                -- below 700); a postgraduate programme's row re-files a student wrongly filed as undergraduate (people.upload_kept_mode)
                current_level = people.upload_kept_level(people.student.entry_mode, people.student.current_level, EXCLUDED.entry_mode, EXCLUDED.current_level, v_stated),
                entry_mode = people.upload_kept_mode(people.student.entry_mode, EXCLUDED.entry_mode),
                entry_level = CASE WHEN EXCLUDED.entry_mode = 'POSTGRADUATE' AND people.student.entry_mode NOT IN ('POSTGRADUATE', 'CCE')
                                        AND coalesce(people.student.entry_level, 0) < 700
                                   THEN EXCLUDED.entry_level ELSE people.student.entry_level END
            WHERE (people.student.surname, people.student.other_names, people.student.sex, people.student.date_of_birth,
                   people.student.state_of_origin, people.student.jamb_reg_no, people.student.programme_code, people.student.current_level,
                   people.student.entry_mode)
                  IS DISTINCT FROM (EXCLUDED.surname, EXCLUDED.other_names, coalesce(EXCLUDED.sex, people.student.sex),
                   coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth), coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                   coalesce(EXCLUDED.jamb_reg_no, people.student.jamb_reg_no), EXCLUDED.programme_code,
                   people.upload_kept_level(people.student.entry_mode, people.student.current_level, EXCLUDED.entry_mode, EXCLUDED.current_level, v_stated),
                   people.upload_kept_mode(people.student.entry_mode, EXCLUDED.entry_mode));
            SELECT id INTO v_student FROM people.student WHERE upper(matric_no) = v_matric;

            v_phone := regexp_replace(coalesce(r->>'phone', r->>'mobile', ''), '[^0-9]', '', 'g');
            IF length(v_phone) = 10 THEN v_phone := '0' || v_phone;
            ELSIF length(v_phone) = 13 AND left(v_phone, 3) = '234' THEN v_phone := '0' || right(v_phone, 10);
            END IF;
            IF v_phone !~ '^0[0-9]{10}$' THEN v_phone := NULL; END IF;

            v_email := lower(nullif(btrim(coalesce(r->>'email', r->>'loginemail', '')), ''));
            IF v_email IS NOT NULL AND v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN v_email := NULL; END IF;

            v_addr := nullif(btrim(coalesce(r->>'address', '')), '');

            IF v_phone IS NOT NULL OR v_email IS NOT NULL OR v_addr IS NOT NULL THEN
                INSERT INTO people.student_contact (student_id, phone, email, address)
                VALUES (v_student, v_phone, v_email, v_addr)
                ON CONFLICT (student_id) DO UPDATE SET
                    phone = coalesce(EXCLUDED.phone, people.student_contact.phone),
                    email = coalesce(EXCLUDED.email, people.student_contact.email),
                    address = coalesce(EXCLUDED.address, people.student_contact.address),
                    updated_at = now()
                WHERE (people.student_contact.phone, people.student_contact.email, people.student_contact.address)
                      IS DISTINCT FROM (coalesce(EXCLUDED.phone, people.student_contact.phone),
                                        coalesce(EXCLUDED.email, people.student_contact.email),
                                        coalesce(EXCLUDED.address, people.student_contact.address));
                l_contact := 1;
            END IF;

            FOR bf, bv IN
                SELECT key, value FROM jsonb_each_text(jsonb_strip_nulls(jsonb_build_object(
                    'nationality',      nullif(btrim(coalesce(r->>'nationality', '')), ''),
                    'state_of_origin',  v_state,
                    'lga',              nullif(btrim(coalesce(r->>'lga', '')), ''),
                    'guardian_name',    nullif(btrim(coalesce(r->>'guardianName', r->>'guardianname', '')), ''),
                    'guardian_address', nullif(btrim(coalesce(r->>'guardianAddress', r->>'guardianaddress', '')), ''),
                    'sponsor_name',     nullif(btrim(coalesce(r->>'sponsorName', r->>'sponsorname', '')), ''),
                    'sponsor_address',  nullif(btrim(coalesce(r->>'sponsorAddress', r->>'sponsoraddress', '')), ''),
                    'kin_name',         nullif(btrim(coalesce(r->>'nokName', r->>'nokname', r->>'kinName', '')), ''),
                    'kin_address',      nullif(btrim(coalesce(r->>'nokAddress', r->>'nokaddress', r->>'kinAddress', '')), ''),
                    'extracurricular',  nullif(btrim(coalesce(r->>'extracurricular', '')), ''),
                    'legacy_appno',     nullif(btrim(coalesce(r->>'appno', r->>'applicationNo', '')), '')
                )))
            LOOP
                INSERT INTO people.biodata (student_id, field, value) VALUES (v_student, bf, bv)
                ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value
                WHERE people.biodata.value IS DISTINCT FROM EXCLUDED.value;
                l_bio := l_bio + 1;
            END LOOP;

            IF NOT EXISTS (SELECT 1 FROM iam.student_account WHERE student_id = v_student) THEN
                -- sealed: a cost-12 hash of a random secret nobody holds, made once for the upload rather than once a
                -- row; the student's first sign-in is their own number (must_change), never this
                IF v_sealed IS NULL THEN v_sealed := crypt(gen_random_uuid()::text, gen_salt('bf', 12)); END IF;
                INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
                VALUES (gen_random_uuid(), v_student, v_sealed, true);
                l_acct := 1;
            END IF;

            IF coalesce(v_exists, false) THEN nu := nu + 1; ELSE nc := nc + 1; END IF;
            ncontact := ncontact + l_contact;
            nbio := nbio + l_bio;
            nacct := nacct + l_acct;
        EXCEPTION WHEN OTHERS THEN
            nerr := nerr + 1;
            IF v_firsterr IS NULL THEN
                v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300);
            END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT n, nc, nu, nnp, nbn, ncontact, nbio, nacct, nerr, v_firsterr;
END $function$;

CREATE OR REPLACE FUNCTION people.import_postgraduate(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, updated integer, no_programme integer, bad_number integer, contacts integer, biography integer, accounts integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    r jsonb;
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_jamb text;
    v_es text; v_yy text; v_el int; v_cl int; v_stated boolean; v_surname text; v_others text; v_school text;
    v_state text; v_phone text; v_email text; v_addr text; v_student uuid; v_exists boolean;
    v_fac text; v_dept text; v_award text; v_dname text;
    bf text; bv text; l_contact int; l_bio int; l_acct int;
    v_sealed text;   -- one hash per upload, made when the first account is opened (V294)
    n int := 0; nc int := 0; nu int := 0; nnp int := 0; nbn int := 0;
    ncontact int := 0; nbio int := 0; nacct int := 0; nerr int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, name, programme, level, and the biography'
            USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;

        -- any institutional matriculation number: a 2–6 letter prefix (MOAU / MOAUM / BSU …) then 2–8 segments
        IF v_matric !~ '^[A-Z]{2,6}(/[A-Z0-9]{1,12}){2,8}$' THEN
            nbn := nbn + 1; CONTINUE;
        END IF;

        -- resolve the programme by code, then by name; create it as POST GRADUATE when it is not on record
        v_prog := btrim(coalesce(r->>'programme', r->>'programmeCode', r->>'programme_code', r->>'course', ''));
        v_prog_code := NULL;
        IF v_prog <> '' THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
            IF v_prog_code IS NULL THEN
                SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived, code LIMIT 1;
            END IF;
        END IF;
        IF v_prog_code IS NULL AND v_prog ~ '^C[0-9]{5}$' THEN
            -- the faculty, department and award to build the missing programme from
            v_fac  := upper(nullif(btrim(coalesce(r->>'faculty', split_part(v_matric, '/', 2))), ''));
            v_dept := upper(nullif(btrim(coalesce(r->>'department', split_part(v_matric, '/', 3))), ''));
            v_award := upper(nullif(btrim(split_part(v_matric, '/', 4)), ''));
            SELECT name INTO v_dname FROM ref.department WHERE upper(code) = v_dept;
            IF v_dept IS NOT NULL AND v_fac IS NOT NULL
               AND EXISTS (SELECT 1 FROM ref.department WHERE upper(code) = v_dept)
               AND EXISTS (SELECT 1 FROM ref.faculty WHERE upper(code) = v_fac) THEN
                INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_research)
                VALUES (upper(v_prog), btrim(coalesce(v_award || ' ', '') || coalesce(v_dname, v_dept)),
                        (SELECT code FROM ref.department WHERE upper(code) = v_dept),
                        (SELECT code FROM ref.faculty WHERE upper(code) = v_fac),
                        0, false, 'POST GRADUATE', false)
                ON CONFLICT (code) DO NOTHING;
                v_prog_code := upper(v_prog);
            END IF;
        END IF;
        IF v_prog_code IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;

        l_contact := 0; l_bio := 0; l_acct := 0;
        BEGIN
            v_surname := nullif(btrim(coalesce(r->>'surname', '')), '');
            v_others  := nullif(btrim(coalesce(r->>'otherNames', r->>'other_names', r->>'othernames', '')), '');
            IF v_surname IS NULL THEN
                DECLARE nm text := btrim(coalesce(r->>'name', r->>'fullName', ''));
                BEGIN
                    IF position(',' IN nm) > 0 THEN
                        v_surname := btrim(split_part(nm, ',', 1));
                        v_others  := btrim(substr(nm, position(',' IN nm) + 1));
                    ELSE
                        v_surname := split_part(nm, ' ', 1);
                        v_others  := nullif(btrim(substr(nm, length(split_part(nm, ' ', 1)) + 1)), '');
                    END IF;
                END;
            END IF;
            IF v_surname IS NULL OR v_surname = '' THEN v_surname := 'UNKNOWN'; END IF;
            v_others := coalesce(v_others, '');

            v_sex := upper(left(btrim(coalesce(r->>'sex', r->>'gender', '')), 1));
            IF v_sex NOT IN ('F', 'M') THEN v_sex := NULL; END IF;

            BEGIN v_dob := (r->>'dob')::date;
            EXCEPTION WHEN OTHERS THEN
                BEGIN v_dob := (r->>'dateOfBirth')::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END;
            END;

            v_state := nullif(btrim(coalesce(r->>'state', r->>'stateOfOrigin', r->>'state_of_origin', '')), '');
            v_jamb := nullif(upper(btrim(coalesce(r->>'jamb', r->>'jambNo', r->>'jamb_no', r->>'jambRegNo', r->>'jamb_reg_no', ''))), '');

            -- this is the postgraduate importer: the entry mode is POSTGRADUATE, and the school defaults to S002
            v_school := upper(nullif(btrim(coalesce(r->>'schoolId', r->>'school_id', r->>'schoolid', '')), ''));
            IF v_school IS NULL THEN v_school := 'S002'; END IF;

            -- entry session from the file, else from the YY before the serial at the end of the matric
            v_es := nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', r->>'yoe', '')), '');
            IF v_es IS NULL OR v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN
                v_yy := substring(v_matric from '/([0-9]{2})/[0-9]{2,7}$');
                IF v_yy IS NOT NULL THEN
                    v_es := '20' || v_yy || '/20' || lpad((v_yy::int + 1)::text, 2, '0');
                ELSE
                    v_es := '2024/2025';
                END IF;
            END IF;
            IF v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN v_es := '2024/2025'; END IF;

            -- V459: the postgraduate levels (people.upload_levels, V455): the file's 700/800/900, else its entry level, else the
            -- programme's (a PhD 900, a postgraduate diploma 700, a Master's 800) — no longer a flat 800 for a row with no level
            SELECT u.entry_level, u.current_level, u.level_stated INTO v_el, v_cl, v_stated
              FROM people.upload_levels(v_prog_code, 'POSTGRADUATE', coalesce(r->>'entryLevel', r->>'entry_level', ''),
                                        coalesce(r->>'level', r->>'currentLevel', r->>'current_level', '')) u;

            SELECT true INTO v_exists FROM people.student WHERE upper(matric_no) = v_matric;
            INSERT INTO people.student (id, matric_no, surname, other_names, sex, date_of_birth, state_of_origin,
                                        jamb_reg_no, programme_code, entry_mode, entry_session, entry_level, current_level,
                                        status, matriculated_at, school_id)
            VALUES (gen_random_uuid(), v_matric, v_surname, v_others, v_sex, v_dob, v_state, v_jamb, v_prog_code, 'POSTGRADUATE',
                    v_es, v_el, v_cl, 'ACTIVE', now(), v_school)
            ON CONFLICT (matric_no) DO UPDATE SET
                surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
                sex = coalesce(EXCLUDED.sex, people.student.sex),
                date_of_birth = coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth),
                state_of_origin = coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                jamb_reg_no = coalesce(EXCLUDED.jamb_reg_no, people.student.jamb_reg_no),
                programme_code = EXCLUDED.programme_code,
                -- V459: the level changes only when the file states one; a student re-filed postgraduate takes the row's levels
                current_level = people.upload_kept_level(people.student.entry_mode, people.student.current_level, 'POSTGRADUATE', EXCLUDED.current_level, v_stated),
                entry_level = CASE WHEN people.student.entry_mode IS DISTINCT FROM 'POSTGRADUATE' AND coalesce(people.student.entry_level, 0) < 700
                                   THEN EXCLUDED.entry_level ELSE people.student.entry_level END,
                entry_mode = 'POSTGRADUATE', school_id = coalesce(EXCLUDED.school_id, people.student.school_id)
            WHERE (people.student.surname, people.student.other_names, people.student.sex, people.student.date_of_birth,
                   people.student.state_of_origin, people.student.jamb_reg_no, people.student.programme_code, people.student.current_level,
                   people.student.entry_mode, people.student.school_id)
                  IS DISTINCT FROM (EXCLUDED.surname, EXCLUDED.other_names, coalesce(EXCLUDED.sex, people.student.sex),
                   coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth), coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                   coalesce(EXCLUDED.jamb_reg_no, people.student.jamb_reg_no), EXCLUDED.programme_code,
                   people.upload_kept_level(people.student.entry_mode, people.student.current_level, 'POSTGRADUATE', EXCLUDED.current_level, v_stated),
                   'POSTGRADUATE', coalesce(EXCLUDED.school_id, people.student.school_id));
            SELECT id INTO v_student FROM people.student WHERE upper(matric_no) = v_matric;

            v_phone := regexp_replace(coalesce(r->>'phone', r->>'mobile', ''), '[^0-9]', '', 'g');
            IF length(v_phone) = 10 THEN v_phone := '0' || v_phone;
            ELSIF length(v_phone) = 13 AND left(v_phone, 3) = '234' THEN v_phone := '0' || right(v_phone, 10);
            END IF;
            IF v_phone !~ '^0[0-9]{10}$' THEN v_phone := NULL; END IF;

            v_email := lower(nullif(btrim(coalesce(r->>'email', r->>'loginemail', r->>'login_email', '')), ''));
            IF v_email IS NOT NULL AND v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN v_email := NULL; END IF;

            v_addr := nullif(btrim(coalesce(r->>'address', '')), '');

            IF v_phone IS NOT NULL OR v_email IS NOT NULL OR v_addr IS NOT NULL THEN
                INSERT INTO people.student_contact (student_id, phone, email, address)
                VALUES (v_student, v_phone, v_email, v_addr)
                ON CONFLICT (student_id) DO UPDATE SET
                    phone = coalesce(EXCLUDED.phone, people.student_contact.phone),
                    email = coalesce(EXCLUDED.email, people.student_contact.email),
                    address = coalesce(EXCLUDED.address, people.student_contact.address),
                    updated_at = now()
                WHERE (people.student_contact.phone, people.student_contact.email, people.student_contact.address)
                      IS DISTINCT FROM (coalesce(EXCLUDED.phone, people.student_contact.phone),
                                        coalesce(EXCLUDED.email, people.student_contact.email),
                                        coalesce(EXCLUDED.address, people.student_contact.address));
                l_contact := 1;
            END IF;

            FOR bf, bv IN
                SELECT key, value FROM jsonb_each_text(jsonb_strip_nulls(jsonb_build_object(
                    'nationality',      nullif(btrim(coalesce(r->>'nationality', '')), ''),
                    'state_of_origin',  v_state,
                    'lga',              nullif(btrim(coalesce(r->>'lga', '')), ''),
                    'guardian_name',    nullif(btrim(coalesce(r->>'guardianName', r->>'guardianname', '')), ''),
                    'guardian_address', nullif(btrim(coalesce(r->>'guardianAddress', r->>'guardianaddress', '')), ''),
                    'sponsor_name',     nullif(btrim(coalesce(r->>'sponsorName', r->>'sponsorname', '')), ''),
                    'sponsor_address',  nullif(btrim(coalesce(r->>'sponsorAddress', r->>'sponsoraddress', '')), ''),
                    'kin_name',         nullif(btrim(coalesce(r->>'nokName', r->>'nokname', r->>'kinName', '')), ''),
                    'kin_address',      nullif(btrim(coalesce(r->>'nokAddress', r->>'nokaddress', r->>'kinAddress', '')), ''),
                    'extracurricular',  nullif(btrim(coalesce(r->>'extracurricular', '')), ''),
                    'legacy_appno',     nullif(btrim(coalesce(r->>'appno', r->>'applicationNo', '')), '')
                )))
            LOOP
                INSERT INTO people.biodata (student_id, field, value) VALUES (v_student, bf, bv)
                ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value
                WHERE people.biodata.value IS DISTINCT FROM EXCLUDED.value;
                l_bio := l_bio + 1;
            END LOOP;

            IF NOT EXISTS (SELECT 1 FROM iam.student_account WHERE student_id = v_student) THEN
                -- sealed: a cost-12 hash of a random secret nobody holds, made once for the upload rather than once a
                -- row; the student's first sign-in is their own number (must_change), never this
                IF v_sealed IS NULL THEN v_sealed := crypt(gen_random_uuid()::text, gen_salt('bf', 12)); END IF;
                INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
                VALUES (gen_random_uuid(), v_student, v_sealed, true);
                l_acct := 1;
            END IF;

            IF coalesce(v_exists, false) THEN nu := nu + 1; ELSE nc := nc + 1; END IF;
            ncontact := ncontact + l_contact;
            nbio := nbio + l_bio;
            nacct := nacct + l_acct;
        EXCEPTION WHEN OTHERS THEN
            nerr := nerr + 1;
            IF v_firsterr IS NULL THEN
                v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300);
            END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT n, nc, nu, nnp, nbn, ncontact, nbio, nacct, nerr, v_firsterr;
END $function$;

-- ── 2 · the preview ─────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.preview_register_upload(p_kind text, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE v jsonb;
BEGIN
    IF p_kind IS NULL OR p_kind NOT IN ('students', 'biodata', 'postgraduate') THEN
        RAISE EXCEPTION 'UPLOAD_KIND: a preview is of the students, biodata or postgraduate upload' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'UPLOAD_ROWS: the file is rows' USING ERRCODE = '23514';
    END IF;
    WITH r AS (
        SELECT t.o AS ord, t.x,
               upper(btrim(coalesce(t.x->>'matric', t.x->>'matricNo', t.x->>'matric_no', t.x->>'matno', t.x->>'regNo', ''))) AS matric,
               btrim(coalesce(t.x->>'programme', t.x->>'programmeCode', t.x->>'programme_code', t.x->>'course', '')) AS prog_text,
               upper(btrim(coalesce(t.x->>'entryMode', t.x->>'entry_mode', t.x->>'mode_entry', ''))) AS mode_text
          FROM jsonb_array_elements(p_rows) WITH ORDINALITY t(x, o)),
    named AS (SELECT * FROM r WHERE r.matric <> ''),
    valid AS (
        SELECT n.*,
               CASE WHEN p_kind = 'postgraduate' THEN n.matric ~ '^[A-Z]{2,6}(/[A-Z0-9]{1,12}){2,8}$'
                    ELSE n.matric ~ '^MOAUM/[A-Z]{2,4}/[0-9]{2}/[0-9]{4}$' OR n.matric ~ '^[A-Z]{2,6}(/[A-Z0-9]{2,6}){1,4}/[0-9]{2,7}$' END AS number_ok,
               -- the programme as the uploads resolve it: by code, then by name
               coalesce((SELECT p.code FROM ref.programme p WHERE upper(p.code) = upper(n.prog_text) LIMIT 1),
                        (SELECT p.code FROM ref.programme p WHERE upper(p.name) = upper(n.prog_text) ORDER BY p.archived, p.code LIMIT 1)) AS prog,
               -- the entry mode as each upload reads it (it decides only whether the row is postgraduate or CCE here)
               CASE WHEN p_kind = 'postgraduate' THEN 'POSTGRADUATE'
                    WHEN p_kind = 'students' AND (n.mode_text IN ('CCE', 'PART TIME', 'PART-TIME', 'PART_TIME') OR n.mode_text LIKE '%CONTINUING%'
                         OR upper(coalesce(n.x->>'route', n.x->>'admissionRoute', n.x->>'admission_route', '')) ~ '(CCE|CONTINUING)'
                         OR upper(coalesce(n.x->>'studyMode', n.x->>'study_mode', '')) ~ 'PART') THEN 'CCE'
                    WHEN p_kind = 'biodata' AND n.mode_text = 'PG' THEN 'POSTGRADUATE'
                    WHEN p_kind = 'biodata' AND n.mode_text IN ('DE', 'DIRECT ENTRY') THEN 'DIRECT_ENTRY'
                    WHEN n.mode_text IN ('UTME', 'DIRECT_ENTRY', 'TRANSFER', 'POSTGRADUATE', 'JUPEB', 'SANDWICH') THEN n.mode_text
                    ELSE 'UTME' END AS mode0
          FROM named n),
    lv AS (
        SELECT v.*, u.mode, u.current_level AS level, u.level_stated
          FROM valid v
          LEFT JOIN LATERAL people.upload_levels(v.prog, v.mode0, coalesce(v.x->>'entryLevel', v.x->>'entry_level', ''),
                                                 coalesce(v.x->>'level', v.x->>'currentLevel', v.x->>'current_level', '')) u ON v.prog IS NOT NULL),
    -- a number named twice: the last row is the one the upload leaves standing
    last AS (SELECT DISTINCT ON (lv.matric) lv.* FROM lv WHERE lv.number_ok AND lv.prog IS NOT NULL ORDER BY lv.matric, lv.ord DESC),
    cmp AS (
        SELECT l.matric, s.id AS sid, btrim(coalesce(s.surname, '') || ', ' || coalesce(s.other_names, ''), ', ') AS name,
               s.programme_code AS old_prog, l.prog AS new_prog,
               s.entry_mode AS old_mode,
               CASE WHEN p_kind = 'postgraduate' THEN 'POSTGRADUATE' ELSE people.upload_kept_mode(s.entry_mode, l.mode) END AS new_mode,
               s.current_level AS old_level,
               people.upload_kept_level(s.entry_mode, s.current_level, l.mode, l.level, l.level_stated) AS new_level
          FROM last l
          LEFT JOIN people.student s ON upper(s.matric_no) = l.matric),
    changes AS (
        SELECT c.matric, c.name, f.field, f.old, f.new, f.rank
          FROM cmp c
          CROSS JOIN LATERAL (VALUES
              ('level', c.old_level::text, c.new_level::text, CASE WHEN c.new_level < c.old_level THEN 1 ELSE 4 END),
              ('programme', c.old_prog, c.new_prog, 2),
              ('entry mode', c.old_mode, c.new_mode, 3)) f(field, old, new, rank)
         WHERE c.sid IS NOT NULL AND f.old IS DISTINCT FROM f.new)
    SELECT jsonb_build_object(
        'kind', p_kind,
        'rows', (SELECT count(*) FROM named),
        'badNumber', (SELECT count(*) FROM valid WHERE NOT number_ok),
        'noProgramme', (SELECT count(*) FROM valid WHERE number_ok AND prog IS NULL
                                                    AND NOT (p_kind = 'postgraduate' AND prog_text ~* '^C[0-9]{5}$')),
        'newProgrammes', (SELECT count(DISTINCT upper(prog_text)) FROM valid WHERE number_ok AND prog IS NULL
                                                                         AND p_kind = 'postgraduate' AND prog_text ~* '^C[0-9]{5}$'),
        'newStudents', (SELECT count(*) FROM cmp WHERE sid IS NULL),
        'existing', (SELECT count(*) FROM cmp WHERE sid IS NOT NULL),
        'unchanged', (SELECT count(*) FROM cmp c WHERE c.sid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM changes x WHERE x.matric = c.matric)),
        'levelChanged', (SELECT count(*) FROM changes WHERE field = 'level'),
        'levelLowered', (SELECT count(*) FROM cmp WHERE sid IS NOT NULL AND new_level < old_level),
        'levelRaised', (SELECT count(*) FROM cmp WHERE sid IS NOT NULL AND new_level > old_level),
        'programmeChanged', (SELECT count(*) FROM changes WHERE field = 'programme'),
        'modeChanged', (SELECT count(*) FROM changes WHERE field = 'entry mode'),
        'changes', coalesce((SELECT jsonb_agg(jsonb_build_object('matric', x.matric, 'name', x.name, 'field', x.field, 'from', x.old, 'to', x.new)
                                              ORDER BY x.rank, x.matric, x.field) FROM changes x), '[]'::jsonb))
      INTO v;
    RETURN v;
END $fn$;
COMMENT ON FUNCTION people.preview_register_upload(text, jsonb) IS
  'V459: what an old-portal register upload (students, biodata, postgraduate) would do, without doing it: rows, refused '
  'numbers and programmes, new students and programmes, and for the students already on the portal how many keep everything '
  'and each change of level (lowered or raised), programme or entry mode — read from the rules the uploads themselves read.';

COMMIT;
