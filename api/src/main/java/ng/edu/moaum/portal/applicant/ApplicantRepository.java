package ng.edu.moaum.portal.applicant;

import java.sql.Types;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** The applicant's rows (V021), read and written through the database's own functions. */
@Repository
class ApplicantRepository {

    private final JdbcClient jdbc;

    ApplicantRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Map<String, Object> lookup(String session, String jambKey) {
        return jdbc.sql("SELECT * FROM admissions.applicant_lookup(:s, :k)").param("s", session).param("k", jambKey).query().singleRow();
    }

    UUID register(String session, String jambKey, String email, String phone, String hash) {
        return jdbc.sql("SELECT admissions.register_applicant(:s, :k, :e, :p, :h)")
                .param("s", session).param("k", jambKey).param("e", email).param("p", phone).param("h", hash)
                .query(UUID.class).single();
    }

    record Account(UUID id, String session, UUID candidateId, String jambKey, String email, String phone, String passwordHash,
                   int failedAttempts, OffsetDateTime lockedUntil, UUID applicationId, String applicationNo, String surname, String otherNames) {
    }

    private static final String ACCOUNT = """
            SELECT a.id, a.session, a.candidate_id, a.jamb_key, a.email, a.phone, a.password_hash, a.failed_attempts, a.locked_until,
                   p.id AS application_id, p.application_no, c.surname, c.other_names
              FROM admissions.applicant_account a
              JOIN admissions.application p ON p.account_id = a.id
              JOIN admissions.candidate c ON c.id = a.candidate_id
            """;

    /** by application number, by email, or by JAMB number — whatever the applicant has to hand */
    Optional<Account> byIdentifier(String identifier) {
        String id = identifier == null ? "" : identifier.trim();
        return jdbc.sql(ACCOUNT + " WHERE lower(a.email) = lower(:id) OR a.jamb_key = upper(:id) OR p.application_no = upper(:id) LIMIT 1")
                .param("id", id).query(Account.class).optional();
    }

    Optional<Account> byId(UUID id) {
        return jdbc.sql(ACCOUNT + " WHERE a.id = :id").param("id", id).query(Account.class).optional();
    }

    void failed(UUID account, int attempts, OffsetDateTime lockedUntil) {
        jdbc.sql("UPDATE admissions.applicant_account SET failed_attempts = :n, locked_until = :until WHERE id = :id")
                .param("n", attempts).param("until", lockedUntil, Types.TIMESTAMP_WITH_TIMEZONE).param("id", account).update();
    }

    void signedIn(UUID account) {
        jdbc.sql("UPDATE admissions.applicant_account SET failed_attempts = 0, locked_until = NULL, last_signed_in_at = now() WHERE id = :id")
                .param("id", account).update();
    }

    void event(String identifier, UUID account, String outcome, String ip) {
        jdbc.sql("INSERT INTO admissions.applicant_event (account_id, identifier, outcome, ip) VALUES (:a, :i, :o, :ip)")
                .param("a", account, Types.OTHER).param("i", identifier == null ? "" : identifier).param("o", outcome).param("ip", ip, Types.VARCHAR).update();
    }

    void openSession(byte[] id, UUID account, Instant absoluteEnd) {
        jdbc.sql("INSERT INTO platform.session (id, person_id, active_office, absolute_end) VALUES (:id, :p, 'applicant', :end)")
                .param("id", id).param("p", account).param("end", absoluteEnd.atOffset(java.time.ZoneOffset.UTC)).update();
    }

    void endSession(byte[] id, UUID account) {
        jdbc.sql("UPDATE platform.session SET ended_at = now(), ended_reason = 'signed out' WHERE id = :id AND person_id = :p AND ended_at IS NULL")
                .param("id", id).param("p", account).update();
    }

    /* ── the application ── */

