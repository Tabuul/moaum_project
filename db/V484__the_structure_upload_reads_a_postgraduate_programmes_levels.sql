-- ═══════════════════════════════════════
-- V484 — The structure upload reads a postgraduate programme's levels and bases
--
-- The course structure upload (catalogue.import_courses, V386, V460) read every row's level as 100 to 600 and put anything
-- else at 100, and knew a course only as Core, Required, Elective or GST: a postgraduate programme's structure loaded through
-- it put an 800-level course at 100 level. catalogue.import_courses_rows is restated from its current definition with one
-- change of rule: for a postgraduate programme a row's level is 700, 800 or 900 (the programme's own award level when the row
-- gives none, or one outside them), and its status may say Deficiency (D, DEF…) or Research (RES…, THESIS, DISSERTATION,
-- PROJECT), the course then a core course of the pool taken on that basis. An undergraduate programme's rows are read as
-- before, to the letter.
--
-- No course or binding is changed by this migration; the next upload of a postgraduate programme reads its levels.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V484: the structure upload reads a postgraduate programme''s levels and bases', true);

CREATE OR REPLACE FUNCTION catalogue.import_courses_rows(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL)
 RETURNS TABLE(rows integer, courses integer, offers integer, no_dept integer, bad_code integer, skipped integer, first_error text, existing integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int; v_curr text; v_owner text; v_status_raw text; v_class text; v_eps boolean; v_both boolean;
        v_pg boolean; v_pg_level int; v_pg_basis text;
        n int := 0; nc int := 0; no int := 0; nnd int := 0; nb int := 0; ns int := 0; ne int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a course upload is made by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: course code, title, units, status, level, semester' USING ERRCODE = '23514';
    END IF;
    v_curr := upper(nullif(btrim(coalesce(p_curriculum, '')), ''));
    IF v_curr IS NOT NULL AND v_curr NOT IN ('CCMAS', 'BMAS') THEN v_curr := NULL; END IF;
    SELECT code, dept_code, category = 'POST GRADUATE', CASE WHEN category = 'POST GRADUATE' THEN admissions.pg_award_level(pg_award) END
      INTO v_prog, v_dept, v_pg, v_pg_level FROM ref.programme
     WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
    IF v_prog IS NULL THEN RAISE EXCEPTION 'no programme is coded or named %', p_programme USING ERRCODE = '23503'; END IF;
    IF v_dept IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department WHERE code = v_dept) THEN
        RAISE EXCEPTION 'the programme % has no department on the register to own its courses', v_prog USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_code := regexp_replace(upper(btrim(coalesce(r->>'code', r->>'courseCode', r->>'course_code', ''))), '\s+', ' ', 'g');
        IF v_code = '' OR v_code ~* '^course\s*code$' THEN CONTINUE; END IF;
        -- V386: the course the pool holds, however the code is written (CSC101, a merged code, a session copy); a new one in the normal form
        v_code := coalesce(catalogue.resolve_course_code(v_code), v_code);
        n := n + 1;
        IF v_code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN nb := nb + 1; CONTINUE; END IF;

        BEGIN
            v_title := nullif(btrim(coalesce(r->>'title', r->>'courseTitle', '')), '');
            IF v_title IS NULL THEN v_title := v_code; END IF;
            v_units := least(coalesce(nullif(regexp_replace(coalesce(r->>'units', ''), '[^0-9]', '', 'g'), '')::int, 0), 12);
            -- V484: a postgraduate programme's levels are 700, 800 and 900 (the programme's own award level when the row gives
            -- none, or one outside them); an undergraduate programme's 100 to 600, as before
            IF v_pg THEN
                v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, v_pg_level);
                IF v_level NOT IN (700, 800, 900) THEN v_level := v_pg_level; END IF;
            ELSE
                v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, 100);
                IF v_level NOT IN (100,200,300,400,500,600) THEN v_level := 100; END IF;
            END IF;
            v_both := catalogue.both_semesters_text(r->>'semester');   -- V386: "Both", "1 & 2"
            v_sem := CASE WHEN v_both THEN 1 ELSE coalesce(nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int, 1) END;
            IF v_sem NOT IN (1,2,3) THEN v_sem := 1; END IF;
            v_lh := nullif(regexp_replace(coalesce(r->>'lh', r->>'LH', ''), '[^0-9]', '', 'g'), '')::int;
            v_ph := nullif(regexp_replace(coalesce(r->>'ph', r->>'PH', ''), '[^0-9]', '', 'g'), '')::int;
            -- V370: the status is read whole before its first letter, so EPS is not taken for E (Elective); EPS, or a GST/EPS
            -- classification column, makes the course general, and EPS files it with the EPS office
            v_status_raw := upper(btrim(coalesce(r->>'status', 'C')));
            v_class := upper(nullif(btrim(coalesce(r->>'classification', r->>'gstEps', '')), ''));
            v_eps := v_status_raw = 'EPS' OR v_class = 'EPS';
            v_status := CASE WHEN v_status_raw IN ('GST', 'EPS') OR v_class IN ('GST', 'EPS') THEN 'G' ELSE upper(left(v_status_raw, 1)) END;
            v_kind := CASE WHEN v_code LIKE 'GST %' OR v_code LIKE 'GST%' THEN 'GST'
                           WHEN v_status = 'G' THEN 'GST'  -- GST/EPS courses carried by status, not a GST code
                           WHEN v_status = 'R' THEN 'Required' WHEN v_status = 'E' THEN 'Elective' ELSE 'Core' END;
            v_basis := CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Core' END;
            -- V484: a postgraduate programme takes a course as Deficiency or Research where the row says so (D, DEF…, RES…,
            -- THESIS, DISSERTATION, PROJECT); such a course is a core course of the pool, its basis the programme's
            v_pg_basis := CASE WHEN NOT v_pg THEN NULL
                               WHEN v_status_raw ~ '^(D$|DEF)' THEN 'Deficiency'
                               WHEN v_status_raw ~ '^(RES|THES|DISS|PROJ)' THEN 'Research' END;
            IF v_pg_basis IS NOT NULL THEN v_kind := 'Core'; v_basis := v_pg_basis; END IF;
            IF v_pg AND v_kind = 'Required' THEN v_kind := 'Core'; END IF;

            SELECT dept_code INTO v_owner FROM catalogue.course WHERE code = v_code;
            IF v_owner IS NOT NULL AND v_owner <> v_dept THEN
                -- V332: another department's course, carried by this programme: one course, bound as Borrowed
                -- (or on the basis the row says where it is GST or Elective); its title, units and level are its owner's to set
                v_basis := coalesce(v_pg_basis, CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Borrowed' END);
                ne := ne + 1;
            ELSE
                INSERT INTO catalogue.course (code, title, units, semester, both_semesters, level, dept_code, kind, lecture_hours, practical_hours, curriculum, state, general_office)
                VALUES (v_code, v_title, v_units, v_sem, v_both, v_level, v_dept, v_kind, v_lh, v_ph, v_curr, 'LIVE', CASE WHEN v_eps THEN 'EPS' END)
                -- V460: an existing course keeps its units; a programme whose file says otherwise gets its own on its binding
                ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = catalogue.course.units, semester = EXCLUDED.semester, both_semesters = EXCLUDED.both_semesters,
                    level = EXCLUDED.level, kind = EXCLUDED.kind, lecture_hours = EXCLUDED.lecture_hours, practical_hours = EXCLUDED.practical_hours,
                    curriculum = coalesce(EXCLUDED.curriculum, catalogue.course.curriculum),
                    state = CASE WHEN catalogue.course.state IN ('BOARD', 'SENATE') OR catalogue.course.reset_batch_id IS NOT NULL THEN 'LIVE' ELSE catalogue.course.state END,
                    ended_on = CASE WHEN catalogue.course.reset_batch_id IS NOT NULL THEN NULL ELSE catalogue.course.ended_on END,
                    reset_batch_id = NULL,
                    -- V370: EPS files a course no office holds with the EPS office; an office's course stays the office's
                    general_office = CASE WHEN catalogue.course.general_office IS NULL THEN EXCLUDED.general_office ELSE catalogue.course.general_office END;
                nc := nc + 1;
            END IF;

            -- V460: the programme takes the course at the file's units where they differ from the course's
            INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, added_by, source, units)
            VALUES (v_code, v_prog, v_level, v_basis, v_actor, 'IMPORT',
                    CASE WHEN v_units > 0 AND v_units IS DISTINCT FROM (SELECT c.units FROM catalogue.course c WHERE c.code = v_code) THEN v_units END)
            ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis, units = EXCLUDED.units;

            no := no + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_code || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, no, nnd, nb, ns, v_firsterr, ne;
END $function$;
COMMENT ON FUNCTION catalogue.import_courses_rows(text, jsonb, text) IS
  'V386, V460, V484: one programme''s course structure loaded — each course created or found in the pool and bound at its level; V484: a postgraduate programme''s rows at 700, 800 or 900 and as Deficiency or Research where the status says so.';

COMMIT;
