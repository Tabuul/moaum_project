package ng.edu.moaum.portal.hrm;

import java.time.LocalDate;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Staff movements (V072): the queue, and the acts that make a movement real. */
@RestController
class MovementController {

    private static final String READERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_audit','OFFICE_deputyaudit','OFFICE_admin','OFFICE_super')";
    private static final String OFFICERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_registrar','OFFICE_super')";
    private static final String APPROVERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_registrar','OFFICE_dregistrar','OFFICE_vc','OFFICE_dvc','OFFICE_super')";

    private final JdbcClient jdbc;

    MovementController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Raise(@NotBlank @Size(max = 40) String number, @NotBlank @Size(max = 30) String kind, @NotNull LocalDate effectiveDate,
                        @Size(max = 300) String whatChanges, @Size(max = 600) String reason, @Size(max = 20) String newGrade, Integer newStep) {
    }

    public record Why(@NotBlank @Size(max = 600) String why) {
    }

    private UUID personByNumber(String number) {
        return jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) LIMIT 1")
                .param("n", number == null ? "" : number.trim()).query(UUID.class).optional()
                .or(() -> jdbc.sql("SELECT p.id FROM iam.person p JOIN hrm.employment e ON e.person_id = p.id WHERE upper(e.staff_no) = upper(:n) OR upper(coalesce(p.staff_number, '')) = upper(:n) LIMIT 1")
                        .param("n", number == null ? "" : number.trim()).query(UUID.class).optional())
                .orElseThrow(() -> new NotFound("staff", number));
    }

    @GetMapping("/api/v1/hr/movements")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String state) {
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM hrm.movement_list(:st)")
                .param("st", state == null || state.isBlank() ? null : state.toUpperCase(), Types.VARCHAR).query().listOfRows();
        List<Map<String, Object>> grades = jdbc.sql("SELECT grade, step, category FROM hrm.grade ORDER BY category, grade, step").query().listOfRows();
        return Map.of("rows", rows, "grades", grades);
    }

    @PostMapping("/api/v1/hr/movements")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> raise(@Valid @RequestBody Raise body) {
        UUID person = personByNumber(body.number());
        UUID id = jdbc.sql("SELECT hrm.raise_movement(:p, :k, :e, :w, :r, :g, :s)")
                .param("p", person).param("k", body.kind()).param("e", body.effectiveDate())
                .param("w", body.whatChanges(), Types.VARCHAR).param("r", body.reason(), Types.VARCHAR)
                .param("g", body.newGrade(), Types.VARCHAR).param("s", body.newStep(), Types.INTEGER)
                .query(UUID.class).single();
        return Map.of("id", id, "state", "REQUESTED");
    }

    @PostMapping("/api/v1/hr/movements/{id}/approve")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id) {
        jdbc.sql("SELECT hrm.approve_movement(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "state", "APPROVED");
    }

    @PostMapping("/api/v1/hr/movements/{id}/decline")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> decline(@PathVariable UUID id, @Valid @RequestBody Why body) {
        jdbc.sql("SELECT hrm.decline_movement(:id, :w)").param("id", id).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "state", "DECLINED");
    }

    @PostMapping("/api/v1/hr/movements/{id}/issue")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> issue(@PathVariable UUID id) {
        String ref = jdbc.sql("SELECT hrm.issue_movement_instrument(:id)").param("id", id).query(String.class).single();
        return Map.of("id", id, "state", "IMPLEMENTED", "instrument", ref);
    }
}
