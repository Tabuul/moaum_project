-- ═══════════════════════════════════════
-- V422 — a late result through the chain, and every outcome read alike on the student's record and the Senate's sheet
--
--   1. A late result. A candidate on a published sheet's roll with no mark on it (a registration added after the sheet was
--      published, or migrated without its result) had no way to a result: an amendment corrects a mark, and there was none
--      to correct (RES_AMEND_NO_MARK). assessment.raise_amendment now raises a LATE result for such a candidate — the same
--      chain, desk by desk, applied by the Registrar on the Senate minute as the candidate's first mark on the sheet, the
--      student told that the result is published. A student not on the sheet's roll is still refused (RES_AMEND_NO_MARK).
--   2. The outcomes, as the University rules them (13 October 2026), read alike everywhere:
--      - ABSENT: an F, counted, and owed — a carryover (registration.carryovers, carryovers_at) and, for a GST/EPS course,
--        owed again (finance.gst_eps_rows), as the Senate's sheet already owed it (CO:).
--      - WITHHELD, INCOMPLETE, MALPRACTICE: held for Senate — never counted, never owed, never an F before Senate decides;
--        the semester is not complete while one is held, so no standing is pronounced on it (assessment.student_standing)
--        and the student reads HELD (assessment.student_result_periods / student_result_status). Senate's decision comes as
--        an amendment of the mark.
--      - EXEMPTED: not counted, not owed; the semester can be complete.
--      The broadsheet (ResultsService) reads the same rules.
-- ═══════════════════════════════════════

BEGIN;

-- ── 1 · a late result: an amendment with no mark before it ──
ALTER TABLE assessment.amendment
    ADD COLUMN kind text NOT NULL DEFAULT 'AMEND' CHECK (kind IN ('AMEND', 'LATE')),
    ALTER COLUMN was_version DROP NOT NULL,
    ALTER COLUMN was_outcome DROP NOT NULL,
    ADD CONSTRAINT ck_amendment_late CHECK ((kind = 'LATE') = (was_version IS NULL) AND (kind = 'LATE') = (was_outcome IS NULL));
COMMENT ON COLUMN assessment.amendment.kind IS
  'V422: AMEND corrects a published mark (was_* hold it); LATE gives a candidate on the published sheet''s roll their first mark (no was_*).';

/* raised by the desk of entry on a published sheet: for a student with a mark on it, a correction; for a student on its roll
   with no mark, a late result (V422) */
CREATE OR REPLACE FUNCTION assessment.raise_amendment(p_sheet uuid, p_student uuid, p_ca int, p_exam int, p_outcome text, p_reason text, p_query uuid)
RETURNS uuid
LANGUAGE plpgsql AS $function$
DECLARE v_stage text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); was record; v_out text := upper(coalesce(nullif(btrim(p_outcome), ''), 'GRADED'));
        v_ca int; v_exam int; v_ca_max int; v_code text; v_query uuid := p_query; v_id uuid; v_year text := to_char(current_date, 'YYYY');
        v_kind text := 'AMEND';
