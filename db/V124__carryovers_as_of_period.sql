-- ═══════════════════════════════════════════════════════════════════════════
-- V124 — carryovers a student holds AS OF a given semester, not their whole life
--
--   registration.carryovers(student) returns every course the student has ever
--   failed and not yet passed — their standing right now. On a broadsheet for an
--   earlier period that is wrong: a 200 level carryover surfaced on a 100 level
--   second-semester sheet, i.e. a debt from a level the student had not reached
--   at the time of that sheet.
--
--   carryovers_at(student, session, semester, inclusive) answers the question at
--   a point in time: the courses failed in a period within the bound and not
--   passed within the bound. With inclusive = false it is what the student
--   carried INTO the semester (the carryover column — re-attempts they now pass
--   or fail again); with inclusive = true it is what they still owe leaving the
--   semester (the remark). Nothing from a later period is ever pulled in.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION registration.carryovers_at(p_student uuid, p_session text, p_semester int, p_inclusive boolean)
RETURNS TABLE (course_code text, title text, units int, failed_in text)
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT ON (f.course_code)
           f.course_code, f.title, f.units, f.session || ' semester ' || f.semester
      FROM assessment.student_results(p_student) f
     WHERE f.published AND f.outcome = 'GRADED' AND f.points = 0
       AND CASE WHEN p_inclusive THEN (f.session, f.semester) <= (p_session, p_semester)
                ELSE (f.session, f.semester) <  (p_session, p_semester) END
       AND NOT EXISTS (
            SELECT 1 FROM assessment.student_results(p_student) g
             WHERE g.course_code = f.course_code AND g.published AND g.outcome = 'GRADED' AND g.points > 0
               AND (g.session, g.semester) > (f.session, f.semester)
               AND CASE WHEN p_inclusive THEN (g.session, g.semester) <= (p_session, p_semester)
                        ELSE (g.session, g.semester) <  (p_session, p_semester) END)
     ORDER BY f.course_code, f.session, f.semester;
$$;

COMMENT ON FUNCTION registration.carryovers_at(uuid, text, int, boolean) IS
  'A student''s outstanding carryovers as of (session, semester): failed within '
  'the bound and not passed within it. inclusive=false = carried into the '
  'semester (the column); inclusive=true = owed leaving it (the remark).';

COMMIT;
