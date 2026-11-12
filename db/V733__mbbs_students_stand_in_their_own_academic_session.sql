-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V733 · MBBS students stand in their own academic session
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's master prompt of 12 November 2026, part A: MBBS students' "academic progression and session calendar operate one
--  academic session behind the general university academic calendar … allow eligible MBBS students to select and update their
--  academic session from their Student Dashboard without being forced to follow the general university current session … must apply
--  specifically to MBBS students and must not change the academic session of other programmes".
--
--  Inspected first: a student's session is decided in two places — people.student_current_session (the database's; CCE students
--  the Centre's route session, postgraduate students the School's, everyone else the University's CURRENT session) and the API's
--  StudentPortalService.sessionOf, which every /me page opens on. Nothing per student or per programme existed; the only "behind the
--  University" mechanism was the CCE route's offset, keyed by entry mode. Four readers decided "the student's session" with the
--  University's own: the registration gate (the University's semester state of the session asked for: a past session's semesters are
--  CLOSED), the cohort engine (people.academic_position_rows_of: registered this session, the final year, elapsed sessions), the past-
--  session fee account (finance.historical_rows_read: every session before the University's current one is past), and the GST/EPS
--  rows (the level a session reads a student at). On the late-October copy of live the lag is real but not uniform: of the 2023/2024
--  MBBS entrants 95% paid 2024/2025 fees and 5% paid 2025/2026 (85% across the University); 200 and 400 Level pay in the current one.
--  So the session is the student's to state, within rules, not one offset for the programme.
--
--  Now:
--    college.programme_rule.sessions_behind_max — how many sessions behind the University a programme's students may stand (1: "one
--      academic session behind"); a programme the College runs (college.runs_programme: MBBS today) is the only one with the choice.
--    people.study_session — a student's own session (one row a student, absent = the University's), and people.study_session_event,
--      every change written once: matriculation number, programme, previous and new session, level, when, by whom and as which office,
--      how it stood (NOT_REQUIRED: the student's own choice within the rules; SET_BY_OFFICE: an office's, with its reason; ROLL_OVER).
--    people.study_session_options — the sessions a student may choose and why each other is not: approved sessions only — on the
--      calendar, CURRENT or CLOSED, never PLANNED or later than the University's current session, never cancelled, never before the
--      entry session, at most the programme's sessions_behind_max behind; never behind the latest session the student registered
--      courses in; and while the student's current level is registered in one session, that session alone for the level (a second
--      session for the same level would let the level be registered twice — a repeated year is the College's or the Academic Office's
--      to set).
--    people.choose_study_session (the student, confirmed) and people.set_study_session (the Academic Office, the Registry, the
--      Provost, the College Secretary, the MBBS Coordinator: any approved session, or back to the University's, with a reason).
--      Neither changes the level, a registration, a result or a payment; each marks the student's past-session fee account to be read
--      again and recomputes their academic position.
--    people.student_current_session, people.academic_context, the registration gate (a College semester of the student's session
--      and level opens it: college.semester), the cohort engine, the past-session fee account, the GST/EPS rows and the results
--      statement's current semester read the student's own session where there is one; add/drop follows the College's semester too.
--    The session roll-over moves every student in a session of their own one session on from it — never into the target, the
--      University's next — once a target (a re-run moves nobody twice), promoting the level as the University's roll-over would
--      (counted to the target), else holding it; both recorded (ROLL_OVER).
--    A change of programme or entry mode off the College's calendar ends the session of one's own (recorded); an office may always
--      send a student back to the University's session, whatever their record now is.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V733: MBBS students stand in their own academic session', true);

-- ── 1 · the rule, the record and its history ────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE college.programme_rule ADD COLUMN sessions_behind_max smallint NOT NULL DEFAULT 1
    CONSTRAINT ck_programme_rule_sessions_behind CHECK (sessions_behind_max BETWEEN 0 AND 3);
COMMENT ON COLUMN college.programme_rule.sessions_behind_max IS
  'V733: how many sessions behind the University''s current session a student of the programme may stand in their own session (people.study_session); 0 keeps them on the University''s.';

CREATE TABLE people.study_session (
    student_id   uuid PRIMARY KEY REFERENCES people.student(id) ON DELETE CASCADE,
    session      text NOT NULL REFERENCES policy.academic_session(name),
    level        integer NOT NULL,
    set_at       timestamptz NOT NULL DEFAULT now(),
    set_by       uuid NOT NULL,
    set_office   text NOT NULL,
    approval     text NOT NULL CHECK (approval IN ('NOT_REQUIRED', 'SET_BY_OFFICE', 'ROLL_OVER')),
    reason       text
);
COMMENT ON TABLE people.study_session IS
  'V733: the academic session a student of a College-run programme (MBBS) stands in, where it is not the University''s current session — read by people.student_current_session and every reader of a student''s session. One row a student; none = the University''s.';
