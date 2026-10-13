-- ═══════════════════════════════════════
-- V436 — the outbox paused, switched and cleared
--
-- The one outbox (platform.notice, V025; the engine around it, V425) holds every e-mail and SMS until the dispatcher takes it
-- to a provider. While the portal is being tested, what waits there must be stoppable without a trace being lost, and what
-- the modules generate must be keepable from real students without the modules being touched. Four things:
--
-- 1 · A message cancelled stays on the record. platform.notice gains the state CANCELLED, with when, by whom and why. It is
--     never deleted; the dispatcher and the retries pick QUEUED and FAILED only, so a cancelled message is never sent.
--
-- 2 · The delivery switches (platform.notice_setting): queue processing, e-mail delivery, SMS delivery, portal notices. Off,
--     the modules still generate and the outbox still holds (an e-mail queued while e-mail delivery is off waits, unsent,
--     until it is switched on or the queue is cleared); a portal notice is delivered the moment it is made, so the portal
--     switch keeps it from being made at all. Generation and delivery are two different things, and only delivery is switched.
--
-- 3 · The clearance: platform.clear_notice_queue cancels what is still QUEUED on the channels named, with a reason, only while
--     queue processing is paused (the API pauses it first and runs the clearance under the dispatcher's own lock, so nothing
--     is being sent meanwhile), and writes the clearance on platform.notice_clearance with the counts before and after and
--     the history it left untouched. SENT, FAILED and DELIVERED messages are not touched: they are history.
--
-- 4 · A job still running (a window's messages, a campaign) would refill the queue it just emptied: platform.cancel_notice_job
--     ends it (state CANCELLED; a campaign's job cancels the campaign), and the open jobs are listed beside the clearance.
--     The weekly biodata and staff reminders have their own switches (V425, V430) and are left to them.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V436: the outbox paused, switched and cleared', true);

-- ── 1 · a message cancelled stays on the record ──────────────────────────────────────────────────────────────────────────────
ALTER TABLE platform.notice DROP CONSTRAINT ck_notice_state;
ALTER TABLE platform.notice ADD CONSTRAINT ck_notice_state CHECK (state IN ('QUEUED', 'SENT', 'FAILED', 'CANCELLED'));
ALTER TABLE platform.notice
    ADD COLUMN cancelled_at  timestamptz NULL,
    ADD COLUMN cancelled_by  uuid NULL,
    ADD COLUMN cancel_reason text NULL,
    ADD CONSTRAINT ck_notice_cancelled CHECK (state <> 'CANCELLED' OR cancelled_at IS NOT NULL);
COMMENT ON COLUMN platform.notice.cancel_reason IS 'V436: why the message was cancelled before delivery; a cancelled message is history, never deleted, and never sent';

-- ── 2 · the delivery switches ────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE platform.notice_setting
    ADD COLUMN dispatch_enabled   boolean NOT NULL DEFAULT true,
    ADD COLUMN email_delivery     boolean NOT NULL DEFAULT true,
    ADD COLUMN sms_delivery       boolean NOT NULL DEFAULT true,
    ADD COLUMN portal_delivery    boolean NOT NULL DEFAULT true,
    ADD COLUMN dispatch_paused_at timestamptz NULL,
    ADD COLUMN dispatch_paused_by uuid NULL;
COMMENT ON COLUMN platform.notice_setting.dispatch_enabled IS 'V436: whether the dispatcher takes the outbox to the providers at all; off, everything waits';
COMMENT ON COLUMN platform.notice_setting.email_delivery IS 'V436: whether queued e-mail is sent; off, it is generated and held';
COMMENT ON COLUMN platform.notice_setting.sms_delivery IS 'V436: whether queued SMS is sent; off, it is generated and held';
COMMENT ON COLUMN platform.notice_setting.portal_delivery IS 'V436: whether portal notices are made; a portal notice is delivered the moment it is made, so off means not made';

CREATE FUNCTION platform.set_delivery(p_dispatch boolean, p_email boolean, p_sms boolean, p_portal boolean, p_actor uuid, p_office text)
RETURNS platform.notice_setting LANGUAGE plpgsql AS $$
DECLARE s platform.notice_setting;
BEGIN
    UPDATE platform.notice_setting
       SET dispatch_paused_at = CASE WHEN p_dispatch IS FALSE AND dispatch_enabled THEN now()
                                     WHEN p_dispatch IS TRUE THEN NULL
                                     ELSE dispatch_paused_at END,
           dispatch_paused_by = CASE WHEN p_dispatch IS FALSE AND dispatch_enabled THEN p_actor
                                     WHEN p_dispatch IS TRUE THEN NULL
                                     ELSE dispatch_paused_by END,
           dispatch_enabled   = coalesce(p_dispatch, dispatch_enabled),
           email_delivery     = coalesce(p_email, email_delivery),
           sms_delivery       = coalesce(p_sms, sms_delivery),
           portal_delivery    = coalesce(p_portal, portal_delivery),
           updated_by = p_actor, updated_office = p_office, updated_at = now()
     WHERE id
    RETURNING * INTO s;
    RETURN s;
END $$;

-- the switches as the screen reads them
CREATE FUNCTION platform.delivery()
RETURNS TABLE (dispatch_enabled boolean, email_delivery boolean, sms_delivery boolean, portal_delivery boolean,
               dispatch_paused_at timestamptz, dispatch_paused_by_name text, updated_at timestamptz, updated_office text)
LANGUAGE sql STABLE AS $$
    SELECT s.dispatch_enabled, s.email_delivery, s.sms_delivery, s.portal_delivery, s.dispatch_paused_at,
           (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = s.dispatch_paused_by),
           s.updated_at, s.updated_office
      FROM platform.notice_setting s WHERE s.id
$$;

-- queue_notice (V425) restated: a portal notice is not made while the portal channel is switched off — it could not be held back later
CREATE OR REPLACE FUNCTION platform.queue_notice(p_channel text, p_recipient text, p_subject text, p_body text, p_about_kind text, p_about_id uuid,
                                                 p_event_key text, p_template_key text, p_priority text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid(); v_to text; v_state text := 'QUEUED'; v_err text := NULL; v_sent timestamptz := NULL;
BEGIN
    IF p_channel = 'PORTAL' THEN
        IF p_about_id IS NULL THEN RETURN NULL; END IF;
        IF NOT coalesce((SELECT s.portal_delivery FROM platform.notice_setting s WHERE s.id), true) THEN RETURN NULL; END IF;
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
  'V425: queues one message; an address that is not one is recorded FAILED (INVALID_EMAIL / INVALID_PHONE) and never tried; a portal notice is delivered at once; an event key makes the message happen once per person per channel. V436: no portal notice is made while the portal channel is switched off.';

-- ── 3 · the clearance on the record ──────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.notice_clearance (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cleared_at           timestamptz NOT NULL DEFAULT now(),
    cleared_by           uuid NULL,
    cleared_office       text NULL,
    channels             text[] NOT NULL,
    reason               text NOT NULL,
    email_pending_before int NOT NULL DEFAULT 0,
    sms_pending_before   int NOT NULL DEFAULT 0,
    email_cancelled      int NOT NULL DEFAULT 0,
    sms_cancelled        int NOT NULL DEFAULT 0,
    email_remaining      int NOT NULL DEFAULT 0,
    sms_remaining        int NOT NULL DEFAULT 0,
    email_sent           int NOT NULL DEFAULT 0,
    sms_sent             int NOT NULL DEFAULT 0,
    email_failed         int NOT NULL DEFAULT 0,
    sms_failed           int NOT NULL DEFAULT 0,
    jobs_open            int NOT NULL DEFAULT 0,
    campaigns_sending    int NOT NULL DEFAULT 0
);
COMMENT ON TABLE platform.notice_clearance IS 'V436: each clearing of the pending e-mail/SMS queue — who, when, why, what waited, what was cancelled, what still waited, and the sent and failed history left untouched.';
SELECT audit.attach('platform.notice_clearance');

CREATE FUNCTION platform.clear_notice_queue(p_channels text[], p_reason text, p_actor uuid, p_office text)
RETURNS platform.notice_clearance LANGUAGE plpgsql AS $$
DECLARE c platform.notice_clearance; s platform.notice_setting; ch text[];
        v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); eb int; sb int; ec int; sc int;
BEGIN
    ch := ARRAY(SELECT DISTINCT upper(btrim(x)) FROM unnest(coalesce(p_channels, '{}'::text[])) x WHERE btrim(x) <> '' ORDER BY 1);
    IF coalesce(array_length(ch, 1), 0) = 0 OR EXISTS (SELECT 1 FROM unnest(ch) x WHERE x NOT IN ('EMAIL', 'SMS')) THEN
        RAISE EXCEPTION 'NOTICE_CLEAR_CHANNEL: the queue cleared is e-mail, SMS or both; a portal notice is delivered the moment it is made and is never pending' USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'NOTICE_CLEAR_REASON: a reason is recorded with every clearance' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM platform.notice_setting WHERE id FOR UPDATE;
    IF s.dispatch_enabled THEN
        RAISE EXCEPTION 'NOTICE_CLEAR_DISPATCHING: pause queue processing first, so that nothing is sent while the queue is cleared' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) FILTER (WHERE n.channel = 'EMAIL'), count(*) FILTER (WHERE n.channel = 'SMS') INTO eb, sb
      FROM platform.notice n WHERE n.state = 'QUEUED';
    WITH done AS (
        UPDATE platform.notice SET state = 'CANCELLED', cancelled_at = now(), cancelled_by = p_actor, cancel_reason = v_reason
         WHERE state = 'QUEUED' AND channel = ANY (ch)
        RETURNING channel)
    SELECT count(*) FILTER (WHERE done.channel = 'EMAIL'), count(*) FILTER (WHERE done.channel = 'SMS') INTO ec, sc FROM done;
    INSERT INTO platform.notice_clearance (cleared_by, cleared_office, channels, reason, email_pending_before, sms_pending_before, email_cancelled, sms_cancelled,
                                           email_remaining, sms_remaining, email_sent, sms_sent, email_failed, sms_failed, jobs_open, campaigns_sending)
    SELECT p_actor, p_office, ch, v_reason, eb, sb, ec, sc,
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'QUEUED' AND n.channel = 'EMAIL'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'QUEUED' AND n.channel = 'SMS'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'SENT' AND n.channel = 'EMAIL'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'SENT' AND n.channel = 'SMS'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'FAILED' AND n.channel = 'EMAIL'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'FAILED' AND n.channel = 'SMS'),
           (SELECT count(*) FROM platform.notice_job j WHERE j.state IN ('QUEUED', 'RUNNING')),
           (SELECT count(*) FROM platform.notice_campaign x WHERE x.state = 'SENDING')
    RETURNING * INTO c;
    RETURN c;
