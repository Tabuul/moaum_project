package ng.edu.moaum.portal.wallet;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import tools.jackson.databind.json.JsonMapper;

@Service
public class WalletService {

    private final WalletRepository repo;
    private final JsonMapper json = JsonMapper.builder().build();

    WalletService(WalletRepository repo) {
        this.repo = repo;
    }

    private String session(String asked) {
        return asked == null || asked.isBlank() ? repo.currentSession() : asked;
    }

    /* ── the student ── */

    @Transactional(readOnly = true)
    public Map<String, Object> mine(UUID student, String sessionAsked) {
        String session = session(sessionAsked);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("balance", repo.balance(student));
        out.put("statement", repo.statement(student));
        out.put("position", repo.position(student, session));
        out.put("status", repo.status(student).orElse(null));
        out.put("eligibility", repo.eligibility(student, session));
        out.put("withdrawal", repo.myWithdrawal(student).orElse(null));
        return out;
    }

    @Transactional
    public Map<String, Object> requestWithdrawal(UUID student, String sessionAsked, BigDecimal amount,
                                                 String bank, String accountNo, String accountName) {
        if (bank == null || bank.isBlank() || accountNo == null || accountNo.isBlank() || accountName == null || accountName.isBlank()) {
            throw new DomainRuleViolation("WAL_BANK", "A withdrawal names the bank, the account number and the account name.",
                    new DomainRuleViolation.Remedy("Enter your own bank account details.", "You"));
        }
        return repo.requestWithdrawal(student, session(sessionAsked), amount, bank.trim(), accountNo.trim(), accountName.trim());
    }

    @Transactional
    public Map<String, Object> apply(UUID student, String sessionAsked, BigDecimal amount) {
        String session = session(sessionAsked);
        String ref = repo.apply(student, session, amount);
        return Map.of("reference", ref, "session", session, "balance", repo.balance(student));
    }

    @Transactional
    public Map<String, Object> topup(UUID student, String sessionAsked, BigDecimal amount) {
        if (amount == null || amount.signum() <= 0) {
            throw new DomainRuleViolation("WAL_AMOUNT", "A top-up is for an amount.", new DomainRuleViolation.Remedy("In naira, above zero.", "You"));
        }
        return Map.of("reference", repo.topup(student, session(sessionAsked), amount), "amount", amount);
    }

    /* ── the Bursary ── */

    @Transactional(readOnly = true)
    public Map<String, Object> desk(String sessionAsked) {
        String session = session(sessionAsked);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("tiles", repo.tiles(session));
        out.put("batches", repo.batches(session));
        out.put("unmatched", repo.unmatched(session));
        out.put("status", repo.statusTiles(session));
        out.put("refusals", repo.refusals(session));
        out.put("sources", repo.sources());
        out.put("withdrawals", repo.withdrawalQueue(session));
        return out;
    }

    /* ── sources of funding (a setting) ── */

    @Transactional(readOnly = true)
    public Map<String, Object> sources() {
        return Map.of("sources", repo.sources());
    }

    @Transactional
    public Map<String, Object> upsertSource(String code, String name, String nature, String sponsor, String account,
                                            Boolean active, String note, Integer sort) {
        return repo.upsertSource(code, name, nature, sponsor, account, active == null || active, note, sort);
    }

    /* ── the report ── */

    @Transactional(readOnly = true)
    public Map<String, Object> report(String sessionAsked) {
        String session = session(sessionAsked);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("bySource", repo.fundingSummary(session));
        out.put("cashflow", repo.cashflow(session));
        return out;
    }

    /* ── withdrawals: the Bursary's queue ── */

    @Transactional
    public Map<String, Object> approveWithdrawal(UUID id) {
        repo.approveWithdrawal(id);
        return Map.of("id", id, "state", "APPROVED");
    }

    @Transactional
    public Map<String, Object> rejectWithdrawal(UUID id, String why) {
        if (why == null || why.isBlank()) {
            throw new DomainRuleViolation("WAL_WHY", "A rejection says why.", new DomainRuleViolation.Remedy("The student sees it.", "Bursary"));
        }
        repo.rejectWithdrawal(id, why.trim());
        return Map.of("id", id, "state", "REJECTED");
    }

    @Transactional
    public Map<String, Object> payWithdrawal(UUID id, String ref) {
        repo.payWithdrawal(id, ref);
        return Map.of("id", id, "state", "PAID");
    }

