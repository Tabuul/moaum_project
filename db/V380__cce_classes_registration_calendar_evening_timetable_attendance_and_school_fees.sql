-- V380: CCE phase 2 — the Centre's classes in the CCE session, course registration for CCE students through the existing
--       engine, the CCE calendar and windows, the evening timetable, attendance on the register, and CCE school fees in use.
--
-- A CCE student studies in the CCE session, one behind undergraduate by default (V379). Undergraduates have already taken
-- that session's classes — their offerings carry approved score sheets — so CCE gets classes of its own in it. Nothing here
-- is a second registration, timetable, attendance or finance system (docs/cce.md, phase 2):
--
--   catalogue.offering.stream     REGULAR (every existing class) or CCE; one class per course, session, semester and stream.
--                                 Every lookup of a class by course, session and semester names its stream; a registration
--                                 entry is refused when the class's stream is not the student's (REGISTRATION_STREAM)
--   policy.route_semester         the CCE calendar: each CCE semester's state and dates (lectures, registration, late
--                                 registration, examinations), set by the Centre or the Academic Office; opened only in the
--                                 CCE session; every change written to the route's history
--   CCE_COURSE_REGISTRATION,      the Directorate of ICT's windows for CCE students, beside the full-time ones, so a
--   CCE_SCHOOL_FEES_PAYMENT       full-time window of the same session never opens or closes the Centre's
--   registration                  the engine reads the student's stream and calendar: the menu shows only the classes of the
--                                 student's stream; the gate, add/drop and the semesters missed read the CCE calendar for a
--                                 CCE student; the support checks and submission likewise
--   catalogue.cce_open_classes,   the Centre opens the CCE classes of a semester (every course its CCE programmes offer, and
--   cce_add_class, cce_withdraw   the carry-overs its students owe), adds one, or withdraws one nobody has used
--   policy.route_period           the evening periods the Centre configures (4–6 pm …), offered as quick picks; the times
--                                 are data, never code
--   catalogue.class_slot          a CCE class's slots are the Centre's (or the Academic Office's); a venue or lecturer clash
--                                 within the CCE timetable is refused; catalogue.cce_clashes reports the rest
--   attendance.register           the register opened to course classes (context COURSE): present, absent, late, excused,
--                                 corrections with reasons, locking; a CCE attendance policy and reports
--   finance                       an uploaded fee structure replaces only the lines of its own kind (CCE or full-time); the
--                                 late fees and the GST/EPS fee read the CCE windows and never reach a CCE student unasked
--
-- Kept apart on purpose: examination sessions, score sheets and CBT stay on full-time classes (stream REGULAR) until the
-- CCE examination step (docs/cce.md, phase 2b); the department's attendance screen keeps registration.attendance.
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V380: CCE classes, registration, calendar, evening timetable, attendance and school fees', true);

-- ── 1 · the stream of a class ───────────────────────────────────────────────────────────────────────────────────
ALTER TABLE catalogue.offering ADD COLUMN stream text NOT NULL DEFAULT 'REGULAR';
ALTER TABLE catalogue.offering ADD CONSTRAINT ck_offering_stream CHECK (stream IN ('REGULAR', 'CCE'));
ALTER TABLE catalogue.offering DROP CONSTRAINT offering_course_code_session_semester_key;
ALTER TABLE catalogue.offering ADD CONSTRAINT offering_course_session_semester_stream_key UNIQUE (course_code, session, semester, stream);
CREATE INDEX ix_offering_stream_session ON catalogue.offering (session, semester) WHERE stream <> 'REGULAR';
COMMENT ON COLUMN catalogue.offering.stream IS
  'V380: whose class this is — REGULAR (the full-time students'') or CCE (the Centre for Continuing Education''s, in the CCE session). A course has one class per session, semester and stream; a student registers only on classes of their own stream.';

/* the stream a student studies in: CCE for a student of the Centre, REGULAR for every other */
CREATE OR REPLACE FUNCTION people.student_stream(p_student uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN s.entry_mode = 'CCE' THEN 'CCE' ELSE 'REGULAR' END FROM people.student s WHERE s.id = p_student
$fn$;
COMMENT ON FUNCTION people.student_stream(uuid) IS 'V380: the stream of classes a student registers on — CCE for a student of the Centre for Continuing Education, REGULAR for every other.';

/* the database's own word that CCE and full-time classes are never mixed on a registration */
CREATE OR REPLACE FUNCTION registration.entry_stream_guard() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_class text; v_student text;
BEGIN
    SELECT o.stream INTO v_class FROM catalogue.offering o WHERE o.id = NEW.offering_id;
    SELECT people.student_stream(r.student_id) INTO v_student FROM registration.course_registration r WHERE r.id = NEW.registration_id;
    IF v_class IS DISTINCT FROM v_student THEN
        RAISE EXCEPTION 'REGISTRATION_STREAM: %',
            CASE WHEN v_student = 'CCE' THEN 'a student of the Centre for Continuing Education registers on the Centre''s classes in the CCE session, never on a full-time class'
                 ELSE 'a full-time student does not register on a class of the Centre for Continuing Education' END
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_entry_stream BEFORE INSERT OR UPDATE OF offering_id ON registration.entry
    FOR EACH ROW EXECUTE FUNCTION registration.entry_stream_guard();

-- ── 2 · the CCE calendar ────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE policy.route_semester (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    route                    text NOT NULL REFERENCES policy.study_route (code),
    session                  text NOT NULL REFERENCES policy.academic_session (name),
    number                   integer NOT NULL CHECK (number BETWEEN 1 AND 3),
    state                    text NOT NULL DEFAULT 'NOT_YET_OPEN' CHECK (state IN ('NOT_YET_OPEN', 'OPEN', 'CLOSED')),
    lectures_from            date NULL,
    lectures_to              date NULL,
    registration_opens       date NULL,
    registration_closes      date NULL,
    late_registration_closes date NULL,
    exams_from               date NULL,
    exams_to                 date NULL,
    note                     text NULL CHECK (note IS NULL OR length(note) <= 600),
    updated_by               uuid NULL,
    updated_office           text NULL,
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_route_semester UNIQUE (route, session, number),
    CONSTRAINT ck_route_semester_lectures CHECK (lectures_to IS NULL OR lectures_from IS NULL OR lectures_to >= lectures_from),
    CONSTRAINT ck_route_semester_reg CHECK (registration_closes IS NULL OR registration_opens IS NULL OR registration_closes >= registration_opens),
    CONSTRAINT ck_route_semester_late CHECK (late_registration_closes IS NULL OR registration_closes IS NULL OR late_registration_closes >= registration_closes),
    CONSTRAINT ck_route_semester_exams CHECK (exams_to IS NULL OR exams_from IS NULL OR exams_to >= exams_from)
);
COMMENT ON TABLE policy.route_semester IS
  'V380: the calendar of a route that studies in a session of its own (CCE): each semester''s state and dates, beside policy.semester (the full-time calendar of the same session, which the Centre''s classes never read). Set by the Centre or the Academic Office; opened only in the route''s current session.';
SELECT audit.attach('policy.route_semester');

/* the Centre (or the Academic Office) sets a CCE semester: its state and dates; a change to a semester already set says why */
CREATE OR REPLACE FUNCTION policy.set_route_semester(p_route text, p_session text, p_number integer, p_state text,
                                                     p_lectures_from date, p_lectures_to date, p_registration_opens date,
                                                     p_registration_closes date, p_late_closes date, p_exams_from date,
                                                     p_exams_to date, p_note text, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE r policy.study_route; cur policy.route_semester; v_route_session text; v_state text := upper(btrim(coalesce(p_state, '')));
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_id uuid; v_before jsonb;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'the CCE calendar');
    SELECT * INTO r FROM policy.study_route WHERE code = upper(btrim(coalesce(p_route, '')));
    IF r.code IS NULL THEN RAISE EXCEPTION 'no route %', p_route USING ERRCODE = '23503'; END IF;
    IF p_number IS NULL OR p_number NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'CCE_CALENDAR_SEMESTER: a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF v_state NOT IN ('NOT_YET_OPEN', 'OPEN', 'CLOSED') THEN
        RAISE EXCEPTION 'CCE_CALENDAR_STATE: a CCE semester is not yet open, open or closed' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session AND a.state <> 'CANCELLED') THEN
        RAISE EXCEPTION 'CCE_SESSION_UNKNOWN: % is not a session on the calendar (or it was cancelled)', p_session USING ERRCODE = '23514';
    END IF;
    v_route_session := policy.route_session(r.code);
    IF p_session > policy.session_after(v_route_session, 1) THEN
        RAISE EXCEPTION 'CCE_CALENDAR_SESSION: the CCE calendar is set for the CCE session (%) and the one after it, not for %', v_route_session, p_session USING ERRCODE = '23514';
    END IF;
    IF p_registration_closes IS NOT NULL AND p_registration_opens IS NOT NULL AND p_registration_closes < p_registration_opens
       OR p_late_closes IS NOT NULL AND p_registration_closes IS NOT NULL AND p_late_closes < p_registration_closes
       OR p_lectures_to IS NOT NULL AND p_lectures_from IS NOT NULL AND p_lectures_to < p_lectures_from
       OR p_exams_to IS NOT NULL AND p_exams_from IS NOT NULL AND p_exams_to < p_exams_from THEN
        RAISE EXCEPTION 'CCE_CALENDAR_DATES: a period ends before it begins (or late registration closes before registration does)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM policy.route_semester WHERE route = r.code AND session = p_session AND number = p_number FOR UPDATE;
    IF v_state = 'OPEN' AND coalesce(cur.state, '') <> 'OPEN' AND p_session <> v_route_session THEN
        RAISE EXCEPTION 'CCE_CALENDAR_SESSION: a CCE semester opens in the CCE session (%); % is not it — the Academic Office sets the CCE session mapping first when the Centre''s year runs on', v_route_session, p_session USING ERRCODE = '23514';
    END IF;
    IF cur.id IS NOT NULL AND v_reason IS NULL THEN
        RAISE EXCEPTION 'CCE_CALENDAR_REASON: a change to a CCE semester already set is recorded with its reason' USING ERRCODE = '23514';
    END IF;
    IF cur.id IS NOT NULL THEN
        v_before := jsonb_build_object('state', cur.state, 'lectures_from', cur.lectures_from, 'lectures_to', cur.lectures_to,
                                       'registration_opens', cur.registration_opens, 'registration_closes', cur.registration_closes,
                                       'late_registration_closes', cur.late_registration_closes, 'exams_from', cur.exams_from, 'exams_to', cur.exams_to);
        UPDATE policy.route_semester
           SET state = v_state, lectures_from = p_lectures_from, lectures_to = p_lectures_to, registration_opens = p_registration_opens,
               registration_closes = p_registration_closes, late_registration_closes = p_late_closes, exams_from = p_exams_from, exams_to = p_exams_to,
               note = nullif(btrim(coalesce(p_note, '')), ''), updated_by = v_actor, updated_office = v_office, updated_at = now()
         WHERE id = cur.id;
        v_id := cur.id;
    ELSE
        INSERT INTO policy.route_semester (route, session, number, state, lectures_from, lectures_to, registration_opens, registration_closes,
                                           late_registration_closes, exams_from, exams_to, note, updated_by, updated_office)
        VALUES (r.code, p_session, p_number, v_state, p_lectures_from, p_lectures_to, p_registration_opens, p_registration_closes,
                p_late_closes, p_exams_from, p_exams_to, nullif(btrim(coalesce(p_note, '')), ''), v_actor, v_office)
        RETURNING id INTO v_id;
    END IF;
    INSERT INTO policy.study_route_event (route, actor, office, what, before, after, reason)
    VALUES (r.code, v_actor, v_office, 'CALENDAR ' || p_session || ' semester ' || p_number, v_before,
            jsonb_build_object('state', v_state, 'lectures_from', p_lectures_from, 'lectures_to', p_lectures_to,
                               'registration_opens', p_registration_opens, 'registration_closes', p_registration_closes,
                               'late_registration_closes', p_late_closes, 'exams_from', p_exams_from, 'exams_to', p_exams_to),
            coalesce(v_reason, 'Set'));
    RETURN v_id;
END $fn$;

/* the windows of a CCE student: their own, beside the full-time students' of the same session */
ALTER TABLE policy.portal_window DROP CONSTRAINT portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check CHECK (window_type = ANY (ARRAY[
    'SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
    'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION',
    'CCE_SCHOOL_FEES_PAYMENT', 'CCE_COURSE_REGISTRATION']));

CREATE OR REPLACE FUNCTION policy.window_type_for(p_student uuid, p_type text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN p_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION') AND people.student_stream(p_student) = 'CCE' THEN 'CCE_' || p_type ELSE p_type END
$fn$;
COMMENT ON FUNCTION policy.window_type_for(uuid, text) IS
  'V380: the portal window that governs a student — a CCE student''s school fees payment and course registration are the CCE windows, never the full-time ones of the same session.';

-- ── 3 · the student's calendar ──────────────────────────────────────────────────────────────────────────────────
/* the semester as the student's calendar states it: the CCE calendar for a CCE student, the full-time calendar for every other */
CREATE OR REPLACE FUNCTION registration.calendar_semester(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE (state text, registration_opens date, registration_closes date, late_registration_closes date,
               fresh_registration_from date, lectures_from date, lectures_to date, calendar text)
LANGUAGE sql STABLE AS $fn$
    SELECT rs.state, rs.registration_opens, rs.registration_closes, rs.late_registration_closes, NULL::date, rs.lectures_from, rs.lectures_to, 'CCE'
      FROM policy.route_semester rs
     WHERE people.student_stream(p_student) = 'CCE' AND rs.route = 'CCE' AND rs.session = p_session AND rs.number = p_semester
    UNION ALL
    SELECT sm.state, sm.registration_opens, sm.registration_closes, sm.late_registration_closes, sm.fresh_registration_from, sm.lectures_from, sm.lectures_to, 'FULL_TIME'
      FROM policy.semester sm
     WHERE people.student_stream(p_student) = 'REGULAR' AND sm.session = p_session AND sm.number = p_semester
$fn$;

/* the open semester of the student's calendar (registration is gated on that semester's fees), else 1 */
CREATE OR REPLACE FUNCTION registration.open_semester(p_student uuid, p_session text)
RETURNS integer LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN people.student_stream(p_student) = 'CCE'
                THEN coalesce((SELECT max(rs.number) FROM policy.route_semester rs WHERE rs.route = 'CCE' AND rs.session = p_session AND rs.state = 'OPEN'), 1)
                ELSE coalesce((SELECT max(sm.number) FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'), 1) END
$fn$;

/* add and drop, by the student's calendar */
CREATE OR REPLACE FUNCTION registration.add_drop_open(p_student uuid, p_session text, p_semester integer)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN people.student_stream(p_student) = 'CCE'
                THEN EXISTS (SELECT 1 FROM policy.route_semester rs
                              WHERE rs.route = 'CCE' AND rs.session = p_session AND rs.number = p_semester AND rs.state = 'OPEN'
                                AND current_date <= coalesce(rs.late_registration_closes, rs.registration_closes, current_date))
                ELSE registration.add_drop_open(p_session, p_semester) END
$fn$;

/* 'closed' or 'archived' when the student's calendar has closed the semester (its registrations are history), else null */
CREATE OR REPLACE FUNCTION registration.semester_closed(p_student uuid, p_session text, p_semester integer)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT lower(c.state) FROM registration.calendar_semester(p_student, p_session, p_semester) c WHERE c.state IN ('CLOSED', 'ARCHIVED')
$fn$;

/* why a CCE student may not register the semester now, or null when the door is open */
CREATE OR REPLACE FUNCTION registration.cce_gate(p_student uuid, p_session text, p_semester integer)
RETURNS text LANGUAGE sql STABLE AS $fn$
    WITH rs AS (SELECT * FROM policy.route_semester WHERE route = 'CCE' AND session = p_session AND number = p_semester),
         w AS (SELECT CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END AS ord)
    SELECT CASE
             WHEN NOT EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.session = p_session AND o.semester = p_semester AND o.stream = 'CCE')
                  THEN 'Course registration for the ' || w.ord || ' semester of ' || p_session || ' opens when the Centre for Continuing Education''s classes for it are set up.'
             WHEN pw.configured AND pw.state = 'CLOSED' THEN 'CCE course registration is currently closed for ' || p_session || ' ' || w.ord || ' semester.' || coalesce(' ' || pw.reason, '')
             WHEN pw.configured AND pw.state = 'SCHEDULED' THEN 'CCE course registration for ' || p_session || ' ' || w.ord || ' semester opens on ' || to_char(pw.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'EXPIRED' THEN 'CCE course registration for ' || p_session || ' ' || w.ord || ' semester closed on ' || to_char(coalesce(pw.late_until, pw.closes_at) AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'OPEN' THEN NULL
             WHEN rs.id IS NULL THEN 'The Centre for Continuing Education has not yet opened the ' || w.ord || ' semester of ' || p_session || ' for registration.'
             WHEN rs.state = 'CLOSED' THEN 'The CCE ' || w.ord || ' semester of ' || p_session || ' is closed for registration.'
             WHEN rs.state = 'NOT_YET_OPEN' THEN 'The CCE ' || w.ord || ' semester of ' || p_session || ' is not yet open for registration'
                  || coalesce('; registration opens on ' || to_char(rs.registration_opens, 'FMDD FMMonth YYYY'), '') || '.'
             WHEN rs.registration_opens IS NOT NULL AND current_date < rs.registration_opens
                  THEN 'CCE course registration for the ' || w.ord || ' semester of ' || p_session || ' opens on ' || to_char(rs.registration_opens, 'FMDD FMMonth YYYY') || '.'
             WHEN coalesce(rs.late_registration_closes, rs.registration_closes) IS NOT NULL AND current_date > coalesce(rs.late_registration_closes, rs.registration_closes)
                  THEN 'CCE course registration for the ' || w.ord || ' semester of ' || p_session || ' closed on ' || to_char(coalesce(rs.late_registration_closes, rs.registration_closes), 'FMDD FMMonth YYYY') || '.'
             ELSE NULL END
      FROM w LEFT JOIN rs ON true LEFT JOIN LATERAL (SELECT * FROM policy.window_state('CCE_COURSE_REGISTRATION', p_session, p_semester)) pw ON true
$fn$;
COMMENT ON FUNCTION registration.cce_gate(uuid, text, integer) IS
  'V380: the CCE student''s door to course registration — the Centre''s classes set up for the semester, then the Directorate of ICT''s CCE registration window (when it has set one), else the CCE calendar.';

/* the course load a CCE student carries per level, when the Academic Office states one (part-time students carry less than the
   full-time 18 to 24 units); until it does, the University's own level limits apply to every student alike */
CREATE TABLE policy.route_level_limit (
    route               text NOT NULL REFERENCES policy.study_route (code),
    level               integer NOT NULL CHECK (level IN (100, 200, 300, 400, 500, 600, 700, 800, 900)),
    min_units           integer NOT NULL,
    max_units           integer NOT NULL,
    probation_max_units integer NULL,
    instrument          text NULL CHECK (instrument IS NULL OR length(instrument) <= 200),
    updated_by          uuid NULL,
    updated_office      text NULL,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (route, level),
    CONSTRAINT ck_route_level_limit_range CHECK (min_units >= 0 AND max_units >= min_units),
    CONSTRAINT ck_route_level_limit_probation CHECK (probation_max_units IS NULL OR probation_max_units >= 0)
);
COMMENT ON TABLE policy.route_level_limit IS
  'V380: the course load of a route''s students per level (CCE: part-time), stated by the Academic Office; where none is stated the University''s policy.level_limit applies. Read through registration.unit_limit.';
SELECT audit.attach('policy.route_level_limit');

/* the unit range a student registers within at a level: the CCE load for a CCE student where one is stated, else the University's */
CREATE OR REPLACE FUNCTION registration.unit_limit(p_student uuid, p_level integer)
RETURNS SETOF policy.level_limit LANGUAGE sql STABLE AS $fn$
    SELECT x.level, x.applies_to, x.min_units, x.max_units, x.carryover_counts, x.instrument, x.probation_max_units FROM (
        SELECT r.level, 'CCE (part-time)'::text AS applies_to, r.min_units, r.max_units, coalesce(l.carryover_counts, true) AS carryover_counts,
               r.instrument, r.probation_max_units, 1 AS pr
          FROM policy.route_level_limit r LEFT JOIN policy.level_limit l ON l.level = r.level
         WHERE r.route = 'CCE' AND r.level = p_level AND people.student_stream(p_student) = 'CCE'
        UNION ALL
        SELECT l.level, l.applies_to, l.min_units, l.max_units, l.carryover_counts, l.instrument, l.probation_max_units, 2
          FROM policy.level_limit l WHERE l.level = p_level) x
     ORDER BY x.pr LIMIT 1
$fn$;
COMMENT ON FUNCTION registration.unit_limit(uuid, integer) IS
  'V380: the unit range (and the probation ceiling) a student registers within at a level — the CCE course load for a CCE student where the Academic Office stated one, else the University''s level limit.';

/* the Academic Office states (or, with no range, withdraws) the CCE course load of a level */
CREATE OR REPLACE FUNCTION policy.set_route_level_limit(p_route text, p_level integer, p_min integer, p_max integer, p_probation integer, p_instrument text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE cur policy.route_level_limit; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['academic', 'super'], 'the CCE course load');
    IF p_level IS NULL OR p_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900) THEN RAISE EXCEPTION 'CCE_LOAD_LEVEL: no such level' USING ERRCODE = '23514'; END IF;
    SELECT * INTO cur FROM policy.route_level_limit WHERE route = upper(btrim(p_route)) AND level = p_level FOR UPDATE;
    IF p_min IS NULL AND p_max IS NULL THEN
        DELETE FROM policy.route_level_limit WHERE route = upper(btrim(p_route)) AND level = p_level;
    ELSE
        IF p_min IS NULL OR p_max IS NULL OR p_min < 0 OR p_max < p_min THEN
            RAISE EXCEPTION 'CCE_LOAD_RANGE: a course load has a minimum and a maximum no lower than it' USING ERRCODE = '23514';
        END IF;
        INSERT INTO policy.route_level_limit (route, level, min_units, max_units, probation_max_units, instrument, updated_by, updated_office)
        VALUES (upper(btrim(p_route)), p_level, p_min, p_max, p_probation, nullif(btrim(coalesce(p_instrument, '')), ''), v_actor, v_office)
        ON CONFLICT (route, level) DO UPDATE SET min_units = EXCLUDED.min_units, max_units = EXCLUDED.max_units, probation_max_units = EXCLUDED.probation_max_units,
            instrument = EXCLUDED.instrument, updated_by = EXCLUDED.updated_by, updated_office = EXCLUDED.updated_office, updated_at = now();
    END IF;
    INSERT INTO policy.study_route_event (route, actor, office, what, before, after, reason)
    VALUES (upper(btrim(p_route)), v_actor, v_office, 'COURSE_LOAD ' || p_level || ' level',
            CASE WHEN cur.route IS NULL THEN NULL ELSE jsonb_build_object('min', cur.min_units, 'max', cur.max_units, 'probation_max', cur.probation_max_units) END,
            CASE WHEN p_min IS NULL AND p_max IS NULL THEN NULL ELSE jsonb_build_object('min', p_min, 'max', p_max, 'probation_max', p_probation) END,
            coalesce(nullif(btrim(coalesce(p_instrument, '')), ''), 'Stated'));
END $fn$;

-- ── 4 · the engine, by the student's stream and calendar ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.registration_gate(p_student uuid, p_session text, p_semester integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    WITH sm AS (SELECT * FROM policy.semester WHERE session = p_session AND number = p_semester),
         st AS (SELECT * FROM people.student WHERE id = p_student),
         w AS (SELECT CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END AS ord)
    SELECT CASE
             -- V380: a CCE student's door is the Centre's: its classes, the CCE window and the CCE calendar — never the full-time ones of the session
             WHEN st.entry_mode = 'CCE' THEN registration.cce_gate(p_student, p_session, p_semester)
             WHEN pw.configured AND pw.state = 'CLOSED' THEN 'Course registration is currently closed for ' || p_session || ' ' || w.ord || ' semester.' || coalesce(' ' || pw.reason, '')
             WHEN pw.configured AND pw.state = 'SCHEDULED' THEN 'Course registration for ' || p_session || ' ' || w.ord || ' semester opens on ' || to_char(pw.opens_at AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'EXPIRED' THEN 'Course registration for ' || p_session || ' ' || w.ord || ' semester closed on ' || to_char(coalesce(pw.late_until, pw.closes_at) AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'OPEN' THEN NULL
             WHEN NOT EXISTS (SELECT 1 FROM sm) THEN NULL
             WHEN sm.state = 'OPEN' THEN NULL
             WHEN sm.state IN ('CLOSED', 'ARCHIVED') THEN 'The ' || w.ord || ' semester of ' || p_session || ' is closed for registration.'
             WHEN sm.fresh_registration_from IS NOT NULL AND sm.fresh_registration_from <= current_date AND st.entry_session = p_session THEN NULL
             WHEN sm.fresh_registration_from IS NOT NULL AND st.entry_session = p_session
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' opens to fresh students on ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             WHEN sm.fresh_registration_from IS NOT NULL
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open; only the session''s fresh students register from ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             ELSE 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open for registration.'
           END
      FROM w LEFT JOIN sm ON true LEFT JOIN st ON true LEFT JOIN LATERAL (SELECT * FROM policy.window_state('COURSE_REGISTRATION', p_session, p_semester)) pw ON true
$function$;
CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, kind text, basis text, owner_dept text, carryover boolean, failed_in text, lecturer text, deferred boolean, deferred_from text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V380: the student's stream: a CCE student is offered the Centre's classes, every other student the full-time ones
    WITH s AS (SELECT st.*, CASE WHEN st.entry_mode = 'CCE' THEN 'CCE' ELSE 'REGULAR' END AS stream FROM people.student st WHERE st.id = p_student),
    -- V366: the GST/EPS courses of the programme at this level the student has already passed
    gst_passed AS (SELECT x.course_code FROM finance.gst_eps_rows(p_session, p_student) x WHERE x.status = 'ALREADY_PASSED'),
    eligible AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, co.basis, c.dept_code
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = s.stream
         WHERE (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)
           AND NOT (c.kind = 'GST' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE o.stream = s.stream AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)),
    -- a course set aside by an approved deferment, due since the student returned, offered this semester and not yet passed
    deferred AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Deferred'::text AS basis, c.dept_code,
               dc.original_session || ' semester ' || dc.original_semester AS deferred_from
          FROM people.deferred_courses(p_student) dc
          JOIN catalogue.course c ON c.code = dc.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE o.stream = s.stream AND dc.status = 'DEFERRED' AND dc.due
           AND (dc.original_session, dc.original_semester) < (p_session, p_semester)
           AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.code = c.code))
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis IN ('Carryover','Deferred')), x.failed_in, p.surname || ', ' || p.given_names,
           (x.basis = 'Deferred'), x.deferred_from
      FROM (SELECT e.*, NULL::text AS failed_in, NULL::text AS deferred_from FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
              AND NOT EXISTS (SELECT 1 FROM deferred df WHERE df.offering_id = e.offering_id)
            UNION ALL SELECT cv.*, NULL::text AS deferred_from FROM carry cv
            UNION ALL SELECT df.offering_id, df.code, df.title, df.units, df.kind, df.basis, df.dept_code, NULL::text, df.deferred_from FROM deferred df) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, (x.basis = 'Deferred') DESC, x.kind, x.code;
$function$;
CREATE OR REPLACE FUNCTION registration.open_course_registration(p_session text, p_semester integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'catalogue', 'registration', 'ref', 'policy'
AS $function$
DECLARE v_count int;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'course registration is opened by a person' USING ERRCODE = '23514';
    END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'no academic session % on the calendar — open the session first', p_session USING ERRCODE = '23503';
    END IF;

    -- 1 · decide, before any lock: the courses of this semester that some structure row offers for any
    --     track, or for a track that still has a student in that programme
    CREATE TEMP TABLE IF NOT EXISTS to_offer (course_code text PRIMARY KEY) ON COMMIT DROP;
    TRUNCATE to_offer;
    WITH live AS (
        SELECT DISTINCT st.programme_code, st.curriculum_track
          FROM people.student st
         WHERE st.status IN ('ACTIVE','PROBATION','ADMITTED')
    )
    INSERT INTO to_offer (course_code)
    SELECT DISTINCT c.code
      FROM catalogue.course c
      JOIN catalogue.course_offer co ON co.course_code = c.code
     WHERE c.semester = p_semester
       AND c.state <> 'ENDED'
       AND (co.track IS NULL
            OR EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code AND l.curriculum_track = co.track))
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o   -- V380: the full-time classes; the Centre opens its own
                        WHERE o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = 'REGULAR');

    -- 2 · insert the rows already chosen, with the audit trigger off for exactly that long
    ALTER TABLE catalogue.offering DISABLE TRIGGER trg_audit_catalogue_offering;
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), t.course_code, p_session, p_semester FROM to_offer t;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ALTER TABLE catalogue.offering ENABLE TRIGGER trg_audit_catalogue_offering;

    RETURN v_count;
END $function$;
CREATE OR REPLACE FUNCTION registration.student_add(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; lim policy.level_limit; v_units int; v_type text; v_status text; v_gate text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'register first, then add or drop' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_student, p_session, p_semester) THEN   -- V380: by the student's calendar
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514',
            HINT = 'It runs while the semester is open, up to the late-registration deadline set by the Registry.';
    END IF;
    IF NOT finance.clears(p_student, p_session, 'REGISTRATION') THEN
        RAISE EXCEPTION 'the Bursary has not cleared you for registration in %', p_session USING ERRCODE = '23514';
    END IF;

    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) WHERE offering_id = p_offering AND NOT carryover;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'that course is not offered to your programme at your level this semester' USING ERRCODE = '23514';
    END IF;
    -- V314: a GST or EPS course is added only by a student whose GST fee is paid
    v_gate := registration.gst_gate(p_student, p_session, m.course_code);
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; it opens the moment the payment is confirmed.';
    END IF;
    v_units := m.units;
    v_type := CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                   WHEN m.basis = 'Elective' OR m.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CURRENT' END;
    -- an approved registration has no further approval step, so the added course is examinable at once;
    -- a still-submitted one keeps REGISTERED and the HOD's approval flips it with the batch (RegistrationRepository)
    v_status := CASE WHEN r.status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END;

    -- would this exceed the level's maximum?
    SELECT * INTO lim FROM registration.unit_limit(p_student, r.level);   -- V380: the CCE course load for a CCE student
    IF FOUND AND registration.units_of(r.id) + v_units > lim.max_units THEN
        RAISE EXCEPTION 'adding this course puts you at % units, over the maximum of % at % level',
            registration.units_of(r.id) + v_units, lim.max_units, r.level USING ERRCODE = '23514',
            HINT = 'Drop a course first, or ask your Head of Department for an overload.';
    END IF;

    -- reinstate a dropped entry, or add a new one
    IF EXISTS (SELECT 1 FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering) THEN
        UPDATE registration.entry SET status = v_status, units = v_units, entry_type = v_type
         WHERE registration_id = r.id AND offering_id = p_offering;
    ELSE
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
        VALUES (r.id, p_offering, v_units, v_type, v_status);
    END IF;
    RETURN registration.units_of(r.id);
