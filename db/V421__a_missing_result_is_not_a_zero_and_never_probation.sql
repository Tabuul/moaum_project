-- ═══════════════════════════════════════
-- V421 — a missing result is not a zero, and never probation
--
--   A student whose results were never uploaded read "You are on probation — your CGPA stood at 0.00 after the 2024/2025
--   second semester at 100 level". The cause was V243: on a published sheet, a candidate with no score at all was read as
--   ABSENT, graded F, 0 points, its units counted — so the CGPA fell to 0.00 and the standing pronounced probation. A sheet
--   cannot leave the lecturer with a blank (every candidate on its roster is graded, absent, withheld, incomplete,
--   malpractice or exempted — I-RES-4), so "no score on a published sheet" means the student was never on that sheet: most
--   often a registration migrated from the old portal whose results were not, on a sheet the legacy upload published for the
--   others; or a registration added after the sheet was published. That is no result, not a failure.
--
--   1. assessment.student_results: a published sheet with no outcome for the student is NO_RESULT for them — not published
--      for them, no grade, no points, no outcome. An absence the lecturer recorded stays ABSENT, graded F (it is a result).
--      Every reader inherits it: the GPA and CGPA leave it out (a student with no result has no CGPA, never 0.00); carryovers
--      never came from it (only a published F does); a transcript or statement reports it as not yet published; the 100-level
--      decision reads the semester as incomplete, not as advice to withdraw.
--   2. assessment.student_standing: pronounced only on the latest semester whose results are complete — every registered
--      course published — and whose CGPA can be computed; a partial semester never pronounces. Before any such semester the
--      standing is NOT_AVAILABLE (it was GOOD), so nothing reads a missing result as good or as bad standing.
--   3. The probation threshold is the University's setting (policy.standing_setting.probation_below_cgpa, 1.00 until changed
--      by the Academic Office or the Registry), read by assessment.standing_of — not a constant.
--   4. assessment.student_result_periods / student_result_status: each registered semester's result status — PUBLISHED (all
--      published), INCOMPLETE (some), UNDER_VERIFICATION or PROCESSING (in the approval chain), NOT_AVAILABLE (nothing past
--      entry) — and the latest semester that has ended, with the message the student reads.
--   5. assessment.result_status_counts: for the offices, how many students of a department, faculty or programme stand in each result
--      status for a semester, with those on probation counted only from complete published results.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V421: a missing result is not a zero, and never probation', true);

-- ── 3 · the probation threshold, the University's setting ──
CREATE TABLE policy.standing_setting (
    row_no              boolean PRIMARY KEY DEFAULT true CHECK (row_no),
    probation_below_cgpa numeric(3,2) NOT NULL DEFAULT 1.00 CHECK (probation_below_cgpa > 0 AND probation_below_cgpa <= 5),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    updated_by          uuid NULL,
    updated_office      text NULL REFERENCES ref.office(code)
);
SELECT audit.attach('policy.standing_setting');
INSERT INTO policy.standing_setting (row_no) VALUES (true);
COMMENT ON TABLE policy.standing_setting IS
  'V421: the University''s academic standing rule — a CGPA below probation_below_cgpa, on complete published results, is probation (or advice to withdraw after it). Set by the Academic Office or the Registry.';

CREATE FUNCTION policy.probation_below_cgpa()
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT probation_below_cgpa FROM policy.standing_setting WHERE row_no), 1.00);
$fn$;

CREATE FUNCTION policy.set_probation_below_cgpa(p_cgpa numeric)
RETURNS numeric LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL OR coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'STANDING_SETTING_OFFICE: the probation threshold is set by the Academic Office or the Registry' USING ERRCODE = '23514';
    END IF;
    IF p_cgpa IS NULL OR p_cgpa <= 0 OR p_cgpa > 5 THEN
        RAISE EXCEPTION 'STANDING_SETTING_CGPA: the threshold is a CGPA above 0 and at most 5' USING ERRCODE = '23514';
    END IF;
    UPDATE policy.standing_setting SET probation_below_cgpa = round(p_cgpa, 2), updated_at = now(), updated_by = who, updated_office = v_office WHERE row_no;
    RETURN round(p_cgpa, 2);
END $fn$;

