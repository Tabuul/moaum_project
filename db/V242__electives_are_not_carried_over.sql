-- ═══════════════════════════════════════════════════════════════════════════
-- V242 — a failed elective is not carried over
--
--   A core course failed is owed: it appears in the carryover column and the
--   remark, is placed on the student's next registration, and is passed
--   before the degree. An elective failed is failed, and that is the end of
--   it: the student takes another elective for the credits, never that one
--   again. The carryover functions now leave electives out, so the column,
--   the remark, the registration menu and every desk that asks "what does
--   this student owe" agree.
--
--   Elective, for a student, is what the programme's structure says the
--   course is to them (a course borrowed as an elective is an elective here
--   though core where it lives); a course the structure does not place is
--   read by its own kind.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION registration.is_elective_for(p_student uuid, p_course text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT bool_or(co.basis = 'Elective')
           FROM catalogue.course_offer co
           JOIN people.student s ON s.id = p_student
          WHERE co.course_code = p_course AND co.programme_code = s.programme_code),
        (SELECT c.kind = 'Elective' FROM catalogue.course c WHERE c.code = p_course),
        false)
$$;

COMMENT ON FUNCTION registration.is_elective_for(uuid, text) IS
  'Whether a course is an elective to this student: by the programme''s structure where it places the course, else by the course''s own kind.';

CREATE OR REPLACE FUNCTION registration.carryovers(p_student uuid)
RETURNS TABLE (course_code text, title text, units int, failed_in text)
LANGUAGE sql STABLE AS $$
    SELECT f.course_code, f.title, f.units, f.session || ' semester ' || f.semester
      FROM assessment.student_results(p_student) f
     WHERE f.published AND f.outcome = 'GRADED' AND f.points = 0
       AND NOT registration.is_elective_for(p_student, f.course_code)
       AND NOT EXISTS (SELECT 1 FROM assessment.student_results(p_student) g
                        WHERE g.course_code = f.course_code AND g.published AND g.outcome = 'GRADED' AND g.points > 0
                          AND (g.session, g.semester) > (f.session, f.semester));
$$;

CREATE OR REPLACE FUNCTION registration.carryovers_at(p_student uuid, p_session text, p_semester int, p_inclusive boolean)
RETURNS TABLE (course_code text, title text, units int, failed_in text)
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT ON (f.course_code)
           f.course_code, f.title, f.units, f.session || ' semester ' || f.semester
      FROM assessment.student_results(p_student) f
     WHERE f.published AND f.outcome = 'GRADED' AND f.points = 0
       AND NOT registration.is_elective_for(p_student, f.course_code)
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
  'A student''s outstanding carryovers as of (session, semester): core courses failed within the bound and not passed within it; electives are never carried. inclusive=false = carried into the semester (the column); inclusive=true = owed leaving it (the remark).';

COMMIT;
