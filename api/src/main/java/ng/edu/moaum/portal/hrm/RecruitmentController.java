package ng.edu.moaum.portal.hrm;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Recruitment (V073): vacancies and the applications scored against them. */
@RestController
class RecruitmentController {

    private static final String READERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_audit','OFFICE_admin','OFFICE_super')";
    private static final String OFFICERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_registrar','OFFICE_super')";

    private final JdbcClient jdbc;

    RecruitmentController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Vacancy(@NotBlank @Size(max = 200) String title, @NotBlank @Size(max = 120) String department,
                          @NotBlank @Size(max = 600) String requirements, @Size(max = 20) String grade, @Size(max = 20) String category, String closesOn) {
    }

    public record State(@NotBlank @Size(max = 20) String state) {
    }

    public record Application(@NotBlank @Size(max = 160) String name, @Size(max = 160) String email, @Size(max = 40) String phone,
                              @Size(max = 200) String qualification, Integer publications, java.math.BigDecimal teachingYears) {
    }

    public record Assess(Integer score, @Size(max = 200) String recommendation, @Size(max = 20) String state) {
    }

    @GetMapping("/api/v1/hr/vacancies")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> vacancies(@RequestParam(required = false) String state) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT v.id, v.title, v.department, v.requirements, v.grade, v.category, v.opened_on, v.closes_on, v.state, v.note,
                       (SELECT count(*) FROM hrm.applicant a WHERE a.vacancy_id = v.id) AS applications,
                       (SELECT count(*) FROM hrm.applicant a WHERE a.vacancy_id = v.id AND a.state = 'SHORTLISTED') AS shortlisted
                  FROM hrm.vacancy v
                 WHERE (:st::text IS NULL OR v.state = :st)
                 ORDER BY (v.state = 'OPEN') DESC, v.opened_on DESC
                """).param("st", state == null || state.isBlank() ? null : state.toUpperCase(), Types.VARCHAR).query().listOfRows();
        return Map.of("rows", rows);
    }

    @PostMapping("/api/v1/hr/vacancies")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody Vacancy body) {
        UUID id = jdbc.sql("""
                INSERT INTO hrm.vacancy (title, department, requirements, grade, category, closes_on)
                VALUES (:t, :d, :r, :g, :c, :cl) RETURNING id
                """)
                .param("t", body.title().trim()).param("d", body.department().trim()).param("r", body.requirements().trim())
                .param("g", body.grade() == null || body.grade().isBlank() ? null : body.grade().trim(), Types.VARCHAR)
                .param("c", body.category() == null || body.category().isBlank() ? null : body.category().trim(), Types.VARCHAR)
                .param("cl", body.closesOn() == null || body.closesOn().isBlank() ? null : java.time.LocalDate.parse(body.closesOn()), Types.DATE)
                .query(UUID.class).single();
        return Map.of("id", id, "state", "OPEN");
    }

    @PostMapping("/api/v1/hr/vacancies/{id}/state")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> setState(@PathVariable UUID id, @Valid @RequestBody State body) {
        int n = jdbc.sql("UPDATE hrm.vacancy SET state = :s WHERE id = :id").param("s", body.state().toUpperCase()).param("id", id).update();
        return Map.of("id", id, "updated", n);
    }

    @GetMapping("/api/v1/hr/vacancies/{id}/applicants")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> applicants(@PathVariable UUID id) {
        Map<String, Object> vacancy = jdbc.sql("SELECT id, title, department, requirements, grade, state FROM hrm.vacancy WHERE id = :id").param("id", id).query().singleRow();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT id, name, email, phone, qualification, publications, teaching_years, score, recommendation, state, applied_at
                  FROM hrm.applicant WHERE vacancy_id = :id ORDER BY score DESC NULLS LAST, name
                """).param("id", id).query().listOfRows();
        return Map.of("vacancy", vacancy, "rows", rows);
    }

    @PostMapping("/api/v1/hr/vacancies/{id}/applicants")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> record(@PathVariable UUID id, @Valid @RequestBody Application body) {
        UUID appId = jdbc.sql("""
                INSERT INTO hrm.applicant (vacancy_id, name, email, phone, qualification, publications, teaching_years)
                VALUES (:v, :n, :e, :p, :q, :pub, :ty) RETURNING id
                """)
                .param("v", id).param("n", body.name().trim())
                .param("e", body.email() == null || body.email().isBlank() ? null : body.email().trim(), Types.VARCHAR)
                .param("p", body.phone() == null || body.phone().isBlank() ? null : body.phone().trim(), Types.VARCHAR)
                .param("q", body.qualification() == null || body.qualification().isBlank() ? null : body.qualification().trim(), Types.VARCHAR)
                .param("pub", body.publications(), Types.INTEGER).param("ty", body.teachingYears(), Types.NUMERIC)
                .query(UUID.class).single();
        return Map.of("id", appId, "state", "APPLIED");
    }

    @PostMapping("/api/v1/hr/applicants/{id}/assess")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> assess(@PathVariable UUID id, @Valid @RequestBody Assess body) {
        jdbc.sql("""
                UPDATE hrm.applicant
                   SET score = coalesce(:sc, score),
                       recommendation = coalesce(:rec, recommendation),
                       state = coalesce(:st, state)
                 WHERE id = :id
                """)
                .param("sc", body.score(), Types.INTEGER)
                .param("rec", body.recommendation() == null || body.recommendation().isBlank() ? null : body.recommendation().trim(), Types.VARCHAR)
                .param("st", body.state() == null || body.state().isBlank() ? null : body.state().toUpperCase(), Types.VARCHAR)
                .param("id", id).update();
        return Map.of("id", id, "updated", true);
    }
}
