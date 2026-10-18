package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

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

/** V557: the bank reconciliation statement of 1010 Bank — Fees collection or 1020 Bank — Disbursements for a period — the ledger's
 *  balance beside the statement's with the items between them; prepared by the Bursary, signed by another officer and then kept. */
@RestController
@RequestMapping("/api/v1/finance/bank-reconciliation")
class BankReconciliationController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_admin','OFFICE_super')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    /** the items sent with a reconciliation; the figures count them all */
    static final int ITEM_ROWS = 5000;

    /** a reconciliation prepared: the account, the period and the closing balance on the bank's statement */
    public record Prepare(@NotNull @Pattern(regexp = "1010|1020") String account, @NotNull LocalDate from, @NotNull LocalDate to,
                          @NotNull BigDecimal closing, @Size(max = 2000) String note) {
    }

    /** a statement line accounted for with a journal; no journal number takes it back */
    public record Journal(@Positive Long journalNo, @Size(max = 500) String note) {
    }

    /** V562: a statement line booked in one press against an account */
    public record Book(@NotBlank @Size(max = 20) String account, @NotBlank @Size(max = 500) String note) {
    }

    /** V562: a transfer between the bank accounts booked from its two lines */
    public record Transfer(@NotNull UUID outLine, @NotNull UUID inLine, @NotBlank @Size(max = 500) String note) {
    }

    /** V562: a signed month asked to be reopened */
    public record Reopen(@NotBlank @Size(max = 2000) String reason) {
    }

    /** V562: a request to reopen decided */
    public record Decide(@NotNull Boolean approve, @Size(max = 2000) String note) {
    }

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    BankReconciliationController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private static void period(String account, LocalDate from, LocalDate to) {
        if (!"1010".equals(account) && !"1020".equals(account)) {
            throw new DomainRuleViolation("RECON_ACCOUNT", "A bank reconciliation is of 1010 Bank — Fees collection or 1020 Bank — Disbursements.");
        }
        if (to.isBefore(from) || ChronoUnit.DAYS.between(from, to) > 366) {
            throw new DomainRuleViolation("RECON_PERIOD", "A reconciliation is of a period of a year at most, its last day not before its first.");
        }
    }

    /** the reconciliation of a period: the one kept as signed, else worked out now (with the closing balance given, or the one the
     *  draft holds), its items, the lines accounted for with a journal, and the draft or signed record */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    @SuppressWarnings("unchecked")
    Map<String, Object> reconciliation(@RequestParam String account, @RequestParam LocalDate from,
                                       @RequestParam LocalDate to, @RequestParam(required = false) BigDecimal closing) {
        period(account, from, to);
        Map<String, Object> saved = jdbc.sql("""
                SELECT r.id, r.account, r.period_from::text AS period_from, r.period_to::text AS period_to, r.statement_closing, r.ledger_balance,
                       r.items_effect, r.difference, r.note, r.state, r.prepared_at, r.signed_at, r.summary::text AS figures, r.items::text AS items,
                       CASE WHEN pp.id IS NULL THEN NULL ELSE pp.surname || ', ' || pp.given_names END AS prepared_by_name,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END AS signed_by_name,
                       r.prepared_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS prepared_by_me
                  FROM finance.bank_reconciliation r
                  LEFT JOIN iam.person pp ON pp.id = r.prepared_by LEFT JOIN iam.person sp ON sp.id = r.signed_by
                 WHERE r.account = :a AND r.period_from = :f AND r.period_to = :t
                """).param("a", account).param("f", from).param("t", to).query().listOfRows().stream().findFirst()
                .<Map<String, Object>>map(java.util.LinkedHashMap::new).orElse(null);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        List<Map<String, Object>> items;
        if (saved != null && "SIGNED".equals(saved.get("state"))) {
            // kept as it was signed: its figures and its items
            out.put("figures", json.readValue((String) saved.get("figures"), Map.class));
            items = json.readValue((String) saved.get("items"), List.class);
        } else {
            BigDecimal c = closing != null ? closing : saved == null ? null : (BigDecimal) saved.get("statement_closing");
            out.put("figures", json.readValue(jdbc.sql("SELECT finance.bank_reconciliation_figures(:a, :f, :t, :c)::text")
                    .param("a", account).param("f", from).param("t", to).param("c", c, Types.NUMERIC).query(String.class).single(), Map.class));
            items = jdbc.sql("""
                    SELECT kind, reference, day::text AS day, description, amount, effect, line_id, journal_no
                      FROM finance.bank_reconciliation_items(:a, :f, :t) LIMIT :n
                    """).param("a", account).param("f", from).param("t", to).param("n", ITEM_ROWS + 1).query().listOfRows();
        }
        if (saved != null) {
            saved.remove("figures");
            saved.remove("items");
        }
        out.put("saved", saved);
        out.put("itemsMore", items.size() > ITEM_ROWS);
        out.put("items", items.size() > ITEM_ROWS ? items.subList(0, ITEM_ROWS) : items);
        out.put("booked", jdbc.sql("""
                SELECT l.id, l.line_no, s.label, coalesce(l.value_date, s.period_to)::text AS day, l.reference, l.description, l.debit, l.credit,
                       j.journal_no, j.memo AS journal_memo, l.booked_note
                  FROM finance.bank_statement_line l JOIN finance.bank_statement s ON s.id = l.statement_id
                  JOIN finance.gl_journal j ON j.id = l.ledger_journal
                 WHERE finance.bank_account_of(s.account_kind) = :a
                   AND coalesce(l.value_date, s.period_to) BETWEEN finance.bank_reconciliation_start(:a, :f) AND :t
                 ORDER BY 4, s.label, l.line_no
                """).param("a", account).param("f", from).param("t", to).query().listOfRows());
        return out;
    }

    /** the reconciliations prepared and signed, newest period first */
    @GetMapping("/saved")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> saved() {
        return jdbc.sql("""
                SELECT r.id, r.account, r.period_from::text AS period_from, r.period_to::text AS period_to, r.statement_closing, r.ledger_balance,
                       r.difference, r.state, r.prepared_at, r.signed_at,
                       CASE WHEN pp.id IS NULL THEN NULL ELSE pp.surname || ', ' || pp.given_names END AS prepared_by_name,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END AS signed_by_name
                  FROM finance.bank_reconciliation r
                  LEFT JOIN iam.person pp ON pp.id = r.prepared_by LEFT JOIN iam.person sp ON sp.id = r.signed_by
                 ORDER BY r.period_to DESC, r.account LIMIT 120
                """).query().listOfRows();
    }

    /** the Bursary prepares the reconciliation with the closing balance on the bank's statement (again, while unsigned) */
    @PostMapping
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> prepare(@Valid @RequestBody Prepare body) {
        period(body.account(), body.from(), body.to());
        jdbc.sql("SELECT finance.prepare_bank_reconciliation(:a, :f, :t, :c, :n)").param("a", body.account()).param("f", body.from()).param("t", body.to())
                .param("c", body.closing()).param("n", body.note(), Types.VARCHAR).query(UUID.class).single();
        return reconciliation(body.account(), body.from(), body.to(), null);
    }

    /** another officer of the Bursary signs it, once the period has ended and all is accounted for */
    @PostMapping("/{id}/sign")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> sign(@PathVariable UUID id) {
        jdbc.sql("SELECT finance.sign_bank_reconciliation(:id)::text").param("id", id).query(String.class).single();
        Map<String, Object> r = jdbc.sql("SELECT account, period_from::text AS period_from, period_to::text AS period_to FROM finance.bank_reconciliation WHERE id = :id")
                .param("id", id).query().singleRow();
        return reconciliation((String) r.get("account"), LocalDate.parse((String) r.get("period_from")), LocalDate.parse((String) r.get("period_to")), null);
    }

    /** a statement line accounted for with a posted journal moving its account, or taken back */
    @PostMapping("/lines/{id}/journal")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> journal(@PathVariable UUID id, @Valid @RequestBody Journal body) {
        jdbc.sql("SELECT finance.book_statement_line(:id, :j, :n)").param("id", id).param("j", body.journalNo(), Types.BIGINT)
                .param("n", body.note(), Types.VARCHAR).query().singleRow();
        return Map.of("id", id, "journalNo", body.journalNo() == null ? "" : body.journalNo());
    }

    /* ── V562: a line booked in one press, transfers, the months closed on the ledger ── */

    /** a statement line booked against the account named and tied to the journal at once */
    @PostMapping("/lines/{id}/book")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> book(@PathVariable UUID id, @Valid @RequestBody Book body) {
        Long no = jdbc.sql("SELECT finance.book_statement_line_to(:id, :a, :n)").param("id", id).param("a", body.account().trim())
                .param("n", body.note()).query(Long.class).single();
        return Map.of("id", id, "journalNo", no);
    }

    /** the transfers between the bank accounts the statements show and no one has booked */
    @GetMapping("/transfers")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> transfers(@RequestParam LocalDate from, @RequestParam LocalDate to) {
        period("1010", from, to);
        return jdbc.sql("""
                SELECT out_line, out_account, out_day::text AS out_day, out_text, in_line, in_account, in_day::text AS in_day, in_text, amount
                  FROM finance.transfer_candidates(:f, :t)
                """).param("f", from).param("t", to).query().listOfRows();
    }

    /** a transfer booked from its debit on one statement and its credit on the other */
    @PostMapping("/transfers")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> transfer(@Valid @RequestBody Transfer body) {
        Long no = jdbc.sql("SELECT finance.book_transfer(:o, :i, :n)").param("o", body.outLine()).param("i", body.inLine())
                .param("n", body.note()).query(Long.class).single();
        return Map.of("journalNo", no);
    }

    /** the months closed on the ledger (the signed reconciliations), the latest of each account marked, and the requests to reopen */
    @GetMapping("/closed")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> closed() {
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("months", jdbc.sql("""
                SELECT r.id, r.account, r.period_from::text AS period_from, r.period_to::text AS period_to, r.difference, r.signed_at,
                       CASE WHEN sp.id IS NULL THEN NULL ELSE sp.surname || ', ' || sp.given_names END AS signed_by_name,
                       NOT EXISTS (SELECT 1 FROM finance.bank_reconciliation l WHERE l.account = r.account AND l.state = 'SIGNED' AND l.period_from > r.period_to) AS latest,
                       EXISTS (SELECT 1 FROM finance.bank_reconciliation_reopen q WHERE q.reconciliation_id = r.id AND q.state = 'REQUESTED') AS reopen_asked
                  FROM finance.bank_reconciliation r LEFT JOIN iam.person sp ON sp.id = r.signed_by
                 WHERE r.state = 'SIGNED'
                 ORDER BY r.period_to DESC, r.account LIMIT 60
                """).query().listOfRows());
        out.put("requests", jdbc.sql("""
                SELECT q.id, q.account, q.period_from::text AS period_from, q.period_to::text AS period_to, q.reason, q.state, q.requested_at, q.decided_at, q.decision_note,
                       CASE WHEN rp.id IS NULL THEN NULL ELSE rp.surname || ', ' || rp.given_names END AS requested_by_name,
                       CASE WHEN dp.id IS NULL THEN NULL ELSE dp.surname || ', ' || dp.given_names END AS decided_by_name,
                       q.requested_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS asked_by_me
                  FROM finance.bank_reconciliation_reopen q
                  LEFT JOIN iam.person rp ON rp.id = q.requested_by LEFT JOIN iam.person dp ON dp.id = q.decided_by
                 ORDER BY (q.state = 'REQUESTED') DESC, q.requested_at DESC LIMIT 30
                """).query().listOfRows());
        return out;
    }

    /** one officer asks for the latest signed month of an account to be reopened */
    @PostMapping("/{id}/reopen")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> reopen(@PathVariable UUID id, @Valid @RequestBody Reopen body) {
        jdbc.sql("SELECT finance.request_reconciliation_reopen(:id, :r)").param("id", id).param("r", body.reason()).query(UUID.class).single();
        return closed();
    }

    /** another officer approves (the month open again, the reconciliation prepared, not signed) or rejects on a note */
    @PostMapping("/reopen/{id}/decide")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody Decide body) {
        jdbc.sql("SELECT finance.decide_reconciliation_reopen(:id, :a, :n)").param("id", id).param("a", body.approve())
                .param("n", body.note(), Types.VARCHAR).query().singleRow();
        return closed();
    }
}
