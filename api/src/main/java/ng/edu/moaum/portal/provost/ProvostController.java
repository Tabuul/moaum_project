package ng.edu.moaum.portal.provost;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Provost's home, scoped to their College: registration by department across every faculty in the
 * College, the result-sheet pipeline, the offerings still without a lecturer, and the students at risk.
 * The College is the scope of their standing 'provost' grant, with a staff-record fallback and, in a
 * single-College institution, the sole College. The College Secretary shares this view. Read-only.
 *
 * The shape mirrors the Dean's dashboard so the same frontend renders it, one scope higher: the
 * "faculty" fields carry the College's code and name.
 */
@RestController
class ProvostController {

    private final JdbcClient jdbc;

    ProvostController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the College the acting Provost heads: the office's own College scope, else the College of their
     *  staff-record home department's faculty, else the sole College where the institution has just one.
     *  The grant may hold the College code OR its name — either resolves to the code. */
    private String actingCollege() {
        String byGrant = AuditContextHolder.current().flatMap(c -> jdbc.sql("""
                WITH raw AS (
                  SELECT COALESCE(
                    (SELECT scope_id FROM iam.office_assignment
                      WHERE person_id = :p AND office_code IN ('provost','collegesecretary') AND scope_kind = 'college'
                        AND nullif(btrim(scope_id), '') IS NOT NULL
                        AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date)
                      ORDER BY valid_from DESC LIMIT 1),
                    (SELECT f.college_code FROM hrm.staff_record sr
                       JOIN ref.department d ON d.code = sr.home_department
                       JOIN ref.faculty f ON f.code = d.faculty_code
                      WHERE sr.person_id = :p AND f.college_code IS NOT NULL LIMIT 1)
                  ) AS v)
                SELECT c.code FROM ref.college c, raw
                 WHERE raw.v IS NOT NULL
                   AND (upper(btrim(c.code)) = upper(btrim(raw.v)) OR lower(btrim(c.name)) = lower(btrim(raw.v)))
                 LIMIT 1
                """).param("p", c.actorId()).query(String.class).optional()).orElse(null);
        if (byGrant != null) {
            return byGrant;
        }
        // a single-College institution: the College is unambiguous even without a scoped grant
        List<String> all = jdbc.sql("SELECT code FROM ref.college ORDER BY code LIMIT 2").query(String.class).list();
        return all.size() == 1 ? all.get(0) : null;
    }

    @GetMapping("/api/v1/provost/dashboard")
    @PreAuthorize("hasAnyAuthority('OFFICE_provost','OFFICE_collegesecretary','OFFICE_financecontroller','OFFICE_super')")
    @Transactional(readOnly = true)
    Map<String, Object> dashboard(@RequestParam(required = false) String session) {
        Map<String, Object> out = new LinkedHashMap<>();
        String col = actingCollege();
        if (col == null) {
            out.put("resolved", false);
            return out;
        }
        out.put("resolved", true);
        out.put("faculty", col);
        out.put("facultyName", jdbc.sql("SELECT name FROM ref.college WHERE code = :c").param("c", col).query(String.class).optional().orElse(col));
        String s = session != null && session.matches("\\d{4}/\\d{4}") ? session
                : jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027");
        out.put("session", s);

        out.put("students", jdbc.sql("""
                SELECT count(*) FROM people.student st
                  JOIN ref.programme p ON p.code = st.programme_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE f.college_code = :c AND st.status IN ('ACTIVE','PROBATION')
                """).param("c", col).query(Long.class).single());

        out.put("byDept", jdbc.sql("""
                SELECT d.code, d.name,
                       count(DISTINCT st.id) AS students,
                       count(DISTINCT st.id) FILTER (WHERE EXISTS (
                           SELECT 1 FROM registration.course_registration r
                            WHERE r.student_id = st.id AND r.session = :s AND r.status IN ('APPROVED','LOCKED'))) AS registered
                  FROM ref.department d
                  JOIN ref.faculty f ON f.code = d.faculty_code
                  JOIN ref.programme p ON p.dept_code = d.code
                  JOIN people.student st ON st.programme_code = p.code AND st.status IN ('ACTIVE','PROBATION')
                 WHERE f.college_code = :c
                 GROUP BY d.code, d.name ORDER BY d.name
                """).param("c", col).param("s", s).query().listOfRows());

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
                  JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE o.session = :s AND f.college_code = :c
                """).param("c", col).param("s", s).query().singleRow());

        Map<String, Object> off = jdbc.sql("""
                SELECT count(*) AS total, count(*) FILTER (WHERE o.lecturer_id IS NULL) AS need_lecturer
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                  JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE o.session = :s AND f.college_code = :c
                """).param("c", col).param("s", s).query().singleRow();
        out.put("offeringsTotal", off.get("total"));
        out.put("offeringsNeedLecturer", off.get("need_lecturer"));

        out.put("probation", jdbc.sql("""
                SELECT count(*) FROM people.student st
                  JOIN ref.programme p ON p.code = st.programme_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE f.college_code = :c AND st.status = 'PROBATION'
                """).param("c", col).query(Long.class).single());
        out.put("atRisk", jdbc.sql("""
                SELECT st.surname || ', ' || st.other_names AS name, coalesce(st.matric_no, st.admission_no) AS number,
                       p.name AS programme, st.current_level AS level
                  FROM people.student st
                  JOIN ref.programme p ON p.code = st.programme_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE f.college_code = :c AND st.status = 'PROBATION'
                 ORDER BY st.current_level, st.surname LIMIT 12
                """).param("c", col).query().listOfRows());

        return out;
    }
}
