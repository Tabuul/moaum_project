package ng.edu.moaum.portal.hrm;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Appraisal and promotion eligibility (V074). */
@RestController
class AppraisalController {

    private static final String READERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_dean','OFFICE_hod','OFFICE_audit','OFFICE_admin','OFFICE_super')";
    private static final String OFFICERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_registrar','OFFICE_dean','OFFICE_hod','OFFICE_super')";

    private final JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    AppraisalController(JdbcClient jdbc, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    public record Record(@NotBlank @Size(max = 40) String number, String cycle, Integer selfScore, Integer supervisorScore,
                         @Size(max = 1) String aperGrade, Integer publications, @Size(max = 400) String note, @Size(max = 20) String state) {
    }

    private String cycle(String asked) {
        if (asked != null && !asked.isBlank()) {
            return asked;
        }
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027");
    }

    @GetMapping("/api/v1/hr/appraisal")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> view(@RequestParam(required = false) String cycle) {
        String c = cycle(cycle);
        // a Head of Department sees only their own department's staff; a wider office sees all
        String dept = scope.actingHodDept();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT * FROM hrm.promotion_view(:c) v
                 WHERE :dept::text IS NULL
                    OR EXISTS (SELECT 1 FROM hrm.staff_record sr WHERE sr.person_id = v.person_id AND sr.home_department = :dept)
                """).param("c", c).param("dept", dept, Types.VARCHAR).query().listOfRows();
        return Map.of("cycle", c, "rows", rows);
    }

    @PostMapping("/api/v1/hr/appraisal")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> record(@Valid @RequestBody Record body) {
        UUID emp = jdbc.sql("""
                SELECT e.id FROM hrm.employment e JOIN iam.person p ON p.id = e.person_id
                 WHERE (upper(e.staff_no) = upper(:n) OR upper(coalesce(p.staff_number, '')) = upper(:n)) AND e.status = 'ACTIVE' LIMIT 1
                """).param("n", body.number().trim()).query().listOfRows().stream().findFirst()
                .map(r -> (UUID) r.get("id")).orElseThrow(() -> new NotFound("staff", body.number()));
        UUID person = jdbc.sql("SELECT person_id FROM hrm.employment WHERE id = :e").param("e", emp).query(UUID.class).single();
        // a Head of Department records appraisals only for their own department's staff
        String dept = scope.actingHodDept();
        if (dept != null) {
            boolean owned = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM hrm.staff_record sr WHERE sr.person_id = :p AND sr.home_department = :d)")
                    .param("p", person).param("d", dept).query(Boolean.class).single());
            if (!owned) {
                throw new NotFound("staff", body.number());
            }
        }
        String c = cycle(body.cycle());
        jdbc.sql("""
                INSERT INTO hrm.appraisal (employment_id, person_id, cycle, self_score, supervisor_score, aper_grade, publications, note, state, updated_at)
                VALUES (:e, :p, :c, :ss, :sv, :g, :pub, :n, coalesce(:st, 'SELF'), now())
                ON CONFLICT (person_id, cycle) DO UPDATE SET
                    self_score = coalesce(excluded.self_score, hrm.appraisal.self_score),
                    supervisor_score = coalesce(excluded.supervisor_score, hrm.appraisal.supervisor_score),
                    aper_grade = coalesce(excluded.aper_grade, hrm.appraisal.aper_grade),
                    publications = coalesce(excluded.publications, hrm.appraisal.publications),
                    note = coalesce(excluded.note, hrm.appraisal.note),
                    state = coalesce(excluded.state, hrm.appraisal.state),
                    updated_at = now()
                """)
                .param("e", emp).param("p", person).param("c", c)
                .param("ss", body.selfScore(), Types.INTEGER).param("sv", body.supervisorScore(), Types.INTEGER)
                .param("g", body.aperGrade() == null || body.aperGrade().isBlank() ? null : body.aperGrade().trim().toUpperCase(), Types.VARCHAR)
                .param("pub", body.publications(), Types.INTEGER)
                .param("n", body.note() == null || body.note().isBlank() ? null : body.note().trim(), Types.VARCHAR)
                .param("st", body.state() == null || body.state().isBlank() ? null : body.state().trim().toUpperCase(), Types.VARCHAR)
                .update();
        return Map.of("cycle", c, "recorded", true);
    }
}