    Optional<Map<String, Object>> application(UUID applicationId) {
        return jdbc.sql("""
                SELECT a.*, admissions.application_stage(a.id) AS stage,
                       c.surname, c.other_names, c.programme, c.entry_mode, c.entry_level, c.offer_state, c.jamb_reg_no,
                       r.sex, r.state_of_origin, r.lga, r.aggregate AS utme, b.list_kind,
                       (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS programme_code,
                       (SELECT f.name FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS faculty_name,
                       (SELECT d.payload ->> 'dob' FROM admissions.attachment d WHERE d.candidate_id = c.id AND d.kind = 'DATE_OF_BIRTH' ORDER BY d.arrived_at DESC LIMIT 1) AS dob,
                       acc.email, acc.phone,
                       s.admission_no, s.matric_no, s.programme_code AS student_programme, s.id AS student_id,
                       sb.label AS batch_label, sb.held_on, sb.starts_at, sb.ends_at, sb.venue
                  FROM admissions.application a
                  JOIN admissions.applicant_account acc ON acc.id = a.account_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id
                  LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
                  LEFT JOIN admissions.caps_batch b ON b.id = r.batch_id
                  LEFT JOIN people.student s ON s.candidate_id = c.id
                  LEFT JOIN admissions.screening_batch sb ON sb.id = a.screening_batch_id
                 WHERE a.id = :id
                """).param("id", applicationId).query().listOfRows().stream().findFirst();
    }

    List<Map<String, Object>> sittings(String session, String jambKey) {
        return jdbc.sql("""
                SELECT st.id, st.exam_body, st.exam_type_raw, st.exam_year, st.exam_number,
                       (SELECT json_agg(json_build_object('subject', g.subject, 'grade', g.grade) ORDER BY g.subject)::text
                          FROM admissions.olevel_grade g WHERE g.sitting_id = st.id) AS subjects
                  FROM admissions.olevel_sitting st WHERE st.session = :s AND st.jamb_key = :k
                 ORDER BY st.exam_year NULLS LAST, st.ord
                """).param("s", session).param("k", jambKey).query().listOfRows();
    }

    List<Map<String, Object>> feeReferences(UUID applicationId) {
        return jdbc.sql("""
                SELECT id, kind, reference, amount, generated_at, expires_at, confirmed_at, channel
                  FROM admissions.fee_reference WHERE application_id = :id ORDER BY generated_at DESC
                """).param("id", applicationId).query().listOfRows();
    }

    List<Map<String, Object>> documents(UUID applicationId) {
        return jdbc.sql("""
                SELECT id, kind, filename, content_type, bytes, uploaded_at, status, reviewed_at, review_note
                  FROM admissions.application_document WHERE application_id = :id AND superseded_at IS NULL ORDER BY kind
                """).param("id", applicationId).query().listOfRows();
    }

    List<Map<String, Object>> clearance(UUID applicationId) {
        return jdbc.sql("SELECT item, state, note, decided_at FROM admissions.clearance_document WHERE application_id = :id")
                .param("id", applicationId).query().listOfRows();
    }

    Map<String, Object> fees(String session) {
        return jdbc.sql("SELECT * FROM admissions.applicant_fee_rule(:s)").param("s", session).query().singleRow();
    }

    Optional<Map<String, Object>> screeningResult(UUID applicationId) {
        return jdbc.sql("SELECT * FROM admissions.screening_result(:id)").param("id", applicationId).query().listOfRows().stream().findFirst();
    }

    void nextOfKin(UUID applicationId, String text) {
        jdbc.sql("UPDATE admissions.application SET next_of_kin = :t WHERE id = :id AND submitted_at IS NULL")
                .param("t", text).param("id", applicationId).update();
    }

    String newFeeReference(UUID applicationId, String kind) {
        return jdbc.sql("SELECT admissions.new_fee_reference(:id, :k)").param("id", applicationId).param("k", kind).query(String.class).single();
    }

