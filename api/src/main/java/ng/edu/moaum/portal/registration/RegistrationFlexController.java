package ng.edu.moaum.portal.registration;

import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Flexible course registration (V504): whether students add courses beside their recommended list (ON by default), how wide —
 * PROGRAMME (their programme's courses at other levels and electives, and the University-wide GST/EPS courses), DEPARTMENT or
 * FACULTY — and whether a course of a higher level than the student's may be added (OFF by default). The Academic Office, the
 * Registry, the Directorate of ICT and super set it with a reason (registration.set_flex_policy refuses any other office too), on
 * the audit spine. Each course a student adds is still judged by the engine (registration.course_check) whatever the rule.
 * V590: whether every curriculum's courses (BMAS, CCMAS) are open to every student whatever the cohort's track (ON from V590), set
 * the same way (registration.set_curriculum_open).
 */
@RestController
@RequestMapping("/api/v1/registration/flex")
class RegistrationFlexController {

    static final String SETTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";

    public record FlexIn(@NotNull Boolean allowOtherCourses, @NotBlank String otherScope, @NotNull Boolean allowHigherLevels,
                         @NotBlank @Size(min = 10, max = 500) String reason) {
    }

    public record CurriculumIn(@NotNull Boolean open, @NotBlank @Size(min = 10, max = 500) String reason) {
    }

    private final JdbcClient jdbc;

    RegistrationFlexController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private Map<String, Object> rule() {
        return jdbc.sql("""
                SELECT p.allow_other_courses, p.other_scope, p.allow_higher_levels, p.curriculum_open, p.reason, p.set_at, helpdesk.person_name(p.set_by) AS set_by, p.set_office
                  FROM registration.flex_rule() p
                """).query().singleRow();
    }

    /** the rule in force — read by the offices that set registration */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> get() {
        return rule();
    }

    @PutMapping
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> set(@Valid @RequestBody FlexIn body) {
        jdbc.sql("SELECT registration.set_flex_policy(:a, :s, :h, :r)").param("a", body.allowOtherCourses())
                .param("s", body.otherScope().trim().toUpperCase()).param("h", body.allowHigherLevels()).param("r", body.reason().trim()).query().listOfRows();
        return rule();
    }

    /** V590: every curriculum's courses open to every student, or the curricula kept apart again */
    @PutMapping("/curriculum")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> curriculum(@Valid @RequestBody CurriculumIn body) {
        jdbc.sql("SELECT registration.set_curriculum_open(:o, :r)").param("o", body.open()).param("r", body.reason().trim()).query().listOfRows();
        return rule();
    }
}
