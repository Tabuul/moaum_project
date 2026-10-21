package ng.edu.moaum.portal.wallet;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;
import ng.edu.moaum.portal.student.StudentReach;

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
 * The old portal's e-wallet reconciled (V583): what each student topped up and paid from the old wallet, as the old-fees export
 * brought them; the balance classed and, where the Bursary holds the old portal's own statement, governed by it; verified by one
 * officer and posted to the wallet by another, as LEGACY_WALLET credits the student applies to fees on the wallet that exists. The
 * database holds every rule; the offices here only keep a reader from asking for a write.
 */
@RestController
@RequestMapping("/api/v1/finance/legacy-wallet")
class LegacyWalletController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit',"
            + "'OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String VERIFIERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";
    private static final String POSTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final StudentReach reach;
    private final tools.jackson.databind.ObjectMapper json;

    LegacyWalletController(JdbcClient jdbc, OfficeScope scope, StudentReach reach, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.reach = reach;
        this.json = json;
    }

    record Ids(List<UUID> ids, String note) { }
    record Decision(String action, String reason) { }
    record Statement(BigDecimal topups, BigDecimal used, BigDecimal refunds, BigDecimal reversed, BigDecimal balance, String source, String note) { }

    private Map<String, Object> jsonOf(String text) {
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    @GetMapping("/figures")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> figures() {
        return jsonOf(jdbc.sql("SELECT finance.legacy_wallet_figures()::text").query(String.class).single());
    }

    @GetMapping("/rows")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> rows(@RequestParam(required = false) String status, @RequestParam(required = false) String q,
                                   @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                   @RequestParam(required = false) Integer limit) {
        OfficeScope.Bound b = scope.bound(fac, dept, null);
        return jdbc.sql("SELECT * FROM finance.legacy_wallet_rows(:status, :q, :fac, :dept, :limit)")
                .param("status", blank(status), Types.VARCHAR).param("q", blank(q), Types.VARCHAR)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("limit", limit == null ? 500 : limit)
                .query().listOfRows();
    }

    /** the reconciliation run again over the imported payments: every student, or one */
    @PostMapping("/compute")
    @PreAuthorize(VERIFIERS)
    @Transactional
    Map<String, Object> compute(@RequestParam(required = false) UUID student) {
        if (student != null) reach.check(student);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT * FROM finance.legacy_wallet_compute(:s)").param("s", student, Types.OTHER).query().singleRow());
        out.put("figures", figures());
        return out;
    }

    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable UUID id) {
        reach.check(id);
        Map<String, Object> row = jdbc.sql("SELECT * FROM finance.legacy_wallet_rows(NULL, NULL, NULL, NULL, 5000) r WHERE r.student_id = :s")
                .param("s", id).query().listOfRows().stream().findFirst().orElse(null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("row", row);
        out.put("payments", jdbc.sql("""
                SELECT pr.reference, pr.session, pr.purpose, pr.amount, pr.confirmed_at, finance.legacy_wallet_method(pr.note) AS method, pr.note,
                       finance.legacy_wallet_is_topup(pr.purpose) AS topup
                  FROM finance.payment_reference pr
                 WHERE pr.student_id = :s AND pr.channel = 'Legacy' AND pr.confirmed_at IS NOT NULL
                   AND (finance.legacy_wallet_is_topup(pr.purpose) OR finance.legacy_wallet_method(pr.note) = 'E-Wallet')
                 ORDER BY pr.confirmed_at
                """).param("s", id).query().listOfRows());
        out.put("wallet", jdbc.sql("SELECT * FROM finance.wallet_statement(:s) w WHERE w.source_code = 'LEGACY_WALLET' ORDER BY w.at").param("s", id).query().listOfRows());
        return out;
    }

    /** the old portal's own statement for one student: it governs the balance, and the row is verified afresh */
    @PostMapping("/students/{id}/statement")
    @PreAuthorize(VERIFIERS)
    @Transactional
    Map<String, Object> statement(@PathVariable UUID id, @RequestBody Statement body) {
        reach.check(id);
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.student WHERE id = :s)").param("s", id).query(Boolean.class).single()) throw new NotFound("student", id);
        jdbc.sql("SELECT finance.legacy_wallet_state(:s, :t, :u, :r, :v, :b, :src, :n)")
                .param("s", id).param("t", body.topups(), Types.NUMERIC).param("u", body.used(), Types.NUMERIC).param("r", body.refunds(), Types.NUMERIC)
                .param("v", body.reversed(), Types.NUMERIC).param("b", body.balance(), Types.NUMERIC).param("src", body.source(), Types.VARCHAR)
                .param("n", body.note(), Types.VARCHAR).query().listOfRows();
        return student(id);
    }

    @PostMapping("/verify")
    @PreAuthorize(VERIFIERS)
    @Transactional
    Map<String, Object> verify(@RequestBody Ids body) {
        if (body.ids() == null || body.ids().isEmpty()) throw new DomainRuleViolation("LEGACY_WALLET_NONE", "Tick the balances to verify.", new DomainRuleViolation.Remedy("Choose at least one.", "You"));
        int n = jdbc.sql("SELECT finance.legacy_wallet_verify(CAST(:ids AS uuid[]), :n)").param("ids", body.ids().stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY)
                .param("n", body.note(), Types.VARCHAR).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("verified", n);
        out.put("asked", body.ids().size());
        return out;
    }

    /** posted by a Bursar officer other than the one who verified: one credit a student, under a batch */
    @PostMapping("/post")
    @PreAuthorize(POSTERS)
    @Transactional
    Map<String, Object> post(@RequestBody Ids body) {
        if (body.ids() == null || body.ids().isEmpty()) throw new DomainRuleViolation("LEGACY_WALLET_NONE", "Tick the verified balances to post.", new DomainRuleViolation.Remedy("Choose at least one.", "You"));
        if (body.ids().size() > 2000) throw new DomainRuleViolation("LEGACY_WALLET_BATCH_SIZE", "A posting takes up to 2,000 students at once.", new DomainRuleViolation.Remedy("Post the rest in another batch.", "You"));
        Map<String, Object> row = jdbc.sql("SELECT batch_ref, posted, amount, skipped, skipped_why::text AS skipped_why FROM finance.legacy_wallet_post(CAST(:ids AS uuid[]), :n)")
                .param("ids", body.ids().stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).param("n", body.note(), Types.VARCHAR).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(row);
        out.put("skipped_why", json.readValue(String.valueOf(row.get("skipped_why")), Object.class));
        return out;
    }

    @PostMapping("/{id}/decide")
    @PreAuthorize(POSTERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @RequestBody Decision body) {
        UUID student = jdbc.sql("SELECT student_id FROM finance.legacy_wallet WHERE id = :id").param("id", id).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("legacy wallet", id));
        reach.check(student);
        jdbc.sql("SELECT finance.legacy_wallet_decide(:id, :a, :r)").param("id", id).param("a", body.action(), Types.VARCHAR).param("r", body.reason(), Types.VARCHAR).query().listOfRows();
        return student(student);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
