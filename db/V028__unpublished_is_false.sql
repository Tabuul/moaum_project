-- ═══════════════════════════════════════════════════════════════════════════
-- V028 — a course with no score sheet yet is unpublished, not unknown
--
--   assessment.student_results (V026) said `published` as
--   `sh.stage = 'PUBLISHED'`, which is NULL when the offering has no sheet
--   at all. A student's screen reads NULL as "we cannot say", when the
--   truth is plain: nothing has been published. The column now answers
--   false whenever there is no published sheet; every mark column stays
--   NULL until the sheet is published (never let a student see an
--   unpublished grade).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION assessment.student_results(p_student uuid)
RETURNS TABLE (session text, semester int, course_code text, title text, units int, entry_type text,
               stage text, published boolean, published_at timestamptz, senate_minute text,
               ca int, exam int, total int, grade text, points numeric, outcome text)
LANGUAGE sql STABLE AS $$
    SELECT r.session, r.semester, c.code, c.title, e.units, e.entry_type,
           coalesce(sh.stage, 'NO_SHEET'), coalesce(sh.stage = 'PUBLISHED', false), sh.published_at, sh.senate_minute,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.ca END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.exam END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.total END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.grade END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.points END,
           CASE WHEN sh.stage = 'PUBLISHED' THEN ls.outcome END
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN assessment.score_sheet sh ON sh.offering_id = o.id
      LEFT JOIN LATERAL (SELECT * FROM assessment.latest_scores(sh.id) x WHERE x.student_id = p_student) ls ON sh.id IS NOT NULL
     WHERE r.student_id = p_student AND r.status IN ('APPROVED','LOCKED')
     ORDER BY r.session, r.semester, c.code;
$$;

COMMENT ON FUNCTION assessment.student_results(uuid) IS
  'The student''s registered courses with the published marks only. published is false, never NULL, '
  'while no sheet exists or the sheet is not yet published; the mark columns stay NULL until it is.';

COMMIT;
