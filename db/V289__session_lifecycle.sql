-- ── V289 — the academic session lifecycle: current and planned at once, and the transition between them ──
--
-- The University runs one session for its returning students while it prepares the
-- next for its entrants. Both were already on the calendar (policy.academic_session
-- since V004: PLANNED, CURRENT, CLOSED; one CURRENT at a time; none overlapping),
-- the entrant already stands in their entry session when it is later than the
-- current one (V278), fees and portal windows are per session (V288), and the
-- semester's early door for fresh students is dated per session (V287). What was
-- missing is the lifecycle itself: a session drafted before it is planned, one
-- archived after it is completed, the official transition point at which the
-- planned session becomes current and the current one completed, and one place
-- that makes that transition - validated, transactional, idempotent and audited -
-- whether the Registrar asks for it or the clock reaches the date.
--
--   DRAFT ─► PLANNED ─► CURRENT ─► CLOSED (read "Completed") ─► ARCHIVED
--
-- The stored word CLOSED stays: nineteen functions and every report read it; the
-- label the University sees is Completed. Semesters keep NOT_YET_OPEN (Planned),
-- OPEN and CLOSED (Completed) and gain ARCHIVED; a semester's "active" phase is
-- read from its dates, not stored, so nothing switches by itself when the policy
-- says the Office opens a semester by hand.
--
-- The transition moves no student. Enrolments, registrations, fees and results of
-- the completed session stay where they are; the entrant of the planned session
-- continues under the same account; the returning student progresses only by the
-- rules that already exist (results, promotion, the roll-over the Registry runs).

-- ── the session's lifecycle ────────────────────────────────────────────────
ALTER TABLE policy.academic_session DROP CONSTRAINT IF EXISTS ck_session_state;
ALTER TABLE policy.academic_session
    ADD CONSTRAINT ck_session_state CHECK (state IN ('DRAFT', 'PLANNED', 'CURRENT', 'CLOSED', 'ARCHIVED')),
    ADD COLUMN IF NOT EXISTS transition_mode text NOT NULL DEFAULT 'MANUAL',
    ADD COLUMN IF NOT EXISTS transitions_on  date NULL,
    ADD COLUMN IF NOT EXISTS made_current_at timestamptz NULL,
    ADD COLUMN IF NOT EXISTS completed_at    timestamptz NULL,
    ADD COLUMN IF NOT EXISTS archived_at     timestamptz NULL;
ALTER TABLE policy.academic_session DROP CONSTRAINT IF EXISTS ck_session_transition_mode;
ALTER TABLE policy.academic_session
    ADD CONSTRAINT ck_session_transition_mode CHECK (transition_mode IN ('MANUAL', 'AUTOMATIC'));
ALTER TABLE policy.academic_session DROP CONSTRAINT IF EXISTS ck_session_archived;
ALTER TABLE policy.academic_session
    ADD CONSTRAINT ck_session_archived CHECK (state <> 'ARCHIVED' OR archived_at IS NOT NULL);

COMMENT ON COLUMN policy.academic_session.transition_mode IS
  'MANUAL: the Registrar makes the planned session current. AUTOMATIC: the session clock makes it current on transitions_on, when the readiness checks pass (V289).';
COMMENT ON COLUMN policy.academic_session.transitions_on IS
  'The official transition point: the day this planned session becomes current. Read by the clock when transition_mode is AUTOMATIC; shown as the date either way (V289).';

-- semesters: Planned (NOT_YET_OPEN), Open, Completed (CLOSED), Archived
ALTER TABLE policy.semester DROP CONSTRAINT IF EXISTS ck_semester_state;
ALTER TABLE policy.semester
    ADD CONSTRAINT ck_semester_state CHECK (state IN ('NOT_YET_OPEN', 'OPEN', 'CLOSED', 'ARCHIVED'));

