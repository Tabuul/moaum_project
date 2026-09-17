-- ===========================================================================
-- V160 - registration draws only the student's curriculum (CCMAS / BMAS)
--
--   V116 recorded the split — each course carries its framework and each student
--   their curriculum_version (CCMAS from 2023/2024, BMAS before) — but said the
--   enforcement would come later: "registration still draws from the one
--   structure a programme carries". This is that enforcement.
--
--   The current 400 level cohort sits under BMAS; 100-300 level under CCMAS. Both
--   structures live in the catalogue side by side (under different course codes),
--   which is why both showed on the form. Now student_menu shows a course only
--   when its curriculum matches the student's — an untagged course (or an
--   untagged student) still shows, so nothing regresses where the split was never
--   recorded.
-- ===========================================================================

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
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
         WHERE c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version))
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
