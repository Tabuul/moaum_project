-- V381: CCE phases 2b and 3 — examinations and results of the Centre's classes in the CCE session, CBT for them, the CCE
--       student's place in the programme (expected completion, spillover, deferment on the CCE calendar), the CCE
--       matriculation series, the route on the transcript, and old-portal CCE students.
--
-- Nothing here is a second examination, result, cohort, deferment or matriculation system (docs/cce.md, section G):
--
--   assessment.exam_session.stream   an examination session is the full-time classes' (REGULAR) or the Centre's (CCE); one
--                                    per session, semester, kind and stream. It releases score sheets to the classes of its
--                                    own stream only, and a score sheet is refused against a session of another stream —
--                                    so CCE results are entered, approved by the same chain and published in the CCE session
--                                    without touching the full-time results already published for the same session name
--   the examination card             lists the papers of the student's own stream only
--   attendance.policy.bars_exams     the Centre may say that attendance below its minimum bars a student from the
--                                    examination of that class; off unless the Centre turns it on; CBT reads it
--   people.academic_position_rows    a CCE student's expected completion and spillover from the CCE entry session and the
--                                    programme's CCE duration (six years unless the Academic Office stated another),
--                                    measured against the CCE session; six years elapsing graduates nobody
--   deferment                        the period a CCE student defers runs on the CCE calendar (people.period_start/_end with
--                                    the student), and the programme timeline counts the CCE duration
--   policy.study_route.matric_*      the matriculation series and the segment a CCE number carries, set by the Registry;
--                                    blank (the default) means the programme's or faculty's series and no segment
--   the statement and transcript     carry the study mode, the route and the Centre
--   people.import_students_rows      an old-portal student marked CCE (or part-time) comes over as CCE and part-time
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V381: CCE examinations, results, CBT, progression, matriculation, transcript and old-portal students', true);

-- ── 1 · examination sessions by stream ──────────────────────────────────────────────────────────────────────────
ALTER TABLE assessment.exam_session ADD COLUMN stream text NOT NULL DEFAULT 'REGULAR';
ALTER TABLE assessment.exam_session ADD CONSTRAINT ck_exam_session_stream CHECK (stream IN ('REGULAR', 'CCE'));
ALTER TABLE assessment.exam_session DROP CONSTRAINT exam_session_session_semester_kind_key;
ALTER TABLE assessment.exam_session ADD CONSTRAINT exam_session_session_semester_kind_stream_key UNIQUE (session, semester, kind, stream);
COMMENT ON COLUMN assessment.exam_session.stream IS
  'V381: whose examinations these are — REGULAR (the full-time classes) or CCE (the Centre for Continuing Education''s classes in the CCE session). A session releases sheets to the classes of its own stream only.';

/* a score sheet belongs to an examination session of its class's stream */
CREATE OR REPLACE FUNCTION assessment.score_sheet_stream_guard() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_class text; v_exam text;
BEGIN
    IF NEW.exam_session_id IS NULL THEN RETURN NEW; END IF;
    SELECT o.stream INTO v_class FROM catalogue.offering o WHERE o.id = NEW.offering_id;
    SELECT e.stream INTO v_exam FROM assessment.exam_session e WHERE e.id = NEW.exam_session_id;
    IF v_class IS DISTINCT FROM v_exam THEN
        RAISE EXCEPTION 'EXAM_STREAM: %', CASE WHEN v_class = 'CCE' THEN 'a class of the Centre for Continuing Education is examined in a CCE examination session'
                                              ELSE 'a full-time class is examined in a full-time examination session' END
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_score_sheet_stream BEFORE INSERT OR UPDATE OF offering_id, exam_session_id ON assessment.score_sheet
    FOR EACH ROW EXECUTE FUNCTION assessment.score_sheet_stream_guard();

-- ── 2 · attendance that bars the examination, where the Centre says so ──────────────────────────────────────────
ALTER TABLE attendance.policy ADD COLUMN bars_exams boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN attendance.policy.bars_exams IS
  'V381: whether attendance below the minimum bars a student from the examination of the class (CBT refuses them). Off unless the policy''s owner turns it on; without a minimum it bars nobody.';

/* the reason a student may not sit the examination of a class for attendance, or null */
CREATE OR REPLACE FUNCTION attendance.exam_bar(p_student uuid, p_offering uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT 'CBT_ATTENDANCE: your attendance in ' || x.course_code || ' is ' || round(x.rate) || '%, below the minimum of ' || round(x.min_percent)
           || '% required to sit its examination'
      FROM catalogue.offering o
      CROSS JOIN LATERAL (SELECT p.bars_exams FROM attendance.policy p
                           WHERE p.context = CASE WHEN o.stream = 'CCE' THEN 'CCE' ELSE 'COURSE' END AND p.session IN (o.session, '*')
                           ORDER BY (p.session = '*') LIMIT 1) pol
      CROSS JOIN LATERAL attendance.course_summary(p_student, o.session) x
     WHERE o.id = p_offering AND x.offering_id = o.id AND pol.bars_exams AND x.verdict = 'NOT_ELIGIBLE'
$fn$;
COMMENT ON FUNCTION attendance.exam_bar(uuid, uuid) IS
  'V381: why attendance bars the student from the examination of the class — only where the class''s attendance policy has a minimum and bars examinations, and the student''s counted attendance is below it.';

DROP FUNCTION attendance.set_cce_policy(text, numeric, numeric, integer, boolean);
CREATE OR REPLACE FUNCTION attendance.set_cce_policy(p_session text, p_min numeric, p_warn numeric, p_min_classes integer, p_show boolean, p_bars boolean)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'the CCE attendance policy');
    IF p_session IS NULL OR (p_session <> '*' AND NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session)) THEN
        RAISE EXCEPTION 'CCE_SESSION_UNKNOWN: % is not a session on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_bars, false) AND p_min IS NULL THEN
        RAISE EXCEPTION 'CCE_ATTENDANCE_BAR: attendance bars the examination only against a minimum; state the minimum first' USING ERRCODE = '23514';
    END IF;
    INSERT INTO attendance.policy (context, session, min_percent, warn_band, min_classes, show_students, bars_exams, updated_by)
    VALUES ('CCE', p_session, p_min, p_warn, coalesce(p_min_classes, 3), coalesce(p_show, true), coalesce(p_bars, false), v_actor)
    ON CONFLICT (context, session) DO UPDATE SET min_percent = EXCLUDED.min_percent, warn_band = EXCLUDED.warn_band, min_classes = EXCLUDED.min_classes,
        show_students = EXCLUDED.show_students, bars_exams = EXCLUDED.bars_exams, updated_by = EXCLUDED.updated_by, updated_at = now();
END $fn$;

-- ── 3 · the student's calendar for deferment ────────────────────────────────────────────────────────────────────
/* when a semester's period begins and ends for the student: the CCE calendar for a CCE student (where the Centre dated it),
   else the University's calendar as before */
CREATE OR REPLACE FUNCTION people.period_start(p_student uuid, p_session text, p_semester integer)
RETURNS date LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(
        (SELECT coalesce(rs.lectures_from, rs.registration_opens) FROM policy.route_semester rs
          WHERE people.student_stream(p_student) = 'CCE' AND rs.route = 'CCE' AND rs.session = p_session AND rs.number = coalesce(p_semester, 1)),
        people.period_start(p_session, p_semester))
$fn$;

CREATE OR REPLACE FUNCTION people.period_end(p_student uuid, p_session text, p_semester integer)
RETURNS date LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(
        (SELECT coalesce(rs.exams_to, rs.lectures_to) FROM policy.route_semester rs
          WHERE people.student_stream(p_student) = 'CCE' AND rs.route = 'CCE' AND rs.session = p_session AND rs.number = p_semester),
        people.period_end(p_session, p_semester))
