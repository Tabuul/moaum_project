-- ═══════════════════════════════════════════════════════════════════════════
-- V198 — resit / special sittings, phase 2: cross-sitting result resolution
--
--   With a sheet per sitting (V197), a course can now carry a Main result and a
--   later Re-sit or Special result. This resolves them to ONE final result per
--   (student, course), applied in exactly one place — assessment.student_results —
--   so GPA, cumulative, carryovers, the student portal and the verify transcript
--   all inherit it:
--
--     • SPECIAL (approved absentee, first attempt) — published, taken → replaces
--       the Main, UNCAPPED.
--     • RESIT (failed or absent in the Main) — published, taken and passed →
--       replaces the Main, CAPPED at the pass mark (the lowest grade band with
--       points > 0: E / 40 / 1.0 in the standing scheme). A failed re-sit stays
--       a fail (a carryover).
--     • Otherwise the Main stands.
--
--   A student only carries a re-sit/special result for a course they were on the
--   roster for (V197's sheet_candidates), so a clean Main pass is never touched.
--   The original Main marks remain on the score sheet and the audit record; the
--   resolution only decides which result the transcript and GPA read.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- the single authoritative result for a student in one offering, resolved across its sittings
CREATE OR REPLACE FUNCTION assessment.course_final(p_student uuid, p_offering uuid)
RETURNS TABLE (sheet_id uuid, stage text, published_at timestamptz, senate_minute text,
               ca int, exam int, total int, grade text, points numeric, outcome text, sitting text)
LANGUAGE sql STABLE AS $$
    WITH sittings AS (
        SELECT sh.id AS sheet_id, sh.stage, sh.published_at, sh.senate_minute,
               coalesce(es.kind, 'MAIN') AS kind,
               ls.ca, ls.exam, ls.total, ls.grade, ls.points, ls.outcome
          FROM assessment.score_sheet sh
          LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
          LEFT JOIN LATERAL assessment.latest_scores(sh.id) ls ON ls.student_id = p_student
         WHERE sh.offering_id = p_offering
    ),
    pass AS (   -- the pass mark of the standing grading scheme: the lowest band scoring points
        SELECT b.grade, b.points, b.low
          FROM policy.grade_band b
         WHERE b.version_id = policy.in_force('grading', 'UNIVERSITY', current_date) AND b.points > 0
         ORDER BY b.points ASC LIMIT 1
    ),
    picked AS (   -- a published special or re-sit the student sat supersedes the Main, else the Main stands
        SELECT s.*, CASE s.kind WHEN 'SPECIAL' THEN 1 WHEN 'RESIT' THEN 2 ELSE 3 END AS pr
          FROM sittings s
         WHERE (s.kind IN ('SPECIAL','RESIT') AND s.stage = 'PUBLISHED' AND s.outcome IS NOT NULL)
            OR s.kind = 'MAIN'
         ORDER BY pr LIMIT 1
    )
    SELECT p.sheet_id, p.stage, p.published_at, p.senate_minute,
           p.ca, p.exam,
           -- a passed re-sit is recorded at the pass mark; a special and the Main are as scored
           CASE WHEN p.pr = 2 AND coalesce(p.points, 0) > 0 THEN (SELECT low    FROM pass) ELSE p.total  END,
           CASE WHEN p.pr = 2 AND coalesce(p.points, 0) > 0 THEN (SELECT grade  FROM pass) ELSE p.grade  END,
           CASE WHEN p.pr = 2 AND coalesce(p.points, 0) > 0 THEN (SELECT points FROM pass) ELSE p.points END,
           p.outcome,
           CASE p.pr WHEN 1 THEN 'SPECIAL' WHEN 2 THEN 'RESIT' ELSE 'MAIN' END
      FROM picked p;
$$;

COMMENT ON FUNCTION assessment.course_final(uuid, uuid) IS
  'The student''s single resolved result for one offering across its sittings: a published special (uncapped) '
  'or passed re-sit (capped at the pass mark) replaces the Main; otherwise the Main stands. Marks show only '
  'where the resolved sheet is published (the caller guards on stage). The original marks stay on each sheet.';

-- student_results now reads the resolved result per course (one row per course, no per-sitting duplication);
-- signature unchanged from V184, so every wrapper (student_gpa, cumulative, carryovers, portal, verify) inherits it
CREATE OR REPLACE FUNCTION assessment.student_results(p_student uuid)
RETURNS TABLE (session text, semester int, course_code text, title text, units int, entry_type text,
               stage text, published boolean, published_at timestamptz, senate_minute text,
               ca int, exam int, total int, grade text, points numeric, outcome text, lecturer text)
LANGUAGE sql STABLE AS $$
    SELECT r.session, r.semester, c.code, c.title, e.units, e.entry_type,
           coalesce(cf.stage, 'NO_SHEET'), coalesce(cf.stage = 'PUBLISHED', false), cf.published_at, cf.senate_minute,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.ca END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.exam END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.total END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.grade END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.points END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.outcome END,
           CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
      LEFT JOIN LATERAL assessment.course_final(p_student, o.id) cf ON true
     WHERE r.student_id = p_student AND r.status IN ('APPROVED','LOCKED')
     ORDER BY r.session, r.semester, c.code;
$$;

COMMIT;