BEGIN
    PERFORM assessment.require_stage_desk('ENTRY', v_office, 'raised');
    SELECT s.stage, c.ca_max, c.code INTO v_stage, v_ca_max, v_code
      FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id JOIN catalogue.course c ON c.code = o.course_code WHERE s.id = p_sheet;
    IF v_stage IS NULL THEN RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found'; END IF;
    IF v_stage <> 'PUBLISHED' THEN
        RAISE EXCEPTION 'RES_AMEND_NOT_PUBLISHED: the sheet is at %; before publication a mark is corrected by returning the sheet', lower(replace(v_stage, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO was FROM assessment.latest_scores(p_sheet) x WHERE x.student_id = p_student;
    IF was.student_id IS NULL THEN
        -- V422: no mark on the sheet — a late result, for a candidate on its roll only
        IF NOT EXISTS (SELECT 1 FROM assessment.sheet_candidates(p_sheet) c WHERE c.student_id = p_student) THEN
            RAISE EXCEPTION 'RES_AMEND_NO_MARK: the student has no mark on this sheet and is not on its roll' USING ERRCODE = '23514';
        END IF;
        v_kind := 'LATE';
    END IF;
    IF v_out NOT IN ('GRADED', 'ABSENT', 'WITHHELD', 'INCOMPLETE', 'MALPRACTICE', 'EXEMPTED') THEN
        RAISE EXCEPTION 'RES_AMEND_OUTCOME: no such outcome %', v_out USING ERRCODE = '23514';
    END IF;
    v_ca := CASE WHEN v_out = 'GRADED' THEN p_ca END;
    v_exam := CASE WHEN v_out = 'GRADED' THEN p_exam END;
    IF v_out = 'GRADED' AND (v_ca IS NULL OR v_exam IS NULL) THEN RAISE EXCEPTION 'RES_AMEND_MARKS: a graded mark carries both the CA and the examination' USING ERRCODE = '23514'; END IF;
    IF v_ca > v_ca_max OR v_exam > 100 - v_ca_max THEN
        RAISE EXCEPTION 'RES_AMEND_SPLIT: % assesses % and examines %', v_code, v_ca_max, 100 - v_ca_max USING ERRCODE = '23514';
    END IF;
    IF v_kind = 'AMEND' AND v_out = was.outcome AND v_ca IS NOT DISTINCT FROM was.ca AND v_exam IS NOT DISTINCT FROM was.exam THEN
        RAISE EXCEPTION 'RES_AMEND_SAME: the mark is already that' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'RES_AMEND_REASON: an amendment says why, in words Senate can read' USING ERRCODE = '23514';
    END IF;
    IF v_query IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM assessment.result_query q WHERE q.id = v_query AND q.sheet_id = p_sheet AND q.student_id = p_student AND q.state = 'CORRECTED') THEN
            RAISE EXCEPTION 'RES_AMEND_QUERY: that query is not this student''s on this sheet answered as corrected' USING ERRCODE = '23514';
        END IF;
    ELSE
        -- the query answered CORRECTED that asked for it, when there is one not yet carried by an amendment
        v_query := (SELECT q.id FROM assessment.result_query q WHERE q.sheet_id = p_sheet AND q.student_id = p_student AND q.state = 'CORRECTED'
                       AND NOT EXISTS (SELECT 1 FROM assessment.amendment m WHERE m.query_id = q.id AND m.stage <> 'WITHDRAWN')
                     ORDER BY q.answered_at DESC LIMIT 1);
    END IF;
    INSERT INTO assessment.amendment (ref, sheet_id, student_id, query_id, kind, was_version, was_ca, was_exam, was_outcome, ca, exam, outcome, reason, raised_by, raised_office)
    VALUES ('AMD-' || v_year || '-' || lpad(platform.next_number('RESULT_AMENDMENT', 'UNIVERSITY', v_year)::text, 5, '0'),
            p_sheet, p_student, v_query, v_kind, was.version, was.ca, was.exam, was.outcome, v_ca, v_exam, v_out, btrim(p_reason), v_actor, v_office)
    RETURNING id INTO v_id;
    INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (v_id, NULL, 'VERIFICATION', 'RAISE', v_actor, v_office, btrim(p_reason));
    RETURN v_id;
END $function$;

/* the student told that a late result is published — no mark in the message (V422) */
CREATE FUNCTION assessment.tell_late_result(p_student uuid, p_course text, p_ref text)
RETURNS void
LANGUAGE plpgsql AS $function$
DECLARE r record; v_from text := coalesce((SELECT name FROM platform.institution_profile LIMIT 1), 'the University');
BEGIN
    SELECT st.surname, st.other_names, rc.email, rc.phone INTO r FROM people.student st LEFT JOIN LATERAL people.student_reach(st.id) rc ON true WHERE st.id = p_student;
    PERFORM platform.queue_notice('EMAIL', r.email, 'Your result in ' || p_course || ' is published',
        'Dear ' || r.surname || ', ' || r.other_names || E',\n\nYour result in ' || p_course || ', not on the published sheet before, is now published on the Senate''s approval (' || p_ref || '). '
        || E'Sign in to the University portal to see it.\n\n' || v_from || ' — Examinations and Records',
        'student', p_student);
    PERFORM platform.queue_notice('SMS', r.phone, 'Result published', 'MOAUM: your result in ' || p_course || ' is now published. Sign in to the portal to see it.', 'student', p_student);
END $function$;

/* approved by the desk of its stage; at Senate, applied on the minute — a late result as the candidate's first mark (V422) */
CREATE OR REPLACE FUNCTION assessment.advance_amendment(p_amendment uuid, p_comment text, p_minute text)
RETURNS text
LANGUAGE plpgsql AS $function$
DECLARE m assessment.amendment; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_last uuid; v_next text; v_version int; v_course text;
BEGIN
    SELECT * INTO m FROM assessment.amendment WHERE id = p_amendment FOR UPDATE;
    IF m.id IS NULL THEN RAISE EXCEPTION 'no amendment %', p_amendment USING ERRCODE = 'no_data_found'; END IF;
    IF m.stage IN ('APPLIED', 'REFUSED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'RES_AMEND_CLOSED: the amendment is % already', lower(m.stage) USING ERRCODE = '23514';
    END IF;
    PERFORM assessment.require_stage_desk(m.stage, v_office, 'approved');
    SELECT d.actor_id INTO v_last FROM assessment.amendment_decision d WHERE d.amendment_id = p_amendment AND d.kind IN ('RAISE', 'ADVANCE')
     ORDER BY d.decided_at DESC LIMIT 1;
    IF v_last IS NOT NULL AND v_last = v_actor THEN
        RAISE EXCEPTION 'you took the previous step of this amendment; another desk must approve this one' USING ERRCODE = 'check_violation',
            HINT = 'BR-006. No one person moves a correction from raising to Senate alone.';
    END IF;
    v_next := assessment.stage_after(m.stage);
    IF v_next = 'PUBLISHED' THEN
        IF p_minute IS NULL OR btrim(p_minute) = '' THEN
            RAISE EXCEPTION 'an amendment is applied on the Senate minute that approved it, and none was cited' USING ERRCODE = 'check_violation';
        END IF;
        SELECT coalesce(max(version), 0) + 1 INTO v_version FROM assessment.score WHERE sheet_id = m.sheet_id AND student_id = m.student_id;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (m.sheet_id, m.student_id, v_version, m.ca, m.exam, m.outcome,
                CASE WHEN m.kind = 'LATE' THEN 'Late result ' ELSE 'Amendment ' END || m.ref || ' on Senate minute ' || btrim(p_minute) || ': ' || m.reason);
        UPDATE assessment.amendment SET stage = 'APPLIED', senate_minute = btrim(p_minute), applied_at = now(), applied_version = v_version WHERE id = p_amendment;
        INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
        VALUES (p_amendment, m.stage, 'APPLIED', 'APPLY', v_actor, v_office, nullif(btrim(coalesce(p_comment, '')), ''));
        SELECT o.course_code INTO v_course FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id WHERE s.id = m.sheet_id;
        IF m.kind = 'LATE' THEN
            PERFORM assessment.tell_late_result(m.student_id, v_course, m.ref);
        ELSE
            PERFORM assessment.tell_amended(m.student_id, v_course, m.ref);
        END IF;
        RETURN 'APPLIED';
    END IF;
    UPDATE assessment.amendment SET stage = v_next WHERE id = p_amendment;
    INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (p_amendment, m.stage, v_next, 'ADVANCE', v_actor, v_office, nullif(btrim(coalesce(p_comment, '')), ''));
    RETURN v_next;
END $function$;

/* the sheet's amendments with their kind (V422: a column more, so the function is made again) */
DROP FUNCTION assessment.amendments_of(uuid);
CREATE FUNCTION assessment.amendments_of(p_sheet uuid)
RETURNS TABLE(id uuid, ref text, sheet_id uuid, student_id uuid, number text, name text, query_ref text, was_ca integer, was_exam integer, was_outcome text,
              ca integer, exam integer, outcome text, reason text, stage text, raised_by uuid, raised_by_name text, raised_office text,
              raised_at timestamp with time zone, senate_minute text, applied_at timestamp with time zone, closed_reason text, last_actor uuid, decisions jsonb,
              kind text)
LANGUAGE sql STABLE AS $function$
    SELECT m.id, m.ref, m.sheet_id, m.student_id, coalesce(st.matric_no, st.admission_no), upper(st.surname) || ', ' || st.other_names, q.ref,
           m.was_ca, m.was_exam, m.was_outcome, m.ca, m.exam, m.outcome, m.reason, m.stage, m.raised_by, p.surname || ', ' || p.given_names, m.raised_office, m.raised_at,
           m.senate_minute, m.applied_at, m.closed_reason,
           (SELECT d.actor_id FROM assessment.amendment_decision d WHERE d.amendment_id = m.id AND d.kind IN ('RAISE', 'ADVANCE') ORDER BY d.decided_at DESC LIMIT 1),
           (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', d.kind, 'from', d.from_stage, 'to', d.to_stage, 'office', d.actor_office, 'comment', d.comment,
                                                         'at', d.decided_at, 'by', (SELECT x.surname || ', ' || x.given_names FROM iam.person x WHERE x.id = d.actor_id))
                                       ORDER BY d.decided_at), '[]'::jsonb)
              FROM assessment.amendment_decision d WHERE d.amendment_id = m.id),
           m.kind
      FROM assessment.amendment m JOIN people.student st ON st.id = m.student_id
      LEFT JOIN assessment.result_query q ON q.id = m.query_id LEFT JOIN iam.person p ON p.id = m.raised_by
     WHERE m.sheet_id = p_sheet
     ORDER BY m.raised_at DESC