$fn$;

/* where a deferment returns the student to, by the student's calendar */
CREATE OR REPLACE FUNCTION people.deferment_return(p_student uuid, p_kind text, p_session text, p_semester integer)
RETURNS TABLE (return_session text, return_semester integer, return_on date) LANGUAGE sql STABLE AS $fn$
    SELECT x.return_session, x.return_semester, people.period_start(p_student, x.return_session, x.return_semester)
      FROM people.deferment_return(p_kind, p_session, p_semester) x
$fn$;

/* the session a deferment of the student is counted in as the current one: the CCE session for a CCE student */
CREATE OR REPLACE FUNCTION people.student_current_session(p_student uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN people.student_stream(p_student) = 'CCE' THEN policy.route_session('CCE')
                ELSE (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1) END
$fn$;

-- ── 4 · the CCE matriculation number ────────────────────────────────────────────────────────────────────────────
ALTER TABLE policy.study_route ADD COLUMN matric_series text NULL REFERENCES people.matric_series (code);
ALTER TABLE policy.study_route ADD COLUMN matric_segment text NULL CHECK (matric_segment IS NULL OR matric_segment ~ '^[A-Z0-9]{2,6}$');
COMMENT ON COLUMN policy.study_route.matric_series IS
  'V381: the matriculation series a route''s students are numbered in (its own run of numbers); blank: the programme''s or faculty''s series, as for every student.';
COMMENT ON COLUMN policy.study_route.matric_segment IS
  'V381: a segment a route''s matriculation number carries after the University code (CCE: MOAU/CCE/…); blank: none. Set by the Registry, never assumed.';

/* the Registry sets the CCE series and segment; a change says why and is kept in the route's history */
CREATE OR REPLACE FUNCTION people.set_route_matric(p_route text, p_series text, p_segment text, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE r policy.study_route; v_series text := nullif(upper(btrim(coalesce(p_series, ''))), ''); v_segment text := nullif(upper(btrim(coalesce(p_segment, ''))), '');
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['academic', 'registrar', 'dregistrar', 'super'], 'the CCE matriculation series');
    SELECT * INTO r FROM policy.study_route WHERE code = upper(btrim(coalesce(p_route, ''))) FOR UPDATE;
    IF r.code IS NULL THEN RAISE EXCEPTION 'no route %', p_route USING ERRCODE = '23503'; END IF;
    IF v_series IS NOT NULL AND NOT EXISTS (SELECT 1 FROM people.matric_series WHERE code = v_series AND active) THEN
        RAISE EXCEPTION 'CCE_MATRIC_SERIES: % is not an active matriculation series; create it on the format screen first', v_series USING ERRCODE = '23514';
    END IF;
    IF v_segment IS NOT NULL AND v_segment !~ '^[A-Z0-9]{2,6}$' THEN
        RAISE EXCEPTION 'CCE_MATRIC_SEGMENT: a segment is two to six letters or digits' USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'CCE_MATRIC_REASON: a change to the CCE matriculation number is recorded with its reason' USING ERRCODE = '23514';
    END IF;
    UPDATE policy.study_route SET matric_series = v_series, matric_segment = v_segment WHERE code = r.code;
    INSERT INTO policy.study_route_event (route, actor, office, what, before, after, reason)
    VALUES (r.code, v_actor, v_office, 'MATRICULATION',
            jsonb_build_object('series', r.matric_series, 'segment', r.matric_segment), jsonb_build_object('series', v_series, 'segment', v_segment), btrim(p_reason));
END $fn$;

-- ── 5 · the examination, by the class's stream ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.release_exam_sheets(p_id uuid)
 RETURNS TABLE(sheets_made integer, offerings_without_lecturer integer)
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e assessment.exam_session; v_made int; v_none int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'score sheets are released by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO e FROM assessment.exam_session WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no examination session %', p_id USING ERRCODE = 'no_data_found'; END IF;
    IF e.state <> 'OPEN' THEN
        RAISE EXCEPTION 'EXAM_NOT_OPEN: the examination session is %; its score sheets are released once it is open', lower(e.state) USING ERRCODE = '23514';
    END IF;
    IF e.sheets_released_at IS NOT NULL THEN
        RAISE EXCEPTION 'EXAM_SHEETS_RELEASED: the score sheets of this session were released on %', to_char(e.sheets_released_at, 'DD Mon YYYY') USING ERRCODE = '23514';
    END IF;
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), o.id, p_id, e.sheets_due
      FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NOT NULL AND o.stream = e.stream   -- V381: the session's own stream
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet s WHERE s.offering_id = o.id AND s.exam_session_id = p_id)
       AND (e.kind = 'MAIN'
            OR EXISTS (SELECT 1 FROM assessment.score_sheet ms
                         JOIN assessment.exam_session mes ON mes.id = ms.exam_session_id AND mes.kind = 'MAIN'
                        WHERE ms.offering_id = o.id AND ms.stage = 'PUBLISHED'));
    GET DIAGNOSTICS v_made = ROW_COUNT;
    SELECT count(*) INTO v_none FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NULL AND o.stream = e.stream;
    UPDATE assessment.exam_session SET sheets_released_at = now(), sheets_released_by = who WHERE id = p_id;
    RETURN QUERY SELECT v_made, v_none;
END;
$function$;
CREATE OR REPLACE FUNCTION assessment.open_exam_session(p_id uuid)
 RETURNS TABLE(sheets_made integer, offerings_without_lecturer integer)
 LANGUAGE plpgsql
AS $function$
DECLARE e assessment.exam_session; v_none int;
BEGIN
    SELECT * INTO e FROM assessment.exam_session WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no examination session %', p_id USING ERRCODE = 'no_data_found';
    END IF;
    IF e.state <> 'DRAFT' THEN
        RAISE EXCEPTION 'the examination session is already %', lower(e.state) USING ERRCODE = 'check_violation';
    END IF;
    SELECT count(*) INTO v_none FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NULL AND o.stream = e.stream;   -- V381
    UPDATE assessment.exam_session SET state = 'OPEN', opened_at = now() WHERE id = p_id;
    RETURN QUERY SELECT 0, v_none;
END;
$function$;
CREATE OR REPLACE FUNCTION catalogue.allocate_offering(p_offering uuid, p_lecturer uuid, p_second uuid, p_overload_ok boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    o        catalogue.offering;
    who      uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_units  int;
    v_load   int;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a teaching allocation is made by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such offering' USING ERRCODE = '23503';
    END IF;
    IF p_lecturer IS NULL THEN
        RAISE EXCEPTION 'an allocation names the lecturer who teaches it' USING ERRCODE = '23514';
    END IF;
    IF p_second IS NOT NULL AND p_second = p_lecturer THEN
        RAISE EXCEPTION 'the second examiner cannot be the lecturer' USING ERRCODE = '23514',
            HINT = 'The person who enters the marks may not be the person who verifies them.';
    END IF;

    SELECT c.units INTO v_units FROM catalogue.course c WHERE c.code = o.course_code;
    SELECT coalesce(sum(c2.units), 0) INTO v_load
      FROM catalogue.offering o2 JOIN catalogue.course c2 ON c2.code = o2.course_code
     WHERE o2.lecturer_id = p_lecturer AND o2.session = o.session AND o2.semester = o.semester AND o2.stream = o.stream AND o2.id <> p_offering;
    IF v_load + coalesce(v_units, 0) > 12 AND NOT p_overload_ok THEN
        RAISE EXCEPTION 'this assignment puts the lecturer at % units, over the approved maximum of 12', v_load + coalesce(v_units, 0)
            USING ERRCODE = '23514', HINT = 'Assign it as an overload if the department intends it; the overload is on the record and reported to the Dean.';
    END IF;

    UPDATE catalogue.offering
       SET lecturer_id = p_lecturer, second_examiner_id = p_second, allocated_on = current_date
     WHERE id = p_offering;

    -- assigning the lecturer opens the score sheet, if the examination session is open, its sheets released, and none exists yet
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), p_offering, es.id, es.sheets_due
      FROM assessment.exam_session es
     WHERE es.session = o.session AND es.semester = o.semester AND es.state = 'OPEN' AND es.sheets_released_at IS NOT NULL
       AND es.stream = o.stream   -- V381: the examination session of the class's own stream
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = p_offering);
END $function$;
CREATE OR REPLACE FUNCTION assessment.student_docket(p_student uuid, p_exam_session uuid)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, held_on date, starts_at time without time zone, ends_at time without time zone, venue text, sheet_stage text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT o.id, c.code, c.title, e.units, t.held_on, t.starts_at, t.ends_at, t.venue, sh.stage
      FROM assessment.exam_session x
      JOIN registration.course_registration r ON r.student_id = p_student AND r.session = x.session AND r.semester = x.semester AND r.status IN ('APPROVED','LOCKED')
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN assessment.score_sheet sh ON sh.offering_id = o.id AND sh.exam_session_id = x.id
      LEFT JOIN assessment.exam_timetable t ON t.offering_id = o.id
     WHERE x.id = p_exam_session AND o.stream = x.stream   -- V381: the papers of the session's own stream
     ORDER BY t.held_on NULLS LAST, t.starts_at NULLS LAST, c.code;
