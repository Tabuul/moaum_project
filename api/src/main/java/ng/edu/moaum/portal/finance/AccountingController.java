package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
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

/**
 * The Bursary's books: a double-entry general ledger over the cash the finance
 * desk already records. Reads (chart, trial balance, ledger, statements) are
 * open to the finance readers; posting — the sync, a manual journal, a reversal
 * — is the Bursary's own act.
 */
@RestController
@RequestMapping("/api/v1/finance/accounting")
class AccountingController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    public record Line(@NotBlank @Size(max = 20) String account, BigDecimal debit, BigDecimal credit,
                       @Size(max = 300) String narration, @Size(max = 12) String session) {
    }

    public record JournalIn(@NotNull LocalDate date, @NotBlank @Size(max = 300) String memo, @NotNull List<Line> lines) {
    }

    public record Reason(@NotBlank @Size(max = 300) String reason) {
    }

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    AccountingController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /* ── reads ── */

    @GetMapping("/chart")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> chart() {
        return jdbc.sql("SELECT code, name, type, normal_side, parent_code, postable, active FROM finance.gl_account WHERE active ORDER BY ord, code")
                .query().listOfRows();
    }

    /** the desk at a glance: cash on the books, income/expenditure this year, and what is waiting to be posted */
    @GetMapping("/overview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> overview() {
        LocalDate yearStart = LocalDate.of(LocalDate.now().getYear(), 1, 1);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("cash", jdbc.sql("""
                SELECT coalesce(sum(p.debit - p.credit), 0) AS balance
                  FROM finance.gl_posting p JOIN finance.gl_account a ON a.code = p.account
                 WHERE a.code IN ('1010','1020','1050')
                """).query(BigDecimal.class).single());
        out.put("ie", jdbc.sql("SELECT * FROM finance.income_expenditure(:f, :t) WHERE section IN ('INCOME_TOTAL','EXPENSE_TOTAL','SURPLUS')")
                .param("f", yearStart).param("t", LocalDate.now()).query().listOfRows());
        // V410: every payment of the one ledger, not only a student's, on the terms the sync posts them
        out.put("unposted", jdbc.sql("SELECT payments, refunds, vouchers FROM finance.gl_unposted()").query().singleRow());
        out.put("journals", jdbc.sql("SELECT count(*) FROM finance.gl_journal").query(Long.class).single());
        out.put("yearStart", yearStart);
        return out;
    }

    /** V506: what is waiting to be posted, alone — the screens that change payments (Old Fees History) show it and post it,
     *  without the overview's figures */
    @GetMapping("/unposted")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> unposted() {
        return jdbc.sql("SELECT payments, refunds, vouchers FROM finance.gl_unposted()").query().singleRow();
    }

    @GetMapping("/trial-balance")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> trialBalance(@RequestParam(required = false) LocalDate asOf) {
        LocalDate t = asOf == null ? LocalDate.now() : asOf;
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM finance.trial_balance(:t)").param("t", t).query().listOfRows();
        BigDecimal dr = rows.stream().map(r -> (BigDecimal) r.get("debit")).reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal cr = rows.stream().map(r -> (BigDecimal) r.get("credit")).reduce(BigDecimal.ZERO, BigDecimal::add);
        return Map.of("asOf", t, "rows", rows, "debit", dr, "credit", cr, "balanced", dr.compareTo(cr) == 0);
    }

    @GetMapping("/ledger")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> ledger(@RequestParam String account, @RequestParam(required = false) LocalDate from,
            @RequestParam(required = false) LocalDate to) {
        LocalDate f = from == null ? LocalDate.now().minusMonths(3) : from;
        LocalDate t = to == null ? LocalDate.now() : to;
        Map<String, Object> acct = jdbc.sql("SELECT code, name, type FROM finance.gl_account WHERE code = :c")
                .param("c", account).query().listOfRows().stream().findFirst().orElseThrow(() -> new DomainRuleViolation("GL_ACCOUNT",
                        "No such account.", new DomainRuleViolation.Remedy("Pick an account from the chart.", "Bursary")));
        // the day as the books keep it: a date, not a timestamp a time zone can move to the day before
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT to_char(entry_date, 'YYYY-MM-DD') AS entry_date, journal_no, memo, narration, debit, credit, balance
                  FROM finance.gl_ledger(:c, :f, :t)
                """).param("c", account).param("f", f).param("t", t).query().listOfRows();
        return Map.of("account", acct, "from", f, "to", t, "rows", rows);
    }

    @GetMapping("/income-expenditure")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> incomeExpenditure(@RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to) {
        LocalDate f = from == null ? LocalDate.of(LocalDate.now().getYear(), 1, 1) : from;
        LocalDate t = to == null ? LocalDate.now() : to;
        return Map.of("from", f, "to", t,
                "rows", jdbc.sql("SELECT * FROM finance.income_expenditure(:f, :t)").param("f", f).param("t", t).query().listOfRows());
    }

    @GetMapping("/balance-sheet")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> balanceSheet(@RequestParam(required = false) LocalDate asOf) {
        LocalDate t = asOf == null ? LocalDate.now() : asOf;
        return Map.of("asOf", t,
                "rows", jdbc.sql("SELECT * FROM finance.balance_sheet(:t)").param("t", t).query().listOfRows());
    }

    /** the journal book: recent journals with their lines nested — a list, not the database's jsonb wrapper, which the
     *  screen could not read (Lines on any journal failed) — and each entry date as the day it is */
    @GetMapping("/journals")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> journals(@RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
            @RequestParam(defaultValue = "100") int limit) {
        LocalDate f = from == null ? LocalDate.now().minusMonths(1) : from;
        LocalDate t = to == null ? LocalDate.now() : to;
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT j.id, j.journal_no, to_char(j.entry_date, 'YYYY-MM-DD') AS entry_date, j.memo, j.source, j.source_type, j.status,
                       (SELECT coalesce(sum(debit),0) FROM finance.gl_posting p WHERE p.journal_id = j.id) AS total,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('account', p.account, 'name', a.name,
                                'debit', p.debit, 'credit', p.credit, 'narration', p.narration) ORDER BY p.line)
                          FROM finance.gl_posting p JOIN finance.gl_account a ON a.code = p.account
                         WHERE p.journal_id = j.id), '[]'::jsonb)::text AS lines
                  FROM finance.gl_journal j
                 WHERE j.entry_date BETWEEN :f AND :t
                 ORDER BY j.journal_no DESC
                 LIMIT :lim
                """).param("f", f).param("t", t).param("lim", Math.min(limit, 500)).query().listOfRows();
        for (Map<String, Object> r : rows)
            r.put("lines", json.readValue(String.valueOf(r.get("lines")), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
        return rows;
    }

    /* ── posting ── */

    /**
     * sweep confirmed payments, paid refunds and paid vouchers not yet on the books into balanced journals — at most
     * {@code limit} of them, oldest first (V410), so a register with tens of thousands unposted is posted in batches that
     * each commit whole; the answer says how many remain, and the screen calls again until none do
     */
    @PostMapping("/sync")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> sync(@RequestParam(defaultValue = "" + SYNC_BATCH) int limit) {
        if (limit < 1 || limit > SYNC_BATCH_MAX)
            throw new DomainRuleViolation("SYNC_LIMIT", "A ledger sync posts between 1 and " + SYNC_BATCH_MAX + " transactions at a time.");
        return jdbc.sql("SELECT payments, refunds, vouchers, remaining FROM finance.gl_sync(:lim)").param("lim", limit).query().singleRow();
    }

    /** the batch the screen posts at a time, and the most one call may post */
    static final int SYNC_BATCH = 2000;
    static final int SYNC_BATCH_MAX = 10000;

    /** a hand-entered balanced journal — opening balances, adjustments, corrections */
    @PostMapping("/journals")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> postJournal(@Valid @RequestBody JournalIn body) {
        if (body.lines().size() < 2) {
            throw new DomainRuleViolation("GL_LINES", "A journal needs at least two lines.",
                    new DomainRuleViolation.Remedy("Add a debit and a credit.", "Bursary"));
        }
        BigDecimal dr = BigDecimal.ZERO, cr = BigDecimal.ZERO;
        for (Line l : body.lines()) {
            BigDecimal d = l.debit() == null ? BigDecimal.ZERO : l.debit();
            BigDecimal c = l.credit() == null ? BigDecimal.ZERO : l.credit();
            if (d.signum() < 0 || c.signum() < 0 || (d.signum() == 0) == (c.signum() == 0)) {
                throw new DomainRuleViolation("GL_LINE", "Each line is a debit or a credit, and positive.",
                        new DomainRuleViolation.Remedy("Fix the line: one side only, above zero.", "Bursary"));
            }
            dr = dr.add(d);
            cr = cr.add(c);
        }
        if (dr.compareTo(cr) != 0) {
            throw new DomainRuleViolation("GL_UNBALANCED", "The journal does not balance: debits " + dr + " ≠ credits " + cr + ".",
                    new DomainRuleViolation.Remedy("Make the debits equal the credits.", "Bursary"));
        }
        List<Map<String, Object>> lines = body.lines().stream().map(l -> {
            Map<String, Object> m = new java.util.LinkedHashMap<>();
            m.put("account", l.account());
            if (l.debit() != null && l.debit().signum() > 0) m.put("debit", l.debit());
            if (l.credit() != null && l.credit().signum() > 0) m.put("credit", l.credit());
            if (l.narration() != null) m.put("narration", l.narration());
            if (l.session() != null) m.put("session", l.session());
            return m;
        }).toList();
        UUID id;
        try {
            id = jdbc.sql("SELECT finance.gl_post(:d, :m, 'MANUAL', 'ADJUSTMENT', NULL, cast(:lines as jsonb))")
                    .param("d", body.date()).param("m", body.memo().trim())
                    .param("lines", json.writeValueAsString(lines), Types.VARCHAR)
                    .query(UUID.class).single();
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            throw new DomainRuleViolation("GL_ACCOUNT", "A line names an account that is not on the chart.",
                    new DomainRuleViolation.Remedy("Pick accounts from the chart.", "Bursary"));
        }
        return Map.of("id", id);
    }

    @PostMapping("/journals/{id}/reverse")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> reverse(@PathVariable UUID id, @Valid @RequestBody Reason body) {
        UUID nid = jdbc.sql("SELECT finance.gl_reverse(:id, :why)")
                .param("id", id).param("why", body.reason().trim()).query(UUID.class).single();
        return Map.of("id", nid);
    }
}
