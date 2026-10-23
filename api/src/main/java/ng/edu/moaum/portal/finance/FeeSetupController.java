package ng.edu.moaum.portal.finance;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V648: the school fees setup — whether a line has been used, removing a line never used, archiving (deactivating) one that was, and
 * a line's versions. The University's master prompt of 23 October 2026 ("SCHOOL FEES SETUP STRUCTURE — EDIT AND REMOVE INCORRECT
 * LEVELS"). The database decides (finance.fee_line_usage, finance.remove_fee_lines): a line no student is charged by and no invoice,
 * payment or ledger entry was made under is removed; any other is archived — ended, kept, no longer charged. No payment reference,
 * receipt, gateway transaction, wallet entry or ledger entry is touched. Adding, editing and ending a line stay on FinanceController.
 */
@RestController
@RequestMapping("/api/v1/finance")
class FeeSetupController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String FEE_SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";

    /** the lines to remove or archive, how, and why — a reason code (Other described) when applied */
    public record Removal(@NotNull @NotEmpty @Size(max = 1000) List<UUID> ids,
                          @NotNull @Pattern(regexp = "REMOVE|DEACTIVATE|AUTO") String mode,
                          @Pattern(regexp = "ADDED_IN_ERROR|WRONG_LEVEL|DUPLICATE|WRONG_PROGRAMME|WRONG_FACULTY|WRONG_SESSION|WRONG_SEMESTER|REPLACED|OTHER") String reasonCode,
                          @Size(max = 400) String reason) {
    }

    private final JdbcClient jdbc;

    FeeSetupController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String office() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    private List<String> permissions() {
        return jdbc.sql("SELECT unnest(finance.fee_setup_permissions(:o))").param("o", office()).query(String.class).list();
    }

    private void need(String permission) {
        if (!permissions().contains(permission)) {
            throw new AccessDeniedException("Your office does not hold " + permission + " on the school fees setup.");
        }
    }

    /** the lines asked for must be the session's (a removed line is not on the schedule, and is answered NOT_FOUND) */
    private void ofSession(String session, List<UUID> ids) {
        long other = jdbc.sql("SELECT count(*) FROM finance.fee_schedule f WHERE f.id = ANY (CAST(:ids AS uuid[])) AND f.session <> :s")
                .param("ids", ids.stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).param("s", session).query(Long.class).single();
        if (other > 0) {
            throw new DomainRuleViolation("FEE_LINE_SESSION", other + " of the lines chosen belong to another session.",
                    new DomainRuleViolation.Remedy("Choose the lines on the session's own schedule.", "Bursary"));
        }
    }

    /** what the acting office may do with the fee setup: the screen shows Edit, Remove, Deactivate and History by it */
    @GetMapping("/fee-setup/permissions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> permissionsOf() {
        return Map.of("office", office(), "permissions", permissions());
    }

    /** whether each line has been used — the lines named (ids), or every line of the session in the status asked */
    @GetMapping("/sessions/{session}/{year}/schedule/usage")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> usage(@PathVariable String session, @PathVariable String year, @RequestParam(required = false) List<UUID> ids,
                                    @RequestParam(required = false) @Pattern(regexp = "ACTIVE|ARCHIVED|ALL") String status) {
        need("VIEW_FEE_SETUP");
        String s = session + "/" + year;
        String st = status == null ? "ACTIVE" : status;
        if (ids != null && ids.size() > 5000) {
            throw new DomainRuleViolation("FEE_USAGE_TOO_MANY", "Ask for 5,000 lines at most.", new DomainRuleViolation.Remedy("Narrow the filters.", "Bursary"));
        }
        return jdbc.sql("""
                SELECT x.* FROM finance.fee_line_usage(ARRAY(
                    SELECT f.id FROM finance.fee_schedule f
                     WHERE f.session = :s
                       AND (CAST(:ids AS uuid[]) IS NULL OR f.id = ANY (CAST(:ids AS uuid[])))
                       AND CASE :st WHEN 'ARCHIVED' THEN f.ended_at IS NOT NULL WHEN 'ALL' THEN true ELSE f.ended_at IS NULL END)) x
                """).param("s", s).param("st", ids != null ? "ALL" : st)
                .param("ids", ids == null ? null : ids.stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY)
                .query().listOfRows();
    }

    /** what removing (or archiving) the lines would do — each REMOVED, ARCHIVED, CANNOT_REMOVE or ALREADY_ARCHIVED — nothing changed */
    @PostMapping("/sessions/{session}/{year}/schedule/remove/preview")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> removePreview(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Removal body) {
        need("VIEW_FEE_SETUP");
        ofSession(session + "/" + year, body.ids());
        return answered(body, false);
    }

    /** the lines removed (never used) or archived (used): REMOVE refuses a used line (CANNOT_REMOVE, unchanged); DEACTIVATE archives;
     *  AUTO removes or archives each as its use decides. The Bursar's office removes; the Students Account Officer deactivates. */
    @PostMapping("/sessions/{session}/{year}/schedule/remove")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> remove(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Removal body) {
        if (!"DEACTIVATE".equals(body.mode())) {
            need("REMOVE_FEE_STRUCTURE");
        }
        if (!"REMOVE".equals(body.mode())) {
            need("DEACTIVATE_FEE_STRUCTURE");
        }
        ofSession(session + "/" + year, body.ids());
        return answered(body, true);
    }

    private Map<String, Object> answered(Removal body, boolean apply) {
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM finance.remove_fee_lines(CAST(:ids AS uuid[]), :m, :c, :r, :a)")
                .param("ids", body.ids().stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).param("m", body.mode())
                .param("c", body.reasonCode(), Types.VARCHAR).param("r", body.reason() == null || body.reason().isBlank() ? null : body.reason().trim(), Types.VARCHAR)
                .param("a", apply).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("applied", apply);
        out.put("mode", body.mode());
        out.put("selected", rows.size());
        for (String o : List.of("REMOVED", "ARCHIVED", "CANNOT_REMOVE", "ALREADY_ARCHIVED", "NOT_FOUND")) {
            out.put(o, rows.stream().filter(r -> o.equals(r.get("outcome"))).count());
        }
        out.put("rows", rows);
        return out;
    }

    /** every version of a line — created, edited, versioned, replaced, deactivated, removed — with who, when and why */
    @GetMapping("/sessions/{session}/{year}/schedule/{id}/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        need("VIEW_FEE_STRUCTURE_HISTORY");
        boolean known = jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.id = :id AND f.session = :s)
                    OR EXISTS (SELECT 1 FROM finance.fee_line_change c WHERE c.line_id = :id AND c.session = :s)
                """).param("id", id).param("s", session + "/" + year).query(Boolean.class).single();
        if (!known) {
            throw new NotFound("fee line", id.toString());
        }
        return jdbc.sql("SELECT * FROM finance.fee_line_history(:id)").param("id", id).query().listOfRows();
    }

    /** the session's lines removed permanently (never used), as they were, with the reason, who and when */
    @GetMapping("/sessions/{session}/{year}/schedule/removed")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> removed(@PathVariable String session, @PathVariable String year) {
        need("VIEW_FEE_STRUCTURE_HISTORY");
        return jdbc.sql("""
                SELECT c.line_id AS id, c.at, c.reason_code, finance.fee_remove_reason_words(c.reason_code) AS reason_words, c.reason, c.actor_office AS office,
                       (SELECT btrim(pe.surname || ', ' || pe.given_names) FROM iam.person pe WHERE pe.id = c.actor) AS by_name,
                       c.before_state ->> 'item' AS item, (c.before_state ->> 'amount')::numeric AS amount, (c.before_state ->> 'level')::integer AS level,
                       c.before_state ->> 'entry_mode' AS entry_mode, c.before_state ->> 'faculty_code' AS faculty_code, fa.name AS faculty_name,
                       c.before_state ->> 'programme_code' AS programme_code, p.name AS programme_name, d.name AS department_name, pfa.name AS programme_faculty_name,
                       (c.before_state ->> 'semester')::integer AS semester, coalesce((c.before_state ->> 'spillover')::boolean, false) AS spillover,
                       (c.before_state ->> 'spill_year')::integer AS spill_year, c.before_state ->> 'kind' AS kind, c.before_state ->> 'indigene' AS indigene,
                       c.batch
                  FROM finance.fee_line_change c
                  LEFT JOIN ref.faculty fa ON fa.code = c.before_state ->> 'faculty_code'
                  LEFT JOIN ref.programme p ON p.code = c.before_state ->> 'programme_code'
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty pfa ON pfa.code = p.faculty_code
                 WHERE c.session = :s AND c.action = 'FEE_STRUCTURE_REMOVED'
                 ORDER BY c.at DESC
                 LIMIT 2000
                """).param("s", session + "/" + year).query().listOfRows();
    }
}