END $function$;
CREATE OR REPLACE FUNCTION registration.student_drop(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; e registration.entry;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'no registration to change' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_student, p_session, p_semester) THEN   -- V380: by the student's calendar
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514';
    END IF;

    SELECT * INTO e FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering AND status <> 'DROPPED';
    IF NOT FOUND THEN RAISE EXCEPTION 'that course is not on your registration' USING ERRCODE = '23514'; END IF;
    IF e.entry_type = 'CARRYOVER' THEN
        RAISE EXCEPTION 'a carryover cannot be dropped; it must be repeated' USING ERRCODE = '23514';
    END IF;
    IF e.entry_type = 'DEFERRED' THEN
        RAISE EXCEPTION 'a deferred course cannot be dropped; it is taken in the semester it is due' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
                WHERE sc.student_id = p_student AND sh.offering_id = p_offering) THEN
        RAISE EXCEPTION 'a mark is already recorded in this course; it cannot be dropped' USING ERRCODE = '23514';
    END IF;

    UPDATE registration.entry SET status = 'DROPPED' WHERE registration_id = r.id AND offering_id = p_offering;
    RETURN registration.units_of(r.id);
END $function$;
CREATE OR REPLACE FUNCTION registration.student_submit(p_registration uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; lim policy.level_limit; units int; st record; v_gate text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT', 'RETURNED') THEN RETURN 'already ' || lower(r.status); END IF;
    -- V361: the school fees the student owes for the session must be stated before they can be paid, or cleared
    IF NOT finance.fee_stated(r.student_id, r.session) THEN
        SELECT p.name AS programme, s.current_level AS level INTO st
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = r.student_id;
        RAISE EXCEPTION 'REG_FEES_NOT_STATED: the school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            coalesce(st.programme, 'the programme'), st.level, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration opens when the Bursary states the session''s school fees on Fee Setup and they are paid; nothing is assumed to be free.';
    END IF;
    IF NOT finance.semester_cleared(r.student_id, r.session, r.semester) THEN
        RAISE EXCEPTION 'the % semester school fees for % are not fully paid',
            CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration for a semester opens when that semester''s school fees are cleared in full; the position updates the moment a payment is confirmed.';
    END IF;
    -- V314: where the University holds the whole registration on the GST fee, an unpaid student does not submit
    v_gate := registration.gst_gate(r.student_id, r.session, NULL);
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; submission opens the moment the payment is confirmed.';
    END IF;
    -- and a GST/EPS course already on the draft is not submitted unpaid either
    SELECT registration.gst_gate(r.student_id, r.session, o.course_code) INTO v_gate
      FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
     WHERE e.registration_id = p_registration AND e.status <> 'DROPPED' AND registration.gst_gate(r.student_id, r.session, o.course_code) IS NOT NULL
     LIMIT 1;
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS, or remove the GST/EPS courses from the registration.';
    END IF;
    units := registration.units_of(p_registration);
    SELECT * INTO lim FROM registration.unit_limit(r.student_id, r.level);   -- V380: the CCE course load for a CCE student
    IF FOUND AND (units < lim.min_units OR units > lim.max_units) THEN
        RAISE EXCEPTION 'the registration carries % units; at % level the range is % to %', units, r.level, lim.min_units, lim.max_units
        USING ERRCODE = '23514', HINT = 'Add or drop courses to bring it within the range, or obtain an overload approval from the Head of Department.';
    END IF;
    SELECT * INTO st FROM assessment.student_standing(r.student_id);
    IF FOUND AND st.standing IN ('PROBATION', 'ADVISED_TO_WITHDRAW') AND lim.probation_max_units IS NOT NULL AND units > lim.probation_max_units THEN
        RAISE EXCEPTION 'you are on probation (CGPA % after % % semester); the registration carries % units and the limit on probation at % level is %',
            st.cgpa, st.pronounced_session, CASE st.pronounced_semester WHEN 1 THEN 'first' ELSE 'second' END, units, r.level, lim.probation_max_units
        USING ERRCODE = '23514', HINT = 'Drop courses to bring the registration within the probation limit. The carryovers stay; choose fewer new courses.';
    END IF;
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    RETURN 'submitted';
END $function$;
CREATE OR REPLACE FUNCTION registration.support_add_checks(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS TABLE(ord integer, rule text, label text, passed boolean, overridable boolean, advisory boolean, message text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; o catalogue.offering; c catalogue.course; r registration.course_registration; v_closed text; v_cal text; m record;
        lim policy.level_limit; v_status text; v_units int; v_add int; v_gate text; v_pre text; w text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
    IF o.id IS NOT NULL THEN SELECT * INTO c FROM catalogue.course WHERE code = o.course_code; END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    -- V380: the student's calendar (the CCE calendar for a CCE student)
    SELECT lower(x.state) INTO v_cal FROM registration.calendar_semester(p_student, p_session, p_semester) x;
    v_closed := registration.semester_closed(p_student, p_session, p_semester);
    v_status := coalesce(r.status, 'NONE');
    w := CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END;
    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) x WHERE x.offering_id = p_offering LIMIT 1;

    ord := 1; rule := 'STUDENT_ACTIVE'; label := 'Student is active'; overridable := false; advisory := false;
    passed := coalesce(s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION'), false);
    message := CASE WHEN s.id IS NULL THEN 'No such student.' WHEN passed THEN 'The student is ' || lower(s.status) || '.'
                    ELSE 'A student who is ' || lower(s.status) || ' does not register.' END;
    RETURN NEXT;

    ord := 2; rule := 'SESSION'; label := 'Correct academic session';
    passed := EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session);
    message := CASE WHEN passed THEN p_session || '.' ELSE 'No academic session ' || coalesce(p_session, '') || ' is on the calendar.' END;
    RETURN NEXT;

    ord := 3; rule := 'SEMESTER_RECORDS'; label := 'Semester not closed';
    passed := v_closed IS NULL;
    message := CASE WHEN passed THEN 'The ' || w || ' semester is ' || replace(coalesce(v_cal, 'not on the calendar'), '_', ' ') || '.'
                    ELSE 'The ' || w || ' semester of ' || p_session || ' is ' || v_closed || '; its registrations are history and are not changed.' END;
    RETURN NEXT;

    ord := 4; rule := 'COURSE_EXISTS'; label := 'Course exists';
    passed := o.id IS NOT NULL AND c.code IS NOT NULL;
    message := CASE WHEN passed THEN c.code || ' ' || c.title || ' (' || coalesce(o.units, c.units) || ' units).' ELSE 'No such course offering.' END;
    RETURN NEXT;

    ord := 5; rule := 'OFFERING_PERIOD'; label := 'Offered this session and semester';
    -- V380: and on the student's stream: a CCE student's class is the Centre's, a full-time student's a full-time class
    passed := o.id IS NOT NULL AND o.session = p_session AND o.semester = p_semester AND o.stream = people.student_stream(p_student);
    message := CASE WHEN o.id IS NULL THEN 'No such course offering.'
                    WHEN passed THEN 'Offered in ' || o.session || ', ' || w || ' semester' || CASE WHEN o.stream = 'CCE' THEN ', a class of the Centre for Continuing Education.' ELSE '.' END
                    WHEN o.session = p_session AND o.semester = p_semester AND o.stream = 'CCE'
                         THEN c.code || ' is offered here as a class of the Centre for Continuing Education; a full-time student registers on the full-time class.'
                    WHEN o.session = p_session AND o.semester = p_semester
                         THEN c.code || ' is offered here as a full-time class; a student of the Centre for Continuing Education registers on the Centre''s class.'
                    ELSE c.code || ' is offered in ' || o.session || ', ' || CASE o.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END
                         || ' semester — not in this registration''s session and semester.' END;
    RETURN NEXT;

    ord := 6; rule := 'COURSE_ACTIVE'; label := 'Course offering is active';
    passed := c.code IS NOT NULL AND c.state <> 'ENDED';
    message := CASE WHEN c.code IS NULL THEN 'No such course.' WHEN passed THEN 'The course is ' || lower(c.state) || '.' ELSE c.code || ' has ended (' || c.ended_on || ').' END;
    RETURN NEXT;

    ord := 7; rule := 'REGISTRATION_STATE'; label := 'Registration not locked';
    passed := v_status <> 'LOCKED';
    message := CASE WHEN v_status = 'NONE' THEN 'No registration yet; the engine drafts one.' WHEN passed THEN 'The registration is ' || lower(v_status) || '.'
                    ELSE 'This registration is locked and cannot be changed.' END;
    RETURN NEXT;

    ord := 8; rule := 'NOT_REGISTERED'; label := 'Not already on the registration';
    passed := NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.offering_id = p_offering AND e.status <> 'DROPPED');
    message := CASE WHEN passed THEN CASE WHEN EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.offering_id = p_offering)
                                          THEN 'Dropped earlier; adding it restores it.' ELSE 'Not on the registration.' END
                    ELSE coalesce(c.code, 'The course') || ' is already on the registration.' END;
    RETURN NEXT;

    ord := 9; rule := 'PROGRAMME_LEVEL'; label := 'Offered to the student''s programme and level'; overridable := true;
    passed := m.offering_id IS NOT NULL AND (NOT m.carryover OR v_status IN ('NONE', 'DRAFT', 'RETURNED'));
    message := CASE WHEN passed THEN coalesce(m.basis, c.kind, '') || ' for ' || s.programme_code || ' at ' || s.current_level || ' level.'
                    WHEN m.offering_id IS NOT NULL THEN 'A carry-over is placed by the engine when the registration is drafted; this registration is ' || lower(v_status) || '.'
                    WHEN c.code IS NULL THEN 'No such course.'
                    ELSE c.code || ' is not on the engine''s menu for ' || s.programme_code || ' at ' || s.current_level || ' level (a ' || c.level || ' level '
                         || lower(c.kind) || ' course of ' || c.dept_code || ').' END;
    RETURN NEXT;
    overridable := false;

    ord := 10; rule := 'UNITS'; label := 'Maximum credit load';
    SELECT * INTO lim FROM registration.unit_limit(p_student, coalesce(r.level, s.current_level));   -- V380: the CCE course load
    v_units := CASE WHEN r.id IS NULL THEN 0 ELSE registration.units_of(r.id) END;
    v_add := coalesce(m.units, o.units, c.units, 0);
    passed := lim.level IS NULL OR v_units + v_add <= lim.max_units;
    message := CASE WHEN lim.level IS NULL THEN 'No unit limit is set for the level.'
                    WHEN passed THEN v_units || ' + ' || v_add || ' units, within the maximum of ' || lim.max_units || '.'
                    ELSE 'Adding it puts the registration at ' || (v_units + v_add) || ' units, over the maximum of ' || lim.max_units || ' at ' || lim.level
                         || ' level; drop a course first, or the Head of Department approves an overload.' END;
    RETURN NEXT;

    ord := 11; rule := 'REGISTRATION_WINDOW'; label := 'Registration window and late registration'; overridable := true;
    v_gate := registration.registration_gate(p_student, p_session, p_semester);
    passed := v_gate IS NULL;
    message := coalesce(v_gate, 'Open.');
    RETURN NEXT;

    ord := 12; rule := 'ADD_DROP_PERIOD'; label := 'Add and drop period';
    IF v_status IN ('SUBMITTED', 'APPROVED') THEN
        passed := registration.add_drop_open(p_student, p_session, p_semester);
        message := CASE WHEN passed THEN 'Open.' ELSE 'Add and drop is not open for ' || p_session || ' semester ' || p_semester
                                                       || '; it runs while the semester is open, up to the late-registration deadline.' END;
    ELSE
        passed := true; message := 'Not needed: the registration is not yet submitted.';
    END IF;
    RETURN NEXT;
    overridable := false;

    ord := 13; rule := 'FEES'; label := 'Payment requirement';
    IF v_status IN ('SUBMITTED', 'APPROVED') THEN
        BEGIN
            passed := coalesce(finance.clears(p_student, p_session, 'REGISTRATION'), false);
            message := CASE WHEN passed THEN 'The Bursary clears the student for registration.' ELSE 'The Bursary has not cleared the student for registration in ' || p_session
                                                                                                   || '; refresh the payment entitlement if a payment is confirmed, else escalate to the Bursary.' END;
        EXCEPTION WHEN check_violation THEN
            passed := false; message := SQLERRM;
        END;
    ELSE
        advisory := true; passed := true;
        message := CASE WHEN finance.semester_cleared(p_student, p_session, p_semester) THEN 'The semester''s fees are cleared.'
                        ELSE 'The ' || w || ' semester''s fees are not cleared: the course goes on the draft, but the engine refuses the submission until they are.' END;
    END IF;
    RETURN NEXT;
    advisory := false;

    ord := 14; rule := 'GST'; label := 'GST/EPS requirement';
    v_gate := CASE WHEN c.code IS NULL THEN NULL ELSE registration.gst_gate(p_student, p_session, c.code) END;
    passed := v_gate IS NULL;
    message := coalesce(v_gate, CASE WHEN c.kind = 'GST' OR c.general_office IS NOT NULL THEN 'The GST fee is paid.' ELSE 'Not a GST/EPS course.' END);
    RETURN NEXT;

    ord := 15; rule := 'PREREQUISITES'; label := 'Prerequisites'; advisory := true; passed := true;
    SELECT string_agg(p.requires_code, ', ' ORDER BY p.requires_code) INTO v_pre FROM catalogue.course_prerequisite p WHERE p.course_code = c.code;
    message := CASE WHEN v_pre IS NULL THEN 'None recorded.' ELSE 'Recorded: ' || v_pre || '. The engine shows them; it does not refuse on them.' END;
    RETURN NEXT;

    ord := 16; rule := 'CORE_ELECTIVE'; label := 'Core or elective';
    message := CASE WHEN c.code IS NULL THEN '—' ELSE coalesce(m.basis, c.kind) || CASE WHEN c.kind = 'Elective' THEN ' — counts within the elective allowance.' ELSE '.' END END;
    RETURN NEXT;
