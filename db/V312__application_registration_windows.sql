-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V312 — Application Registration: two more windows of the portal, opened and closed by the
--        Director of ICT — POST_UTME_REGISTRATION (/apply) and POSTGRADUATE_APPLICATION (/pg/apply)
--
--   The same policy.portal_window of V288/V295: a rule per window type and session, superseded
--   never overwritten, its state computed from the server's clock, every act on the history with
--   its reason. Like admission status checking the two run over the whole admission exercise of a
--   session: no semester, no late period. Unlike it they are OPEN until the Director first acts,
--   so what runs today keeps running.
--
--   What a closed window stops: the creation of a NEW application — a Post-UTME applicant account
--   (admissions.register_applicant) or a postgraduate application (admissions.pg_apply). Nothing
--   else: an applicant who registered before the closing signs in, pays, uploads, submits and reads
--   their status as before; nothing is deleted, cancelled or reversed. Admission status checking
--   keeps its own window.
--
--   The refusal is enforced here, by a trigger on the two tables a new application is born in,
--   when the writer is the applicant themselves (the audit office 'applicant'); an office importing
--   the old portal's applicants is not an applicant registering. The API refuses earlier and more
--   kindly, with the Director's own closure message; this is the backstop no path can go round.
--
--   policy.portal_window_message holds, per application window, the message the public sees while
--   it is closed; the Director edits it on the screen. policy.application_windows_public() is what
--   the portal's login and apply pages and the University's website read: the state, the dates and
--   the message of each, for the session an application would be filed under today.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V312: the application registration windows', true);

