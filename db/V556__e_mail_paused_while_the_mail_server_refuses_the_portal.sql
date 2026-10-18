-- V556: e-mail paused while the mail server refuses the portal, so the mailbox is not locked by the retries.
--
-- On Railway the mail server refuses the portal's sign-in (MailAuthenticationException). V532 already holds every e-mail when the
-- account or the server fails — nothing is lost or counted against the message — but the dispatcher tried the sign-in again every
-- 30 seconds: some 120 refused sign-ins an hour against the University's Microsoft 365 mailbox, which Microsoft may lock.
--   * platform.smtp_pause: after a failure of the account or the server (V532's systemic kinds: sign-in refused, server not
--     reached, TLS, blocked, sending limit…) e-mail waits 5 minutes, then 10, 20, 40 and 60 at most between tries; SMS and portal
--     notices go on. The first e-mail that goes resumes it at once, and so does saving the mail settings or a test that passes.
--     platform.smtp_hold / smtp_resume / smtp_pause_state.
--   * The provider's state for ICT (platform.provider_status) reads FAILING while e-mail is held so, with what the failure means in
--     words (the Mail server screen's own) before the server's error — never "stuck" because the tries are fewer.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V556: e-mail paused while the mail server refuses the portal', true);

CREATE TABLE platform.smtp_pause (
    id           boolean PRIMARY KEY DEFAULT true CHECK (id),
    failures     integer NOT NULL DEFAULT 0,
    paused_until timestamptz,
    since        timestamptz,
    kind         text,
    words        text,
    detail       text,
    updated_at   timestamptz NOT NULL DEFAULT now()
);
INSERT INTO platform.smtp_pause (id) VALUES (true);
COMMENT ON TABLE platform.smtp_pause IS
  'V556: e-mail held after a failure of the account or the mail server — the failures in a row, until when, what it means; resumed by the first e-mail that goes';
INSERT INTO audit.exemption (relid, reason) VALUES
  ('platform.smtp_pause'::regclass, 'V556: whether the dispatcher holds e-mail after the mail server failed — machinery moved by each try; the settings ICT saves are on the spine');

-- a failure of the account or the server: e-mail waits 5, 10, 20, 40, then 60 minutes between tries
CREATE FUNCTION platform.smtp_hold(p_kind text, p_words text, p_detail text)
RETURNS timestamptz
LANGUAGE sql AS $fn$
    UPDATE platform.smtp_pause
       SET failures = failures + 1, since = coalesce(since, now()), kind = p_kind, words = p_words, detail = left(p_detail, 600),
           paused_until = now() + make_interval(mins => least(5 * (2 ^ least(failures, 5))::int, 60)), updated_at = now()
     WHERE id
    RETURNING paused_until
$fn$;
COMMENT ON FUNCTION platform.smtp_hold(text, text, text) IS 'V556: e-mail held after a failure of the account or the mail server, 5 minutes doubling to an hour';

-- e-mail goes again at once: an e-mail went, the settings were saved, or a test passed
CREATE FUNCTION platform.smtp_resume()
RETURNS boolean
LANGUAGE sql AS $fn$
    WITH r AS (
        UPDATE platform.smtp_pause SET failures = 0, paused_until = NULL, since = NULL, kind = NULL, words = NULL, detail = NULL, updated_at = now()
         WHERE id AND (failures > 0 OR paused_until IS NOT NULL)
        RETURNING 1)
    SELECT EXISTS (SELECT 1 FROM r)
$fn$;
COMMENT ON FUNCTION platform.smtp_resume() IS 'V556: e-mail no longer held (it went, or ICT changed or tested the settings)';

CREATE FUNCTION platform.smtp_pause_state()
RETURNS jsonb
LANGUAGE sql STABLE AS $fn$
    SELECT jsonb_build_object(
        'held', p.failures > 0, 'paused', p.paused_until IS NOT NULL AND p.paused_until > now(), 'until', p.paused_until,
        'failures', p.failures, 'since', p.since, 'kind', p.kind, 'words', p.words, 'detail', p.detail,
        'waiting', (SELECT count(*) FROM platform.notice n WHERE n.state = 'QUEUED' AND n.channel = 'EMAIL'))
      FROM platform.smtp_pause p WHERE p.id
$fn$;
COMMENT ON FUNCTION platform.smtp_pause_state() IS 'V556: whether e-mail is held, until when, why in words, and how many e-mails wait';

-- V442's provider state, reading FAILING while e-mail is held, with the failure in words
CREATE OR REPLACE FUNCTION platform.provider_status()
 RETURNS TABLE(channel text, state text, since timestamp with time zone, delivery_on boolean, tried bigint, failed bigint, last_error text, last_error_at timestamp with time zone, last_ok_at timestamp with time zone, providers text, waiting bigint, oldest_waiting timestamp with time zone, balance numeric, balance_raw text, balance_at timestamp with time zone, alerted_state text, alerted_at timestamp with time zone, checked_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    WITH s AS (SELECT * FROM platform.notice_setting WHERE id),
         t AS (SELECT x.channel, sum(x.tried) AS tried, sum(x.failed) AS failed, max(x.last_ok_at) AS last_ok_at, max(x.last_error_at) AS last_error_at,
                      (array_agg(x.last_error ORDER BY x.last_error_at DESC NULLS LAST))[1] AS last_error, string_agg(DISTINCT x.provider, ', ') AS providers
                 FROM platform.dispatch_tally x WHERE x.hour >= date_trunc('hour', now()) - interval '1 hour' GROUP BY x.channel),
         q AS (SELECT n.channel, count(*) AS waiting, min(n.created_at) AS oldest FROM platform.notice n
                WHERE n.state = 'QUEUED' AND n.channel IN ('EMAIL', 'SMS') GROUP BY n.channel),
         -- V556: e-mail held after a failure of the account or the server
         p AS (SELECT * FROM platform.smtp_pause WHERE id AND failures > 0)
    SELECT h.channel,
           CASE WHEN NOT s.dispatch_enabled OR NOT CASE h.channel WHEN 'EMAIL' THEN s.email_delivery ELSE s.sms_delivery END THEN 'OFF'
                WHEN h.channel = 'EMAIL' AND p.failures IS NOT NULL THEN 'FAILING'
                WHEN coalesce(t.tried, 0) >= s.failing_min AND coalesce(t.failed, 0) * 100 >= s.failing_share * t.tried THEN 'FAILING'
                WHEN q.oldest IS NOT NULL AND q.oldest < now() - make_interval(mins => s.stuck_minutes) AND coalesce(t.tried, 0) = 0 THEN 'STUCK'
                WHEN h.channel = 'SMS' AND h.balance IS NOT NULL AND s.sms_low_balance > 0 AND h.balance < s.sms_low_balance THEN 'LOW_BALANCE'
                WHEN coalesce(t.tried, 0) > 0 THEN 'OK'
                ELSE 'IDLE' END,
           h.since,
           s.dispatch_enabled AND CASE h.channel WHEN 'EMAIL' THEN s.email_delivery ELSE s.sms_delivery END,
           coalesce(t.tried, 0), coalesce(t.failed, 0),
           CASE WHEN h.channel = 'EMAIL' AND p.failures IS NOT NULL
                THEN concat_ws(' — ', p.words, 'e-mail waits until ' || to_char(p.paused_until AT TIME ZONE 'Africa/Lagos', 'HH24:MI') || ' between tries', p.detail)
                ELSE t.last_error END,
           CASE WHEN h.channel = 'EMAIL' AND p.failures IS NOT NULL THEN p.updated_at ELSE t.last_error_at END,
           t.last_ok_at, t.providers,
           coalesce(q.waiting, 0), q.oldest, h.balance, h.balance_raw, h.balance_at, h.alerted_state, h.alerted_at, h.checked_at
      FROM platform.provider_health h CROSS JOIN s
      LEFT JOIN t ON t.channel = h.channel
      LEFT JOIN q ON q.channel = h.channel
      LEFT JOIN p ON true
     ORDER BY h.channel
$function$;
COMMENT ON FUNCTION platform.provider_status() IS
  'V442/V556: each channel''s state for ICT — OFF, FAILING (as e-mail held after the account or the server failed), STUCK, LOW_BALANCE, OK or IDLE — with its last error in words';

COMMIT;
