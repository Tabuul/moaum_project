package ng.edu.moaum.portal.finance;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

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

/**
 * V647: school-fees history, JAMB number to matriculation number. The old portal named a payer by whatever number they had — a JAMB
 * registration number before matriculation — and the old-fees import now resolves it to the student (people.resolve_student), keeping
 * the number beside the payment (finance.payment_identity). A payment whose number names no student yet, or several, is held
 * (finance.legacy_payment_held); here the Students Account Officer and the Bursary read the held payments as their numbers resolve now
 * (MATCHED, AMBIGUOUS, NO_MATCH, ALREADY_RECONCILED, DUPLICATE, INVALID), initiate a PAY-RECON batch of the matched, and a Bursar
 * officer who did not initiate it approves — each payment recorded once by the import — or rejects it. The database holds every rule.
 */
@RestController
@RequestMapping("/api/v1/finance/fee-history-reconciliation")
class FeeHistoryReconciliationController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    private static final String INITIATORS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts')";
    private static final String DECIDERS = "hasAuthority('OFFICE_bursar')";

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;

    FeeHistoryReconciliationController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> json(String text) {
        return text == null ? Map.of() : JSON.readValue(text, Map.class);
    }

    @GetMapping("/figures")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> figures() {
        return json(jdbc.sql("SELECT finance.fee_history_figures()::text").query(String.class).single());
    }

    private static final String SCAN = "FROM finance.fee_history_scan(:ses, :cat, :pur, :q, :fac, :dept, :prog) s";

    /** the held payments as their numbers resolve now, filtered and paged; the matched ones are what a batch takes */
    @GetMapping("/held")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> held(@RequestParam(required = false) String session, @RequestParam(required = false) String category,
                             @RequestParam(required = false) String purpose, @RequestParam(required = false) String q,
                             @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                             @RequestParam(required = false) String prog, @RequestParam(defaultValue = "0") int page,
                             @RequestParam(defaultValue = "50") int size) {
        int sz = Math.min(Math.max(size, 1), 500);
        int pg = Math.max(page, 0);
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> totals = scan(jdbc.sql("SELECT count(*) AS n, coalesce(sum(s.amount), 0) AS amount " + SCAN),
                session, category, purpose, q, fac, dept, prog).query().singleRow();
        out.put("total", totals.get("n"));
        out.put("amount", totals.get("amount"));
        out.put("byCategory", scan(jdbc.sql("SELECT s.category, count(*) AS n, coalesce(sum(s.amount), 0) AS amount " + SCAN + " GROUP BY 1 ORDER BY 1"),
                session, null, purpose, q, fac, dept, prog).query().listOfRows());
        out.put("rows", scan(jdbc.sql("SELECT s.* " + SCAN + " ORDER BY s.session DESC NULLS LAST, s.original_identifier, s.payref LIMIT :n OFFSET :o"),
                session, category, purpose, q, fac, dept, prog).param("n", sz).param("o", pg * sz).query().listOfRows());
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    private static JdbcClient.StatementSpec scan(JdbcClient.StatementSpec spec, String session, String category, String purpose, String q,
                                                String fac, String dept, String prog) {
        return spec.param("ses", blank(session), Types.VARCHAR).param("cat", blank(category) == null ? null : category.trim().toUpperCase(), Types.VARCHAR)
                .param("pur", blank(purpose) == null ? null : purpose.trim().toUpperCase(), Types.VARCHAR).param("q", blank(q), Types.VARCHAR)
                .param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR);
    }

    public record Initiate(List<UUID> heldIds, Boolean allMatched, String session, String purpose, String q, String fac, String dept, String prog,
                           @NotBlank @Size(max = 2000) String reason) {
    }

    /** a batch of the matched held payments — those chosen, or every matched one under the filters (Match JAMB payments) */
    @PostMapping("/batches")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> initiate(@Valid @RequestBody Initiate body) {
        List<UUID> ids = body.heldIds();
        if (Boolean.TRUE.equals(body.allMatched())) {
            ids = scan(jdbc.sql("SELECT s.id " + SCAN), body.session(), "MATCHED", body.purpose(), body.q(), body.fac(), body.dept(), body.prog())
                    .query(UUID.class).list();
        }
        if (ids == null || ids.isEmpty()) {
            throw new DomainRuleViolation("FEE_RECON_NONE", "No held payment names one student under these filters.",
                    new DomainRuleViolation.Remedy("Widen the filters, or wait for the students to come onto the register.", "You"));
        }
        String ref = jdbc.sql("SELECT finance.fee_history_initiate(CAST(:ids AS uuid[]), :r)")
                .param("ids", ids.stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).param("r", body.reason().trim())
                .query(String.class).single();
        return batch(ref);
    }

    @GetMapping("/batches")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> batches() {
        return jdbc.sql("""
                SELECT b.ref, b.state, b.reason, b.scanned, b.matched, b.ambiguous, b.unmatched, b.duplicate, b.amount, b.reconciled, b.reconciled_amount,
                       helpdesk.person_name(b.initiated_by) AS initiated_by, b.initiated_office, b.initiated_at,
                       helpdesk.person_name(b.decided_by) AS decided_by, b.decided_office, b.decided_at, b.decision_note, cardinality(b.held_ids) AS payments
                  FROM finance.fee_history_recon_batch b ORDER BY b.initiated_at DESC LIMIT 200
                """).query().listOfRows();
    }

    @GetMapping("/batches/{year}/{seq}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> batch(@PathVariable String year, @PathVariable String seq) {
        return batch("PAY-RECON/" + year + "/" + seq);
    }

    private Map<String, Object> batch(String ref) {
        Map<String, Object> b = jdbc.sql("""
                SELECT b.ref, b.state, b.reason, b.scanned, b.matched, b.ambiguous, b.unmatched, b.duplicate, b.amount, b.reconciled, b.reconciled_amount,
                       b.initiated_by AS initiated_by_id, helpdesk.person_name(b.initiated_by) AS initiated_by, b.initiated_office, b.initiated_at,
                       helpdesk.person_name(b.decided_by) AS decided_by, b.decided_office, b.decided_at, b.decision_note, b.result::text AS result
                  FROM finance.fee_history_recon_batch b WHERE b.ref = :r
                """).param("r", ref).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("reconciliation", ref));
        Map<String, Object> out = new LinkedHashMap<>(b);
        out.put("payments", jdbc.sql("""
                SELECT h.id, h.original_identifier, h.identifier_type, h.purpose, h.session, h.semester, h.amount, h.payref, h.status, h.payment_id,
                       s.id AS student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS student_name, s.matric_no,
                       pr.reference AS payment_reference
                  FROM finance.fee_history_recon_batch b
                  JOIN finance.legacy_payment_held h ON h.id = ANY (b.held_ids)
                  LEFT JOIN LATERAL people.resolve_student(h.original_identifier, true) rs ON true
                  LEFT JOIN people.student s ON s.id = coalesce((SELECT pr2.student_id FROM finance.payment_reference pr2 WHERE pr2.id = h.payment_id), rs.student_id)
                  LEFT JOIN finance.payment_reference pr ON pr.id = h.payment_id
                 WHERE b.ref = :r ORDER BY h.session, h.original_identifier
                """).param("r", ref).query().listOfRows());
        return out;
    }

    public record Decision(Boolean approve, @Size(max = 2000) String note) {
    }

    @PostMapping("/batches/{year}/{seq}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable String year, @PathVariable String seq, @Valid @RequestBody Decision body) {
        String ref = "PAY-RECON/" + year + "/" + seq;
        Map<String, Object> out = new LinkedHashMap<>(json(jdbc.sql("SELECT finance.fee_history_decide(:r, :a, :n)::text")
                .param("r", ref).param("a", Boolean.TRUE.equals(body.approve())).param("n", blank(body.note()), Types.VARCHAR).query(String.class).single()));
        out.put("batch", batch(ref));
        return out;
    }

    public record Withdrawal(@Size(max = 2000) String reason) {
    }

    @PostMapping("/batches/{year}/{seq}/withdraw")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> withdraw(@PathVariable String year, @PathVariable String seq, @RequestBody Withdrawal body) {
        String ref = "PAY-RECON/" + year + "/" + seq;
        jdbc.sql("SELECT finance.fee_history_withdraw(:r, :w)").param("r", ref).param("w", blank(body.reason()), Types.VARCHAR).query().singleRow();
        return batch(ref);
    }
}