-- ── 1 · two more window types, of the admission exercise ─────────────────────────────────────
ALTER TABLE policy.portal_window DROP CONSTRAINT IF EXISTS portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check
    CHECK (window_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION'));
ALTER TABLE policy.portal_window ADD CONSTRAINT ck_window_application_session
    CHECK (window_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION') OR (semester IS NULL AND late_until IS NULL AND NOT late_fee_enabled));
ALTER TABLE policy.portal_window_event DROP CONSTRAINT IF EXISTS portal_window_event_action_check;
ALTER TABLE policy.portal_window_event ADD CONSTRAINT portal_window_event_action_check
    CHECK (action IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT', 'MESSAGE'));

-- ── 2 · the state: the two application windows are open until the Director first acts ────────
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
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type = 'ADMISSION_STATUS_CHECKING' THEN 'CLOSED' ELSE 'OPEN' END
                WHEN w.forced = 'CLOSED' THEN 'CLOSED'
                WHEN w.forced = 'OPEN' THEN 'OPEN'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'SCHEDULED'
                WHEN w.closes_at IS NULL OR now() <= w.closes_at THEN 'OPEN'
                WHEN w.late_until IS NOT NULL AND now() <= w.late_until THEN 'OPEN'
                ELSE 'EXPIRED' END,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type = 'ADMISSION_STATUS_CHECKING' THEN 'NONE' ELSE 'NORMAL' END
                WHEN w.forced = 'OPEN' THEN CASE WHEN w.late_fee_enabled THEN 'LATE' ELSE 'NORMAL' END
                WHEN w.forced = 'CLOSED' THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at AND w.late_until IS NOT NULL AND now() <= w.late_until THEN 'LATE'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at THEN 'NONE'
                ELSE 'NORMAL' END,
           w.opens_at, w.closes_at, w.late_until, coalesce(w.late_fee_enabled, false), w.forced, w.reason, w.id, w.semester
      FROM (SELECT 1) one LEFT JOIN w ON true
$fn$;

-- ── 3 · the Director's act, now on five windows ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text,
                                             p_opens timestamptz, p_closes timestamptz, p_late_until timestamptz, p_late_fee boolean,
                                             p_reason text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type = 'ADMISSION_STATUS_CHECKING' AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: admission status checking opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
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
END $fn$;

-- ── 4 · the message the public reads while an application window is closed ──────────────────
CREATE TABLE policy.portal_window_message (
    window_type    text PRIMARY KEY CHECK (window_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION')),
    message        text NOT NULL CHECK (length(btrim(message)) BETWEEN 1 AND 2000),
    updated_by     uuid,
    updated_office text,
    updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE policy.portal_window_message IS
  'The Director of ICT''s closure message for each application window (V312): plain text, shown on the portal and read by the website while the window is closed, scheduled or expired.';
SELECT audit.attach('policy.portal_window_message');
GRANT SELECT, INSERT, UPDATE ON policy.portal_window_message TO app_student;

INSERT INTO policy.portal_window_message (window_type, message) VALUES
  ('POST_UTME_REGISTRATION',
   E'POST-UTME REGISTRATION IS CURRENTLY CLOSED\n\nThank you for your interest in Rev. Fr. Moses Orshio Adasu University, Makurdi.\n\nThe Post-UTME registration period has ended. Please check the University''s official website and this portal for announcements regarding the next application window.'),
  ('POSTGRADUATE_APPLICATION',
   E'POSTGRADUATE APPLICATION IS CURRENTLY CLOSED\n\nThank you for your interest in our postgraduate programmes.\n\nThe current application period has ended. Please check the University''s official website for information about the next application cycle.');

CREATE OR REPLACE FUNCTION policy.window_message_set(p_type text, p_message text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_old text; v_new text;
BEGIN
    IF p_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION') THEN RAISE EXCEPTION 'no closure message for %', p_type USING ERRCODE = '23514'; END IF;
    -- plain text only: tags are stripped, control characters other than the newline dropped (a CRLF becomes LF), whitespace trimmed
    v_new := btrim(regexp_replace(regexp_replace(coalesce(p_message, ''), '<[^>]*>', '', 'g'), '[\u0001-\u0008\u000B-\u001F\u007F]', '', 'g'));
    IF length(v_new) = 0 THEN RAISE EXCEPTION 'the closure message cannot be blank' USING ERRCODE = '23514'; END IF;
    IF length(v_new) > 2000 THEN RAISE EXCEPTION 'the closure message is at most 2000 characters' USING ERRCODE = '23514'; END IF;
    SELECT message INTO v_old FROM policy.portal_window_message WHERE window_type = p_type;
    INSERT INTO policy.portal_window_message (window_type, message, updated_by, updated_office, updated_at)
    VALUES (p_type, v_new, p_actor, p_office, now())
    ON CONFLICT (window_type) DO UPDATE SET message = EXCLUDED.message, updated_by = EXCLUDED.updated_by, updated_office = EXCLUDED.updated_office, updated_at = now();
    INSERT INTO policy.portal_window_event (window_type, session, action, previous_state, new_state, reason, actor, office)
    SELECT p_type, coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1), (SELECT max(name) FROM policy.academic_session)),
           'MESSAGE', left(v_old, 120), left(v_new, 120), 'closure message updated', p_actor, p_office
     WHERE EXISTS (SELECT 1 FROM policy.academic_session);
END $fn$;

-- ── 5 · the session an application is filed under today, and the public view of both windows ─
CREATE OR REPLACE FUNCTION policy.application_session(p_type text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN admissions.pg_current_session()
                ELSE coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1),
                              (SELECT max(name) FROM policy.academic_session WHERE state <> 'PLANNED'),
                              (SELECT max(name) FROM policy.academic_session)) END
$fn$;
COMMENT ON FUNCTION policy.application_session(text) IS
  'The session a new application of this kind would be filed under today (V312): the current academic session for Post-UTME; the postgraduate school''s current session for postgraduate.';

CREATE OR REPLACE FUNCTION policy.application_windows_public()
RETURNS TABLE(window_type text, session text, state text, opens_at timestamptz, closes_at timestamptz, message text)
LANGUAGE sql STABLE AS $fn$
    SELECT t.window_type, s.session, w.state, w.opens_at, w.closes_at, m.message
      FROM (VALUES ('POST_UTME_REGISTRATION'), ('POSTGRADUATE_APPLICATION')) t(window_type)
      CROSS JOIN LATERAL (SELECT policy.application_session(t.window_type) AS session) s
      CROSS JOIN LATERAL policy.window_state(t.window_type, s.session, NULL) w
      LEFT JOIN policy.portal_window_message m ON m.window_type = t.window_type
$fn$;
COMMENT ON FUNCTION policy.application_windows_public() IS
  'What the portal''s login and apply pages and the University''s website read (V312): each application window''s state for the session an application would be filed under today, its dates, and the closure message. Nothing private.';

-- ── 6 · the backstop: a new application is not born while its window is closed ───────────────
CREATE OR REPLACE FUNCTION policy.application_window_guard()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_type text := TG_ARGV[0]; v_state text;
BEGIN
    -- only the applicant registering themselves is held at the door; an office importing or correcting records is not
    IF coalesce(current_setting('moaum.actor_office', true), '') <> 'applicant' THEN RETURN NEW; END IF;
    SELECT state INTO v_state FROM policy.window_state(v_type, NEW.session, NULL);
    IF v_state <> 'OPEN' THEN
        RAISE EXCEPTION 'APPLICATION_CLOSED: % for % is % — no new application can be started until the Director of ICT opens it',
            CASE v_type WHEN 'POST_UTME_REGISTRATION' THEN 'Post-UTME registration' ELSE 'postgraduate application' END, NEW.session, lower(v_state)
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS trg_application_window_putme ON admissions.applicant_account;
CREATE TRIGGER trg_application_window_putme BEFORE INSERT ON admissions.applicant_account
    FOR EACH ROW EXECUTE FUNCTION policy.application_window_guard('POST_UTME_REGISTRATION');
DROP TRIGGER IF EXISTS trg_application_window_pg ON admissions.pg_application;
CREATE TRIGGER trg_application_window_pg BEFORE INSERT ON admissions.pg_application
    FOR EACH ROW EXECUTE FUNCTION policy.application_window_guard('POSTGRADUATE_APPLICATION');

COMMIT;
