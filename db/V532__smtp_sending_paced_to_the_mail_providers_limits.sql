-- ═══════════════════════════════════════
-- V532 — E-mail over SMTP paced to the mail provider's limits
--
--   From 14 Oct 2026 every e-mail failed against a wrong SMTP host (smtp.mail.outlook.com, Microsoft's inbound exchange
--   host), and 177,000 e-mails waited. Once the host was right (smtp.office365.com), the dispatcher would have sent 200
--   every half-minute from one Microsoft 365 mailbox, which Microsoft allows about 30 messages a minute and 10,000
--   recipients a day: the mailbox is throttled, then blocked from sending (Restricted entities).
--
--   · platform.notice_setting.smtp_per_minute (default 30) and smtp_per_day (default 10,000) — Microsoft 365's own limits
--     for one mailbox; empty means no limit (an SMTP service with limits of its own); set by the Directorate of ICT
--     (platform.set_smtp_pace), on the audit spine with the other notice settings;
--   · platform.smtp_attempt — every attempt the dispatcher (or the Mail server screen's test) makes over SMTP, kept two
--     days, so the pace is counted across every instance of the API, not in one instance's memory;
--   · platform.smtp_pace() — the limits, what was tried in the last minute and the last 24 hours, and how many more may go
--     now (NULL: no limit); the dispatcher takes no more e-mail from the outbox than that.
--   The HTTP relay (MOAUM_NOTICES_EMAIL_URL) and SMS are not paced here: their providers take bulk.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V532: SMTP sending paced to the mail provider''s limits', true);

ALTER TABLE platform.notice_setting
    ADD COLUMN smtp_per_minute int NULL DEFAULT 30 CHECK (smtp_per_minute IS NULL OR smtp_per_minute BETWEEN 1 AND 10000),
    ADD COLUMN smtp_per_day    int NULL DEFAULT 10000 CHECK (smtp_per_day IS NULL OR smtp_per_day BETWEEN 1 AND 1000000);
COMMENT ON COLUMN platform.notice_setting.smtp_per_minute IS
  'V532: at most this many e-mails over SMTP in any minute (Microsoft 365 allows a mailbox 30); NULL = no limit';
COMMENT ON COLUMN platform.notice_setting.smtp_per_day IS
  'V532: at most this many e-mails over SMTP in any 24 hours (Microsoft 365 allows a mailbox 10,000 recipients); NULL = no limit';

CREATE TABLE platform.smtp_attempt (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at timestamptz NOT NULL DEFAULT clock_timestamp(),
    ok boolean NOT NULL
);
CREATE INDEX ix_smtp_attempt_at ON platform.smtp_attempt (at);
COMMENT ON TABLE platform.smtp_attempt IS 'V532: each attempt to send an e-mail over SMTP, for the pace; kept two days';
SELECT audit.exempt('platform.smtp_attempt',
    'A counter of SMTP attempts for pacing, pruned after two days; each message''s outcome is on the outbox and the dispatch tally.');

-- an attempt counted (and the counter kept to two days)
CREATE FUNCTION platform.smtp_attempted(p_ok boolean)
RETURNS void LANGUAGE sql AS $$
    DELETE FROM platform.smtp_attempt WHERE at < now() - interval '2 days';
    INSERT INTO platform.smtp_attempt (ok) VALUES (coalesce(p_ok, false));
$$;

-- the limits, what was tried, and how many more may go now
CREATE FUNCTION platform.smtp_pace()
RETURNS TABLE (per_minute int, per_day int, last_minute bigint, last_day bigint, allowance int)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT n.smtp_per_minute, n.smtp_per_day FROM platform.notice_setting n WHERE n.id),
         c AS (SELECT count(*) FILTER (WHERE a.at > clock_timestamp() - interval '1 minute') AS m,
                      count(*) FILTER (WHERE a.at > clock_timestamp() - interval '24 hours') AS d
                 FROM platform.smtp_attempt a WHERE a.at > clock_timestamp() - interval '24 hours')
    SELECT s.smtp_per_minute, s.smtp_per_day, c.m, c.d,
           CASE WHEN s.smtp_per_minute IS NULL AND s.smtp_per_day IS NULL THEN NULL
                ELSE greatest(0, least(coalesce(s.smtp_per_minute - c.m, 2147483647), coalesce(s.smtp_per_day - c.d, 2147483647)))::int END
      FROM s CROSS JOIN c
$$;
COMMENT ON FUNCTION platform.smtp_pace() IS
  'V532: the SMTP pace — the limits per minute and per day, the attempts in the last minute and 24 hours, and how many more may be sent now (NULL: no limit)';

-- the limits set by the Directorate of ICT; NULL is no limit
CREATE FUNCTION platform.set_smtp_pace(p_per_minute int, p_per_day int, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_per_minute IS NOT NULL AND (p_per_minute < 1 OR p_per_minute > 10000) THEN
        RAISE EXCEPTION 'NOTICE_PACE_RANGE: e-mails a minute is from 1 to 10,000, or empty for no limit' USING ERRCODE = '23514';
    END IF;
    IF p_per_day IS NOT NULL AND (p_per_day < 1 OR p_per_day > 1000000) THEN
        RAISE EXCEPTION 'NOTICE_PACE_RANGE: e-mails a day is from 1 to 1,000,000, or empty for no limit' USING ERRCODE = '23514';
    END IF;
    IF p_per_minute IS NOT NULL AND p_per_day IS NOT NULL AND p_per_day < p_per_minute THEN
        RAISE EXCEPTION 'NOTICE_PACE_RANGE: a day''s limit is not below a minute''s' USING ERRCODE = '23514';
    END IF;
    UPDATE platform.notice_setting
       SET smtp_per_minute = p_per_minute, smtp_per_day = p_per_day, updated_by = p_actor, updated_office = p_office, updated_at = now()
     WHERE id;
END $$;

COMMIT;
