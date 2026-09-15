-- ═══════════════════════════════════════════════════════════════════════════
-- V142 — keep demo courses off the student's registration menu
--
--   db/demo.sql seeds five walkthrough courses coded 'DMO …'. If any is offered
--   to a real programme they can surface on a real student's course-registration
--   screen. registration.student_menu now excludes 'DMO %' courses from both the
--   eligible set and the carryovers, so a demo course never appears to a student
--   whether or not the demo data has been purged. Everything else is unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (offering_id uuid, course_code text, title text, units int, kind text, basis text, owner_dept text,
               carryover boolean, failed_in text, lecturer text)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    eligible AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, co.basis, c.dept_code
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester)
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis = 'Carryover'), x.failed_in, p.surname || ', ' || p.given_names
      FROM (SELECT e.*, NULL::text AS failed_in FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
            UNION ALL SELECT * FROM carry) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, x.kind, x.code;
$$;

COMMIT;
