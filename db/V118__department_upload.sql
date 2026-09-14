-- ═══════════════════════════════════════════════════════════════════════════
-- V118 — create and upload departments
--
--   Faculties (V091) and programmes (V091) can be created and uploaded; a
--   department could only be born as a side effect of a programme upload. This
--   gives the department its own desk: create one, upload a list, or remove an
--   empty one — the same shape as faculties, resolving the faculty by code or
--   name and never duplicating on a re-upload.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- one department, upserted under its faculty (by code or by name)
CREATE OR REPLACE FUNCTION ref.upsert_department(p_code text, p_name text, p_faculty text)
RETURNS ref.department
LANGUAGE plpgsql AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, ''))); v_fac text; r ref.department;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a department is created by a person' USING ERRCODE = '23514';
    END IF;
    IF v_code = '' THEN RAISE EXCEPTION 'a department has a code' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'a department has a name' USING ERRCODE = '23514'; END IF;

    SELECT code INTO v_fac FROM ref.faculty WHERE upper(code) = upper(btrim(coalesce(p_faculty, '')));
    IF v_fac IS NULL THEN SELECT code INTO v_fac FROM ref.faculty WHERE upper(name) = upper(btrim(coalesce(p_faculty, ''))) LIMIT 1; END IF;
    IF v_fac IS NULL THEN
        RAISE EXCEPTION 'no faculty is coded or named % — create the faculty first', p_faculty USING ERRCODE = '23503';
    END IF;

    INSERT INTO ref.department (code, name, faculty_code)
    VALUES (v_code, btrim(p_name), v_fac)
    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, faculty_code = EXCLUDED.faculty_code
    RETURNING * INTO r;
    RETURN r;
END $$;

-- a list of departments: rows of code, name, faculty
CREATE OR REPLACE FUNCTION ref.import_departments(p_rows jsonb)
RETURNS TABLE (rows int, saved int, bad_code int, no_faculty int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_code text; v_name text; v_fac text;
        n int := 0; ns int := 0; nb int := 0; nnf int := 0;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'departments are loaded by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'the file is rows: department code, name, faculty' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_code := upper(btrim(coalesce(r->>'code', r->>'departmentCode', r->>'department_code', r->>'deptCode', '')));
        IF v_code = '' OR v_code ~* '^(department\s*)?code$' THEN CONTINUE; END IF;   -- blank or a header row
        n := n + 1;
        v_name := btrim(coalesce(r->>'name', r->>'department', r->>'departmentName', r->>'dept', ''));
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', r->>'facultyName', ''));
        IF v_name = '' THEN nb := nb + 1; CONTINUE; END IF;
        IF NOT EXISTS (SELECT 1 FROM ref.faculty f WHERE upper(f.code) = upper(v_fac) OR upper(f.name) = upper(v_fac)) THEN
            nnf := nnf + 1; CONTINUE;
        END IF;
        PERFORM ref.upsert_department(v_code, v_name, v_fac);
        ns := ns + 1;
    END LOOP;
    RETURN QUERY SELECT n, ns, nb, nnf;
END $$;

-- remove a department, but only when nothing hangs on it
CREATE OR REPLACE FUNCTION ref.delete_department(p_code text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, '')));
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a department is removed by a person' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM ref.department WHERE code = v_code) THEN
        RAISE EXCEPTION 'no department is coded %', p_code USING ERRCODE = '23503';
    END IF;
    IF EXISTS (SELECT 1 FROM ref.programme WHERE dept_code = v_code) THEN
        RAISE EXCEPTION 'department % still has programmes — remove or move them first', v_code USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course WHERE dept_code = v_code) THEN
        RAISE EXCEPTION 'department % still carries courses — remove them first', v_code USING ERRCODE = '23514';
    END IF;
    DELETE FROM ref.department WHERE code = v_code;
END $$;

COMMIT;
