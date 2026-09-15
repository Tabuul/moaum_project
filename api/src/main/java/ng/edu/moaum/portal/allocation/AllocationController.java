package ng.edu.moaum.portal.allocation;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.constraints.NotNull;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Teaching allocation, worked by the Head of Department (V041). */
@RestController
@RequestMapping("/api/v1/allocation")
class AllocationController {

    private static final String ALLOCATORS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;

    AllocationController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Assign(@NotNull UUID lecturer, UUID secondExaminer, Boolean overload) {
    }

    /** the departments a lecturer can be allocated in (reference data, any signed-in staff) */
    @GetMapping("/departments")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    List<Map<String, Object>> departments() {
        return jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows();
    }

    /** the department's offerings for a session and semester, with who is on each and how many are registered */
    @GetMapping
    @PreAuthorize(ALLOCATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> offerings(@RequestParam String dept, @RequestParam String session, @RequestParam(defaultValue = "1") int semester) {
        return jdbc.sql("""
                SELECT o.id, o.course_code, c.title, c.units, o.allocated_on,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND r.status = 'APPROVED') AS registered,
                       o.lecturer_id,
                       CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END AS lecturer,
                       o.second_examiner_id,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END AS second_examiner,
                       EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = o.id) AS sheet
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                  LEFT JOIN iam.person sp ON sp.id = o.second_examiner_id
                 WHERE o.session = :session AND o.semester = :semester AND c.dept_code = :dept
                 ORDER BY o.course_code
                """).param("session", session).param("semester", semester).param("dept", dept).query().listOfRows();
    }

    /**
     * The lecturers a course can be allocated to, with their current teaching load. By default the
     * department's own lecturers; with all=true, every lecturer in the University (each labelled with
     * their home department) so a department can assign its course to a lecturer from another
     * department — the cross-department teaching case. The lecturer keeps one dashboard and enters the
     * scores there, whatever department the course belongs to.
     */
    @GetMapping("/lecturers")
    @PreAuthorize(ALLOCATORS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> lecturers(@RequestParam String dept, @RequestParam String session,
                                        @RequestParam(defaultValue = "1") int semester,
                                        @RequestParam(defaultValue = "false") boolean all) {
        String live = "a.office_code IN ('lecturer', 'hod') AND a.scope_kind = 'department'"
                + " AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)";
        String load = "coalesce((SELECT sum(c.units) FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code"
                + " WHERE o.lecturer_id = p.id AND o.session = :session AND o.semester = :semester), 0) AS load";
        if (all) {
            return jdbc.sql("""
                    SELECT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number,
                           (SELECT string_agg(DISTINCT a.scope_id, ', ' ORDER BY a.scope_id) FROM iam.office_assignment a
                             WHERE a.person_id = p.id AND %s) AS department,
                           %s
                      FROM iam.person p
                     WHERE p.ended_on IS NULL
                       AND EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p.id AND %s)
                     ORDER BY name
                    """.formatted(live, load, live))
                    .param("session", session).param("semester", semester).query().listOfRows();
        }
        return jdbc.sql("""
                SELECT DISTINCT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number, :dept AS department,
                       %s
                  FROM iam.person p
                  JOIN iam.office_assignment a ON a.person_id = p.id
                 WHERE %s AND a.scope_id = :dept
                 ORDER BY load, name
                """.formatted(load, live))
                .param("session", session).param("semester", semester).param("dept", dept).query().listOfRows();
    }

    /** assign a lecturer and a second examiner to an offering */
    @PostMapping("/{offering}")
    @PreAuthorize(ALLOCATORS)
    @Transactional
    Map<String, Object> assign(@PathVariable UUID offering, @RequestBody Assign body) {
        jdbc.sql("SELECT catalogue.allocate_offering(:o, :lec, :sec, :ov)")
                .param("o", offering).param("lec", body.lecturer())
                .param("sec", body.secondExaminer(), Types.OTHER)
                .param("ov", Boolean.TRUE.equals(body.overload()))
                .query().singleRow();
        return Map.of("offering", offering, "allocated", true);
    }
}