END $function$;
CREATE OR REPLACE FUNCTION registration.support_drop_checks(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS TABLE(ord integer, rule text, label text, passed boolean, overridable boolean, advisory boolean, message text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r registration.course_registration; e registration.entry; v_closed text; v_status text; v_gate text; lim policy.level_limit; v_units int; v_code text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    v_closed := registration.semester_closed(p_student, p_session, p_semester);   -- V380: by the student's calendar
    IF r.id IS NOT NULL THEN SELECT * INTO e FROM registration.entry x WHERE x.registration_id = r.id AND x.offering_id = p_offering; END IF;
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering;
    v_status := coalesce(r.status, 'NONE');
    overridable := false; advisory := false;

    ord := 1; rule := 'REGISTRATION_EXISTS'; label := 'A registration to change';
    passed := r.id IS NOT NULL; message := CASE WHEN passed THEN 'The registration is ' || lower(v_status) || '.' ELSE 'No registration to change.' END;
    RETURN NEXT;
    ord := 2; rule := 'REGISTRATION_STATE'; label := 'Registration not locked';
    passed := v_status <> 'LOCKED'; message := CASE WHEN passed THEN 'Not locked.' ELSE 'This registration is locked and cannot be changed.' END;
    RETURN NEXT;
    ord := 3; rule := 'SEMESTER_RECORDS'; label := 'Semester not closed';
    passed := v_closed IS NULL;
    message := CASE WHEN passed THEN 'Not closed.' ELSE 'The semester is ' || v_closed || '; its registrations are history and are not changed.' END;
    RETURN NEXT;
    ord := 4; rule := 'ON_REGISTRATION'; label := 'On the current registration';
    passed := e.offering_id IS NOT NULL AND e.status <> 'DROPPED';
    message := CASE WHEN passed THEN coalesce(v_code, 'The course') || ' is ' || lower(e.status) || ' (' || e.units || ' units).'
                    ELSE coalesce(v_code, 'That course') || ' is not on the registration.' END;
    RETURN NEXT;
    ord := 5; rule := 'NOT_CARRYOVER'; label := 'Not a carry-over or deferred course';
    passed := e.offering_id IS NULL OR e.entry_type NOT IN ('CARRYOVER', 'DEFERRED');
    message := CASE WHEN passed THEN 'A ' || lower(coalesce(e.entry_type, 'current')) || ' course.'
                    WHEN e.entry_type = 'CARRYOVER' THEN 'A carry-over cannot be dropped; it must be repeated.'
                    ELSE 'A deferred course cannot be dropped; it is taken in the semester it is due.' END;
    RETURN NEXT;
    ord := 6; rule := 'NO_MARK'; label := 'No mark recorded';
    passed := NOT EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id WHERE sc.student_id = p_student AND sh.offering_id = p_offering);
    message := CASE WHEN passed THEN 'No mark is recorded.' ELSE 'A mark is already recorded in this course; it is examination history and is not dropped.' END;
    RETURN NEXT;
    ord := 7; rule := 'REGISTRATION_WINDOW'; label := 'Registration window and late registration'; overridable := true;
    v_gate := registration.registration_gate(p_student, p_session, p_semester);
    passed := v_gate IS NULL; message := coalesce(v_gate, 'Open.');
    RETURN NEXT;
    ord := 8; rule := 'ADD_DROP_PERIOD'; label := 'Add and drop period';
    IF v_status IN ('SUBMITTED', 'APPROVED') THEN
        passed := registration.add_drop_open(p_student, p_session, p_semester);
        message := CASE WHEN passed THEN 'Open.' ELSE 'Add and drop is not open for ' || p_session || ' semester ' || p_semester || '.' END;
    ELSE
        passed := true; message := 'Not needed: the registration is not yet submitted.';
    END IF;
    RETURN NEXT;
    overridable := false;
    ord := 9; rule := 'UNITS'; label := 'Minimum credit load'; advisory := true; passed := true;
    SELECT * INTO lim FROM registration.unit_limit(p_student, r.level);   -- V380: the CCE course load
    v_units := CASE WHEN r.id IS NULL THEN 0 ELSE registration.units_of(r.id) - CASE WHEN e.status IS NOT NULL AND e.status <> 'DROPPED' THEN e.units ELSE 0 END END;
    message := CASE WHEN lim.level IS NULL THEN 'No unit limit is set for the level.'
                    WHEN v_units >= lim.min_units THEN v_units || ' units after the drop, within the minimum of ' || lim.min_units || '.'
                    ELSE v_units || ' units after the drop, under the minimum of ' || lim.min_units || '; a draft so short is refused at submission.' END;
    RETURN NEXT;
END $function$;
CREATE OR REPLACE FUNCTION registration.support_submit(p_student uuid, p_session text, p_semester integer, p_override boolean, p_by uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; v_closed text; s people.student; v_gate text; v_out text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT coalesce(s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION'), false) THEN
        RAISE EXCEPTION 'REG_RULE: a student who is % does not register', lower(coalesce(s.status, 'unknown')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'REG_RULE: no registration for % semester % to submit', p_session, p_semester USING ERRCODE = '23514'; END IF;
    v_closed := registration.semester_closed(p_student, p_session, p_semester);   -- V380: by the student's calendar
    IF v_closed IS NOT NULL THEN
        RAISE EXCEPTION 'REG_RULE: the semester is %; its registrations are history and are not changed', v_closed USING ERRCODE = '23514';
    END IF;
    v_gate := registration.registration_gate(p_student, p_session, p_semester);
    IF v_gate IS NOT NULL AND NOT coalesce(p_override, false) THEN
        RAISE EXCEPTION 'REG_BLOCKED: %', v_gate USING ERRCODE = '23514',
            HINT = 'If the registration was interrupted by a portal fault, an agent whose posting carries the support override may set the window aside, on the student''s ticket.';
    END IF;
    IF v_gate IS NOT NULL AND (p_by IS NULL OR nullif(btrim(coalesce(p_reason, '')), '') IS NULL) THEN
        RAISE EXCEPTION 'REG_OVERRIDE: an override names who approves it and why' USING ERRCODE = '23514';
    END IF;
    v_out := registration.student_submit(r.id);   -- the fees, the GST gate, the unit range and the probation ceiling: the engine's
    RETURN jsonb_build_object('registrationId', r.id, 'status', (SELECT x.status FROM registration.course_registration x WHERE x.id = r.id), 'result', v_out,
                              'units', registration.units_of(r.id), 'overridden', v_gate IS NOT NULL, 'normalRule', v_gate);
END $function$;
CREATE OR REPLACE FUNCTION registration.semesters_unregistered(p_student uuid)
 RETURNS TABLE(semesters integer, last_registered text, first_missed text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    reg AS (SELECT r.session, r.semester FROM registration.course_registration r
             WHERE r.student_id = p_student AND r.status IN ('APPROVED','LOCKED')),
    -- V380: the semesters the student's calendar has closed — the CCE calendar's for a CCE student, the full-time calendar's for every other
    closed AS (
        SELECT c.session, c.semester FROM registration.closed_semesters() c CROSS JOIN s WHERE s.entry_mode IS DISTINCT FROM 'CCE'
        UNION ALL
        SELECT rs.session, rs.number FROM policy.route_semester rs CROSS JOIN s
         WHERE s.entry_mode = 'CCE' AND rs.route = 'CCE'
           AND (rs.state = 'CLOSED' OR coalesce(rs.late_registration_closes, rs.registration_closes) < current_date)),
    missed AS (
        SELECT c.session, c.semester FROM closed c CROSS JOIN s
         WHERE c.session >= s.entry_session
           AND NOT EXISTS (SELECT 1 FROM reg WHERE (reg.session, reg.semester) >= (c.session, c.semester))
           -- a semester set aside by an approved deferment was not missed
           AND NOT EXISTS (SELECT 1 FROM people.deferment d WHERE d.student_id = p_student AND d.session = c.session
                             AND d.state IN ('APPROVED','ACTIVE','COMPLETED') AND (d.kind = 'SESSION' OR d.semester = c.semester))
    ),
    word AS (SELECT 1 AS n, 'first' AS w UNION ALL SELECT 2, 'second' UNION ALL SELECT 3, 'third')
    SELECT (SELECT count(*) FROM missed)::int,
           (SELECT r.session || ' ' || coalesce(w.w, r.semester::text) || ' semester' FROM reg r LEFT JOIN word w ON w.n = r.semester ORDER BY r.session DESC, r.semester DESC LIMIT 1),
           (SELECT m.session || ' ' || coalesce(w.w, m.semester::text) || ' semester' FROM missed m LEFT JOIN word w ON w.n = m.semester ORDER BY m.session, m.semester LIMIT 1)
$function$;
CREATE OR REPLACE FUNCTION registration.registration_cause(p_session text, p_semester integer)
 RETURNS TABLE(faculty_code text, faculty text, programme_code text, programme text, expected integer, registered integer, not_registered integer, fee_blocked integer, cleared_idle integer, scheme_in_force boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_force boolean := policy.in_force('clearance', 'UNIVERSITY', current_date) IS NOT NULL;
BEGIN
    RETURN QUERY
    WITH pop AS (
        SELECT s.id, s.programme_code,
               EXISTS (SELECT 1 FROM registration.course_registration r
                        WHERE r.student_id = s.id AND r.session = p_session AND r.semester = p_semester
                          AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) AS reg
          FROM people.student s
         WHERE s.matric_no IS NOT NULL AND s.status IN ('ACTIVE', 'PROBATION')
           AND s.entry_mode IS DISTINCT FROM 'CCE'   -- V380: the full-time session's registration; CCE registers in its own session
    ),
    marked AS (
        SELECT pop.*,
               CASE WHEN pop.reg THEN false
                    WHEN v_force THEN NOT finance.clears(pop.id, p_session, 'REGISTRATION')
                    ELSE true END AS blocked
          FROM pop
    )
    SELECT f.code, f.name, pg.code, pg.name,
           count(*)::int AS expected,
           count(*) FILTER (WHERE m.reg)::int AS registered,
           count(*) FILTER (WHERE NOT m.reg)::int AS not_registered,
           count(*) FILTER (WHERE NOT m.reg AND m.blocked)::int AS fee_blocked,
           count(*) FILTER (WHERE NOT m.reg AND NOT m.blocked)::int AS cleared_idle,
           v_force
      FROM marked m
      JOIN ref.programme pg ON pg.code = m.programme_code
      JOIN ref.faculty f ON f.code = pg.faculty_code
     GROUP BY f.code, f.name, pg.code, pg.name
     ORDER BY f.name, pg.name;
END $function$;
CREATE OR REPLACE FUNCTION finance.late_registration_applies(p_student uuid, p_session text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM generate_series(1, 3) sem
         CROSS JOIN LATERAL policy.window_state(policy.window_type_for(p_student, 'COURSE_REGISTRATION'), p_session, sem) w   -- V380: a CCE student's own window
         WHERE w.configured AND w.late_fee_enabled
           AND ((w.phase = 'LATE' AND NOT EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = sem
                                                     AND r.submitted_at IS NOT NULL AND (w.closes_at IS NULL OR r.submitted_at <= w.closes_at)))
             OR EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = sem
                          AND r.submitted_at IS NOT NULL AND w.closes_at IS NOT NULL AND r.submitted_at > w.closes_at)))
$function$;
CREATE OR REPLACE FUNCTION finance.late_payment_applies(p_student uuid, p_session text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT w.late_fee_enabled AND w.phase = 'LATE'
       AND coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                      WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
                        AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at)), 0)
         < (SELECT coalesce(sum(c.amount), 0) FROM finance.charges_of(p_student, p_session, ARRAY['FEE']) c)
      FROM policy.window_state(policy.window_type_for(p_student, 'SCHOOL_FEES_PAYMENT'), p_session, NULL) w   -- V380: a CCE student's own window
$function$;
CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text, p_opens timestamp with time zone, p_closes timestamp with time zone, p_late_until timestamp with time zone, p_late_fee boolean, p_reason text, p_actor uuid, p_office text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
                      'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION',
                      'CCE_SCHOOL_FEES_PAYMENT', 'CCE_COURSE_REGISTRATION') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('ADMISSION_STATUS_CHECKING', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_ADMISSION_STATUS_CHECKING') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: admission status checking opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_APPLICATION_SESSION: an application window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF p_action NOT IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT') THEN RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514'; END IF;
    IF p_action IN ('CLOSE', 'REOPEN', 'SHORTEN') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'the reason for % is recorded, and none was given', lower(p_action) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM policy.portal_window WHERE window_type = p_type AND session = p_session AND coalesce(semester, 0) = coalesce(p_semester, 0) AND superseded_at IS NULL FOR UPDATE;
    SELECT * INTO prev FROM policy.window_state(p_type, p_session, p_semester);
    v_opens := coalesce(p_opens, cur.opens_at); v_closes := coalesce(p_closes, cur.closes_at); v_late := coalesce(p_late_until, cur.late_until);
    v_fee := coalesce(p_late_fee, cur.late_fee_enabled, false);
    CASE p_action
        WHEN 'OPEN', 'REOPEN' THEN v_forced := CASE WHEN p_opens IS NULL AND p_closes IS NULL THEN 'OPEN' ELSE NULL END;
                                   IF p_opens IS NULL AND p_closes IS NOT NULL THEN v_opens := now(); END IF;
        WHEN 'CLOSE' THEN v_forced := 'CLOSED';
        WHEN 'SCHEDULE' THEN IF p_opens IS NULL THEN RAISE EXCEPTION 'a schedule names when the window opens' USING ERRCODE = '23514'; END IF; v_forced := NULL;
        WHEN 'EXTEND' THEN IF p_closes IS NULL AND p_late_until IS NULL THEN RAISE EXCEPTION 'an extension names the new closing' USING ERRCODE = '23514'; END IF;
                           IF cur.id IS NOT NULL AND p_closes IS NOT NULL AND cur.closes_at IS NOT NULL AND p_closes < cur.closes_at THEN RAISE EXCEPTION 'that closing is earlier than before; shorten the window instead' USING ERRCODE = '23514'; END IF;
                           v_forced := CASE WHEN cur.forced = 'CLOSED' THEN NULL ELSE cur.forced END;
        WHEN 'SHORTEN' THEN IF p_closes IS NULL THEN RAISE EXCEPTION 'a shortening names the new closing' USING ERRCODE = '23514'; END IF; v_forced := cur.forced;
        WHEN 'EDIT' THEN v_forced := cur.forced;
    END CASE;
    IF v_closes IS NOT NULL AND v_opens IS NOT NULL AND v_closes < v_opens THEN RAISE EXCEPTION 'the window closes before it opens' USING ERRCODE = '23514'; END IF;
    IF v_late IS NOT NULL AND v_closes IS NOT NULL AND v_late < v_closes THEN RAISE EXCEPTION 'the late period ends before the window closes' USING ERRCODE = '23514'; END IF;
    IF cur.id IS NOT NULL THEN UPDATE policy.portal_window SET superseded_at = now() WHERE id = cur.id; END IF;
    INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, late_until, late_fee_enabled, forced, reason, created_by, created_office)
    VALUES (p_type, p_session, p_semester, v_opens, v_closes, v_late, v_fee, v_forced, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office)
    RETURNING id INTO v_id;
    SELECT * INTO nxt FROM policy.window_state(p_type, p_session, p_semester);
    INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, previous_state, new_state, previous_opens_at, previous_closes_at, previous_late_until,
                                            new_opens_at, new_closes_at, new_late_until, late_fee_enabled, reason, actor, office)
    VALUES (v_id, p_type, p_session, p_semester, p_action, CASE WHEN prev.configured THEN prev.state ELSE prev.state || ' (default)' END, nxt.state, cur.opens_at, cur.closes_at, cur.late_until,
            v_opens, v_closes, v_late, v_fee, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office);
    RETURN v_id;
