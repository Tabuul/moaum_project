-- V531: the CGPA of every student named, read at once.
--
-- Records & Queries showed the CGPA beside each student only for a scope of up to 1,500 students, because each was worked out by
-- assessment.student_gpa in turn — about 15 ms a student on the live-shaped copy (500 students of Biological Sciences in 7.3 s), a
-- faculty of 9,600 in minutes. assessment.scope_cgpa gives the same CGPA for a list of students in one pass: each score sheet's
-- latest scores are read once (assessment.latest_scores) for every student on it, and the result each registered course counts
-- is chosen as assessment.course_final chooses it — a published special or re-sit the student sat before the main sheet, a re-sit
-- passed recorded at the pass mark of the class's grading scheme, an absence counted as an F — over the student's approved
-- registrations, as assessment.student_results reads them. The CGPA is the cumulative one of the student's latest semester, which
-- is the weighted grade points of every published graded or absent course over their units (assessment.student_gpa's cgpa on its
-- last row); a student with no published result has none.
--
-- And the fee position of the students named, read at once (finance.fee_positions_of): what the fee schedule states for them,
-- asked once for each fee profile (the profile V524 reads by), and the session's due, paid, balance and instalments from
-- finance.session_fee_positions — the CCE fee summary reads it for a large CCE register, where each student's
-- finance.fee_stated and finance.position in turn slow down after some thousands of calls.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.reason', 'V531: the CGPA of every student named, read at once', true);

CREATE FUNCTION assessment.scope_cgpa(p_students uuid[])
RETURNS TABLE(student_id uuid, cgpa numeric) LANGUAGE sql STABLE AS $function$
    WITH them AS MATERIALIZED (SELECT DISTINCT x AS id FROM unnest(p_students) x WHERE x IS NOT NULL),
    ent AS MATERIALIZED (   -- the courses on each student's approved registrations, as student_results reads them
        SELECT e.registration_id, r.student_id, e.offering_id, e.units
          FROM them t
          JOIN registration.course_registration r ON r.student_id = t.id
          JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code
         WHERE r.status IN ('APPROVED', 'LOCKED')),
    sheets AS MATERIALIZED (
        SELECT sh.id AS sheet_id, sh.offering_id, sh.stage, coalesce(es.kind, 'MAIN') AS kind
          FROM assessment.score_sheet sh
          LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
         WHERE sh.offering_id IN (SELECT DISTINCT en.offering_id FROM ent en)),
    scores AS MATERIALIZED (   -- each sheet's latest scores, read once for every student on it
        SELECT s.sheet_id, ls.student_id, ls.points, ls.outcome
          FROM sheets s CROSS JOIN LATERAL assessment.latest_scores(s.sheet_id) ls
         WHERE ls.student_id IN (SELECT t.id FROM them t)),
    sittings AS (   -- as course_final: a published special or re-sit the student sat, or the main sheet
        SELECT en.registration_id, en.student_id, en.offering_id, en.units, s.stage, sc.points, sc.outcome,
               CASE s.kind WHEN 'SPECIAL' THEN 1 WHEN 'RESIT' THEN 2 ELSE 3 END AS pr
          FROM ent en
          JOIN sheets s ON s.offering_id = en.offering_id
          LEFT JOIN scores sc ON sc.sheet_id = s.sheet_id AND sc.student_id = en.student_id
         WHERE (s.kind IN ('SPECIAL', 'RESIT') AND s.stage = 'PUBLISHED' AND sc.outcome IS NOT NULL) OR s.kind = 'MAIN'),
    picked AS MATERIALIZED (
        SELECT DISTINCT ON (x.registration_id, x.offering_id) x.* FROM sittings x ORDER BY x.registration_id, x.offering_id, x.pr),
    pass AS (   -- the pass mark of the class's standing grading scheme: the lowest band scoring points
        SELECT o.offering_id,
               (SELECT b.points FROM policy.grade_band b
                 WHERE b.version_id = coalesce(policy.in_force('grading', policy.grading_scope(o.offering_id), current_date),
                                               policy.in_force('grading', 'UNIVERSITY', current_date))
                   AND b.points > 0
                 ORDER BY b.points ASC LIMIT 1) AS points
          FROM (SELECT DISTINCT p.offering_id FROM picked p WHERE p.pr = 2) o),
    counted AS (   -- a published course graded or absent counts its units; an absence scores nothing
        SELECT p.student_id, p.units,
               CASE WHEN p.outcome = 'ABSENT' THEN 0::numeric
                    WHEN p.pr = 2 AND coalesce(p.points, 0) > 0 THEN (SELECT ps.points FROM pass ps WHERE ps.offering_id = p.offering_id)
                    ELSE p.points END AS points
          FROM picked p
         WHERE p.stage = 'PUBLISHED' AND p.outcome IN ('GRADED', 'ABSENT'))
    SELECT c.student_id,
           CASE WHEN sum(c.units) > 0 THEN round(sum(c.units * coalesce(c.points, 0))::numeric / sum(c.units), 2) END
      FROM counted c
     GROUP BY c.student_id
$function$;

COMMENT ON FUNCTION assessment.scope_cgpa(uuid[]) IS
  'V531: the CGPA of each student named, as assessment.student_gpa gives it on the student''s latest semester, read in one pass (a student with no published graded or absent course is not returned)';

CREATE FUNCTION finance.fee_positions_of(p_session text, p_students uuid[])
RETURNS TABLE(student_id uuid, stated boolean, due numeric, paid numeric, balance numeric, instalments_paid integer, paid_in_full boolean, has_arrears boolean)
LANGUAGE sql STABLE AS $function$
    WITH them AS MATERIALIZED (SELECT DISTINCT x AS id FROM unnest(p_students) x WHERE x IS NOT NULL),
    prof AS MATERIALIZED (   -- the fee schedule's answers depend only on the fee profile (V524)
        SELECT t.id AS student_id,
               CASE WHEN fp.student_id IS NULL THEN t.id::text
                    ELSE row(fp.programme_code, fp.current_level, fp.entry_mode, fp.state, fp.is_spill)::text END AS k
          FROM them t LEFT JOIN finance.fee_profiles() fp ON fp.student_id = t.id),
    said AS MATERIALIZED (
        SELECT r.k, finance.fee_stated(r.student_id, p_session) AS stated
          FROM (SELECT DISTINCT ON (p.k) p.k, p.student_id FROM prof p ORDER BY p.k, p.student_id) r),
    pos AS MATERIALIZED (SELECT f.* FROM finance.session_fee_positions(p_session) f WHERE f.student_id IN (SELECT t.id FROM them t))
    SELECT pf.student_id, sd.stated, coalesce(p.due, 0), coalesce(p.paid, 0), coalesce(p.balance, 0), coalesce(p.instalments_paid, 2),
           coalesce(p.paid_in_full, true), coalesce(p.has_arrears, false)
      FROM prof pf JOIN said sd ON sd.k = pf.k LEFT JOIN pos p ON p.student_id = pf.student_id
$function$;

COMMENT ON FUNCTION finance.fee_positions_of(text, uuid[]) IS
  'V531: for each student named, finance.fee_stated (asked once for each fee profile) and finance.position''s due, paid, balance, instalments, paid in full and arrears for the session, read at once';

COMMIT;