$function$;

/* the candidates on a published sheet's roll with no mark on it and no late result open — those a late result is for (V422) */
CREATE FUNCTION assessment.late_candidates(p_sheet uuid)
RETURNS TABLE(student_id uuid, number text, surname text, other_names text, programme_code text)
LANGUAGE sql STABLE AS $function$
    SELECT st.id, coalesce(st.matric_no, st.admission_no), st.surname, st.other_names, st.programme_code
      FROM (SELECT c.student_id FROM assessment.sheet_candidates(p_sheet) c
            EXCEPT SELECT l.student_id FROM assessment.latest_scores(p_sheet) l) x
      JOIN people.student st ON st.id = x.student_id
     WHERE (SELECT s.stage FROM assessment.score_sheet s WHERE s.id = p_sheet) = 'PUBLISHED'
       AND NOT EXISTS (SELECT 1 FROM assessment.amendment m WHERE m.sheet_id = p_sheet AND m.student_id = st.id
                         AND m.stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN'))
     ORDER BY st.surname, st.other_names
$function$;
COMMENT ON FUNCTION assessment.late_candidates(uuid) IS
  'V422: the candidates on a published sheet''s roll with no mark on it and no late result open — the students a late result is raised for.';

-- ── 2 · the outcomes read alike: an absence is owed ──
CREATE OR REPLACE FUNCTION registration.carryovers(p_student uuid)
RETURNS TABLE(course_code text, title text, units integer, failed_in text)
LANGUAGE sql STABLE AS $function$
    SELECT f.course_code, f.title, f.units, f.session || ' semester ' || f.semester
      FROM assessment.student_results(p_student) f
     -- V422: a recorded absence is an F and owed, as a graded F is
     WHERE f.published AND f.outcome IN ('GRADED', 'ABSENT') AND f.points = 0
       AND NOT registration.is_elective_for(p_student, f.course_code)
       AND NOT EXISTS (SELECT 1 FROM assessment.student_results(p_student) g
                        WHERE g.course_code = f.course_code AND g.published AND g.outcome = 'GRADED' AND g.points > 0
                          AND (g.session, g.semester) > (f.session, f.semester));
$function$;

CREATE OR REPLACE FUNCTION registration.carryovers_at(p_student uuid, p_session text, p_semester integer, p_inclusive boolean)
RETURNS TABLE(course_code text, title text, units integer, failed_in text)
LANGUAGE sql STABLE AS $function$
    SELECT DISTINCT ON (f.course_code)
           f.course_code, f.title, f.units, f.session || ' semester ' || f.semester
      FROM assessment.student_results(p_student) f
     -- V422: a recorded absence is an F and owed, as a graded F is
     WHERE f.published AND f.outcome IN ('GRADED', 'ABSENT') AND f.points = 0
       AND NOT registration.is_elective_for(p_student, f.course_code)
       AND CASE WHEN p_inclusive THEN (f.session, f.semester) <= (p_session, p_semester)
                ELSE (f.session, f.semester) <  (p_session, p_semester) END
       AND NOT EXISTS (
            SELECT 1 FROM assessment.student_results(p_student) g
             WHERE g.course_code = f.course_code AND g.published AND g.outcome = 'GRADED' AND g.points > 0
               AND (g.session, g.semester) > (f.session, f.semester)
               AND CASE WHEN p_inclusive THEN (g.session, g.semester) <= (p_session, p_semester)
                        ELSE (g.session, g.semester) <  (p_session, p_semester) END)
     ORDER BY f.course_code, f.session, f.semester;
$function$;

-- ── 2 · the outcomes read alike: a held result keeps the semester open ──
CREATE OR REPLACE FUNCTION assessment.student_standing(p_student uuid)
RETURNS TABLE(standing text, cgpa numeric, pronounced_session text, pronounced_semester integer, pronounced_level integer)
LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    -- V422: a semester with a result held for Senate (withheld, incomplete, malpractice) is not complete
    held AS (SELECT DISTINCT x.session, x.semester FROM assessment.student_results(p_student) x
              WHERE x.published AND x.outcome IN ('WITHHELD', 'INCOMPLETE', 'MALPRACTICE')),
    sems AS (
        SELECT g.session, g.semester, g.cgpa, g.lcgpa, r.level
          FROM assessment.student_gpa(p_student) g
          JOIN registration.course_registration r ON r.student_id = p_student AND r.session = g.session AND r.semester = g.semester
         -- V421: only a semester whose every registered course is published, with a CGPA computed from real results
         WHERE g.cgpa IS NOT NULL AND g.published_count > 0 AND g.published_count = g.registered_count
           AND NOT EXISTS (SELECT 1 FROM held h WHERE h.session = g.session AND h.semester = g.semester)
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
  'V244, V246, V421, V422: the standing pronounced by the latest complete published semester (every registered course published, none held for Senate) — PROBATION, ADVISED_TO_WITHDRAW or GOOD against the University''s threshold; NOT_AVAILABLE before any such semester.';

CREATE OR REPLACE FUNCTION assessment.student_result_periods(p_student uuid)
RETURNS TABLE(session text, semester integer, level integer, registered integer, published integer, in_chain integer, at_verification integer,
              status text, in_progress boolean)
LANGUAGE sql STABLE AS $fn$
    WITH rows AS (SELECT * FROM assessment.student_results(p_student)),
    per AS (
        SELECT x.session, x.semester, count(*)::int AS registered, count(*) FILTER (WHERE x.published)::int AS published,
               count(*) FILTER (WHERE NOT x.published AND x.stage IN ('DEPT_BOARD', 'FACULTY_SCRUTINY', 'FACULTY_COMPILATION', 'FACULTY_BOARD', 'RECORDS', 'SENATE'))::int AS in_chain,
               count(*) FILTER (WHERE NOT x.published AND x.stage = 'VERIFICATION')::int AS at_verification,
               count(*) FILTER (WHERE x.published AND x.outcome IN ('WITHHELD', 'INCOMPLETE', 'MALPRACTICE'))::int AS held
          FROM rows x GROUP BY x.session, x.semester)
    SELECT p.session, p.semester,
           (SELECT r.level FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p.session AND r.semester = p.semester
             ORDER BY r.level DESC LIMIT 1),
           p.registered, p.published, p.in_chain, p.at_verification,
           -- V422: every course published but one or more held for Senate is HELD, not complete
           CASE WHEN p.published = p.registered AND p.held > 0 THEN 'HELD'
                WHEN p.published = p.registered THEN 'PUBLISHED'
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
  'V421, V422: each registered semester''s result status for the student — PUBLISHED, HELD (all published, one or more held for Senate), INCOMPLETE, PROCESSING, UNDER_VERIFICATION or NOT_AVAILABLE — and whether the semester is still running.';

CREATE OR REPLACE FUNCTION assessment.student_result_status(p_student uuid)
RETURNS TABLE(session text, semester integer, level integer, status text, registered integer, published integer, message text)
LANGUAGE sql STABLE AS $fn$
    WITH p AS (SELECT * FROM assessment.student_result_periods(p_student) x WHERE NOT x.in_progress ORDER BY x.session DESC, x.semester DESC LIMIT 1),
    w AS (SELECT p.*, p.session || ' ' || CASE p.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE p.semester::text END || ' semester' AS period,
                 (SELECT count(*) FROM assessment.student_results(p_student) x
                   WHERE x.session = p.session AND x.semester = p.semester AND x.published AND x.outcome IN ('WITHHELD', 'INCOMPLETE', 'MALPRACTICE')) AS held
            FROM p)
    SELECT w.session, w.semester, w.level, w.status, w.registered, w.published,
           CASE w.status
               WHEN 'NOT_AVAILABLE' THEN 'Your result for the ' || w.period || ' has not yet been uploaded or published.'
               WHEN 'UNDER_VERIFICATION' THEN 'Your result for the ' || w.period || ' is under verification.'
               WHEN 'PROCESSING' THEN 'Your result for the ' || w.period || ' is being processed and has not yet been published.'
               WHEN 'INCOMPLETE' THEN w.published || ' of your ' || w.registered || ' courses for the ' || w.period
                                      || ' are published; the rest are still being processed. Your standing is read when the semester''s results are complete.'
               -- V422
               WHEN 'HELD' THEN 'Your result for the ' || w.period || ' is published with ' || w.held || ' course' || CASE WHEN w.held = 1 THEN '' ELSE 's' END
                                || ' held for the Senate''s decision. Your standing is read when the Senate decides.'
           END
      FROM w;
$fn$;
COMMENT ON FUNCTION assessment.student_result_status(uuid) IS
  'V421, V422: the latest semester that has ended, its result status and the message the student reads (none when its results are complete).';

-- ── 2 · the outcomes read alike: an absence from a GST/EPS course owes it again ──
CREATE OR REPLACE FUNCTION finance.gst_eps_rows(p_session text, p_student uuid DEFAULT NULL::uuid)
 RETURNS TABLE(student_id uuid, course_code text, title text, units integer, office text, level integer, semesters integer[], offering_id uuid, source text, counts boolean, status text, registered boolean, failed_in text, last_grade text, passed_in text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH cur AS (SELECT coalesce(max(name), '') AS name FROM policy.academic_session WHERE state = 'CURRENT'),
    -- the undergraduates in good standing it may concern, at the level the session reads them at
    base AS (
        SELECT s.id, s.programme_code, s.curriculum_track, s.curriculum_version,
               CASE WHEN p_session >= cur.name THEN s.current_level
                    ELSE (SELECT max(cr.level) FROM registration.course_registration cr WHERE cr.student_id = s.id AND cr.session = p_session) END AS level
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          CROSS JOIN cur
         WHERE (p_student IS NULL OR s.id = p_student) AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND s.entry_mode IS DISTINCT FROM 'CCE'),   -- V380: the GST/EPS fee is the full-time students'; the Bursary states CCE fees as CCE lines
    gc AS (SELECT c.code, c.title, c.units, c.level, c.general_office, c.curriculum, c.state
             FROM catalogue.course c WHERE c.kind = 'GST' AND c.general_office IS NOT NULL AND c.code NOT LIKE 'DMO %'),
    -- the GST/EPS courses the session runs, in which semesters
    offered AS (SELECT o.course_code, array_agg(o.semester ORDER BY o.semester) AS semesters, (array_agg(o.id ORDER BY o.semester))[1] AS offering_id
                  FROM catalogue.offering o JOIN gc ON gc.code = o.course_code
                 WHERE o.session = p_session AND o.stream = 'REGULAR'
                 GROUP BY o.course_code),
    -- every GST/EPS registration entry of these students up to the session
    ent AS (SELECT cr.student_id, cr.session, cr.semester, cr.status AS reg_status, e.status AS entry_status, o.id AS offering_id, o.course_code
              FROM base b
              JOIN registration.course_registration cr ON cr.student_id = b.id AND cr.session <= p_session
              JOIN registration.entry e ON e.registration_id = cr.id
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN gc ON gc.code = o.course_code),
    -- the record's results: the entries of approved registrations, as assessment.student_results reads them
    rec AS (SELECT DISTINCT x.student_id, x.session, x.semester, x.offering_id, x.course_code FROM ent x
             WHERE x.reg_status IN ('APPROVED', 'LOCKED') AND x.entry_status IN ('REGISTERED', 'APPROVED')),
    sheets AS (SELECT sh.id, sh.offering_id, sh.stage, coalesce(es.kind, 'MAIN') AS kind
                 FROM assessment.score_sheet sh
                 LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
                WHERE sh.offering_id IN (SELECT r.offering_id FROM rec r)),
    -- each sheet's latest scores read once, not once per student
    scores AS MATERIALIZED (SELECT sh.id AS sheet_id, ls.student_id, ls.points, ls.outcome, ls.grade
                              FROM sheets sh CROSS JOIN LATERAL assessment.latest_scores(sh.id) ls),
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
    SELECT o.student_id, o.course_code, gc.title, gc.units, coalesce(gc.general_office, 'GST'), coalesce(o.level, gc.level), off.semesters, off.offering_id, o.source,
           -- owed this session: being taken; or run this session and still owed (a carryover, or the programme's course not yet passed)
           (rg.course_code IS NOT NULL OR (off.course_code IS NOT NULL AND (o.source = 'CARRYOVER' OR NOT coalesce(ps.before, false)))),
           CASE WHEN coalesce(ps.now, false) THEN 'COMPLETED'
                WHEN fn.course_code IS NOT NULL THEN 'FAILED'
                WHEN rg.course_code IS NOT NULL THEN 'REGISTERED'
                WHEN o.source = 'COURSE_OFFERING' AND coalesce(ps.before, false) THEN 'ALREADY_PASSED'
                WHEN off.course_code IS NULL THEN 'NOT_OFFERED'
                ELSE 'OUTSTANDING' END,
           rg.course_code IS NOT NULL, ca.failed_in, ca.grade, ps.passed_in
      FROM one o
      JOIN gc ON gc.code = o.course_code
      LEFT JOIN offered off ON off.course_code = o.course_code
      LEFT JOIN reg rg ON rg.student_id = o.student_id AND rg.course_code = o.course_code
      LEFT JOIN pass ps ON ps.student_id = o.student_id AND ps.course_code = o.course_code
      LEFT JOIN fail_now fn ON fn.student_id = o.student_id AND fn.course_code = o.course_code
      LEFT JOIN carry ca ON ca.student_id = o.student_id AND ca.course_code = o.course_code
$function$;

COMMIT;