END $function$;

-- ── 5 · the Centre's classes ────────────────────────────────────────────────────────────────────────────────────
/* the sessions the Centre's classes are opened in: the CCE session, and the one after it (planned ahead) */
CREATE OR REPLACE FUNCTION catalogue.cce_class_session(p_session text)
RETURNS void LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_cce text := policy.route_session('CCE');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session AND a.state <> 'CANCELLED') THEN
        RAISE EXCEPTION 'CCE_SESSION_UNKNOWN: % is not a session on the calendar (or it was cancelled)', p_session USING ERRCODE = '23514';
    END IF;
    IF p_session IS DISTINCT FROM v_cce AND p_session IS DISTINCT FROM policy.session_after(v_cce, 1) THEN
        RAISE EXCEPTION 'CCE_CLASS_SESSION: the Centre''s classes are opened in the CCE session (%) or the one after it, not in %', v_cce, p_session USING ERRCODE = '23514';
    END IF;
END $fn$;

/* every class the semester needs, opened at once: each course a CCE programme offers in that semester (for a track still
   carrying a CCE student, or any track), and each carry-over a CCE student owes from that semester; one already open stays */
CREATE OR REPLACE FUNCTION catalogue.cce_open_classes(p_session text, p_semester integer)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'opening the Centre''s classes');
    IF p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'CCE_CLASS_SEMESTER: a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    PERFORM catalogue.cce_class_session(p_session);
    WITH live AS (SELECT DISTINCT st.programme_code, st.curriculum_track FROM people.student st
                   WHERE st.entry_mode = 'CCE' AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    offered AS (
        SELECT DISTINCT c.code
          FROM catalogue.course c
          JOIN catalogue.course_offer co ON co.course_code = c.code
          JOIN ref.programme_route pr ON pr.programme_code = co.programme_code AND pr.route = 'CCE' AND pr.active
         WHERE c.semester = p_semester AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
           AND (co.track IS NULL OR EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code AND l.curriculum_track = co.track))
        UNION
        SELECT DISTINCT c.code
          FROM people.student st
          CROSS JOIN LATERAL registration.carryovers(st.id) cv
          JOIN catalogue.course c ON c.code = cv.course_code
         WHERE st.entry_mode = 'CCE' AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND c.semester = p_semester AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %')
    INSERT INTO catalogue.offering (id, course_code, session, semester, stream)
    SELECT gen_random_uuid(), o.code, p_session, p_semester, 'CCE' FROM offered o
    ON CONFLICT (course_code, session, semester, stream) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;

/* one class added by hand (a course the semester's opening did not reach) */
CREATE OR REPLACE FUNCTION catalogue.cce_add_class(p_course text, p_session text, p_semester integer)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE c catalogue.course; v uuid;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'adding a class of the Centre');
    IF p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'CCE_CLASS_SEMESTER: a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    PERFORM catalogue.cce_class_session(p_session);
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_course, '')));
    IF c.code IS NULL THEN RAISE EXCEPTION 'CCE_CLASS_COURSE: no course % on the catalogue', p_course USING ERRCODE = '23514'; END IF;
    IF c.state = 'ENDED' THEN RAISE EXCEPTION 'CCE_CLASS_COURSE: % has ended; restore it on the catalogue first', c.code USING ERRCODE = '23514'; END IF;
    INSERT INTO catalogue.offering (id, course_code, session, semester, stream)
    VALUES (gen_random_uuid(), c.code, p_session, p_semester, 'CCE')
    ON CONFLICT (course_code, session, semester, stream) DO NOTHING;
    SELECT id INTO v FROM catalogue.offering WHERE course_code = c.code AND session = p_session AND semester = p_semester AND stream = 'CCE';
    RETURN v;
