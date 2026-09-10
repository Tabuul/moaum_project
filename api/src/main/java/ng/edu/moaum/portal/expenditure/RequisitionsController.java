package ng.edu.moaum.portal.expenditure;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Procurement requisitions (V076): the method is set by value and cannot be overridden. */
@RestController
class RequisitionsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String RAISERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_ict','OFFICE_registrar','OFFICE_hrm','OFFICE_dean','OFFICE_super')";
    private static final String APPROVERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;

    RequisitionsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Raise(@NotBlank @Size(max = 200) String item, @Size(max = 600) String description, @NotBlank @Size(max = 120) String costCentre, @NotNull @DecimalMin("1") BigDecimal value) {
    }

    public record Why(@NotBlank @Size(max = 400) String why) {
    }

    @GetMapping("/api/v1/expenditure/requisitions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String state) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.id, r.reference, r.item, r.description, r.cost_centre, r.value,
                       expenditure.procurement_method(r.value) AS method, r.state, r.note,
                       r.raised_at, pr.surname || ', ' || pr.given_names AS raised_by_name,
                       r.raised_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS raised_by_me
                  FROM expenditure.requisition r LEFT JOIN iam.person pr ON pr.id = r.raised_by
                 WHERE (:st::text IS NULL OR r.state = :st)
                 ORDER BY (r.state = 'RAISED') DESC, r.raised_at DESC
                """).param("st", state == null || state.isBlank() ? null : state.toUpperCase(), Types.VARCHAR).query().listOfRows();
        return Map.of("rows", rows);
    }

    @PostMapping("/api/v1/expenditure/requisitions")
    @PreAuthorize(RAISERS)
    @Transactional
    Map<String, Object> raise(@Valid @RequestBody Raise body) {
        String ref = jdbc.sql("SELECT 'RQ-' || to_char(current_date, 'YYYY') || '-' || lpad(platform.next_number('REQUISITION', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0')").query(String.class).single();
        jdbc.sql("""
                INSERT INTO expenditure.requisition (reference, item, description, cost_centre, value, raised_by)
                VALUES (:r, :i, :d, :cc, :v, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                """)
                .param("r", ref).param("i", body.item().trim())
                .param("d", body.description() == null || body.description().isBlank() ? null : body.description().trim(), Types.VARCHAR)
                .param("cc", body.costCentre().trim()).param("v", body.value())
                .update();
        return Map.of("reference", ref, "state", "RAISED");
    }

    @PostMapping("/api/v1/expenditure/requisitions/{id}/approve")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id) {
        int n = jdbc.sql("""
                UPDATE expenditure.requisition
                   SET state = 'APPROVED', decided_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, decided_at = now()
                 WHERE id = :id AND state = 'RAISED' AND raised_by <> nullif(current_setting('moaum.actor_id', true), '')::uuid
                """).param("id", id).update();
        if (n == 0) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("RQ_APPROVE", "This requisition cannot be approved by you.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("A requisition is approved by a second officer, and only while it is raised.", "Bursary"));
        }
        return Map.of("id", id, "state", "APPROVED");
    }

    @PostMapping("/api/v1/expenditure/requisitions/{id}/po")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> po(@PathVariable UUID id) {
        jdbc.sql("UPDATE expenditure.requisition SET state = 'PO_RAISED' WHERE id = :id AND state = 'APPROVED'").param("id", id).update();
        return Map.of("id", id, "state", "PO_RAISED");
    }

    @PostMapping("/api/v1/expenditure/requisitions/{id}/close")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> close(@PathVariable UUID id) {
        jdbc.sql("UPDATE expenditure.requisition SET state = 'CLOSED' WHERE id = :id AND state IN ('PO_RAISED','APPROVED')").param("id", id).update();
        return Map.of("id", id, "state", "CLOSED");
    }

    @PostMapping("/api/v1/expenditure/requisitions/{id}/reject")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> reject(@PathVariable UUID id, @Valid @RequestBody Why body) {
        jdbc.sql("""
                UPDATE expenditure.requisition
                   SET state = 'REJECTED', decision_note = :w, decided_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, decided_at = now()
                 WHERE id = :id AND state = 'RAISED'
                """).param("id", id).param("w", body.why().trim()).update();
        return Map.of("id", id, "state", "REJECTED");
    }
}
