-- ═══════════════════════════════════════════════════════════════════════════
-- V093 — legacy results: an out-of-range mark is skipped and reported, not fatal
--
--   The legacy importer (V082) inserted the mark straight, so a single row with
--   a CA above 40, an exam above 60 or a total outside 0–100 tripped the score
--   constraint and rolled the whole upload back. Now such a row is skipped and
--   counted under "no/invalid mark", the way an unmatched student or course is —
--   the rest of the file loads, and the exam officer fixes the flagged rows and
--   re-uploads. Same return shape as V082, so nothing downstream changes.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION assessment.import_legacy_semester(p_session text, p_semester int, p_rows jsonb, p_with_results boolean)
RETURNS TABLE (rows int, students int, offerings int, registrations int, results int, no_student int, no_course int, no_mark int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_code text; v_units int; v_level int; v_ca int; v_exam int; v_total int; v_outcome text;
        v_student uuid; v_offering uuid; v_sheet uuid; v_reg uuid; v_have_mark boolean;
        n int := 0; n_off int := 0; n_reg int := 0; n_res int := 0; nns int := 0; nnc int := 0; nnm int := 0;
        seen_students uuid[] := '{}'; seen_offerings uuid[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, course, units and the mark' USING ERRCODE = '23514';
    END IF;
    PERFORM assessment.ensure_session(p_session);

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', r->>'reg_no', '')));
        v_code := upper(btrim(coalesce(r->>'course', r->>'courseCode', r->>'course_code', r->>'code', '')));
        v_code := regexp_replace(v_code, '^([A-Z]{2,4})\s*([0-9]{3})$', '\1 \2');
        IF v_matric = '' OR v_code = '' THEN CONTINUE; END IF;
        n := n + 1;

        SELECT id INTO v_student FROM people.student WHERE upper(matric_no) = v_matric;
        IF v_student IS NULL THEN nns := nns + 1; CONTINUE; END IF;

        IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN nnc := nnc + 1; CONTINUE; END IF;
        SELECT units, level INTO v_units, v_level FROM catalogue.course WHERE code = v_code;
        v_units := coalesce(nullif(regexp_replace(coalesce(r->>'units', r->>'unit', r->>'cu', ''), '[^0-9]', '', 'g'), '')::int, v_units);
        v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, v_level);

        SELECT id INTO v_offering FROM catalogue.offering WHERE course_code = v_code AND session = p_session AND semester = p_semester;
        IF v_offering IS NULL THEN
            v_offering := gen_random_uuid();
            INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (v_offering, v_code, p_session, p_semester);
        END IF;
        IF NOT (v_offering = ANY(seen_offerings)) THEN n_off := n_off + 1; seen_offerings := seen_offerings || v_offering; END IF;

        INSERT INTO people.enrolment (id, student_id, session, level)
        VALUES (gen_random_uuid(), v_student, p_session, v_level) ON CONFLICT (student_id, session) DO NOTHING;
        SELECT id INTO v_reg FROM registration.course_registration WHERE student_id = v_student AND session = p_session AND semester = p_semester;
        IF v_reg IS NULL THEN
            v_reg := gen_random_uuid();
            INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by)
            VALUES (v_reg, v_student, p_session, p_semester, v_level, 'APPROVED', now(), now(), v_actor);
            n_reg := n_reg + 1;
        END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
        VALUES (v_reg, v_offering, v_units, 'CURRENT', 'APPROVED')
        ON CONFLICT (registration_id, offering_id) DO UPDATE SET units = EXCLUDED.units, status = 'APPROVED';
        IF NOT (v_student = ANY(seen_students)) THEN seen_students := seen_students || v_student; END IF;

        IF NOT p_with_results THEN CONTINUE; END IF;

        v_ca := nullif(regexp_replace(coalesce(r->>'ca', r->>'CA', ''), '[^0-9]', '', 'g'), '')::int;
        v_exam := nullif(regexp_replace(coalesce(r->>'exam', r->>'EXAM', ''), '[^0-9]', '', 'g'), '')::int;
        v_total := nullif(regexp_replace(coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark', ''), '[^0-9]', '', 'g'), '')::int;
        v_outcome := upper(btrim(coalesce(r->>'outcome', 'GRADED')));
        IF v_outcome NOT IN ('GRADED','ABSENT','WITHHELD','INCOMPLETE','MALPRACTICE','EXEMPTED') THEN v_outcome := 'GRADED'; END IF;
        v_have_mark := (v_ca IS NOT NULL AND v_exam IS NOT NULL) OR v_total IS NOT NULL;
        IF v_outcome = 'GRADED' AND NOT v_have_mark THEN nnm := nnm + 1; CONTINUE; END IF;
        IF v_ca IS NOT NULL AND v_exam IS NULL AND v_total IS NULL THEN v_total := v_ca; v_ca := NULL; END IF;

        -- skip and report an out-of-range mark rather than letting the constraint abort the whole upload
        IF v_outcome = 'GRADED' AND (
               (v_exam IS NOT NULL AND ((v_ca IS NULL OR v_ca < 0 OR v_ca > 40) OR (v_exam < 0 OR v_exam > 60)))
            OR (v_exam IS NULL AND (v_total IS NULL OR v_total < 0 OR v_total > 100))
           ) THEN
            nnm := nnm + 1; CONTINUE;
        END IF;

        SELECT id INTO v_sheet FROM assessment.score_sheet WHERE offering_id = v_offering;
        IF v_sheet IS NULL THEN
            v_sheet := gen_random_uuid();
            INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at)
            VALUES (v_sheet, v_offering, 'PUBLISHED', 'Migrated from the legacy portal', now());
        ELSIF (SELECT stage FROM assessment.score_sheet WHERE id = v_sheet) <> 'PUBLISHED' THEN
            UPDATE assessment.score_sheet SET stage = 'PUBLISHED', senate_minute = coalesce(senate_minute, 'Migrated from the legacy portal'),
                   published_at = coalesce(published_at, now()) WHERE id = v_sheet;
        END IF;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, total, outcome, imported, reason)
        VALUES (v_sheet, v_student,
                coalesce((SELECT max(version) + 1 FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student), 1),
                CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_ca END,
                CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_exam END,
                CASE WHEN v_outcome = 'GRADED' AND v_exam IS NULL THEN v_total END,
                v_outcome, true,
                CASE WHEN (SELECT count(*) FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student) > 0
                     THEN 'Re-imported from the legacy portal' END);
        n_res := n_res + 1;
    END LOOP;
    RETURN QUERY SELECT n, cardinality(seen_students), n_off, n_reg, n_res, nns, nnc, nnm;
END $$;

COMMIT;