END $fn$;

/* a class nobody has used, withdrawn: no registration, sheet, register, material, examination or posting refers to it */
CREATE OR REPLACE FUNCTION catalogue.cce_withdraw_class(p_offering uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE o catalogue.offering; v_what text;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'withdrawing a class of the Centre');
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering FOR UPDATE;
    IF o.id IS NULL THEN RAISE EXCEPTION 'no such class' USING ERRCODE = '23503'; END IF;
    IF o.stream <> 'CCE' THEN RAISE EXCEPTION 'CCE_CLASS_NOT_CCE: % is a full-time class; the Centre withdraws only its own', o.course_code USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'CCE_CLASS_REASON: a class is withdrawn with its reason' USING ERRCODE = '23514'; END IF;
    v_what := CASE WHEN EXISTS (SELECT 1 FROM registration.entry e WHERE e.offering_id = o.id) THEN 'students have registered on it'
                   WHEN EXISTS (SELECT 1 FROM assessment.score_sheet s WHERE s.offering_id = o.id) THEN 'it has a score sheet'
                   WHEN EXISTS (SELECT 1 FROM attendance.register r WHERE r.context = 'COURSE' AND r.subject_ref = o.id) THEN 'attendance has been taken on it'
                   WHEN EXISTS (SELECT 1 FROM lms.material m WHERE m.offering_id = o.id) OR EXISTS (SELECT 1 FROM lms.assignment a WHERE a.offering_id = o.id) THEN 'its course space has material'
                   WHEN EXISTS (SELECT 1 FROM assessment.cbt_exam x WHERE x.offering_id = o.id) OR EXISTS (SELECT 1 FROM assessment.exam_timetable t WHERE t.offering_id = o.id) THEN 'an examination is set on it'
                   WHEN EXISTS (SELECT 1 FROM people.deferred_course d WHERE d.offering_id = o.id) OR EXISTS (SELECT 1 FROM assessment.siwes_supervisor v WHERE v.offering_id = o.id) THEN 'a student record refers to it'
                   END;
    IF v_what IS NOT NULL THEN
        RAISE EXCEPTION 'CCE_CLASS_IN_USE: % stays — %; a class with history is kept', o.course_code, v_what USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', 'CCE class withdrawn: ' || btrim(p_reason), true);
    DELETE FROM catalogue.class_slot WHERE offering_id = o.id;
    DELETE FROM catalogue.offering_teacher WHERE offering_id = o.id;
    DELETE FROM catalogue.offering WHERE id = o.id;
END $fn$;

-- ── 6 · the evening timetable ───────────────────────────────────────────────────────────────────────────────────
CREATE TABLE policy.route_period (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    route      text NOT NULL REFERENCES policy.study_route (code),
    label      text NOT NULL CHECK (btrim(label) <> '' AND length(label) <= 60),
    starts_at  time NOT NULL,
    ends_at    time NOT NULL,
    active     boolean NOT NULL DEFAULT true,
    ord        integer NOT NULL DEFAULT 0,
    updated_by uuid NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_route_period_times CHECK (ends_at > starts_at),
    CONSTRAINT uq_route_period UNIQUE (route, starts_at, ends_at)
);
COMMENT ON TABLE policy.route_period IS
  'V380: the lecture periods a route''s timetable offers as quick picks (the CCE evening periods). Data the Centre or the Academic Office edits or retires; a slot may still be any time.';
SELECT audit.attach('policy.route_period');
-- the examples the University gave, as editable data the Centre may change or retire
INSERT INTO policy.route_period (route, label, starts_at, ends_at, ord) VALUES
    ('CCE', '4:00 pm – 6:00 pm', '16:00', '18:00', 1),
    ('CCE', '5:00 pm – 7:00 pm', '17:00', '19:00', 2),
    ('CCE', '6:00 pm – 8:00 pm', '18:00', '20:00', 3),
    ('CCE', '7:00 pm – 9:00 pm', '19:00', '21:00', 4);

CREATE OR REPLACE FUNCTION policy.set_route_period(p_id uuid, p_route text, p_label text, p_starts time, p_ends time, p_active boolean, p_ord integer)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'the CCE lecture periods');
    IF p_starts IS NULL OR p_ends IS NULL OR p_ends <= p_starts THEN RAISE EXCEPTION 'CCE_PERIOD_TIMES: a period ends after it starts' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_label, '')), '') IS NULL THEN RAISE EXCEPTION 'CCE_PERIOD_LABEL: a period has a label' USING ERRCODE = '23514'; END IF;
    IF p_id IS NULL THEN
        INSERT INTO policy.route_period (route, label, starts_at, ends_at, active, ord, updated_by)
        VALUES (upper(btrim(p_route)), btrim(p_label), p_starts, p_ends, coalesce(p_active, true), coalesce(p_ord, 0), v_actor)
        RETURNING id INTO v;
    ELSE
        UPDATE policy.route_period SET label = btrim(p_label), starts_at = p_starts, ends_at = p_ends, active = coalesce(p_active, true),
               ord = coalesce(p_ord, ord), updated_by = v_actor, updated_at = now()
         WHERE id = p_id AND route = upper(btrim(p_route)) RETURNING id INTO v;
        IF v IS NULL THEN RAISE EXCEPTION 'no such period' USING ERRCODE = '23503'; END IF;
    END IF;
    RETURN v;
END $fn$;

/* a CCE class's slot: the Centre's or the Academic Office's; no venue or lecturer is in two CCE classes at once */
CREATE OR REPLACE FUNCTION catalogue.class_slot_route_guard() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE o catalogue.offering; v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_clash text;
BEGIN
    SELECT * INTO o FROM catalogue.offering WHERE id = NEW.offering_id;
    IF o.stream IS DISTINCT FROM 'CCE' THEN RETURN NEW; END IF;
    IF coalesce(v_office, '') NOT IN ('cce', 'academic', 'super') THEN
        RAISE EXCEPTION 'CCE_SLOT_OFFICE: a class of the Centre for Continuing Education is put on the timetable by the Centre or the Academic Office' USING ERRCODE = '23514';
    END IF;
    IF NEW.ended_at IS NULL THEN
        -- one CCE timetable write at a time per session and semester, so two lectures saved at once cannot both miss each other
        PERFORM pg_advisory_xact_lock(hashtext('cce-timetable:' || o.session || ':' || o.semester));
        SELECT o2.course_code || ' (' || to_char(s.starts_at, 'HH24:MI') || '–' || to_char(s.ends_at, 'HH24:MI') || ')' INTO v_clash
          FROM catalogue.class_slot s JOIN catalogue.offering o2 ON o2.id = s.offering_id
         WHERE s.ended_at IS NULL AND s.id <> NEW.id AND o2.stream = 'CCE' AND o2.session = o.session AND o2.semester = o.semester
           AND s.weekday = NEW.weekday AND lower(btrim(s.venue)) = lower(btrim(NEW.venue))
           AND s.starts_at < NEW.ends_at AND NEW.starts_at < s.ends_at
         LIMIT 1;
        IF v_clash IS NOT NULL THEN
            RAISE EXCEPTION 'CCE_SLOT_VENUE_CLASH: % is already taken then by %', btrim(NEW.venue), v_clash USING ERRCODE = '23514';
        END IF;
        IF o.lecturer_id IS NOT NULL THEN
            SELECT o2.course_code || ' (' || to_char(s.starts_at, 'HH24:MI') || '–' || to_char(s.ends_at, 'HH24:MI') || ')' INTO v_clash
              FROM catalogue.class_slot s JOIN catalogue.offering o2 ON o2.id = s.offering_id
             WHERE s.ended_at IS NULL AND s.id <> NEW.id AND o2.id <> o.id AND o2.stream = 'CCE' AND o2.session = o.session AND o2.semester = o.semester
               AND o2.lecturer_id = o.lecturer_id AND s.weekday = NEW.weekday AND s.starts_at < NEW.ends_at AND NEW.starts_at < s.ends_at
             LIMIT 1;
            IF v_clash IS NOT NULL THEN
                RAISE EXCEPTION 'CCE_SLOT_LECTURER_CLASH: the lecturer teaches % then', v_clash USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_class_slot_route BEFORE INSERT OR UPDATE ON catalogue.class_slot FOR EACH ROW EXECUTE FUNCTION catalogue.class_slot_route_guard();

/* what the CCE timetable still has to settle: a lecturer in two classes at once (allocated after the slots were set), a
   venue in two (the same), a programme's level with two of its courses at once, and a venue a full-time class uses then */
