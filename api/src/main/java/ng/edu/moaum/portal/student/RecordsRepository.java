package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * One scope, every query (proto/part21). Each view is one statement over the
 * same seven parameters, and every column is named as the screen reads it.
 * Nothing here is estimated: a view with no rows has no rows.
 */
@Repository
class RecordsRepository {

    /** the register joined up to its faculty */
    private static final String STUDENT_FROM = """
              FROM people.student s
              JOIN ref.programme p ON p.code = s.programme_code
              JOIN ref.department d ON d.code = p.dept_code
            """;

    private static final String STUDENT_WHERE = """
             WHERE (CAST(:fac AS text) IS NULL OR p.faculty_code = CAST(:fac AS text))
               AND (CAST(:dept AS text) IS NULL OR p.dept_code = CAST(:dept AS text))
               AND (CAST(:prog AS text) IS NULL OR p.code = CAST(:prog AS text))
               AND (CAST(:level AS int) IS NULL OR s.current_level = CAST(:level AS int))
            """;

    private static final String OFFERING_JOIN = """
              JOIN catalogue.course c ON c.code = o.course_code
              JOIN ref.department d ON d.code = c.dept_code
            """;

    private static final String OFFERING_WHERE = """
             WHERE o.session = CAST(:session AS text)
               AND (CAST(:sem AS int) IS NULL OR o.semester = CAST(:sem AS int))
               AND (CAST(:fac AS text) IS NULL OR d.faculty_code = CAST(:fac AS text))
               AND (CAST(:dept AS text) IS NULL OR c.dept_code = CAST(:dept AS text))
               AND (CAST(:level AS int) IS NULL OR c.level = CAST(:level AS int))
               AND (CAST(:course AS text) IS NULL OR c.code = CAST(:course AS text))
               AND (CAST(:prog AS text) IS NULL OR EXISTS (
                        SELECT 1 FROM catalogue.course_offer f
                         WHERE f.course_code = c.code AND f.programme_code = CAST(:prog AS text)))
             ORDER BY c.code
            """;

    private final JdbcClient jdbc;

    RecordsRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** V360: the register, with each student's CGPA from the published results when the scope is narrow enough to read
     *  them all (the GPA is computed per student, not stored) — otherwise the column is left empty and the screen says why */
    List<Map<String, Object>> students(Scope scope, boolean withCgpa) {
        return jdbc.sql("""
                SELECT s.id::text AS "id", s.matric_no AS "matricNo", s.admission_no AS "admissionNo",
                       s.surname || ', ' || s.other_names AS "name",
                       s.current_level AS "level", s.status AS "status",
                       CASE WHEN CAST(:withCgpa AS boolean) THEN (SELECT g.cgpa FROM assessment.student_gpa(s.id) g
                                                                   ORDER BY g.session DESC, g.semester DESC LIMIT 1) END AS "cgpa"
                """ + STUDENT_FROM + STUDENT_WHERE + " ORDER BY s.surname, s.other_names")
                .param("fac", scope.fac(), Types.VARCHAR).param("dept", scope.dept(), Types.VARCHAR).param("prog", scope.prog(), Types.VARCHAR)
                .param("level", scope.level(), Types.INTEGER).param("withCgpa", withCgpa)
                .query().listOfRows();
    }

    /** V360: the session's school fees for each student in scope — what the fee schedule charges them and what they have
     *  paid against it, the Bursary's own figures (finance.charges and confirmed school-fee payments, as finance.position
     *  reads them); arrears of earlier sessions are on each student's own record */
    List<Map<String, Object>> fees(Scope scope) {
        return rows("""
                SELECT s.id::text AS "id", s.matric_no AS "matricNo", s.admission_no AS "admissionNo",
                       s.surname || ', ' || s.other_names AS "name", s.current_level AS "level",
                       ch.due AS "due", coalesce(pd.paid, 0) AS "paid", greatest(ch.due - coalesce(pd.paid, 0), 0) AS "balance",
                       CASE WHEN ch.due = 0 THEN 'NO_CHARGE' WHEN coalesce(pd.paid, 0) >= ch.due THEN 'PAID'
                            WHEN coalesce(pd.paid, 0) > 0 THEN 'PART_PAID' ELSE 'UNPAID' END AS "state"
                """ + STUDENT_FROM + """
                  CROSS JOIN LATERAL (SELECT coalesce(sum(c.amount), 0) AS due FROM finance.charges(s.id, CAST(:session AS text)) c) ch
                  LEFT JOIN LATERAL (SELECT sum(r.amount) AS paid FROM finance.payment_reference r
                                      WHERE r.student_id = s.id AND r.session = CAST(:session AS text) AND r.confirmed_at IS NOT NULL
                                        AND r.purpose LIKE 'School fees%') pd ON true
                """ + STUDENT_WHERE + " ORDER BY s.surname, s.other_names", scope);
    }

