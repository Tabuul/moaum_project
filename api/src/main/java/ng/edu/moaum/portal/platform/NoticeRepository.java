package ng.edu.moaum.portal.platform;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** The outbox (V025): what is queued, what went, what did not. */
@Repository
public class NoticeRepository {

    private final JdbcClient jdbc;

    public NoticeRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Queued(UUID id, String channel, String recipient, String subject, String body, int attempts) {
    }

    /** a file queued with a notice (V230) */
    public record Attachment(String filename, String contentType, byte[] content) {
    }

    public List<Attachment> attachments(UUID noticeId) {
        return jdbc.sql("SELECT filename, content_type, content FROM platform.notice_attachment WHERE notice_id = :n ORDER BY created_at")
                .param("n", noticeId).query(Attachment.class).list();
    }

    /** queue an email with attachments, in the caller's transaction; returns the notice id */
    public UUID queueEmail(String recipient, String subject, String body, String aboutKind, UUID aboutId, List<Attachment> files) {
        UUID id = jdbc.sql("SELECT platform.queue_notice('EMAIL', :r, :s, :b, :k, :a)")
                .param("r", recipient).param("s", subject).param("b", body)
                .param("k", aboutKind, Types.VARCHAR).param("a", aboutId, Types.OTHER)
                .query(UUID.class).single();
        for (Attachment f : files) {
            jdbc.sql("INSERT INTO platform.notice_attachment (notice_id, filename, content_type, content, size_bytes) VALUES (:n, :f, :t, :c, :z)")
                    .param("n", id).param("f", f.filename()).param("t", f.contentType()).param("c", f.content()).param("z", f.content().length).update();
        }
        return id;
    }

    public List<Queued> queued(int limit) {
        return jdbc.sql("""
                SELECT id, channel, recipient, subject, body, attempts FROM platform.notice
                 WHERE state = 'QUEUED' AND attempts < 5 AND channel IN ('EMAIL', 'SMS')
                 ORDER BY CASE priority WHEN 'CRITICAL' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END, created_at
                 LIMIT :n
                """).param("n", limit).query(Queued.class).list();
    }

    // ── V436: the delivery switches, the batch they allow, the clearance and the jobs ──

    /** the switches: queue processing at all, e-mail delivery, SMS delivery, portal notices */
    public record Delivery(boolean dispatch, boolean email, boolean sms, boolean portal) { }

    public Delivery delivery() {
        Map<String, Object> r = jdbc.sql("SELECT dispatch_enabled, email_delivery, sms_delivery, portal_delivery FROM platform.notice_setting WHERE id").query().singleRow();
        return new Delivery(Boolean.TRUE.equals(r.get("dispatch_enabled")), Boolean.TRUE.equals(r.get("email_delivery")),
                Boolean.TRUE.equals(r.get("sms_delivery")), Boolean.TRUE.equals(r.get("portal_delivery")));
    }

    /** the batch the dispatcher may send now: nothing while queue processing is paused; only the channels whose delivery is on; never a cancelled message */
    public List<Queued> sendable(int limit) {
        return sendable(limit, delivery());
    }

    public List<Queued> sendable(int limit, Delivery d) {
        if (!d.dispatch() || (!d.email() && !d.sms())) {
            return List.of();
        }
        return jdbc.sql("""
                SELECT id, channel, recipient, subject, body, attempts FROM platform.notice
                 WHERE state = 'QUEUED' AND attempts < 5 AND ((channel = 'EMAIL' AND :email) OR (channel = 'SMS' AND :sms))
                 ORDER BY CASE priority WHEN 'CRITICAL' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END, created_at
                 LIMIT :n
                """).param("email", d.email()).param("sms", d.sms()).param("n", limit).query(Queued.class).list();
    }