CREATE OR REPLACE FUNCTION catalogue.cce_clashes(p_session text, p_semester integer)
RETURNS TABLE (kind text, weekday integer, starts_at time, ends_at time, first_course text, second_course text, detail text)
LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT sl.id, sl.weekday, sl.starts_at, sl.ends_at, lower(btrim(sl.venue)) AS venue, btrim(sl.venue) AS venue_text,
                      o.id AS offering_id, o.course_code, o.lecturer_id
                 FROM catalogue.class_slot sl JOIN catalogue.offering o ON o.id = sl.offering_id
                WHERE sl.ended_at IS NULL AND o.stream = 'CCE' AND o.session = p_session AND o.semester = p_semester),
    pairs AS (SELECT a.*, b.course_code AS b_course, b.offering_id AS b_offering, b.lecturer_id AS b_lecturer, b.venue AS b_venue,
                     greatest(a.starts_at, b.starts_at) AS s_at, least(a.ends_at, b.ends_at) AS e_at
                FROM s a JOIN s b ON a.weekday = b.weekday AND a.id < b.id AND a.offering_id <> b.offering_id
                                 AND a.starts_at < b.ends_at AND b.starts_at < a.ends_at)
    SELECT 'LECTURER', p.weekday, p.s_at, p.e_at, p.course_code, p.b_course,
           coalesce((SELECT pe.surname || ', ' || pe.given_names FROM iam.person pe WHERE pe.id = p.lecturer_id), 'The lecturer') || ' teaches both'
      FROM pairs p WHERE p.lecturer_id IS NOT NULL AND p.lecturer_id = p.b_lecturer
    UNION ALL
    SELECT 'VENUE', p.weekday, p.s_at, p.e_at, p.course_code, p.b_course, p.venue_text || ' holds both'
      FROM pairs p WHERE p.venue = p.b_venue
    UNION ALL
    SELECT DISTINCT 'STUDENTS', p.weekday, p.s_at, p.e_at, p.course_code, p.b_course,
           pr.name || ', ' || ca.level || ' level, takes both'
      FROM pairs p
      JOIN catalogue.course_offer ca ON ca.course_code = p.course_code AND ca.basis IN ('Core', 'GST')
      JOIN catalogue.course_offer cb ON cb.course_code = p.b_course AND cb.programme_code = ca.programme_code AND cb.level = ca.level AND cb.basis IN ('Core', 'GST')
      JOIN ref.programme_route rt ON rt.programme_code = ca.programme_code AND rt.route = 'CCE' AND rt.active
      JOIN ref.programme pr ON pr.code = ca.programme_code
    UNION ALL
    SELECT DISTINCT 'FULL_TIME_VENUE', s.weekday, greatest(s.starts_at, f.starts_at), least(s.ends_at, f.ends_at), s.course_code, fo.course_code,
           s.venue_text || ' is on the full-time timetable of ' || fo.session || ' then'
      FROM s
      JOIN catalogue.class_slot f ON f.ended_at IS NULL AND f.weekday = s.weekday AND lower(btrim(f.venue)) = s.venue
                                 AND f.starts_at < s.ends_at AND s.starts_at < f.ends_at
      JOIN catalogue.offering fo ON fo.id = f.offering_id AND fo.stream = 'REGULAR' AND fo.session = policy.university_current_session()
$fn$;

-- ── 7 · attendance on the register, for course classes ──────────────────────────────────────────────────────────
ALTER TABLE attendance.register DROP CONSTRAINT register_context_check;
ALTER TABLE attendance.register ADD CONSTRAINT register_context_check CHECK (context IN ('JUPEB', 'COURSE'));
ALTER TABLE attendance.policy DROP CONSTRAINT policy_context_check;
ALTER TABLE attendance.policy ADD CONSTRAINT policy_context_check CHECK (context IN ('JUPEB', 'CCE', 'COURSE'));
ALTER TABLE attendance.policy ADD COLUMN show_students boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN attendance.policy.show_students IS 'V380: whether the students read their own attendance on the portal (the University''s policy; shown unless it says otherwise).';
CREATE INDEX ix_attendance_register_course ON attendance.register (subject_ref, held_on DESC) WHERE context = 'COURSE';

/* the person teaches the class: its lecturer, its second examiner or a co-lecturer */
CREATE OR REPLACE FUNCTION attendance.course_teaches(p_person uuid, p_offering uuid)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM catalogue.offering o
                    WHERE o.id = p_offering AND p_person IS NOT NULL
                      AND (o.lecturer_id = p_person OR o.second_examiner_id = p_person
                           OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = p_person)))
$fn$;

/* the attendance policy a class answers to: the Centre's for a CCE class, the course classes' for a full-time one */
CREATE OR REPLACE FUNCTION attendance.course_policy(p_offering uuid)
RETURNS TABLE (min_percent numeric, warn_band numeric, min_classes integer, show_students boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT p.min_percent, p.warn_band, p.min_classes, p.show_students
      FROM catalogue.offering o
      JOIN attendance.policy p ON p.context = CASE WHEN o.stream = 'CCE' THEN 'CCE' ELSE 'COURSE' END AND p.session IN (o.session, '*')
     WHERE o.id = p_offering
     ORDER BY (p.session = '*') LIMIT 1
$fn$;

/* the student's attendance on each class of the session, by the register */
CREATE OR REPLACE FUNCTION attendance.course_summary(p_student uuid, p_session text)
RETURNS TABLE (offering_id uuid, course_code text, title text, semester integer, total integer, present integer, absent integer,
               late integer, excused integer, counted integer, rate numeric, min_percent numeric, verdict text, show_students boolean)
LANGUAGE sql STABLE AS $fn$
    WITH mine AS (
        SELECT DISTINCT o.id, o.course_code, coalesce(o.title, c.title) AS title, o.semester
          FROM registration.course_registration cr
          JOIN registration.entry e ON e.registration_id = cr.id AND e.status IN ('REGISTERED', 'APPROVED')
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code
         WHERE cr.student_id = p_student AND cr.session = p_session),
    g AS (SELECT m.id, count(k.id)::int AS total,
                 count(*) FILTER (WHERE k.status = 'PRESENT')::int AS present, count(*) FILTER (WHERE k.status = 'ABSENT')::int AS absent,
                 count(*) FILTER (WHERE k.status = 'LATE')::int AS late, count(*) FILTER (WHERE k.status = 'EXCUSED')::int AS excused
            FROM mine m
            LEFT JOIN attendance.register r ON r.context = 'COURSE' AND r.subject_ref = m.id
            LEFT JOIN attendance.mark k ON k.register_id = r.id AND k.member_ref = p_student
           GROUP BY m.id)
    SELECT m.id, m.course_code, m.title, m.semester, g.total, g.present, g.absent, g.late, g.excused, g.total - g.excused,
           CASE WHEN g.total - g.excused > 0 THEN round(100.0 * (g.present + g.late) / (g.total - g.excused), 2) END,
           pol.min_percent,
           CASE WHEN pol.min_percent IS NULL OR g.total = 0 THEN NULL WHEN g.total - g.excused = 0 THEN 'REQUIRES_REVIEW'
                WHEN round(100.0 * (g.present + g.late) / (g.total - g.excused), 2) >= pol.min_percent THEN 'ELIGIBLE' ELSE 'NOT_ELIGIBLE' END,
           coalesce(pol.show_students, true)
      FROM mine m JOIN g ON g.id = m.id
      LEFT JOIN LATERAL attendance.course_policy(m.id) pol ON true
     ORDER BY m.semester, m.course_code
$fn$;

/* attendance by student and class, for a stream (CCE), a session, a semester, a faculty, department, programme or course,
   and a date range — the reports the Centre and the Academic Office read */
CREATE OR REPLACE FUNCTION attendance.course_report(p_stream text, p_session text, p_semester integer, p_faculty text, p_dept text,
                                                   p_programme text, p_course text, p_from date, p_to date)
RETURNS TABLE (student_id uuid, number text, name text, programme_code text, programme text, level integer, faculty text, department text,
               offering_id uuid, course_code text, title text, semester integer, total integer, present integer, absent integer,
               late integer, excused integer, rate numeric, min_percent numeric, verdict text)
LANGUAGE sql STABLE AS $fn$
    WITH cls AS (SELECT o.id, o.course_code, coalesce(o.title, c.title) AS title, o.semester
                   FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                  WHERE (p_stream IS NULL OR o.stream = p_stream) AND o.session = p_session
                    AND (p_semester IS NULL OR o.semester = p_semester) AND (p_course IS NULL OR o.course_code = upper(btrim(p_course)))),
    k AS (SELECT r.subject_ref AS offering_id, m.member_ref AS student_id, m.status
            FROM attendance.register r JOIN cls ON cls.id = r.subject_ref
            JOIN attendance.mark m ON m.register_id = r.id
           WHERE r.context = 'COURSE' AND (p_from IS NULL OR r.held_on >= p_from) AND (p_to IS NULL OR r.held_on <= p_to)),
    g AS (SELECT k.offering_id, k.student_id, count(*)::int AS total,
                 count(*) FILTER (WHERE k.status = 'PRESENT')::int AS present, count(*) FILTER (WHERE k.status = 'ABSENT')::int AS absent,
                 count(*) FILTER (WHERE k.status = 'LATE')::int AS late, count(*) FILTER (WHERE k.status = 'EXCUSED')::int AS excused
            FROM k GROUP BY k.offering_id, k.student_id)
    SELECT st.id, coalesce(st.matric_no, st.admission_no), st.surname || ', ' || st.other_names, st.programme_code, pr.name, st.current_level,
           f.name, d.name, cls.id, cls.course_code, cls.title, cls.semester, g.total, g.present, g.absent, g.late, g.excused,
           CASE WHEN g.total - g.excused > 0 THEN round(100.0 * (g.present + g.late) / (g.total - g.excused), 2) END,
           pol.min_percent,
           CASE WHEN pol.min_percent IS NULL THEN NULL WHEN g.total - g.excused = 0 THEN 'REQUIRES_REVIEW'
                WHEN round(100.0 * (g.present + g.late) / (g.total - g.excused), 2) >= pol.min_percent THEN 'ELIGIBLE' ELSE 'NOT_ELIGIBLE' END
      FROM g
      JOIN cls ON cls.id = g.offering_id
      JOIN people.student st ON st.id = g.student_id
      JOIN ref.programme pr ON pr.code = st.programme_code
      LEFT JOIN ref.department d ON d.code = pr.dept_code
      LEFT JOIN ref.faculty f ON f.code = pr.faculty_code
      LEFT JOIN LATERAL attendance.course_policy(cls.id) pol ON true
     WHERE (p_faculty IS NULL OR pr.faculty_code = p_faculty) AND (p_dept IS NULL OR pr.dept_code = p_dept)
       AND (p_programme IS NULL OR st.programme_code = p_programme)
     ORDER BY cls.course_code, st.surname, st.other_names
$fn$;

/* the Centre sets its attendance policy: the minimum attendance (blank: none is enforced), the warning band, the classes
   counted before a warning, and whether students read their own attendance */
CREATE OR REPLACE FUNCTION attendance.set_cce_policy(p_session text, p_min numeric, p_warn numeric, p_min_classes integer, p_show boolean)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'the CCE attendance policy');
    IF p_session IS NULL OR (p_session <> '*' AND NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session)) THEN
        RAISE EXCEPTION 'CCE_SESSION_UNKNOWN: % is not a session on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    INSERT INTO attendance.policy (context, session, min_percent, warn_band, min_classes, show_students, updated_by)
    VALUES ('CCE', p_session, p_min, p_warn, coalesce(p_min_classes, 3), coalesce(p_show, true), v_actor)
    ON CONFLICT (context, session) DO UPDATE SET min_percent = EXCLUDED.min_percent, warn_band = EXCLUDED.warn_band,
        min_classes = EXCLUDED.min_classes, show_students = EXCLUDED.show_students, updated_by = EXCLUDED.updated_by, updated_at = now();
END $fn$;

-- ── 8 · the register's references, for course classes ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION attendance.check_refs() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.context = 'JUPEB' THEN
        IF NOT EXISTS (SELECT 1 FROM jupeb.subject WHERE id = NEW.subject_ref) THEN
            RAISE EXCEPTION 'ATT_SUBJECT: no such JUPEB subject' USING ERRCODE = '23514';
        END IF;
        IF NEW.class_ref IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jupeb.class WHERE id = NEW.class_ref AND session = NEW.session) THEN
            RAISE EXCEPTION 'ATT_CLASS: no such JUPEB class in %', NEW.session USING ERRCODE = '23514';
        END IF;
    ELSIF NEW.context = 'COURSE' THEN
        -- V380: a course class's register: the subject is the class (catalogue.offering) of that session and semester
        IF NOT EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.id = NEW.subject_ref AND o.session = NEW.session AND o.semester = NEW.semester) THEN
            RAISE EXCEPTION 'ATT_OFFERING: no such class in % semester %', NEW.session, NEW.semester USING ERRCODE = '23514';
        END IF;
        IF NEW.class_ref IS NOT NULL THEN
            RAISE EXCEPTION 'ATT_CLASS: a course class''s register has no class group' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION attendance.check_slot_ref() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.slot_ref IS NOT NULL AND NOT (CASE NEW.context
            WHEN 'JUPEB' THEN EXISTS (SELECT 1 FROM jupeb.timetable_slot t WHERE t.id = NEW.slot_ref AND t.subject_id = NEW.subject_ref AND t.session = NEW.session
                                         AND t.semester = NEW.semester AND t.class_id IS NOT DISTINCT FROM NEW.class_ref)
            -- V380: a course class's lecture is one of the class's own slots on the timetable
            WHEN 'COURSE' THEN EXISTS (SELECT 1 FROM catalogue.class_slot s WHERE s.id = NEW.slot_ref AND s.offering_id = NEW.subject_ref)
            ELSE false END) THEN
        RAISE EXCEPTION 'ATT_SLOT: that lecture is not of this subject, class, session and semester' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;

/* who is on a register: a JUPEB subject's students, or a course class's registered students (submitted, approved or locked) */
CREATE OR REPLACE FUNCTION attendance.roster(p_register uuid)
RETURNS TABLE (member_ref uuid, name text, application_no text, exam_no text, combination_code text, class_name text, stream text)
LANGUAGE sql STABLE AS $fn$
    SELECT x.member_ref, x.name, x.application_no, x.exam_no, x.combination_code, x.class_name, x.stream FROM (
        SELECT a.id AS member_ref, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, '') AS name, a.application_no, a.exam_no,
               c.code AS combination_code, cl.name AS class_name, a.stream, a.surname AS s1, a.first_name AS s2
          FROM attendance.register r
          JOIN jupeb.application a ON a.session = r.session AND a.state IN ('STUDENT', 'COMPLETED')
          JOIN jupeb.subject_registration sr ON sr.application_id = a.id AND sr.subject_id = r.subject_ref
          LEFT JOIN jupeb.combination c ON c.id = a.combination_id
          LEFT JOIN jupeb.class cl ON cl.id = a.class_id
         WHERE r.id = p_register AND r.context = 'JUPEB' AND (r.class_ref IS NULL OR a.class_id = r.class_ref)
        UNION ALL
        -- V380: a course class: the students registered on it in its session and semester (the number in application_no,
        -- the programme in combination_code, the level in class_name)
        SELECT DISTINCT st.id, st.surname || ', ' || st.other_names, coalesce(st.matric_no, st.admission_no), NULL::text,
               st.programme_code, cr.level || ' Level', NULL::text, st.surname, st.other_names
          FROM attendance.register r
          JOIN registration.entry e ON e.offering_id = r.subject_ref AND e.status IN ('REGISTERED', 'APPROVED')
          JOIN registration.course_registration cr ON cr.id = e.registration_id AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
                                                  AND cr.session = r.session AND cr.semester = r.semester
          JOIN people.student st ON st.id = cr.student_id
         WHERE r.id = p_register AND r.context = 'COURSE') x
     ORDER BY x.s1, x.s2
