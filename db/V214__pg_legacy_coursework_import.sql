-- ═══════════════════════════════════════════════════════════════════════════
-- V214 — the postgraduate coursework migration from the old portal
--
--   The undergraduate legacy import (V204, assessment.import_legacy_semester)
--   writes the shared engine: catalogue.course, registration.*, assessment.score
--   — graded with the University's undergraduate bands. Postgraduate coursework is
--   kept in its own module (V211: admissions.pg_course / pg_registration /
--   pg_score) and graded on its own scale (A 70+, B 60–59, C 50–59, F below 50;
--   no D/E). So a postgraduate's past registration and results, brought over from
--   the old portal, must land in the POSTGRADUATE tables — otherwise a migrated
--   postgraduate shows a blank CGPA on the register and empty coursework pages,
--   and is graded on the wrong scheme.
--
--   This is that importer, mirroring V204's shape and resilience:
--
--     • the student is matched by matriculation number and must be a POSTGRADUATE
--       already on the register (loaded first by people.import_postgraduate, V203);
--     • the course is resolved by (programme, code) and CREATED in admissions.pg_course
--       from the row's title/units/kind when it is not on record yet — exactly as
--       the undergraduate importer creates a missing offering;
--     • a registration is created (or endorsed) for the session/semester, the course
--       entered on it, and — for a results file — the score recorded with its
--       postgraduate grade;
--     • a results row whose student is not on the register yet is HELD (like V204)
--       and posted automatically once that student is loaded;
--     • postgraduate study has two semesters (Policy 7), so the semester is 1 or 2.
--
--   The holding store is migration scratch, re-derivable from the uploaded file,
--   so it is exempt from the audit spine like assessment.legacy_result_holding.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS admissions.pg_legacy_holding (
    session     text NOT NULL,
    semester    int  NOT NULL,
    matric      text NOT NULL,
    course_code text NOT NULL,
    raw         jsonb NOT NULL,          -- the original row, replayed once the student exists
    loaded_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session, semester, matric, course_code)
);
CREATE INDEX IF NOT EXISTS ix_pg_legacy_holding_matric ON admissions.pg_legacy_holding (matric);
SELECT audit.exempt('admissions.pg_legacy_holding',
    'Migration scratch: postgraduate results whose student is not loaded yet, kept verbatim and replayed on reconcile; re-derivable from the uploaded file.');

-- ── the importer: one session/semester of postgraduate registration or results ──
CREATE OR REPLACE FUNCTION admissions.import_legacy_pg_semester(
    p_session text, p_semester int, p_rows jsonb, p_with_results boolean)
