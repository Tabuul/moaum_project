-- ═══════════════════════════════════════════════════════════════════════════
-- V166 — platform.remove_demo_courses: purge demo courses left in the catalogue
--
--   db/demo.sql seeds courses coded 'DMO …', but demo courses were also created
--   by hand in the catalogue UI while walking the portal — coded 'DMC …' and
--   titled 'Demo …'. They surface on the lecturer-allocation and registration
--   screens. platform.remove_demo_data removes the whole demo world (students,
--   candidates and DMO courses); this is the narrow, course-only purge asked for:
--   it deletes the demo courses and everything hanging off them — their offerings,
--   materials, assignments and submissions, score sheets, questions, timetable and
--   class slots, and any registration entries on them — but touches no student,
--   candidate or real course. A demo course is one coded 'DMO ' or 'DMC ', or
--   titled 'Demo …' (a real course is never titled that). Guarded by REMOVE DEMO,
--   run in one transaction, and idempotent — it removes nothing on a clean base.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION platform.remove_demo_courses(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; r jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a demo purge is made by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'REMOVE DEMO' THEN
        RAISE EXCEPTION 'type REMOVE DEMO to confirm removing the demo courses' USING ERRCODE = '23514';
    END IF;

    -- the demo courses, by their markers, and everything scoped to them
    CREATE TEMP TABLE _dc ON COMMIT DROP AS
        SELECT code FROM catalogue.course
         WHERE code LIKE 'DMO %' OR code LIKE 'DMC %' OR title ILIKE 'Demo %';
    CREATE TEMP TABLE _do ON COMMIT DROP AS
        SELECT id FROM catalogue.offering WHERE course_code IN (SELECT code FROM _dc);
    CREATE TEMP TABLE _dsheet ON COMMIT DROP AS
        SELECT id FROM assessment.score_sheet WHERE offering_id IN (SELECT id FROM _do);

    r := jsonb_build_object(
        'demo_courses',   (SELECT count(*) FROM _dc),
        'demo_offerings', (SELECT count(*) FROM _do));

    -- learning spaces hung on the demo offerings
    DELETE FROM lms.submission_blob WHERE submission_id IN (
        SELECT id FROM lms.submission WHERE assignment_id IN (SELECT id FROM lms.assignment WHERE offering_id IN (SELECT id FROM _do)));
    DELETE FROM lms.submission WHERE assignment_id IN (SELECT id FROM lms.assignment WHERE offering_id IN (SELECT id FROM _do));
    DELETE FROM lms.access WHERE material_id IN (SELECT id FROM lms.material WHERE offering_id IN (SELECT id FROM _do));
    DELETE FROM lms.material_blob WHERE material_id IN (SELECT id FROM lms.material WHERE offering_id IN (SELECT id FROM _do));
    DELETE FROM lms.material WHERE offering_id IN (SELECT id FROM _do);
    DELETE FROM lms.assignment WHERE offering_id IN (SELECT id FROM _do);

    -- results, registration and timetable scoped to the demo offerings/courses
    DELETE FROM assessment.score WHERE sheet_id IN (SELECT id FROM _dsheet);
    DELETE FROM assessment.decision WHERE sheet_id IN (SELECT id FROM _dsheet);
    DELETE FROM assessment.score_sheet WHERE id IN (SELECT id FROM _dsheet);
    DELETE FROM registration.attendance WHERE offering_id IN (SELECT id FROM _do);
    DELETE FROM assessment.exam_timetable WHERE offering_id IN (SELECT id FROM _do);
    DELETE FROM assessment.question WHERE course_code IN (SELECT code FROM _dc);
    DELETE FROM catalogue.class_slot WHERE offering_id IN (SELECT id FROM _do);
    -- a real student may have registered a demo course: drop the entry, keep the registration
    DELETE FROM registration.entry WHERE offering_id IN (SELECT id FROM _do);
    DELETE FROM catalogue.offering WHERE id IN (SELECT id FROM _do);
    DELETE FROM catalogue.course_offer WHERE course_code IN (SELECT code FROM _dc);
    DELETE FROM catalogue.course WHERE code IN (SELECT code FROM _dc);

    RETURN r || jsonb_build_object('removed', true);
END $$;

COMMIT;