    /** V360: attendance as the lecturers have marked it, for each student on an approved registration in scope — the
     *  courses with a register, classes attended of those held, and the lowest course rate. No minimum is applied: none is
     *  configured for the University's courses, and a rate is not judged against a number nobody set */
    List<Map<String, Object>> attendance(Scope scope) {
        return rows("""
                SELECT s.id::text AS "id", s.matric_no AS "matricNo", s.admission_no AS "admissionNo",
                       s.surname || ', ' || s.other_names AS "name", s.current_level AS "level",
                       count(DISTINCT e.offering_id)::int AS "courses",
                       (count(DISTINCT e.offering_id) FILTER (WHERE at.held > 0))::int AS "withRegister",
                       coalesce(sum(at.attended), 0)::int AS "attended", coalesce(sum(at.held), 0)::int AS "held",
                       CASE WHEN sum(at.held) > 0 THEN round(100.0 * sum(at.attended) / sum(at.held))::int END AS "rate",
                       min(CASE WHEN at.held > 0 THEN round(100.0 * at.attended / at.held)::int END) AS "lowest"
                """ + STUDENT_FROM + """
                  JOIN registration.course_registration r ON r.student_id = s.id AND r.session = CAST(:session AS text)
                       AND (CAST(:sem AS int) IS NULL OR r.semester = CAST(:sem AS int)) AND r.status IN ('APPROVED', 'LOCKED')
                  JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
                  LEFT JOIN LATERAL (SELECT count(*) FILTER (WHERE a.present) AS attended, count(*) AS held
                                       FROM registration.attendance a WHERE a.offering_id = e.offering_id AND a.student_id = s.id) at ON true
                """ + STUDENT_WHERE + """
                 GROUP BY s.id, s.matric_no, s.admission_no, s.surname, s.other_names, s.current_level
                 ORDER BY s.surname, s.other_names
                """, scope);
    }

    List<Map<String, Object>> registration(Scope scope) {
        return rows("""
                SELECT s.id::text AS "id", s.matric_no AS "matricNo",
                       s.surname || ', ' || s.other_names AS "name",
                       s.current_level AS "level", r.semester AS "semester",
                       CASE WHEN r.id IS NULL THEN NULL ELSE registration.units_of(r.id) END AS "units",
                       to_char(r.submitted_at, 'YYYY-MM-DD') AS "submittedAt",
                       coalesce(r.status, 'NOT_REGISTERED') AS "status"
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN registration.course_registration r
                         ON r.student_id = s.id AND r.session = CAST(:session AS text)
                        AND (CAST(:sem AS int) IS NULL OR r.semester = CAST(:sem AS int))
                """ + STUDENT_WHERE + " ORDER BY s.surname, s.other_names, r.semester", scope);
    }

    /** Where each result set has reached, and how many failed of those graded. */
    List<Map<String, Object>> results(Scope scope) {
        return rows("""
                SELECT c.code AS "course", coalesce(o.title, c.title) AS "title", coalesce(o.units, c.units) AS "units",
                       (SELECT count(*)::int FROM registration.entry e
                          JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status = 'APPROVED'
                           AND r.status IN ('APPROVED', 'LOCKED')) AS "candidates",
                       h.stage AS "stage", h.returned_times AS "returnedTimes", sc.graded AS "graded",
                       CASE WHEN sc.graded > 0 THEN round(100.0 * sc.failed / sc.graded)::int END AS "failRate"
                  FROM catalogue.offering o
                """ + OFFERING_JOIN + """
                  LEFT JOIN assessment.score_sheet h ON h.offering_id = o.id
                  LEFT JOIN LATERAL (
                        SELECT count(*) FILTER (WHERE outcome = 'GRADED')::int AS graded,
                               count(*) FILTER (WHERE outcome = 'GRADED' AND points = 0)::int AS failed
                          FROM assessment.latest_scores(h.id)) sc ON true
                """ + OFFERING_WHERE, scope);
    }

