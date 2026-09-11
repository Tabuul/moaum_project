-- ═══════════════════════════════════════════════════════════════════════════
-- V094 — cumulative figures for the broadsheet (the MOAUM senate result format)
--
--   The broadsheet shows a candidate's semester GPA beside the figures "to
--   date": total credits registered (TCR), total credits earned (TCE), total
--   weighted grade points (TWGP), the last CGPA (LCGPA, the standing before this
--   semester) and the CGPA now. All are computed from the published, graded
--   results up to and including the semester in view — never typed.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION assessment.student_cumulative(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (tcr int, tce int, twgp numeric, cgpa numeric, prev_cgpa numeric)
LANGUAGE sql STABLE AS $$
    WITH r AS (
        SELECT session, semester, units, points
          FROM assessment.student_results(p_student)
         WHERE published AND outcome = 'GRADED'
    ),
    upto AS (SELECT * FROM r WHERE (session, semester) <= (p_session, p_semester)),
    prev AS (SELECT * FROM r WHERE (session, semester) <  (p_session, p_semester))
    SELECT coalesce((SELECT sum(units) FROM upto), 0)::int,
           coalesce((SELECT sum(units) FROM upto WHERE points > 0), 0)::int,
           coalesce((SELECT sum(units * points) FROM upto), 0),
           (SELECT CASE WHEN coalesce(sum(units), 0) > 0 THEN round(sum(units * points) / sum(units), 2) END FROM upto),
           (SELECT CASE WHEN coalesce(sum(units), 0) > 0 THEN round(sum(units * points) / sum(units), 2) END FROM prev);
$$;

COMMENT ON FUNCTION assessment.student_cumulative(uuid, text, int) IS
'The broadsheet''s cumulative-to-date figures for a student at a point in time: TCR, TCE, TWGP, CGPA and the previous CGPA, from the published graded results up to and including (session, semester).';

COMMIT;
