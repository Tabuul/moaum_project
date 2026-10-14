-- ═══════════════════════════════════════
-- V455 — A postgraduate student keeps a postgraduate level
--
-- Reported 14 Oct 2026: a PhD student (BSU/AR/REL/PHD/23/0627) shown at 100 Level, not 900. The two old-portal uploads of the
-- register — the Students register (people.import_students_rows) and the student biodata (people.import_biography_rows) —
-- knew only the undergraduate levels: a level outside 100–600 in the file became 100 (the entry level) and the current level
-- followed it, and a student already on the portal had their current level overwritten by it. A postgraduate student loaded
-- by the postgraduate register (people.import_postgraduate, which keeps 700/800/900) and then carried in either of the other
-- two files was set to 100 Level, still marked Postgraduate. The Railway register is right (its 3,450 postgraduate students
-- are at 700–900); a portal whose register came through those uploads is not.
--
--   1 · people.upload_levels: the one rule both uploads now read. A row of a postgraduate programme (or marked POSTGRADUATE,
--       never CCE) is filed POSTGRADUATE at a postgraduate level — the file's when it says 700, 800 or 900, else its entry
--       level, else the programme's (people.pg_level_of: a PhD 900, a postgraduate diploma 700, any other a Master's 800);
--       an undergraduate row keeps the rule it had (100–600; the entry level 100 for UTME and CCE, 200 otherwise).
--   2 · On a student already on the portal, neither upload lowers a postgraduate student below 700, and a row of a
--       postgraduate programme moves a student wrongly filed as UTME (or Direct Entry, Transfer …) to POSTGRADUATE at its level.
--   3 · Repaired: every student of a postgraduate programme (not CCE) whose entry mode is not POSTGRADUATE or whose entry or
--       current level is below 700 — the current level restored to the entry level when that is postgraduate, else the
--       programme's. Changes are on the audit spine under this migration; counts are reported.
--   4 · people.level_in (the level a student was at in a session, V330): a postgraduate student's level is their own, not
--       advanced a level a session and capped at 600.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V455: a postgraduate student keeps a postgraduate level', true);

-- ── 1 · the rule ────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.pg_level_of(p_programme text)
RETURNS integer LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN upper(p.name) ~ '^\s*(PH\.?\s?D|DOCTOR OF PHILOSOPHY)' THEN 900
                WHEN upper(p.name) ~ '^\s*(P\.?\s?G\.?\s?D|POST\s?-?GRADUATE DIPLOMA)' THEN 700
                ELSE 800 END
      FROM ref.programme p
     WHERE p.code = p_programme
$fn$;
COMMENT ON FUNCTION people.pg_level_of(text) IS
  'V455: the level a postgraduate programme''s students are at when nothing else says: a PhD 900, a postgraduate diploma (PGD, PGDM) 700, any other (a Master''s) 800.';

CREATE FUNCTION people.upload_levels(p_programme text, p_mode text, p_entry_level text, p_level text,
                                     OUT mode text, OUT entry_level integer, OUT current_level integer, OUT level_stated boolean)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_pg boolean; v_el int; v_cl int;
BEGIN
    mode := p_mode;
    v_el := nullif(regexp_replace(coalesce(p_entry_level, ''), '[^0-9]', '', 'g'), '')::int;
    v_cl := nullif(regexp_replace(coalesce(p_level, ''), '[^0-9]', '', 'g'), '')::int;
    v_pg := mode IS DISTINCT FROM 'CCE'
            AND (mode = 'POSTGRADUATE' OR EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = p_programme AND p.category = 'POST GRADUATE'));
    IF v_pg THEN
        mode := 'POSTGRADUATE';
        IF v_el IS NULL OR v_el NOT IN (700, 800, 900) THEN
            v_el := CASE WHEN v_cl IN (700, 800, 900) THEN v_cl ELSE coalesce(people.pg_level_of(p_programme), 800) END;
        END IF;
        level_stated := coalesce(v_cl IN (700, 800, 900), false);
        IF v_cl IS NULL OR v_cl NOT IN (700, 800, 900) THEN v_cl := v_el; END IF;
    ELSE
        level_stated := coalesce(v_cl IN (100, 200, 300, 400, 500, 600), false);
        v_el := coalesce(v_el, CASE WHEN mode IN ('UTME', 'CCE') THEN 100 ELSE 200 END);
        v_cl := coalesce(v_cl, v_el);
        IF v_el NOT IN (100, 200, 300, 400, 500, 600) THEN v_el := 100; END IF;
        IF v_cl NOT IN (100, 200, 300, 400, 500, 600) THEN v_cl := v_el; END IF;
    END IF;
    entry_level := v_el;
    current_level := v_cl;
