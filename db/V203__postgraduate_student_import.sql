-- ═══════════════════════════════════════════════════════════════════════════
-- V203 — the postgraduate student import from the old portal
--
--   The biography import (V188) is built for undergraduates: it clamps the level
--   to 100–600 and drops school_id, so a postgraduate row (level 800, school
--   S002) would land at level 100 with no school. This is that importer adapted
--   for the postgraduate sheet, sharing the SAME people.student / people.biodata /
--   people.student_contact / iam.student_account tables and the SAME ref.programme
--   table (postgraduate programmes sit beside the undergraduate ones, told apart
--   by ref.programme.category):
--
--     • the level is kept as the sheet states it (700/800/900), not clamped;
--     • entry_mode is POSTGRADUATE and school_id defaults to S002, so the V117
--       trigger sets the postgraduate curriculum;
--     • the programme is resolved by its old-portal code (then name), and CREATED
--       as a POST GRADUATE programme in ref.programme when it is not there yet —
--       from the row's faculty and department and the award in the matric number;
--     • contact, biography, the student account (matric-number first password)
--       and the JAMB number are written exactly as the biography import does.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION people.import_postgraduate(p_rows jsonb)
RETURNS TABLE (rows int, created int, updated int, no_programme int, bad_number int,
               contacts int, biography int, accounts int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE
    r jsonb;
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_jamb text;
    v_es text; v_el int; v_cl int; v_surname text; v_others text; v_school text;
    v_state text; v_phone text; v_email text; v_addr text; v_student uuid; v_exists boolean;
    v_fac text; v_dept text; v_award text; v_dname text;
    bf text; bv text; l_contact int; l_bio int; l_acct int;
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

            v_es := nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', r->>'yoe', '')), '');
            IF v_es IS NULL OR v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN
                IF v_matric ~ '/[0-9]{2}/[0-9]{2,7}$' THEN
                    v_es := '20' || split_part(v_matric, '/', 5) || '/20'
                            || lpad(((split_part(v_matric, '/', 5))::int + 1)::text, 2, '0');
                ELSE
                    v_es := '2024/2025';
                END IF;
            END IF;
            IF v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN v_es := '2024/2025'; END IF;

            -- the level is kept as stated (postgraduate levels 700/800/900 are valid, V201); default a Master's 800
            v_cl := coalesce(nullif(regexp_replace(coalesce(r->>'level', r->>'currentLevel', r->>'current_level', ''), '[^0-9]', '', 'g'), '')::int, 0);
            v_el := coalesce(nullif(regexp_replace(coalesce(r->>'entryLevel', r->>'entry_level', ''), '[^0-9]', '', 'g'), '')::int, v_cl);
            IF v_el NOT IN (100,200,300,400,500,600,700,800,900) THEN v_el := 800; END IF;
            IF v_cl NOT IN (100,200,300,400,500,600,700,800,900) THEN v_cl := v_el; END IF;

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
                programme_code = EXCLUDED.programme_code, current_level = EXCLUDED.current_level,
                entry_mode = 'POSTGRADUATE', school_id = coalesce(EXCLUDED.school_id, people.student.school_id);
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
                    updated_at = now();
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
                ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value;
                l_bio := l_bio + 1;
            END LOOP;

            IF NOT EXISTS (SELECT 1 FROM iam.student_account WHERE student_id = v_student) THEN
                INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
                VALUES (gen_random_uuid(), v_student, crypt(gen_random_uuid()::text, gen_salt('bf', 12)), true);
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
END $$;

COMMIT;
