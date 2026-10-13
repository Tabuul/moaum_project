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
                       count(*) FILTER (WHERE state = 'FAILED' AND last_error IN ('INVALID_EMAIL', 'INVALID_PHONE')) AS invalid,
                       count(*) FILTER (WHERE created_at > now() - interval '7 days') AS week,
                       count(*) FILTER (WHERE state = 'SENT' AND sent_at > now() - interval '7 days') AS week_sent,
                       count(*) FILTER (WHERE state = 'FAILED' AND created_at > now() - interval '7 days') AS week_failed
                  FROM platform.notice GROUP BY channel ORDER BY channel
                """).query().listOfRows();
    }

    public void sent(UUID id, String providerRef) {
        jdbc.sql("UPDATE platform.notice SET state = 'SENT', sent_at = now(), attempts = attempts + 1, provider_ref = :r, last_error = NULL WHERE id = :id")
                .param("r", providerRef, Types.VARCHAR).param("id", id).update();
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
                SELECT id, channel, recipient, subject, about_kind, about_id, created_at, state, attempts, sent_at, last_error
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
}