$fn$;

-- ── 9 · what reads classes by course, session and semester names the stream ───────────────────────────────────
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
       AND o.stream = 'REGULAR'   -- V380: examination sessions are the full-time classes' until the CCE examination step
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = p_offering);
END $function$;
CREATE OR REPLACE FUNCTION assessment.import_legacy_semester(p_session text, p_semester integer, p_rows jsonb, p_with_results boolean)
 RETURNS TABLE(rows integer, students integer, offerings integer, registrations integer, results integer, no_student integer, held integer, no_course integer, no_mark integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_code text; v_units int; v_level int; v_ca int; v_exam int; v_total int; v_outcome text;
        v_student uuid; v_offering uuid; v_sheet uuid; v_reg uuid; v_have_mark boolean;
        n int := 0; n_off int := 0; n_reg int := 0; n_res int := 0; nns int := 0; n_held int := 0; nnc int := 0; nnm int := 0;
        ns int := 0; v_firsterr text := NULL;
        seen_students uuid[] := '{}'; seen_offerings uuid[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, course, units and the mark' USING ERRCODE = '23514';
    END IF;
    PERFORM assessment.ensure_session(p_session);

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', r->>'reg_no', '')));
        v_code := upper(btrim(coalesce(r->>'course', r->>'courseCode', r->>'course_code', r->>'code', '')));
        v_code := regexp_replace(v_code, '^([A-Z]{2,4})\s*([0-9]{3})$', '\1 \2');
        IF v_matric = '' OR v_code = '' THEN CONTINUE; END IF;
        n := n + 1;

        BEGIN   -- one savepoint per row: any unexpected error sets the row aside, the batch survives
            SELECT id INTO v_student FROM people.student WHERE upper(matric_no) = v_matric;
            IF v_student IS NULL THEN
                -- the student is not on the register yet: HOLD the result row, to be posted on reconcile
                IF p_with_results THEN
                    INSERT INTO assessment.legacy_result_holding (session, semester, matric, course_code, raw)
                    VALUES (p_session, p_semester, v_matric, v_code, r)
                    ON CONFLICT (session, semester, matric, course_code) DO UPDATE SET raw = EXCLUDED.raw, loaded_at = now();
                    n_held := n_held + 1;
                ELSE
                    nns := nns + 1;
                END IF;
                CONTINUE;
            END IF;

            IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN nnc := nnc + 1; CONTINUE; END IF;
            -- the unit is the course's, from the catalogue — the file's "Units" column is a status code, not a credit unit
            SELECT units, level INTO v_units, v_level FROM catalogue.course WHERE code = v_code;
            v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, v_level);

            SELECT id INTO v_offering FROM catalogue.offering WHERE course_code = v_code AND session = p_session AND semester = p_semester AND stream = 'REGULAR';
            IF v_offering IS NULL THEN
                v_offering := gen_random_uuid();
                INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (v_offering, v_code, p_session, p_semester);
            END IF;
            IF NOT (v_offering = ANY(seen_offerings)) THEN n_off := n_off + 1; seen_offerings := seen_offerings || v_offering; END IF;

            INSERT INTO people.enrolment (id, student_id, session, level)
            VALUES (gen_random_uuid(), v_student, p_session, v_level) ON CONFLICT (student_id, session) DO NOTHING;
            SELECT id INTO v_reg FROM registration.course_registration WHERE student_id = v_student AND session = p_session AND semester = p_semester;
            IF v_reg IS NULL THEN
                v_reg := gen_random_uuid();
                INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by)
                VALUES (v_reg, v_student, p_session, p_semester, v_level, 'APPROVED', now(), now(), v_actor);
                n_reg := n_reg + 1;
            END IF;
            INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
            VALUES (v_reg, v_offering, v_units, 'CURRENT', 'APPROVED')
            ON CONFLICT (registration_id, offering_id) DO UPDATE SET units = EXCLUDED.units, status = 'APPROVED';
            IF NOT (v_student = ANY(seen_students)) THEN seen_students := seen_students || v_student; END IF;

            IF NOT p_with_results THEN CONTINUE; END IF;

            v_ca := nullif(regexp_replace(coalesce(r->>'ca', r->>'CA', ''), '[^0-9]', '', 'g'), '')::int;
            v_exam := nullif(regexp_replace(coalesce(r->>'exam', r->>'EXAM', ''), '[^0-9]', '', 'g'), '')::int;
            v_total := nullif(regexp_replace(coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark', ''), '[^0-9]', '', 'g'), '')::int;
            v_outcome := upper(btrim(coalesce(r->>'outcome', 'GRADED')));
            IF v_outcome NOT IN ('GRADED','ABSENT','WITHHELD','INCOMPLETE','MALPRACTICE','EXEMPTED') THEN v_outcome := 'GRADED'; END IF;
            v_have_mark := (v_ca IS NOT NULL AND v_exam IS NOT NULL) OR v_total IS NOT NULL;
            IF v_outcome = 'GRADED' AND NOT v_have_mark THEN nnm := nnm + 1; CONTINUE; END IF;
            IF v_ca IS NOT NULL AND v_exam IS NULL AND v_total IS NULL THEN v_total := v_ca; v_ca := NULL; END IF;

            IF v_outcome = 'GRADED' AND (
                   (v_exam IS NOT NULL AND ((v_ca IS NULL OR v_ca < 0 OR v_ca > 40) OR (v_exam < 0 OR v_exam > 60)))
                OR (v_exam IS NULL AND (v_total IS NULL OR v_total < 0 OR v_total > 100))
               ) THEN
                nnm := nnm + 1; CONTINUE;
            END IF;

            SELECT id INTO v_sheet FROM assessment.score_sheet WHERE offering_id = v_offering;
            IF v_sheet IS NULL THEN
                v_sheet := gen_random_uuid();
                INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at)
                VALUES (v_sheet, v_offering, 'PUBLISHED', 'Migrated from the legacy portal', now());
            ELSIF (SELECT stage FROM assessment.score_sheet WHERE id = v_sheet) <> 'PUBLISHED' THEN
                UPDATE assessment.score_sheet SET stage = 'PUBLISHED', senate_minute = coalesce(senate_minute, 'Migrated from the legacy portal'),
                       published_at = coalesce(published_at, now()) WHERE id = v_sheet;
            END IF;
            INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, total, outcome, imported, reason)
            VALUES (v_sheet, v_student,
                    coalesce((SELECT max(version) + 1 FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student), 1),
                    CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_ca END,
                    CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_exam END,
                    CASE WHEN v_outcome = 'GRADED' AND v_exam IS NULL THEN v_total END,
                    v_outcome, true,
                    CASE WHEN (SELECT count(*) FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student) > 0
                         THEN 'Re-imported from the legacy portal' END);
            n_res := n_res + 1;
            -- the result is posted: clear any hold for this student/course
            DELETE FROM assessment.legacy_result_holding
             WHERE session = p_session AND semester = p_semester AND matric = v_matric AND course_code = v_code;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ' ' || v_code || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, cardinality(seen_students), n_off, n_reg, n_res, nns, n_held, nnc, nnm, ns, v_firsterr;
END $function$;
CREATE OR REPLACE FUNCTION catalogue.gst_offering_gaps(p_session text, p_office text)
 RETURNS TABLE(course_code text, title text, level integer, semester integer, office text, programmes bigint, levels text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT c.code, c.title, c.level, c.semester, c.general_office, count(DISTINCT co.programme_code),
           string_agg(DISTINCT co.level::text, ', ')
      FROM catalogue.course c
      JOIN catalogue.course_offer co ON co.course_code = c.code
      JOIN ref.programme p ON p.code = co.programme_code AND NOT coalesce(p.archived, false) AND p.category = 'UNDER GRADUATE'
     WHERE c.kind = 'GST' AND c.general_office IS NOT NULL AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
       AND (p_office IS NULL OR c.general_office = p_office)
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND o.session = p_session AND o.stream = 'REGULAR')
     GROUP BY c.code, c.title, c.level, c.semester, c.general_office
     ORDER BY c.general_office, c.level, c.code
$function$;
CREATE OR REPLACE FUNCTION catalogue.open_gst_offerings(p_session text, p_office text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_state text; n int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an offering is opened by a person' USING ERRCODE = '23514'; END IF;
    SELECT state INTO v_state FROM policy.academic_session WHERE name = p_session;
    IF NOT FOUND THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF v_state IN ('CLOSED', 'ARCHIVED', 'CANCELLED') THEN
        RAISE EXCEPTION 'GST_SESSION_CLOSED: % is %; its offerings are not opened now', p_session, lower(v_state) USING ERRCODE = '23514';
    END IF;
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), g.course_code, p_session, g.semester FROM catalogue.gst_offering_gaps(p_session, p_office) g
    ON CONFLICT (course_code, session, semester, stream) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $function$;
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
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NOT NULL AND o.stream = 'REGULAR'
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet s WHERE s.offering_id = o.id AND s.exam_session_id = p_id)
       AND (e.kind = 'MAIN'
            OR EXISTS (SELECT 1 FROM assessment.score_sheet ms
                         JOIN assessment.exam_session mes ON mes.id = ms.exam_session_id AND mes.kind = 'MAIN'
                        WHERE ms.offering_id = o.id AND ms.stage = 'PUBLISHED'));
    GET DIAGNOSTICS v_made = ROW_COUNT;
    SELECT count(*) INTO v_none FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NULL AND o.stream = 'REGULAR';
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
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NULL AND o.stream = 'REGULAR';
    UPDATE assessment.exam_session SET state = 'OPEN', opened_at = now() WHERE id = p_id;
    RETURN QUERY SELECT 0, v_none;
