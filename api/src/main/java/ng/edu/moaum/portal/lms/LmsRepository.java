package ng.edu.moaum.portal.lms;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class LmsRepository {

    record FileContent(String filename, String contentType, byte[] content) {
    }

    private final JdbcClient jdbc;

    LmsRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    String currentSession() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027");
    }

    /* ── the roll ── */

    boolean onRoll(UUID offering, UUID student) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT lms.on_roll(:o, :s)").param("o", offering).param("s", student).query(Boolean.class).single());
    }

    boolean teaches(UUID offering, UUID person) {
        return Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM catalogue.offering WHERE id = :o AND (lecturer_id = :p OR second_examiner_id = :p))")
                .param("o", offering).param("p", person).query(Boolean.class).single());
    }

    /** the student's spaces: every approved registration in the session */
    List<Map<String, Object>> studentSpaces(UUID student, String session) {
        return jdbc.sql("""
                SELECT o.id AS offering_id, o.course_code, c.title, c.units, o.semester,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS lecturer,
                       (SELECT count(*) FROM lms.material m WHERE m.offering_id = o.id AND m.published_at IS NOT NULL AND m.ended_at IS NULL) AS materials,
                       (SELECT count(DISTINCT a.material_id) FROM lms.access a JOIN lms.material m ON m.id = a.material_id
                         WHERE m.offering_id = o.id AND m.published_at IS NOT NULL AND m.ended_at IS NULL AND a.student_id = :s) AS accessed,
                       (SELECT count(*) FROM lms.assignment x WHERE x.offering_id = o.id AND x.ended_at IS NULL AND now() BETWEEN x.opens_at AND x.closes_at
                          AND NOT EXISTS (SELECT 1 FROM lms.submission sb WHERE sb.assignment_id = x.id AND sb.student_id = :s)) AS due,
                       (SELECT max(m.week) FROM lms.material m WHERE m.offering_id = o.id AND m.published_at IS NOT NULL) AS weeks
                  FROM registration.course_registration r
                  JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN iam.person p ON p.id = o.lecturer_id
                 WHERE r.student_id = :s AND r.session = :n AND r.status IN ('APPROVED','LOCKED')
                 ORDER BY o.semester, o.course_code
                """).param("s", student).param("n", session).query().listOfRows();
    }

    /** the lecturer's spaces: the offerings allocated to them in the session */
    List<Map<String, Object>> lecturerSpaces(UUID person, String session) {
        return jdbc.sql("""
                SELECT o.id AS offering_id, o.course_code, c.title, c.units, o.semester, lms.roll_size(o.id) AS enrolled,
                       (SELECT count(*) FROM lms.material m WHERE m.offering_id = o.id AND m.ended_at IS NULL) AS materials,
                       (SELECT count(*) FROM lms.assignment x WHERE x.offering_id = o.id AND x.ended_at IS NULL) AS assignments
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                 WHERE (o.lecturer_id = :p OR o.second_examiner_id = :p) AND o.session = :n
                 ORDER BY o.semester, o.course_code
                """).param("p", person).param("n", session).query().listOfRows();
    }

    Map<String, Object> offering(UUID id) {
        return jdbc.sql("""
                SELECT o.id AS offering_id, o.course_code, c.title, c.units, o.session, o.semester, lms.roll_size(o.id) AS enrolled,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS lecturer,
                       (SELECT sh.stage FROM assessment.score_sheet sh
                          LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
                         WHERE sh.offering_id = o.id AND coalesce(es.kind, 'MAIN') = 'MAIN' LIMIT 1) AS sheet_stage
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code LEFT JOIN iam.person p ON p.id = o.lecturer_id
                 WHERE o.id = :o
                """).param("o", id).query().singleRow();
    }

    /* ── material ── */

    List<Map<String, Object>> materials(UUID offering, boolean publishedOnly, UUID student) {
        return jdbc.sql("""
                SELECT m.id, m.week, m.title, m.kind, m.description, m.filename, m.content_type, m.bytes, m.link, m.published_at, m.created_at,
                       (SELECT count(DISTINCT a.student_id) FROM lms.access a WHERE a.material_id = m.id) AS readers,
                       (:s::uuid IS NOT NULL AND EXISTS (SELECT 1 FROM lms.access a WHERE a.material_id = m.id AND a.student_id = :s)) AS read_by_me
                  FROM lms.material m
                 WHERE m.offering_id = :o AND m.ended_at IS NULL AND (NOT :pub OR m.published_at IS NOT NULL)
                 ORDER BY m.week NULLS LAST, m.created_at DESC
                """).param("o", offering).param("pub", publishedOnly).param("s", student, Types.OTHER).query().listOfRows();
    }

    UUID addMaterial(UUID offering, Integer week, String title, String kind, String description, String filename, String contentType, byte[] content,
                     String link, boolean publish, UUID by) {
        UUID id = UUID.randomUUID();
        jdbc.sql("""
                INSERT INTO lms.material (id, offering_id, week, title, kind, description, filename, content_type, bytes, link, published_at, published_by)
                VALUES (:id, :o, :w, :t, :k, :d, :f, :c, :b, :l, CASE WHEN :p THEN now() END, CASE WHEN :p THEN :by END)
                """).param("id", id).param("o", offering).param("w", week, Types.INTEGER).param("t", title).param("k", kind).param("d", description, Types.VARCHAR)
                .param("f", filename, Types.VARCHAR).param("c", contentType, Types.VARCHAR).param("b", content == null ? null : (long) content.length, Types.BIGINT)
                .param("l", link, Types.VARCHAR).param("p", publish).param("by", by).update();
        if (content != null) {
            jdbc.sql("INSERT INTO lms.material_blob (material_id, content) VALUES (:id, :c)").param("id", id).param("c", content).update();
        }
        return id;
    }

    int publish(UUID material, UUID offering, UUID by) {
        return jdbc.sql("UPDATE lms.material SET published_at = now(), published_by = :by WHERE id = :m AND offering_id = :o AND published_at IS NULL")
                .param("by", by).param("m", material).param("o", offering).update();
    }

    int endMaterial(UUID material, UUID offering) {
        return jdbc.sql("UPDATE lms.material SET ended_at = now() WHERE id = :m AND offering_id = :o AND ended_at IS NULL").param("m", material).param("o", offering).update();
    }

    Optional<FileContent> materialContent(UUID material) {
        return jdbc.sql("""
                SELECT m.filename, m.content_type, b.content FROM lms.material m JOIN lms.material_blob b ON b.material_id = m.id
                 WHERE m.id = :m AND m.ended_at IS NULL
                """).param("m", material).query(FileContent.class).optional();
    }

    Optional<UUID> offeringOfMaterial(UUID material) {
        return jdbc.sql("SELECT offering_id FROM lms.material WHERE id = :m AND published_at IS NOT NULL").param("m", material).query(UUID.class).optional();
    }

    void countRead(UUID material, UUID student) {
        jdbc.sql("INSERT INTO lms.access (material_id, student_id) VALUES (:m, :s)").param("m", material).param("s", student).update();
    }

    /* ── assignments ── */

    List<Map<String, Object>> assignments(UUID offering, UUID student) {
        return jdbc.sql("""
                SELECT a.id, a.title, a.brief, a.kind, a.opens_at, a.closes_at, a.late_hours, a.late_penalty, a.weight, a.out_of, a.created_at,
                       (SELECT count(*) FROM lms.submission s WHERE s.assignment_id = a.id) AS submitted,
                       (SELECT count(*) FROM lms.submission s WHERE s.assignment_id = a.id AND s.mark IS NOT NULL) AS marked,
                       lms.roll_size(a.offering_id) AS enrolled,
                       s.id AS my_submission_id, s.submitted_at AS my_submitted_at, s.late AS my_late, s.mark AS my_mark, s.feedback AS my_feedback, s.filename AS my_filename, s.text AS my_text
                  FROM lms.assignment a
                  LEFT JOIN lms.submission s ON s.assignment_id = a.id AND s.student_id = :s
                 WHERE a.offering_id = :o AND a.ended_at IS NULL ORDER BY a.closes_at DESC
                """).param("o", offering).param("s", student, Types.OTHER).query().listOfRows();
    }

    UUID addAssignment(UUID offering, String title, String brief, String kind, OffsetDateTime opens, OffsetDateTime closes, Integer lateHours, Integer latePenalty, int weight, Integer outOf, UUID by) {
        UUID id = UUID.randomUUID();
        jdbc.sql("""
                INSERT INTO lms.assignment (id, offering_id, title, brief, kind, opens_at, closes_at, late_hours, late_penalty, weight, out_of, created_by)
                VALUES (:id, :o, :t, :b, :k, coalesce(:op, now()), :cl, coalesce(:lh, 48), coalesce(:lp, 10), :w, coalesce(:oo, 100), :by)
                """).param("id", id).param("o", offering).param("t", title).param("b", brief, Types.VARCHAR).param("k", kind)
                .param("op", opens, Types.TIMESTAMP_WITH_TIMEZONE).param("cl", closes).param("lh", lateHours, Types.INTEGER).param("lp", latePenalty, Types.INTEGER)
                .param("w", weight).param("oo", outOf, Types.INTEGER).param("by", by).update();
        return id;
    }

    UUID submit(UUID assignment, UUID student, String text, String filename, String contentType, byte[] content) {
        UUID id = jdbc.sql("SELECT lms.submit(:a, :s, :t, :f, :c, :b)").param("a", assignment).param("s", student).param("t", text, Types.VARCHAR)
                .param("f", filename, Types.VARCHAR).param("c", contentType, Types.VARCHAR).param("b", content == null ? null : (long) content.length, Types.BIGINT)
                .query(UUID.class).single();
        if (content != null) {
            jdbc.sql("INSERT INTO lms.submission_blob (submission_id, content) VALUES (:id, :c)").param("id", id).param("c", content).update();
        }
        return id;
    }

    List<Map<String, Object>> submissions(UUID assignment) {
        return jdbc.sql("""
                SELECT s.id, s.submitted_at, s.late, s.mark, s.marked_at, s.feedback, s.filename, s.text, s.bytes,
                       st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name
                  FROM lms.submission s JOIN people.student st ON st.id = s.student_id
                 WHERE s.assignment_id = :a ORDER BY st.surname, st.other_names
                """).param("a", assignment).query().listOfRows();
    }

    Optional<UUID> offeringOfAssignment(UUID assignment) {
        return jdbc.sql("SELECT offering_id FROM lms.assignment WHERE id = :a").param("a", assignment).query(UUID.class).optional();
    }

    int mark(UUID submission, UUID assignment, BigDecimal mark, String feedback, UUID by) {
        return jdbc.sql("UPDATE lms.submission SET mark = :m, marked_at = now(), marked_by = :by, feedback = :f WHERE id = :s AND assignment_id = :a")
                .param("m", mark).param("by", by).param("f", feedback, Types.VARCHAR).param("s", submission).param("a", assignment).update();
    }

    Optional<FileContent> submissionContent(UUID submission) {
        return jdbc.sql("""
                SELECT s.filename, s.content_type, b.content FROM lms.submission s JOIN lms.submission_blob b ON b.submission_id = s.id WHERE s.id = :s
                """).param("s", submission).query(FileContent.class).optional();
    }

    Optional<Map<String, Object>> submissionOwner(UUID submission) {
        return jdbc.sql("SELECT s.student_id, a.offering_id FROM lms.submission s JOIN lms.assignment a ON a.id = s.assignment_id WHERE s.id = :s")
                .param("s", submission).query().listOfRows().stream().findFirst();
    }

    List<Map<String, Object>> gradebook(UUID offering) {
        return jdbc.sql("SELECT * FROM lms.gradebook(:o)").param("o", offering).query().listOfRows();
    }

    int promote(UUID offering) {
        return jdbc.sql("SELECT lms.promote_ca(:o)").param("o", offering).query(Integer.class).single();
    }

    /** engagement: never signed in to the space (no read), materials read, submissions, attendance */
    List<Map<String, Object>> engagement(UUID offering) {
        return jdbc.sql("""
                SELECT g.student_id, g.number, g.name, g.submitted, g.marked,
                       (SELECT count(DISTINCT a.material_id) FROM lms.access a JOIN lms.material m ON m.id = a.material_id WHERE m.offering_id = :o AND a.student_id = g.student_id) AS materials_read,
                       (SELECT count(*) FROM lms.material m WHERE m.offering_id = :o AND m.published_at IS NOT NULL AND m.ended_at IS NULL) AS materials,
                       (SELECT count(*) FROM lms.assignment x WHERE x.offering_id = :o AND x.ended_at IS NULL) AS assignments,
                       (SELECT max(a.at) FROM lms.access a JOIN lms.material m ON m.id = a.material_id WHERE m.offering_id = :o AND a.student_id = g.student_id) AS last_read,
                       (SELECT count(*) FILTER (WHERE at.present) FROM registration.attendance at WHERE at.offering_id = :o AND at.student_id = g.student_id) AS attended,
                       (SELECT count(*) FROM registration.attendance at WHERE at.offering_id = :o AND at.student_id = g.student_id) AS held
                  FROM lms.gradebook(:o) g ORDER BY g.name
                """).param("o", offering).query().listOfRows();
    }
}