    /** V532: the batch with no more e-mail than the SMTP pace allows now (SMS as before) */
    public List<Queued> sendable(int limit, Delivery d, int emailCap) {
        if (!d.dispatch() || (!d.email() && !d.sms())) {
            return List.of();
        }
        return jdbc.sql("""
                SELECT id, channel, recipient, subject, body, attempts FROM (
                    (SELECT id, channel, recipient, subject, body, attempts, priority, created_at FROM platform.notice
                      WHERE state = 'QUEUED' AND attempts < 5 AND channel = 'EMAIL' AND :email
                      ORDER BY CASE priority WHEN 'CRITICAL' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END, created_at
                      LIMIT :cap)
                    UNION ALL
                    (SELECT id, channel, recipient, subject, body, attempts, priority, created_at FROM platform.notice
                      WHERE state = 'QUEUED' AND attempts < 5 AND channel = 'SMS' AND :sms
                      ORDER BY CASE priority WHEN 'CRITICAL' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END, created_at
                      LIMIT :n)) x
                 ORDER BY CASE x.priority WHEN 'CRITICAL' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END, x.created_at
                 LIMIT :n
                """).param("email", d.email() && emailCap > 0).param("sms", d.sms()).param("cap", Math.max(0, emailCap)).param("n", limit)
                .query(Queued.class).list();
    }

    /** V532: the SMTP pace — the limits (null: none), the attempts in the last minute and 24 hours, how many more may go now (null: no limit) */
    public record SmtpPace(Integer perMinute, Integer perDay, long lastMinute, long lastDay, Integer allowance) { }

    public SmtpPace smtpPace() {
        Map<String, Object> r = jdbc.sql("SELECT * FROM platform.smtp_pace()").query().singleRow();
        return new SmtpPace(r.get("per_minute") == null ? null : ((Number) r.get("per_minute")).intValue(),
                r.get("per_day") == null ? null : ((Number) r.get("per_day")).intValue(),
                ((Number) r.get("last_minute")).longValue(), ((Number) r.get("last_day")).longValue(),
                r.get("allowance") == null ? null : ((Number) r.get("allowance")).intValue());
    }

    public void smtpAttempted(boolean ok) {
        jdbc.sql("SELECT platform.smtp_attempted(:ok)").param("ok", ok).query().singleRow();
    }

    public void setSmtpPace(Integer perMinute, Integer perDay, UUID actor, String office) {
        jdbc.sql("SELECT platform.set_smtp_pace(:m, :d, :by, :office)").param("m", perMinute, Types.INTEGER).param("d", perDay, Types.INTEGER)
                .param("by", actor, Types.OTHER).param("office", office, Types.VARCHAR).query().singleRow();
    }

    /** V532: a message the account's or server's failure kept from going — the error noted, the attempt not counted against it */
    /** V556: until when e-mail is held after a failure of the account or the mail server, or null */
    public java.time.OffsetDateTime smtpHeldUntil() {
        return jdbc.sql("SELECT paused_until FROM platform.smtp_pause WHERE id").query(java.time.OffsetDateTime.class).optional().orElse(null);
    }

    /** V556: a failure of the account or the server: e-mail waits 5 minutes doubling to an hour; until when */
    public java.time.OffsetDateTime smtpHold(String kind, String words, String detail) {
        return jdbc.sql("SELECT platform.smtp_hold(:k, :w, :d)").param("k", kind, java.sql.Types.VARCHAR).param("w", words, java.sql.Types.VARCHAR)
                .param("d", detail, java.sql.Types.VARCHAR).query(java.time.OffsetDateTime.class).single();
    }

    /** V556: e-mail no longer held */
    public boolean smtpResume() {
        return Boolean.TRUE.equals(jdbc.sql("SELECT platform.smtp_resume()").query(Boolean.class).single());
    }

    /** V556: whether e-mail is held, until when, why in words, how many wait — for the Mail server screen */
    public String smtpPauseState() {
        return jdbc.sql("SELECT platform.smtp_pause_state()::text").query(String.class).single();
    }

    public void held(UUID id, String error) {
        jdbc.sql("UPDATE platform.notice SET last_error = :e WHERE id = :id")
                .param("e", error == null ? "" : error.substring(0, Math.min(error.length(), 400))).param("id", id).update();
    }

    public Map<String, Object> deliveryRow() {
        return jdbc.sql("SELECT * FROM platform.delivery()").query().singleRow();
    }

    public void setDelivery(Boolean dispatch, Boolean email, Boolean sms, Boolean portal, UUID actor, String office) {
        jdbc.sql("SELECT dispatch_enabled FROM platform.set_delivery(:d, :e, :s, :p, :by, :office)")
                .param("d", dispatch, Types.BOOLEAN).param("e", email, Types.BOOLEAN).param("s", sms, Types.BOOLEAN).param("p", portal, Types.BOOLEAN)
                .param("by", actor, Types.OTHER).param("office", office, Types.VARCHAR).query().singleRow();
    }