$function$;
CREATE OR REPLACE FUNCTION assessment.cbt_eligibility(p_exam uuid, p_student uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE e assessment.cbt_exam; st people.student; v_gate text; v_ready text; n int; v_enabled boolean;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RETURN 'CBT_EXAM_NOT_FOUND: no such examination'; END IF;
    -- V365: a JUPEB examination's candidate is a JUPEB student, judged by the JUPEB rules
    IF e.office = 'JUPEB' THEN RETURN assessment.cbt_jupeb_eligibility(p_exam, p_student); END IF;
    IF e.state = 'CANCELLED' THEN RETURN 'CBT_EXAM_CANCELLED: this examination was cancelled'; END IF;
    IF e.state <> 'PUBLISHED' THEN RETURN 'CBT_EXAM_NOT_OPEN: this examination is not open to candidates'; END IF;
    SELECT cbt_enabled INTO v_enabled FROM catalogue.course WHERE code = e.course_code;
    IF NOT coalesce(v_enabled, false) THEN RETURN format('CBT_COURSE_NOT_ENABLED: %s is not a CBT course', e.course_code); END IF;
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF NOT FOUND OR st.status NOT IN ('ACTIVE', 'ADMITTED', 'PROBATION') THEN
        RETURN 'CBT_STUDENT_INACTIVE: only an active student sits an examination';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                    WHERE cr.student_id = p_student AND en.offering_id = e.offering_id
                      AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN
        RETURN format('CBT_COURSE_NOT_REGISTERED: %s is not on your submitted registration for %s', e.course_code, e.session);
    END IF;
    -- V381: attendance below the class's minimum bars the examination where the class's attendance policy says so
    v_gate := attendance.exam_bar(p_student, e.offering_id);
    IF v_gate IS NOT NULL THEN RETURN v_gate; END IF;
    IF e.office IN ('GST', 'EPS') THEN
        v_gate := registration.gst_gate(p_student, e.session, e.course_code);
        IF v_gate IS NOT NULL THEN RETURN v_gate; END IF;
    ELSIF NOT coalesce(finance.clears(p_student, e.session, 'EXAMINATION'), false) THEN
        RETURN format('CBT_FEES_NOT_CLEARED: your %s school fees are not cleared for examinations', e.session);
    END IF;
    v_ready := assessment.cbt_paper_ready(p_exam);
    IF v_ready IS NOT NULL THEN RETURN v_ready; END IF;
    IF e.starts_at > now() THEN RETURN format('CBT_EXAM_NOT_STARTED: the examination opens at %s', to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI')); END IF;
    IF e.ends_at <= now() THEN RETURN 'CBT_EXAM_ENDED: the examination window has closed'; END IF;
    SELECT count(*) INTO n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND candidate_id = p_student AND status <> 'IN_PROGRESS';
    IF n >= e.attempt_limit THEN RETURN format('CBT_ATTEMPT_LIMIT: you have used the %s attempt%s this examination allows', e.attempt_limit, CASE WHEN e.attempt_limit = 1 THEN '' ELSE 's' END); END IF;
    RETURN NULL;
END $function$;

-- ── 6 · the CCE student's place in the programme ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.academic_position_rows(p_student uuid DEFAULT NULL::uuid)
 RETURNS SETOF people.academic_position
 LANGUAGE sql
 STABLE
AS $function$
    WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1),
    -- V381: a CCE student stands in the CCE session, for the CCE duration of the programme (six years unless stated)
    cce AS (SELECT policy.route_session('CCE') AS name),
    cfg AS (SELECT max_spillover_years FROM policy.progression_setting),
    st AS (
        SELECT s.id, s.matric_no, s.jamb_reg_no, s.entry_session, s.entry_level, s.programme_code, s.current_level, s.status, s.candidate_id, s.entry_mode,
               c.session AS candidate_session,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.final_level ELSE p.final_level END AS configured_final,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.duration_years ELSE p.duration_years END AS configured_years,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.final_level ELSE finance.final_level(s.programme_code) END AS final_level,
               co.effective_cohort AS override_cohort, a.name AS entry_on_calendar, a.merged_into
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN LATERAL ref.programme_route_terms(s.programme_code, 'CCE') rt ON s.entry_mode = 'CCE'
          LEFT JOIN people.cohort_override co ON co.student_id = s.id
          LEFT JOIN policy.academic_session a ON a.name = s.entry_session
         WHERE p_student IS NULL OR s.id = p_student),
    dups AS (SELECT matric_no FROM people.student WHERE matric_no IS NOT NULL GROUP BY matric_no HAVING count(*) > 1),
    defs AS (
        SELECT d.student_id,
               ceil(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)))::numeric / 2)::int AS sessions,
               bool_or(d.state = 'ACTIVE') AS live
          FROM people.deferment d
         WHERE d.state IN ('APPROVED','ACTIVE','COMPLETED') AND (p_student IS NULL OR d.student_id = p_student)
         GROUP BY d.student_id),
    reg AS (
        SELECT r.student_id,
               bool_or(r.session = cur.name AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cur_reg,
               bool_or(r.session = (SELECT name FROM cce) AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cce_reg,
               max(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS last_reg
          FROM registration.course_registration r LEFT JOIN cur ON true
         WHERE p_student IS NULL OR r.student_id = p_student
         GROUP BY r.student_id),
    enr AS (
        SELECT e.student_id, bool_or(e.session = cur.name) AS cur_enr, bool_or(e.session = (SELECT name FROM cce)) AS cce_enr, max(e.session) AS last_enr
          FROM people.enrolment e LEFT JOIN cur ON true
         WHERE p_student IS NULL OR e.student_id = p_student
         GROUP BY e.student_id),
    grad AS (
        SELECT DISTINCT ON (g.student_id) g.student_id, g.session, g.senate_state, g.unmet
          FROM records.graduand g
         WHERE p_student IS NULL OR g.student_id = p_student
         ORDER BY g.student_id, (g.senate_state = 'APPROVED') DESC, g.session DESC),
    base AS (
        SELECT st.*,
               coalesce(policy.session_year(st.candidate_session),
                        CASE WHEN st.jamb_reg_no ~ '^20[0-9]{2}[0-9]{8}[A-Z]{2}$' THEN left(st.jamb_reg_no, 4)::int END,
                        policy.session_year(st.entry_session)) AS jamb_year,
               CASE WHEN st.matric_no ~ '/[0-9]{2}/' THEN 2000 + (regexp_match(st.matric_no, '/([0-9]{2})/'))[1]::int END AS matric_year,
               coalesce(st.override_cohort, policy.effective_session(st.entry_session)) AS effective_cohort,
               CASE WHEN st.override_cohort IS NOT NULL THEN 'OVERRIDE' WHEN st.merged_into IS NOT NULL THEN 'MERGED' ELSE 'ENTRY' END AS cohort_source,
               coalesce(st.configured_years, CASE WHEN st.configured_final IS NOT NULL THEN greatest((st.configured_final - coalesce(st.entry_level, 100)) / 100 + 1, 1) END) AS duration_years,
               st.configured_final IS NOT NULL AS level_based,
               coalesce(d.sessions, 0) AS deferred_sessions, coalesce(d.live, false) AS live_deferment,
               coalesce(CASE WHEN st.entry_mode = 'CCE' THEN r.cce_reg ELSE r.cur_reg END, false) AS registered_current, greatest(r.last_reg, e.last_enr) AS last_session,
               coalesce(CASE WHEN st.entry_mode = 'CCE' THEN e.cce_enr ELSE e.cur_enr END, false) AS enrolled_current,
               g.senate_state AS graduation_state, g.session AS graduation_session, g.unmet AS graduation_unmet, g.student_id IS NOT NULL AS has_graduand,
               st.matric_no IN (SELECT matric_no FROM dups) AS dup_matric,
               CASE WHEN st.entry_mode = 'CCE' THEN (SELECT name FROM cce) ELSE (SELECT name FROM cur) END AS current_session, (SELECT max_spillover_years FROM cfg) AS max_spill
          FROM st LEFT JOIN defs d ON d.student_id = st.id LEFT JOIN reg r ON r.student_id = st.id
               LEFT JOIN enr e ON e.student_id = st.id LEFT JOIN grad g ON g.student_id = st.id),
    timed AS (
        SELECT b.*,
               CASE WHEN b.duration_years IS NOT NULL THEN policy.session_after(b.effective_cohort, b.duration_years - 1 + b.deferred_sessions) END AS expected_completion,
               policy.sessions_elapsed(b.effective_cohort, b.current_session) AS elapsed_sessions
          FROM base b),
    measured AS (
        SELECT t.*,
               greatest(0, coalesce(policy.sessions_elapsed(t.expected_completion, t.current_session), 0)) AS spillover_years,
               CASE WHEN t.elapsed_sessions IS NULL THEN NULL
                    WHEN NOT t.level_based THEN coalesce(t.entry_level, t.current_level)
                    ELSE least(t.configured_final, coalesce(t.entry_level, 100) + 100 * greatest(0, t.elapsed_sessions - t.deferred_sessions)) END AS computed_level
          FROM timed t),
    ruled AS (
        SELECT m.*,
               CASE
                 WHEN m.graduation_state = 'APPROVED' OR m.status = 'GRADUATED' THEN 'R1'
                 WHEN m.status IN ('WITHDRAWN','VOLUNTARY_WITHDRAWAL','EXPELLED','DECEASED','TRANSFERRED_OUT','RUSTICATED','SUSPENDED','DORMANT','DEFERRED','ADMITTED') THEN 'R2'
                 WHEN m.entry_session IS NULL OR policy.session_year(m.effective_cohort) IS NULL OR m.duration_years IS NULL OR m.current_session IS NULL THEN 'R6'
                 WHEN m.has_graduand AND m.graduation_unmet IS NULL AND m.graduation_state <> 'APPROVED' THEN 'R5'
                 WHEN m.spillover_years > m.max_spill THEN 'R4L'
                 WHEN m.spillover_years > 0 THEN 'R4'
                 WHEN m.registered_current OR m.enrolled_current THEN 'R3'
                 WHEN m.last_session IS NULL THEN 'R6'
                 ELSE 'R3L' END AS rule,
               array_remove(ARRAY[
                   CASE WHEN m.entry_session IS NULL THEN 'MISSING_ENTRY_SESSION' END,
                   CASE WHEN m.entry_session IS NOT NULL AND policy.session_year(m.entry_session) IS NULL THEN 'ENTRY_SESSION_INVALID' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.elapsed_sessions < 0 THEN 'ENTRY_SESSION_AHEAD' END,
                   CASE WHEN m.matric_no IS NULL AND m.status <> 'ADMITTED' THEN 'MISSING_MATRIC' END,
                   CASE WHEN m.jamb_reg_no IS NULL THEN 'MISSING_JAMB' END,
                   CASE WHEN m.duration_years IS NULL THEN 'DURATION_NOT_CONFIGURED' END,
                   CASE WHEN m.dup_matric THEN 'DUPLICATE_MATRIC' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.computed_level IS NOT NULL AND m.computed_level <> m.current_level THEN 'LEVEL_CONFLICT' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND NOT m.registered_current AND NOT m.enrolled_current THEN 'NO_CURRENT_REGISTRATION' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.last_session IS NULL THEN 'NO_REGISTRATION_HISTORY' END,
                   CASE WHEN m.status = 'GRADUATED' AND m.graduation_state IS DISTINCT FROM 'APPROVED' THEN 'GRADUATED_WITHOUT_APPROVAL' END,
                   CASE WHEN m.status <> 'GRADUATED' AND m.graduation_state = 'APPROVED' THEN 'APPROVED_NOT_GRADUATED' END,
                   CASE WHEN m.status = 'DEFERRED' AND NOT m.live_deferment THEN 'DEFERRED_WITHOUT_LIVE_DEFERMENT' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.spillover_years > m.max_spill THEN 'SPILLOVER_LIMIT_REACHED' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.spillover_years > 0 THEN 'BEYOND_PROGRAMME_LENGTH' END
               ]::text[], NULL) AS issues
          FROM measured m)
    SELECT r.id,
           r.jamb_year, r.matric_year, r.entry_session, r.effective_cohort, r.cohort_source, r.entry_level, r.programme_code, r.final_level, r.duration_years,
           r.current_session, r.current_level, r.computed_level, r.expected_completion, r.deferred_sessions, r.elapsed_sessions, r.spillover_years,
           CASE WHEN r.status NOT IN ('ACTIVE','PROBATION') THEN 'NOT_APPLICABLE'
                WHEN r.spillover_years = 0 THEN 'NORMAL'
                WHEN r.spillover_years > r.max_spill THEN 'SPILLOVER_LIMIT_REACHED'
                ELSE 'SPILLOVER_YEAR_' || least(r.spillover_years, 3) END,
           r.registered_current, r.enrolled_current, r.last_session, r.graduation_state, r.graduation_session,
           r.status,
           CASE r.rule
             WHEN 'R1'  THEN 'GRADUATED'
             WHEN 'R2'  THEN r.status
             WHEN 'R5'  THEN 'GRADUATION_ELIGIBLE'
             WHEN 'R4L' THEN 'SPILLOVER_LIMIT_REACHED'
             WHEN 'R4'  THEN 'SPILLOVER'
             WHEN 'R3'  THEN 'ACTIVE'
             WHEN 'R3L' THEN 'ACTIVE'
             ELSE 'REQUIRES_REVIEW' END,
           CASE r.rule WHEN 'R1' THEN 'GRADUATED' WHEN 'R3' THEN CASE WHEN r.status IN ('ACTIVE','PROBATION') THEN r.status ELSE 'ACTIVE' END
                       WHEN 'R3L' THEN r.status WHEN 'R4' THEN r.status WHEN 'R5' THEN r.status ELSE r.status END,
           r.rule,
           CASE
             WHEN r.rule = 'R1' AND r.graduation_state = 'APPROVED' AND r.status IN ('GRADUATED','ACTIVE','PROBATION') THEN 'VALIDATED'
             WHEN r.rule = 'R1' THEN 'REVIEW'
             WHEN r.rule = 'R2' AND NOT (r.status = 'DEFERRED' AND NOT r.live_deferment) THEN 'VALIDATED'
             WHEN r.rule IN ('R6', 'R4L') THEN 'REVIEW'
             WHEN r.dup_matric OR (r.status IN ('ACTIVE','PROBATION') AND r.computed_level IS NOT NULL AND r.computed_level <> r.current_level AND r.spillover_years = 0) THEN 'REVIEW'
             WHEN r.rule IN ('R3', 'R5') THEN 'VALIDATED'
             WHEN r.rule = 'R4' AND (r.registered_current OR r.enrolled_current) THEN 'VALIDATED'
             ELSE 'LIKELY' END,
           r.issues,
           now()
      FROM ruled r
$function$;
CREATE OR REPLACE FUNCTION people.deferment_save(p_student uuid, p_id uuid, p_kind text, p_session text, p_semester integer, p_reason text, p_explanation text, p_declared boolean, p_extension_of uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE d people.deferment; e record; v_id uuid; v_sem int; v_ret record; st people.deferment_setting; fee record;
BEGIN
    SELECT * INTO st FROM people.deferment_setting WHERE id = 1;
    SELECT * INTO e FROM people.deferment_eligibility(p_student);
    v_sem := CASE WHEN p_kind = 'SEMESTER' THEN p_semester ELSE NULL END;
    IF p_kind NOT IN ('SEMESTER','SESSION') THEN RAISE EXCEPTION 'a deferment is of a semester or of a session' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no such session %', p_session USING ERRCODE = '23514'; END IF;
    IF p_kind = 'SEMESTER' AND (v_sem IS NULL OR v_sem > coalesce((SELECT semesters FROM policy.academic_session WHERE name = p_session), 2)) THEN
        RAISE EXCEPTION 'choose the semester of % to defer', p_session USING ERRCODE = '23514';
    END IF;
    IF p_session < (SELECT name FROM policy.academic_session WHERE state = 'CURRENT') THEN
        RAISE EXCEPTION 'a session that has passed is not deferred' USING ERRCODE = '23514', HINT = 'Choose the current session or a coming one.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM people.deferment_reason WHERE code = p_reason AND active) THEN RAISE EXCEPTION 'choose a reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO v_ret FROM people.deferment_return(p_student, p_kind, p_session, v_sem);   -- V381: by the student's calendar
    IF p_id IS NULL THEN
        IF NOT e.eligible THEN RAISE EXCEPTION '%', e.reason USING ERRCODE = '23514', HINT = 'Deferment request not available.'; END IF;
        -- the fee before the form: a CONFIRMED, unspent payment of the deferment application fee
        SELECT * INTO fee FROM people.deferment_fee_view(p_student);
        IF fee.id IS NULL OR fee.state <> 'CONFIRMED' OR fee.used_by IS NOT NULL THEN
            RAISE EXCEPTION 'the deferment application fee of NGN % is paid before the application form opens', st.fee USING ERRCODE = '23514',
                  HINT = 'Generate the fee reference on the Deferment screen, pay it, and the form opens the moment the payment is confirmed.';
        END IF;
        IF p_extension_of IS NOT NULL THEN
            IF NOT st.allow_extension THEN RAISE EXCEPTION 'an extension of a deferment is not granted' USING ERRCODE = '23514'; END IF;
            IF NOT EXISTS (SELECT 1 FROM people.deferment x WHERE x.id = p_extension_of AND x.student_id = p_student AND x.state IN ('ACTIVE','APPROVED')) THEN
                RAISE EXCEPTION 'an extension follows a deferment in force' USING ERRCODE = '23514';
            END IF;
        END IF;
        IF (people.deferment_used(p_student) + (CASE WHEN p_kind = 'SESSION' THEN 1 ELSE 0.5 END)) > st.max_sessions THEN
            RAISE EXCEPTION 'this would take your deferments to more than the % session(s) the University allows', st.max_sessions USING ERRCODE = '23514';
        END IF;
        INSERT INTO people.deferment (reference, student_id, kind, session, semester, reason_code, explanation, declared, extension_of,
                                      period_from, return_session, return_semester, return_on, fee_id)
        VALUES (people.deferment_new_reference(), p_student, p_kind, p_session, v_sem, p_reason, nullif(btrim(coalesce(p_explanation, '')), ''), coalesce(p_declared, false), p_extension_of,
                people.period_start(p_student, p_session, v_sem), v_ret.return_session, v_ret.return_semester, v_ret.return_on, fee.id)
        RETURNING id INTO v_id;
        UPDATE people.deferment_fee SET used_by = v_id WHERE id = fee.id;
        PERFORM people.deferment_log(v_id, 'FEE_PAID', NULL, NULL, 'Deferment application fee NGN ' || fee.amount::text || ' confirmed ' || to_char(fee.confirmed_at, 'DD Mon YYYY') || ' · ' || fee.reference || coalesce(' · receipt ' || fee.receipt_no, ''));
        PERFORM people.deferment_log(v_id, 'CREATED', NULL, 'DRAFT', 'Request opened for ' || p_session || coalesce(' semester ' || v_sem, ''));
        RETURN v_id;
    END IF;
    SELECT * INTO d FROM people.deferment WHERE id = p_id AND student_id = p_student FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such deferment request' USING ERRCODE = '23503'; END IF;
    IF d.state NOT IN ('DRAFT','CORRECTION_REQUIRED') THEN RAISE EXCEPTION 'the request is %; it is no longer yours to change', lower(replace(d.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    UPDATE people.deferment SET kind = p_kind, session = p_session, semester = v_sem, reason_code = p_reason,
           explanation = nullif(btrim(coalesce(p_explanation, '')), ''), declared = coalesce(p_declared, false),
           period_from = people.period_start(p_student, p_session, v_sem), return_session = v_ret.return_session, return_semester = v_ret.return_semester, return_on = v_ret.return_on,
           updated_at = now()
     WHERE id = d.id;
    PERFORM people.deferment_log(d.id, 'UPDATED', d.state, d.state, NULL);
    RETURN d.id;
END $function$;
CREATE OR REPLACE FUNCTION people.programme_timeline(p_student uuid)
 RETURNS TABLE(entry_session text, entry_level integer, final_level integer, semesters_per_session integer, original_semesters integer, original_completion_session text, original_completion_semester integer, original_completion_on date, approved_semesters integer, approved_sessions numeric, approved_count integer, adjusted_semesters integer, adjusted_completion_session text, adjusted_completion_semester integer, adjusted_completion_on date, live_state text, live_return_session text, live_return_semester integer, live_return_on date)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; v_final int; v_sps int; v_years int; v_orig int; v_ext int := 0; v_n int := 0; v_idx int; live people.deferment;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF s.id IS NULL THEN RETURN; END IF;
    v_final := coalesce(finance.final_level(s.programme_code), 400);
    v_sps := coalesce((SELECT a.semesters FROM policy.academic_session a WHERE a.name = s.entry_session), 2);
    v_years := greatest((v_final - coalesce(s.entry_level, 100)) / 100 + 1, 1);
    -- V381: a CCE student's programme runs the CCE duration (six years unless the Academic Office stated another)
    IF s.entry_mode = 'CCE' THEN
        SELECT coalesce(t.final_level, v_final), coalesce(t.duration_years, v_years) INTO v_final, v_years FROM ref.programme_route_terms(s.programme_code, 'CCE') t;
    END IF;
    v_orig := v_years * v_sps;
    SELECT coalesce(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session))), 0), count(*)
      INTO v_ext, v_n
      FROM people.deferment d WHERE d.student_id = p_student AND d.state IN ('APPROVED','ACTIVE','COMPLETED');
    SELECT * INTO live FROM people.deferment d WHERE d.student_id = p_student AND d.state IN ('APPROVED','ACTIVE') ORDER BY d.return_on DESC NULLS LAST LIMIT 1;
    v_idx := v_orig + v_ext - 1;   -- zero-based index of the last semester, counted from the entry session's first
    RETURN QUERY SELECT s.entry_session, s.entry_level, v_final, v_sps,
        v_orig, people.session_plus(s.entry_session, v_years - 1), v_sps, people.period_end(p_student, people.session_plus(s.entry_session, v_years - 1), v_sps),
        v_ext, round(v_ext::numeric / v_sps, 1), v_n,
        v_orig + v_ext, people.session_plus(s.entry_session, v_idx / v_sps), (v_idx % v_sps) + 1, people.period_end(p_student, people.session_plus(s.entry_session, v_idx / v_sps), (v_idx % v_sps) + 1),
        live.state, live.return_session, live.return_semester, live.return_on;
END $function$;
CREATE OR REPLACE FUNCTION people.deferments_tick()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE d record; st people.deferment_setting; n int := 0; s people.student;
BEGIN
    SELECT * INTO st FROM people.deferment_setting WHERE id = 1;
    -- approved, and the period has begun (or the session is the current one and the semester open): in force
    FOR d IN
        SELECT x.* FROM people.deferment x
         WHERE x.state = 'APPROVED'
           AND (current_date >= x.period_from
                OR (people.student_stream(x.student_id) = 'REGULAR'
                    AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = x.session AND a.state = 'CURRENT'
                                 AND (x.kind = 'SESSION' OR EXISTS (SELECT 1 FROM policy.semester sm WHERE sm.session = x.session AND sm.number = x.semester AND sm.state = 'OPEN'))))
                -- V381: a CCE student's deferment begins with the CCE session, or its CCE semester open
                OR (people.student_stream(x.student_id) = 'CCE' AND x.session = policy.route_session('CCE')
                    AND (x.kind = 'SESSION' OR EXISTS (SELECT 1 FROM policy.route_semester rs WHERE rs.route = 'CCE' AND rs.session = x.session AND rs.number = x.semester AND rs.state = 'OPEN'))))
    LOOP
        SELECT * INTO s FROM people.student WHERE id = d.student_id;
        UPDATE people.deferment SET state = 'ACTIVE', activated_at = now(), prior_status = s.status, updated_at = now() WHERE id = d.id;
        IF s.status IN ('ACTIVE','PROBATION','ADMITTED') AND s.matric_no IS NOT NULL THEN
            PERFORM people.change_status(s.id, 'DEFERRED', d.reference, current_date, 'Deferment in force');
            UPDATE people.status_change SET expires_on = d.return_on WHERE id = (SELECT id FROM people.status_change WHERE student_id = s.id ORDER BY effective_on DESC, id DESC LIMIT 1);
        END IF;
        PERFORM people.deferment_log(d.id, 'ACTIVATED', 'APPROVED', 'ACTIVE', 'The deferred period has begun');
        PERFORM people.deferment_tell(d.id, 'Your deferment is now in force', 'Your deferment of ' || d.session || coalesce(' semester ' || d.semester, '') || ' is in force. Your expected return is ' || d.return_session || ' semester ' || d.return_semester || '.');
        n := n + 1;
    END LOOP;
    -- the return approaching: reminded once
    FOR d IN
        SELECT x.* FROM people.deferment x
         WHERE x.state = 'ACTIVE' AND x.reminder_sent_at IS NULL AND x.return_on IS NOT NULL AND x.return_on <= current_date + st.reminder_days
    LOOP
        UPDATE people.deferment SET reminder_sent_at = now() WHERE id = d.id;
        PERFORM people.deferment_tell(d.id, 'Your deferment is ending soon',
            'Your approved deferment ends on ' || to_char(d.return_on, 'DD Month YYYY') || '. Review your school fees and course registration for ' || d.return_session || ' semester ' || d.return_semester || '; the desk confirms your return.');
        PERFORM people.deferment_tell_desk(d.id, 'hod', 'A student is due to return from deferment', 'A student of your department is due to return from deferment on ' || to_char(d.return_on, 'DD Month YYYY') || '. Confirm the return on the deferments desk when they present themselves.');
        n := n + 1;
    END LOOP;
    RETURN n;
END $function$;

-- ── 7 · the CCE matriculation number ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.matric_components(p_student uuid)
 RETURNS TABLE(university_code text, faculty_segment text, programme_segment text, uses_code boolean, yy text, series_code text, programme_code text, programme text, faculty_code text, faculty text, problem text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V381: a CCE student's number carries the CCE segment after the University code, and runs in the CCE series, where the Registry set them
    SELECT mf.university_code || CASE WHEN s.entry_mode = 'CCE' AND rt.matric_segment IS NOT NULL THEN mf.separator || rt.matric_segment ELSE '' END,
           CASE WHEN mf.faculty_code THEN coalesce(p.matric_faculty_code, f.matric_code, f.code) END,
           CASE WHEN mf.programme_code AND p.matric_uses_code THEN p.matric_code END,
           mf.programme_code AND p.matric_uses_code,
           CASE WHEN mf.year THEN substr(coalesce(s.entry_session, to_char(now(), 'YYYY')), 3, 2) END,
           coalesce(CASE WHEN s.entry_mode = 'CCE' THEN rt.matric_series END, p.matric_series, f.matric_series, 'GENERAL'),
           p.code, p.name, f.code, f.name,
           CASE WHEN p.code IS NULL THEN 'The student has no programme on the record'
                WHEN mf.programme_code AND p.matric_uses_code AND p.matric_code IS NULL THEN 'Programme ' || p.name || ' is configured to carry a code but has none; give it one or set it to carry none'
                WHEN mf.faculty_code AND coalesce(p.matric_faculty_code, f.matric_code, f.code) IS NULL THEN 'The faculty has no matriculation code'
                WHEN NOT EXISTS (SELECT 1 FROM people.matric_series ms WHERE ms.code = coalesce(CASE WHEN s.entry_mode = 'CCE' THEN rt.matric_series END, p.matric_series, f.matric_series, 'GENERAL') AND ms.active)
                     THEN 'The series ' || coalesce(CASE WHEN s.entry_mode = 'CCE' THEN rt.matric_series END, p.matric_series, f.matric_series, 'GENERAL') || ' is not active' END
      FROM people.student s
      CROSS JOIN people.matric_format mf
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN policy.study_route rt ON rt.code = 'CCE'
     WHERE s.id = p_student AND mf.id = 'UNIVERSITY';
$function$;
CREATE OR REPLACE FUNCTION people.matric_shape_ok(p_no text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    -- V381: up to three segments between the University code and the year (a route's segment, the faculty, the programme)
    SELECT p_no ~ '^[A-Z]{2,6}[/-][A-Z0-9]{2,6}([/-][A-Z0-9]{2,6}){0,2}[/-][0-9]{2}[/-][0-9]{1,8}$';
$function$;

-- ── 8 · the statement and the transcript, and the old portal's CCE students ────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.build_statement(p_student uuid, p_kind text, p_session text, p_semester integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE st record; g record; pol credentials.document_policy; v_sessions jsonb; v_cgpa numeric; v_class text; v_scope text; v_cur text; v_cur_sem int;
        v_pg boolean; v_research jsonb; v_totals record; v_semesters jsonb;
BEGIN
    SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.entry_mode, s.entry_session, s.entry_level, s.current_level, s.status, s.programme_code, s.study_mode,
           p.name AS programme, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty, coalesce(p.pg_award, p.name) AS award_name
      INTO st FROM people.student s JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE s.id = p_student;
    IF st.id IS NULL THEN RAISE EXCEPTION 'no student record' USING ERRCODE = '23503'; END IF;
    SELECT * INTO pol FROM credentials.document_policy WHERE kind = p_kind;
    SELECT * INTO g FROM records.graduand gg WHERE gg.student_id = p_student AND gg.senate_state = 'APPROVED' ORDER BY gg.session DESC LIMIT 1;
    v_pg := st.entry_mode = 'POSTGRADUATE' OR EXISTS (SELECT 1 FROM admissions.pg_registration r WHERE r.student_id = p_student);
    v_cur := (SELECT name FROM policy.academic_session WHERE state = 'CURRENT');
    v_cur_sem := (SELECT number FROM policy.semester WHERE session = v_cur AND state = 'OPEN' ORDER BY number DESC LIMIT 1);
    -- V381: a CCE student's current semester is the CCE calendar's
    IF st.entry_mode = 'CCE' THEN
        v_cur := policy.route_session('CCE');
        v_cur_sem := (SELECT number FROM policy.route_semester WHERE route = 'CCE' AND session = v_cur AND state = 'OPEN' ORDER BY number DESC LIMIT 1);
    END IF;
    -- the scope of the document
    v_scope := CASE p_kind WHEN 'SESSIONAL_TRANSCRIPT' THEN 'SELECTED_SESSION' WHEN 'MINI_TRANSCRIPT' THEN pol.includes ELSE 'CUMULATIVE' END;
    IF NOT v_pg THEN
        SELECT jsonb_agg(jsonb_build_object('session', q.session, 'semesters', q.semesters) ORDER BY q.session) INTO v_sessions
          FROM (SELECT r.session,
                       jsonb_agg(jsonb_build_object('semester', r.semester, 'courses', r.courses, 'units', gp.units, 'gpa', gp.gpa, 'cgpa', gp.cgpa, 'tcr', gp.tcr, 'tce', gp.tce, 'twgp', gp.twgp) ORDER BY r.semester) AS semesters
                  FROM (SELECT x.session, x.semester,
                               jsonb_agg(jsonb_build_object('code', x.course_code, 'title', x.title, 'units', x.units, 'grade', x.grade, 'points', x.points, 'quality', round(coalesce(x.points, 0) * x.units, 2), 'type', x.entry_type, 'outcome', x.outcome) ORDER BY x.course_code) AS courses
                          FROM assessment.student_results(p_student) x
                         WHERE x.published
                           AND (v_scope = 'CUMULATIVE' OR (v_scope = 'SELECTED_SESSION' AND x.session = p_session)
                                OR (v_scope = 'SELECTED_SEMESTER' AND x.session = p_session AND x.semester = p_semester)
                                OR (v_scope = 'CURRENT_SEMESTER' AND x.session = v_cur AND x.semester = coalesce(v_cur_sem, x.semester)))
                         GROUP BY x.session, x.semester) r
                  LEFT JOIN assessment.student_gpa(p_student) gp ON gp.session = r.session AND gp.semester = r.semester
                 GROUP BY r.session) q;
        SELECT coalesce(max(cgpa) FILTER (WHERE (session, semester) = (SELECT session, semester FROM assessment.student_gpa(p_student) ORDER BY session DESC, semester DESC LIMIT 1)), 0) INTO v_cgpa FROM assessment.student_gpa(p_student);
        IF g.cgpa IS NOT NULL THEN v_cgpa := g.cgpa; END IF;
        v_class := CASE WHEN g.student_id IS NOT NULL THEN coalesce(policy.class_of(g.cgpa), 'Pass') ELSE policy.class_of(v_cgpa) END;
        v_research := NULL;
    ELSE
        SELECT jsonb_agg(jsonb_build_object('session', q.session, 'semesters', q.semesters) ORDER BY q.session) INTO v_sessions
          FROM (SELECT r.session,
                       jsonb_agg(jsonb_build_object('semester', r.semester, 'courses', r.courses, 'units', r.units, 'gpa', admissions.pg_gpa(p_student, r.session, r.semester)) ORDER BY r.semester) AS semesters
                  FROM (SELECT reg.session, reg.semester, sum(c.units) FILTER (WHERE c.kind <> 'DEFICIENCY') AS units,
                               jsonb_agg(jsonb_build_object('code', c.code, 'title', c.title, 'units', c.units, 'grade', sc.grade, 'points', sc.points, 'quality', round(sc.points * c.units, 2), 'type', c.kind) ORDER BY c.code) AS courses
                          FROM admissions.pg_registration reg JOIN admissions.pg_registration_entry e ON e.registration_id = reg.id
                          JOIN admissions.pg_course c ON c.id = e.course_id JOIN admissions.pg_score sc ON sc.entry_id = e.id
                         WHERE reg.student_id = p_student
                           AND (v_scope = 'CUMULATIVE' OR (v_scope = 'SELECTED_SESSION' AND reg.session = p_session)
                                OR (v_scope = 'SELECTED_SEMESTER' AND reg.session = p_session AND reg.semester = p_semester)
                                OR (v_scope = 'CURRENT_SEMESTER' AND reg.session = v_cur))
                         GROUP BY reg.session, reg.semester) r
                 GROUP BY r.session) q;
        v_cgpa := coalesce(g.cgpa, admissions.pg_cgpa(p_student));
        v_class := CASE WHEN g.student_id IS NOT NULL THEN 'Awarded' ELSE NULL END;
        SELECT jsonb_build_object('kind', pr.degree_kind, 'topic', pr.topic, 'stage', pr.stage, 'vivaGrade', pr.viva_grade, 'awardedAt', pr.awarded_at) INTO v_research
          FROM admissions.pg_research pr WHERE pr.student_id = p_student;
    END IF;
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'holder', st.surname || ', ' || st.other_names,
        'matricNo', st.matric_no, 'admissionNo', st.admission_no,
        'programme', st.programme, 'programmeCode', st.programme_code, 'department', st.department, 'faculty', st.faculty,
        'award', CASE WHEN g.student_id IS NOT NULL THEN coalesce(g.award, st.award_name) ELSE st.award_name END,
        'entryMode', st.entry_mode, 'entrySession', st.entry_session, 'entryLevel', st.entry_level, 'level', st.current_level, 'status', st.status,
        -- V381: the mode of study and the route, and for CCE the Centre and the programme's duration on it
        'studyMode', CASE st.study_mode WHEN 'PART_TIME' THEN 'Part-time' ELSE 'Full-time' END,
        'route', CASE WHEN st.entry_mode = 'CCE' THEN 'Centre for Continuing Education (CCE)' END,
        'centre', CASE WHEN st.entry_mode = 'CCE' THEN (SELECT u.name FROM policy.study_route r JOIN ref.unit u ON u.code = r.centre_unit WHERE r.code = 'CCE') END,
        'durationYears', CASE WHEN st.entry_mode = 'CCE' THEN (SELECT t.duration_years FROM ref.programme_route_terms(st.programme_code, 'CCE') t) END,
        'postgraduate', v_pg, 'scope', v_scope, 'session', p_session, 'semester', p_semester,
        'sessions', coalesce(v_sessions, '[]'::jsonb),
        'cgpa', v_cgpa, 'classOfDegree', v_class,
        'standing', CASE WHEN g.student_id IS NOT NULL THEN 'Graduated' WHEN st.status = 'GRADUATED' THEN 'Graduated' ELSE initcap(lower(replace(st.status, '_', ' '))) END,
        'graduationSession', g.session, 'graduationMinute', g.senate_minute,
        'graduationDate', CASE WHEN g.student_id IS NOT NULL THEN (SELECT ends_on FROM policy.academic_session WHERE name = g.session) END,
        'research', v_research,
        'gradingScale', (SELECT jsonb_agg(jsonb_build_object('grade', b.grade, 'low', b.low, 'high', b.high, 'points', b.points) ORDER BY b.points DESC)
                           FROM policy.grade_band b WHERE b.version_id = policy.in_force('grading', 'UNIVERSITY', current_date)),
        'classificationBands', (SELECT jsonb_agg(jsonb_build_object('class', b.class, 'low', b.low, 'high', b.high) ORDER BY b.ord)
                                  FROM policy.classification_band b WHERE b.version_id = policy.in_force('classification', 'UNIVERSITY', current_date))
    ));
END $function$;
CREATE OR REPLACE FUNCTION people.import_students_rows(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, updated integer, no_programme integer, bad_number integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_mode text; v_es text; v_el int; v_cl int;
        v_surname text; v_others text; v_exists boolean; v_state text; v_school text;
        n int := 0; nc int := 0; nu int := 0; nnp int := 0; nbn int := 0; ns int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, name, programme, level' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_matric !~ '^MOAUM/[A-Z]{2,4}/[0-9]{2}/[0-9]{4}$'
           AND v_matric !~ '^[A-Z]{2,6}(/[A-Z0-9]{2,6}){1,4}/[0-9]{2,7}$' THEN nbn := nbn + 1; CONTINUE; END IF;

        v_prog := btrim(coalesce(r->>'programme', r->>'programmeCode', r->>'programme_code', r->>'course', ''));
        SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
        IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived, code LIMIT 1; END IF;
        IF v_prog_code IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;

        BEGIN
            v_surname := nullif(btrim(coalesce(r->>'surname', '')), '');
            v_others := nullif(btrim(coalesce(r->>'otherNames', r->>'other_names', r->>'othernames', '')), '');
            IF v_surname IS NULL THEN
                DECLARE nm text := btrim(coalesce(r->>'name', r->>'fullName', ''));
                BEGIN
                    IF position(',' IN nm) > 0 THEN v_surname := btrim(split_part(nm, ',', 1)); v_others := btrim(substr(nm, position(',' IN nm) + 1));
                    ELSE v_surname := split_part(nm, ' ', 1); v_others := nullif(btrim(substr(nm, length(split_part(nm, ' ', 1)) + 1)), ''); END IF;
                END;
            END IF;
            IF v_surname IS NULL OR v_surname = '' THEN v_surname := 'UNKNOWN'; END IF;
            v_others := coalesce(v_others, '');

            v_sex := upper(left(btrim(coalesce(r->>'sex', r->>'gender', '')), 1));
            IF v_sex NOT IN ('F','M') THEN v_sex := NULL; END IF;
            BEGIN v_dob := (r->>'dob')::date; EXCEPTION WHEN OTHERS THEN BEGIN v_dob := (r->>'dateOfBirth')::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END; END;
            v_state := nullif(btrim(coalesce(r->>'state', r->>'stateOfOrigin', r->>'state_of_origin', '')), '');
            v_school := upper(nullif(btrim(coalesce(r->>'schoolId', r->>'school_id', r->>'schoolid', '')), ''));
            v_mode := upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', 'UTME')));
            -- V381: a student of the Centre for Continuing Education (the route, the study mode or the entry mode says so) comes over as CCE
            IF v_mode IN ('CCE', 'PART TIME', 'PART-TIME', 'PART_TIME') OR v_mode LIKE '%CONTINUING%'
               OR upper(coalesce(r->>'route', r->>'admissionRoute', r->>'admission_route', '')) ~ '(CCE|CONTINUING)'
               OR upper(coalesce(r->>'studyMode', r->>'study_mode', '')) ~ 'PART' THEN
                v_mode := 'CCE';
            END IF;
            IF v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH','CCE') THEN v_mode := 'UTME'; END IF;

            v_es := nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', '')), '');
            IF v_es IS NULL OR v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN
                IF v_matric ~ '^MOAUM/' THEN
                    v_es := '20' || split_part(v_matric, '/', 3) || '/20' || lpad(((split_part(v_matric, '/', 3))::int + 1)::text, 2, '0');
                ELSE
                    v_es := coalesce(v_es, '2000/2001');
                END IF;
            END IF;
            IF v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN v_es := '2000/2001'; END IF;

            v_el := coalesce(nullif(regexp_replace(coalesce(r->>'entryLevel', r->>'entry_level', ''), '[^0-9]', '', 'g'), '')::int, CASE WHEN v_mode IN ('UTME', 'CCE') THEN 100 ELSE 200 END);
            v_cl := coalesce(nullif(regexp_replace(coalesce(r->>'level', r->>'currentLevel', r->>'current_level', ''), '[^0-9]', '', 'g'), '')::int, v_el);
            IF v_el NOT IN (100,200,300,400,500,600) THEN v_el := 100; END IF;
            IF v_cl NOT IN (100,200,300,400,500,600) THEN v_cl := v_el; END IF;

            SELECT true INTO v_exists FROM people.student WHERE upper(matric_no) = v_matric;
            INSERT INTO people.student (id, matric_no, surname, other_names, sex, date_of_birth, state_of_origin, programme_code, entry_mode,
                                        entry_session, entry_level, current_level, status, matriculated_at, school_id, study_mode)
            VALUES (gen_random_uuid(), v_matric, v_surname, v_others, v_sex, v_dob, v_state, v_prog_code, v_mode, v_es, v_el, v_cl, 'ACTIVE', now(), v_school,
                    CASE WHEN v_mode = 'CCE' THEN 'PART_TIME' ELSE 'FULL_TIME' END)
            ON CONFLICT (matric_no) DO UPDATE SET surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
                sex = coalesce(EXCLUDED.sex, people.student.sex), date_of_birth = coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth),
                state_of_origin = coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                programme_code = EXCLUDED.programme_code, current_level = EXCLUDED.current_level,
                school_id = coalesce(EXCLUDED.school_id, people.student.school_id);
            IF coalesce(v_exists, false) THEN nu := nu + 1; ELSE nc := nc + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, nu, nnp, nbn, ns, v_firsterr;
END $function$;

COMMENT ON FUNCTION people.period_start(uuid, text, integer) IS
  'V381: when a semester''s period begins for the student — the CCE calendar''s date for a CCE student where the Centre dated it, else the University''s calendar.';
COMMENT ON FUNCTION people.set_route_matric(text, text, text, text) IS
  'V381: the Registry sets the matriculation series and segment of a route''s students (CCE), with the reason; blank leaves the programme''s or faculty''s series and no segment.';

-- ── 12 · the stored position of a CCE student kept current ─────────────────────────────────────────────────────
/* The position is stored and recomputed by triggers on the student's own rows. A CCE student's also reads the CCE session
   mapping and the programme's CCE length, so a change to either recomputes the CCE students (a few, not the register);
   and the CCE students already on record are recomputed now, under the CCE rules above. */
CREATE OR REPLACE FUNCTION people.refresh_route_positions()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN RETURN NULL; END IF;
    PERFORM people.refresh_academic_position(s.id) FROM people.student s WHERE s.entry_mode = 'CCE';
    RETURN NULL;
END $fn$;
COMMENT ON FUNCTION people.refresh_route_positions() IS
  'V381: recomputes the stored academic position of every CCE student when the CCE session mapping, the route''s default length or a programme''s CCE terms change.';
CREATE TRIGGER trg_position_study_route AFTER UPDATE OF session_offset, session_override, default_duration_years, entry_level ON policy.study_route
    FOR EACH STATEMENT EXECUTE FUNCTION people.refresh_route_positions();
CREATE TRIGGER trg_position_programme_route AFTER INSERT OR UPDATE OR DELETE ON ref.programme_route
    FOR EACH STATEMENT EXECUTE FUNCTION people.refresh_route_positions();

DO $$ BEGIN PERFORM people.refresh_academic_position(s.id) FROM people.student s WHERE s.entry_mode = 'CCE'; END $$;

COMMIT;