END $fn$;
COMMENT ON FUNCTION people.upload_levels(text, text, text, text) IS
  'V455: the entry mode and levels an old-portal upload files a row at — a postgraduate programme''s row (or one marked '
  'POSTGRADUATE, never CCE) POSTGRADUATE at 700/800/900 (the file''s, else its entry level, else people.pg_level_of); an '
  'undergraduate row at 100–600 as before. level_stated: the file gave a level of that kind (not a default).';

-- ── 1, 2 · both uploads read it, and keep a postgraduate student's level (restated from V381 and V294, changes marked V455) ──
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
                -- V455: a postgraduate student at a postgraduate level keeps it unless the file states one (never lowered
                -- below 700, never moved to a default); a postgraduate programme's row files a student wrongly filed as
                -- undergraduate POSTGRADUATE at its level
                current_level = CASE WHEN (people.student.entry_mode = 'POSTGRADUATE' OR EXCLUDED.entry_mode = 'POSTGRADUATE')
                                     AND people.student.current_level IN (700, 800, 900)
                                     AND (EXCLUDED.current_level < 700 OR NOT v_stated)
                                    THEN people.student.current_level ELSE EXCLUDED.current_level END,
                entry_mode = CASE WHEN EXCLUDED.entry_mode = 'POSTGRADUATE' AND people.student.entry_mode NOT IN ('POSTGRADUATE', 'CCE')
                                  THEN 'POSTGRADUATE' ELSE people.student.entry_mode END,
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
                -- V455: a postgraduate student at a postgraduate level keeps it unless the file states one (never lowered
                -- below 700, never moved to a default); a postgraduate programme's row files a student wrongly filed as
                -- undergraduate POSTGRADUATE at its level
                current_level = CASE WHEN (people.student.entry_mode = 'POSTGRADUATE' OR EXCLUDED.entry_mode = 'POSTGRADUATE')
                                     AND people.student.current_level IN (700, 800, 900)
                                     AND (EXCLUDED.current_level < 700 OR NOT v_stated)
                                    THEN people.student.current_level ELSE EXCLUDED.current_level END,
                entry_mode = CASE WHEN EXCLUDED.entry_mode = 'POSTGRADUATE' AND people.student.entry_mode NOT IN ('POSTGRADUATE', 'CCE')
                                  THEN 'POSTGRADUATE' ELSE people.student.entry_mode END,
                entry_level = CASE WHEN EXCLUDED.entry_mode = 'POSTGRADUATE' AND people.student.entry_mode NOT IN ('POSTGRADUATE', 'CCE')
                                        AND coalesce(people.student.entry_level, 0) < 700
                                   THEN EXCLUDED.entry_level ELSE people.student.entry_level END
            WHERE (people.student.surname, people.student.other_names, people.student.sex, people.student.date_of_birth,
                   people.student.state_of_origin, people.student.jamb_reg_no, people.student.programme_code, people.student.current_level,
                   people.student.entry_mode)
                  IS DISTINCT FROM (EXCLUDED.surname, EXCLUDED.other_names, coalesce(EXCLUDED.sex, people.student.sex),
                   coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth), coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                   coalesce(EXCLUDED.jamb_reg_no, people.student.jamb_reg_no), EXCLUDED.programme_code,
                   CASE WHEN (people.student.entry_mode = 'POSTGRADUATE' OR EXCLUDED.entry_mode = 'POSTGRADUATE')
                                     AND people.student.current_level IN (700, 800, 900)
                                     AND (EXCLUDED.current_level < 700 OR NOT v_stated)
                                    THEN people.student.current_level ELSE EXCLUDED.current_level END,
                   CASE WHEN EXCLUDED.entry_mode = 'POSTGRADUATE' AND people.student.entry_mode NOT IN ('POSTGRADUATE', 'CCE')
                        THEN 'POSTGRADUATE' ELSE people.student.entry_mode END);
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

