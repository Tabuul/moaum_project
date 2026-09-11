-- ═══════════════════════════════════════════════════════════════════════════
-- V084 — uploading a department's courses (a CCMAS programme structure)
--
--   The Directorate of ICT (and the Super Administrator) load a department's
--   approved course structure, and an HOD loads their own department's. The
--   source is the programme's CCMAS table: course code, title, units, status,
--   lecture and practical hours, grouped by level and semester. Each course is
--   created in the catalogue and offered to the programme at its level.
--
--   CCMAS codes are not all "ABC 123" — some are "BSU-SOC-107". The code rule
--   is relaxed to accept them as they are, so a code matches what the student
--   and the lecturer already know. Lecture and practical hours are kept on the
--   course.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- accept the CCMAS code forms (BSU-SOC-107, SSC 202) alongside the classic ABC 123
ALTER TABLE catalogue.course DROP CONSTRAINT ck_course_code;
ALTER TABLE catalogue.course ADD CONSTRAINT ck_course_code CHECK (code ~ '^[A-Z][A-Z0-9 /-]{2,19}$');

ALTER TABLE catalogue.course ADD COLUMN IF NOT EXISTS lecture_hours   int NULL;
ALTER TABLE catalogue.course ADD COLUMN IF NOT EXISTS practical_hours int NULL;

-- the importer: one programme's course structure, as rows from the CCMAS document
CREATE OR REPLACE FUNCTION catalogue.import_courses(p_programme text, p_rows jsonb)
RETURNS TABLE (rows int, courses int, offers int, no_dept int, bad_code int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int;
        n int := 0; nc int := 0; no int := 0; nnd int := 0; nb int := 0;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a course upload is made by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: course code, title, units, status, level, semester' USING ERRCODE = '23514';
    END IF;
    SELECT code, dept_code INTO v_prog, v_dept FROM ref.programme
     WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
    IF v_prog IS NULL THEN RAISE EXCEPTION 'no programme is coded or named %', p_programme USING ERRCODE = '23503'; END IF;
    IF v_dept IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department WHERE code = v_dept) THEN
        RAISE EXCEPTION 'the programme % has no department on the register to own its courses', v_prog USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_code := regexp_replace(upper(btrim(coalesce(r->>'code', r->>'courseCode', r->>'course_code', ''))), '\s+', ' ', 'g');
        IF v_code = '' OR v_code ~* '^course\s*code$' THEN CONTINUE; END IF;   -- blank or a header row
        n := n + 1;
        IF v_code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN nb := nb + 1; CONTINUE; END IF;
        v_title := nullif(btrim(coalesce(r->>'title', r->>'courseTitle', '')), '');
        IF v_title IS NULL THEN v_title := v_code; END IF;
        v_units := least(coalesce(nullif(regexp_replace(coalesce(r->>'units', ''), '[^0-9]', '', 'g'), '')::int, 0), 12);
        v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, 100);
        IF v_level NOT IN (100,200,300,400,500,600) THEN v_level := 100; END IF;
        v_sem := coalesce(nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int, 1);
        IF v_sem NOT IN (1,2,3) THEN v_sem := 1; END IF;
        v_lh := nullif(regexp_replace(coalesce(r->>'lh', r->>'LH', ''), '[^0-9]', '', 'g'), '')::int;
        v_ph := nullif(regexp_replace(coalesce(r->>'ph', r->>'PH', ''), '[^0-9]', '', 'g'), '')::int;
        v_status := upper(left(btrim(coalesce(r->>'status', 'C')), 1));
        v_kind := CASE WHEN v_code LIKE 'GST %' OR v_code LIKE 'GST%' THEN 'GST'
                       WHEN v_status = 'R' THEN 'Required' WHEN v_status = 'E' THEN 'Elective' ELSE 'Compulsory' END;
        v_basis := CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Core' END;

        INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, lecture_hours, practical_hours)
        VALUES (v_code, v_title, v_units, v_sem, v_level, v_dept, v_kind, v_lh, v_ph)
        ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units, semester = EXCLUDED.semester,
            level = EXCLUDED.level, kind = EXCLUDED.kind, lecture_hours = EXCLUDED.lecture_hours, practical_hours = EXCLUDED.practical_hours;
        nc := nc + 1;
        INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis)
        VALUES (v_code, v_prog, v_level, v_basis)
        ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis;
        no := no + 1;
    END LOOP;
    RETURN QUERY SELECT n, nc, no, nnd, nb;
END $$;

COMMIT;