    /** what waits now on e-mail and SMS, for the confirmation before a clearance */
    public List<Map<String, Object>> pending() {
        return jdbc.sql("SELECT * FROM platform.notice_pending()").query().listOfRows();
    }

    private static final String CLEARANCE_COLUMNS = "c.id, c.cleared_at, c.cleared_office, array_to_string(c.channels, ',') AS channels, c.reason, "
            + "c.email_pending_before, c.sms_pending_before, c.email_cancelled, c.sms_cancelled, c.email_remaining, c.sms_remaining, "
            + "c.email_sent, c.sms_sent, c.email_failed, c.sms_failed, c.jobs_open, c.campaigns_sending";

    /** the pending queue cancelled on the channels named, with the reason; the database refuses it while queue processing runs */
    public Map<String, Object> clear(List<String> channels, String reason, UUID actor, String office) {
        return jdbc.sql("SELECT " + CLEARANCE_COLUMNS + " FROM platform.clear_notice_queue(string_to_array(:ch, ','), :r, :by, :office) c")
                .param("ch", String.join(",", channels)).param("r", reason, Types.VARCHAR)
                .param("by", actor, Types.OTHER).param("office", office, Types.VARCHAR).query().singleRow();
    }

    public List<Map<String, Object>> clearances(int limit) {
        return jdbc.sql("SELECT " + CLEARANCE_COLUMNS + ", p.surname || ', ' || p.given_names AS cleared_by_name "
                + "FROM platform.notice_clearance c LEFT JOIN iam.person p ON p.id = c.cleared_by ORDER BY c.cleared_at DESC LIMIT :n")
                .param("n", limit).query().listOfRows();
    }

    /** the jobs that would still write to the queue */
    public List<Map<String, Object>> openJobs() {
        return jdbc.sql("SELECT * FROM platform.open_notice_jobs()").query().listOfRows();
    }

    public String cancelJob(UUID id, String reason, UUID actor, String office) {
        return jdbc.sql("SELECT platform.cancel_notice_job(:id, :r, :by, :office)")
                .param("id", id).param("r", reason, Types.VARCHAR).param("by", actor, Types.OTHER).param("office", office, Types.VARCHAR)
                .query(String.class).single();
    }

    /** V425: the outbox searched — by channel, state, what the notice is about, words in the recipient or subject, and a day range */
    public List<Map<String, Object>> search(String channel, String state, String kind, String q, java.time.LocalDate from, java.time.LocalDate to, int limit) {
        return jdbc.sql("""
                SELECT n.id, n.channel, n.recipient, n.subject, n.about_kind, n.about_id, n.created_at, n.state, n.attempts, n.sent_at, n.last_error,
                       n.cancel_reason, n.delivery_state, n.delivered_at, n.delivery_detail,
                       n.template_key, n.priority, n.event_key,
                       CASE n.about_kind WHEN 'student' THEN (SELECT s.surname || ', ' || s.other_names || coalesce(' (' || s.matric_no || ')', '') FROM people.student s WHERE s.id = n.about_id)
                                         WHEN 'person' THEN (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = n.about_id) END AS about_name
                  FROM platform.notice n
                 WHERE (CAST(:channel AS text) IS NULL OR n.channel = CAST(:channel AS text))
                   AND (CAST(:state AS text) IS NULL OR n.state = CAST(:state AS text))
                   AND (CAST(:kind AS text) IS NULL OR n.about_kind = CAST(:kind AS text))
                   AND (CAST(:q AS text) IS NULL OR n.recipient ILIKE '%' || CAST(:q AS text) || '%' OR n.subject ILIKE '%' || CAST(:q AS text) || '%'
                        OR coalesce(n.template_key, '') ILIKE '%' || CAST(:q AS text) || '%')
                   AND (CAST(:from AS date) IS NULL OR n.created_at >= CAST(:from AS date))
                   AND (CAST(:to AS date) IS NULL OR n.created_at < CAST(:to AS date) + 1)
                 ORDER BY n.created_at DESC LIMIT :n
                """).param("channel", channel, Types.VARCHAR).param("state", state, Types.VARCHAR).param("kind", kind, Types.VARCHAR)
                .param("q", q, Types.VARCHAR).param("from", from, Types.DATE).param("to", to, Types.DATE).param("n", limit).query().listOfRows();
    }