    UUID storeDocument(UUID applicationId, String kind, String filename, String contentType, byte[] content) {
        UUID id = UUID.randomUUID();
        jdbc.sql("UPDATE admissions.application_document SET superseded_at = now() WHERE application_id = :a AND kind = :k AND superseded_at IS NULL")
                .param("a", applicationId).param("k", kind).update();
        jdbc.sql("""
                INSERT INTO admissions.application_document (id, application_id, kind, filename, content_type, bytes)
                VALUES (:id, :a, :k, :f, :t, :b)
                """).param("id", id).param("a", applicationId).param("k", kind).param("f", filename).param("t", contentType).param("b", content.length).update();
        jdbc.sql("INSERT INTO admissions.application_document_blob (document_id, content) VALUES (:id, :c)")
                .param("id", id).param("c", content).update();
        return id;
    }

    Optional<DocumentContent> documentContent(UUID documentId, UUID applicationId) {
        return jdbc.sql("""
                SELECT d.filename, d.content_type, b.content
                  FROM admissions.application_document d JOIN admissions.application_document_blob b ON b.document_id = d.id
                 WHERE d.id = :id AND (:a::uuid IS NULL OR d.application_id = :a)
                """).param("id", documentId).param("a", applicationId, Types.OTHER).query(DocumentContent.class).optional();
    }

    String submit(UUID applicationId, String ip) {
        return jdbc.sql("SELECT admissions.submit_application(:id, :ip)").param("id", applicationId).param("ip", ip, Types.VARCHAR).query(String.class).single();
    }

    String undertaking(UUID applicationId) {
        return jdbc.sql("SELECT admissions.sign_undertaking(:id)").param("id", applicationId).query(String.class).single();
    }

    String decline(UUID applicationId) {
        return jdbc.sql("SELECT admissions.decline_offer(:id)").param("id", applicationId).query(String.class).single();
    }

    /* ── the notices sent about this application (V025) ── */

    List<Map<String, Object>> notices(UUID applicationId) {
        return jdbc.sql("""
                SELECT id, channel, recipient, subject, body, created_at, state, sent_at
                  FROM platform.notice WHERE about_kind = 'application' AND about_id = :id ORDER BY created_at DESC LIMIT 30
                """).param("id", applicationId).query().listOfRows();
    }

    void queueNotice(String channel, String recipient, String subject, String body, UUID applicationId) {
        jdbc.sql("SELECT platform.queue_notice(:c, :r, :s, :b, 'application', :a)")
                .param("c", channel).param("r", recipient).param("s", subject).param("b", body).param("a", applicationId).query().singleRow();
    }

    /* ── the password reset (V025) ── */

    void newReset(UUID account, String tokenHash, Instant expires) {
        jdbc.sql("INSERT INTO admissions.password_reset (account_id, token_hash, expires_at) VALUES (:a, :h, :e)")
                .param("a", account).param("h", tokenHash).param("e", expires.atOffset(java.time.ZoneOffset.UTC)).update();
    }

    record Reset(UUID id, UUID accountId, OffsetDateTime expiresAt, OffsetDateTime usedAt) {
    }

    Optional<Reset> resetByHash(String tokenHash) {
        return jdbc.sql("SELECT id, account_id, expires_at, used_at FROM admissions.password_reset WHERE token_hash = :h")
                .param("h", tokenHash).query(Reset.class).optional();
    }

    void useReset(UUID id) {
        jdbc.sql("UPDATE admissions.password_reset SET used_at = now() WHERE id = :id").param("id", id).update();
    }

    void setPassword(UUID account, String hash) {
        jdbc.sql("UPDATE admissions.applicant_account SET password_hash = :h, failed_attempts = 0, locked_until = NULL WHERE id = :id")
                .param("h", hash).param("id", account).update();
        jdbc.sql("UPDATE platform.session SET ended_at = now(), ended_reason = 'password reset' WHERE person_id = :id AND ended_at IS NULL")
                .param("id", account).update();
    }
}
