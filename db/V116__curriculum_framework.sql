-- ═══════════════════════════════════════════════════════════════════════════
-- V116 — record the curriculum framework (CCMAS / BMAS)
--
--   A course structure is uploaded under a framework — the NUC's current CCMAS,
--   or the older BMAS. We record which on the course, and stamp each student's
--   curriculum from the session they entered (CCMAS from 2023/2024, the national
--   start; BMAS before). This only RECORDS the split — registration still draws
--   from the one structure a programme carries. The cutover lives in one
--   function, people.curriculum_of, so it can be changed in a later migration.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- 1 · the framework a course was defined under
ALTER TABLE catalogue.course ADD COLUMN IF NOT EXISTS curriculum text;
ALTER TABLE catalogue.course DROP CONSTRAINT IF EXISTS ck_course_curriculum;
ALTER TABLE catalogue.course ADD CONSTRAINT ck_course_curriculum
    CHECK (curriculum IS NULL OR curriculum IN ('CCMAS', 'BMAS'));

-- 2 · the framework a student sits under, by the session they entered
CREATE OR REPLACE FUNCTION people.curriculum_of(p_session text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_session IS NULL OR p_session !~ '^[0-9]{4}/[0-9]{4}$' THEN NULL
        WHEN p_session >= '2023/2024' THEN 'CCMAS'
        ELSE 'BMAS' END
$$;

-- fill it on every insert path (intake, migration imports, future) when not given
CREATE OR REPLACE FUNCTION people.fill_curriculum() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.curriculum_version IS NULL THEN
        NEW.curriculum_version := people.curriculum_of(NEW.entry_session);
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_student_curriculum ON people.student;
CREATE TRIGGER trg_student_curriculum BEFORE INSERT ON people.student
    FOR EACH ROW EXECUTE FUNCTION people.fill_curriculum();

-- backfill the students already on the register
UPDATE people.student SET curriculum_version = people.curriculum_of(entry_session)
 WHERE curriculum_version IS NULL AND entry_session ~ '^[0-9]{4}/[0-9]{4}$';

-- 3 · the importer records the framework of the structure it loads
DROP FUNCTION IF EXISTS catalogue.import_courses(text, jsonb);
CREATE FUNCTION catalogue.import_courses(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL)
RETURNS TABLE (rows int, courses int, offers int, no_dept int, bad_code int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int; v_curr text;
        n int := 0; nc int := 0; no int := 0; nnd int := 0; nb int := 0; ns int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a course upload is made by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: course code, title, units, status, level, semester' USING ERRCODE = '23514';
    END IF;
    v_curr := upper(nullif(btrim(coalesce(p_curriculum, '')), ''));
    IF v_curr IS NOT NULL AND v_curr NOT IN ('CCMAS', 'BMAS') THEN v_curr := NULL; END IF;
    SELECT code, dept_code INTO v_prog, v_dept FROM ref.programme
     WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
    IF v_prog IS NULL THEN RAISE EXCEPTION 'no programme is coded or named %', p_programme USING ERRCODE = '23503'; END IF;
    IF v_dept IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department WHERE code = v_dept) THEN
        RAISE EXCEPTION 'the programme % has no department on the register to own its courses', v_prog USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_code := regexp_replace(upper(btrim(coalesce(r->>'code', r->>'courseCode', r->>'course_code', ''))), '\s+', ' ', 'g');
        IF v_code = '' OR v_code ~* '^course\s*code$' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN nb := nb + 1; CONTINUE; END IF;

        BEGIN
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

            INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, lecture_hours, practical_hours, curriculum)
            VALUES (v_code, v_title, v_units, v_sem, v_level, v_dept, v_kind, v_lh, v_ph, v_curr)
            ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units, semester = EXCLUDED.semester,
                level = EXCLUDED.level, kind = EXCLUDED.kind, lecture_hours = EXCLUDED.lecture_hours, practical_hours = EXCLUDED.practical_hours,
                curriculum = coalesce(EXCLUDED.curriculum, catalogue.course.curriculum);

            INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis)
            VALUES (v_code, v_prog, v_level, v_basis)
            ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis;

            nc := nc + 1;
            no := no + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_code || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, no, nnd, nb, ns, v_firsterr;
END $$;

COMMIT;
