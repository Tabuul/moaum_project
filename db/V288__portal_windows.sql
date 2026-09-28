-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V288 — the portal's windows: school fees payment and course registration, opened and closed
--        centrally by the Director of ICT
--
--   policy.portal_window holds, per window type (SCHOOL_FEES_PAYMENT, COURSE_REGISTRATION; more
--   may follow), per session and optionally per semester, the current rule: when it opens, when
--   it closes, until when the late period runs, whether the late fee applies, and a forced OPEN
--   or CLOSED that overrides the dates at once. Every change supersedes the row before it, so
--   history is kept, and writes policy.portal_window_event with the previous and new values, the
--   officer and the reason. policy.window_state computes the state from server time in
--   Africa/Lagos: OPEN (phase NORMAL or LATE), SCHEDULED, CLOSED, EXPIRED; where nothing is
--   configured the window is OPEN by default, so what runs today keeps running.
--   Enforcement: finance.new_reference refuses a school-fees reference while the window is not
--   open (a reference already generated is paid and verified as before); the registration gate
--   reads the registration window before the calendar's semester. Late fees are lines of the
--   Bursar's fee schedule with a kind (LATE_PAYMENT, LATE_REGISTRATION) that the charges engine
--   adds only while the window is in its late phase and the obligation was not met in time.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V288: the portal''s payment and registration windows', true);

