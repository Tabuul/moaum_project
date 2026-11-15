-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V767 — Database reads made lighter for a smaller database
--
--   The portal's database was enlarged on 26 October 2026 and is to be brought back to a smaller size. Measured on a copy of the
--   live data replaying students' and applicants' page loads (statement statistics per call), the work that dominated is put
--   right where it is read, with every answer unchanged:
--     · finance.gst_eps_rows(session, student) — the GST/EPS courses a student owes, behind the dashboard's GST & EPS panel, the
--       registration page's GST gate, the GST entitlement and the payable courses — was written for the whole register and for
--       one student at once ("p_student IS NULL OR …"). Asked for one student inside another function or a kept plan, the
--       student's own rows could not be found by their keys: every student of the register was read, every GST registration
--       entry of the register (about 50,000) joined, and every score on the student's GST sheets (about 13,000) read, for one
--       student's handful of rows — about 350 ms a call. The register and the one student are now two branches, one of them
--       skipped at once: the student's registrations are read by the student's key and the student's own latest scores alone,
--       about 9 ms a call. The register's branch is the rule as it was. (The rows for one student, and the register's, were
--       compared row for row on the copy: the same.)
--
--   With it, in the API (no change to any answer; every student's and applicant's responses compared old against new on the copy):
--     · the sessions a postgraduate, CCE or MBBS student has fees in (StudentPortalRepository.sessionsWithChargesFor, read on every
--       screen of theirs) are listed before each is tested: left in a subquery, finance.fee_stated was pushed below the DISTINCT and
--       asked once for every fee line (851 times for two sessions, about 4 s) — more than half the database's time in the replay;
--     · the registration page and Add Other Course ask the GST gate of all their GST/EPS courses in one call (gst_gate_many), not
--       once a course; the dashboard's GST panel reads the student's requirement alone (finance.gst_eps_eligibility), not the whole
--       explanation it used to work out only to drop;
--     · iam/me, asked on every screen, no longer counts the University's queues (over the whole register) or reads the staff
--       record for a student or an applicant, whose screens show neither; a student keeps the bell, their own unread notices.
--   Measured on the copy (400 students, 200 applicants, 3,000 page loads): the database's time from 1,958 s to 350 s, the pages
--   read from 31.7 to 17.8 million.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V767: database reads made lighter for a smaller database', true);

