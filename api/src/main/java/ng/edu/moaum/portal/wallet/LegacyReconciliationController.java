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
 * Legacy financial reconciliation (V625): the Students Account Officer's desk for the old portal's outstanding fees and e-wallet
 * top-ups. The outstanding fees of a session as the reconciliation classifies each student — what the student owes (a liability,
 * never wallet money) and what the student paid above the fees stated (a credit the University holds); the legacy credit request
 * that carries a verified overpayment to the wallet: confirmed and initiated by the officer, approved, rejected or returned for
 * correction by a Bursar officer other than the initiator, the wallet credited once on approval. The database holds every rule
 * (finance.legacy_credit_*); the offices here only keep a reader from asking for a write. The e-wallet half is the legacy wallet
 * desk (LegacyWalletController, V583), whose figures this desk reads too.
 *
 * <p>V631: the old portal's OUTSTANDING FEES payments, kept apart from school fees — listed one a payment, verified by the Students
 * Account Officer (or the Bursar), credited to the student's wallet by a Bursar officer other than the verifier (one credit a
 * payment, source LEGACY_OUTSTANDING), or rejected, returned to the officer or reopened by the Bursar with a reason
 * (finance.legacy_outstanding_payment_*).
 */
@RestController
@RequestMapping("/api/v1/finance/legacy-reconciliation")
class LegacyReconciliationController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit',"
            + "'OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String INITIATORS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";
    private static final String DECIDERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final StudentReach reach;
    private final tools.jackson.databind.ObjectMapper json;

    LegacyReconciliationController(JdbcClient jdbc, OfficeScope scope, StudentReach reach, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.reach = reach;
        this.json = json;
    }

    /** the officer's confirmation: the amount (null = the excess the records show), the reason, the evidence, the reason for a
     *  different amount, and the explicit confirmation — never a blind one-click */
    record Request(UUID student, String session, BigDecimal amount, String reason, String evidence, String adjustmentReason, Boolean confirmed) { }
    record Decision(String action, String note) { }
    record Reason(String reason) { }
    /** V631: the payments ticked, the officer's remarks and, for a verification, the explicit confirmation */
    record Payments(List<UUID> ids, String note, Boolean confirmed) { }
    record PaymentDecision(String action, String reason) { }

    private Map<String, Object> jsonOf(String text) {
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private String sessionOr(String session) {
        String s = blank(session);
        return s != null ? s : jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
    }

    /** the desk's figures: the session's outstanding fees (liabilities and credits kept apart), the requests by state, the old e-wallet */
    @GetMapping("/figures")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> figures(@RequestParam(required = false) String session) {
        Map<String, Object> out = new LinkedHashMap<>(jsonOf(jdbc.sql("SELECT finance.legacy_reconciliation_figures(:s)::text").param("s", sessionOr(session)).query(String.class).single()));
        out.put("outstandingPayments", jsonOf(jdbc.sql("SELECT finance.legacy_outstanding_payment_figures()::text").query(String.class).single()));
        return out;
    }

    /** the sessions with old-portal school-fees payments on record, latest first */
    @GetMapping("/sessions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<String> sessions() {
        return jdbc.sql("""
                SELECT DISTINCT r.session FROM finance.payment_reference r
                 WHERE r.channel = 'Legacy' AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
                 ORDER BY r.session DESC
                """).query(String.class).list();
    }

    /** the old portal's outstanding fees of a session, student by student — OWES, CREDIT, CREDIT_DECIDED, SETTLED, NO_FEE_STATED */
    @GetMapping("/outstanding")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> outstanding(@RequestParam(required = false) String session, @RequestParam(required = false) String state,
                                          @RequestParam(required = false) String q, @RequestParam(required = false) String fac,
                                          @RequestParam(required = false) String dept, @RequestParam(defaultValue = "500") int limit,
                                          @RequestParam(defaultValue = "true") boolean legacyOnly) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), null);
        return jdbc.sql("SELECT * FROM finance.legacy_outstanding_rows(:s, :st, :q, :fac, :dept, :limit, :legacy)")
                .param("s", sessionOr(session)).param("st", blank(state), Types.VARCHAR).param("q", blank(q), Types.VARCHAR)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR)
                .param("limit", Math.max(1, Math.min(limit, 5000))).param("legacy", legacyOnly).query().listOfRows();
    }

    /** the legacy credit requests — the queue (pending the Bursar, returned), the history (credited, rejected, withdrawn) */
    @GetMapping("/requests")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> requests(@RequestParam(required = false) String status, @RequestParam(required = false) String session,
                                       @RequestParam(required = false) String q, @RequestParam(required = false) String fac,
                                       @RequestParam(required = false) String dept, @RequestParam(defaultValue = "500") int limit) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), null);
        return jdbc.sql("SELECT * FROM finance.legacy_credit_rows(:st, :s, :q, :fac, :dept, :limit)")
                .param("st", blank(status), Types.VARCHAR).param("s", blank(session), Types.VARCHAR).param("q", blank(q), Types.VARCHAR)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR)
                .param("limit", Math.max(1, Math.min(limit, 5000))).query().listOfRows();
    }

    @GetMapping("/requests/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> request(@PathVariable UUID id) {
        Map<String, Object> row = jdbc.sql("SELECT * FROM finance.legacy_credit_rows(NULL, NULL, NULL, NULL, NULL, 5000) r WHERE r.id = :id").param("id", id)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("legacy credit request", id));
        reach.check(UUID.fromString(String.valueOf(row.get("student_id"))));
        return row;
    }

    /** one student's legacy picture: the sessions with old-portal payments and the position on each, the requests, the old e-wallet */
    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable UUID id) {
        reach.check(id);
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.student WHERE id = :s)").param("s", id).query(Boolean.class).single()) throw new NotFound("student", id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", jdbc.sql("""
                SELECT s.id, s.surname || ', ' || s.other_names AS name, s.matric_no, s.jamb_reg_no, s.admission_no, s.programme_code, p.name AS programme,
                       p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty, s.current_level, s.status, s.entry_session
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE s.id = :s
                """).param("s", id).query().singleRow());
        out.put("sessions", jdbc.sql("""
                SELECT x.session, pos.due, pos.paid, greatest(pos.due - pos.paid, 0) AS owed, greatest(pos.paid - pos.due, 0) AS excess,
                       x.legacy_payments, x.legacy_amount, d.decision, d.amount AS decided_amount, d.reference AS decision_reference
                  FROM (SELECT r.session, count(*) FILTER (WHERE r.channel = 'Legacy')::int AS legacy_payments,
                               coalesce(sum(r.amount) FILTER (WHERE r.channel = 'Legacy'), 0) AS legacy_amount
                          FROM finance.payment_reference r
                         WHERE r.student_id = :s AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
                         GROUP BY r.session) x
                  CROSS JOIN LATERAL finance.position(:s, x.session) pos
                  LEFT JOIN LATERAL finance.overpayment_settled(:s, x.session) d ON true
                 ORDER BY x.session DESC
                """).param("s", id).query().listOfRows());
        out.put("payments", jdbc.sql("""
                SELECT r.reference, r.session, r.purpose, r.amount, r.confirmed_at, r.channel, r.receipt_no, lp.payref AS legacy_payref, r.note
                  FROM finance.payment_reference r
                  LEFT JOIN finance.legacy_payref lp ON lp.reference = r.reference
                 WHERE r.student_id = :s AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
                 ORDER BY r.session DESC, r.confirmed_at
                """).param("s", id).query().listOfRows());
        out.put("requests", jdbc.sql("SELECT * FROM finance.legacy_credit_rows(NULL, NULL, NULL, NULL, NULL, 5000) r WHERE r.student_id = :s ORDER BY r.initiated_at DESC")
                .param("s", id).query().listOfRows());
        out.put("legacyWallet", jsonOf(jdbc.sql("SELECT coalesce(finance.legacy_wallet_of(:s), '{}'::jsonb)::text").param("s", id).query(String.class).single()));
        out.put("walletBalance", jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", id).query(BigDecimal.class).optional().orElse(BigDecimal.ZERO));
        return out;
    }

    /** the officer confirms the overpayment and initiates the credit: nothing is credited here; the Bursar is told */
    @PostMapping("/requests")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> initiate(@RequestBody Request body) {
        if (body.student() == null) throw new DomainRuleViolation("LEGACY_CREDIT_STUDENT", "Name the student.", new DomainRuleViolation.Remedy("Open the student's row and confirm from there.", "You"));
        reach.check(body.student());
        if (!Boolean.TRUE.equals(body.confirmed())) {
            throw new DomainRuleViolation("LEGACY_CREDIT_CONFIRM", "Confirm that the legacy record and the amount were reviewed against the available records.",
                    new DomainRuleViolation.Remedy("Tick the confirmation before submitting.", "You"));
        }
        Map<String, Object> row = jdbc.sql("SELECT (r).id AS id FROM (SELECT finance.legacy_credit_initiate(:s, :ses, :a, :why, :ev, :adj) AS r) x")
                .param("s", body.student()).param("ses", blank(body.session()), Types.VARCHAR).param("a", body.amount(), Types.NUMERIC)
                .param("why", blank(body.reason()), Types.VARCHAR).param("ev", blank(body.evidence()), Types.VARCHAR).param("adj", blank(body.adjustmentReason()), Types.VARCHAR)
                .query().singleRow();
        return request(UUID.fromString(String.valueOf(row.get("id"))));
    }

    /** a request the Bursar returned, corrected and sent again */
    @PostMapping("/requests/{id}/resubmit")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> resubmit(@PathVariable UUID id, @RequestBody Request body) {
        reach.check(studentOf(id));
        if (!Boolean.TRUE.equals(body.confirmed())) {
            throw new DomainRuleViolation("LEGACY_CREDIT_CONFIRM", "Confirm that the legacy record and the amount were reviewed against the available records.",
                    new DomainRuleViolation.Remedy("Tick the confirmation before submitting.", "You"));
        }
        jdbc.sql("SELECT finance.legacy_credit_resubmit(:id, :a, :why, :ev, :adj)")
                .param("id", id).param("a", body.amount(), Types.NUMERIC).param("why", blank(body.reason()), Types.VARCHAR)
                .param("ev", blank(body.evidence()), Types.VARCHAR).param("adj", blank(body.adjustmentReason()), Types.VARCHAR).query().listOfRows();
        return request(id);
    }

    @PostMapping("/requests/{id}/withdraw")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id, @RequestBody Reason body) {
        reach.check(studentOf(id));
        jdbc.sql("SELECT finance.legacy_credit_withdraw(:id, :why)").param("id", id).param("why", blank(body.reason()), Types.VARCHAR).query().listOfRows();
        return request(id);
    }

    /** the Bursar's decision — approve (the wallet credited once), reject or return for correction; never the initiator's own */
    @PostMapping("/requests/{id}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @RequestBody Decision body) {
        reach.check(studentOf(id));
        jdbc.sql("SELECT finance.legacy_credit_decide(:id, :a, :n)").param("id", id).param("a", blank(body.action()), Types.VARCHAR).param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        return request(id);
    }

    /* ── V631: the old portal's OUTSTANDING FEES payments ── */

    /** one row a payment — WAITING, VERIFIED, RETURNED, CREDITED, REJECTED (TO_VERIFY = waiting or returned) — with the student's
     *  school-fee position on that session */
    @GetMapping("/outstanding-payments")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> outstandingPayments(@RequestParam(required = false) String status, @RequestParam(required = false) String session,
                                                  @RequestParam(required = false) String q, @RequestParam(required = false) String fac,
                                                  @RequestParam(required = false) String dept, @RequestParam(required = false) UUID student,
                                                  @RequestParam(defaultValue = "500") int limit) {
        if (student != null) reach.check(student);
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), null);
        return jdbc.sql("SELECT * FROM finance.legacy_outstanding_payment_rows(:st, :s, :q, :fac, :dept, :limit, :student)")
                .param("st", blank(status), Types.VARCHAR).param("s", blank(session), Types.VARCHAR).param("q", blank(q), Types.VARCHAR)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR)
                .param("limit", Math.max(1, Math.min(limit, 5000))).param("student", student, Types.OTHER).query().listOfRows();
    }

    /** the officer verifies the ticked payments against the records: nothing is credited here; the Bursar is told */
    @PostMapping("/outstanding-payments/verify")
    @PreAuthorize(INITIATORS)
    @Transactional
    Map<String, Object> verifyOutstandingPayments(@RequestBody Payments body) {
        List<UUID> ids = idsOf(body, "verify");
        if (!Boolean.TRUE.equals(body.confirmed())) {
            throw new DomainRuleViolation("LEGACY_OUTSTANDING_CONFIRM", "Confirm that each payment was checked against the available records.",
                    new DomainRuleViolation.Remedy("Tick the confirmation before verifying.", "You"));
        }
        int n = jdbc.sql("SELECT finance.legacy_outstanding_payment_verify(CAST(:ids AS uuid[]), :n)")
                .param("ids", ids.stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).param("n", blank(body.note()), Types.VARCHAR)
                .query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("verified", n);
        out.put("asked", ids.size());
        return out;
    }

    /** a Bursar officer other than the verifier credits the verified payments to the wallets: one credit a payment, under a batch */
    @PostMapping("/outstanding-payments/credit")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> creditOutstandingPayments(@RequestBody Payments body) {
        List<UUID> ids = idsOf(body, "credit");
        Map<String, Object> row = jdbc.sql("SELECT batch_ref, credited, amount, skipped, skipped_why::text AS skipped_why "
                        + "FROM finance.legacy_outstanding_payment_credit(CAST(:ids AS uuid[]), :n)")
                .param("ids", ids.stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).param("n", blank(body.note()), Types.VARCHAR).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(row);
        out.put("skipped_why", json.readValue(String.valueOf(row.get("skipped_why")), Object.class));
        return out;
    }

    /** the Bursar rejects a payment, returns a verified one to the officer or reopens a rejected one, with a reason */
    @PostMapping("/outstanding-payments/{id}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decideOutstandingPayment(@PathVariable UUID id, @RequestBody PaymentDecision body) {
        UUID student = jdbc.sql("SELECT student_id FROM finance.payment_reference WHERE id = :id").param("id", id).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("outstanding fees payment", id));
        reach.check(student);
        jdbc.sql("SELECT finance.legacy_outstanding_payment_decide(:id, :a, :r)").param("id", id).param("a", blank(body.action()), Types.VARCHAR)
                .param("r", blank(body.reason()), Types.VARCHAR).query().listOfRows();
        return jdbc.sql("SELECT * FROM finance.legacy_outstanding_payment_rows(NULL, NULL, NULL, NULL, NULL, 5000, :s) r WHERE r.payment_id = :id")
                .param("s", student, Types.OTHER).param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("outstanding fees payment", id));
    }

    private static List<UUID> idsOf(Payments body, String verb) {
        if (body == null || body.ids() == null || body.ids().isEmpty()) {
            throw new DomainRuleViolation("LEGACY_OUTSTANDING_NONE", "Tick the payments to " + verb + ".", new DomainRuleViolation.Remedy("Choose at least one.", "You"));
        }
        if (body.ids().size() > 2000) {
            throw new DomainRuleViolation("LEGACY_OUTSTANDING_BATCH_SIZE", "Up to 2,000 payments at once.", new DomainRuleViolation.Remedy("Do the rest in another batch.", "You"));
        }
        return body.ids();
    }

    private UUID studentOf(UUID id) {
        return jdbc.sql("SELECT student_id FROM finance.legacy_credit_request WHERE id = :id").param("id", id).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("legacy credit request", id));
    }
}
