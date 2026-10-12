-- ═══════════════════════════════════════
-- V405 — a course that joins the structure later gets its class in every opened semester
--
--   A class (catalogue.offering) is opened for every structure course of a semester when the calendar opens that semester's
--   registration (registration.open_course_registration), and never again. A course uploaded into a programme's structure
--   after that — the MOAU- codes, uploaded while the session was running — had no class: it could not be allocated to a
--   lecturer, timetabled or registered, and nothing on any screen said why. From V405:
--     1 · catalogue.open_classes_for_courses(codes): a class for each course in every session and semester whose classes
--         are already open (a session not closed, with classes of the REGULAR stream), by the rule the calendar applied —
--         in the structure of a full-time programme, for a track a live student is on, running in that semester.
--     2 · it runs by itself when structure rows are added (the upload, Department courses) and when an ended course is
--         restored.
--     3 · catalogue.courses_without_class(dept, session): what the allocation desk shows — a department's courses with no
--         class in the session's opened semesters, and why: not in any programme's structure, or simply no class yet (the
--         desk opens them, as the calendar would, through registration.open_course_registration).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V405: a course that joins the structure later gets its class', true);

-- ── 1 · the classes a course is owed in the semesters already open ──────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.open_classes_for_courses(p_codes text[])
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
    WITH opened AS (
        SELECT DISTINCT o.session, o.semester
          FROM catalogue.offering o
          JOIN policy.academic_session s ON s.name = o.session AND s.state NOT IN ('CLOSED', 'ARCHIVED', 'CANCELLED')
         WHERE o.stream = 'REGULAR'),
    live AS (
        SELECT DISTINCT st.programme_code, st.curriculum_track
          FROM people.student st
         WHERE st.status IN ('ACTIVE', 'PROBATION', 'ADMITTED'))
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), c.code, x.session, x.semester
      FROM catalogue.course c
      JOIN opened x ON catalogue.runs_in(c.semester, c.both_semesters, x.semester)
     WHERE c.code = ANY (p_codes) AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
       AND EXISTS (SELECT 1
                     FROM catalogue.course_offer co
                    WHERE co.course_code = c.code
                      AND NOT EXISTS (SELECT 1 FROM ref.programme pp WHERE pp.code = co.programme_code AND pp.category = 'POST GRADUATE')
                      AND (co.track IS NULL OR EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code AND l.curriculum_track = co.track)))
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                        WHERE o.course_code = c.code AND o.session = x.session AND o.semester = x.semester AND o.stream = 'REGULAR')
    ON CONFLICT (course_code, session, semester, stream) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION catalogue.open_classes_for_courses(text[]) IS
  'V405: a class for each named course in every session and semester whose classes are already open, by the rule registration.open_course_registration applies; the number opened.';

-- ── 2 · by itself: structure rows added, an ended course restored ──────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.classes_for_new_offers()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM catalogue.open_classes_for_courses(ARRAY(SELECT DISTINCT r.course_code FROM new_rows r));
    RETURN NULL;
END $fn$;
DROP TRIGGER IF EXISTS trg_course_offer_opens_classes ON catalogue.course_offer;
CREATE TRIGGER trg_course_offer_opens_classes
    AFTER INSERT ON catalogue.course_offer
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT EXECUTE FUNCTION catalogue.classes_for_new_offers();

CREATE OR REPLACE FUNCTION catalogue.classes_for_restored_course()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM catalogue.open_classes_for_courses(ARRAY[NEW.code]);
    RETURN NULL;
END $fn$;
DROP TRIGGER IF EXISTS trg_course_restored_opens_classes ON catalogue.course;
CREATE TRIGGER trg_course_restored_opens_classes
    AFTER UPDATE OF state ON catalogue.course
    FOR EACH ROW WHEN (OLD.state = 'ENDED' AND NEW.state <> 'ENDED')
    EXECUTE FUNCTION catalogue.classes_for_restored_course();

-- ── 3 · what the allocation desk shows: a department's courses with no class in the session's opened semesters ─────
CREATE OR REPLACE FUNCTION catalogue.courses_without_class(p_dept text, p_session text)
RETURNS TABLE(code text, title text, level int, semester int, reason text)
LANGUAGE sql STABLE AS $fn$
    WITH opened AS (SELECT DISTINCT o.semester FROM catalogue.offering o WHERE o.session = p_session AND o.stream = 'REGULAR')
    SELECT c.code, c.title, c.level, c.semester,
           CASE WHEN NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code) THEN 'NOT_IN_STRUCTURE'
                ELSE 'NO_CLASS' END
      FROM catalogue.course c
     WHERE c.dept_code = p_dept AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
       AND EXISTS (SELECT 1 FROM opened x
                    WHERE catalogue.runs_in(c.semester, c.both_semesters, x.semester)
                      AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                                       WHERE o.course_code = c.code AND o.session = p_session AND o.semester = x.semester AND o.stream = 'REGULAR'))
     ORDER BY c.level, c.semester, c.code
$fn$;
COMMENT ON FUNCTION catalogue.courses_without_class(text, text) IS
  'V405: a department''s live courses with no REGULAR class in a semester of the session whose classes are already open, and why — NOT_IN_STRUCTURE (no programme offers it) or NO_CLASS.';

COMMIT;