-- ── 1 · the windows and their history ────────────────────────────────────────────────────────
CREATE TABLE policy.portal_window (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    window_type      text NOT NULL CHECK (window_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION')),
    session          text NOT NULL REFERENCES policy.academic_session(name),
    semester         integer CHECK (semester BETWEEN 1 AND 3),
    opens_at         timestamptz,
    closes_at        timestamptz,
    late_until       timestamptz,
    late_fee_enabled boolean NOT NULL DEFAULT false,
    forced           text CHECK (forced IN ('OPEN', 'CLOSED')),
    reason           text,
    created_by       uuid,
    created_office   text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    superseded_at    timestamptz,
    CONSTRAINT ck_window_dates CHECK (closes_at IS NULL OR opens_at IS NULL OR closes_at >= opens_at),
    CONSTRAINT ck_window_late CHECK (late_until IS NULL OR closes_at IS NULL OR late_until >= closes_at)
);
CREATE UNIQUE INDEX ux_portal_window_current ON policy.portal_window (window_type, session, coalesce(semester, 0)) WHERE superseded_at IS NULL;
COMMENT ON TABLE policy.portal_window IS 'The Director of ICT''s rule on when a portal operation is open (V288): per window type, session and optional semester; a change supersedes the row before it, never overwrites it.';
SELECT audit.attach('policy.portal_window');

CREATE TABLE policy.portal_window_event (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    window_id         uuid REFERENCES policy.portal_window(id),
    window_type       text NOT NULL,
    session           text NOT NULL,
    semester          integer,
    action            text NOT NULL CHECK (action IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT')),
    previous_state    text,
    new_state         text,
    previous_opens_at timestamptz,
    previous_closes_at timestamptz,
    previous_late_until timestamptz,
    new_opens_at      timestamptz,
    new_closes_at     timestamptz,
    new_late_until    timestamptz,
    late_fee_enabled  boolean,
    reason            text,
    actor             uuid,
    office            text,
    at                timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_portal_window_event_at ON policy.portal_window_event (window_type, session, at DESC);
COMMENT ON TABLE policy.portal_window_event IS 'Every act on a portal window (V288): what it was, what it became, who, when, why. Insert-only.';
SELECT audit.attach('policy.portal_window_event');
GRANT SELECT, INSERT, UPDATE ON policy.portal_window TO app_student;
GRANT SELECT, INSERT ON policy.portal_window_event TO app_student;

-- ── 2 · the state, from the rule and the clock ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION policy.window_state(p_type text, p_session text, p_semester integer)
RETURNS TABLE(configured boolean, state text, phase text, opens_at timestamptz, closes_at timestamptz, late_until timestamptz,
              late_fee_enabled boolean, forced text, reason text, window_id uuid, semester integer)
LANGUAGE sql STABLE AS $fn$
    WITH w AS (
        SELECT * FROM policy.portal_window
         WHERE window_type = p_type AND session = p_session AND superseded_at IS NULL
           AND (semester = p_semester OR semester IS NULL)
         ORDER BY (semester IS NOT NULL) DESC LIMIT 1)
    SELECT w.id IS NOT NULL,
           CASE WHEN w.id IS NULL THEN 'OPEN'
                WHEN w.forced = 'CLOSED' THEN 'CLOSED'
                WHEN w.forced = 'OPEN' THEN 'OPEN'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'SCHEDULED'
                WHEN w.closes_at IS NULL OR now() <= w.closes_at THEN 'OPEN'
                WHEN w.late_until IS NOT NULL AND now() <= w.late_until THEN 'OPEN'
                ELSE 'EXPIRED' END,
           CASE WHEN w.id IS NULL THEN 'NORMAL'
                WHEN w.forced = 'OPEN' THEN CASE WHEN w.late_fee_enabled THEN 'LATE' ELSE 'NORMAL' END
                WHEN w.forced = 'CLOSED' THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at AND w.late_until IS NOT NULL AND now() <= w.late_until THEN 'LATE'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at THEN 'NONE'
                ELSE 'NORMAL' END,
           w.opens_at, w.closes_at, w.late_until, coalesce(w.late_fee_enabled, false), w.forced, w.reason, w.id, w.semester
      FROM (SELECT 1) one LEFT JOIN w ON true
$fn$;
COMMENT ON FUNCTION policy.window_state(text, text, integer) IS 'A portal window''s state now (V288): configured or open by default; OPEN, SCHEDULED, CLOSED or EXPIRED; phase NORMAL, LATE or NONE; the dates and the rule behind it.';

CREATE OR REPLACE FUNCTION policy.window_open(p_type text, p_session text, p_semester integer)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT state = 'OPEN' FROM policy.window_state(p_type, p_session, p_semester)
$fn$;

-- ── 3 · the Director's act: one function, every action, the history kept ─────────────────────
CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text,
                                             p_opens timestamptz, p_closes timestamptz, p_late_until timestamptz, p_late_fee boolean,
                                             p_reason text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION') THEN RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514'; END IF;
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
    VALUES (v_id, p_type, p_session, p_semester, p_action, CASE WHEN prev.configured THEN prev.state ELSE 'OPEN (default)' END, nxt.state, cur.opens_at, cur.closes_at, cur.late_until,
            v_opens, v_closes, v_late, v_fee, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office);
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION policy.window_act(text, text, integer, text, timestamptz, timestamptz, timestamptz, boolean, text, uuid, text) IS
  'The Director of ICT''s act on a window (V288): OPEN/REOPEN (now, or over dates), CLOSE (now), SCHEDULE, EXTEND, SHORTEN, EDIT; the row before is superseded, the event written.';

-- ── 4 · school fees: no new reference while the window is shut ───────────────────────────────
ALTER TABLE finance.fee_schedule ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'FEE' CHECK (kind IN ('FEE', 'LATE_PAYMENT', 'LATE_REGISTRATION'));
COMMENT ON COLUMN finance.fee_schedule.kind IS 'FEE: charged as stated. LATE_PAYMENT / LATE_REGISTRATION: charged only while the portal window is in its late phase and the obligation was not met before the deadline (V288).';

-- ── 5 · the charges engine with the late kinds; the gates that read the windows ─────────────
CREATE OR REPLACE FUNCTION finance.charges_of(p_student uuid, p_session text, p_kinds text[])
 RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
 LANGUAGE sql
 STABLE
AS $fn$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT f.id,
           replace(replace(replace(f.item,
               '(semester 1)', '(First Semester)'),
               '(semester 2)', '(Second Semester)'),
               '(semester 3)', '(Third Semester)') AS item,
           f.amount, f.ord
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.kind = ANY (p_kinds)
       AND f.spillover = me.is_spill
       AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = me.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL
            OR f.semester <= coalesce((SELECT max(sm.number) FROM policy.semester sm
                                        WHERE sm.session = p_session AND sm.state = 'OPEN'), 3))
     ORDER BY f.ord, f.item;
$fn$;

CREATE OR REPLACE FUNCTION finance.late_payment_applies(p_student uuid, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT w.late_fee_enabled AND w.phase = 'LATE'
       AND coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                      WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
                        AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at)), 0)
         < (SELECT coalesce(sum(c.amount), 0) FROM finance.charges_of(p_student, p_session, ARRAY['FEE']) c)
      FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL) w
$fn$;

