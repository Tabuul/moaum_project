package ng.edu.moaum.portal.reports;

import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The University's statutory returns, read straight off the register: enrolment
 * by faculty, programme and level, and revenue by category. Read-only — a return
 * is a view of the record, verified against it, never a change to it. The
 * admissions return is drawn from the admissions cycle it already answers with.
 */
@RestController
@RequestMapping("/api/v1/reports")
class ReportsController {

    private static final String ENROLMENT_READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String REVENUE_READERS =
            "hasAnyAuthority('OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";

    private final JdbcClient jdbc;

    ReportsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** Enrolment for a session's cohort: students admitted that session, by faculty, programme and level, split by sex. */
    @GetMapping("/enrolment")
    @PreAuthorize(ENROLMENT_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> enrolment(@RequestParam String session) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT f.name AS faculty, p.name AS programme, s.current_level AS level,
                       count(*) FILTER (WHERE s.sex = 'M') AS male,
                       count(*) FILTER (WHERE s.sex = 'F') AS female,
                       count(*) FILTER (WHERE s.sex IS NULL) AS unstated,
                       count(*) AS total
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE s.entry_session = :s
                   AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED')
                 GROUP BY f.name, p.name, s.current_level
                 ORDER BY f.name, p.name, s.current_level
                """).param("s", session).query().listOfRows();
        Map<String, Object> totals = jdbc.sql("""
                SELECT count(*) FILTER (WHERE s.sex = 'M') AS male,
                       count(*) FILTER (WHERE s.sex = 'F') AS female,
                       count(*) FILTER (WHERE s.sex IS NULL) AS unstated,
                       count(*) AS total
                  FROM people.student s
                 WHERE s.entry_session = :s
                   AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED')
                """).param("s", session).query().singleRow();
        return Map.of("session", session, "rows", rows, "totals", totals);
    }

    /** Outstanding carryovers, as at now: for every active student, a course whose LATEST published attempt is
     *  an F is still carried; grouped by faculty, programme and course so the office sees the re-sit load. Set-based
     *  (one pass over published sheets), not per-student. */
    @GetMapping("/carryovers")
    @PreAuthorize(ENROLMENT_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> carryovers(@RequestParam String session) {
        String cte = """
                WITH attempts AS (
                    SELECT r.student_id, c.code AS course, c.title, e.units, r.session AS ses, r.semester AS sem, ls.points,
                           p.name AS programme, f.name AS faculty
                      FROM registration.course_registration r
                      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
                      JOIN catalogue.offering o ON o.id = e.offering_id
                      JOIN catalogue.course c ON c.code = o.course_code
                      JOIN assessment.score_sheet sh ON sh.offering_id = o.id AND sh.stage = 'PUBLISHED'
                      JOIN LATERAL assessment.latest_scores(sh.id) ls ON ls.student_id = r.student_id
                      JOIN people.student s ON s.id = r.student_id AND s.status IN ('ACTIVE','PROBATION')
                      JOIN ref.programme p ON p.code = s.programme_code
                      JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE r.status IN ('APPROVED','LOCKED') AND ls.outcome = 'GRADED'
                ),
                latest AS (
                    SELECT DISTINCT ON (student_id, course) student_id, course, title, units, points, programme, faculty
                      FROM attempts ORDER BY student_id, course, ses DESC, sem DESC
                )
                """;
        List<Map<String, Object>> rows = jdbc.sql(cte + """
                SELECT faculty, programme, course, title, max(units) AS units, count(*) AS students
                  FROM latest WHERE points = 0
                 GROUP BY faculty, programme, course, title
                 ORDER BY faculty, programme, course
                """).query().listOfRows();
        Map<String, Object> tally = jdbc.sql(cte + """
                SELECT count(*) AS carried, count(DISTINCT student_id) AS students
                  FROM latest WHERE points = 0
                """).query().singleRow();
        Map<String, Object> totals = Map.of("students", tally.getOrDefault("carried", 0L), "units", "");
        return Map.of("session", session, "rows", rows, "totals", totals,
                "distinctStudents", tally.getOrDefault("students", 0L));
    }

    /** Revenue confirmed for a session: student fees and applicant fees, by category. */
    @GetMapping("/revenue")
    @PreAuthorize(REVENUE_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> revenue(@RequestParam String session) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT t.category, count(*) AS payments, coalesce(sum(t.amount), 0) AS amount
                  FROM (
                        SELECT r.purpose AS category, r.amount
                          FROM finance.payment_reference r
                         WHERE r.session = :s AND r.confirmed_at IS NOT NULL
                        UNION ALL
                        SELECT CASE fr.kind
                                   WHEN 'APPLICATION' THEN 'Application & Post-UTME'
                                   WHEN 'ACCEPTANCE'  THEN 'Acceptance'
                                   ELSE fr.kind END AS category,
                               fr.amount
                          FROM admissions.fee_reference fr
                          JOIN admissions.application a ON a.id = fr.application_id
                         WHERE a.session = :s AND fr.confirmed_at IS NOT NULL
                       ) t
                 GROUP BY t.category
                 ORDER BY amount DESC, t.category
                """).param("s", session).query().listOfRows();
        Map<String, Object> totals = jdbc.sql("""
                SELECT count(*) AS payments, coalesce(sum(t.amount), 0) AS amount
                  FROM (
                        SELECT r.amount FROM finance.payment_reference r
                         WHERE r.session = :s AND r.confirmed_at IS NOT NULL
                        UNION ALL
                        SELECT fr.amount FROM admissions.fee_reference fr
                          JOIN admissions.application a ON a.id = fr.application_id
                         WHERE a.session = :s AND fr.confirmed_at IS NOT NULL
                       ) t
                """).param("s", session).query().singleRow();
        return Map.of("session", session, "rows", rows, "totals", totals);
    }
}