    @Transactional
    public Map<String, Object> load(String ref, String sessionAsked, LocalDate received, String note, List<Map<String, Object>> rows) {
        if (rows == null || rows.isEmpty()) {
            throw new DomainRuleViolation("WAL_ROWS", "A remittance is rows: matriculation number, name, amount.",
                    new DomainRuleViolation.Remedy("Read the Fund's file and send its rows.", "Bursary"));
        }
        return repo.load(ref, session(sessionAsked), received, note, json.writeValueAsString(rows));
    }

    @Transactional
    public Map<String, Object> creditWallet(String number, String sessionAsked, BigDecimal amount, String reason, String source) {
        if (amount == null || amount.signum() <= 0) {
            throw new DomainRuleViolation("WAL_AMOUNT", "A wallet credit is for an amount.", new DomainRuleViolation.Remedy("In naira, above zero.", "Bursary"));
        }
        if (reason == null || reason.isBlank()) {
            throw new DomainRuleViolation("WAL_REASON", "A wallet credit names its reason.", new DomainRuleViolation.Remedy("Say why; the student sees it on the statement.", "Bursary"));
        }
        UUID student = repo.studentByNumber(number == null ? "" : number.trim()).orElseThrow(() -> new DomainRuleViolation("WAL_NO_STUDENT",
                "No student carries the number " + number + ".", new DomainRuleViolation.Remedy("The number as the register holds it.", "Registry")));
        String session = session(sessionAsked);
        UUID entry = repo.creditWallet(student, session, amount, reason.trim(), source == null || source.isBlank() ? null : source.trim());
        return Map.of("entry", entry, "student", student, "session", session, "amount", amount, "balance", repo.balance(student));
    }

    /** the Bursary wipes one student's wallet to zero — every entry and withdrawal, so the balance starts afresh */
    @Transactional
    public Map<String, Object> resetWallet(String number, String reason) {
        if (reason == null || reason.isBlank()) {
            throw new DomainRuleViolation("WAL_RESET_WHY", "A wallet reset names its reason.", new DomainRuleViolation.Remedy("Say why the wallet is wiped; it is on the record.", "Bursary"));
        }
        UUID student = repo.studentByNumber(number == null ? "" : number.trim()).orElseThrow(() -> new DomainRuleViolation("WAL_NO_STUDENT",
                "No student carries the number " + number + ".", new DomainRuleViolation.Remedy("The number as the register holds it.", "Registry")));
        Map<String, Object> wiped = repo.resetWallet(student);
        return Map.of("student", student, "entries", wiped.getOrDefault("entries", 0), "withdrawals", wiped.getOrDefault("withdrawals", 0), "balance", repo.balance(student));
    }

    /** the Bursary (or the audit directorate) looks up any student's wallet ledger by number */
    @Transactional(readOnly = true)
    public Map<String, Object> studentLedger(String number, String sessionAsked) {
        UUID student = repo.studentByNumber(number == null ? "" : number.trim()).orElseThrow(() -> new DomainRuleViolation("WAL_NO_STUDENT",
                "No student carries the number " + number + ".", new DomainRuleViolation.Remedy("The number as the register holds it.", "Registry")));
        String session = session(sessionAsked);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", repo.studentHeader(student));
        out.put("session", session);
        out.put("balance", repo.balance(student));
        out.put("statement", repo.statement(student));
        out.put("position", repo.position(student, session));
        out.put("status", repo.status(student).orElse(null));
        return out;
    }

    @Transactional
    public Map<String, Object> match(UUID row, String number, String note) {
        UUID student = repo.studentByNumber(number == null ? "" : number.trim()).orElseThrow(() -> new DomainRuleViolation("WAL_NO_STUDENT",
                "No student carries the number " + number + ".", new DomainRuleViolation.Remedy("The number as the register holds it.", "Registry")));
        repo.match(row, student, note);
        return Map.of("row", row, "student", student, "state", "MATCHED");
    }

    @Transactional
    public Map<String, Object> reverse(UUID row, String why) {
        repo.reverse(row, why);
        return Map.of("row", row, "state", "REVERSED");
    }

    @Transactional
    public Map<String, Object> loadStatus(String sessionAsked, List<Map<String, Object>> rows) {
        if (rows == null || rows.isEmpty()) {
            throw new DomainRuleViolation("WAL_ROWS", "The Fund's list is rows: number, name, decision, reason.",
                    new DomainRuleViolation.Remedy("Read the Fund's file and send its rows.", "Bursary"));
        }
        return repo.loadStatus(session(sessionAsked), json.writeValueAsString(rows));
    }
}