-- ── 4 · the level a student was at in a session (restated from V330, the change marked V455) ──────────────────────────
CREATE OR REPLACE FUNCTION people.level_in(p_student uuid, p_session text, p_semester int DEFAULT NULL)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT r.level FROM registration.course_registration r
          WHERE r.student_id = p_student AND r.session = p_session AND (p_semester IS NULL OR r.semester = p_semester)
          ORDER BY (r.status IN ('APPROVED','LOCKED')) DESC, r.semester LIMIT 1),
        (SELECT r.level FROM registration.course_registration r
          WHERE r.student_id = p_student AND r.session = p_session
          ORDER BY (r.status IN ('APPROVED','LOCKED')) DESC, r.semester LIMIT 1),
        (SELECT e.level FROM people.enrolment e WHERE e.student_id = p_student AND e.session = p_session),
        (SELECT CASE WHEN people.is_postgraduate(st.entry_mode, pp.category) THEN st.current_level   -- V455: a postgraduate's level is their own
                     WHEN es.starts_on IS NOT NULL AND cs.starts_on IS NOT NULL AND cs.starts_on >= es.starts_on
                     THEN least(600, st.entry_level + 100 * (SELECT count(*)::int FROM policy.academic_session a WHERE a.starts_on > es.starts_on AND a.starts_on <= cs.starts_on))
                END
           FROM people.student st
           LEFT JOIN ref.programme pp ON pp.code = st.programme_code
           LEFT JOIN policy.academic_session es ON es.name = st.entry_session
           LEFT JOIN policy.academic_session cs ON cs.name = p_session
          WHERE st.id = p_student),
        (SELECT st.current_level FROM people.student st WHERE st.id = p_student))
$$;

-- ── 3 · repaired: the students of a postgraduate programme filed below 700 or not as POSTGRADUATE ─────────────────────
CREATE FUNCTION people.repair_postgraduate_levels()
RETURNS TABLE (repaired integer, filed_postgraduate integer, level_restored integer) LANGUAGE sql AS $fn$
    WITH bad AS (
        SELECT s.id, s.entry_mode, s.entry_level, s.current_level, people.pg_level_of(p.code) AS by_programme
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
         WHERE p.category = 'POST GRADUATE'
           AND s.entry_mode IS DISTINCT FROM 'CCE'
           AND (s.entry_mode IS DISTINCT FROM 'POSTGRADUATE' OR coalesce(s.entry_level, 0) < 700 OR coalesce(s.current_level, 0) < 700)),
    fixed AS (
        UPDATE people.student s
           SET entry_mode = 'POSTGRADUATE',
               entry_level = CASE WHEN b.entry_level IN (700, 800, 900) THEN b.entry_level
                                  WHEN b.current_level IN (700, 800, 900) THEN b.current_level
                                  ELSE b.by_programme END,
               current_level = CASE WHEN b.current_level IN (700, 800, 900) THEN b.current_level
                                    WHEN b.entry_level IN (700, 800, 900) THEN b.entry_level
                                    ELSE b.by_programme END
          FROM bad b
         WHERE s.id = b.id
        RETURNING b.entry_mode IS DISTINCT FROM 'POSTGRADUATE' AS mode_fixed, coalesce(b.current_level, 0) < 700 AS level_fixed)
    SELECT count(*)::int, (count(*) FILTER (WHERE mode_fixed))::int, (count(*) FILTER (WHERE level_fixed))::int FROM fixed
$fn$;
COMMENT ON FUNCTION people.repair_postgraduate_levels() IS
  'V455: every student of a postgraduate programme (not CCE) filed other than POSTGRADUATE or below 700 is filed POSTGRADUATE, '
  'the current level restored to the entry level when that is postgraduate, else the programme''s (people.pg_level_of). '
  'Returns how many, how many re-filed, how many levels restored. Run once by V455; safe to run again.';

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM people.repair_postgraduate_levels();
    RAISE NOTICE 'V455: % student(s) of a postgraduate programme repaired — % filed POSTGRADUATE, % restored to a postgraduate level',
                 r.repaired, r.filed_postgraduate, r.level_restored;
END $$;

COMMIT;