CREATE OR REPLACE FUNCTION finance.late_registration_applies(p_student uuid, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (
        SELECT 1 FROM generate_series(1, 3) sem
         CROSS JOIN LATERAL policy.window_state('COURSE_REGISTRATION', p_session, sem) w
         WHERE w.configured AND w.late_fee_enabled
           AND ((w.phase = 'LATE' AND NOT EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = sem
                                                     AND r.submitted_at IS NOT NULL AND (w.closes_at IS NULL OR r.submitted_at <= w.closes_at)))
             OR EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = sem
                          AND r.submitted_at IS NOT NULL AND w.closes_at IS NOT NULL AND r.submitted_at > w.closes_at)))
$fn$;

CREATE OR REPLACE FUNCTION finance.charges(p_student uuid, p_session text)
 RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
 LANGUAGE sql STABLE AS $fn$
    SELECT c.id, c.item, c.amount, c.ord FROM finance.charges_of(p_student, p_session, ARRAY['FEE']) c
    UNION ALL
    SELECT c.id, c.item, c.amount, c.ord FROM finance.charges_of(p_student, p_session, ARRAY['LATE_PAYMENT']) c WHERE finance.late_payment_applies(p_student, p_session)
    UNION ALL
    SELECT c.id, c.item, c.amount, c.ord FROM finance.charges_of(p_student, p_session, ARRAY['LATE_REGISTRATION']) c WHERE finance.late_registration_applies(p_student, p_session)
    ORDER BY ord, item
$fn$;

CREATE OR REPLACE FUNCTION registration.registration_gate(p_student uuid, p_session text, p_semester integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $fn$
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
             WHEN sm.state = 'CLOSED' THEN 'The ' || w.ord || ' semester of ' || p_session || ' is closed for registration.'
             WHEN sm.fresh_registration_from IS NOT NULL AND sm.fresh_registration_from <= current_date AND st.entry_session = p_session THEN NULL
             WHEN sm.fresh_registration_from IS NOT NULL AND st.entry_session = p_session
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' opens to fresh students on ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             WHEN sm.fresh_registration_from IS NOT NULL
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open; only the session''s fresh students register from ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             ELSE 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open for registration.'
           END
      FROM w LEFT JOIN sm ON true LEFT JOIN st ON true LEFT JOIN LATERAL (SELECT * FROM policy.window_state('COURSE_REGISTRATION', p_session, p_semester)) pw ON true
$fn$;

CREATE OR REPLACE FUNCTION finance.new_reference(p_student uuid, p_session text, p_amount numeric, p_purpose text)
 RETURNS text
 LANGUAGE plpgsql
AS $fn$
DECLARE pos record; v_ref text; v_matric text; win record;
BEGIN
    -- school fees wait for a successful online screening where the session requires one (V269)
    PERFORM admissions.screening_refuse_student(p_student, 'SCHOOL FEES');
    -- the portal's school-fees window (V288): a new reference is generated only while it is open; one already generated is paid and verified as before
    SELECT * INTO win FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL);
    IF win.state <> 'OPEN' THEN
        RAISE EXCEPTION 'SCHOOL_FEES_PAYMENT_CLOSED: school fees payment is currently % for %', lower(win.state), p_session USING ERRCODE = '23514',
            HINT = CASE WHEN win.state = 'SCHEDULED' THEN 'It opens on ' || to_char(win.opens_at AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.' ELSE 'The Directorate of ICT opens the payment window.' END;
    END IF;
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    IF pos.due = 0 THEN
        RAISE EXCEPTION 'no charge is stated for % yet', p_session USING ERRCODE = '23514',
            HINT = 'The Bursar states the session''s fee schedule before anything is paid against it.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'a payment is for an amount' USING ERRCODE = '23514';
    END IF;
    IF p_amount > pos.balance THEN
        RAISE EXCEPTION 'the amount % is more than the balance of %', p_amount, pos.balance USING ERRCODE = '23514',
            HINT = 'Pay the balance, or part of it; nothing is taken beyond what is owed.';
    END IF;
    SELECT coalesce(matric_no, admission_no, 'X') INTO v_matric FROM people.student WHERE id = p_student;
    v_ref := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
    VALUES (p_student, p_session, v_ref, coalesce(p_purpose, 'School fees ' || p_session), p_amount, now() + interval '24 hours');
    RETURN v_ref;
END $fn$;

COMMIT;
