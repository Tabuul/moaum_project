package ng.edu.moaum.portal.dean;

import java.util.LinkedHashMap;
import java.util.Map;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Dean's home, scoped to their own faculty: registration by department, the result-sheet pipeline
 * across the faculty, the offerings still without a lecturer, and the students at risk. The faculty is
 * the scope of their standing 'dean' grant, with the same fallbacks the HOD scope uses. Read-only.
 */
@RestController
class DeanController {

    private final JdbcClient jdbc;

    DeanController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the faculty the acting Dean heads: the office's own faculty scope, else the faculty of their staff-record
     *  home department. The grant may hold the faculty code OR its name — either resolves to the code. */
    private String actingFaculty() {
        return AuditContextHolder.current().flatMap(c -> jdbc.sql("""
                WITH raw AS (
                  SELECT COALESCE(
                    (SELECT scope_id FROM iam.office_assignment
                      WHERE person_id = :p AND office_code IN ('dean','facultyofficer') AND scope_kind = 'faculty'
                        AND nullif(btrim(scope_id), '') IS NOT NULL
                        AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date)
                      ORDER BY valid_from DESC LIMIT 1),
                    (SELECT d.faculty_code FROM hrm.staff_record sr JOIN ref.department d ON d.code = sr.home_department
                      WHERE sr.person_id = :p AND nullif(btrim(sr.home_department), '') IS NOT NULL LIMIT 1)
                  ) AS v)
                SELECT f.code FROM ref.faculty f, raw
                 WHERE raw.v IS NOT NULL
                   AND (upper(btrim(f.code)) = upper(btrim(raw.v)) OR lower(btrim(f.name)) = lower(btrim(raw.v)))
                 LIMIT 1
                """).param("p", c.actorId()).query(String.class).optional()).orElse(null);
    }

    @GetMapping("/api/v1/dean/dashboard")
    @PreAuthorize("hasAnyAuthority('OFFICE_dean','OFFICE_facultyofficer','OFFICE_super')")
    @Transactional(readOnly = true)
    Map<String, Object> dashboard(@RequestParam(required = false) String session) {
        Map<String, Object> out = new LinkedHashMap<>();
        String fac = actingFaculty();
        if (fac == null) {
            out.put("resolved", false);
            return out;
        }
        out.put("resolved", true);
        out.put("faculty", fac);
        out.put("facultyName", jdbc.sql("SELECT name FROM ref.faculty WHERE code = :f").param("f", fac).query(String.class).optional().orElse(fac));
        String s = session != null && session.matches("\\d{4}/\\d{4}") ? session
                : jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027");
        out.put("session", s);

        out.put("students", jdbc.sql("""
                SELECT count(*) FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
                 WHERE p.faculty_code = :f AND st.status IN ('ACTIVE','PROBATION')
                """).param("f", fac).query(Long.class).single());

        out.put("byDept", jdbc.sql("""
                SELECT d.code, d.name,
                       count(DISTINCT st.id) AS students,
                       count(DISTINCT st.id) FILTER (WHERE EXISTS (
                           SELECT 1 FROM registration.course_registration r
                            WHERE r.student_id = st.id AND r.session = :s AND r.status IN ('APPROVED','LOCKED'))) AS registered
                  FROM ref.department d
                  JOIN ref.programme p ON p.dept_code = d.code
                  JOIN people.student st ON st.programme_code = p.code AND st.status IN ('ACTIVE','PROBATION')
                 WHERE d.faculty_code = :f
                 GROUP BY d.code, d.name ORDER BY d.name
                """).param("f", fac).param("s", s).query().listOfRows());

        out.put("pipeline", jdbc.sql("""
                SELECT count(*) FILTER (WHERE ss.stage = 'ENTRY') AS entry,
                       count(*) FILTER (WHERE ss.stage IN
                           ('VERIFICATION','DEPT_BOARD','FACULTY_SCRUTINY','FACULTY_COMPILATION','FACULTY_BOARD','RECORDS')) AS workflow,
                       count(*) FILTER (WHERE ss.stage = 'SENATE') AS senate,
                       count(*) FILTER (WHERE ss.stage = 'PUBLISHED') AS published
                  FROM assessment.score_sheet ss
                  JOIN catalogue.offering o ON o.id = ss.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                 WHERE o.session = :s AND d.faculty_code = :f
                """).param("f", fac).param("s", s).query().singleRow());

        Map<String, Object> off = jdbc.sql("""
                SELECT count(*) AS total, count(*) FILTER (WHERE o.lecturer_id IS NULL) AS need_lecturer
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                 WHERE o.session = :s AND d.faculty_code = :f
                """).param("f", fac).param("s", s).query().singleRow();
        out.put("offeringsTotal", off.get("total"));
        out.put("offeringsNeedLecturer", off.get("need_lecturer"));

        out.put("probation", jdbc.sql("""
                SELECT count(*) FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
                 WHERE p.faculty_code = :f AND st.status = 'PROBATION'
                """).param("f", fac).query(Long.class).single());
        out.put("atRisk", jdbc.sql("""
                SELECT st.surname || ', ' || st.other_names AS name, coalesce(st.matric_no, st.admission_no) AS number,
                       p.name AS programme, st.current_level AS level
                  FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
                 WHERE p.faculty_code = :f AND st.status = 'PROBATION'
                 ORDER BY st.current_level, st.surname LIMIT 12
                """).param("f", fac).query().listOfRows());

        return out;
    }
}
