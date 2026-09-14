-- ═══════════════════════════════════════════════════════════════════════════
-- V114 — the core students import: admit legacy matrics, and survive a bad row
--
--   people.import_students (the "students, core only" tab) still took only the
--   University's own matric shape and derived the entry session by casting the
--   third segment to an int — which crashes on a legacy number (BSU/BM/RAD/21/
--   2204 → 'RAD'::int). It now accepts the legacy shape like the biography
--   import (V098/V111), derives the session safely, and wraps each row in a
--   savepoint so one bad row is skipped and counted, not fatal.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP FUNCTION IF EXISTS people.import_students(jsonb);
CREATE FUNCTION people.import_students(p_rows jsonb)
RETURNS TABLE (rows int, created int, updated int, no_programme int, bad_number int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_mode text; v_es text; v_el int; v_cl int;
        v_surname text; v_others text; v_exists boolean; v_state text;
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
            v_mode := upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', 'UTME')));
            IF v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH') THEN v_mode := 'UTME'; END IF;

            -- the entry session: from the file, else derived from the University's own number, else a default
            v_es := nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', '')), '');
            IF v_es IS NULL OR v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN
                IF v_matric ~ '^MOAUM/' THEN
                    v_es := '20' || split_part(v_matric, '/', 3) || '/20' || lpad(((split_part(v_matric, '/', 3))::int + 1)::text, 2, '0');
                ELSE
                    v_es := coalesce(v_es, '2000/2001');
                END IF;
            END IF;
            IF v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN v_es := '2000/2001'; END IF;

            v_el := coalesce(nullif(regexp_replace(coalesce(r->>'entryLevel', r->>'entry_level', ''), '[^0-9]', '', 'g'), '')::int, CASE WHEN v_mode = 'UTME' THEN 100 ELSE 200 END);
            v_cl := coalesce(nullif(regexp_replace(coalesce(r->>'level', r->>'currentLevel', r->>'current_level', ''), '[^0-9]', '', 'g'), '')::int, v_el);
            IF v_el NOT IN (100,200,300,400,500,600) THEN v_el := 100; END IF;
            IF v_cl NOT IN (100,200,300,400,500,600) THEN v_cl := v_el; END IF;

            SELECT true INTO v_exists FROM people.student WHERE upper(matric_no) = v_matric;
            INSERT INTO people.student (id, matric_no, surname, other_names, sex, date_of_birth, state_of_origin, programme_code, entry_mode,
                                        entry_session, entry_level, current_level, status, matriculated_at)
            VALUES (gen_random_uuid(), v_matric, v_surname, v_others, v_sex, v_dob, v_state, v_prog_code, v_mode, v_es, v_el, v_cl, 'ACTIVE', now())
            ON CONFLICT (matric_no) DO UPDATE SET surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
                sex = coalesce(EXCLUDED.sex, people.student.sex), date_of_birth = coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth),
                state_of_origin = coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                programme_code = EXCLUDED.programme_code, current_level = EXCLUDED.current_level;
            IF coalesce(v_exists, false) THEN nu := nu + 1; ELSE nc := nc + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, nu, nnp, nbn, ns, v_firsterr;
END $$;

COMMIT;
