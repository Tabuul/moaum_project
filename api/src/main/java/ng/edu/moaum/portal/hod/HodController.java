package ng.edu.moaum.portal.hod;

import java.util.LinkedHashMap;
import java.util.Map;

import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Head of Department's home, scoped to their own department by OfficeScope:
 * the registrations waiting on them, the offerings still without a lecturer,
 * and the size of the department — the figures a dashboard should lead with.
 * Read-only.
 */
@RestController
@RequestMapping("/api/v1/hod")
class HodController {

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    HodController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    @GetMapping("/dashboard")
    @PreAuthorize("hasAuthority('OFFICE_hod')")
    @Transactional(readOnly = true)
    Map<String, Object> dashboard(@RequestParam(required = false) String session) {
        Map<String, Object> out = new LinkedHashMap<>();
        String dept = scope.actingDept();
        if (dept == null || dept.isBlank() || "__none__".equals(dept)) {
            out.put("resolved", false);
            return out;   // the office is not resolved to a department; the screen explains
        }
        out.put("resolved", true);
        out.put("dept", dept);
        out.put("deptName", jdbc.sql("SELECT name FROM ref.department WHERE code = :d").param("d", dept).query(String.class).optional().orElse(dept));
        String s = session != null && session.matches("\\d{4}/\\d{4}") ? session
                : jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027");
        out.put("session", s);

        out.put("approvals", jdbc.sql("""
                SELECT count(*) FROM registration.course_registration r
                  JOIN people.student st ON st.id = r.student_id
                  JOIN ref.programme p ON p.code = st.programme_code
                 WHERE r.session = :s AND r.status = 'SUBMITTED' AND p.dept_code = :d
                """).param("s", s).param("d", dept).query(Long.class).single());

        out.put("offeringsNeedLecturer", jdbc.sql("""
                SELECT count(*) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                 WHERE o.session = :s AND c.dept_code = :d AND o.lecturer_id IS NULL
                """).param("s", s).param("d", dept).query(Long.class).single());

        out.put("offeringsTotal", jdbc.sql("""
                SELECT count(*) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                 WHERE o.session = :s AND c.dept_code = :d
                """).param("s", s).param("d", dept).query(Long.class).single());

        out.put("deptStudents", jdbc.sql("""
                SELECT count(*) FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
                 WHERE p.dept_code = :d AND st.status IN ('ACTIVE', 'PROBATION')
                """).param("d", dept).query(Long.class).single());

        out.put("deptCourses", jdbc.sql("SELECT count(*) FROM catalogue.course WHERE dept_code = :d AND state <> 'ENDED'")
                .param("d", dept).query(Long.class).single());

        out.put("needLecturer", jdbc.sql("""
                SELECT c.code, c.title, c.level, o.semester
                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                 WHERE o.session = :s AND c.dept_code = :d AND o.lecturer_id IS NULL
                 ORDER BY c.level, c.code LIMIT 12
                """).param("s", s).param("d", dept).query().listOfRows());

        return out;
    }

    /** the department's academic staff, scoped to the acting HOD's own department — names and ranks only,
     *  no payroll. For the HOD to see who is on the establishment of their department. */
    @GetMapping("/staff")
    @PreAuthorize("hasAuthority('OFFICE_hod')")
    @Transactional(readOnly = true)
    Map<String, Object> staff() {
        Map<String, Object> out = new LinkedHashMap<>();
        String dept = scope.actingDept();
        if (dept == null || dept.isBlank() || "__none__".equals(dept)) {
            out.put("resolved", false);
            return out;
        }
        out.put("resolved", true);
        out.put("dept", dept);
        out.put("deptName", jdbc.sql("SELECT name FROM ref.department WHERE code = :d").param("d", dept).query(String.class).optional().orElse(dept));
        out.put("staff", jdbc.sql("""
                SELECT p.surname || ', ' || p.given_names AS name, sr.pno, sr.present_rank, sr.sex,
                       (SELECT status FROM hrm.employment e WHERE e.person_id = sr.person_id ORDER BY (status = 'ACTIVE') DESC LIMIT 1) AS employment,
                       EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = sr.person_id AND a.office_code = 'lecturer'
                                AND (a.valid_to IS NULL OR a.valid_to > current_date)) AS teaches
                  FROM hrm.staff_record sr JOIN iam.person p ON p.id = sr.person_id
                 WHERE sr.home_department = :d
                 ORDER BY p.surname, p.given_names
                """).param("d", dept).query().listOfRows());
        return out;
    }
}
