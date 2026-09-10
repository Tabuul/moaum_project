package ng.edu.moaum.portal.matriculation;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class MatriculationRepository {

    private final JdbcClient jdbc;

    MatriculationRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    List<Matriculation.FacultyLine> faculties(String session) {
        return jdbc.sql("""
                SELECT f.code, f.name,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.office_assignment oa JOIN iam.person p ON p.id = oa.person_id
                         WHERE oa.office_code = 'facultyofficer' AND oa.scope_kind = 'faculty' AND oa.scope_id = f.code
                           AND (oa.valid_to IS NULL OR oa.valid_to >= current_date) ORDER BY oa.valid_from DESC LIMIT 1) AS officer,
                       (SELECT count(*) FROM people.faculty_list_rows(:s, f.code)) AS registered,
                       (SELECT count(*) FROM people.faculty_list_rows(:s, f.code) x WHERE x.query_reason IS NULL) AS confirmed,
                       (SELECT count(*) FROM people.faculty_list_rows(:s, f.code) x WHERE x.query_reason IS NOT NULL) AS queried,
                       coalesce(l.state, 'NOT_RETURNED') AS state, l.confirmed_at
                  FROM ref.faculty f
                  LEFT JOIN people.faculty_list l ON l.session = :s AND l.faculty_code = f.code
                 ORDER BY f.name
                """).param("s", session).query(Matriculation.FacultyLine.class).list();
    }

    Optional<String> facultyName(String code) {
        return jdbc.sql("SELECT name FROM ref.faculty WHERE code = :c").param("c", code).query(String.class).optional();
    }

    List<Matriculation.Row> rows(String session, String faculty) {
        return jdbc.sql("""
                SELECT student_id, admission_no, surname, other_names, dept_code, dept_name, units, registration_status,
                       query_reason, query_office
                  FROM people.faculty_list_rows(:s, :f)
                """).param("s", session).param("f", faculty).query(Matriculation.Row.class).list();
    }

    List<Matriculation.Held> heldBack(String session) {
        return jdbc.sql("""
                SELECT q.student_id, s.admission_no, s.surname, s.other_names, f.name AS faculty_name, q.reason, q.office
                  FROM people.faculty_list_query q
                  JOIN people.faculty_list l ON l.id = q.list_id
                  JOIN ref.faculty f ON f.code = l.faculty_code
                  JOIN people.student s ON s.id = q.student_id
                 WHERE l.session = :s AND q.withdrawn_at IS NULL AND s.matric_no IS NULL
                 ORDER BY f.name, s.surname
                """).param("s", session).query(Matriculation.Held.class).list();
    }

    record ListRow(UUID id, String state, OffsetDateTime confirmedAt) {
    }

    Optional<ListRow> list(String session, String faculty) {
        return jdbc.sql("SELECT id, state, confirmed_at FROM people.faculty_list WHERE session = :s AND faculty_code = :f")
                .param("s", session).param("f", faculty).query(ListRow.class).optional();
    }

    UUID ensureList(String session, String faculty) {
        return list(session, faculty).map(ListRow::id).orElseGet(() -> {
            UUID id = UUID.randomUUID();
            jdbc.sql("INSERT INTO people.faculty_list (id, session, faculty_code) VALUES (:id, :s, :f)")
                    .param("id", id).param("s", session).param("f", faculty).update();
            return id;
        });
    }

    void confirm(UUID listId, UUID by) {
        jdbc.sql("UPDATE people.faculty_list SET state = 'CONFIRMED', confirmed_at = now(), confirmed_by = :by WHERE id = :id")
                .param("by", by).param("id", listId).update();
    }

    void query(UUID listId, UUID student, String reason, String office) {
        jdbc.sql("""
                INSERT INTO people.faculty_list_query (list_id, student_id, reason, office) VALUES (:l, :s, :r, :o)
                ON CONFLICT (list_id, student_id) DO UPDATE SET reason = EXCLUDED.reason, office = EXCLUDED.office, withdrawn_at = NULL
                """).param("l", listId).param("s", student).param("r", reason).param("o", office).update();
    }

    int withdraw(UUID listId, UUID student) {
        return jdbc.sql("UPDATE people.faculty_list_query SET withdrawn_at = now() WHERE list_id = :l AND student_id = :s AND withdrawn_at IS NULL")
                .param("l", listId).param("s", student).update();
    }

    boolean onList(String session, String faculty, UUID student) {
        return rows(session, faculty).stream().anyMatch(r -> r.studentId().equals(student));
    }

    List<Matriculation.Run> runs(String session) {
        return jdbc.sql("SELECT id, ref, session, run_at, issued FROM people.matriculation_run WHERE session = :s ORDER BY run_at DESC")
                .param("s", session).query(Matriculation.Run.class).list();
    }

    List<Matriculation.Allocation> sample(UUID run) {
        return jdbc.sql("""
                SELECT s.admission_no, s.matric_no, s.surname, s.other_names, d.name AS dept_name
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code
                 WHERE s.matriculation_run = :r ORDER BY s.matric_no LIMIT 5
                """).param("r", run).query(Matriculation.Allocation.class).list();
    }

    record RunResult(String runRef, int issued) {
    }

    RunResult run(String session) {
        return jdbc.sql("SELECT run_ref, issued FROM people.matriculate(:s)").param("s", session).query(RunResult.class).single();
    }

    /** matriculate one student once fees are paid and courses registered; returns the number issued */
    String matriculateStudent(java.util.UUID studentId) {
        return jdbc.sql("SELECT people.matriculate_student(:id)").param("id", studentId).query(String.class).single();
    }

    Integer minUnits(int level) {
        return jdbc.sql("SELECT min_units FROM policy.level_limit WHERE level = :l").param("l", level).query(Integer.class)
                .optional().orElse(null);
    }
}
