package ng.edu.moaum.portal.governance;

import java.sql.Types;
import java.time.LocalDate;
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
import org.springframework.web.bind.annotation.RestController;

/** Data governance (V075): the NDPA register, data-subject requests, DR drills, and security posture. */
@RestController
class GovernanceController {

    private static final String READERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_audit','OFFICE_deputyaudit','OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super')";
    private static final String WRITERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    private static final String ICT = "hasAnyAuthority('OFFICE_ict','OFFICE_super')";

    private final JdbcClient jdbc;

    GovernanceController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Dpia(@NotBlank @Size(max = 20) String state) {
    }

    public record Dsr(@NotBlank @Size(max = 20) String kind, @NotBlank @Size(max = 200) String requester, LocalDate dueOn, @Size(max = 400) String note) {
    }

    public record Advance(@NotBlank @Size(max = 20) String state, @Size(max = 400) String note) {
    }

    public record Drill(@NotBlank @Size(max = 20) String kind, LocalDate ranOn, Integer rpoMinutes, Integer rtoMinutes, @Size(max = 20) String outcome, @Size(max = 400) String note) {
    }

    /* ── the NDPA register ── */

    @GetMapping("/api/v1/governance/register")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> register() {
        List<Map<String, Object>> rows = jdbc.sql("SELECT id, activity, lawful_basis, sensitive, retention, dpia_state, note FROM governance.processing_activity ORDER BY activity").query().listOfRows();
        return Map.of("rows", rows);
    }

    @PostMapping("/api/v1/governance/register/{id}/dpia")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> dpia(@PathVariable UUID id, @Valid @RequestBody Dpia body) {
        int n = jdbc.sql("UPDATE governance.processing_activity SET dpia_state = :s WHERE id = :id").param("s", body.state().toUpperCase()).param("id", id).update();
        return Map.of("id", id, "updated", n);
    }

    /* ── data-subject rights requests ── */

    @GetMapping("/api/v1/governance/dsr")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> dsrList() {
        List<Map<String, Object>> rows = jdbc.sql("SELECT id, reference, kind, requester, received_on, due_on, state, note FROM governance.dsr ORDER BY (state IN ('RECEIVED','IN_PROGRESS')) DESC, due_on").query().listOfRows();
        return Map.of("rows", rows);
    }

    @PostMapping("/api/v1/governance/dsr")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> dsrRecord(@Valid @RequestBody Dsr body) {
        String ref = jdbc.sql("SELECT 'DSR-' || to_char(current_date, 'YYYY') || '-' || lpad(platform.next_number('DSR', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0')").query(String.class).single();
        jdbc.sql("""
                INSERT INTO governance.dsr (reference, kind, requester, received_on, due_on, note)
                VALUES (:r, :k, :req, current_date, coalesce(:due, current_date + 30), :n)
                """)
                .param("r", ref).param("k", body.kind().toUpperCase()).param("req", body.requester().trim())
                .param("due", body.dueOn(), Types.DATE).param("n", body.note() == null || body.note().isBlank() ? null : body.note().trim(), Types.VARCHAR)
                .update();
        return Map.of("reference", ref);
    }

    @PostMapping("/api/v1/governance/dsr/{id}/advance")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> dsrAdvance(@PathVariable UUID id, @Valid @RequestBody Advance body) {
        jdbc.sql("UPDATE governance.dsr SET state = :s, note = coalesce(:n, note) WHERE id = :id")
                .param("s", body.state().toUpperCase()).param("n", body.note() == null || body.note().isBlank() ? null : body.note().trim(), Types.VARCHAR).param("id", id).update();
        return Map.of("id", id, "state", body.state().toUpperCase());
    }

    /* ── disaster recovery ── */

    @GetMapping("/api/v1/governance/dr")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> dr() {
        List<Map<String, Object>> drills = jdbc.sql("SELECT id, kind, ran_on, rpo_minutes, rto_minutes, outcome, note FROM governance.dr_drill ORDER BY ran_on DESC LIMIT 50").query().listOfRows();
        return Map.of("drills", drills);
    }

    @PostMapping("/api/v1/governance/dr")
    @PreAuthorize(ICT)
    @Transactional
    Map<String, Object> recordDrill(@Valid @RequestBody Drill body) {
        UUID id = jdbc.sql("""
                INSERT INTO governance.dr_drill (kind, ran_on, rpo_minutes, rto_minutes, outcome, note)
                VALUES (:k, coalesce(:d, current_date), :rpo, :rto, coalesce(:o, 'PASSED'), :n) RETURNING id
                """)
                .param("k", body.kind().toUpperCase()).param("d", body.ranOn(), Types.DATE)
                .param("rpo", body.rpoMinutes(), Types.INTEGER).param("rto", body.rtoMinutes(), Types.INTEGER)
                .param("o", body.outcome() == null || body.outcome().isBlank() ? null : body.outcome().toUpperCase(), Types.VARCHAR)
                .param("n", body.note() == null || body.note().isBlank() ? null : body.note().trim(), Types.VARCHAR)
                .query(UUID.class).single();
        return Map.of("id", id);
    }

    /* ── security posture, from the audit spine and the sign-in record ── */

    @GetMapping("/api/v1/governance/security")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_audit','OFFICE_deputyaudit','OFFICE_security','OFFICE_registrar','OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super')")
    @Transactional(readOnly = true)
    Map<String, Object> security() {
        Map<String, Object> audit = jdbc.sql("""
                SELECT (SELECT count(*) FROM audit.entries) AS entries,
                       (SELECT count(*) FROM audit.chain_head) AS shards,
                       (SELECT count(*) FROM audit.unattached()) AS unattached_tables,
                       (SELECT max(occurred_at) FROM audit.entries) AS last_entry
                """).query().singleRow();
        Map<String, Object> signins = jdbc.sql("""
                SELECT count(*) FILTER (WHERE outcome = 'SIGNED_IN') AS signed_in,
                       count(*) FILTER (WHERE outcome = 'BAD_PASSWORD') AS bad_password,
                       count(*) FILTER (WHERE outcome = 'UNKNOWN') AS unknown_user,
                       count(*) FILTER (WHERE outcome = 'LOCKED') AS locked,
                       count(*) AS total
                  FROM iam.sign_in_event WHERE at > now() - interval '7 days'
                """).query().singleRow();
        List<Map<String, Object>> topFail = jdbc.sql("""
                SELECT username, count(*) AS attempts, max(at) AS last_at
                  FROM iam.sign_in_event WHERE at > now() - interval '7 days' AND outcome IN ('BAD_PASSWORD','UNKNOWN','LOCKED')
                 GROUP BY username ORDER BY count(*) DESC LIMIT 10
                """).query().listOfRows();
        return Map.of("audit", audit, "signins", signins, "topFailures", topFail);
    }
}
