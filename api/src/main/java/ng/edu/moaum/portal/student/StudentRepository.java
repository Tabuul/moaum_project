package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * The register, and the whole of one record. Every list is a list within a
 * scope, written as {@code (CAST(:x AS …) IS NULL OR …)} so that one
 * statement serves every narrowing of it.
 *
 * <p>The session is not a filter on the register: a student is on it whether
 * or not they have enrolled for the session being looked at. The session
 * decides which registrations the record shows, not who exists.
 */
@Repository
class StudentRepository {

    private static final String SELECT_ROW = """
            SELECT s.id, s.matric_no, s.admission_no, s.jamb_reg_no,
                   s.surname, s.other_names, s.sex, s.date_of_birth,
                   p.code AS programme_code, p.name AS programme_name,
                   d.code AS dept_code, d.name AS dept_name,
                   f.code AS faculty_code, f.name AS faculty_name,
                   s.entry_mode, s.entry_session, s.entry_level, s.current_level, s.status
              FROM people.student s
              JOIN ref.programme p ON p.code = s.programme_code
              JOIN ref.department d ON d.code = p.dept_code
              JOIN ref.faculty f ON f.code = p.faculty_code
            """;

    static final String IN_SCOPE = """
             WHERE (CAST(:fac AS text) IS NULL OR f.code = CAST(:fac AS text))
               AND (CAST(:dept AS text) IS NULL OR d.code = CAST(:dept AS text))
               AND (CAST(:prog AS text) IS NULL OR p.code = CAST(:prog AS text))
               AND (CAST(:level AS int) IS NULL OR s.current_level = CAST(:level AS int))
            """;

    private final JdbcClient jdbc;

    StudentRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    List<StudentRow> register(Scope scope, String q) {
        return scoped(jdbc.sql(SELECT_ROW + IN_SCOPE + """
                   AND (CAST(:q AS text) IS NULL OR s.matric_no ILIKE CAST(:like AS text)
                        OR s.admission_no ILIKE CAST(:like AS text)
                        OR s.surname ILIKE CAST(:like AS text)
                        OR s.other_names ILIKE CAST(:like AS text)
                        OR (s.surname || ' ' || s.other_names) ILIKE CAST(:like AS text))
                 ORDER BY s.surname, s.other_names
                 LIMIT 2000
                """), scope)
                .param("q", q, Types.VARCHAR)
                .param("like", q == null ? null : "%" + q + "%", Types.VARCHAR)
                .query(StudentRow.class)
                .list();
    }

    /** The register entire: what the University has, whatever the scope shows. */
    int total() {
        return jdbc.sql("SELECT count(*)::int FROM people.student").query(Integer.class).single();
    }

    /** The students one scope selects — the population every records view counts against. */
    int inScope(Scope scope) {
        return scoped(jdbc.sql("""
                SELECT count(*)::int
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.department d ON d.code = p.dept_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                """ + IN_SCOPE), scope)
                .query(Integer.class)
                .single();
    }

    Optional<StudentRow> student(UUID id) {
        return jdbc.sql(SELECT_ROW + " WHERE s.id = :id").param("id", id).query(StudentRow.class).optional();
    }

    /**
     * Every field the record has, in the order the sections take them, with
     * the value where one is recorded. A field with no value is still shown:
     * the record says what is missing as well as what is held.
     */
    List<StudentRecord.BiodataField> biodata(UUID id) {
        return jdbc.sql("""
                SELECT f.field, f.section, f.label, f.tier, f.hint, f.wide, f.ord, b.value
                  FROM ref.biodata_field f
                  LEFT JOIN people.biodata b ON b.student_id = :id AND b.field = f.field
                 ORDER BY f.ord
                """).param("id", id).query(StudentRecord.BiodataField.class).list();
    }

    List<StudentRecord.Document> documents(UUID id) {
        return jdbc.sql("""
                SELECT id, kind, detail, source, received_on, status
                  FROM people.document WHERE student_id = :id
                 ORDER BY received_on DESC NULLS LAST, kind
                """).param("id", id).query(StudentRecord.Document.class).list();
    }

    List<StudentRecord.StatusEntry> statusHistory(UUID id) {
        return jdbc.sql("""
                SELECT id, from_status, to_status, instrument, effective_on, reason
                  FROM people.status_change WHERE student_id = :id
                 ORDER BY effective_on DESC
                """).param("id", id).query(StudentRecord.StatusEntry.class).list();
    }

    List<StudentRecord.Enrolment> enrolments(UUID id) {
        return jdbc.sql("""
                SELECT session, level, mode, fee_category, enrolled_at
                  FROM people.enrolment WHERE student_id = :id ORDER BY session DESC
                """).param("id", id).query(StudentRecord.Enrolment.class).list();
    }