    /** V425: the delivery picture by channel — all time, and the last seven days */
    public List<Map<String, Object>> byChannel() {
        return jdbc.sql("""
                SELECT channel,
                       count(*) AS total,
                       count(*) FILTER (WHERE state = 'SENT') AS sent,
                       count(*) FILTER (WHERE state = 'QUEUED') AS queued,
                       count(*) FILTER (WHERE state = 'FAILED') AS failed,
                       count(*) FILTER (WHERE state = 'CANCELLED') AS cancelled,
                       count(*) FILTER (WHERE state = 'SENT' AND delivery_state = 'DELIVERED') AS delivered,
                       count(*) FILTER (WHERE state = 'SENT' AND delivery_state IN ('BOUNCED', 'UNDELIVERED')) AS bounced,
                       count(*) FILTER (WHERE state = 'FAILED' AND last_error IN ('INVALID_EMAIL', 'INVALID_PHONE')) AS invalid,
                       count(*) FILTER (WHERE created_at > now() - interval '7 days') AS week,
                       count(*) FILTER (WHERE state = 'SENT' AND sent_at > now() - interval '7 days') AS week_sent,
                       count(*) FILTER (WHERE state = 'FAILED' AND created_at > now() - interval '7 days') AS week_failed
                  FROM platform.notice GROUP BY channel ORDER BY channel
                """).query().listOfRows();
    }

    public void sent(UUID id, String providerRef) {
        sent(id, providerRef, null);
    }

    /** V438: the provider's own id of the message kept, so its delivery report can find it */
    public void sent(UUID id, String providerRef, String providerId) {
        jdbc.sql("UPDATE platform.notice SET state = 'SENT', sent_at = now(), attempts = attempts + 1, provider_ref = :r, provider_id = :p, last_error = NULL WHERE id = :id")
                .param("r", providerRef, Types.VARCHAR).param("p", providerId, Types.VARCHAR).param("id", id).update();
    }

    // ── V438: delivery receipts ──

