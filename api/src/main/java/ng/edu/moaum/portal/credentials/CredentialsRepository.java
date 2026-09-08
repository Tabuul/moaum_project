package ng.edu.moaum.portal.credentials;

import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class CredentialsRepository {

    private static final String TRANSCRIPT_SELECT = """
            SELECT t.id, t.ref, t.student_id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names,
                   t.destination, t.destination_name, t.mode, t.express, t.copies, t.requested_at, t.paid_at, t.stage,
                   t.produced_at, t.produced_by, t.released_at, t.released_by,
                   (SELECT count(*) FROM clearance.position(t.student_id, 'TRANSCRIPT') c
                     WHERE c.unit IN ('BURSARY','LIBRARY','DEPARTMENT') AND c.state = 'CLEARED') AS units_cleared,
                   (SELECT c.label FROM clearance.position(t.student_id, 'TRANSCRIPT') c WHERE c.state <> 'CLEARED'
                     ORDER BY c.ord LIMIT 1) AS held_by,
                   (SELECT c.item FROM clearance.position(t.student_id, 'TRANSCRIPT') c WHERE c.state <> 'CLEARED'
                     ORDER BY c.ord LIMIT 1) AS held_reason
              FROM credentials.transcript_request t JOIN people.student s ON s.id = t.student_id
            """;

    private final JdbcClient jdbc;

    CredentialsRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    List<Credentials.TranscriptRow> transcripts() {
        return jdbc.sql(TRANSCRIPT_SELECT + " ORDER BY t.requested_at").query(Credentials.TranscriptRow.class).list();
    }

    Optional<Credentials.TranscriptRow> transcript(UUID id) {
        return jdbc.sql(TRANSCRIPT_SELECT + " WHERE t.id = :id").param("id", id).query(Credentials.TranscriptRow.class).optional();
    }

    boolean studentExists(UUID id) {
        return jdbc.sql("SELECT count(*) FROM people.student WHERE id = :id").param("id", id).query(Long.class).single() > 0;
    }

    boolean isClear(UUID student, String purpose) {
        return jdbc.sql("SELECT clearance.is_clear(:s, :p)").param("s", student).param("p", purpose).query(Boolean.class).single();
    }

    long next(String kind, String scope, String session) {
        return jdbc.sql("SELECT platform.next_number(:k, :s, :y)").param("k", kind).param("s", scope).param("y", session)
                .query(Long.class).single();
    }

    UUID createTranscript(String ref, CredentialsService.TranscriptIn in, String stage) {
        UUID id = UUID.randomUUID();
        jdbc.sql("""
                INSERT INTO credentials.transcript_request
                       (id, ref, student_id, destination, destination_name, mode, express, copies, paid_at, stage)
                VALUES (:id, :ref, :s, :d, :dn, :m, :x, :c, CASE WHEN :paid THEN now() END, :stage)
                """).param("id", id).param("ref", ref).param("s", in.studentId()).param("d", in.destination())
                .param("dn", in.destinationName(), Types.VARCHAR).param("m", in.mode() == null ? "DIGITAL" : in.mode())
                .param("x", in.express() != null && in.express()).param("c", in.copies() == null ? 1 : in.copies())
                .param("paid", in.paid() != null && in.paid()).param("stage", stage).update();
        return id;
    }

    void markPaid(UUID id, String stage) {
        jdbc.sql("UPDATE credentials.transcript_request SET paid_at = now(), stage = :st WHERE id = :id")
                .param("st", stage).param("id", id).update();
    }

    void setStage(UUID id, String stage) {
        jdbc.sql("UPDATE credentials.transcript_request SET stage = :st WHERE id = :id").param("st", stage).param("id", id).update();
    }

    void produce(UUID id) {
        jdbc.sql("SELECT credentials.produce_transcript(:id)").param("id", id).query().singleRow();
    }

    void release(UUID id) {
        jdbc.sql("SELECT credentials.release_transcript(:id)").param("id", id).query().singleRow();
    }

    List<Credentials.Certificate> certificates(String convocation) {
        return jdbc.sql("""
                SELECT c.id, c.number, c.student_id, s.matric_no, s.surname, s.other_names, c.award, c.class_of_degree,
                       c.convocation, c.serial, b.batch, c.status, c.printed_on, c.collected_on, c.collected_note,
                       c.held_reason, c.issuing_name, c.duplicate_of
                  FROM credentials.certificate c
                  JOIN people.student s ON s.id = c.student_id
                  LEFT JOIN credentials.stationery_batch b ON b.id = c.batch_id
                 WHERE (:conv::text IS NULL OR c.convocation = :conv)
                 ORDER BY c.number DESC
                """).param("conv", convocation).query(Credentials.Certificate.class).list();
    }

    Optional<Credentials.Certificate> certificate(UUID id) {
        return jdbc.sql("""
                SELECT c.id, c.number, c.student_id, s.matric_no, s.surname, s.other_names, c.award, c.class_of_degree,
                       c.convocation, c.serial, b.batch, c.status, c.printed_on, c.collected_on, c.collected_note,
                       c.held_reason, c.issuing_name, c.duplicate_of
                  FROM credentials.certificate c JOIN people.student s ON s.id = c.student_id
                  LEFT JOIN credentials.stationery_batch b ON b.id = c.batch_id
                 WHERE c.id = :id
                """).param("id", id).query(Credentials.Certificate.class).optional();
    }

    List<Credentials.Batch> batches() {
        return jdbc.sql("""
                SELECT b.id, b.batch, b.serial_from, b.serial_to, b.received_on, b.serial_to - b.serial_from + 1 AS issued,
                       (SELECT count(*) FROM credentials.certificate c WHERE c.batch_id = b.id) AS used, b.spoiled, b.returned
                  FROM credentials.stationery_batch b ORDER BY b.received_on DESC, b.batch DESC
                """).query(Credentials.Batch.class).list();
    }

    Optional<Credentials.Batch> batch(UUID id) {
        return batches().stream().filter(b -> b.id().equals(id)).findFirst();
    }

    UUID createBatch(String batch, int from, int to, LocalDate receivedOn) {
        UUID id = UUID.randomUUID();
        jdbc.sql("INSERT INTO credentials.stationery_batch (id, batch, serial_from, serial_to, received_on) VALUES (:id, :b, :f, :t, :r)")
                .param("id", id).param("b", batch).param("f", from).param("t", to).param("r", receivedOn).update();
        return id;
    }

    void countBatch(UUID id, String column, int count) {
        jdbc.sql("UPDATE credentials.stationery_batch SET " + column + " = " + column + " + :n WHERE id = :id")
                .param("n", count).param("id", id).update();
    }

    Integer nextSerial(UUID batchId) {
        return jdbc.sql("""
                SELECT s FROM credentials.stationery_batch b,
                       generate_series(b.serial_from, b.serial_to) AS s
                 WHERE b.id = :id AND NOT EXISTS (SELECT 1 FROM credentials.certificate c WHERE c.batch_id = b.id AND c.serial = s)
                 ORDER BY s LIMIT 1
                """).param("id", batchId).query(Integer.class).optional().orElse(null);
    }

    Optional<Credentials.Graduand> approvedGraduand(UUID student) {
        return jdbc.sql("""
                SELECT g.student_id, s.matric_no, s.surname, s.other_names, g.award, policy.class_of(g.cgpa) AS class_of_degree, g.session
                  FROM records.graduand g JOIN people.student s ON s.id = g.student_id
                 WHERE g.student_id = :s AND g.senate_state = 'APPROVED'
                 ORDER BY g.session DESC LIMIT 1
                """).param("s", student).query(Credentials.Graduand.class).optional();
    }

    List<Credentials.Graduand> awaitingPrint() {
        return jdbc.sql("""
                SELECT g.student_id, s.matric_no, s.surname, s.other_names, g.award, policy.class_of(g.cgpa) AS class_of_degree, g.session
                  FROM records.graduand g JOIN people.student s ON s.id = g.student_id
                 WHERE g.senate_state = 'APPROVED'
                   AND NOT EXISTS (SELECT 1 FROM credentials.certificate c WHERE c.student_id = g.student_id AND c.status <> 'REVOKED')
                 ORDER BY s.surname, s.other_names
                """).query(Credentials.Graduand.class).list();
    }

    long approvedGraduands(String session) {
        return jdbc.sql("SELECT count(*) FROM records.graduand WHERE senate_state = 'APPROVED' AND (:s::text IS NULL OR session = :s)")
                .param("s", session).query(Long.class).single();
    }

    UUID insertCertificate(String number, UUID student, String award, String cls, String convocation, Integer serial,
                           UUID batchId, UUID duplicateOf) {
        UUID id = UUID.randomUUID();
        jdbc.sql("""
                INSERT INTO credentials.certificate (id, number, student_id, award, class_of_degree, convocation, serial, batch_id, duplicate_of)
                VALUES (:id, :n, :s, :a, :c, :conv, :serial, :b, :dup)
                """).param("id", id).param("n", number).param("s", student).param("a", award).param("c", cls)
                .param("conv", convocation).param("serial", serial, Types.INTEGER).param("b", batchId, Types.OTHER)
                .param("dup", duplicateOf, Types.OTHER).update();
        return id;
    }

    void setCertificate(UUID id, String status, LocalDate collectedOn, String collectedNote, String heldReason) {
        jdbc.sql("""
                UPDATE credentials.certificate
                   SET status = :st, collected_on = coalesce(:on, collected_on), collected_note = coalesce(:note, collected_note),
                       held_reason = :held
                 WHERE id = :id
                """).param("st", status).param("on", collectedOn, Types.DATE).param("note", collectedNote, Types.VARCHAR)
                .param("held", heldReason, Types.VARCHAR).param("id", id).update();
    }
}
