package ng.edu.moaum.portal.auth;

import java.sql.Types;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class AuthRepository {

    private final JdbcClient jdbc;

    AuthRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    record Credential(UUID personId, String username, String passwordHash, boolean mustChange, int failedAttempts,
                      OffsetDateTime lockedUntil, String surname, String givenNames, String staffNumber, LocalDate endedOn) {
    }

    Optional<Credential> byUsername(String username) {
        return jdbc.sql("""
                SELECT c.person_id, c.username, c.password_hash, c.must_change, c.failed_attempts, c.locked_until,
                       p.surname, p.given_names, p.staff_number, p.ended_on
                  FROM iam.credential c JOIN iam.person p ON p.id = c.person_id
                 WHERE c.username = :u
                """).param("u", username).query(Credential.class).optional();
    }

    Optional<Credential> byPerson(UUID person) {
        return jdbc.sql("""
                SELECT c.person_id, c.username, c.password_hash, c.must_change, c.failed_attempts, c.locked_until,
                       p.surname, p.given_names, p.staff_number, p.ended_on
                  FROM iam.credential c JOIN iam.person p ON p.id = c.person_id
                 WHERE c.person_id = :p
                """).param("p", person).query(Credential.class).optional();
    }

    record Office(String officeCode, String label, String scopeKind, String scopeId, LocalDate validTo) {
    }

    List<Office> liveOffices(UUID person) {
        return jdbc.sql("SELECT office_code, label, scope_kind, scope_id, valid_to FROM iam.live_offices(:p)")
                .param("p", person).query(Office.class).list();
    }

    void failed(UUID person, int attempts, OffsetDateTime lockedUntil) {
        jdbc.sql("UPDATE iam.credential SET failed_attempts = :n, locked_until = :until WHERE person_id = :p")
                .param("n", attempts).param("until", lockedUntil, Types.TIMESTAMP_WITH_TIMEZONE).param("p", person).update();
    }

    void signedIn(UUID person) {
        jdbc.sql("UPDATE iam.credential SET failed_attempts = 0, locked_until = NULL, last_sign_in_at = now() WHERE person_id = :p")
                .param("p", person).update();
    }

    void event(String username, UUID person, String outcome, String ip, byte[] session) {
        jdbc.sql("""
                INSERT INTO iam.sign_in_event (id, username, person_id, outcome, source_ip, session_id)
                VALUES (gen_random_uuid(), :u, :p, :o, CAST(:ip AS inet), :s)
                """).param("u", username).param("p", person, Types.OTHER).param("o", outcome)
                .param("ip", ip, Types.VARCHAR).param("s", session, Types.BINARY).update();
    }

    void openSession(byte[] id, UUID person, String office, Instant absoluteEnd) {
        jdbc.sql("INSERT INTO platform.session (id, person_id, active_office, absolute_end) VALUES (:id, :p, :o, :end)")
                .param("id", id).param("p", person).param("o", office).param("end", absoluteEnd.atOffset(java.time.ZoneOffset.UTC)).update();
    }

    int endSession(byte[] id, UUID person, String reason) {
        return jdbc.sql("""
                UPDATE platform.session SET ended_at = now(), ended_reason = :r
                 WHERE id = :id AND person_id = :p AND ended_at IS NULL
                """).param("r", reason).param("id", id).param("p", person).update();
    }

    record Session(String id, String activeOffice, OffsetDateTime issuedAt, OffsetDateTime lastSeenAt, OffsetDateTime absoluteEnd) {
    }

    List<Session> sessions(UUID person) {
        return jdbc.sql("""
                SELECT encode(id, 'hex') AS id, active_office, issued_at, last_seen_at, absolute_end
                  FROM platform.session WHERE person_id = :p AND ended_at IS NULL AND absolute_end > now()
                 ORDER BY last_seen_at DESC
                """).param("p", person).query(Session.class).list();
    }

    void setCredential(UUID person, String username, String hash, boolean mustChange, UUID by, String kind) {
        jdbc.sql("""
                INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by)
                VALUES (:p, :u, :h, :m, :by)
                ON CONFLICT (person_id) DO UPDATE SET username = EXCLUDED.username, password_hash = EXCLUDED.password_hash,
                        must_change = EXCLUDED.must_change, failed_attempts = 0, locked_until = NULL, set_at = now(), set_by = EXCLUDED.set_by
                """).param("p", person).param("u", username).param("h", hash).param("m", mustChange).param("by", by).update();
        jdbc.sql("INSERT INTO iam.credential_event (id, person_id, kind, by_person) VALUES (gen_random_uuid(), :p, :k, :by)")
                .param("p", person).param("k", kind).param("by", by).update();
    }

    boolean usernameTaken(String username, UUID exceptPerson) {
        return jdbc.sql("SELECT count(*) FROM iam.credential WHERE username = :u AND person_id <> :p")
                .param("u", username).param("p", exceptPerson).query(Long.class).single() > 0;
    }

    long credentials() {
        return jdbc.sql("SELECT count(*) FROM iam.credential").query(Long.class).single();
    }

    UUID createPerson(String staffNumber, String surname, String givenNames) {
        UUID id = UUID.randomUUID();
        jdbc.sql("INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (:id, :n, :s, :g)")
                .param("id", id).param("n", staffNumber, Types.VARCHAR).param("s", surname).param("g", givenNames).update();
        return id;
    }

    void grant(UUID person, String office, String scopeKind, String instrument, UUID by) {
        jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, :o, :k, :i, :by, current_date)
                """).param("p", person).param("o", office).param("k", scopeKind).param("i", instrument).param("by", by).update();
    }

    record OfficeRow(String code, String label, String scopeKind) {
    }

    List<OfficeRow> offices() {
        return jdbc.sql("SELECT code, label, scope_kind FROM ref.office ORDER BY label").query(OfficeRow.class).list();
    }
}
