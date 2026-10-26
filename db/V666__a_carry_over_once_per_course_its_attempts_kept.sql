-- V666. A carry-over once per course, its attempts kept — the University's master prompt of 26 October 2026 ("Carry-over
-- deduplication, result clearance & single course-semester registration").
--
-- A carry-over is not stored: registration.carryovers reads it from the published results each time (a failure on a published
-- sheet — a graded F or a recorded absence, V422 — of a course the student's programme does not hold as an elective, with no pass
-- published after it). The latest version of a score is the one read, so a result corrected through the amendment chain (V358)
-- clears a carry-over, or brings it back, as soon as it is published; a sheet not yet published clears nothing and fails no one
-- (no result is not a failure). What was wrong: it returned one row per failed attempt, so a course failed in 2024/2025 and failed
-- again in 2025/2026 was owed twice — twice on the dashboard, the carry-over page, the student's full record, the registration
-- page's carry-over list, counted twice in the completion check behind graduation (people.lifecycle_completion_rows) and in the
-- Bursary's spillover list (finance.spillover_students). On the live-shaped copy of 21 October 2026: 274 students, 394 courses
-- shown twice.
--
--   registration.carryover_attempts(student) — each failed attempt still owed, the session and semester it was failed in (the old
--     reading, kept for the reports that need every attempt: assessment.absence_carryovers);
--   registration.carryovers(student) — one row per course (its code, the course's own identity — a code shared by separate courses
--     is held under each course's own code, V646): the last failure as failed_in, how many failed attempts are owed, the first;
--   registration.carryover_history(student) — every attempt of every course the student has failed on a published result, with
--     its result (failed, passed, awaited, registered with no result yet) and whether the course is owed now.
--
-- Nothing is deleted or rewritten: registrations, sheets and scores stay as they are; the history is read from them.

CREATE OR REPLACE FUNCTION registration.carryover_attempts(p_student uuid)
RETURNS TABLE (course_code text, title text, units integer, failed_in text, session text, semester integer)
LANGUAGE sql STABLE AS $$
    -- the student's published results, read once
    WITH r AS MATERIALIZED (
        SELECT x.session, x.semester, x.course_code, x.title, x.units, x.outcome, x.points
          FROM assessment.student_results(p_student) x WHERE x.published)
    SELECT f.course_code, f.title, f.units, f.session || ' semester ' || f.semester, f.session, f.semester
      FROM r f
     -- V422: a recorded absence is an F and owed, as a graded F is
     WHERE f.outcome IN ('GRADED', 'ABSENT') AND f.points = 0
       AND NOT registration.is_elective_for(p_student, f.course_code)
       AND NOT EXISTS (SELECT 1 FROM r g
                        WHERE g.course_code = f.course_code AND g.outcome = 'GRADED' AND g.points > 0
                          AND (g.session, g.semester) > (f.session, f.semester))
     ORDER BY f.course_code, f.session, f.semester;
$$;
COMMENT ON FUNCTION registration.carryover_attempts(uuid) IS
  'V666: each failed attempt of a course still owed (a graded F or an absence on a published sheet with no pass published after it), the session and semester failed in. registration.carryovers reads one row per course from it.';

-- the columns callers read stay first and in place (course_code, title, units, failed_in); the attempts follow
DROP FUNCTION registration.carryovers(uuid);
CREATE FUNCTION registration.carryovers(p_student uuid)
RETURNS TABLE (course_code text, title text, units integer, failed_in text, attempts integer, first_failed_in text)
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT ON (a.course_code) a.course_code, a.title, a.units, a.failed_in, a.attempts, a.first_failed_in
      FROM (SELECT x.*, (count(*) OVER (PARTITION BY x.course_code))::int AS attempts,
                   first_value(x.failed_in) OVER (PARTITION BY x.course_code ORDER BY x.session, x.semester) AS first_failed_in
              FROM registration.carryover_attempts(p_student) x) a
     ORDER BY a.course_code, a.session DESC, a.semester DESC;
$$;
COMMENT ON FUNCTION registration.carryovers(uuid) IS
  'V666: the courses a student owes, once each: the last failure (failed_in, "<session> semester <n>"), the failed attempts owed and the first. Read by the dashboard, the carry-over page, the registration menu, the full record, the completion check and the spillover lists alike.';

CREATE OR REPLACE FUNCTION registration.carryover_history(p_student uuid)
RETURNS TABLE (course_code text, title text, session text, semester integer, grade text, result text, owed boolean)
LANGUAGE sql STABLE AS $$
    WITH r AS MATERIALIZED (SELECT * FROM assessment.student_results(p_student)),
    -- the courses failed on a published result at least once
    failed AS (SELECT DISTINCT x.course_code FROM r x WHERE x.published AND x.outcome IN ('GRADED', 'ABSENT') AND x.points = 0),
    owed AS (SELECT DISTINCT a.course_code FROM registration.carryover_attempts(p_student) a)
    SELECT x.course_code, x.title, x.session, x.semester, x.grade,
           CASE WHEN x.published AND x.outcome = 'GRADED' AND x.points > 0 THEN 'PASSED'
                WHEN x.published THEN 'FAILED'
                WHEN x.stage = 'NO_SHEET' THEN 'REGISTERED'
                WHEN x.stage = 'NO_RESULT' THEN 'NO_RESULT'
                ELSE 'AWAITED' END,
           x.course_code IN (SELECT o.course_code FROM owed o)
      FROM r x
     WHERE x.course_code IN (SELECT f.course_code FROM failed f)
     ORDER BY x.course_code, x.session, x.semester;
$$;
COMMENT ON FUNCTION registration.carryover_history(uuid) IS
  'V666: every attempt of each course a student has failed on a published result — PASSED, FAILED, AWAITED (a sheet on its way), NO_RESULT (a published sheet without them), REGISTERED (no sheet yet) — and whether the course is owed now. The history behind registration.carryovers; nothing is removed from it.';

-- V422's report of the students owed a course only because of an absence reads every attempt still owed, as before
CREATE OR REPLACE FUNCTION assessment.absence_carryovers(p_fac text, p_dept text, p_prog text)
 RETURNS TABLE(student_id uuid, number text, name text, programme_code text, programme text, level integer, status text, course_code text, title text, units integer, absent_in text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH ab AS (
        SELECT DISTINCT sc.student_id, o.course_code, o.session || ' semester ' || o.semester AS absent_in
          FROM assessment.score sc
          JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id AND sh.stage = 'PUBLISHED'
          JOIN catalogue.offering o ON o.id = sh.offering_id
         WHERE sc.outcome = 'ABSENT'
           AND NOT EXISTS (SELECT 1 FROM assessment.score n WHERE n.sheet_id = sc.sheet_id AND n.student_id = sc.student_id AND n.version > sc.version)),
    who AS (
        SELECT DISTINCT ab.student_id FROM ab
          JOIN people.student st ON st.id = ab.student_id
          JOIN ref.programme p ON p.code = st.programme_code
         -- the students still on the register: a graduate or a withdrawal owes no course
         WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'RUSTICATED', 'DORMANT')
           AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR st.programme_code = p_prog)),
    -- each student's failed attempts still owed, read once (V666: every attempt, not the one row per course carryovers gives)
    co AS (SELECT who.student_id, x.course_code, x.title, x.units, x.failed_in FROM who CROSS JOIN LATERAL registration.carryover_attempts(who.student_id) x)
    SELECT st.id, coalesce(st.matric_no, st.admission_no), upper(st.surname) || ', ' || st.other_names, st.programme_code, p.name,
           st.current_level, st.status, co.course_code, co.title, co.units, co.failed_in
      FROM co
      JOIN ab ON ab.student_id = co.student_id AND ab.course_code = co.course_code AND ab.absent_in = co.failed_in
      JOIN people.student st ON st.id = co.student_id
      JOIN ref.programme p ON p.code = st.programme_code
     -- owed only because of the absence: no graded F of the same course still owed (that was owed before V422)
     WHERE NOT EXISTS (SELECT 1 FROM co f WHERE f.student_id = co.student_id AND f.course_code = co.course_code
                         AND NOT EXISTS (SELECT 1 FROM ab x WHERE x.student_id = f.student_id AND x.course_code = f.course_code AND x.absent_in = f.failed_in))
     ORDER BY p.name, st.current_level, st.surname, st.other_names, co.course_code
$function$;