SELECT audit.attach('people.study_session');

CREATE TABLE people.study_session_event (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    matric_no     text,
    programme_code text,
    from_session  text,             -- NULL: the University's session
    to_session    text,             -- NULL: back to the University's session
    level         integer,
    at            timestamptz NOT NULL DEFAULT clock_timestamp(),   -- the moment, so changes within one act read in their order
    by_person     uuid,
    office        text,
    approval      text NOT NULL CHECK (approval IN ('NOT_REQUIRED', 'SET_BY_OFFICE', 'ROLL_OVER')),
    reason        text,
    roll_over_to  text              -- the target of the session roll-over that made the change (a re-run moves nobody twice)
);
CREATE INDEX ix_study_session_event_student ON people.study_session_event (student_id, at);
CREATE INDEX ix_study_session_event_at ON people.study_session_event (at DESC);
COMMENT ON TABLE people.study_session_event IS
  'V733: every change of a student''s own academic session, written once — the matriculation number, programme, previous and new session, the level, when, by whom and as which office, and how it stood (the student''s choice within the rules, an office''s with its reason, the session roll-over).';
SELECT audit.attach('people.study_session_event');

CREATE FUNCTION people.study_session_event_kept() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 THEN RETURN OLD; END IF;   -- the student's record removed takes it with it
    RAISE EXCEPTION 'STUDY_SESSION_EVENT_KEPT: a change of a student''s session is written once and kept' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_study_session_event_kept BEFORE UPDATE OR DELETE ON people.study_session_event
    FOR EACH ROW EXECUTE FUNCTION people.study_session_event_kept();

