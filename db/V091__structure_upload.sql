-- ═══════════════════════════════════════════════════════════════════════════
-- V091 — create and upload the academic structure: faculties and programmes
--
--   Until now faculties and programmes were seeded by migration only. The
--   Directorate of ICT and the Academic Office can now create them from the
--   portal, one at a time or in bulk from a spreadsheet, the same way courses
--   are loaded. A programme resolves its faculty (by code or name) and its
--   department, creating the department under the faculty when it does not yet
--   exist; a blank department defaults to the faculty itself.
--
--   Every write is attributed on the audit spine (ref.faculty, ref.department
--   and ref.programme are already attached). Re-loading updates rather than
--   duplicates. Nothing is deleted here.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── faculties ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ref.upsert_faculty(p_code text, p_name text)
RETURNS ref.faculty
LANGUAGE plpgsql AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, ''))); r ref.faculty;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a faculty is created by a person' USING ERRCODE = '23514';
    END IF;
    IF v_code = '' THEN RAISE EXCEPTION 'a faculty has a code' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'a faculty has a name' USING ERRCODE = '23514'; END IF;
    INSERT INTO ref.faculty (code, name) VALUES (v_code, btrim(p_name))
    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name
    RETURNING * INTO r;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION ref.import_faculties(p_rows jsonb)
RETURNS TABLE (rows int, saved int, bad int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_code text; v_name text; n int := 0; ns int := 0; nb int := 0;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'faculties are loaded by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'the file is rows: faculty code and name' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_code := upper(btrim(coalesce(r->>'code', r->>'facultyCode', r->>'faculty_code', '')));
        v_name := btrim(coalesce(r->>'name', r->>'faculty', r->>'facultyName', ''));
        IF v_code = '' OR v_code ~* '^(faculty\s*)?code$' THEN CONTINUE; END IF;   -- blank or a header row
        n := n + 1;
        IF v_name = '' THEN nb := nb + 1; CONTINUE; END IF;
        PERFORM ref.upsert_faculty(v_code, v_name);
        ns := ns + 1;
    END LOOP;
    RETURN QUERY SELECT n, ns, nb;
END $$;

-- ── programmes (with their faculty and department) ───────────────────────────
CREATE OR REPLACE FUNCTION ref.upsert_programme(
    p_code text, p_name text, p_faculty text, p_dept_code text, p_dept_name text, p_category text, p_min_score int)
RETURNS ref.programme
LANGUAGE plpgsql AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, ''))); v_fac text; v_dept text; v_cat text; r ref.programme;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a programme is created by a person' USING ERRCODE = '23514';
    END IF;
    IF v_code !~ '^C[0-9]{5}$' THEN
        RAISE EXCEPTION 'a programme code is C followed by five digits, e.g. C00061' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'a programme has a name' USING ERRCODE = '23514'; END IF;

    -- the faculty: by code, else by name
    SELECT code INTO v_fac FROM ref.faculty WHERE upper(code) = upper(btrim(coalesce(p_faculty, '')));
    IF v_fac IS NULL THEN SELECT code INTO v_fac FROM ref.faculty WHERE upper(name) = upper(btrim(coalesce(p_faculty, ''))) LIMIT 1; END IF;
    IF v_fac IS NULL THEN
        RAISE EXCEPTION 'no faculty is coded or named % — create the faculty first', p_faculty USING ERRCODE = '23503';
    END IF;

    -- the department: the code given, or the faculty itself as a default; created under the faculty if new
    v_dept := upper(nullif(btrim(coalesce(p_dept_code, '')), ''));
    IF v_dept IS NULL THEN v_dept := v_fac; END IF;
    INSERT INTO ref.department (code, name, faculty_code)
    VALUES (v_dept, coalesce(nullif(btrim(p_dept_name), ''), (SELECT name FROM ref.faculty WHERE code = v_fac)), v_fac)
    ON CONFLICT (code) DO NOTHING;

    v_cat := upper(btrim(coalesce(p_category, '')));
    v_cat := CASE WHEN v_cat LIKE 'POST%' OR v_cat LIKE 'PG%' THEN 'POST GRADUATE' ELSE 'UNDER GRADUATE' END;

    INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category)
    VALUES (v_code, btrim(p_name), v_dept, v_fac, coalesce(p_min_score, 0), false, v_cat)
    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, dept_code = EXCLUDED.dept_code,
        faculty_code = EXCLUDED.faculty_code, min_score = EXCLUDED.min_score, category = EXCLUDED.category
    RETURNING * INTO r;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION ref.import_programmes(p_rows jsonb)
RETURNS TABLE (rows int, saved int, bad_code int, no_faculty int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_code text; v_name text; v_fac text; v_ms int;
        n int := 0; ns int := 0; nb int := 0; nnf int := 0;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'programmes are loaded by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'the file is rows: programme code, name, faculty' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_code := upper(btrim(coalesce(r->>'code', r->>'programmeCode', r->>'programme_code', '')));
        IF v_code = '' OR v_code ~* '^(programme\s*)?code$' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_code !~ '^C[0-9]{5}$' THEN nb := nb + 1; CONTINUE; END IF;
        v_name := btrim(coalesce(r->>'name', r->>'programme', r->>'programmeName', ''));
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', r->>'facultyName', ''));
        v_ms := nullif(regexp_replace(coalesce(r->>'minScore', r->>'min_score', r->>'minimum', ''), '[^0-9]', '', 'g'), '')::int;
        IF NOT EXISTS (SELECT 1 FROM ref.faculty f WHERE upper(f.code) = upper(v_fac) OR upper(f.name) = upper(v_fac)) THEN
            nnf := nnf + 1; CONTINUE;
        END IF;
        PERFORM ref.upsert_programme(v_code, v_name, v_fac,
            coalesce(r->>'departmentCode', r->>'department_code', r->>'deptCode', ''),
            coalesce(r->>'department', r->>'departmentName', r->>'dept', ''),
            coalesce(r->>'category', ''), v_ms);
        ns := ns + 1;
    END LOOP;
    RETURN QUERY SELECT n, ns, nb, nnf;
END $$;

COMMIT;