    public boolean receiptTokenOk(String token) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT platform.receipt_token_ok(:t)").param("t", token, Types.VARCHAR).query(Boolean.class).single());
    }

    public String receiptToken() {
        return jdbc.sql("SELECT receipt_token FROM platform.notice_setting WHERE id").query(String.class).optional().orElse(null);
    }

    public String newReceiptToken(UUID actor, String office) {
        return jdbc.sql("SELECT platform.new_receipt_token(:by, :office)").param("by", actor, Types.OTHER).param("office", office, Types.VARCHAR).query(String.class).single();
    }

    /** the provider's word on one message: DELIVERED, BOUNCED, UNDELIVERED, or IGNORED, UNMATCHED, NOT_SENT — always logged */
    public Map<String, Object> recordReceipt(String provider, String providerId, String status, String detail, String payloadJson) {
        return jdbc.sql("SELECT outcome, notice_id FROM platform.record_receipt(:p, :id, :s, :d, :j::jsonb)")
                .param("p", provider, Types.VARCHAR).param("id", providerId, Types.VARCHAR).param("s", status, Types.VARCHAR)
                .param("d", detail, Types.VARCHAR).param("j", payloadJson, Types.VARCHAR).query().singleRow();
    }

    public List<Map<String, Object>> receipts(int limit) {
        return jdbc.sql("""
                SELECT r.id, r.provider, r.received_at, r.provider_id, r.status_word, r.notice_id, r.outcome, r.detail,
                       n.channel, n.recipient, n.subject
                  FROM platform.notice_receipt r LEFT JOIN platform.notice n ON n.id = r.notice_id
                 ORDER BY r.received_at DESC LIMIT :n
                """).param("n", limit).query().listOfRows();
    }

    public void failed(UUID id, String error, boolean giveUp) {
        jdbc.sql("UPDATE platform.notice SET attempts = attempts + 1, last_error = :e, state = CASE WHEN :g THEN 'FAILED' ELSE state END WHERE id = :id")
                .param("e", error == null ? "" : error.substring(0, Math.min(error.length(), 400))).param("g", giveUp).param("id", id).update();
    }

    public Map<String, Object> counts() {
        return jdbc.sql("""
                SELECT count(*) FILTER (WHERE state = 'QUEUED') AS queued,
                       count(*) FILTER (WHERE state = 'SENT') AS sent,
                       count(*) FILTER (WHERE state = 'FAILED') AS failed,
                       count(*) FILTER (WHERE state = 'CANCELLED') AS cancelled,
                       count(*) FILTER (WHERE state = 'SENT' AND sent_at > now() - interval '24 hours') AS sent_today
                  FROM platform.notice
                """).query().singleRow();
    }

    public List<Map<String, Object>> recent(int limit) {
        return jdbc.sql("""
                SELECT id, channel, recipient, subject, about_kind, about_id, created_at, state, attempts, sent_at, last_error,
                       cancel_reason, delivery_state, delivered_at, delivery_detail
                  FROM platform.notice ORDER BY created_at DESC LIMIT :n
                """).param("n", limit).query().listOfRows();
    }

    /** put a failed notice (or all of them) back in the queue so the dispatcher tries again */
    public int requeue(java.util.UUID id) {
        return jdbc.sql("UPDATE platform.notice SET state = 'QUEUED', attempts = 0, last_error = NULL WHERE id = :id AND state = 'FAILED'")
                .param("id", id).update();
    }

    public int requeueAllFailed() {
        // V425: an address that is not one is never tried again by a retry-all; it is corrected on the record first
        return jdbc.sql("UPDATE platform.notice SET state = 'QUEUED', attempts = 0, last_error = NULL WHERE state = 'FAILED' AND coalesce(last_error, '') NOT IN ('INVALID_EMAIL', 'INVALID_PHONE')").update();
    }

    // ── V440: a person's messages, and one sent again ──

    /** what the portal sent a student ('student') or a member of staff ('person'), newest first, with the provider's word */
    public List<Map<String, Object>> messagesFor(String kind, UUID id) {
        return jdbc.sql("SELECT * FROM platform.messages_for(:k, :id, 100)").param("k", kind).param("id", id).query().listOfRows();
    }

    public boolean isAbout(UUID notice, String kind, UUID id) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM platform.notice n WHERE n.id = :n AND n.about_kind = :k AND n.about_id = :id)")
                .param("n", notice).param("k", kind).param("id", id).query(Boolean.class).single());
    }

    /** a failed, cancelled, bounced or undelivered e-mail or SMS queued again to the address the record holds now; the new message's id */
    public UUID resend(UUID notice, UUID actor, String office) {
        return jdbc.sql("SELECT platform.resend_notice(:n, :by, :office)")
                .param("n", notice).param("by", actor, Types.OTHER).param("office", office, Types.VARCHAR).query(UUID.class).single();
    }

    // ── V442: the providers watched ──

    /** one attempt counted against its channel, provider and hour, with the error when it failed */
    public void recordAttempt(String channel, String provider, boolean ok, String error) {
        jdbc.sql("SELECT platform.record_attempt(:c, :p, :ok, :e)")
                .param("c", channel).param("p", provider, Types.VARCHAR).param("ok", ok).param("e", error, Types.VARCHAR).query().singleRow();
    }

    public List<Map<String, Object>> providerStatus() {
        return jdbc.sql("SELECT * FROM platform.provider_status()").query().listOfRows();
    }

    public Map<String, Object> providerSettings() {
        return jdbc.sql("SELECT provider_watch, failing_share, failing_min, stuck_minutes, sms_low_balance FROM platform.notice_setting WHERE id").query().singleRow();
    }

    public void setProviderWatch(Boolean watch, java.math.BigDecimal lowBalance, UUID actor, String office) {
        jdbc.sql("SELECT platform.set_provider_watch(:w, :b, :by, :office)")
                .param("w", watch, Types.BOOLEAN).param("b", lowBalance, Types.NUMERIC).param("by", actor, Types.OTHER).param("office", office, Types.VARCHAR)
                .query().singleRow();
    }

    public void recordSmsBalance(String raw, java.math.BigDecimal value) {
        jdbc.sql("SELECT platform.record_sms_balance(:r, :v)").param("r", raw, Types.VARCHAR).param("v", value, Types.NUMERIC).query().singleRow();
    }

    /** the watch: the messages queued to the Directorate of ICT (0 while every channel is well or the problem was told) */
    public int watchProviders() {
        return jdbc.sql("SELECT platform.watch_providers()").query(Integer.class).single();
    }
}
