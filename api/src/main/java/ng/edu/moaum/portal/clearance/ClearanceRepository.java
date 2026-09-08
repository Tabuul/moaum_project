package ng.edu.moaum.portal.clearance;

import java.sql.Types;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class ClearanceRepository {

    private final JdbcClient jdbc;

    ClearanceRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    List<Clearance.Unit> units() {
        return jdbc.sql("SELECT code, label, clears_against, holds_for, typical_reason, office_code, ord FROM clearance.unit ORDER BY ord")
                .query(Clearance.Unit.class).list();
    }

    Optional<Clearance.Unit> unit(String code) {
        return units().stream().filter(u -> u.code().equals(code)).findFirst();
    }

    record StudentRow(UUID id, String number, String surname, String otherNames, String programmeName, String deptName,
                      String facultyCode, int level) {
    }

    /** the candidates a scope selects: enrolled in the session where anybody is, else the whole register in scope */
    List<StudentRow> students(String fac, String dept, String prog, Integer level, String session) {
        return jdbc.sql("""
                SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names,
                       p.name AS programme_name, d.name AS dept_name, d.faculty_code, s.current_level AS level
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.department d ON d.code = p.dept_code
                 WHERE (:fac::text IS NULL OR d.faculty_code = :fac)
                   AND (:dept::text IS NULL OR p.dept_code = :dept)
                   AND (:prog::text IS NULL OR s.programme_code = :prog)
                   AND (:level::int IS NULL OR s.current_level = :level)
                   AND (NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.session = :session)
                        OR EXISTS (SELECT 1 FROM people.enrolment e WHERE e.session = :session AND e.student_id = s.id))
                 ORDER BY s.surname, s.other_names
                """)
                .param("fac", fac).param("dept", dept).param("prog", prog).param("level", level).param("session", session)
                .query(StudentRow.class).list();
    }

    long total() {
        return jdbc.sql("SELECT count(*) FROM people.student").query(Long.class).single();
    }

    List<Clearance.Position> position(UUID student, String purpose) {
        return jdbc.sql("""
                SELECT c.unit, c.label, c.state, c.item, c.officer_id,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS officer,
                       c.decided_at, i.note, c.ord
                  FROM clearance.position(:s, :p) c
                  LEFT JOIN iam.person p ON p.id = c.officer_id
                  LEFT JOIN LATERAL (SELECT note FROM clearance.item x WHERE x.student_id = :s AND x.purpose = :p
                                      AND x.unit = c.unit AND x.superseded_by IS NULL ORDER BY x.decided_at DESC LIMIT 1) i ON true
                 ORDER BY c.ord
                """).param("s", student).param("p", purpose).query(Clearance.Position.class).list();
    }

    boolean studentExists(UUID id) {
        return jdbc.sql("SELECT count(*) FROM people.student WHERE id = :id").param("id", id).query(Long.class).single() > 0;
    }

    void decide(UUID student, String purpose, String unit, String state, String item, UUID officer, String note) {
        jdbc.sql("""
                INSERT INTO clearance.item (id, student_id, purpose, unit, state, item, officer_id, note)
                VALUES (gen_random_uuid(), :s, :p, :u, :st, :i, :o, :n)
                """).param("s", student).param("p", purpose).param("u", unit).param("st", state)
                .param("i", item, Types.VARCHAR).param("o", officer).param("n", note, Types.VARCHAR).update();
    }
}
