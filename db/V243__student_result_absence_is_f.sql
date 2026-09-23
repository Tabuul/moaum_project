-- ═══════════════════════════════════════════════════════════════════════════
-- V243 — the student's own record reads an absence as the broadsheet does: ABS, graded F, no point
--
--   The broadsheet (Senate's sheet) treats a candidate with no score on a
--   counted set, or recorded absent, as having failed the course: ABS, F0,
--   the units registered and no point, the course owed. The student's own
--   result and GPA came from assessment.student_results, which left such a
--   course blank and out of the GPA, so a student could read a better
--   standing than Senate approved. Now the student's record says the same:
--   on a published sheet, no score or an absence is outcome ABSENT with
--   grade F and 0 points, and the GPA and cumulative functions count its
--   units. Every reader of student_results — the slip, the student's
--   broadsheet, the verification page, the transcript — inherits it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION assessment.student_results(p_student uuid)
RETURNS TABLE (session text, semester int, course_code text, title text, units int, entry_type text,
               stage text, published boolean, published_at timestamptz, senate_minute text,
               ca int, exam int, total int, grade text, points numeric, outcome text, lecturer text)
LANGUAGE sql STABLE AS $$
    SELECT r.session, r.semester, c.code, c.title, e.units, e.entry_type,
           coalesce(cf.stage, 'NO_SHEET'), coalesce(cf.stage = 'PUBLISHED', false), cf.published_at, cf.senate_minute,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.ca END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.exam END,
           CASE WHEN cf.stage = 'PUBLISHED' AND cf.outcome = 'GRADED' THEN cf.total END,
           -- a published sheet with no score, or an absence, is an F: the candidate did not sit
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome = 'GRADED' THEN cf.grade
                                                     WHEN cf.outcome IS NULL OR cf.outcome = 'ABSENT' THEN 'F' END END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome = 'GRADED' THEN cf.points
                                                     WHEN cf.outcome IS NULL OR cf.outcome = 'ABSENT' THEN 0::numeric END END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome IS NULL THEN 'ABSENT' ELSE cf.outcome END END,
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

-- the GPA counts an absence as a failed course: its units registered, no point
CREATE OR REPLACE FUNCTION assessment.student_gpa(p_student uuid)
RETURNS TABLE (session text, semester int, units int, gpa numeric, cgpa numeric,
               published_count int, registered_count int,
               cur int, cue int, wgp numeric, tcr int, tce int, twgp numeric, lcgpa numeric)
LANGUAGE sql STABLE AS $$
    WITH rows AS (SELECT * FROM assessment.student_results(p_student)),
    per AS (
        SELECT r.session, r.semester,
               coalesce(sum(r.units) FILTER (WHERE r.published AND r.outcome IN ('GRADED','ABSENT')), 0)::int AS cur,
               coalesce(sum(r.units) FILTER (WHERE r.published AND r.outcome = 'GRADED' AND r.points > 0), 0)::int AS cue,
               coalesce(sum(r.units * coalesce(r.points, 0)) FILTER (WHERE r.published AND r.outcome IN ('GRADED','ABSENT')), 0)::numeric AS wgp,
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

CREATE OR REPLACE FUNCTION assessment.student_cumulative(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (tcr int, tce int, twgp numeric, cgpa numeric, prev_cgpa numeric)
LANGUAGE sql STABLE AS $$
    WITH r AS (
        SELECT session, semester, units, coalesce(points, 0) AS points
          FROM assessment.student_results(p_student)
         WHERE published AND outcome IN ('GRADED','ABSENT')
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
'The broadsheet''s cumulative-to-date figures for a student at a point in time: TCR, TCE, TWGP, CGPA and the previous CGPA, from the published results up to and including (session, semester); an absence counts as a failed course.';

COMMIT;
