package ng.edu.moaum.portal.catalogue;

import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** A department's course catalogue (V042). */
@RestController
@RequestMapping("/api/v1/catalogue")
class CatalogueController {

    private static final String OWNERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;

    CatalogueController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record NewCourse(@NotBlank @Size(max = 8) String code, @NotBlank @Size(max = 120) String title,
                            @NotNull @Min(0) Integer units, @NotNull Integer semester, @NotNull Integer level,
                            @NotBlank @Size(max = 12) String dept, @Size(max = 20) String kind) {
    }

    /** every course a department owns, with the lecturer of its offering in the current session, if any */
    @GetMapping("/courses")
    @PreAuthorize(OWNERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses(@RequestParam String dept) {
        return jdbc.sql("""
                WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1)
                SELECT c.code, c.title, c.units, c.semester, c.level, c.kind, c.state, c.ended_on,
                       (SELECT CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
                          FROM catalogue.offering o LEFT JOIN iam.person p ON p.id = o.lecturer_id
                         WHERE o.course_code = c.code AND o.session = (SELECT name FROM cur)
                         ORDER BY o.semester LIMIT 1) AS lecturer,
                       EXISTS (SELECT 1 FROM catalogue.offering o2 WHERE o2.course_code = c.code AND o2.session = (SELECT name FROM cur)) AS offered
                  FROM catalogue.course c
                 WHERE c.dept_code = :dept
                 ORDER BY c.level, c.semester, c.code
                """).param("dept", dept).query().listOfRows();
    }

    @PostMapping("/courses")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> create(@Valid @RequestBody NewCourse body) {
        String code = jdbc.sql("SELECT catalogue.create_course(:c, :t, :u, :s, :l, :d, :k)")
                .param("c", body.code()).param("t", body.title()).param("u", body.units()).param("s", body.semester())
                .param("l", body.level()).param("d", body.dept()).param("k", body.kind())
                .query(String.class).single();
        return Map.of("code", code, "state", "BOARD");
    }

    @PostMapping("/courses/{code}/end")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> end(@PathVariable String code) {
        jdbc.sql("SELECT catalogue.end_course(:c)").param("c", code).query().singleRow();
        return Map.of("code", code, "state", "ENDED");
    }
}