CREATE OR REPLACE FUNCTION assessment.standing_of(p_level integer, p_semester integer, p_cgpa numeric, p_prev_cgpa numeric, p_de_at_200 boolean)
RETURNS text LANGUAGE sql STABLE AS $fn$
    WITH t AS (SELECT policy.probation_below_cgpa() AS below)
    SELECT CASE
        WHEN p_cgpa IS NULL OR p_cgpa >= t.below THEN NULL
        -- a first semester: the probation list, from 200 level, never a Direct Entry student's 200 level
        WHEN p_semester = 1 THEN CASE WHEN p_level >= 200 AND NOT coalesce(p_de_at_200, false) THEN 'PROBATION' END
        -- a second semester: still under the threshold after that level's probation list is advice to withdraw;
        -- otherwise (100 level, a fresh fall, a Direct Entry student's 200 level) probation
        WHEN p_level >= 200 AND NOT coalesce(p_de_at_200, false) AND p_prev_cgpa IS NOT NULL AND p_prev_cgpa < t.below THEN 'ADVISED_TO_WITHDRAW'
        ELSE 'PROBATION'
    END
      FROM t
$fn$;
COMMENT ON FUNCTION assessment.standing_of(integer, integer, numeric, numeric, boolean) IS
  'V244, V246, V421: the standing a semester''s CGPA pronounces, against the University''s probation threshold (policy.probation_below_cgpa) — NULL when there is no CGPA or it meets the threshold.';

-- ── 1 · no outcome on a published sheet is no result for the student ──
CREATE OR REPLACE FUNCTION assessment.student_results(p_student uuid)
RETURNS TABLE(session text, semester integer, course_code text, title text, units integer, entry_type text, stage text, published boolean,
              published_at timestamp with time zone, senate_minute text, ca integer, exam integer, total integer, grade text, points numeric,
              outcome text, lecturer text)
LANGUAGE sql STABLE AS $fn$
    SELECT r.session, r.semester, c.code, coalesce(o.title, c.title), e.units, e.entry_type,
           -- V421: a published sheet the student is not on (no outcome for them) is no result — never an absence
           CASE WHEN cf.stage = 'PUBLISHED' AND cf.outcome IS NULL THEN 'NO_RESULT' ELSE coalesce(cf.stage, 'NO_SHEET') END,
           coalesce(cf.stage = 'PUBLISHED' AND cf.outcome IS NOT NULL, false),
           CASE WHEN cf.outcome IS NOT NULL THEN cf.published_at END, CASE WHEN cf.outcome IS NOT NULL THEN cf.senate_minute END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.ca END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.exam END,
           CASE WHEN cf.stage = 'PUBLISHED' AND cf.outcome = 'GRADED' THEN cf.total END,
           -- a recorded absence is an F: the candidate did not sit
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome = 'GRADED' THEN cf.grade WHEN cf.outcome = 'ABSENT' THEN 'F' END END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome = 'GRADED' THEN cf.points WHEN cf.outcome = 'ABSENT' THEN 0::numeric END END,
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
$fn$;
COMMENT ON FUNCTION assessment.student_results(uuid) IS
  'V243, V421: the student''s courses and their final results — published only where the published sheet has an outcome for them; a recorded absence is F; no outcome on a published sheet is NO_RESULT (no grade, no points), never a failure.';

-- ── 2 · the standing, pronounced only on a complete semester ──
CREATE OR REPLACE FUNCTION assessment.student_standing(p_student uuid)
RETURNS TABLE(standing text, cgpa numeric, pronounced_session text, pronounced_semester integer, pronounced_level integer)
LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    sems AS (
        SELECT g.session, g.semester, g.cgpa, g.lcgpa, r.level
          FROM assessment.student_gpa(p_student) g
          JOIN registration.course_registration r ON r.student_id = p_student AND r.session = g.session AND r.semester = g.semester
         -- V421: only a semester whose every registered course is published, with a CGPA computed from real results
         WHERE g.cgpa IS NOT NULL AND g.published_count > 0 AND g.published_count = g.registered_count
    ),
    latest AS (SELECT * FROM sems ORDER BY session DESC, semester DESC LIMIT 1)
    SELECT coalesce(assessment.standing_of(l.level, l.semester, l.cgpa, l.lcgpa, s.entry_mode = 'DIRECT_ENTRY' AND l.level = 200), 'GOOD'),
           l.cgpa, l.session, l.semester, l.level
      FROM latest l CROSS JOIN s
    UNION ALL
    -- no complete published semester yet: the standing cannot be told — never good, never probation
    SELECT 'NOT_AVAILABLE', NULL, NULL, NULL, NULL WHERE NOT EXISTS (SELECT 1 FROM latest)
$fn$;
COMMENT ON FUNCTION assessment.student_standing(uuid) IS
  'V244, V246, V421: the standing pronounced by the latest complete published semester (every registered course published) — PROBATION, ADVISED_TO_WITHDRAW or GOOD against the University''s threshold; NOT_AVAILABLE before any such semester.';

-- ── 4 · each registered semester's result status, and the one the student is told about ──
CREATE FUNCTION assessment.student_result_periods(p_student uuid)
RETURNS TABLE(session text, semester integer, level integer, registered integer, published integer, in_chain integer, at_verification integer,
              status text, in_progress boolean)
LANGUAGE sql STABLE AS $fn$
    WITH rows AS (SELECT * FROM assessment.student_results(p_student)),
    per AS (
        SELECT x.session, x.semester, count(*)::int AS registered, count(*) FILTER (WHERE x.published)::int AS published,
               count(*) FILTER (WHERE NOT x.published AND x.stage IN ('DEPT_BOARD', 'FACULTY_SCRUTINY', 'FACULTY_COMPILATION', 'FACULTY_BOARD', 'RECORDS', 'SENATE'))::int AS in_chain,
               count(*) FILTER (WHERE NOT x.published AND x.stage = 'VERIFICATION')::int AS at_verification
          FROM rows x GROUP BY x.session, x.semester)
    SELECT p.session, p.semester,
           (SELECT r.level FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p.session AND r.semester = p.semester
             ORDER BY r.level DESC LIMIT 1),
           p.registered, p.published, p.in_chain, p.at_verification,
           CASE WHEN p.published = p.registered THEN 'PUBLISHED'
                WHEN p.published > 0 THEN 'INCOMPLETE'
                WHEN p.in_chain > 0 THEN 'PROCESSING'
                WHEN p.at_verification > 0 THEN 'UNDER_VERIFICATION'
                ELSE 'NOT_AVAILABLE' END,
           -- the semester still running on the University's calendar (or the CCE calendar): its results are not yet due
           EXISTS (SELECT 1 FROM policy.semester m WHERE m.session = p.session AND m.number = p.semester AND m.state IN ('OPEN', 'NOT_YET_OPEN'))
             OR EXISTS (SELECT 1 FROM policy.route_semester m JOIN people.student st ON st.id = p_student AND st.entry_mode = 'CCE'
                         WHERE m.route = 'CCE' AND m.session = p.session AND m.number = p.semester AND m.state IN ('OPEN', 'NOT_YET_OPEN'))
      FROM per p
     ORDER BY p.session, p.semester;
$fn$;
COMMENT ON FUNCTION assessment.student_result_periods(uuid) IS
  'V421: each registered semester''s result status for the student — PUBLISHED, INCOMPLETE, PROCESSING, UNDER_VERIFICATION or NOT_AVAILABLE — and whether the semester is still running.';

CREATE FUNCTION assessment.student_result_status(p_student uuid)
RETURNS TABLE(session text, semester integer, level integer, status text, registered integer, published integer, message text)
LANGUAGE sql STABLE AS $fn$
    WITH p AS (SELECT * FROM assessment.student_result_periods(p_student) x WHERE NOT x.in_progress ORDER BY x.session DESC, x.semester DESC LIMIT 1),
    w AS (SELECT p.*, p.session || ' ' || CASE p.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE p.semester::text END || ' semester' AS period FROM p)
    SELECT w.session, w.semester, w.level, w.status, w.registered, w.published,
           CASE w.status
               WHEN 'NOT_AVAILABLE' THEN 'Your result for the ' || w.period || ' has not yet been uploaded or published.'
               WHEN 'UNDER_VERIFICATION' THEN 'Your result for the ' || w.period || ' is under verification.'
               WHEN 'PROCESSING' THEN 'Your result for the ' || w.period || ' is being processed and has not yet been published.'
               WHEN 'INCOMPLETE' THEN w.published || ' of your ' || w.registered || ' courses for the ' || w.period
                                      || ' are published; the rest are still being processed. Your standing is read when the semester''s results are complete.'
           END
      FROM w;
$fn$;
COMMENT ON FUNCTION assessment.student_result_status(uuid) IS
  'V421: the latest semester that has ended, its result status and the message the student reads (none when its results are complete).';

-- ── 5 · for the offices: students of a department or faculty by result status, for a semester ──
CREATE FUNCTION assessment.result_status_counts(p_dept text, p_faculty text, p_programme text, p_session text, p_semester integer)
RETURNS TABLE(status text, students bigint)
LANGUAGE sql STABLE AS $fn$
    WITH st AS (
        SELECT DISTINCT r.student_id
          FROM registration.course_registration r
          JOIN people.student s ON s.id = r.student_id
          JOIN ref.programme pr ON pr.code = s.programme_code
         WHERE r.session = p_session AND r.semester = p_semester AND r.status IN ('APPROVED', 'LOCKED')
           AND (p_dept IS NULL OR pr.dept_code = p_dept) AND (p_faculty IS NULL OR pr.faculty_code = p_faculty)
           AND (p_programme IS NULL OR s.programme_code = p_programme)),
    per AS (
        SELECT st.student_id, x.status,
               (SELECT g.standing FROM assessment.student_standing(st.student_id) g LIMIT 1) AS standing
          FROM st JOIN LATERAL (SELECT y.status FROM assessment.student_result_periods(st.student_id) y
                                 WHERE y.session = p_session AND y.semester = p_semester) x ON true)
    SELECT v.status, count(*) FROM (
        SELECT per.status FROM per
        UNION ALL
        -- probation and advice to withdraw, only where the standing was pronounced on complete published results
        SELECT per.standing FROM per WHERE per.standing IN ('PROBATION', 'ADVISED_TO_WITHDRAW')) v
     GROUP BY v.status;
$fn$;
COMMENT ON FUNCTION assessment.result_status_counts(text, text, text, text, integer) IS
  'V421: how many students of a department, faculty or programme (or all, all NULL) registered for a semester stand in each result status — NOT_AVAILABLE, UNDER_VERIFICATION, PROCESSING, INCOMPLETE, PUBLISHED — with PROBATION and ADVISED_TO_WITHDRAW counted from complete published results only.';

COMMIT;
