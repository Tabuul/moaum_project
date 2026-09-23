-- ═══════════════════════════════════════════════════════════════════════════
-- V238 — the grace mark: a total one short of the pass mark is the pass mark
--
--   Senate's practice: a candidate whose CA and examination add to 39 is
--   given the one mark and passes at 40. The rule lives where the total is
--   computed (assessment.latest_scores), so the score sheet, the broadsheet,
--   the transcript and the student's own result all say 40 and grade it as
--   the scheme in force grades 40. The pass mark is read off the grading
--   scheme — the lowest band that carries a point — not written here, so a
--   scheme that moves the pass mark moves the grace with it.
--
--   The two marks the lecturer typed stay as typed: 39 is still 20 + 19 on
--   the record; the total is what is graced. A total the old portal imported
--   whole is left as the old portal graded it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION assessment.grace_total(p_raw int, p_at date DEFAULT current_date)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT CASE
             WHEN p_raw IS NULL THEN NULL
             WHEN p_raw = (SELECT min(b.low) FROM policy.grade_band b
                            WHERE b.version_id = policy.in_force('grading', 'UNIVERSITY', p_at) AND b.points > 0) - 1
               THEN p_raw + 1
             ELSE p_raw
           END
$$;

COMMENT ON FUNCTION assessment.grace_total(int, date) IS
  'A total one short of the lowest passing band in force is raised to it (39 → 40 under the 2015 scheme); any other total is returned as it is.';

CREATE OR REPLACE FUNCTION assessment.latest_scores(p_sheet uuid)
RETURNS TABLE (student_id uuid, ca int, exam int, total int, grade text, points numeric,
               outcome text, version int, amended boolean)
LANGUAGE sql STABLE AS $$
    SELECT s.student_id, s.ca, s.exam, t.total,
           g.grade, g.points, s.outcome, s.version, s.version > 1
      FROM (SELECT DISTINCT ON (student_id) * FROM assessment.score
             WHERE sheet_id = p_sheet ORDER BY student_id, version DESC) s
      CROSS JOIN LATERAL (SELECT CASE WHEN s.outcome <> 'GRADED' THEN NULL
                                      WHEN s.ca IS NOT NULL AND s.exam IS NOT NULL AND NOT s.imported THEN assessment.grace_total(s.ca + s.exam)
                                      ELSE coalesce(s.ca + s.exam, s.total) END AS total) t
      LEFT JOIN LATERAL policy.grade_of(t.total) g ON true
$$;

COMMIT;
