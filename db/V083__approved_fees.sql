-- ═══════════════════════════════════════════════════════════════════════════
-- V083 — the approved fees structure: by faculty, level, semester and indigeneship
--
--   Council approves a fees structure that differs by faculty, by level (with a
--   Direct-Entry band), by semester, and by whether the student is an indigene
--   of the State the University sits in. The Bursary uploads the approved table
--   and the portal charges each student the cell that is theirs. The session
--   charge is the sum of the student's semesters, as the structure's own Total
--   column is — so nothing in how a session is paid or cleared changes; the
--   semester is a label on each line, and the indigene split is a filter.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'Approved fees by faculty, level, semester and indigeneship (V083)', true);

-- ── 1 · the indigene dimension on a fee line (the semester column already exists, V055) ──
ALTER TABLE finance.fee_schedule ADD COLUMN IF NOT EXISTS indigene text NULL;
ALTER TABLE finance.fee_schedule
    DROP CONSTRAINT IF EXISTS ck_fee_indigene,
    ADD CONSTRAINT ck_fee_indigene CHECK (indigene IS NULL OR indigene IN ('INDIGENE', 'NON_INDIGENE'));

-- a student's state of origin, for the indigene fee; for a portal-admitted student it is on the CAPS row,
-- for a migrated student it comes over in the biodata import
ALTER TABLE people.student ADD COLUMN IF NOT EXISTS state_of_origin text NULL;

-- the University's own State: an indigene is of this State (a setting the Bursary can change)
CREATE TABLE IF NOT EXISTS finance.fee_setting (
    id           int PRIMARY KEY DEFAULT 1,
    home_state   text NOT NULL DEFAULT 'Benue',
    CONSTRAINT ck_fee_setting_one CHECK (id = 1)
);
INSERT INTO finance.fee_setting (id, home_state) VALUES (1, 'Benue') ON CONFLICT (id) DO NOTHING;

-- ── 2 · charges now also pick the student's indigeneship cell (keeping V055's group + open-semester rule) ──
CREATE OR REPLACE FUNCTION finance.charges(p_student uuid, p_session text)
RETURNS TABLE (id uuid, item text, amount numeric, ord int)
LANGUAGE sql STABLE AS $$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT f.id, f.item, f.amount, f.ord
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND (f.level IS NULL OR f.level = me.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = me.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL
            OR f.semester = (SELECT sm.number FROM policy.semester sm
                              WHERE sm.session = p_session AND sm.state = 'OPEN'
                              ORDER BY sm.number LIMIT 1))
     ORDER BY f.ord, f.item;
$$;

-- the whole session's fee for the student — both semesters summed — for the student who pays the full session at once
CREATE OR REPLACE FUNCTION finance.session_fee_total(p_student uuid, p_session text)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT coalesce(sum(f.amount), 0)
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND (f.level IS NULL OR f.level = me.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = me.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)));
$$;

-- ── 3 · the importer: the approved table, as rows the Bursary sends ──
-- Each row is one cell of the structure: a faculty (code or name), a level, an entry mode, a semester,
-- an indigeneship and the amount. Uploading replaces the session's approved structure (the previous one is ended).
CREATE OR REPLACE FUNCTION finance.import_fee_structure(p_session text, p_rows jsonb)
RETURNS TABLE (rows int, lines int, faculties int, no_faculty int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_fac text; v_fac_code text; v_level int; v_mode text; v_sem int; v_ind text; v_amt numeric; v_item text; v_ord int;
        n int := 0; nl int := 0; nnf int := 0; facs text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a fees structure is uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: faculty, level, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    -- replace the session's approved structure: end what stands, then load the new
    UPDATE finance.fee_schedule SET ended_at = now() WHERE session = p_session AND ended_at IS NULL;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amt IS NULL OR v_amt < 0 THEN CONTINUE; END IF;
        n := n + 1;
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', ''));
        v_fac_code := NULL;
        IF v_fac <> '' THEN
            SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(code) = upper(v_fac);
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) = upper(v_fac) LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) LIKE '%' || upper(v_fac) || '%' LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN nnf := nnf + 1; END IF;
        END IF;
        v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_level IS NOT NULL AND v_level NOT IN (100,200,300,400,500,600) THEN v_level := NULL; END IF;
        v_mode := nullif(upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', ''))), '');
        IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH') THEN v_mode := NULL; END IF;
        v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_sem IS NOT NULL AND v_sem NOT IN (1,2,3) THEN v_sem := NULL; END IF;
        v_ind := upper(btrim(coalesce(r->>'indigene', '')));
        v_ind := CASE WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' ELSE NULL END;
        v_item := nullif(btrim(coalesce(r->>'item', '')), '');
        IF v_item IS NULL THEN v_item := 'School fees' || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END; END IF;
        v_ord := coalesce(nullif(regexp_replace(coalesce(r->>'ord', ''), '[^0-9]', '', 'g'), '')::int, coalesce(v_sem, 1));

        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, semester, indigene, ord)
        VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac_code, v_sem, v_ind, v_ord);
        nl := nl + 1;
        IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY(facs)) THEN facs := facs || v_fac_code; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nl, cardinality(facs), nnf;
END $$;

-- the student biodata import (V082) now also carries the state of origin, so the indigene fee applies
CREATE OR REPLACE FUNCTION people.import_students(p_rows jsonb)
RETURNS TABLE (rows int, created int, updated int, no_programme int, bad_number int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_mode text; v_es text; v_el int; v_cl int;
        v_surname text; v_others text; v_yy text; v_exists boolean; v_state text;
        n int := 0; nc int := 0; nu int := 0; nnp int := 0; nbn int := 0;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, name, programme, level' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_matric !~ '^MOAUM/[A-Z]{2,4}/[0-9]{2}/[0-9]{4}$' THEN nbn := nbn + 1; CONTINUE; END IF;

        v_prog := btrim(coalesce(r->>'programme', r->>'programmeCode', r->>'programme_code', r->>'course', ''));
        SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
        IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived, code LIMIT 1; END IF;
        IF v_prog_code IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;

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
        v_yy := split_part(v_matric, '/', 3);
        v_es := coalesce(nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', '')), ''), '20' || v_yy || '/20' || lpad((v_yy::int + 1)::text, 2, '0'));
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
    END LOOP;
    RETURN QUERY SELECT n, nc, nu, nnp, nbn;
END $$;

-- what was uploaded, for the Bursary to read back
CREATE OR REPLACE FUNCTION finance.fee_structure(p_session text)
RETURNS TABLE (faculty_code text, faculty_name text, level int, entry_mode text, semester int, indigene text, item text, amount numeric)
LANGUAGE sql STABLE AS $$
    SELECT f.faculty_code, fac.name, f.level, f.entry_mode, f.semester, f.indigene, f.item, f.amount
      FROM finance.fee_schedule f LEFT JOIN ref.faculty fac ON fac.code = f.faculty_code
     WHERE f.session = p_session AND f.ended_at IS NULL
     ORDER BY fac.name NULLS FIRST, f.level, f.semester, f.indigene, f.item
$$;

COMMIT;
