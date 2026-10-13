package ng.edu.moaum.portal.privacy;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** V441: the legal documents, the privacy contact, the acceptances and the person's own requests — every rule is the database's. */
@Repository
class PrivacyRepository {

    private static final String DOC = """
            SELECT d.id, d.kind, d.version, d.status, d.title, d.summary, d.sections::text AS sections, d.review_points::text AS review_points,
                   d.requires_acceptance, d.effective_on, d.created_at, d.updated_at, d.published_at, d.archived_at, d.archive_note,
                   coalesce(c.surname || ', ' || c.given_names, '') AS created_by_name,
                   coalesce(u.surname || ', ' || u.given_names, '') AS updated_by_name,
                   coalesce(p.surname || ', ' || p.given_names, '') AS published_by_name,
                   (SELECT count(*) FROM jsonb_array_elements(d.review_points) r WHERE r->>'confirmed_at' IS NULL)::int AS review_pending
              FROM platform.legal_document d
              LEFT JOIN iam.person c ON c.id = d.created_by
              LEFT JOIN iam.person u ON u.id = d.updated_by
              LEFT JOIN iam.person p ON p.id = d.published_by
            """;

    private final JdbcClient jdbc;

    PrivacyRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Optional<Map<String, Object>> published(String kind) {
        return jdbc.sql(DOC + " WHERE d.kind = :k AND d.status = 'PUBLISHED'").param("k", kind).query().listOfRows().stream().findFirst();
    }

    Optional<Map<String, Object>> document(UUID id) {
        return jdbc.sql(DOC + " WHERE d.id = :id").param("id", id).query().listOfRows().stream().findFirst();
    }

    List<Map<String, Object>> documents() {
        return jdbc.sql(DOC + " ORDER BY d.kind, d.version DESC").query().listOfRows();
    }

    Map<String, Object> draft(String kind, UUID actor, String office) {
        return jdbc.sql("SELECT id FROM platform.legal_document_draft(:k, :a, :o)").param("k", kind).param("a", actor).param("o", office)
                .query().singleRow();
    }

    void update(UUID id, String title, String summary, String sectionsJson, java.time.LocalDate effectiveOn, Boolean requires, UUID actor, String office) {
        jdbc.sql("SELECT id FROM platform.legal_document_update(:id, :t, :s, CAST(:j AS jsonb), :e, :r, :a, :o)")
                .param("id", id).param("t", title).param("s", summary, Types.VARCHAR).param("j", sectionsJson)
                .param("e", effectiveOn, Types.DATE).param("r", requires, Types.BOOLEAN).param("a", actor).param("o", office)
                .query().listOfRows();
    }

    void review(UUID id, String key, boolean confirmed, UUID actor, String office) {
        jdbc.sql("SELECT id FROM platform.legal_review_confirm(:id, :k, :c, :a, :o)")
                .param("id", id).param("k", key).param("c", confirmed).param("a", actor).param("o", office).query().listOfRows();
    }

    void publish(UUID id, java.time.LocalDate effectiveOn, UUID actor, String office) {
        jdbc.sql("SELECT id FROM platform.legal_document_publish(:id, :e, :a, :o)")
                .param("id", id).param("e", effectiveOn, Types.DATE).param("a", actor).param("o", office).query().listOfRows();
    }

    void withdraw(UUID id, UUID actor, String office) {
        jdbc.sql("SELECT id FROM platform.legal_document_withdraw(:id, :a, :o)").param("id", id).param("a", actor).param("o", office).query().listOfRows();
    }

    Map<String, Object> contact() {
        return jdbc.sql("""
                SELECT c.dpo_name, c.dpo_title, c.dpo_office, c.dpo_email, c.dpo_phone, c.dpo_address, c.request_days, c.note, c.updated_at, c.updated_office,
                       coalesce(p.surname || ', ' || p.given_names, '') AS updated_by_name
                  FROM platform.privacy_contact c LEFT JOIN iam.person p ON p.id = c.updated_by WHERE c.id = true
                """).query().singleRow();
    }