RETURNS TABLE (rows int, students int, courses int, registrations int, results int,
               no_student int, held int, no_mark int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_code text; v_title text; v_units int; v_kind text; v_mode text;
        v_ca numeric; v_exam numeric; v_total numeric; v_grade text; v_points numeric;
        v_student uuid; v_pg boolean; v_prog text; v_course uuid; v_reg uuid; v_entry uuid;
        n int := 0; n_course int := 0; n_reg int := 0; n_res int := 0; nns int := 0; n_held int := 0;
        nnm int := 0; ns int := 0; v_firsterr text := NULL;
        seen_students uuid[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_semester NOT IN (1, 2) THEN
        RAISE EXCEPTION 'postgraduate study has two semesters: the semester is 1 or 2' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, course, units and the mark' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', r->>'reg_no', '')));
        v_code := upper(btrim(coalesce(r->>'course', r->>'courseCode', r->>'course_code', r->>'code', '')));
        v_code := regexp_replace(v_code, '^([A-Z]{2,4})\s*([0-9]{3})$', '\1 \2');
        IF v_matric = '' OR v_code = '' THEN CONTINUE; END IF;
        n := n + 1;

        BEGIN   -- one savepoint per row: any unexpected error sets the row aside, the batch survives
            SELECT s.id, (s.entry_mode = 'POSTGRADUATE'), s.programme_code
              INTO v_student, v_pg, v_prog
              FROM people.student s WHERE upper(s.matric_no) = v_matric;

            IF v_student IS NULL THEN
                -- the student is not on the register yet: HOLD a results row, to be posted on reconcile
                IF p_with_results THEN
                    INSERT INTO admissions.pg_legacy_holding (session, semester, matric, course_code, raw)
                    VALUES (p_session, p_semester, v_matric, v_code, r)
                    ON CONFLICT (session, semester, matric, course_code) DO UPDATE SET raw = EXCLUDED.raw, loaded_at = now();
                    n_held := n_held + 1;
                ELSE
                    nns := nns + 1;
                END IF;
                CONTINUE;
            END IF;
            IF NOT v_pg THEN
                -- the number belongs to a student who is not a postgraduate — not for this importer
                nns := nns + 1; CONTINUE;
            END IF;

            -- resolve the course of the student's programme, creating it from the row when it is not on record
            v_title := nullif(btrim(coalesce(r->>'title', r->>'courseTitle', r->>'course_title', r->>'name', '')), '');
            v_units := coalesce(nullif(regexp_replace(coalesce(r->>'units', r->>'unit', r->>'credit', r->>'cu', ''), '[^0-9]', '', 'g'), '')::int, 3);
            IF v_units < 0 OR v_units > 12 THEN v_units := 3; END IF;
            v_kind := upper(btrim(coalesce(r->>'kind', r->>'type', 'CORE')));
            IF v_kind NOT IN ('CORE','ELECTIVE','DEFICIENCY','RESEARCH') THEN v_kind := 'CORE'; END IF;

            SELECT id INTO v_course FROM admissions.pg_course WHERE programme_code = v_prog AND upper(code) = v_code;
            IF v_course IS NULL THEN
                INSERT INTO admissions.pg_course (programme_code, code, title, units, kind, semester)
                VALUES (v_prog, v_code, coalesce(v_title, v_code), v_units, v_kind, p_semester)
                ON CONFLICT (programme_code, code) DO NOTHING
                RETURNING id INTO v_course;
                IF v_course IS NULL THEN
                    SELECT id INTO v_course FROM admissions.pg_course WHERE programme_code = v_prog AND upper(code) = v_code;
                ELSE
                    n_course := n_course + 1;
                END IF;
            END IF;
            IF v_course IS NULL THEN ns := ns + 1; CONTINUE; END IF;

            -- the registration for this session/semester (created endorsed under a legacy minute, or endorsed if present)
            v_mode := upper(btrim(coalesce(r->>'mode', r->>'studyMode', r->>'study_mode', '')));
            v_mode := CASE WHEN v_mode LIKE 'PART%' OR v_mode = 'PT' THEN 'PART_TIME' ELSE 'FULL_TIME' END;
            SELECT id INTO v_reg FROM admissions.pg_registration
             WHERE student_id = v_student AND session = p_session AND semester = p_semester;
            IF v_reg IS NULL THEN
                INSERT INTO admissions.pg_registration (student_id, session, semester, mode, state, endorsed_by, endorsed_at)
                VALUES (v_student, p_session, p_semester, v_mode, 'ENDORSED', v_actor, now())
                RETURNING id INTO v_reg;
                n_reg := n_reg + 1;
            ELSE
                UPDATE admissions.pg_registration
                   SET state = 'ENDORSED', endorsed_by = coalesce(endorsed_by, v_actor),
                       endorsed_at = coalesce(endorsed_at, now()), updated_at = now()
                 WHERE id = v_reg;
            END IF;

            INSERT INTO admissions.pg_registration_entry (registration_id, course_id)
            VALUES (v_reg, v_course) ON CONFLICT (registration_id, course_id) DO NOTHING
            RETURNING id INTO v_entry;
            IF v_entry IS NULL THEN
                SELECT id INTO v_entry FROM admissions.pg_registration_entry
                 WHERE registration_id = v_reg AND course_id = v_course;
            END IF;
            IF NOT (v_student = ANY(seen_students)) THEN seen_students := seen_students || v_student; END IF;

            IF NOT p_with_results THEN CONTINUE; END IF;

            -- the score: CA + exam → total (0–100), graded on the postgraduate scale
            v_ca := nullif(regexp_replace(coalesce(r->>'ca', r->>'CA', ''), '[^0-9.]', '', 'g'), '')::numeric;
            v_exam := nullif(regexp_replace(coalesce(r->>'exam', r->>'EXAM', ''), '[^0-9.]', '', 'g'), '')::numeric;
            v_total := nullif(regexp_replace(coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark', ''), '[^0-9.]', '', 'g'), '')::numeric;
            IF v_total IS NULL AND v_ca IS NOT NULL AND v_exam IS NOT NULL THEN v_total := v_ca + v_exam; END IF;
            IF v_total IS NULL THEN nnm := nnm + 1; CONTINUE; END IF;
            v_total := round(v_total);
            IF v_total < 0 OR v_total > 100 THEN nnm := nnm + 1; CONTINUE; END IF;

            SELECT g.grade, g.points INTO v_grade, v_points FROM admissions.pg_grade(v_total) g;
            INSERT INTO admissions.pg_score (entry_id, ca, exam, total, grade, points, recorded_by)
            VALUES (v_entry, v_ca, v_exam, v_total, v_grade, v_points, v_actor)
            ON CONFLICT (entry_id) DO UPDATE SET ca = EXCLUDED.ca, exam = EXCLUDED.exam, total = EXCLUDED.total,
                grade = EXCLUDED.grade, points = EXCLUDED.points, recorded_at = now(), recorded_by = EXCLUDED.recorded_by;
            n_res := n_res + 1;
            -- the result is posted: clear any hold for this student/course
            DELETE FROM admissions.pg_legacy_holding
             WHERE session = p_session AND semester = p_semester AND matric = v_matric AND course_code = v_code;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ' ' || v_code || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, cardinality(seen_students), n_course, n_reg, n_res, nns, n_held, nnm, ns, v_firsterr;
END $$;

-- post every held postgraduate result whose student is now on the register (replayed through the
-- importer, which clears each hold as its result posts). Called after a postgraduate-students upload.
CREATE OR REPLACE FUNCTION admissions.pg_reconcile_legacy_holding()
RETURNS TABLE (reconciled int, still_held int)
LANGUAGE plpgsql AS $$
DECLARE grp record; v_before int; v_after int;
BEGIN
    SELECT count(*) INTO v_before FROM admissions.pg_legacy_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric AND s.entry_mode = 'POSTGRADUATE');
    FOR grp IN
        SELECT h.session, h.semester, jsonb_agg(h.raw) AS rows
          FROM admissions.pg_legacy_holding h
         WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric AND s.entry_mode = 'POSTGRADUATE')
         GROUP BY h.session, h.semester
    LOOP
        PERFORM admissions.import_legacy_pg_semester(grp.session, grp.semester, grp.rows, true);
    END LOOP;
    SELECT count(*) INTO v_after FROM admissions.pg_legacy_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric AND s.entry_mode = 'POSTGRADUATE');
    RETURN QUERY SELECT greatest(v_before - v_after, 0),
                        (SELECT count(*)::int FROM admissions.pg_legacy_holding);
END $$;

COMMIT;