END $$;
COMMENT ON FUNCTION platform.clear_notice_queue(text[], text, uuid, text) IS
  'V436: what still waits on the channels named is cancelled (never deleted) with the reason given, only while queue processing is paused; the clearance is written with its counts.';

-- what waits now, by channel, for the confirmation before a clearance
CREATE FUNCTION platform.notice_pending()
RETURNS TABLE (channel text, pending bigint, oldest timestamptz, newest timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT c.channel, count(n.id), min(n.created_at), max(n.created_at)
      FROM (VALUES ('EMAIL'), ('SMS')) c(channel)
      LEFT JOIN platform.notice n ON n.channel = c.channel AND n.state = 'QUEUED'
     GROUP BY c.channel ORDER BY c.channel
$$;

-- ── 4 · a job still running is ended, so it does not refill the queue ────────────────────────────────────────────────────────
ALTER TABLE platform.notice_job DROP CONSTRAINT notice_job_state_check;
ALTER TABLE platform.notice_job ADD CONSTRAINT notice_job_state_check CHECK (state IN ('QUEUED', 'RUNNING', 'DONE', 'FAILED', 'CANCELLED'));

CREATE FUNCTION platform.cancel_notice_job(p_job uuid, p_reason text, p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE j platform.notice_job; v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_campaign uuid;
BEGIN
    SELECT * INTO j FROM platform.notice_job x WHERE x.id = p_job FOR UPDATE;
    IF j.id IS NULL THEN RAISE EXCEPTION 'NOTICE_JOB_NONE: no such job' USING ERRCODE = '23514'; END IF;
    IF j.state NOT IN ('QUEUED', 'RUNNING') THEN
        RAISE EXCEPTION 'NOTICE_JOB_FINISHED: a job already % is not cancelled', lower(j.state) USING ERRCODE = '23514';
    END IF;
    IF j.kind = 'CAMPAIGN' THEN
        v_campaign := nullif(j.payload->>'campaign_id', '')::uuid;
        UPDATE platform.notice_campaign
           SET state = 'CANCELLED', cancelled_at = now(), cancel_reason = coalesce(v_reason, cancel_reason), updated_at = now()
         WHERE id = v_campaign AND state IN ('DRAFT', 'SENDING');
    END IF;
    UPDATE platform.notice_job
       SET state = 'CANCELLED', finished_at = now(),
           error = 'cancelled by ' || coalesce(p_office, 'an office') || CASE WHEN v_reason IS NULL THEN '' ELSE ': ' || v_reason END
     WHERE id = p_job;
    RETURN j.kind;
END $$;

-- campaign_cancel (V426) restated: the campaign's job is cancelled, not marked done
CREATE OR REPLACE FUNCTION platform.campaign_cancel(p_campaign uuid, p_reason text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE c platform.notice_campaign;
BEGIN
    SELECT * INTO c FROM platform.notice_campaign x WHERE x.id = p_campaign FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'CAMPAIGN_NONE: no such campaign' USING ERRCODE = '23514'; END IF;
    IF c.state NOT IN ('DRAFT', 'SENDING') THEN
        RAISE EXCEPTION 'CAMPAIGN_FINISHED: a campaign already % is not cancelled', lower(c.state) USING ERRCODE = '23514';
    END IF;
    UPDATE platform.notice_campaign SET state = 'CANCELLED', cancelled_at = now(), cancel_reason = nullif(btrim(coalesce(p_reason, '')), ''), updated_at = now() WHERE id = p_campaign;
    IF c.job_id IS NOT NULL THEN
        UPDATE platform.notice_job SET state = 'CANCELLED', finished_at = coalesce(finished_at, now()),
               error = 'cancelled by ' || coalesce(p_office, 'an office') || CASE WHEN nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN '' ELSE ': ' || btrim(p_reason) END
         WHERE id = c.job_id AND state IN ('QUEUED', 'RUNNING');
    END IF;
END $$;

-- the jobs that would still write to the queue, with what each is about
CREATE FUNCTION platform.open_notice_jobs()
RETURNS TABLE (id uuid, kind text, state text, about text, created_at timestamptz, created_office text, reached int, queued int, runs int)
LANGUAGE sql STABLE AS $$
    SELECT j.id, j.kind, j.state,
           CASE j.kind
                WHEN 'CAMPAIGN' THEN coalesce((SELECT x.name FROM platform.notice_campaign x WHERE x.id = nullif(j.payload->>'campaign_id', '')::uuid), 'a campaign')
                WHEN 'WINDOW' THEN coalesce(j.payload->>'type', 'a window') || ' ' || coalesce(j.payload->>'action', '') || coalesce(' · ' || nullif(j.payload->>'session', ''), '')
                ELSE lower(replace(j.kind, '_', ' ')) END,
           j.created_at, j.created_office, j.reached, j.queued, j.runs
      FROM platform.notice_job j
     WHERE j.state IN ('QUEUED', 'RUNNING')
     ORDER BY j.created_at
$$;

COMMIT;