    void setContact(String name, String title, String office, String email, String phone, String address, int days, String note, UUID actor, String acting) {
        jdbc.sql("SELECT id FROM platform.privacy_contact_set(:n, :t, :o, :e, :p, :ad, :d, :note, :a, :acting)")
                .param("n", name, Types.VARCHAR).param("t", title, Types.VARCHAR).param("o", office, Types.VARCHAR).param("e", email, Types.VARCHAR)
                .param("p", phone, Types.VARCHAR).param("ad", address, Types.VARCHAR).param("d", days).param("note", note, Types.VARCHAR)
                .param("a", actor).param("acting", acting).query().listOfRows();
    }

    /** the University as the institution profile names it (V320) — the tokens the document is read with */
    Map<String, Object> institution() {
        return jdbc.sql("SELECT name, short_name, motto, address, city, state, country, phone, email, website FROM platform.institution_profile LIMIT 1")
                .query().listOfRows().stream().findFirst().orElseGet(LinkedHashMap::new);
    }

    boolean smsOn() {
        return jdbc.sql("SELECT enabled FROM platform.sms_settings WHERE id = true").query(Boolean.class).optional().orElse(false);
    }

    boolean mailOn() {
        return jdbc.sql("SELECT count(*) > 0 FROM platform.mail_settings WHERE smtp_host IS NOT NULL").query(Boolean.class).optional().orElse(false);
    }

    List<Map<String, Object>> needed(String subjectKind, UUID subject) {
        return jdbc.sql("SELECT document_id, kind, version, title, effective_on::text AS effective_on, published_at FROM platform.policy_acceptance_needed(:k, :id)")
                .param("k", subjectKind).param("id", subject).query().listOfRows();
    }

    List<Map<String, Object>> accepted(String subjectKind, UUID subject) {
        return jdbc.sql("SELECT kind, version, accepted_at, channel FROM platform.policy_acceptance WHERE subject_kind = :k AND subject_id = :id AND withdrawn_at IS NULL ORDER BY accepted_at DESC")
                .param("k", subjectKind).param("id", subject).query().listOfRows();
    }

    boolean accept(String subjectKind, UUID subject, UUID document, String ip, String userAgent, String channel) {
        return jdbc.sql("SELECT platform.policy_accept(:k, :id, :d, :ip, :ua, :c)")
                .param("k", subjectKind).param("id", subject).param("d", document).param("ip", ip, Types.VARCHAR).param("ua", userAgent, Types.VARCHAR)
                .param("c", channel).query(Boolean.class).single();
    }

    List<Map<String, Object>> acceptanceSummary(UUID document) {
        return jdbc.sql("SELECT subject_kind, accepted, withdrawn, last_at FROM platform.policy_acceptance_summary(:d)").param("d", document).query().listOfRows();
    }

    String fileRequest(String kind, String subjectKind, UUID subject, String contact, String detail) {
        return jdbc.sql("SELECT governance.dsr_file(:k, :sk, :id, :c, :d)")
                .param("k", kind).param("sk", subjectKind).param("id", subject).param("c", contact, Types.VARCHAR).param("d", detail).query(String.class).single();
    }

    List<Map<String, Object>> myRequests(String subjectKind, UUID subject) {
        return jdbc.sql("SELECT reference, kind, received_on, due_on, state, detail FROM governance.dsr_mine(:k, :id)")
                .param("k", subjectKind).param("id", subject).query().listOfRows();
    }

    /** who changed the documents and the contact, from the audit spine */
    List<Map<String, Object>> history(int limit) {
        return jdbc.sql("""
                SELECT e.occurred_at, e.actor_office, e.action, e.subject_type, e.subject_id, e.reason,
                       coalesce(p.surname || ', ' || p.given_names, 'Unknown') AS actor,
                       e.after_state->>'kind' AS kind, e.after_state->>'version' AS version, e.after_state->>'status' AS status
                  FROM audit.entries e LEFT JOIN iam.person p ON p.id = e.actor_id
                 WHERE e.subject_type IN ('platform.legal_document', 'platform.privacy_contact')
                 ORDER BY e.occurred_at DESC LIMIT :n
                """).param("n", Math.max(1, Math.min(limit, 500))).query().listOfRows();
    }
}
