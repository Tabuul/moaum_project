-- ═══════════════════════════════════════
-- V425 — the central notification engine: templates, the portal channel, one message per event, contacts checked before queuing
--
--   Every module already reaches a person through one outbox (platform.notice, queued by platform.queue_notice, sent by the
--   API's dispatcher over the mail account or the SMS account ICT configured). What was missing: the words were written
--   into fifty functions and the API; a message had no key, so a retried event could send twice; an address was never
--   looked at before it was tried; the portal itself was not a channel; a big send ran inside one request. This migration
--   adds the engine around the one outbox, and changes no module's business rule:
--
--   1. platform.notice_template — the editable texts, keyed by event (WINDOW_OPENED, BIODATA_REMINDER, PORTAL_MIGRATION,
--      ANNOUNCEMENT …), with [TOKENS] the sender fills, an e-mail, an SMS and a portal text each, a priority and whether
--      the message is mandatory (a mandatory one is never switched off by a preference). A variant key WINDOW_CLOSED:
--      SCHOOL_FEES_PAYMENT overrides the base key for that window type.
--   2. platform.notice gains the PORTAL channel (shown on the dashboard, read_at kept apart in platform.notice_read),
--      event_key (one message per event, per person, per channel — the unique index refuses the second), template_key,
--      priority. platform.queue_notice checks the address first: an e-mail that is not one or a phone that is not one is
--      recorded FAILED with INVALID_EMAIL / INVALID_PHONE and never tried; a missing address queues nothing, as before.
--   3. platform.render / notify / tell_student / tell_person — a template rendered for one person from the record (the
--      name, matric number, programme, session … and the University's name and portal address), queued on every channel
--      the template has.
--   4. platform.notice_job — a big send queued as a job the scheduler drains in batches (platform.run_notice_job): the
--      portal window messages (open, close, extend, reopen) now go this way, through the templates, to the same students
--      as before (the route's students, in the session).
--   5. people.biodata_status — UP_TO_DATE · INCOMPLETE · REVIEW_REQUIRED · OUTDATED on V423's completion and the student's
--      own confirmation (people.biodata_review, "my biodata is correct"); people.biodata_setting lets ICT run the weekly
--      reminder on its own, gate OFF, and state after how many days a record is OUTDATED; people.remind_biodata restated
--      (V423) to read the status and the BIODATA_REMINDER template — still at most once in seven days, still silent once
--      the record is up to date.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V425: the central notification engine — templates, the portal channel, one message per event', true);

-- ── 1 · the templates ─────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.notice_template (
    key            text PRIMARY KEY CHECK (key ~ '^[A-Z][A-Z0-9_]*(:[A-Z][A-Z0-9_]*)?$'),
    label          text NOT NULL,
    purpose        text NOT NULL,
    email_subject  text NULL,
    email_body     text NULL,
    sms_body       text NULL,
    portal_title   text NULL,
    portal_body    text NULL,
    variables      text[] NOT NULL DEFAULT '{}',
    mandatory      boolean NOT NULL DEFAULT true,
    priority       text NOT NULL DEFAULT 'NORMAL' CHECK (priority IN ('CRITICAL', 'HIGH', 'NORMAL', 'LOW')),
    enabled        boolean NOT NULL DEFAULT true,
    updated_by     uuid NULL,
    updated_office text NULL,
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_template_email  CHECK ((email_subject IS NULL) = (email_body IS NULL)),
    CONSTRAINT ck_template_portal CHECK ((portal_title IS NULL) = (portal_body IS NULL)),
    CONSTRAINT ck_template_some   CHECK (email_body IS NOT NULL OR sms_body IS NOT NULL OR portal_body IS NOT NULL)
);
SELECT audit.attach('platform.notice_template');
COMMENT ON TABLE platform.notice_template IS
  'V425: the texts the portal sends, keyed by event; [TOKENS] are filled from the record and the sender''s values. A key with a :VARIANT suffix (a window type) overrides the base key for that variant.';

CREATE TABLE platform.notice_setting (
    id             boolean PRIMARY KEY DEFAULT true CHECK (id),
    portal_url     text NULL,
    job_batch      int NOT NULL DEFAULT 2000 CHECK (job_batch BETWEEN 100 AND 20000),
    updated_by     uuid NULL,
    updated_office text NULL,
    updated_at     timestamptz NOT NULL DEFAULT now()
);
INSERT INTO platform.notice_setting (id) VALUES (true);
SELECT audit.attach('platform.notice_setting');
COMMENT ON TABLE platform.notice_setting IS 'V425: the portal address written into messages ([PORTAL_URL]) and how many people a notification job reaches per run.';

CREATE OR REPLACE FUNCTION platform.portal_url()
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(nullif(btrim(portal_url), ''), '') FROM platform.notice_setting WHERE id
$$;

CREATE OR REPLACE FUNCTION platform.set_portal_url(p_url text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_url IS NOT NULL AND btrim(p_url) <> '' AND btrim(p_url) !~ '^https?://[^[:space:]]+$' THEN
        RAISE EXCEPTION 'NOTICE_PORTAL_URL: the portal address starts with http:// or https://' USING ERRCODE = '23514';
    END IF;
    UPDATE platform.notice_setting
       SET portal_url = nullif(regexp_replace(btrim(coalesce(p_url, '')), '/+$', ''), ''), updated_by = p_actor, updated_office = p_office, updated_at = now()
     WHERE id;
END $$;

-- the template that applies: the variant for this window type, else the base; only an enabled one
CREATE OR REPLACE FUNCTION platform.template_for(p_key text, p_variant text)
RETURNS platform.notice_template LANGUAGE sql STABLE AS $$
    SELECT t FROM platform.notice_template t
     WHERE t.enabled AND t.key IN (p_key, p_key || ':' || coalesce(p_variant, ''), p_key || ':' || regexp_replace(coalesce(p_variant, ''), '^(CCE|PG)_', ''))
     ORDER BY CASE WHEN t.key = p_key || ':' || coalesce(p_variant, '') THEN 0
                   WHEN t.key = p_key || ':' || regexp_replace(coalesce(p_variant, ''), '^(CCE|PG)_', '') THEN 1 ELSE 2 END
     LIMIT 1
$$;

-- [TOKEN] replaced by the value given; a token nobody supplied becomes nothing, never stays in the text
CREATE OR REPLACE FUNCTION platform.render_text(p_text text, p_vars jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v_out text := p_text; v_tok text;
BEGIN
    IF p_text IS NULL THEN RETURN NULL; END IF;
    FOR v_tok IN SELECT DISTINCT m[1] FROM regexp_matches(p_text, '\[([A-Z][A-Z0-9_]*)\]', 'g') m LOOP
        v_out := replace(v_out, '[' || v_tok || ']', coalesce(p_vars ->> v_tok, ''));
    END LOOP;
    -- a sentence left empty by an absent token leaves no double space or stray " ." behind
    RETURN regexp_replace(regexp_replace(v_out, ' {2,}', ' ', 'g'), ' \.', '.', 'g');
END $$;

-- what every message may use without the sender saying so
CREATE OR REPLACE FUNCTION platform.standard_vars()
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'UNIVERSITY_NAME', coalesce((SELECT name FROM platform.institution_profile ORDER BY updated_at DESC LIMIT 1), 'the University'),
        'UNIVERSITY_SHORT', coalesce((SELECT nullif(short_name, '') FROM platform.institution_profile ORDER BY updated_at DESC LIMIT 1), 'MOAUM'),
        'PORTAL_URL', platform.portal_url(),
        'DATE', to_char(now() AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY'))
$$;

CREATE OR REPLACE FUNCTION platform.render(p_key text, p_variant text, p_channel text, p_vars jsonb)
RETURNS TABLE(subject text, body text) LANGUAGE plpgsql STABLE AS $$
DECLARE t platform.notice_template; v jsonb := platform.standard_vars() || coalesce(p_vars, '{}'::jsonb);
BEGIN
    t := platform.template_for(p_key, p_variant);
    IF t.key IS NULL THEN RETURN; END IF;
    IF p_channel = 'EMAIL' AND t.email_body IS NOT NULL THEN
        RETURN QUERY SELECT platform.render_text(t.email_subject, v), platform.render_text(t.email_body, v);
    ELSIF p_channel = 'SMS' AND t.sms_body IS NOT NULL THEN
        -- an SMS carries no subject; the outbox files it under the e-mail's, so one event reads alike on both channels
        RETURN QUERY SELECT platform.render_text(coalesce(t.email_subject, t.portal_title, t.label), v), platform.render_text(t.sms_body, v);
    ELSIF p_channel = 'PORTAL' AND t.portal_body IS NOT NULL THEN
        RETURN QUERY SELECT platform.render_text(t.portal_title, v), platform.render_text(t.portal_body, v);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION platform.save_template(p_key text, p_label text, p_purpose text, p_email_subject text, p_email_body text, p_sms_body text,
                                                  p_portal_title text, p_portal_body text, p_variables text[], p_mandatory boolean, p_priority text,
                                                  p_enabled boolean, p_actor uuid, p_office text)
RETURNS platform.notice_template LANGUAGE plpgsql AS $$
DECLARE t platform.notice_template;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'NOTICE_TEMPLATE_OFFICE: notification templates are edited by ICT or an administrator' USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_label, '')), '') IS NULL THEN
        RAISE EXCEPTION 'NOTICE_TEMPLATE_LABEL: a template has a name' USING ERRCODE = '23514';
    END IF;
    IF p_sms_body IS NOT NULL AND length(p_sms_body) > 320 THEN
        RAISE EXCEPTION 'NOTICE_TEMPLATE_SMS_LONG: an SMS text is at most 320 characters before the tokens are filled' USING ERRCODE = '23514';
    END IF;
    INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority, enabled,
                                          updated_by, updated_office, updated_at)
    VALUES (upper(btrim(p_key)), btrim(p_label), coalesce(btrim(p_purpose), ''), nullif(btrim(coalesce(p_email_subject, '')), ''), nullif(btrim(coalesce(p_email_body, '')), ''),
            nullif(btrim(coalesce(p_sms_body, '')), ''), nullif(btrim(coalesce(p_portal_title, '')), ''), nullif(btrim(coalesce(p_portal_body, '')), ''),
            coalesce(p_variables, '{}'), coalesce(p_mandatory, true), coalesce(upper(p_priority), 'NORMAL'), coalesce(p_enabled, true), p_actor, p_office, now())
    ON CONFLICT (key) DO UPDATE
       SET label = EXCLUDED.label, purpose = EXCLUDED.purpose, email_subject = EXCLUDED.email_subject, email_body = EXCLUDED.email_body,
           sms_body = EXCLUDED.sms_body, portal_title = EXCLUDED.portal_title, portal_body = EXCLUDED.portal_body,
           variables = CASE WHEN cardinality(EXCLUDED.variables) > 0 THEN EXCLUDED.variables ELSE platform.notice_template.variables END,
           mandatory = EXCLUDED.mandatory, priority = EXCLUDED.priority, enabled = EXCLUDED.enabled,
           updated_by = EXCLUDED.updated_by, updated_office = EXCLUDED.updated_office, updated_at = now()
    RETURNING * INTO t;
    RETURN t;
END $$;

-- ── 2 · the outbox: the portal channel, one message per event, the address checked ───────────────────────────────────
ALTER TABLE platform.notice DROP CONSTRAINT ck_notice_channel;
ALTER TABLE platform.notice ADD CONSTRAINT ck_notice_channel CHECK (channel IN ('EMAIL', 'SMS', 'PORTAL'));
ALTER TABLE platform.notice
    ADD COLUMN event_key    text NULL,
    ADD COLUMN template_key text NULL,
    ADD COLUMN priority     text NOT NULL DEFAULT 'NORMAL' CHECK (priority IN ('CRITICAL', 'HIGH', 'NORMAL', 'LOW'));
CREATE UNIQUE INDEX ux_notice_event ON platform.notice (event_key, channel, about_kind, about_id) WHERE event_key IS NOT NULL;
CREATE INDEX ix_notice_about_portal ON platform.notice (about_kind, about_id, created_at DESC) WHERE channel = 'PORTAL';
CREATE INDEX ix_notice_created ON platform.notice (created_at DESC);
COMMENT ON COLUMN platform.notice.event_key IS 'V425: the event this message answers; one message per event, per person, per channel (ux_notice_event) however often the event is raised';
COMMENT ON COLUMN platform.notice.template_key IS 'V425: the template the words came from, when they came from one';

-- a portal notice read: kept apart from the audited outbox row, so that a read is not an audit entry
CREATE TABLE platform.notice_read (
    notice_id uuid PRIMARY KEY REFERENCES platform.notice(id) ON DELETE CASCADE,
    read_at   timestamptz NOT NULL DEFAULT now()
);
SELECT audit.exempt('platform.notice_read', 'when a portal notice was read by the person it is about; written by the person, read for the unread count');

CREATE OR REPLACE FUNCTION platform.email_valid(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p IS NOT NULL AND length(p) <= 320 AND p ~ '^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z0-9-]{2,}$'
$$;
-- a Nigerian number as the portal takes it: 0 and ten digits, or 234 and ten digits (spaces, dashes and a leading + ignored)
CREATE OR REPLACE FUNCTION platform.phone_valid(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') ~ '^(0[0-9]{10}|234[0-9]{10})$'
$$;

CREATE OR REPLACE FUNCTION platform.queue_notice(p_channel text, p_recipient text, p_subject text, p_body text, p_about_kind text, p_about_id uuid,
                                                 p_event_key text, p_template_key text, p_priority text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid(); v_to text; v_state text := 'QUEUED'; v_err text := NULL; v_sent timestamptz := NULL;
BEGIN
    IF p_channel = 'PORTAL' THEN
        IF p_about_id IS NULL THEN RETURN NULL; END IF;
        v_to := coalesce(nullif(btrim(coalesce(p_recipient, '')), ''), coalesce(p_about_kind, 'portal') || ':' || p_about_id);
        v_state := 'SENT'; v_sent := now();
    ELSE
        v_to := nullif(btrim(coalesce(p_recipient, '')), '');
        IF v_to IS NULL THEN RETURN NULL; END IF;
        IF p_channel = 'EMAIL' AND NOT platform.email_valid(v_to) THEN
            v_state := 'FAILED'; v_err := 'INVALID_EMAIL';
        ELSIF p_channel = 'SMS' AND NOT platform.phone_valid(v_to) THEN
            v_state := 'FAILED'; v_err := 'INVALID_PHONE';
        END IF;
    END IF;
    INSERT INTO platform.notice (id, channel, recipient, subject, body, about_kind, about_id, state, sent_at, last_error, event_key, template_key, priority)
    VALUES (v, p_channel, v_to, p_subject, p_body, p_about_kind, p_about_id, v_state, v_sent, v_err,
            nullif(btrim(coalesce(p_event_key, '')), ''), p_template_key, coalesce(upper(p_priority), 'NORMAL'))
    ON CONFLICT (event_key, channel, about_kind, about_id) WHERE event_key IS NOT NULL DO NOTHING;
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN v;
END $$;
COMMENT ON FUNCTION platform.queue_notice(text, text, text, text, text, uuid, text, text, text) IS
  'V425: queues one message; an address that is not one is recorded FAILED (INVALID_EMAIL / INVALID_PHONE) and never tried; a portal notice is delivered at once; an event key makes the message happen once per person and channel.';

-- the six-argument form every module calls: the same, with no event key
CREATE OR REPLACE FUNCTION platform.queue_notice(p_channel text, p_recipient text, p_subject text, p_body text, p_about_kind text, p_about_id uuid)
RETURNS uuid LANGUAGE sql AS $$
    SELECT platform.queue_notice(p_channel, p_recipient, p_subject, p_body, p_about_kind, p_about_id, NULL, NULL, NULL)
$$;

CREATE OR REPLACE FUNCTION platform.mark_notice_read(p_notice uuid, p_about_kind text, p_about_id uuid)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM platform.notice n WHERE n.id = p_notice AND n.channel = 'PORTAL' AND n.about_kind = p_about_kind AND n.about_id = p_about_id) THEN
        RETURN false;
    END IF;
    INSERT INTO platform.notice_read (notice_id) VALUES (p_notice) ON CONFLICT (notice_id) DO NOTHING;
    RETURN true;
END $$;

CREATE OR REPLACE FUNCTION platform.mark_all_read(p_about_kind text, p_about_id uuid)
RETURNS int LANGUAGE sql AS $$
    WITH ins AS (
        INSERT INTO platform.notice_read (notice_id)
        SELECT n.id FROM platform.notice n
         WHERE n.channel = 'PORTAL' AND n.about_kind = p_about_kind AND n.about_id = p_about_id
           AND NOT EXISTS (SELECT 1 FROM platform.notice_read r WHERE r.notice_id = n.id)
        ON CONFLICT DO NOTHING RETURNING 1)
    SELECT count(*)::int FROM ins
$$;

-- the person's own portal notices, newest first, with whether each was read
CREATE OR REPLACE FUNCTION platform.portal_notices(p_about_kind text, p_about_id uuid, p_limit int DEFAULT 50)
RETURNS TABLE(id uuid, subject text, body text, priority text, template_key text, created_at timestamptz, read_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT n.id, n.subject, n.body, n.priority, n.template_key, n.created_at, r.read_at
      FROM platform.notice n LEFT JOIN platform.notice_read r ON r.notice_id = n.id
     WHERE n.channel = 'PORTAL' AND n.about_kind = p_about_kind AND n.about_id = p_about_id
     ORDER BY n.created_at DESC LIMIT greatest(1, p_limit)
$$;

CREATE OR REPLACE FUNCTION platform.unread_count(p_about_kind text, p_about_id uuid)
RETURNS int LANGUAGE sql STABLE AS $$
    SELECT count(*)::int FROM platform.notice n
     WHERE n.channel = 'PORTAL' AND n.about_kind = p_about_kind AND n.about_id = p_about_id
       AND NOT EXISTS (SELECT 1 FROM platform.notice_read r WHERE r.notice_id = n.id)
$$;

-- ── 3 · a template rendered for one person ───────────────────────────────────────────────────────────────────────────
-- queues the template on every channel it has for which the person has an address; returns how many were queued
CREATE OR REPLACE FUNCTION platform.notify(p_key text, p_variant text, p_vars jsonb, p_about_kind text, p_about_id uuid,
                                           p_email text, p_phone text, p_event_key text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE t platform.notice_template; r record; v uuid; n int := 0;
BEGIN
    t := platform.template_for(p_key, p_variant);
    IF t.key IS NULL THEN RETURN 0; END IF;
    -- counted: a message queued or delivered — not one recorded FAILED for an address that is not one, nor one the event key refused
    IF t.email_body IS NOT NULL AND nullif(btrim(coalesce(p_email, '')), '') IS NOT NULL THEN
        SELECT * INTO r FROM platform.render(p_key, p_variant, 'EMAIL', p_vars);
        v := platform.queue_notice('EMAIL', p_email, r.subject, r.body, p_about_kind, p_about_id, p_event_key, t.key, t.priority);
        IF v IS NOT NULL AND EXISTS (SELECT 1 FROM platform.notice x WHERE x.id = v AND x.state <> 'FAILED') THEN n := n + 1; END IF;
    END IF;
    IF t.sms_body IS NOT NULL AND nullif(btrim(coalesce(p_phone, '')), '') IS NOT NULL THEN
        SELECT * INTO r FROM platform.render(p_key, p_variant, 'SMS', p_vars);
        v := platform.queue_notice('SMS', p_phone, r.subject, r.body, p_about_kind, p_about_id, p_event_key, t.key, t.priority);
        IF v IS NOT NULL AND EXISTS (SELECT 1 FROM platform.notice x WHERE x.id = v AND x.state <> 'FAILED') THEN n := n + 1; END IF;
    END IF;
    IF t.portal_body IS NOT NULL AND p_about_id IS NOT NULL THEN
        SELECT * INTO r FROM platform.render(p_key, p_variant, 'PORTAL', p_vars);
        v := platform.queue_notice('PORTAL', NULL, r.subject, r.body, p_about_kind, p_about_id, p_event_key, t.key, t.priority);
        IF v IS NOT NULL THEN n := n + 1; END IF;
    END IF;
    RETURN n;
END $$;

-- what the record says about a student, for the tokens: the sender's values win over the record's
CREATE OR REPLACE FUNCTION platform.student_vars(p_student uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'FIRST_NAME', coalesce(nullif(split_part(s.other_names, ' ', 1), ''), s.surname),
        'LAST_NAME', s.surname,
        'FULL_NAME', s.surname || ', ' || s.other_names,
        'MATRIC_NUMBER', s.matric_no,
        'JAMB_NUMBER', s.jamb_reg_no,
        'APPLICATION_NUMBER', s.admission_no,
        'LOGIN_ID', coalesce(s.matric_no, s.jamb_reg_no, s.admission_no),
        'PROGRAMME', p.name,
        'DEPARTMENT', d.name,
        'FACULTY', f.name,
        'LEVEL', s.current_level::text,
        'SESSION', CASE WHEN s.entry_mode = 'CCE' THEN policy.route_session('CCE')
                        WHEN s.entry_mode = 'POSTGRADUATE' THEN admissions.pg_current_session()
                        ELSE policy.university_current_session() END))
      FROM people.student s
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE s.id = p_student
$$;

CREATE OR REPLACE FUNCTION platform.tell_student(p_student uuid, p_key text, p_variant text, p_vars jsonb, p_event_key text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM people.student_reach(p_student);
    IF NOT FOUND THEN RETURN 0; END IF;
    RETURN platform.notify(p_key, p_variant, platform.student_vars(p_student) || coalesce(p_vars, '{}'::jsonb), 'student', p_student, r.email, r.phone, p_event_key);
END $$;
COMMENT ON FUNCTION platform.tell_student(uuid, text, text, jsonb, text) IS
  'V425: a template rendered for one student from the register and the sender''s values, queued by e-mail, SMS and on the portal (each where the template has a text and the student an address); once per event key.';

CREATE OR REPLACE FUNCTION platform.person_vars(p_person uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'FIRST_NAME', coalesce(nullif(split_part(p.given_names, ' ', 1), ''), p.surname),
        'LAST_NAME', p.surname,
        'FULL_NAME', p.surname || ', ' || p.given_names,
        'STAFF_NUMBER', p.staff_number,
        'LOGIN_ID', p.staff_number))
      FROM iam.person p WHERE p.id = p_person
$$;

CREATE OR REPLACE FUNCTION platform.tell_person(p_person uuid, p_key text, p_variant text, p_vars jsonb, p_event_key text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE p record;
BEGIN
    SELECT email, phone INTO p FROM iam.person WHERE id = p_person AND ended_on IS NULL;
    IF NOT FOUND THEN RETURN 0; END IF;
    RETURN platform.notify(p_key, p_variant, platform.person_vars(p_person) || coalesce(p_vars, '{}'::jsonb), 'person', p_person, p.email, p.phone, p_event_key);
END $$;

-- a staff member's e-mail and phone are the person's: what they write on their profile is what the portal reaches them by
CREATE OR REPLACE FUNCTION hrm.staff_profile_contact()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE iam.person
       SET email = CASE WHEN nullif(btrim(coalesce(NEW.email, '')), '') IS NOT NULL THEN btrim(NEW.email) ELSE email END,
           phone = CASE WHEN nullif(btrim(coalesce(NEW.phone, '')), '') IS NOT NULL THEN btrim(NEW.phone) ELSE phone END
     WHERE id = NEW.person_id
       AND (email IS DISTINCT FROM nullif(btrim(coalesce(NEW.email, '')), '') AND nullif(btrim(coalesce(NEW.email, '')), '') IS NOT NULL
            OR phone IS DISTINCT FROM nullif(btrim(coalesce(NEW.phone, '')), '') AND nullif(btrim(coalesce(NEW.phone, '')), '') IS NOT NULL);
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_staff_profile_contact ON hrm.staff_profile;
CREATE TRIGGER trg_staff_profile_contact AFTER INSERT OR UPDATE OF email, phone ON hrm.staff_profile
    FOR EACH ROW EXECUTE FUNCTION hrm.staff_profile_contact();

-- ── 4 · big sends as jobs the scheduler drains ───────────────────────────────────────────────────────────────────────
CREATE TABLE platform.notice_job (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind           text NOT NULL CHECK (kind IN ('WINDOW', 'CAMPAIGN', 'BIODATA_REMINDER')),
    payload        jsonb NOT NULL DEFAULT '{}',
    state          text NOT NULL DEFAULT 'QUEUED' CHECK (state IN ('QUEUED', 'RUNNING', 'DONE', 'FAILED')),
    created_at     timestamptz NOT NULL DEFAULT now(),
    created_by     uuid NULL,
    created_office text NULL,
    started_at     timestamptz NULL,
    finished_at    timestamptz NULL,
    cursor_id      uuid NULL,
    reached        int NOT NULL DEFAULT 0,
    queued         int NOT NULL DEFAULT 0,
    runs           int NOT NULL DEFAULT 0,
    error          text NULL
);
CREATE INDEX ix_notice_job_open ON platform.notice_job (created_at) WHERE state IN ('QUEUED', 'RUNNING');
SELECT audit.attach('platform.notice_job');
COMMENT ON TABLE platform.notice_job IS
  'V425: a send too big for one request — a portal window message to a session''s students, a campaign — drained by the scheduler in batches (platform.run_notice_job), the cursor kept so a restart resumes rather than repeats.';

CREATE OR REPLACE FUNCTION policy.window_word(p_type text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_type
        WHEN 'SCHOOL_FEES_PAYMENT' THEN 'School fees payment'
        WHEN 'COURSE_REGISTRATION' THEN 'Course registration'
        WHEN 'ADMISSION_STATUS_CHECKING' THEN 'Admission status checking'
        WHEN 'POST_UTME_REGISTRATION' THEN 'Post-UTME registration'
        WHEN 'POSTGRADUATE_APPLICATION' THEN 'Postgraduate application'
        WHEN 'POSTGRADUATE_ADMISSION_STATUS_CHECKING' THEN 'Postgraduate admission status checking'
        WHEN 'JUPEB_APPLICATION' THEN 'JUPEB application'
        WHEN 'JUPEB_ADMISSION_STATUS_CHECKING' THEN 'JUPEB admission status checking'
        WHEN 'CCE_APPLICATION' THEN 'CCE application'
        WHEN 'CCE_SCHOOL_FEES_PAYMENT' THEN 'CCE school fees payment'
        WHEN 'CCE_COURSE_REGISTRATION' THEN 'CCE course registration'
        WHEN 'POST_UTME_CBT' THEN 'Post-UTME CBT'
        WHEN 'POST_UTME_RESULT_CHECKING' THEN 'Post-UTME result checking'
        WHEN 'PG_SCHOOL_FEES_PAYMENT' THEN 'Postgraduate school fees payment'
        WHEN 'PG_COURSE_REGISTRATION' THEN 'Postgraduate course registration'
        ELSE initcap(replace(lower(p_type), '_', ' ')) END
$$;

-- the students a window's message is for: the route's students (CCE_, PG_, else every other), in the session
CREATE OR REPLACE FUNCTION policy.window_audience(p_type text, p_session text, p_after uuid, p_limit int)
RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
    SELECT st.id FROM people.student st
     WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
       AND CASE WHEN p_type LIKE 'CCE\_%' THEN st.entry_mode = 'CCE'
                WHEN p_type LIKE 'PG\_%' THEN st.entry_mode = 'POSTGRADUATE'
                ELSE coalesce(st.entry_mode, '') NOT IN ('CCE', 'POSTGRADUATE') END
       AND (st.entry_session = p_session
            OR EXISTS (SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = st.id AND cr.session = p_session)
            OR EXISTS (SELECT 1 FROM finance.payment_reference p WHERE p.student_id = st.id AND p.session = p_session))
       AND (p_after IS NULL OR st.id > p_after)
     ORDER BY st.id
     LIMIT greatest(1, p_limit)
$$;

-- the window's message queued as a job; the event it answers is the latest one recorded for the window
CREATE OR REPLACE FUNCTION platform.queue_window_job(p_type text, p_session text, p_semester int, p_action text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_event uuid; v_job uuid; w record;
BEGIN
    IF p_action NOT IN ('OPEN', 'REOPEN', 'EXTEND', 'CLOSE') THEN RETURN NULL; END IF;
    SELECT e.id INTO v_event FROM policy.portal_window_event e
     WHERE e.window_type = p_type AND e.session = p_session AND e.semester IS NOT DISTINCT FROM p_semester
     ORDER BY e.at DESC LIMIT 1;
    SELECT * INTO w FROM policy.window_state(p_type, p_session, p_semester);
    INSERT INTO platform.notice_job (kind, payload, created_by, created_office)
    VALUES ('WINDOW', jsonb_strip_nulls(jsonb_build_object(
                'type', p_type, 'session', p_session, 'semester', p_semester, 'action', p_action, 'event_id', v_event,
                'closes_at', w.closes_at, 'late_until', w.late_until, 'phase', w.phase, 'reason', w.reason)),
            p_actor, p_office)
    RETURNING id INTO v_job;
    RETURN v_job;
END $$;

CREATE OR REPLACE FUNCTION platform.window_vars(p jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'WINDOW', policy.window_word(p ->> 'type'),
        'SESSION', p ->> 'session',
        'SEMESTER', CASE WHEN p ->> 'semester' IS NULL THEN '' ELSE ', semester ' || (p ->> 'semester') END,
        'START_DATE', '',
        'END_DATE', CASE WHEN p ->> 'closes_at' IS NULL THEN '' ELSE to_char((p ->> 'closes_at')::timestamptz AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') END,
        'CLOSES_NOTE', CASE WHEN p ->> 'closes_at' IS NULL THEN '' ELSE 'It closes on ' || to_char((p ->> 'closes_at')::timestamptz AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.' END,
        'LATE_NOTE', CASE WHEN p ->> 'late_until' IS NULL THEN ''
                          ELSE 'Late ' || CASE WHEN (p ->> 'type') LIKE '%SCHOOL_FEES_PAYMENT' THEN 'payment' ELSE 'registration' END
                               || ' runs until ' || to_char((p ->> 'late_until')::timestamptz AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.' END,
        'PHASE_NOTE', CASE WHEN p ->> 'phase' = 'LATE' THEN 'You are now in the late period.' ELSE '' END,
        'REASON', coalesce(p ->> 'reason', ''))
$$;

-- one run of the oldest open job: up to p_limit people, the cursor kept; the job is DONE when a run finds nobody further
CREATE OR REPLACE FUNCTION platform.run_notice_job(p_limit int DEFAULT NULL)
RETURNS TABLE(job_id uuid, kind text, reached int, queued int, done boolean)
LANGUAGE plpgsql AS $$
DECLARE j record; v_limit int := coalesce(p_limit, (SELECT job_batch FROM platform.notice_setting WHERE id), 2000);
        v_key text; v_vars jsonb; v_event text; s uuid; v_reached int := 0; v_queued int := 0; v_last uuid;
BEGIN
    SELECT * INTO j FROM platform.notice_job x WHERE x.state IN ('QUEUED', 'RUNNING') ORDER BY x.created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN; END IF;
    UPDATE platform.notice_job SET state = 'RUNNING', started_at = coalesce(started_at, now()), runs = runs + 1 WHERE id = j.id;
    BEGIN
        IF j.kind = 'WINDOW' THEN
            v_key := 'WINDOW_' || CASE j.payload ->> 'action' WHEN 'OPEN' THEN 'OPENED' WHEN 'REOPEN' THEN 'REOPENED' WHEN 'EXTEND' THEN 'EXTENDED' ELSE 'CLOSED' END;
            v_vars := platform.window_vars(j.payload);
            v_event := 'window:' || coalesce(j.payload ->> 'event_id', j.id::text) || ':' || (j.payload ->> 'action');
            FOR s IN SELECT * FROM policy.window_audience(j.payload ->> 'type', j.payload ->> 'session', j.cursor_id, v_limit) LOOP
                v_queued := v_queued + platform.tell_student(s, v_key, j.payload ->> 'type', v_vars, v_event);
                v_reached := v_reached + 1; v_last := s;
            END LOOP;
        ELSE
            RAISE EXCEPTION 'NOTICE_JOB_KIND: no runner for a % job yet', j.kind USING ERRCODE = '23514';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        UPDATE platform.notice_job SET state = 'FAILED', error = left(SQLERRM, 400), finished_at = now() WHERE id = j.id;
        RETURN QUERY SELECT j.id, j.kind, 0, 0, true;
        RETURN;
    END;
    UPDATE platform.notice_job
       SET cursor_id = coalesce(v_last, cursor_id), reached = platform.notice_job.reached + v_reached, queued = platform.notice_job.queued + v_queued,
           state = CASE WHEN v_reached < v_limit THEN 'DONE' ELSE 'RUNNING' END,
           finished_at = CASE WHEN v_reached < v_limit THEN now() END
     WHERE id = j.id;
    RETURN QUERY SELECT j.id, j.kind, v_reached, v_queued, v_reached < v_limit;
END $$;
COMMENT ON FUNCTION platform.run_notice_job(int) IS
  'V425: drains the oldest open notification job by one batch (the setting''s size unless given); run by the API every half-minute; a job that raises is FAILED with the error kept.';

-- ── 5 · the student''s biodata status, their confirmation, the reminder on its own switch ─────────────────────────────
CREATE TABLE people.biodata_setting (
    id             boolean PRIMARY KEY DEFAULT true CHECK (id),
    remind_enabled boolean NOT NULL DEFAULT false,
    review_days    int NULL CHECK (review_days IS NULL OR review_days BETWEEN 30 AND 3650),
    updated_by     uuid NULL,
    updated_office text NULL,
    updated_at     timestamptz NOT NULL DEFAULT now()
);
INSERT INTO people.biodata_setting (id) VALUES (true);
SELECT audit.attach('people.biodata_setting');
COMMENT ON TABLE people.biodata_setting IS
  'V425: whether the weekly biodata reminder runs while the gate is OFF (remind_enabled), and after how many days without a change or a confirmation a record is OUTDATED (review_days; null = never).';

CREATE OR REPLACE FUNCTION people.set_biodata_setting(p_remind boolean, p_review_days int, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'BIO_SETTING_OFFICE: the biodata reminder is set by ICT or an administrator' USING ERRCODE = '23514';
    END IF;
    UPDATE people.biodata_setting SET remind_enabled = coalesce(p_remind, remind_enabled), review_days = p_review_days,
           updated_by = p_actor, updated_office = p_office, updated_at = now() WHERE id;
END $$;

-- the student's word that the record is correct as it stands
CREATE TABLE people.biodata_review (
    student_id   uuid PRIMARY KEY REFERENCES people.student(id) ON DELETE CASCADE,
    confirmed_at timestamptz NOT NULL DEFAULT now(),
    confirmed_by uuid NULL
);
SELECT audit.attach('people.biodata_review');

CREATE OR REPLACE FUNCTION people.confirm_biodata(p_student uuid, p_actor uuid)
RETURNS timestamptz LANGUAGE plpgsql AS $$
DECLARE c record; v_at timestamptz;
BEGIN
    SELECT * INTO c FROM people.biodata_completion(ARRAY[p_student]);
    IF c.student_id IS NULL THEN
        RAISE EXCEPTION 'BIO_NO_STUDENT: no such student' USING ERRCODE = '23514';
    END IF;
    IF NOT c.complete THEN
        RAISE EXCEPTION 'BIODATA_INCOMPLETE: % required item(s) still missing: %', c.required - c.completed, array_to_string(c.missing_labels, ', ') USING ERRCODE = '23514';
    END IF;
    INSERT INTO people.biodata_review (student_id, confirmed_at, confirmed_by) VALUES (p_student, now(), p_actor)
    ON CONFLICT (student_id) DO UPDATE SET confirmed_at = now(), confirmed_by = EXCLUDED.confirmed_by
    RETURNING confirmed_at INTO v_at;
    RETURN v_at;
END $$;

-- a student's biodata status: INCOMPLETE while a required item is missing; OUTDATED past the review period; REVIEW_REQUIRED
-- for a record that came over from the old portal (on the register with a matriculation number the portal never issued)
-- that the student has neither written to nor confirmed since; else UP_TO_DATE. A biodata row written before V423 carries no
-- time, so "written to since" is a row with one; the contact row's time is not read, the import stamps it too.
CREATE OR REPLACE FUNCTION people.biodata_statuses(p_students uuid[])
RETURNS TABLE(student_id uuid, status text, required int, completed int, missing text[], missing_labels text[],
              last_updated timestamptz, confirmed_at timestamptz, migrated boolean, last_reminded_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH st AS (SELECT review_days FROM people.biodata_setting WHERE id),
         w AS (SELECT b.student_id, max(b.updated_at) AS written_at FROM people.biodata b WHERE b.student_id IN (SELECT unnest(p_students)) GROUP BY b.student_id)
    SELECT c.student_id,
           CASE WHEN NOT c.complete THEN 'INCOMPLETE'
                WHEN st.review_days IS NOT NULL
                     AND coalesce(greatest(w.written_at, r.confirmed_at), w.written_at, r.confirmed_at, c.last_updated) < now() - make_interval(days => st.review_days) THEN 'OUTDATED'
                WHEN r.confirmed_at IS NULL AND w.written_at IS NULL AND (s.matric_no IS NOT NULL AND s.matriculation_run IS NULL) THEN 'REVIEW_REQUIRED'
                ELSE 'UP_TO_DATE' END,
           c.required, c.completed, c.missing, c.missing_labels, coalesce(greatest(c.last_updated, w.written_at), c.last_updated, w.written_at), r.confirmed_at,
           (s.matric_no IS NOT NULL AND s.matriculation_run IS NULL) AS migrated,
           m.last_sent_at
      FROM people.biodata_completion(p_students) c
      JOIN people.student s ON s.id = c.student_id
      LEFT JOIN w ON w.student_id = c.student_id
      LEFT JOIN people.biodata_review r ON r.student_id = c.student_id
      LEFT JOIN people.biodata_reminder m ON m.student_id = c.student_id
      CROSS JOIN st
$$;
COMMENT ON FUNCTION people.biodata_statuses(uuid[]) IS
  'V425: UP_TO_DATE · INCOMPLETE · REVIEW_REQUIRED · OUTDATED for a list of students at once, on V423''s completion and the student''s own confirmation.';

CREATE OR REPLACE FUNCTION people.biodata_status(p_student uuid)
RETURNS TABLE(student_id uuid, status text, required int, completed int, missing text[], missing_labels text[],
              last_updated timestamptz, confirmed_at timestamptz, migrated boolean, last_reminded_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT * FROM people.biodata_statuses(ARRAY[p_student])
$$;

-- the counts an office reads: how the students on the register stand
CREATE OR REPLACE FUNCTION people.biodata_status_counts()
RETURNS TABLE(total int, up_to_date int, incomplete int, review_required int, outdated int, no_email int, no_phone int, migrated int)
LANGUAGE sql STABLE AS $$
    WITH ids AS (SELECT array_agg(id) AS a FROM people.student s WHERE people.biodata_applicable(s.status)),
         x AS (SELECT * FROM people.biodata_statuses((SELECT a FROM ids)))
    SELECT (SELECT coalesce(cardinality(a), 0) FROM ids),
           count(*) FILTER (WHERE x.status = 'UP_TO_DATE')::int,
           count(*) FILTER (WHERE x.status = 'INCOMPLETE')::int,
           count(*) FILTER (WHERE x.status = 'REVIEW_REQUIRED')::int,
           count(*) FILTER (WHERE x.status = 'OUTDATED')::int,
           (SELECT count(*)::int FROM people.student s CROSS JOIN LATERAL people.student_reach(s.id) r WHERE people.biodata_applicable(s.status) AND nullif(btrim(coalesce(r.email, '')), '') IS NULL),
           (SELECT count(*)::int FROM people.student s CROSS JOIN LATERAL people.student_reach(s.id) r WHERE people.biodata_applicable(s.status) AND nullif(btrim(coalesce(r.phone, '')), '') IS NULL),
           count(*) FILTER (WHERE x.migrated)::int
      FROM x
$$;

-- V423's weekly reminder, restated: it runs while the gate is ON or the reminder switch is; it reads the status, so a record
-- that is complete but never reviewed is reminded too; the words come from the BIODATA_REMINDER template; one message a week.
CREATE OR REPLACE FUNCTION people.remind_biodata(p_limit int DEFAULT 3000)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0; v_q int; v_week text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'IYYY-"W"IW');
BEGIN
    IF NOT coalesce((SELECT enabled FROM people.biodata_gate LIMIT 1), false)
       AND NOT coalesce((SELECT remind_enabled FROM people.biodata_setting WHERE id), false) THEN
        RETURN 0;
    END IF;
    FOR r IN
        WITH cand AS (
            SELECT s.id FROM people.student s
             WHERE people.biodata_applicable(s.status)
               AND EXISTS (SELECT 1 FROM iam.student_account a WHERE a.student_id = s.id)
               AND NOT EXISTS (SELECT 1 FROM people.biodata_reminder m WHERE m.student_id = s.id AND m.last_sent_at > now() - interval '7 days')
        )
        SELECT x.student_id, x.status, x.missing_labels, x.completed, x.required
          FROM people.biodata_statuses((SELECT coalesce(array_agg(id), '{}'::uuid[]) FROM cand)) x
          LEFT JOIN people.biodata_reminder m ON m.student_id = x.student_id
         WHERE x.status <> 'UP_TO_DATE'
         ORDER BY m.last_sent_at NULLS FIRST, x.student_id
         LIMIT greatest(1, p_limit)
    LOOP
        v_q := platform.tell_student(r.student_id, 'BIODATA_REMINDER', NULL, jsonb_build_object(
                   'FIELD_LIST', CASE WHEN cardinality(coalesce(r.missing_labels, '{}')) = 0 THEN '' ELSE array_to_string(r.missing_labels, ', ') END,
                   'MISSING_COUNT', (r.required - r.completed)::text,
                   'STATUS_NOTE', CASE r.status WHEN 'INCOMPLETE' THEN (r.required - r.completed) || ' required item' || CASE WHEN r.required - r.completed = 1 THEN '' ELSE 's' END || ' still missing: ' || array_to_string(r.missing_labels, ', ') || '.'
                                                WHEN 'OUTDATED' THEN 'Your record has not been reviewed for some time. Please confirm it is still correct.'
                                                ELSE 'Your record came over from the old portal. Please review it and confirm it is correct.' END),
                   'biodata:' || v_week || ':' || r.student_id);
        INSERT INTO people.biodata_reminder (student_id, last_sent_at, sent, queued) VALUES (r.student_id, now(), 1, v_q)
        ON CONFLICT (student_id) DO UPDATE SET last_sent_at = now(), sent = people.biodata_reminder.sent + 1, queued = EXCLUDED.queued;
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION people.remind_biodata(int) IS
  'V425 (V423 restated): while the gate is ON or the reminder switch is, tells each student whose biodata is not up to date (incomplete, never reviewed since migration, or outdated) through the BIODATA_REMINDER template — at most once in seven days; silent once the record is up to date.';

-- ── 6 · the texts ─────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('WINDOW_OPENED', 'Portal window opened', 'Sent to the students of the session when ICT opens a window (course registration, school fees payment, …). A key WINDOW_OPENED:COURSE_REGISTRATION overrides it for that window.',
 '[WINDOW] for [SESSION][SEMESTER] is open',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION][SEMESTER] is now open. [CLOSES_NOTE] [LATE_NOTE] [PHASE_NOTE]\n\nSign in to the portal to proceed: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: [WINDOW] for [SESSION][SEMESTER] is open. [CLOSES_NOTE] Sign in: [PORTAL_URL]',
 '[WINDOW] is open', '[WINDOW] for [SESSION][SEMESTER] is now open. [CLOSES_NOTE] [LATE_NOTE] [PHASE_NOTE]',
 ARRAY['FIRST_NAME','LAST_NAME','FULL_NAME','MATRIC_NUMBER','WINDOW','SESSION','SEMESTER','END_DATE','CLOSES_NOTE','LATE_NOTE','PHASE_NOTE','REASON','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_REOPENED', 'Portal window reopened', 'Sent to the students of the session when ICT reopens a closed window.',
 '[WINDOW] for [SESSION][SEMESTER] is open again',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION][SEMESTER] has been reopened. [CLOSES_NOTE] [LATE_NOTE] [PHASE_NOTE]\n\nSign in to the portal to proceed: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: [WINDOW] for [SESSION][SEMESTER] is open again. [CLOSES_NOTE] Sign in: [PORTAL_URL]',
 '[WINDOW] reopened', '[WINDOW] for [SESSION][SEMESTER] has been reopened. [CLOSES_NOTE] [LATE_NOTE] [PHASE_NOTE]',
 ARRAY['FIRST_NAME','WINDOW','SESSION','SEMESTER','END_DATE','CLOSES_NOTE','LATE_NOTE','PHASE_NOTE','REASON','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_EXTENDED', 'Portal window extended', 'Sent to the students of the session when ICT extends a window.',
 '[WINDOW] for [SESSION][SEMESTER] is extended',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION][SEMESTER] has been extended. [CLOSES_NOTE] [LATE_NOTE] [PHASE_NOTE]\n\nSign in to the portal to proceed: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: [WINDOW] for [SESSION][SEMESTER] is extended. [CLOSES_NOTE] Sign in: [PORTAL_URL]',
 '[WINDOW] extended', '[WINDOW] for [SESSION][SEMESTER] has been extended. [CLOSES_NOTE] [LATE_NOTE] [PHASE_NOTE]',
 ARRAY['FIRST_NAME','WINDOW','SESSION','SEMESTER','END_DATE','CLOSES_NOTE','LATE_NOTE','PHASE_NOTE','REASON','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_CLOSED', 'Portal window closed', 'Sent to the students of the session when ICT closes a window before its time.',
 '[WINDOW] for [SESSION][SEMESTER] is closed',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION][SEMESTER] is closed from now. [REASON]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: [WINDOW] for [SESSION][SEMESTER] is closed from now.',
 '[WINDOW] closed', '[WINDOW] for [SESSION][SEMESTER] is closed from now. [REASON]',
 ARRAY['FIRST_NAME','WINDOW','SESSION','SEMESTER','REASON','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_CLOSED:SCHOOL_FEES_PAYMENT', 'School fees payment closed', 'The closing message for the school fees payment windows (the University''s, the Centre''s and the School''s): a reference already generated may still be paid.',
 '[WINDOW] for [SESSION] is closed',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION] is closed from now. [REASON] A fee reference already generated may still be paid; no new reference is generated until the window reopens.\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: [WINDOW] for [SESSION] is closed from now. A reference already generated may still be paid.',
 '[WINDOW] closed', '[WINDOW] for [SESSION] is closed from now. [REASON] A fee reference already generated may still be paid; no new reference is generated until the window reopens.',
 ARRAY['FIRST_NAME','WINDOW','SESSION','REASON','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_CLOSED:COURSE_REGISTRATION', 'Course registration closed', 'The closing message for the course registration windows: nothing is drafted or submitted until it reopens.',
 '[WINDOW] for [SESSION][SEMESTER] is closed',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION][SEMESTER] is closed from now. [REASON] No registration is drafted or submitted until the window reopens.\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: [WINDOW] for [SESSION][SEMESTER] is closed from now.',
 '[WINDOW] closed', '[WINDOW] for [SESSION][SEMESTER] is closed from now. [REASON] No registration is drafted or submitted until the window reopens.',
 ARRAY['FIRST_NAME','WINDOW','SESSION','SEMESTER','REASON','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('BIODATA_REMINDER', 'Biodata update required', 'The weekly reminder to a student whose biodata is incomplete, not yet reviewed since migration, or outdated; at most one a week, none once the record is up to date.',
 'Complete your biodata on the student portal',
 E'Dear [FIRST_NAME],\n\nYour record on the [UNIVERSITY_NAME] portal needs your attention. [STATUS_NOTE]\n\nSign in and open Biodata to update it: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: your portal biodata needs an update. Sign in and open Biodata: [PORTAL_URL]',
 'Biodata update required', '[STATUS_NOTE] Open Biodata to update your record.',
 ARRAY['FIRST_NAME','LAST_NAME','FULL_NAME','MATRIC_NUMBER','STATUS_NOTE','FIELD_LIST','MISSING_COUNT','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('PORTAL_MIGRATION', 'Welcome to the new portal', 'The migration campaign: sent once to each student, lecturer and staff member brought over from the old portal.',
 'Welcome to the new [UNIVERSITY_NAME] portal',
 E'Dear [FIRST_NAME],\n\nThe University has moved to a new portal. You can sign in with your existing credentials, or with the credentials the University gave you.\n\nPortal: [PORTAL_URL]\nYour sign-in: [LOGIN_ID]\n\nPlease sign in and review your biodata so that your information is correct and up to date.\n\nRegards,\n[UNIVERSITY_NAME]',
 'Dear [FIRST_NAME], [UNIVERSITY_SHORT] has moved to a new portal. Sign in at [PORTAL_URL] and review your biodata. Thank you.',
 'Welcome to the new portal', 'The University has moved to a new portal. Please review your biodata so that your information is correct and up to date.',
 ARRAY['FIRST_NAME','LAST_NAME','FULL_NAME','LOGIN_ID','MATRIC_NUMBER','STAFF_NUMBER','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('ANNOUNCEMENT', 'Announcement', 'A message an authorised office writes itself: [TITLE] and [MESSAGE] are the office''s words; the rest is filled from the record.',
 '[TITLE]',
 E'Dear [FIRST_NAME],\n\n[MESSAGE]\n\n[SIGNATURE]',
 '[UNIVERSITY_SHORT]: [SMS_MESSAGE]',
 '[TITLE]', '[MESSAGE]',
 ARRAY['FIRST_NAME','LAST_NAME','FULL_NAME','TITLE','MESSAGE','SMS_MESSAGE','SIGNATURE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], false, 'LOW');

COMMIT;