    List<StudentRecord.Registration> registrations(UUID id, String session) {
        return jdbc.sql("""
                SELECT r.id, r.session, r.semester, r.level, r.status,
                       registration.units_of(r.id) AS units, r.submitted_at
                  FROM registration.course_registration r
                 WHERE r.student_id = :id
                   AND (CAST(:session AS text) IS NULL OR r.session = CAST(:session AS text))
                 ORDER BY r.session DESC, r.semester
                """).param("id", id).param("session", session, Types.VARCHAR)
                .query(StudentRecord.Registration.class).list();
    }

    /** The units an approved registration carries, over the whole record: credits registered, not earned. */
    int approvedUnits(UUID id) {
        return jdbc.sql("""
                SELECT coalesce(sum(registration.units_of(r.id)), 0)::int
                  FROM registration.course_registration r
                 WHERE r.student_id = :id AND r.status IN ('APPROVED', 'LOCKED')
                """).param("id", id).query(Integer.class).single();
    }

    List<StudentRecord.Clearance> clearance(UUID id, String purpose) {
        return jdbc.sql("""
                SELECT unit, label, state, item, decided_at, ord
                  FROM clearance.position(:id, :purpose)
                """).param("id", id).param("purpose", purpose).query(StudentRecord.Clearance.class).list();
    }

    List<StudentRecord.PendingChange> pendingChanges(UUID id) {
        return jdbc.sql("""
                SELECT c.id, c.field, coalesce(f.label, c.field) AS label, c.from_value, c.to_value,
                       c.evidence, c.requested_at, c.state
                  FROM people.biodata_change c
                  LEFT JOIN ref.biodata_field f ON f.field = c.field
                 WHERE c.student_id = :id AND c.state IN ('PENDING', 'EVIDENCE_ASKED')
                 ORDER BY c.requested_at
                """).param("id", id).query(StudentRecord.PendingChange.class).list();
    }

    List<StudentRecord.DecidedChange> decidedChanges(UUID id) {
        return jdbc.sql("""
                SELECT c.id, c.field, coalesce(f.label, c.field) AS label, c.from_value, c.to_value,
                       c.evidence, c.requested_at, c.state, c.decision, c.decided_at
                  FROM people.biodata_change c
                  LEFT JOIN ref.biodata_field f ON f.field = c.field
                 WHERE c.student_id = :id AND c.state IN ('APPROVED', 'REFUSED')
                 ORDER BY c.decided_at DESC
                """).param("id", id).query(StudentRecord.DecidedChange.class).list();
    }

    // ── writes ───────────────────────────────────────────────────────────

    Optional<String> tierOf(String field) {
        return jdbc.sql("SELECT tier FROM ref.biodata_field WHERE field = :f").param("f", field)
                .query(String.class).optional();
    }

    Optional<String> valueOf(UUID student, String field) {
        return jdbc.sql("SELECT value FROM people.biodata WHERE student_id = :id AND field = :f")
                .param("id", student).param("f", field).query(String.class).optional();
    }

    void writeBiodata(UUID student, String field, String value) {
        jdbc.sql("""
                INSERT INTO people.biodata (student_id, field, value) VALUES (:id, :f, :v)
                ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value
                """).param("id", student).param("f", field).param("v", value).update();
    }

    UUID askForChange(UUID student, String field, String from, String to, String evidence) {
        UUID id = UUID.randomUUID();
        jdbc.sql("""
                INSERT INTO people.biodata_change (id, student_id, field, from_value, to_value, evidence, state)
                VALUES (:id, :s, :f, :from, :to, :ev, 'PENDING')
                """).param("id", id).param("s", student).param("f", field)
                .param("from", from, Types.VARCHAR).param("to", to)
                .param("ev", evidence, Types.VARCHAR).update();
        return id;
    }

    void changeStatus(UUID student, String to, String instrument, LocalDate effective, String reason) {
        jdbc.sql("SELECT people.change_status(:id, :to, :instrument, :effective, :reason)")
                .param("id", student).param("to", to).param("instrument", instrument)
                .param("effective", effective).param("reason", reason, Types.VARCHAR)
                .query().singleRow();
    }

    /** correct a student's current level (the reason travels on the audit spine via the request's X-Reason) */
    void correctLevel(UUID student, int level) {
        jdbc.sql("UPDATE people.student SET current_level = :lvl WHERE id = :id")
                .param("lvl", level).param("id", student).update();
    }

    /** The Academic Office brings a session's admitted candidates onto the register. */
    int intake(String session) {
        return jdbc.sql("SELECT people.intake(:s)").param("s", session).query(Integer.class).single();
    }

    private JdbcClient.StatementSpec scoped(JdbcClient.StatementSpec spec, Scope scope) {
        return spec.param("fac", scope.fac(), Types.VARCHAR)
                .param("dept", scope.dept(), Types.VARCHAR)
                .param("prog", scope.prog(), Types.VARCHAR)
                .param("level", scope.level(), Types.INTEGER);
    }
}