-- ── the transition log ────────────────────────────────────────────────────
CREATE TABLE policy.session_transition (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    from_session   text NULL,
    to_session     text NOT NULL REFERENCES policy.academic_session(name),
    outcome        text NOT NULL,
    mode           text NOT NULL,
    reason         text NULL,
    senate_minute  text NULL,
    checks         jsonb NOT NULL DEFAULT '[]'::jsonb,
    actor_id       uuid NULL,
    actor_office   text NULL,
    at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_transition_outcome CHECK (outcome IN ('DONE', 'BLOCKED', 'ALREADY')),
    CONSTRAINT ck_transition_mode CHECK (mode IN ('MANUAL', 'AUTOMATIC'))
);
COMMENT ON TABLE policy.session_transition IS
  'Every attempt to make a planned session current (V289): who or what asked (mode), the session that was current, the readiness checks as they stood, and whether it was done, blocked or already so.';
CREATE INDEX ix_session_transition_at ON policy.session_transition (at DESC);
SELECT audit.attach('policy.session_transition');
GRANT SELECT, INSERT ON policy.session_transition TO app_student;

-- ── labels ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION policy.session_label(p_state text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE p_state WHEN 'DRAFT' THEN 'Draft' WHEN 'PLANNED' THEN 'Planned' WHEN 'CURRENT' THEN 'Current'
                        WHEN 'CLOSED' THEN 'Completed' WHEN 'ARCHIVED' THEN 'Archived' ELSE coalesce(p_state, '') END
$fn$;

CREATE OR REPLACE FUNCTION policy.semester_label(p_state text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE p_state WHEN 'NOT_YET_OPEN' THEN 'Planned' WHEN 'OPEN' THEN 'Open' WHEN 'CLOSED' THEN 'Completed'
                        WHEN 'ARCHIVED' THEN 'Archived' ELSE coalesce(p_state, '') END
$fn$;

-- ── the next planned session: the earliest planned one after the current ──
CREATE OR REPLACE FUNCTION policy.next_planned_session()
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT s.name FROM policy.academic_session s
     WHERE s.state = 'PLANNED'
       AND s.starts_on > coalesce((SELECT c.starts_on FROM policy.academic_session c WHERE c.state = 'CURRENT'), date '0001-01-01')
     ORDER BY s.starts_on LIMIT 1
$fn$;

-- ── readiness: what the transition into a session needs, and what it advises ──
CREATE OR REPLACE FUNCTION policy.transition_readiness(p_to text)
RETURNS TABLE(code text, ok boolean, blocking boolean, detail text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE s policy.academic_session%ROWTYPE; cur policy.academic_session%ROWTYPE; n_sem int; n_dated int; n_fee int; n_fresh int; n_win int;
BEGIN
    SELECT * INTO s FROM policy.academic_session WHERE name = p_to;
    SELECT * INTO cur FROM policy.academic_session WHERE state = 'CURRENT';
    IF s.name IS NULL THEN
        RETURN QUERY SELECT 'SESSION_EXISTS', false, true, 'No session named ' || coalesce(p_to, '?') || ' is on the calendar.';
        RETURN;
    END IF;
    RETURN QUERY SELECT 'SESSION_EXISTS', true, true, p_to || ' is on the calendar (' || policy.session_label(s.state) || ').';
    RETURN QUERY SELECT 'STATE_PLANNED', s.state = 'PLANNED', true,
        CASE s.state WHEN 'PLANNED' THEN 'The session is planned.'
                     WHEN 'CURRENT' THEN 'The session is already current; nothing is to be done.'
                     WHEN 'DRAFT' THEN 'The session is still a draft: mark it planned once its setup is agreed.'
                     ELSE 'The session is ' || lower(policy.session_label(s.state)) || ' and cannot become current again.' END;
    RETURN QUERY SELECT 'SENATE_MINUTE', s.senate_minute IS NOT NULL AND btrim(s.senate_minute) <> '', true,
        CASE WHEN s.senate_minute IS NOT NULL AND btrim(s.senate_minute) <> '' THEN 'Senate minute ' || s.senate_minute || ' is recorded.'
             ELSE 'No Senate minute is recorded against the session; a session is not current without the minute that resolved to run it.' END;
    RETURN QUERY SELECT 'NO_CONFLICT', cur.name IS NULL OR cur.name = s.name OR s.starts_on > cur.starts_on, true,
        CASE WHEN cur.name IS NULL THEN 'No session is current; ' || p_to || ' becomes the first.'
             WHEN cur.name = s.name THEN 'Already the current session.'
             WHEN s.starts_on > cur.starts_on THEN cur.name || ' is current and will be completed by the transition.'
             ELSE p_to || ' begins before the current session ' || cur.name || ' and cannot follow it.' END;
    SELECT count(*), count(*) FILTER (WHERE lectures_from IS NOT NULL) INTO n_sem, n_dated FROM policy.semester WHERE session = p_to;
    RETURN QUERY SELECT 'SEMESTERS_CONFIGURED', n_sem >= 1, false,
        CASE WHEN n_sem >= s.semesters THEN n_sem || ' of ' || s.semesters || ' semesters are on the calendar.'
             WHEN n_sem >= 1 THEN n_sem || ' of ' || s.semesters || ' semesters are on the calendar; the rest can follow.'
             ELSE 'No semester of ' || p_to || ' is on the calendar yet.' END;
    RETURN QUERY SELECT 'FIRST_SEMESTER_DATED', EXISTS (SELECT 1 FROM policy.semester WHERE session = p_to AND number = 1 AND lectures_from IS NOT NULL), false,
        CASE WHEN EXISTS (SELECT 1 FROM policy.semester WHERE session = p_to AND number = 1 AND lectures_from IS NOT NULL)
             THEN 'The first semester''s lectures are dated.' ELSE 'The first semester has no lecture dates; registration, examinations and results wait on them.' END;
    SELECT count(*) INTO n_fee FROM finance.fee_schedule WHERE session = p_to AND ended_at IS NULL;
    RETURN QUERY SELECT 'FEE_SCHEDULE', n_fee > 0, false,
        CASE WHEN n_fee > 0 THEN n_fee || ' fee schedule line(s) are stated for ' || p_to || '.' ELSE 'The Bursar has stated no fee schedule for ' || p_to || '; students see no charge.' END;
    SELECT count(*) INTO n_win FROM policy.portal_window WHERE session = p_to AND superseded_at IS NULL;
    RETURN QUERY SELECT 'PORTAL_WINDOWS', true, false,
        CASE WHEN n_win > 0 THEN n_win || ' portal window rule(s) are set for ' || p_to || '.' ELSE 'No portal window is configured for ' || p_to || '; school fees payment and course registration are open by default.' END;
    SELECT count(*) INTO n_fresh FROM people.student WHERE entry_session = p_to;
    RETURN QUERY SELECT 'FRESH_STUDENTS', true, false,
        CASE WHEN n_fresh > 0 THEN n_fresh || ' entrant(s) of ' || p_to || ' are on the register and continue under the same accounts.' ELSE 'No entrant of ' || p_to || ' is on the register yet.' END;
    RETURN QUERY SELECT 'RETURNING_STUDENTS', true, false,
        'Returning students are not moved by the transition: they progress by the results, promotion and roll-over rules that already exist.';
END $fn$;

COMMENT ON FUNCTION policy.transition_readiness(text) IS
  'The checks the transition into a planned session runs (V289): blocking ones stop it (exists, planned, Senate minute, follows the current session); advisory ones are shown and, for the automatic clock, also block.';

-- ── the transition itself: one function, one transaction, idempotent, logged ──
CREATE OR REPLACE FUNCTION policy.transition_session(p_to text, p_mode text, p_reason text, p_minute text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        cur text; s policy.academic_session%ROWTYPE; v_checks jsonb; v_blocked boolean; v_minute text; v_id uuid;
BEGIN
    IF p_mode NOT IN ('MANUAL', 'AUTOMATIC') THEN
        RAISE EXCEPTION 'SESSION_TRANSITION_INVALID: a transition is MANUAL or AUTOMATIC, not %', coalesce(p_mode, '?') USING ERRCODE = '23514';
    END IF;
    IF p_mode = 'MANUAL' AND who IS NULL THEN
        RAISE EXCEPTION 'SESSION_TRANSITION_INVALID: a manual session transition is made by a person' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'SESSION_TRANSITION_INVALID: a session transition names its reason' USING ERRCODE = '23514';
    END IF;
    PERFORM 1 FROM policy.academic_session WHERE name = p_to FOR UPDATE;
    SELECT * INTO s FROM policy.academic_session WHERE name = p_to;
    SELECT name INTO cur FROM policy.academic_session WHERE state = 'CURRENT' FOR UPDATE;

    -- already current: nothing to do, and said so (idempotent)
    IF s.name IS NOT NULL AND s.state = 'CURRENT' THEN
        INSERT INTO policy.session_transition (from_session, to_session, outcome, mode, reason, senate_minute, checks, actor_id, actor_office)
        VALUES (cur, p_to, 'ALREADY', p_mode, btrim(p_reason), s.senate_minute, '[]'::jsonb, who, office) RETURNING id INTO v_id;
        RETURN jsonb_build_object('id', v_id, 'outcome', 'ALREADY', 'from', cur, 'to', p_to, 'mode', p_mode, 'checks', '[]'::jsonb);
    END IF;

    -- a minute given now is recorded against the session before the checks read it
    v_minute := nullif(btrim(coalesce(p_minute, '')), '');
    IF v_minute IS NOT NULL AND s.name IS NOT NULL THEN
        UPDATE policy.academic_session SET senate_minute = v_minute WHERE name = p_to;
    END IF;

    SELECT coalesce(jsonb_agg(jsonb_build_object('code', r.code, 'ok', r.ok, 'blocking', r.blocking, 'detail', r.detail) ORDER BY r.blocking DESC, r.code), '[]'::jsonb),
           bool_or(NOT r.ok AND (r.blocking OR p_mode = 'AUTOMATIC'))
      INTO v_checks, v_blocked
      FROM policy.transition_readiness(p_to) r;

    IF s.name IS NULL OR coalesce(v_blocked, false) THEN
        INSERT INTO policy.session_transition (from_session, to_session, outcome, mode, reason, senate_minute, checks, actor_id, actor_office)
        VALUES (cur, coalesce(s.name, p_to), 'BLOCKED', p_mode, btrim(p_reason), v_minute, v_checks, who, office) RETURNING id INTO v_id;
        RETURN jsonb_build_object('id', v_id, 'outcome', 'BLOCKED', 'from', cur, 'to', p_to, 'mode', p_mode, 'checks', v_checks);
    END IF;

    -- both moves in this one transaction: the current session completed, the planned one current
    IF cur IS NOT NULL THEN
        UPDATE policy.academic_session SET state = 'CLOSED', completed_at = now() WHERE name = cur;
    END IF;
    UPDATE policy.academic_session SET state = 'CURRENT', made_current_at = now(), senate_minute = coalesce(v_minute, senate_minute) WHERE name = p_to;

    INSERT INTO policy.session_transition (from_session, to_session, outcome, mode, reason, senate_minute, checks, actor_id, actor_office)
    VALUES (cur, p_to, 'DONE', p_mode, btrim(p_reason), coalesce(v_minute, s.senate_minute), v_checks, who, office) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id', v_id, 'outcome', 'DONE', 'from', cur, 'to', p_to, 'mode', p_mode, 'checks', v_checks);
END $fn$;

COMMENT ON FUNCTION policy.transition_session(text, text, text, text) IS
  'The one place a planned session becomes current (V289): the current session is completed and the planned one made current in the same transaction, or nothing changes; already current answers ALREADY; a failed check answers BLOCKED and is logged; no student is moved.';

-- ── archive a completed session ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION policy.archive_session(p_name text, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; st text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'SESSION_ARCHIVE_REFUSED: a session is archived by a person' USING ERRCODE = '23514'; END IF;
    SELECT state INTO st FROM policy.academic_session WHERE name = p_name FOR UPDATE;
    IF st IS NULL THEN RAISE EXCEPTION 'SESSION_ARCHIVE_REFUSED: no session named % is on the calendar', p_name USING ERRCODE = '23514'; END IF;
    IF st = 'ARCHIVED' THEN RETURN; END IF;
    IF st <> 'CLOSED' THEN
        RAISE EXCEPTION 'SESSION_ARCHIVE_REFUSED: % is % and only a completed session is archived', p_name, lower(policy.session_label(st)) USING ERRCODE = '23514';
    END IF;
    UPDATE policy.academic_session SET state = 'ARCHIVED', archived_at = now() WHERE name = p_name;
    UPDATE policy.semester SET state = 'ARCHIVED' WHERE session = p_name AND state = 'CLOSED';
END $fn$;

-- ── the clock's question: which planned session is due to become current ──
CREATE OR REPLACE FUNCTION policy.sessions_due_for_transition()
RETURNS TABLE(name text, transitions_on date, senate_minute text)
LANGUAGE sql STABLE AS $fn$
    SELECT s.name, s.transitions_on, s.senate_minute
      FROM policy.academic_session s
     WHERE s.state = 'PLANNED' AND s.transition_mode = 'AUTOMATIC' AND s.transitions_on IS NOT NULL AND s.transitions_on <= current_date
       -- one attempt a day: a blocked attempt today is not repeated until the Office has had the day to act
       AND NOT EXISTS (SELECT 1 FROM policy.session_transition t WHERE t.to_session = s.name AND t.mode = 'AUTOMATIC' AND t.at::date = current_date)
     ORDER BY s.starts_on
$fn$;

-- ── a semester archived reads as completed where the register reads closed ──
CREATE OR REPLACE FUNCTION registration.closed_semesters()
 RETURNS TABLE(session text, semester integer, closed_on date)
 LANGUAGE sql STABLE AS $fn$
    SELECT s.session, s.number, coalesce(s.late_registration_closes, s.registration_closes, a.ends_on)
      FROM policy.semester s JOIN policy.academic_session a ON a.name = s.session
     WHERE s.state IN ('CLOSED', 'ARCHIVED') OR coalesce(s.late_registration_closes, s.registration_closes, a.ends_on) < current_date
     ORDER BY s.session, s.number
$fn$;

CREATE OR REPLACE FUNCTION registration.registration_gate(p_student uuid, p_session text, p_semester integer)
 RETURNS text LANGUAGE sql STABLE AS $fn$
    WITH sm AS (SELECT * FROM policy.semester WHERE session = p_session AND number = p_semester),
         st AS (SELECT * FROM people.student WHERE id = p_student),
         w AS (SELECT CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END AS ord)
    SELECT CASE
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
$fn$;

-- ── the student's academic context: the session they stand in and why ──────
-- CURRENT: a returning student in the current session (or the latest run one between sessions).
-- PREPARING: an entrant whose entry session is still planned - pre-resumption work.
CREATE OR REPLACE FUNCTION people.academic_context(p_student uuid)
RETURNS TABLE(session text, context text, session_state text, current_session text, transitions_on date)
LANGUAGE sql STABLE AS $fn$
    WITH st AS (SELECT s.entry_session FROM people.student s WHERE s.id = p_student),
         cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'),
         run AS (SELECT name FROM policy.academic_session WHERE state IN ('CURRENT', 'CLOSED', 'ARCHIVED') ORDER BY name DESC LIMIT 1),
         base AS (SELECT coalesce((SELECT name FROM cur), (SELECT name FROM run)) AS name),
         stands AS (SELECT CASE WHEN st.entry_session IS NOT NULL AND (base.name IS NULL OR st.entry_session > base.name) THEN st.entry_session ELSE base.name END AS name
                      FROM st CROSS JOIN base)
    SELECT stands.name,
           CASE WHEN a.state IN ('PLANNED', 'DRAFT') AND stands.name = st.entry_session THEN 'PREPARING'
                WHEN stands.name IS NULL THEN 'NONE' ELSE 'CURRENT' END,
           a.state, (SELECT name FROM cur), a.transitions_on
      FROM stands CROSS JOIN st LEFT JOIN policy.academic_session a ON a.name = stands.name
$fn$;

COMMENT ON FUNCTION people.academic_context(uuid) IS
  'The session a student stands in and why (V289): CURRENT for a returning student, PREPARING for an entrant of a session still planned, with the session''s state and the transition date.';
