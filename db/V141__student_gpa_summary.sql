-- ═══════════════════════════════════════════════════════════════════════════
-- V141 — assessment.student_gpa: the full academic summary per semester
--
--   The student's result page showed GPA, CGPA and units. This adds the rest of
--   the broadsheet summary, computed from the same published sheets:
--     CUR  credit units registered (counted) this semester
--     CUE  credit units earned (passed) this semester
--     WGP  weighted grade points this semester (Σ units·points)
--     GPA  WGP / CUR
--     TCR  total credit units registered, cumulative
--     TCE  total credit units earned, cumulative
--     TWGP total weighted grade points, cumulative
--     LCGPA the CGPA at the end of the previous semester
--     CGPA TWGP / TCR, cumulative
--   Return columns are added, so the function is dropped and recreated.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP FUNCTION IF EXISTS assessment.student_gpa(uuid);

CREATE OR REPLACE FUNCTION assessment.student_gpa(p_student uuid)
RETURNS TABLE (session text, semester int, units int, gpa numeric, cgpa numeric,
               published_count int, registered_count int,
               cur int, cue int, wgp numeric, tcr int, tce int, twgp numeric, lcgpa numeric)
LANGUAGE sql STABLE AS $$
    WITH rows AS (SELECT * FROM assessment.student_results(p_student)),
    per AS (
        SELECT r.session, r.semester,
               coalesce(sum(r.units) FILTER (WHERE r.published AND r.outcome = 'GRADED'), 0)::int AS cur,
               coalesce(sum(r.units) FILTER (WHERE r.published AND r.outcome = 'GRADED' AND r.points > 0), 0)::int AS cue,
               coalesce(sum(r.units * r.points) FILTER (WHERE r.published AND r.outcome = 'GRADED'), 0)::numeric AS wgp,
               count(*) FILTER (WHERE r.published)::int AS published_count,
               count(*)::int AS registered_count
          FROM rows r GROUP BY r.session, r.semester),
    cum AS (
        SELECT p.*,
               sum(p.cur) OVER w AS tcr, sum(p.cue) OVER w AS tce, sum(p.wgp) OVER w AS twgp
          FROM per p
        WINDOW w AS (ORDER BY p.session, p.semester ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))
    SELECT c.session, c.semester, c.cur AS units,
           CASE WHEN c.cur > 0 THEN round(c.wgp / c.cur, 2) END AS gpa,
           CASE WHEN c.tcr > 0 THEN round(c.twgp / c.tcr, 2) END AS cgpa,
           c.published_count, c.registered_count,
           c.cur, c.cue, round(c.wgp, 1) AS wgp, c.tcr::int, c.tce::int, round(c.twgp, 1) AS twgp,
           lag(CASE WHEN c.tcr > 0 THEN round(c.twgp / c.tcr, 2) END) OVER (ORDER BY c.session, c.semester) AS lcgpa
      FROM cum c
     ORDER BY c.session, c.semester;
$$;

COMMIT;