END;
$function$;
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
    res AS (SELECT f.student_id, f.course_code, f.session, f.semester, f.grade,
                   coalesce(f.stage = 'PUBLISHED' AND f.outcome = 'GRADED' AND f.points > 0, false) AS passed,
                   coalesce(f.stage = 'PUBLISHED' AND f.outcome = 'GRADED' AND f.points = 0, false) AS failed
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
CREATE OR REPLACE FUNCTION finance.gst_entitlement(p_student uuid, p_session text)
 RETURNS TABLE(required boolean, stated boolean, fee numeric, covers_eps boolean, paid numeric, entitled boolean, state text, reference text, receipt_no text, paid_at timestamp with time zone, open_reference text, open_amount numeric, open_expires_at timestamp with time zone, source text, channel text, legacy_reference text, gst_required boolean, eps_required boolean, reason text, gst_reason text, eps_reason text, review boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH f AS (SELECT * FROM finance.gst_fee_for(p_student, p_session)),
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    -- V367: a payment counts net of the refunds approved or paid against it (finance.refund.source_reference); refunded in full, it entitles no more
    pays AS (SELECT r.id, r.reference, r.receipt_no, r.amount - x.refunded AS amount, r.confirmed_at, r.channel
               FROM finance.payment_reference r
               CROSS JOIN LATERAL (SELECT finance.gst_refunded(r.reference) AS refunded) x
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                AND r.amount > x.refunded),
    agg AS (SELECT coalesce(sum(amount), 0) AS paid, max(confirmed_at) AS paid_at, count(*) AS n FROM pays),
    last AS (SELECT p.id, p.reference, p.receipt_no, p.channel FROM pays p ORDER BY p.confirmed_at DESC LIMIT 1),
    open AS (SELECT r.reference, r.amount, r.expires_at
               FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()
              ORDER BY r.generated_at DESC LIMIT 1),
    el AS (SELECT * FROM finance.gst_eps_eligibility(p_student, p_session)),
    -- whether this portal runs GST/EPS in the session at all: a payment no course requires is only questioned where it does
    run AS (SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.session = p_session AND o.stream = 'REGULAR') AS gst_run)
    SELECT el.required, f.stated, f.amount, cfg.covers_eps, agg.paid,
           -- a confirmed reference was generated for the fee as it stood: a later change of the fee does not unmake the payment
           (agg.n > 0 OR (f.stated AND f.amount = 0)) AS entitled,
           CASE WHEN agg.n > 0 THEN 'PAID'
                WHEN NOT el.required THEN 'NOT_REQUIRED'
                WHEN f.stated AND f.amount = 0 THEN 'EXEMPT'
                WHEN NOT f.stated THEN 'NOT_STATED'
                WHEN open.reference IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           last.reference, last.receipt_no, agg.paid_at, open.reference, open.amount, open.expires_at,
           CASE WHEN last.id IS NULL THEN NULL WHEN last.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           last.channel,
           (SELECT coalesce(lp.source_reference, lp.source_transaction_id) FROM finance.legacy_gst_reconciliation rc JOIN finance.legacy_gst_payment lp ON lp.id = rc.payment_id WHERE rc.payment_reference_id = last.id),
           el.gst_required, el.eps_required, el.reason, el.gst_reason, el.eps_reason,
           -- V367: until the Bursary decides it — kept, or refunded through the refund workflow
           (agg.n > 0 AND NOT el.required AND run.gst_run AND NOT finance.gst_review_settled(p_student, p_session))
      FROM f CROSS JOIN cfg CROSS JOIN agg CROSS JOIN el CROSS JOIN run LEFT JOIN last ON true LEFT JOIN open ON true
$function$;
CREATE OR REPLACE FUNCTION finance.gst_population(p_session text, p_semester integer)
 RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level integer, status text, entry_mode text, required boolean, fee numeric, stated boolean, paid numeric, entitled boolean, pay_state text, reference text, paid_at timestamp with time zone, gst_registered boolean, eps_registered boolean, gst_courses integer, eps_courses integer, registered_at timestamp with time zone, pay_source text, gst_required boolean, eps_required boolean, gst_reason text, eps_reason text, gst_carryover boolean, eps_carryover boolean, gst_completed boolean, eps_completed boolean, gst_owed text, eps_owed text, review boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH base AS (
        SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex,
               p.faculty_code, f.name AS faculty, p.dept_code, d.name AS department, s.programme_code, p.name AS programme,
               s.current_level AS level, s.status, s.entry_mode
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = d.faculty_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') AND s.entry_mode IS DISTINCT FROM 'CCE'),   -- V380
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    run AS (SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.session = p_session AND o.stream = 'REGULAR') AS gst_run),
    -- the engine over the whole register at once; a semester asked for narrows what is owed to the courses run in it
    eng AS (SELECT r.student_id, r.office, r.source, r.status, r.course_code,
                   (r.counts AND (p_semester IS NULL OR p_semester = ANY (r.semesters))) AS due
              FROM finance.gst_eps_rows(p_session, NULL) r),
    req AS (SELECT x.student_id,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'GST'), false) AS g_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'GST'), false) AS g_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'GST'), false) AS g_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'GST'), false) AS g_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'GST'), false) AS g_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'GST'), false) AS g_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'GST' AND x.due), false) AS g_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'GST' AND x.due) AS g_owed,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'EPS'), false) AS e_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'EPS'), false) AS e_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'EPS'), false) AS e_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'EPS'), false) AS e_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'EPS'), false) AS e_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'EPS'), false) AS e_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'EPS' AND x.due), false) AS e_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'EPS' AND x.due) AS e_owed
              FROM eng x GROUP BY x.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM finance.gst_fee f WHERE f.session = p_session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    -- V367: net of the refunds approved or paid against each payment; a payment refunded in full no longer counts
    refunded AS (SELECT rf.source_reference AS reference, sum(rf.amount) AS amount FROM finance.refund rf
                  WHERE rf.state IN ('APPROVED', 'PAID') AND rf.source_reference IS NOT NULL GROUP BY rf.source_reference),
    net AS (SELECT r.student_id, r.reference, r.channel, r.confirmed_at, r.amount - coalesce(x.amount, 0) AS amount
              FROM finance.payment_reference r LEFT JOIN refunded x ON x.reference = r.reference
             WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.amount > coalesce(x.amount, 0)),
    pays AS (SELECT r.student_id, sum(r.amount) AS paid, max(r.confirmed_at) AS paid_at, count(*) AS n,
                    (array_agg(r.reference ORDER BY r.confirmed_at DESC))[1] AS reference,
                    (array_agg(r.channel ORDER BY r.confirmed_at DESC))[1] AS channel
               FROM net r
              GROUP BY r.student_id),
    -- V367: a payment no course requires stays in review until the Bursary decides it
    undecided AS (SELECT DISTINCT r.student_id FROM net r
                   WHERE NOT EXISTS (SELECT 1 FROM finance.gst_payment_review d LEFT JOIN finance.refund rf ON rf.id = d.refund_id
                                      WHERE d.reference = r.reference AND (d.decision = 'KEEP' OR rf.state <> 'REJECTED'))),
    pend AS (SELECT DISTINCT r.student_id FROM finance.payment_reference r
              WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()),
    regs AS (SELECT cr.student_id,
                    count(*) FILTER (WHERE c.general_office = 'GST') AS gst_courses,
                    count(*) FILTER (WHERE c.general_office = 'EPS') AS eps_courses,
                    min(cr.submitted_at) AS registered_at
               FROM registration.course_registration cr
               JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
               JOIN catalogue.offering o ON o.id = e.offering_id
               JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
              WHERE cr.session = p_session AND (p_semester IS NULL OR cr.semester = p_semester)
              GROUP BY cr.student_id),
    j AS (SELECT b.*, coalesce(q.g_req, false) AS g_req, coalesce(q.e_req, false) AS e_req,
                 (coalesce(q.g_req, false) OR (coalesce(q.e_req, false) AND cfg.covers_eps)) AS req,
                 q.g_off, q.g_carry, q.g_reg, q.g_done, q.g_none, q.g_complete, q.g_owed,
                 q.e_off, q.e_carry, q.e_reg, q.e_done, q.e_none, q.e_complete, q.e_owed,
                 fr.id AS fee_id, fr.amount AS fee_amount, py.paid, py.paid_at, py.n, py.reference, py.channel, pd.student_id AS pending,
                 rg.gst_courses, rg.eps_courses, rg.registered_at, run.gst_run AS run_on, (ud.student_id IS NOT NULL) AS undecided
            FROM base b
            CROSS JOIN cfg CROSS JOIN run
            LEFT JOIN req q ON q.student_id = b.id
            LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                                WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                                  AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                                ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                                LIMIT 1) fr ON true
            LEFT JOIN pays py ON py.student_id = b.id
            LEFT JOIN pend pd ON pd.student_id = b.id
            LEFT JOIN regs rg ON rg.student_id = b.id
            LEFT JOIN undecided ud ON ud.student_id = b.id)
    SELECT j.id, j.number, j.surname, j.other_names, j.sex, j.faculty_code, j.faculty, j.dept_code, j.department, j.programme_code, j.programme,
           j.level, j.status, j.entry_mode,
           j.req,
           coalesce(j.fee_amount, 0), (j.fee_id IS NOT NULL),
           coalesce(j.paid, 0),
           (coalesce(j.n, 0) > 0 OR (j.fee_id IS NOT NULL AND j.fee_amount = 0)),
           CASE WHEN coalesce(j.n, 0) > 0 THEN 'PAID'
                WHEN NOT j.req THEN 'NOT_REQUIRED'
                WHEN j.fee_id IS NOT NULL AND j.fee_amount = 0 THEN 'EXEMPT'
                WHEN j.fee_id IS NULL THEN 'NOT_STATED'
                WHEN j.pending IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           j.reference, j.paid_at,
           coalesce(j.gst_courses, 0) > 0, coalesce(j.eps_courses, 0) > 0, coalesce(j.gst_courses, 0)::int, coalesce(j.eps_courses, 0)::int, j.registered_at,
           CASE WHEN j.n IS NULL THEN NULL WHEN j.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           j.g_req, j.e_req,
           finance.gst_eps_reason('GST', coalesce(j.g_off, false), coalesce(j.g_carry, false), coalesce(j.g_reg, false), coalesce(j.g_done, false), coalesce(j.g_none, false)),
           finance.gst_eps_reason('EPS', coalesce(j.e_off, false), coalesce(j.e_carry, false), coalesce(j.e_reg, false), coalesce(j.e_done, false), coalesce(j.e_none, false)),
           coalesce(j.g_carry, false), coalesce(j.e_carry, false), coalesce(j.g_complete, false), coalesce(j.e_complete, false),
           j.g_owed, j.e_owed,
           (coalesce(j.n, 0) > 0 AND NOT j.req AND j.run_on AND j.undecided)
      FROM j
$function$;
CREATE OR REPLACE FUNCTION finance.gst_course_stats(p_session text, p_semester integer, p_office text)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, level integer, semester integer, general_office text, dept_code text, department text, lecturer_id uuid, lecturer text, state text, registered bigint, entitled bigint, sheet_id uuid, stage text, graded bigint, published_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    WITH pays AS (SELECT DISTINCT r.student_id FROM finance.payment_reference r
                   WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL)
    SELECT o.id, c.code, c.title, c.units, c.level, o.semester, c.general_office, c.dept_code, d.name, o.lecturer_id,
           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END, c.state,
           (SELECT count(*) FROM registration.entry e WHERE e.offering_id = o.id AND e.status <> 'DROPPED'),
           (SELECT count(*) FROM registration.entry e JOIN registration.course_registration cr ON cr.id = e.registration_id
              JOIN pays py ON py.student_id = cr.student_id WHERE e.offering_id = o.id AND e.status <> 'DROPPED'),
           sh.id, sh.stage,
           CASE WHEN sh.id IS NULL THEN 0 ELSE (SELECT count(*) FROM assessment.latest_scores(sh.id) WHERE outcome = 'GRADED') END,
           sh.published_at
      FROM catalogue.offering o
      JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
      JOIN ref.department d ON d.code = c.dept_code
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
      LEFT JOIN assessment.score_sheet sh ON sh.offering_id = o.id
     WHERE o.session = p_session AND o.stream = 'REGULAR' AND (p_semester IS NULL OR o.semester = p_semester) AND (p_office IS NULL OR c.general_office = p_office)
     ORDER BY o.semester, c.level, c.code
$function$;
CREATE OR REPLACE FUNCTION policy.archive_session(p_name text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; st text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'SESSION_ARCHIVE_REFUSED: a session is archived by a person' USING ERRCODE = '23514'; END IF;
    SELECT state INTO st FROM policy.academic_session WHERE name = p_name FOR UPDATE;
    IF st IS NULL THEN RAISE EXCEPTION 'SESSION_ARCHIVE_REFUSED: no session named % is on the calendar', p_name USING ERRCODE = '23514'; END IF;
    IF st = 'ARCHIVED' THEN RETURN; END IF;
    IF st <> 'CLOSED' THEN
        RAISE EXCEPTION 'SESSION_ARCHIVE_REFUSED: % is % and only a completed session is archived', p_name, lower(policy.session_label(st)) USING ERRCODE = '23514';
    END IF;
    -- V380: a session a route still studies in (the CCE session) is not archived under it
    IF EXISTS (SELECT 1 FROM policy.study_route r WHERE policy.route_session(r.code) = p_name) THEN
        RAISE EXCEPTION 'SESSION_ARCHIVE_REFUSED: the Centre for Continuing Education still studies in % (the CCE session); archive it once the CCE session has moved on', p_name USING ERRCODE = '23514';
    END IF;
    UPDATE policy.academic_session SET state = 'ARCHIVED', archived_at = now() WHERE name = p_name;
    UPDATE policy.semester SET state = 'ARCHIVED' WHERE session = p_name AND state = 'CLOSED';
END $function$;

-- ── 10 · the fee structure, replaced by its own kind ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.import_fee_structure(p_session text, p_rows jsonb)
 RETURNS TABLE(rows integer, lines integer, faculties integer, no_faculty integer, no_programme integer, no_group integer, spillover integer, programmes integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_fac text; v_fac_code text; v_level int; v_mode text; v_sem int; v_ind text; v_amt numeric; v_item text; v_ord int;
        v_spill boolean; v_prog text; v_prog_code text; v_grp text; v_grp_code text; v_kind text; v_cce boolean; v_full boolean;
        n int := 0; nl int := 0; nnf int := 0; nnp int := 0; nng int := 0; nsp int := 0; facs text[] := '{}'; progs text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a fees structure is uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: faculty or programme, level, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    -- replace the session's approved structure: end what stands, then load the new. V380: only the lines of the upload's own
    -- kind — a CCE (part-time) structure replaces the CCE lines, a full-time structure every other line — so the CCE fees of a
    -- session and the full-time fees of the same session never end each other
    v_cce := EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE upper(btrim(coalesce(x->>'entryMode', x->>'entry_mode', ''))) = 'CCE');
    v_full := EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE upper(btrim(coalesce(x->>'entryMode', x->>'entry_mode', ''))) <> 'CCE');
    UPDATE finance.fee_schedule SET ended_at = now()
     WHERE session = p_session AND ended_at IS NULL
       AND ((v_cce AND entry_mode = 'CCE') OR (v_full AND entry_mode IS DISTINCT FROM 'CCE'));
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amt IS NULL OR v_amt < 0 THEN CONTINUE; END IF;
        n := n + 1;

        -- the faculty, by code or name
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', ''));
        v_fac_code := NULL;
        IF v_fac <> '' THEN
            SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(code) = upper(v_fac);
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) = upper(v_fac) LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) LIKE '%' || upper(v_fac) || '%' LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN nnf := nnf + 1; END IF;
        END IF;

        -- the programme, by code or name: the line is that programme's alone
        v_prog := btrim(coalesce(r->>'programmeCode', r->>'programme_code', r->>'programme', r->>'program', ''));
        v_prog_code := NULL;
        IF v_prog <> '' THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
            IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived LIMIT 1; END IF;
            IF v_prog_code IS NULL THEN nnp := nnp + 1; END IF;
            -- a programme names its faculty; the faculty column is not needed beside it
            IF v_prog_code IS NOT NULL AND v_fac_code IS NULL THEN SELECT faculty_code INTO v_fac_code FROM ref.programme WHERE code = v_prog_code; END IF;
        END IF;

        -- the fee group, by code or name
        v_grp := btrim(coalesce(r->>'feeGroup', r->>'fee_group', r->>'group', ''));
        v_grp_code := NULL;
        IF v_grp <> '' THEN
            SELECT code INTO v_grp_code FROM ref.fee_group WHERE upper(code) = upper(v_grp);
            IF v_grp_code IS NULL THEN SELECT code INTO v_grp_code FROM ref.fee_group WHERE upper(name) = upper(v_grp) LIMIT 1; END IF;
            IF v_grp_code IS NULL THEN nng := nng + 1; END IF;
        END IF;

        v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_level IS NOT NULL AND v_level NOT IN (100,200,300,400,500,600,700,800,900) THEN v_level := NULL; END IF;
        v_mode := nullif(upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', ''))), '');
        IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH','CCE') THEN v_mode := NULL; END IF;
        v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_sem IS NOT NULL AND v_sem NOT IN (1,2,3) THEN v_sem := NULL; END IF;
        v_ind := upper(btrim(coalesce(r->>'indigene', '')));
        v_ind := CASE WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' ELSE NULL END;
        v_spill := lower(btrim(coalesce(r->>'spillover', 'false'))) IN ('true', 't', '1', 'yes', 'y', 'spillover', 'spill');
        IF v_spill THEN v_level := NULL; nsp := nsp + 1; END IF;   -- a spillover line is level-agnostic (V088)
        v_kind := upper(regexp_replace(btrim(coalesce(r->>'kind', r->>'type', '')), '[^A-Za-z]', '', 'g'));
        v_kind := CASE WHEN v_kind LIKE 'LATEPAY%' THEN 'LATE_PAYMENT' WHEN v_kind LIKE 'LATEREG%' THEN 'LATE_REGISTRATION' ELSE 'FEE' END;
        v_item := nullif(btrim(coalesce(r->>'item', '')), '');
        IF v_item IS NULL THEN
            v_item := CASE v_kind WHEN 'LATE_PAYMENT' THEN 'Late payment fee' WHEN 'LATE_REGISTRATION' THEN 'Late registration fee'
                                  ELSE CASE WHEN v_spill THEN 'School fees (spillover)' ELSE 'School fees' END END
                      || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END;
        END IF;
        v_ord := coalesce(nullif(regexp_replace(coalesce(r->>'ord', r->>'order', ''), '[^0-9]', '', 'g'), '')::int,
                          coalesce(v_sem, 1) + CASE WHEN v_spill THEN 100 ELSE 0 END);

        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, indigene, ord, spillover, kind)
        VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac_code, v_prog_code, v_grp_code, v_sem, v_ind, v_ord, v_spill, v_kind);
        nl := nl + 1;
        IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY(facs)) THEN facs := facs || v_fac_code; END IF;
        IF v_prog_code IS NOT NULL AND NOT (v_prog_code = ANY(progs)) THEN progs := progs || v_prog_code; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nl, cardinality(facs), nnf, nnp, nng, nsp, cardinality(progs);
END $function$;

COMMENT ON FUNCTION catalogue.cce_open_classes(text, integer) IS
  'V380: the Centre opens a semester''s CCE classes at once — each course its CCE programmes offer in the semester, and each carry-over its students owe from it — in the CCE session or the one after it.';
COMMENT ON FUNCTION attendance.course_summary(uuid, text) IS
  'V380: a student''s attendance on each of their classes in a session, by the register (present, absent, late, excused), against the class''s attendance policy.';

COMMIT;