    /** The examination sessions of a session, and who is cleared to sit them. */
    List<Map<String, Object>> exams(Scope scope) {
        return rows("""
                SELECT x.id::text AS "id", x.kind AS "kind", x.semester AS "semester",
                       to_char(x.exams_from, 'YYYY-MM-DD') AS "examsFrom",
                       to_char(x.exams_to, 'YYYY-MM-DD') AS "examsTo",
                       to_char(x.sheets_due, 'YYYY-MM-DD') AS "sheetsDue", x.state AS "state", x.stream AS "stream",
                       coalesce(n.candidates, 0) AS "candidates", coalesce(n.cleared, 0) AS "cleared"
                  FROM assessment.exam_session x
                  LEFT JOIN LATERAL (
                        SELECT count(DISTINCT r.student_id)::int AS candidates,
                               count(DISTINCT r.student_id)
                                   FILTER (WHERE clearance.is_clear(r.student_id, 'EXAMINATION'))::int AS cleared
                          FROM registration.course_registration r
                          JOIN people.student s ON s.id = r.student_id
                          JOIN ref.programme p ON p.code = s.programme_code
                         WHERE r.session = x.session AND r.semester = x.semester
                           AND r.status IN ('APPROVED', 'LOCKED')
                           AND (CASE WHEN s.entry_mode = 'CCE' THEN 'CCE' ELSE 'REGULAR' END) = x.stream   -- V381: the session's own students
                           AND (CAST(:fac AS text) IS NULL OR p.faculty_code = CAST(:fac AS text))
                           AND (CAST(:dept AS text) IS NULL OR p.dept_code = CAST(:dept AS text))
                           AND (CAST(:prog AS text) IS NULL OR p.code = CAST(:prog AS text))
                           AND (CAST(:level AS int) IS NULL OR s.current_level = CAST(:level AS int))) n ON true
                 WHERE x.session = CAST(:session AS text)
                   AND (CAST(:sem AS int) IS NULL OR x.semester = CAST(:sem AS int))
                 ORDER BY x.semester, x.kind
                """, scope);
    }

    /** Who teaches what: the offering, its lecturer and its second examiner. */
    List<Map<String, Object>> allocation(Scope scope) {
        return rows("""
                SELECT c.code AS "course", coalesce(o.title, c.title) AS "title", coalesce(o.units, c.units) AS "units",
                       (SELECT count(*)::int FROM registration.entry e
                         WHERE e.offering_id = o.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) AS "registered",
                       CASE WHEN l.id IS NULL THEN NULL ELSE l.surname || ', ' || l.given_names END AS "lecturer",
                       CASE WHEN x.id IS NULL THEN NULL ELSE x.surname || ', ' || x.given_names END AS "secondExaminer",
                       to_char(o.allocated_on, 'YYYY-MM-DD') AS "allocatedOn"
                  FROM catalogue.offering o
                """ + OFFERING_JOIN + """
                  LEFT JOIN iam.person l ON l.id = o.lecturer_id
                  LEFT JOIN iam.person x ON x.id = o.second_examiner_id
                """ + OFFERING_WHERE, scope);
    }

    /** Who is held for convocation, and by which unit. */
    List<Map<String, Object>> clearance(Scope scope) {
        return rows("""
                SELECT s.id::text AS "id", s.matric_no AS "matricNo",
                       s.surname || ', ' || s.other_names AS "name", s.current_level AS "level",
                       cl.bursary AS "BURSARY", cl.department AS "DEPARTMENT", cl.faculty AS "FACULTY",
                       cl.library AS "LIBRARY", cl.health AS "HEALTH", cl.hostel AS "HOSTEL",
                       cl.works AS "WORKS", cl.alumni AS "ALUMNI", cl.clear AS "clear"
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN LATERAL (
                        SELECT max(state) FILTER (WHERE unit = 'BURSARY') AS bursary,
                               max(state) FILTER (WHERE unit = 'DEPARTMENT') AS department,
                               max(state) FILTER (WHERE unit = 'FACULTY') AS faculty,
                               max(state) FILTER (WHERE unit = 'LIBRARY') AS library,
                               max(state) FILTER (WHERE unit = 'HEALTH') AS health,
                               max(state) FILTER (WHERE unit = 'HOSTEL') AS hostel,
                               max(state) FILTER (WHERE unit = 'WORKS') AS works,
                               max(state) FILTER (WHERE unit = 'ALUMNI') AS alumni,
                               bool_and(state = 'CLEARED') AS clear
                          FROM clearance.position(s.id, 'CONVOCATION')) cl ON true
                """ + STUDENT_WHERE + " ORDER BY s.surname, s.other_names", scope);
    }

    private List<Map<String, Object>> rows(String sql, Scope scope) {
        return jdbc.sql(sql)
                .param("fac", scope.fac(), Types.VARCHAR)
                .param("dept", scope.dept(), Types.VARCHAR)
                .param("prog", scope.prog(), Types.VARCHAR)
                .param("level", scope.level(), Types.INTEGER)
                .param("course", scope.course(), Types.VARCHAR)
                .param("session", scope.session(), Types.VARCHAR)
                .param("sem", scope.sem(), Types.INTEGER)
                .query()
                .listOfRows();
    }
}