CREATE OR REPLACE FUNCTION finance.gst_eps_rows(p_session text, p_student uuid DEFAULT NULL::uuid)
 RETURNS TABLE(student_id uuid, course_code text, title text, units integer, office text, level integer, semesters integer[], offering_id uuid, source text, counts boolean, status text, registered boolean, failed_in text, last_grade text, passed_in text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH cur AS (SELECT coalesce(max(name), '') AS name FROM policy.academic_session WHERE state = 'CURRENT'),
    -- V711: the Bursary's spillover basis (finance.spill_basis) and each undergraduate programme's final level, read once (only the
    -- student's own programme when one student is asked for)
    sb AS MATERIALIZED (SELECT finance.spill_basis() AS basis),
    fl AS MATERIALIZED (SELECT p.code, finance.final_level(p.code) AS final_level FROM ref.programme p
                         WHERE p.category = 'UNDER GRADUATE' AND (p_student IS NULL OR p.code = (SELECT st.programme_code FROM people.student st WHERE st.id = p_student))),
    -- the undergraduates in good standing it may concern, at the level the session reads them at
    -- the register, or the one student asked for: two branches, one of them skipped at once, so the student's is read by its key
    -- whatever plan the caller's statement keeps
    base AS MATERIALIZED (
        SELECT s.id, s.programme_code, s.curriculum_track, s.curriculum_version,
               CASE WHEN p_session >= coalesce(ss.session, cur.name) THEN s.current_level
                    ELSE (SELECT max(cr.level) FROM registration.course_registration cr WHERE cr.student_id = s.id AND cr.session = p_session) END AS level
          FROM (SELECT x.* FROM people.student x WHERE p_student IS NULL
                UNION ALL
                SELECT x.* FROM people.student x WHERE p_student IS NOT NULL AND x.id = p_student) s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          CROSS JOIN cur
          LEFT JOIN people.study_session ss ON ss.student_id = s.id   -- V733
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND s.entry_mode IS DISTINCT FROM 'CCE'),   -- V380: the GST/EPS fee is the full-time students'; the Bursary states CCE fees as CCE lines
    -- V711: the students in spillover in the session they are at now — finance.spill's rule (V571, V637) read over the register at once
    -- (asked student by student it cost the desk's whole-register read most of a second): on the cohort basis, the cohort engine's
    -- spillover state; on the level basis, above the programme's final level, or at it in a spillover state (SP1/SP2). The state is
    -- looked up only for a student it can decide. Kept apart from the engine's own reads so their plan is not touched.
    sp AS (SELECT c.id
             FROM (SELECT b.id, s.current_level, fl.final_level, sb.basis
                     FROM base b JOIN people.student s ON s.id = b.id JOIN fl ON fl.code = s.programme_code CROSS JOIN sb CROSS JOIN cur
                    WHERE p_session >= coalesce(people.own_session(b.id), cur.name) AND (sb.basis = 'COHORT' OR s.current_level >= fl.final_level)) c
            WHERE CASE WHEN c.basis <> 'COHORT' AND c.current_level > c.final_level THEN true
                       ELSE coalesce((SELECT ap.spillover_state LIKE 'SPILLOVER%' FROM people.academic_position ap WHERE ap.student_id = c.id), false) END),
    gc AS (SELECT c.code, c.title, c.units, c.level, c.general_office, c.curriculum, c.state
             FROM catalogue.course c WHERE c.kind = 'GST' AND c.general_office IS NOT NULL AND c.code NOT LIKE 'DMO %'),
    -- the GST/EPS courses the session runs, in which semesters
    offered AS (SELECT o.course_code, array_agg(o.semester ORDER BY o.semester) AS semesters, (array_agg(o.id ORDER BY o.semester))[1] AS offering_id
                  FROM catalogue.offering o JOIN gc ON gc.code = o.course_code
                 WHERE o.session = p_session AND o.stream = 'REGULAR'
                 GROUP BY o.course_code),
    -- every GST/EPS registration entry of these students up to the session
    -- (one student asked for: read from the student's own registrations, never from every GST entry of the register)
    ent AS (SELECT cr.student_id, cr.session, cr.semester, cr.status AS reg_status, e.status AS entry_status, o.id AS offering_id, o.course_code
              FROM base b
              JOIN registration.course_registration cr ON cr.student_id = b.id AND cr.session <= p_session
              JOIN registration.entry e ON e.registration_id = cr.id
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN gc ON gc.code = o.course_code
             WHERE p_student IS NULL
            UNION ALL
            SELECT cr.student_id, cr.session, cr.semester, cr.status AS reg_status, e.status AS entry_status, o.id AS offering_id, o.course_code
              FROM registration.course_registration cr
              JOIN base b ON b.id = cr.student_id
              JOIN registration.entry e ON e.registration_id = cr.id
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN gc ON gc.code = o.course_code
             WHERE p_student IS NOT NULL AND cr.student_id = p_student AND cr.session <= p_session),
    -- the record's results: the entries of approved registrations, as assessment.student_results reads them
    rec AS (SELECT DISTINCT x.student_id, x.session, x.semester, x.offering_id, x.course_code FROM ent x
             WHERE x.reg_status IN ('APPROVED', 'LOCKED') AND x.entry_status IN ('REGISTERED', 'APPROVED')),
    sheets AS (SELECT sh.id, sh.offering_id, sh.stage, coalesce(es.kind, 'MAIN') AS kind
                 FROM assessment.score_sheet sh
                 LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
                WHERE sh.offering_id IN (SELECT r.offering_id FROM rec r)),
    -- each sheet's latest scores read once, not once per student
    -- one student asked for: that student's latest scores alone (latest_scores keyed on the student, the score index read for them);
    -- the whole register: every student's on the sheets
    scores AS MATERIALIZED (SELECT sh.id AS sheet_id, ls.student_id, ls.points, ls.outcome, ls.grade
                              FROM sheets sh CROSS JOIN LATERAL assessment.latest_scores(sh.id) ls
                             WHERE p_student IS NULL
                            UNION ALL
                            SELECT sh.id AS sheet_id, ls.student_id, ls.points, ls.outcome, ls.grade
                              FROM sheets sh CROSS JOIN LATERAL assessment.latest_scores(sh.id) ls
                             WHERE p_student IS NOT NULL AND ls.student_id = p_student),
    sitting AS (SELECT r.student_id, r.session, r.semester, r.offering_id, r.course_code, sh.stage, sh.kind, sc.points, sc.outcome, sc.grade,
                       CASE sh.kind WHEN 'SPECIAL' THEN 1 WHEN 'RESIT' THEN 2 ELSE 3 END AS pr
                  FROM rec r JOIN sheets sh ON sh.offering_id = r.offering_id
                  LEFT JOIN scores sc ON sc.sheet_id = sh.id AND sc.student_id = r.student_id),
    -- assessment.course_final's resolution: a published special or re-sit the student sat supersedes the main sitting
    fin AS (SELECT DISTINCT ON (x.student_id, x.offering_id) x.*
                FROM sitting x
               WHERE (x.kind IN ('SPECIAL', 'RESIT') AND x.stage = 'PUBLISHED' AND x.outcome IS NOT NULL) OR x.kind = 'MAIN'
               ORDER BY x.student_id, x.offering_id, x.pr),
    -- V422: a recorded absence is failed too (an F, owed again), as registration.carryovers reads it
    res AS (SELECT f.student_id, f.course_code, f.session, f.semester,
                   CASE WHEN f.stage = 'PUBLISHED' AND f.outcome = 'ABSENT' THEN 'F' ELSE f.grade END AS grade,
                   coalesce(f.stage = 'PUBLISHED' AND f.outcome = 'GRADED' AND f.points > 0, false) AS passed,
                   coalesce(f.stage = 'PUBLISHED' AND (f.outcome = 'ABSENT' OR (f.outcome = 'GRADED' AND f.points = 0)), false) AS failed
              FROM fin f),
    -- registration.carryovers_at's rule as of the session's start: failed, not passed since, never an elective
    carry AS (SELECT DISTINCT ON (f.student_id, f.course_code) f.student_id, f.course_code, f.session || ' semester ' || f.semester AS failed_in, f.grade
                FROM res f JOIN base b ON b.id = f.student_id
               WHERE f.failed AND f.session < p_session
                 AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co
                                  WHERE co.course_code = f.course_code AND co.programme_code = b.programme_code AND co.basis = 'Elective')
                 AND NOT EXISTS (SELECT 1 FROM res g
                                  WHERE g.student_id = f.student_id AND g.course_code = f.course_code AND g.passed
                                    AND (g.session, g.semester) > (f.session, f.semester) AND g.session < p_session)
               ORDER BY f.student_id, f.course_code, f.session, f.semester),
    pass AS (SELECT r.student_id, r.course_code, bool_or(r.session < p_session) AS before, bool_or(r.session = p_session) AS now,
                    max(r.session || ' semester ' || r.semester) AS passed_in
               FROM res r WHERE r.passed GROUP BY r.student_id, r.course_code),
    fail_now AS (SELECT DISTINCT r.student_id, r.course_code FROM res r WHERE r.failed AND r.session = p_session),
    reg AS (SELECT x.student_id, x.course_code FROM ent x WHERE x.session = p_session AND x.entry_status <> 'DROPPED' GROUP BY x.student_id, x.course_code),
    -- the programme's own GST/EPS courses at the student's level, read as the registration menu reads them
    curric AS (SELECT b.id AS student_id, co.course_code, co.level
                 FROM base b
                 JOIN catalogue.course_offer co ON co.programme_code = b.programme_code AND co.level = b.level
                                               AND (co.track IS NULL OR b.curriculum_track IS NULL OR co.track = b.curriculum_track)
                 JOIN gc ON gc.code = co.course_code AND gc.state <> 'ENDED'
                WHERE gc.curriculum IS NULL OR b.curriculum_version IS NULL OR gc.curriculum = b.curriculum_version),
    src AS (SELECT c.student_id, c.course_code, 'CARRYOVER'::text AS source, 1 AS pr, NULL::int AS level FROM carry c
            UNION ALL SELECT c.student_id, c.course_code, 'COURSE_OFFERING', 2, c.level FROM curric c
            UNION ALL SELECT r.student_id, r.course_code, 'REGISTERED', 3, NULL FROM reg r),
    one AS (SELECT DISTINCT ON (s.student_id, s.course_code) s.* FROM src s ORDER BY s.student_id, s.course_code, s.pr)
    SELECT o.student_id, o.course_code, gc.title, gc.units, coalesce(gc.general_office, 'GST'), coalesce(o.level, gc.level), off.semesters, off.offering_id, CASE WHEN sp.id IS NOT NULL AND rg.course_code IS NOT NULL THEN 'REGISTERED' ELSE o.source END,
           -- owed this session: being taken; or run this session and still owed (a carryover, or the programme's course not yet passed)
           (rg.course_code IS NOT NULL OR (off.course_code IS NOT NULL AND (o.source = 'CARRYOVER' OR (NOT coalesce(ps.before, false) AND sp.id IS NULL)))),
           CASE WHEN coalesce(ps.now, false) THEN 'COMPLETED'
                WHEN fn.course_code IS NOT NULL THEN 'FAILED'
                WHEN rg.course_code IS NOT NULL THEN 'REGISTERED'
                WHEN o.source = 'COURSE_OFFERING' AND coalesce(ps.before, false) THEN 'ALREADY_PASSED'
                WHEN off.course_code IS NULL THEN 'NOT_OFFERED'
                WHEN sp.id IS NOT NULL THEN 'NOT_OWED_SPILLOVER'
                ELSE 'OUTSTANDING' END,
           rg.course_code IS NOT NULL, ca.failed_in, ca.grade, ps.passed_in
      FROM one o
      JOIN gc ON gc.code = o.course_code
      LEFT JOIN offered off ON off.course_code = o.course_code
      LEFT JOIN reg rg ON rg.student_id = o.student_id AND rg.course_code = o.course_code
      LEFT JOIN pass ps ON ps.student_id = o.student_id AND ps.course_code = o.course_code
      LEFT JOIN fail_now fn ON fn.student_id = o.student_id AND fn.course_code = o.course_code
      LEFT JOIN carry ca ON ca.student_id = o.student_id AND ca.course_code = o.course_code
      LEFT JOIN sp ON sp.id = o.student_id AND o.source = 'COURSE_OFFERING'
$function$;

COMMENT ON FUNCTION finance.gst_eps_rows(text, uuid) IS
  'V366 and after; V767: the GST/EPS courses each student owes in a session (the register, or one student) — one student read by their own keys (their registrations, their latest scores), never through the register';

COMMIT;
