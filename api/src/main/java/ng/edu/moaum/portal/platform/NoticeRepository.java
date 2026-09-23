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
                 WHERE state = 'QUEUED' AND attempts < 5 ORDER BY created_at LIMIT :n
                """).param("n", limit).query(Queued.class).list();
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
        return jdbc.sql("UPDATE platform.notice SET state = 'QUEUED', attempts = 0, last_error = NULL WHERE state = 'FAILED'").update();
    }
}