/* a student's own session, or NULL (the University's) */
CREATE FUNCTION people.own_session(p_student uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT session FROM people.study_session WHERE student_id = p_student;
$$;

-- ── 2 · the sessions a student may stand in ─────────────────────────────────────────────────────────────────────────────────────
/* whether the student may hold a session of their own: a student of a programme the College runs, regular (not CCE or postgraduate),
   ACTIVE or on PROBATION; NULL when they may, else the reason */
CREATE FUNCTION people.study_session_refusal(p_student uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN s.id IS NULL THEN 'NO_STUDENT'
        WHEN NOT college.runs_programme(s.programme_code) THEN 'NOT_COLLEGE_PROGRAMME'
        WHEN s.entry_mode IN ('CCE', 'POSTGRADUATE') THEN 'OWN_CALENDAR'
        WHEN s.status NOT IN ('ACTIVE', 'PROBATION') THEN 'NOT_STUDYING'
        WHEN s.entry_session IS NULL THEN 'NO_ENTRY_SESSION'
    END
      FROM (SELECT 1) one LEFT JOIN people.student s ON s.id = p_student;
$$;

CREATE FUNCTION people.study_session_options(p_student uuid)
RETURNS TABLE(session text, state text, starts_on date, is_university boolean, is_own boolean, selectable boolean, why text)
LANGUAGE sql STABLE AS $$
    WITH st AS (SELECT s.id, s.entry_session, s.current_level, s.programme_code,
                       coalesce((SELECT r.sessions_behind_max FROM college.programme_rule r WHERE r.programme_code = s.programme_code), 0) AS behind
                  FROM people.student s WHERE s.id = p_student),
         uni AS (SELECT a.name, a.starts_on FROM policy.academic_session a WHERE a.name = policy.university_current_session()),
         floor AS (SELECT policy.session_before(u.name, st.behind) AS name FROM uni u CROSS JOIN st),
         reg AS (SELECT max(r.session) AS latest,
                        max(r.session) FILTER (WHERE r.level = st.current_level) AS at_level,
                        count(DISTINCT r.session) FILTER (WHERE r.level = st.current_level) AS level_sessions
                   FROM registration.course_registration r JOIN st ON st.id = r.student_id
                  WHERE r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
         own AS (SELECT people.own_session(p_student) AS name)
    SELECT a.name, a.state, a.starts_on, a.name = u.name, a.name = coalesce(o.name, u.name),
           w.why IS NULL, w.why
      FROM policy.academic_session a
      CROSS JOIN uni u CROSS JOIN st CROSS JOIN floor f CROSS JOIN reg g CROSS JOIN own o
      CROSS JOIN LATERAL (SELECT CASE
            WHEN a.name < st.entry_session THEN 'BEFORE_ENTRY'
            WHEN f.name IS NOT NULL AND a.name < f.name THEN 'TOO_FAR_BEHIND'
            WHEN g.latest IS NOT NULL AND a.name < g.latest THEN 'BEHIND_YOUR_REGISTRATION'
            WHEN g.at_level IS NOT NULL AND a.name <> g.at_level THEN 'LEVEL_REGISTERED_ELSEWHERE'
            WHEN EXISTS (SELECT 1 FROM registration.course_registration r2
                          WHERE r2.student_id = st.id AND r2.session = a.name AND r2.level <> st.current_level
                            AND r2.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN 'REGISTERED_AT_ANOTHER_LEVEL'
        END AS why) w
     WHERE (a.state IN ('CURRENT', 'CLOSED') OR a.name = u.name)   -- the University's own session whatever its state (between sessions, a planned one)
       AND a.merged_into IS NULL
       AND a.starts_on <= u.starts_on
       AND a.name >= coalesce(least(st.entry_session, f.name, o.name), st.entry_session)
     ORDER BY a.starts_on DESC;
$$;
COMMENT ON FUNCTION people.study_session_options(uuid) IS
  'V733: the sessions a student of a College-run programme may stand in — the University''s current session and CURRENT or CLOSED sessions before it on the calendar, never cancelled or merged, never before the entry session, at most the programme''s sessions_behind_max behind — each selectable or with the reason it is not: BEFORE_ENTRY, TOO_FAR_BEHIND, BEHIND_YOUR_REGISTRATION (earlier than the latest session registered in), LEVEL_REGISTERED_ELSEWHERE (the current level is registered in another session), REGISTERED_AT_ANOTHER_LEVEL (the session holds the student''s registration of another level).';

-- ── 3 · a change, the student's own or an office's ──────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.study_session_apply(p_student uuid, p_session text, p_approval text, p_reason text, p_roll_over_to text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        s people.student; v_prev text; v_uni text := policy.university_current_session();
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    v_prev := people.own_session(p_student);
    IF p_session IS NULL THEN
        DELETE FROM people.study_session WHERE student_id = p_student;
    ELSE
        INSERT INTO people.study_session (student_id, session, level, set_at, set_by, set_office, approval, reason)
        VALUES (p_student, p_session, s.current_level, now(), who, v_office, p_approval, nullif(btrim(p_reason), ''))
        ON CONFLICT (student_id) DO UPDATE SET session = EXCLUDED.session, level = EXCLUDED.level, set_at = EXCLUDED.set_at,
               set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office, approval = EXCLUDED.approval, reason = EXCLUDED.reason;
    END IF;
    INSERT INTO people.study_session_event (student_id, matric_no, programme_code, from_session, to_session, level, by_person, office, approval, reason, roll_over_to)
    VALUES (p_student, s.matric_no, s.programme_code, v_prev, p_session, s.current_level, who, v_office, p_approval, nullif(btrim(p_reason), ''), p_roll_over_to);
    -- the readers that keep a student's session read again: the past-session fee account and the academic position
    INSERT INTO finance.historical_stale (student_id) VALUES (p_student) ON CONFLICT (student_id) DO UPDATE SET marked_at = now();
    PERFORM people.refresh_academic_positions(ARRAY[p_student]);
    RETURN jsonb_build_object('student', p_student, 'previous', coalesce(v_prev, v_uni), 'previousOwn', v_prev IS NOT NULL,
                              'session', coalesce(p_session, v_uni), 'own', p_session IS NOT NULL, 'level', s.current_level,
                              'university', v_uni);
END $$;

/* the student's own choice, confirmed: an approved session only (people.study_session_options) */
CREATE FUNCTION people.choose_study_session(p_student uuid, p_session text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_refusal text := people.study_session_refusal(p_student); o record;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a session is chosen by a person' USING ERRCODE = '23514';
    END IF;
    IF v_refusal IS NOT NULL THEN
        RAISE EXCEPTION 'STUDY_SESSION_NOT_YOURS: %', CASE v_refusal
            WHEN 'NOT_COLLEGE_PROGRAMME' THEN 'only a student of a programme the College runs on its own calendar (MBBS) chooses a session; every other student stands in the University''s'
            WHEN 'OWN_CALENDAR' THEN 'a CCE or postgraduate student stands in the session of their own calendar'
            WHEN 'NOT_STUDYING' THEN 'a session is chosen by a student who is studying (active or on probation)'
            ELSE 'no session can be chosen for this record' END USING ERRCODE = '23514';
    END IF;
    SELECT * INTO o FROM people.study_session_options(p_student) x WHERE x.session = p_session;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'STUDY_SESSION_NOT_APPROVED: % is not a session you may stand in', coalesce(p_session, 'that') USING ERRCODE = '23514',
            HINT = 'Choose one of the sessions offered: on the calendar, not later than the University''s current session, not before your entry session.';
    END IF;
    IF o.is_own THEN
        RAISE EXCEPTION 'STUDY_SESSION_UNCHANGED: you already stand in %', p_session USING ERRCODE = '23514';
    END IF;
    IF NOT o.selectable THEN
        RAISE EXCEPTION 'STUDY_SESSION_REFUSED: %', CASE o.why
            WHEN 'BEFORE_ENTRY' THEN p_session || ' is before your entry session'
            WHEN 'TOO_FAR_BEHIND' THEN p_session || ' is further behind the University''s session than your programme allows'
            WHEN 'BEHIND_YOUR_REGISTRATION' THEN 'you have registered courses in a later session than ' || p_session
            WHEN 'LEVEL_REGISTERED_ELSEWHERE' THEN 'your present level is registered in another session; a second session for the same level would register it twice'
            WHEN 'REGISTERED_AT_ANOTHER_LEVEL' THEN 'you registered another level in ' || p_session
            ELSE p_session || ' cannot be chosen' END USING ERRCODE = '23514',
            HINT = 'The College or the Academic Office sets a session the rules do not allow — a repeated year, for instance.';
    END IF;
    -- the University's own session chosen: no session of one's own (the row goes, the change is recorded)
    RETURN people.study_session_apply(p_student, CASE WHEN o.is_university THEN NULL ELSE p_session END, 'NOT_REQUIRED', NULL);
END $$;
COMMENT ON FUNCTION people.choose_study_session(uuid, text) IS
  'V733: the student''s own choice of session, confirmed on the dashboard — an approved session (people.study_session_options) only; the University''s current session chosen ends the session of one''s own. The level, registrations, results and payments are untouched.';

/* an office's: any approved session (the calendar's rules; not the student's registration rules), or back to the University's, with
   the reason */
CREATE FUNCTION people.set_study_session(p_student uuid, p_session text, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_refusal text := people.study_session_refusal(p_student); o record;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a session is set by a person' USING ERRCODE = '23514';
    END IF;
    IF v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'provost', 'collegesecretary', 'mbbscoordinator', 'super') THEN
        RAISE EXCEPTION 'STUDY_SESSION_OFFICE: a student''s session is set by the Academic Office, the Registry or the College' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'STUDY_SESSION_REASON: a session set for a student says why (ten characters or more)' USING ERRCODE = '23514';
    END IF;
    -- back to the University's session is always open to an office (a student who left the programme); a session only to the eligible
    IF v_refusal IS NOT NULL AND p_session IS NOT NULL THEN
        RAISE EXCEPTION 'STUDY_SESSION_NOT_YOURS: this student does not stand in a session of their own (%)', v_refusal USING ERRCODE = '23514';
    END IF;
    IF p_session IS NOT NULL THEN
        SELECT * INTO o FROM people.study_session_options(p_student) x WHERE x.session = p_session;
        IF NOT FOUND OR o.why IN ('BEFORE_ENTRY', 'TOO_FAR_BEHIND') THEN
            RAISE EXCEPTION 'STUDY_SESSION_NOT_APPROVED: % is not an approved session for this student', p_session USING ERRCODE = '23514',
                HINT = 'On the calendar, not later than the University''s current session, not before the entry session, within the programme''s allowance.';
        END IF;
        IF o.is_university THEN p_session := NULL; END IF;
    END IF;
    IF p_session IS NOT DISTINCT FROM people.own_session(p_student) THEN
        RAISE EXCEPTION 'STUDY_SESSION_UNCHANGED: the student already stands in %', coalesce(p_session, 'the University''s session') USING ERRCODE = '23514';
    END IF;
    RETURN people.study_session_apply(p_student, p_session, 'SET_BY_OFFICE', p_reason);
END $$;
COMMENT ON FUNCTION people.set_study_session(uuid, text, text) IS
  'V733: an office sets a student''s own session — the Academic Office, the Registry, the Provost, the College Secretary, the MBBS Coordinator — any approved session on the calendar''s rules (a repeated year included), or NULL for the University''s, with a reason of ten characters or more.';

/* a student whose programme or entry mode takes them off the College's calendar (an inter-departmental transfer, a programme swap)
   stands in the University's session again: the session of their own ends, recorded */
CREATE FUNCTION people.study_session_end_on_programme() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM people.study_session WHERE student_id = NEW.id)
       AND people.study_session_refusal(NEW.id) IN ('NOT_COLLEGE_PROGRAMME', 'OWN_CALENDAR') THEN
        PERFORM people.study_session_apply(NEW.id, NULL, 'SET_BY_OFFICE',
            'Programme changed to ' || coalesce(NEW.programme_code, '?') || ': back to the University''s session');
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_study_session_end_on_programme AFTER UPDATE OF programme_code, entry_mode ON people.student
    FOR EACH ROW WHEN (OLD.programme_code IS DISTINCT FROM NEW.programme_code OR OLD.entry_mode IS DISTINCT FROM NEW.entry_mode)
    EXECUTE FUNCTION people.study_session_end_on_programme();

-- ── 4 · the readers of a student's session ──────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.student_current_session(p_student uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce(people.own_session(p_student),   -- V733: an MBBS student's own session
                    CASE people.student_stream(p_student)
                         WHEN 'CCE' THEN policy.route_session('CCE')
                         WHEN 'PG' THEN admissions.pg_current_session()
                         ELSE (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1) END)
$function$;


/* V733: the College's semester of a session for a student standing in it as their own session, behind the University's — the
   semester of that session and the student's level the College has stated (college.semester); no row otherwise */
CREATE FUNCTION registration.college_semester(p_student uuid, p_session text, p_semester integer)
RETURNS TABLE(ordinal integer, starts_on date, ends_on date) LANGUAGE sql STABLE AS $$
    SELECT c.ordinal, c.starts_on, c.ends_on
      FROM people.study_session ss
      JOIN people.student s ON s.id = ss.student_id
      JOIN college.semester c ON c.session = ss.session AND c.level = s.current_level AND c.ordinal = p_semester
     WHERE ss.student_id = p_student AND ss.session = p_session
       AND p_session IS DISTINCT FROM policy.university_current_session();
$$;
COMMENT ON FUNCTION registration.college_semester(uuid, text, integer) IS
  'V733: the College''s semester (college.semester) of a student''s own session and level, when they stand in a session behind the University''s — it opens and closes their registration in that session in place of the University''s semester, which is closed.';

CREATE OR REPLACE FUNCTION registration.open_semester(p_student uuid, p_session text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE people.student_stream(p_student)
                WHEN 'CCE' THEN coalesce((SELECT max(rs.number) FROM policy.route_semester rs WHERE rs.route = 'CCE' AND rs.session = p_session AND rs.state = 'OPEN'), 1)
                WHEN 'PG' THEN coalesce((SELECT max(ps.number) FROM admissions.pg_semester ps WHERE ps.session = p_session AND ps.state = 'OPEN'), 1)
                -- V733: a session of one's own behind the University's: the College's latest semester of it begun for the student's level
                ELSE coalesce((SELECT max(c.ordinal) FROM people.study_session ss JOIN people.student s ON s.id = ss.student_id
                                 JOIN college.semester c ON c.session = ss.session AND c.level = s.current_level AND c.starts_on <= current_date
                                WHERE ss.student_id = p_student AND ss.session = p_session AND p_session IS DISTINCT FROM policy.university_current_session()),
                              (SELECT max(sm.number) FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'), 1) END
$function$;

CREATE OR REPLACE FUNCTION registration.calendar_semester(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(state text, registration_opens date, registration_closes date, late_registration_closes date, fresh_registration_from date, lectures_from date, lectures_to date, calendar text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT rs.state, rs.registration_opens, rs.registration_closes, rs.late_registration_closes, NULL::date, rs.lectures_from, rs.lectures_to, 'CCE'
      FROM policy.route_semester rs
     WHERE people.student_stream(p_student) = 'CCE' AND rs.route = 'CCE' AND rs.session = p_session AND rs.number = p_semester
    UNION ALL
    -- V389: the School of Postgraduate Studies' semester
    SELECT ps.state, ps.registration_opens, ps.registration_closes, ps.registration_closes, NULL::date, ps.lectures_from, ps.lectures_to, 'PG'
      FROM admissions.pg_semester ps
     WHERE people.student_stream(p_student) = 'PG' AND ps.session = p_session AND ps.number = p_semester
    UNION ALL
    -- V733: a session of one's own behind the University's: the College's semester of it for the student's level
    SELECT CASE WHEN c.starts_on IS NULL OR current_date < c.starts_on THEN 'NOT_YET_OPEN'
                WHEN c.ends_on IS NOT NULL AND current_date > c.ends_on THEN 'CLOSED' ELSE 'OPEN' END,
           c.starts_on, c.ends_on, c.ends_on, NULL::date, c.starts_on, c.ends_on, 'COLLEGE'
      FROM registration.college_semester(p_student, p_session, p_semester) c
     WHERE people.student_stream(p_student) = 'REGULAR'
    UNION ALL
    SELECT sm.state, sm.registration_opens, sm.registration_closes, sm.late_registration_closes, sm.fresh_registration_from, sm.lectures_from, sm.lectures_to, 'FULL_TIME'
      FROM policy.semester sm
     WHERE people.student_stream(p_student) = 'REGULAR' AND sm.session = p_session AND sm.number = p_semester
       AND NOT EXISTS (SELECT 1 FROM registration.college_semester(p_student, p_session, p_semester))
$function$;

CREATE OR REPLACE FUNCTION registration.add_drop_open(p_student uuid, p_session text, p_semester integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE people.student_stream(p_student)
                WHEN 'CCE' THEN EXISTS (SELECT 1 FROM policy.route_semester rs
                                         WHERE rs.route = 'CCE' AND rs.session = p_session AND rs.number = p_semester AND rs.state = 'OPEN'
                                           AND current_date <= coalesce(rs.late_registration_closes, rs.registration_closes, current_date))
                WHEN 'PG' THEN EXISTS (SELECT 1 FROM admissions.pg_semester ps
                                        WHERE ps.session = p_session AND ps.number = p_semester AND ps.state = 'OPEN'
                                          AND current_date <= coalesce(ps.registration_closes, current_date))
                -- V733: a session of one's own behind the University's: the College's semester of it for the student's level
                ELSE CASE WHEN EXISTS (SELECT 1 FROM registration.college_semester(p_student, p_session, p_semester))
                          THEN EXISTS (SELECT 1 FROM registration.college_semester(p_student, p_session, p_semester) c
                                        WHERE c.starts_on IS NOT NULL AND c.starts_on <= current_date AND (c.ends_on IS NULL OR current_date <= c.ends_on))
                          ELSE registration.add_drop_open(p_session, p_semester) END END
$function$;

DO $$
DECLARE d text;
BEGIN
    -- the dashboard's context: the student's own session
    d := pg_get_functiondef('people.academic_context(uuid)'::regprocedure);
    IF position('ELSE coalesce((SELECT name FROM cur), (SELECT name FROM run)) END AS name),' IN d) = 0
       OR position('ELSE (SELECT name FROM cur) END, a.transitions_on' IN d) = 0 THEN
        RAISE EXCEPTION 'V733: people.academic_context is not as V379 left it';
    END IF;
    d := replace(d, 'ELSE coalesce((SELECT name FROM cur), (SELECT name FROM run)) END AS name),',
                    'ELSE coalesce(people.own_session(p_student), (SELECT name FROM cur), (SELECT name FROM run)) END AS name),   -- V733');
    d := replace(d, 'ELSE (SELECT name FROM cur) END, a.transitions_on', 'ELSE coalesce(people.own_session(p_student), (SELECT name FROM cur)) END, a.transitions_on');
    EXECUTE d;

    -- the registration gate: the College's semester of a session of one's own, behind the University's, opens and closes it
    d := pg_get_functiondef('registration.registration_gate(uuid,text,integer)'::regprocedure);
    IF position('WHEN st.entry_mode = ''POSTGRADUATE'' THEN registration.pg_gate_of(p_session, p_semester)' IN d) = 0
       OR position('FROM w LEFT JOIN sm ON true LEFT JOIN st ON true' IN d) = 0 THEN
        RAISE EXCEPTION 'V733: registration.registration_gate is not as V389 left it';
    END IF;
    d := replace(d, 'WHEN st.entry_mode = ''POSTGRADUATE'' THEN registration.pg_gate_of(p_session, p_semester)',
        'WHEN st.entry_mode = ''POSTGRADUATE'' THEN registration.pg_gate_of(p_session, p_semester)
             -- V733: an MBBS student in a session of their own, behind the University''s: the College''s semester of it for their level
             WHEN cs.ordinal IS NOT NULL AND (cs.starts_on IS NULL OR current_date < cs.starts_on)
                  THEN ''The College''''s '' || w.ord || '' semester of '' || p_session || '' for '' || st.current_level || '' Level ''
                       || coalesce(''opens on '' || to_char(cs.starts_on, ''DD Month YYYY''), ''is not yet dated'') || ''.''
             WHEN cs.ordinal IS NOT NULL AND cs.ends_on IS NOT NULL AND current_date > cs.ends_on
                  THEN ''The College''''s '' || w.ord || '' semester of '' || p_session || '' for '' || st.current_level || '' Level closed on '' || to_char(cs.ends_on, ''DD Month YYYY'') || ''.''
             WHEN cs.ordinal IS NOT NULL THEN NULL');
    d := replace(d, 'FROM w LEFT JOIN sm ON true LEFT JOIN st ON true',
        'FROM w LEFT JOIN sm ON true LEFT JOIN st ON true LEFT JOIN LATERAL registration.college_semester(p_student, p_session, p_semester) cs ON true');
    EXECUTE d;

    -- the cohort engine: a student's current session is their own where they have one
    d := pg_get_functiondef('people.academic_position_rows_of(uuid[])'::regprocedure);
    IF (length(d) - length(replace(d, 'ELSE (SELECT name FROM cur) END', ''))) / length('ELSE (SELECT name FROM cur) END') <> 3
       OR position('bool_or(r.session = cur.name AND' IN d) = 0 OR position('AND r.session < cur.name)' IN d) = 0
       OR position('bool_or(e.session = cur.name)' IN d) = 0 OR position('WHERE e.session < cur.name)' IN d) = 0
       OR position('LEFT JOIN policy.academic_session a ON a.name = s.entry_session' IN d) = 0
       OR position('AS reconciled_graduate' IN d) = 0 THEN
        RAISE EXCEPTION 'V733: people.academic_position_rows_of is not as V695 left it';
    END IF;
    d := replace(d, 'ELSE (SELECT name FROM cur) END', 'ELSE coalesce(st.own_session, (SELECT name FROM cur)) END');
    d := replace(d, 'bool_or(r.session = cur.name AND', 'bool_or(r.session = coalesce(st.own_session, cur.name) AND');
    d := replace(d, 'AND r.session < cur.name)', 'AND r.session < coalesce(st.own_session, cur.name))');
    d := replace(d, 'bool_or(e.session = cur.name)', 'bool_or(e.session = coalesce(st.own_session, cur.name))');
    d := replace(d, 'WHERE e.session < cur.name)', 'WHERE e.session < coalesce(st.own_session, cur.name))');
    d := replace(d, 'AS reconciled_graduate', 'AS reconciled_graduate,
               ss.session AS own_session   -- V733: an MBBS student''s own session');
    d := replace(d, 'LEFT JOIN policy.academic_session a ON a.name = s.entry_session',
                    'LEFT JOIN policy.academic_session a ON a.name = s.entry_session
          LEFT JOIN people.study_session ss ON ss.student_id = s.id');
    EXECUTE d;

    -- the past-session fee account: a student's past ends before their own session
    d := pg_get_functiondef('finance.historical_rows_read(uuid[])'::regprocedure);
    IF (length(d) - length(replace(d, 'ELSE b.before_current END', ''))) / length('ELSE b.before_current END') <> 2
       OR position(E'CROSS JOIN bounds b\n          LEFT JOIN admissions.candidate c' IN d) = 0 THEN
        RAISE EXCEPTION 'V733: finance.historical_rows_read is not as V725 left it';
    END IF;
    d := replace(d, 'ELSE b.before_current END', 'ELSE CASE WHEN ss.session IS NOT NULL THEN finance.session_before(ss.session) ELSE b.before_current END END');
    d := replace(d, E'CROSS JOIN bounds b\n          LEFT JOIN admissions.candidate c',
                    E'CROSS JOIN bounds b\n          LEFT JOIN people.study_session ss ON ss.student_id = s.id   -- V733\n          LEFT JOIN admissions.candidate c');
    EXECUTE d;

    -- the GST/EPS rows: the level a session reads a student at — the current level from their own session on
    d := pg_get_functiondef('finance.gst_eps_rows(text,uuid)'::regprocedure);
    IF position('CASE WHEN p_session >= cur.name THEN s.current_level' IN d) = 0
       OR position(E'JOIN ref.programme p ON p.code = s.programme_code AND p.category = ''UNDER GRADUATE''\n          CROSS JOIN cur' IN d) = 0
       OR position('WHERE p_session >= cur.name AND (sb.basis' IN d) = 0 THEN
        RAISE EXCEPTION 'V733: finance.gst_eps_rows is not as V711 left it';
    END IF;
    d := replace(d, 'CASE WHEN p_session >= cur.name THEN s.current_level', 'CASE WHEN p_session >= coalesce(ss.session, cur.name) THEN s.current_level');
    d := replace(d, E'JOIN ref.programme p ON p.code = s.programme_code AND p.category = ''UNDER GRADUATE''\n          CROSS JOIN cur',
                    E'JOIN ref.programme p ON p.code = s.programme_code AND p.category = ''UNDER GRADUATE''\n          CROSS JOIN cur\n          LEFT JOIN people.study_session ss ON ss.student_id = s.id   -- V733');
    d := replace(d, 'WHERE p_session >= cur.name AND (sb.basis', 'WHERE p_session >= coalesce(people.own_session(b.id), cur.name) AND (sb.basis');
    EXECUTE d;

    -- the GST/EPS history test reads the level the same way
    d := pg_get_functiondef('registration.gst_history_only(uuid,text)'::regprocedure);
    IF position('CASE WHEN p_session >= coalesce((SELECT max(name) FROM policy.academic_session WHERE state = ''CURRENT''), '''')' IN d) = 0 THEN
        RAISE EXCEPTION 'V733: registration.gst_history_only is not as V645 left it';
    END IF;
    d := replace(d, 'CASE WHEN p_session >= coalesce((SELECT max(name) FROM policy.academic_session WHERE state = ''CURRENT''), '''')',
                    'CASE WHEN p_session >= coalesce(people.own_session(s.id), (SELECT max(name) FROM policy.academic_session WHERE state = ''CURRENT''), '''')');
    EXECUTE d;

    -- the results statement's current semester: an MBBS student's own session
    d := pg_get_functiondef('credentials.build_statement(uuid,text,text,integer)'::regprocedure);
    IF position(E'    -- the scope of the document\n' IN d) = 0 THEN
        RAISE EXCEPTION 'V733: credentials.build_statement is not as it was left';
    END IF;
    d := replace(d, E'    -- the scope of the document\n',
                    E'    -- V733: an MBBS student in a session of their own: that session, every semester of it\n'
                 || E'    IF people.own_session(p_student) IS NOT NULL THEN\n'
                 || E'        v_cur := people.own_session(p_student);\n'
                 || E'        v_cur_sem := NULL;\n'
                 || E'    END IF;\n'
                 || E'    -- the scope of the document\n');
    EXECUTE d;

    -- the session roll-over: a student in a session of their own moves one session on from it (never to the University's), with their
    -- level, as far as the target session; the University's roll-over of everyone else unchanged
    d := pg_get_functiondef('people.roll_over_session(text,text,text)'::regprocedure);
    IF (length(d) - length(replace(d, 'AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)', '')))
         / length('AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)') <> 2
       OR position('v_created boolean := false; v_promoted int := 0;' IN d) = 0
       OR position(E'    PERFORM set_config(''moaum.level_session'', '''', true);\n' IN d) = 0
       OR position('''promoted'', v_promoted, ''held'', v_held,' IN d) = 0 THEN
        RAISE EXCEPTION 'V733: people.roll_over_session is not as V725 left it';
    END IF;
    d := replace(d, 'AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)',
                    'AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)
       AND NOT EXISTS (SELECT 1 FROM people.study_session ss WHERE ss.student_id = s.id)   -- V733: a session of their own moves below');
    d := replace(d, 'v_created boolean := false; v_promoted int := 0;', 'v_created boolean := false; v_promoted int := 0; v_own int := 0; v_moved int := 0;');
    -- a student in a session of their own (an MBBS student behind the University) moves one session on from it — never into the target,
    -- the University's next — once a target (a re-run moves nobody twice); the level is promoted as the University's roll-over would
    -- promote it (counted to the target, below the final level, no hold), else the student is held at their level; both recorded
    d := replace(d, E'    PERFORM set_config(''moaum.level_session'', '''', true);\n',
          E'    -- V733: a student in a session of their own (an MBBS student behind the University) moves one session on from it — never into\n'
       || E'    -- the target — once a target; the level promoted as the University''s roll-over would promote it, else held; recorded\n'
       || E'    FOR r IN\n'
       || E'        SELECT s.id, x.tgt,\n'
       || E'               s.current_level < coalesce(finance.final_level(s.programme_code), 400) AS below_final,\n'
       || E'               (s.current_level < coalesce(finance.final_level(s.programme_code), 400)\n'
       || E'                AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = x.tgt)\n'
       || E'                AND people.counted_sessions(s.entry_session, p_to_session) > 0\n'
       || E'                AND s.current_level + 100 <= s.entry_level + 100 * people.counted_sessions(s.entry_session, p_to_session)\n'
       || E'                AND s.current_level + 100 <= coalesce(people.department_hold_of(s.id, x.tgt), 999)) AS promote\n'
       || E'          FROM people.student s\n'
       || E'          JOIN people.study_session ss ON ss.student_id = s.id\n'
       || E'         CROSS JOIN LATERAL (SELECT policy.session_after(ss.session, 1) AS tgt) x\n'
       || E'         WHERE s.status IN (''ACTIVE'', ''PROBATION'')\n'
       || E'           AND s.matric_no IS NOT NULL\n'
       || E'           AND college.runs_programme(s.programme_code)\n'
       || E'           AND x.tgt < p_to_session\n'
       || E'           AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = x.tgt AND a.state <> ''CANCELLED'')\n'
       || E'           AND NOT EXISTS (SELECT 1 FROM people.study_session_event ev WHERE ev.student_id = s.id AND ev.roll_over_to = p_to_session)\n'
       || E'    LOOP\n'
       || E'        PERFORM set_config(''moaum.level_session'', r.tgt, true);\n'
       || E'        IF r.promote THEN\n'
       || E'            UPDATE people.student SET current_level = current_level + 100 WHERE id = r.id;\n'
       || E'            INSERT INTO people.enrolment (id, student_id, session, level)\n'
       || E'            SELECT gen_random_uuid(), r.id, r.tgt, s2.current_level FROM people.student s2 WHERE s2.id = r.id\n'
       || E'            ON CONFLICT (student_id, session) DO NOTHING;\n'
       || E'            v_own := v_own + 1;\n'
       || E'        ELSIF r.below_final THEN\n'
       || E'            v_held := v_held + 1;\n'
       || E'        END IF;\n'
       || E'        PERFORM people.study_session_apply(r.id, r.tgt, ''ROLL_OVER'', ''Session roll-over to '' || p_to_session || '': '' || btrim(p_reason), p_to_session);\n'
       || E'        v_moved := v_moved + 1;\n'
       || E'    END LOOP;\n'
       || E'\n'
       || E'    PERFORM set_config(''moaum.level_session'', '''', true);\n');
    d := replace(d, '''promoted'', v_promoted, ''held'', v_held,', '''promoted'', v_promoted, ''promoted_own_session'', v_own, ''moved_own_session'', v_moved, ''held'', v_held,');
    EXECUTE d;
END $$;

-- the students whose academic position reads a session: none has a session of their own yet, so nothing moves today; the functions
-- above read it from the first choice on
COMMIT;
