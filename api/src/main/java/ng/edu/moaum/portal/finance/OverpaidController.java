package ng.edu.moaum.portal.finance;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DeadlockRetry;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V781: Overpaid school fees reconciled from the Bursar's dashboard. The students of a session who paid above their charge, by cause,
 * with every hold on them; the wallet credit requested for many at once by one Bursary officer and approved by another; the refund
 * raised in bulk for the exact repeats; the figures the Bursar's and the Students Account Officer's dashboards read.
 *
 * <p>The list is read from a kept copy (finance.overpaid_snapshot, worked out by {@link OverpaidWatch} and by the desk's Refresh): it
 * costs seconds a session to work out and cannot sit behind every page. The state of each row — decisions, requests, refunds — is joined
 * live at every read, so an officer's act shows at once on every instance. <b>Money never reads the kept list</b>: every request,
 * approval, refund and carry reads the session live in the database (finance.overpaid_read), and both the list and the student's own
 * position must agree on the amount. The database holds every rule; the offices here keep a reader from asking for a write.
 *
 * <p>Nothing here applies money to fees: an approval credits each wallet (source OVERPAID) and tells the student, who applies it on
 * the Wallet page to the school fees they next owe, or asks there for a refund.
 *
 * <p>A refusal raised in SQL as {@code CODE: words} with a HINT reaches the client as {code, detail, remedy} through ProblemHandler
 * (23514 and its kin answer 422, 42501 answers 403).
 */
@RestController
@RequestMapping("/api/v1/finance/overpaid")
class OverpaidController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String REQUESTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";
    private static final String DECIDERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private static final Pattern SESSION = Pattern.compile("^[0-9]{4}/[0-9]{4}$");
    /** the timestamp an approval pass hands back as `since` (the pass's own, to the microsecond) */
    private static final Pattern SINCE = Pattern.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+(Z|[+-][0-9]{2}:?[0-9]{2})$");
    private static final Set<String> CAUSES = Set.of("PORTAL_TWICE", "OLD_AND_PORTAL", "OLD_TWICE", "PART_PAYMENTS", "ABOVE_FEE_LINE");
    /** the causes a repeat of the same money makes up: the only ones requested, or refunded, as a whole */
    private static final Set<String> PAID_TWICE = Set.of("PORTAL_TWICE", "OLD_AND_PORTAL", "OLD_TWICE");
    private static final Set<String> STATES = Set.of("UNDECIDED", "OVER_DECIDED", "CREDIT_REQUESTED", "CREDIT_RETURNED", "CREDITED", "CARRIED",
            "REFUND_RAISED", "REFUND_APPROVED", "REFUND_PAID", "REFUND_BY_HAND");
    private static final Set<String> CREDIT_STATUSES = Set.of("PENDING_BURSAR_APPROVAL", "RETURNED_FOR_CORRECTION", "CREDITED", "REJECTED", "WITHDRAWN");
    private static final int MOST_NAMED = 2000;

    /** the request for a wallet credit: the students named (or a paid-twice cause as a whole), why, and the two confirmations */
    public record Act(String session, List<UUID> students, @Size(max = 40) String cause, @NotBlank @Size(min = 10, max = 500) String reason,
                      Boolean confirmed, Boolean feeSetupChecked, Integer limit, @Size(max = 40) String batch) { }

    public record Decide(@Size(max = 40) String batch, List<UUID> ids, @NotBlank @Size(max = 20) String action, @Size(max = 500) String note, Integer limit, String since) { }

    public record Withdraw(@Size(max = 40) String batch, List<UUID> ids, @NotBlank @Size(min = 10, max = 500) String reason) { }

    public record Refresh(String session) { }

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;
    private final TransactionTemplate tx;

    OverpaidController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.json = json;
        this.tx = new TransactionTemplate(transactions);
    }

    /* ── the figures and the rows: reads of the kept list, never a refresh ── */

    /** the dashboards' and the desk's figures of a session; a session never worked out answers computed false with zeros */
    @GetMapping("/figures")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> figures(Authentication authentication, @RequestParam(required = false) String session) {
        return figuresOf(sessionOr(session), me(authentication));
    }

    /** a page of the session's kept list with the state of each student read live, filtered and ordered in the statement: the
     *  students who are decided above their excess first, then those not decided, those not held, the most left to decide */
    @GetMapping("/rows")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> rows(Authentication authentication, @RequestParam(required = false) String session, @RequestParam(required = false) String cause,
                             @RequestParam(required = false) String state, @RequestParam(required = false) Boolean held, @RequestParam(required = false) Boolean bulk,
                             @RequestParam(required = false) String faculty, @RequestParam(required = false) String department, @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "100") int size,
                             @RequestParam(defaultValue = "false") boolean export) {
        String ses = sessionOr(session);
        String c = blank(cause);
        if (c != null && !CAUSES.contains(c.toUpperCase())) {
            throw new DomainRuleViolation("OVERPAID_FILTER", c + " is not a cause of an overpayment.", new DomainRuleViolation.Remedy("Choose one of the five causes.", "You"));
        }
        String st = blank(state);
        if (st != null && !STATES.contains(st.toUpperCase())) {
            throw new DomainRuleViolation("OVERPAID_FILTER", st + " is not a state of an overpaid student.", new DomainRuleViolation.Remedy("Choose one of the states the desk lists.", "You"));
        }
        String term = blank(q);
        if (term != null) {
            term = term.toUpperCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
        }
        int sz = Math.max(1, Math.min(size, export ? 100_000 : 500));
        int pg = Math.max(0, Math.min(page, 1_000_000));
        String text = jdbc.sql("""
                WITH d AS MATERIALIZED (
                    SELECT x.* FROM finance.overpaid_desk(:s, :me) x
                     WHERE (CAST(:cause AS text) IS NULL OR x.cause = CAST(:cause AS text))
                       AND (CAST(:state AS text) IS NULL OR x.state = CAST(:state AS text))
                       AND (CAST(:held AS boolean) IS NULL OR (cardinality(x.holds) > 0) = CAST(:held AS boolean))
                       AND (CAST(:bulk AS boolean) IS NULL OR x.bulk = CAST(:bulk AS boolean))
                       AND (CAST(:faculty AS text) IS NULL OR x.faculty_code = CAST(:faculty AS text))
                       AND (CAST(:department AS text) IS NULL OR x.dept_code = CAST(:department AS text))
                       AND (CAST(:q AS text) IS NULL OR upper(x.number) LIKE '%' || CAST(:q AS text) || '%' OR upper(x.name) LIKE '%' || CAST(:q AS text) || '%')),
                pg AS (
                    SELECT d.*, row_number() OVER (ORDER BY (d.state = 'OVER_DECIDED') DESC, (d.state = 'UNDECIDED') DESC, (cardinality(d.holds) = 0) DESC,
                                                           d.remaining DESC, d.number, d.student_id) AS rn
                      FROM d ORDER BY rn LIMIT :n OFFSET :o),
                run AS (SELECT r.refreshed_at FROM finance.overpaid_snapshot_run r WHERE r.session = :s)
                SELECT jsonb_strip_nulls(jsonb_build_object(
                    'session', CAST(:s AS text),
                    'refreshedAt', (SELECT r.refreshed_at FROM run r),
                    'computed', EXISTS (SELECT 1 FROM run),
                    'total', (SELECT count(*) FROM d),
                    'rows', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                            'student_id', p.student_id, 'number', p.number, 'name', p.name, 'programme_code', p.programme_code, 'dept_code', p.dept_code,
                            'faculty_code', p.faculty_code, 'level', p.level, 'cohort_level', p.cohort_level, 'status', p.status,
                            'due', p.due, 'paid', p.paid, 'excess', p.excess, 'decided', p.decided, 'refunded_by_hand', nullif(p.refunded_by_hand, 0),
                            'remaining', p.remaining, 'over_decided', nullif(p.over_decided, 0), 'cause', p.cause, 'bulk', p.bulk,
                            'repeat_amount', p.repeat_amount, 'n_payments', p.n_payments, 'payments', p.payments, 'holds', to_jsonb(p.holds),
                            'refund_only', p.refund_only, 'suggested', p.suggested, 'state', p.state, 'decisions', p.decisions,
                            'request', CASE WHEN p.request_id IS NULL THEN NULL
                                            ELSE jsonb_build_object('id', p.request_id, 'ref', p.request_ref, 'amount', p.request_amount, 'status', p.request_status,
                                                                    'batch', p.request_batch, 'by', p.request_by, 'at', p.request_at, 'mine', p.request_mine,
                                                                    'skip', p.request_skip) END)) ORDER BY p.rn) FROM pg p), '[]'::jsonb),
                    'faculties', coalesce((SELECT jsonb_agg(jsonb_build_object('code', f.code, 'name', f.name) ORDER BY f.name) FROM ref.faculty f
                                            WHERE f.code IN (SELECT n.faculty_code FROM finance.overpaid_snapshot n WHERE n.session = :s)), '[]'::jsonb),
                    'departments', coalesce((SELECT jsonb_agg(jsonb_build_object('code', dp.code, 'name', dp.name, 'faculty', dp.faculty_code) ORDER BY dp.name) FROM ref.department dp
                                              WHERE dp.code IN (SELECT n.dept_code FROM finance.overpaid_snapshot n WHERE n.session = :s)), '[]'::jsonb)))::text
                """).param("s", ses).param("me", me(authentication))
                .param("cause", c == null ? null : c.toUpperCase(), Types.VARCHAR).param("state", st == null ? null : st.toUpperCase(), Types.VARCHAR)
                .param("held", held, Types.BOOLEAN).param("bulk", bulk, Types.BOOLEAN)
                .param("faculty", blank(faculty), Types.VARCHAR).param("department", blank(department), Types.VARCHAR).param("q", term, Types.VARCHAR)
                .param("n", sz).param("o", (long) pg * sz).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(jsonOf(text));
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    /* ── the kept list worked out again ── */

    /** the desk's Refresh: the session's list worked out now (another refresh running leaves its answer standing); answers the figures */
    @PostMapping("/refresh")
    @PreAuthorize(REQUESTERS)
    Map<String, Object> refresh(Authentication authentication, @RequestBody(required = false) Refresh body) {
        String ses = sessionOr(body == null ? null : body.session());
        UUID me = me(authentication);
        return DeadlockRetry.inTransaction(tx, () -> {
            jdbc.sql("SELECT * FROM finance.overpaid_refresh(:s)").param("s", ses).query().singleRow();
            return figuresOf(ses, me);
        });
    }

    /* ── the wallet credit, in bulk, by two officers ── */

    /** one Bursary officer's request for the wallet credit of many students: one request each, under one batch number, the whole
     *  undecided excess of each; nothing is credited here — another officer approves */
    @PostMapping("/credits/request")
    @PreAuthorize(REQUESTERS)
    Map<String, Object> request(@Valid @RequestBody Act body) {
        confirmed(body);
        String[] students = students(body.students());
        int limit = body.limit() == null ? 1000 : Math.max(1, Math.min(body.limit(), MOST_NAMED));
        String ses = sessionNamed(body.session());
        String cause = blank(body.cause());   // the cause as the refund reads it: upper-case, so one spelling is accepted by both
        return DeadlockRetry.inTransaction(tx, () -> {
            Map<String, Object> row = jdbc.sql("""
                    SELECT batch_ref, requested, amount, skipped, skipped_why::text AS skipped_why, remaining
                      FROM finance.overpaid_credits_request(:s, CAST(:w AS uuid[]), :c, :r, :n, :b, :f)
                    """).param("s", ses).param("w", students, Types.ARRAY).param("c", cause == null ? null : cause.toUpperCase(), Types.VARCHAR).param("r", body.reason().trim())
                    .param("n", limit).param("b", blank(body.batch()), Types.VARCHAR).param("f", Boolean.TRUE.equals(body.feeSetupChecked())).query().singleRow();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("batch", row.get("batch_ref"));
            out.put("requested", row.get("requested"));
            out.put("amount", row.get("amount"));
            out.put("skipped", row.get("skipped"));
            out.put("skippedWhy", jsonOf(String.valueOf(row.get("skipped_why")), Object.class));
            out.put("remaining", row.get("remaining"));
            return out;
        });
    }

    /** the requests made on this desk, a page at a time (a batch above one page is read page by page), each with whether it is the
     *  caller's own; status one of the request statuses (default: waiting for the Bursar) or ALL */
    @GetMapping("/credits")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> credits(Authentication authentication, @RequestParam(required = false) String session, @RequestParam(required = false) String status,
                                      @RequestParam(required = false) String batch, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "200") int size) {
        String ses = sessionOr(session);
        String st = blank(status) == null ? "PENDING_BURSAR_APPROVAL" : status.trim().toUpperCase();
        if (!"ALL".equals(st) && !CREDIT_STATUSES.contains(st)) {
            throw new DomainRuleViolation("OVERPAID_FILTER", st + " is not a status of a credit request.", new DomainRuleViolation.Remedy("Choose a status the desk lists, or ALL.", "You"));
        }
        int sz = Math.max(1, Math.min(size, 500));
        return jdbc.sql("""
                SELECT r.*, (r.initiated_by_id = :me) AS mine
                  FROM finance.legacy_credit_rows(:st, :s, NULL, NULL, NULL, :n, NULL, NULL, :b, true, :o) r
                """).param("st", "ALL".equals(st) ? null : st, Types.VARCHAR).param("s", ses).param("me", me(authentication)).param("n", sz)
                .param("b", blank(batch), Types.VARCHAR).param("o", Math.max(0, Math.min(page, 1_000_000)) * sz).query().listOfRows();
    }

    /** another Bursary officer approves (each wallet credited, the student told), rejects or returns for correction the requests of a
     *  batch or the ones named, a call at a time; what a call cannot credit is left with its code and words and not tried again in the
     *  pass (`since`, handed back on each call), so `remaining` reaches 0. Nothing is applied to fees by this call. */
    @PostMapping("/credits/decide")
    @PreAuthorize(DECIDERS)
    Map<String, Object> decide(@Valid @RequestBody Decide body) {
        String[] ids = ids(body.ids(), "requests");
        int limit = body.limit() == null ? 200 : Math.max(1, Math.min(body.limit(), 500));
        String since = blank(body.since());
        if (since != null && !SINCE.matcher(since).matches()) {
            throw new DomainRuleViolation("OVERPAID_SINCE", "The moment the pass began is not a timestamp.", new DomainRuleViolation.Remedy("Pass back the `since` of the first answer, as it was sent.", "You"));
        }
        return DeadlockRetry.inTransaction(tx, () -> {
            Map<String, Object> row = jdbc.sql("""
                    SELECT batch_ref, to_char(since AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS since, credited, amount, rejected, returned,
                           skipped, skipped_why::text AS skipped_why, remaining
                      FROM finance.overpaid_credits_decide(CAST(:w AS uuid[]), :b, :a, :n, :l, CAST(:since AS timestamptz))
                    """).param("w", ids, Types.ARRAY).param("b", blank(body.batch()), Types.VARCHAR).param("a", body.action().trim())
                    .param("n", blank(body.note()), Types.VARCHAR).param("l", limit).param("since", since, Types.VARCHAR).query().singleRow();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("batch", row.get("batch_ref"));
            out.put("since", row.get("since"));
            out.put("credited", row.get("credited"));
            out.put("amount", row.get("amount"));
            out.put("rejected", row.get("rejected"));
            out.put("returned", row.get("returned"));
            out.put("skipped", row.get("skipped"));
            out.put("skippedWhy", jsonOf(String.valueOf(row.get("skipped_why")), Object.class));
            out.put("remaining", row.get("remaining"));
            return out;
        });
    }

    /** a mistaken request undone in one act, by whoever requested it (or any Bursary officer): the open requests of a batch, or the
     *  ones named, withdrawn with a reason */
    @PostMapping("/credits/withdraw")
    @PreAuthorize(REQUESTERS)
    Map<String, Object> withdraw(@Valid @RequestBody Withdraw body) {
        String[] ids = ids(body.ids(), "requests");
        return DeadlockRetry.inTransaction(tx, () -> {
            Integer n = jdbc.sql("SELECT finance.overpaid_credits_withdraw(:b, CAST(:w AS uuid[]), :r)").param("b", blank(body.batch()), Types.VARCHAR)
                    .param("w", ids, Types.ARRAY).param("r", body.reason().trim()).query(Integer.class).single();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("withdrawn", n);
            return out;
        });
    }

    /* ── the refund, in bulk, for the exact repeats ── */

    /** refunds raised (one a student, on the Refunds & Credits desk) for the students named, or for a paid-twice cause as a whole — the
     *  exact repeats only; any other student is decided one at a time with the fee setup confirmed; every hold stops it */
    @PostMapping("/refund")
    @PreAuthorize(DECIDERS)
    Map<String, Object> refund(@Valid @RequestBody Act body) {
        confirmed(body);
        String[] students = students(body.students());
        String cause = blank(body.cause());
        if (students.length == 0 && (cause == null || !PAID_TWICE.contains(cause.toUpperCase()))) {
            throw new DomainRuleViolation("OVERPAID_BULK_WHO", "Name the students, or a paid-twice cause.",
                    new DomainRuleViolation.Remedy("Tick the students, or filter by a paid-twice cause and refund all of it.", "You"));
        }
        int limit = body.limit() == null ? 2000 : Math.max(1, Math.min(body.limit(), 5000));
        String ses = sessionNamed(body.session());
        return DeadlockRetry.inTransaction(tx, () -> {
            Map<String, Object> row = jdbc.sql("SELECT * FROM finance.decide_overpayments(:s, 'REFUND', CAST(:w AS uuid[]), :r, :n, :c, :f)")
                    .param("s", ses).param("w", students, Types.ARRAY).param("r", body.reason().trim()).param("n", limit)
                    .param("c", cause == null ? null : cause.toUpperCase(), Types.VARCHAR).param("f", Boolean.TRUE.equals(body.feeSetupChecked())).query().singleRow();
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("refunds", row.get("refunds"));
            out.put("held", row.get("held"));
            out.put("apart", row.get("apart"));
            out.put("requested", row.get("requested"));
            out.put("uncertain", row.get("uncertain"));
            out.put("unchecked", row.get("unchecked"));
            out.put("remaining", row.get("remaining"));
            return out;
        });
    }

    /* ── helpers ── */

    private Map<String, Object> figuresOf(String session, UUID me) {
        return jsonOf(jdbc.sql("SELECT finance.overpaid_figures(:s, :me)::text").param("s", session).param("me", me).query(String.class).single());
    }

    private static UUID me(Authentication authentication) {
        return UUID.fromString(authentication.getName());
    }

    private Map<String, Object> jsonOf(String text) {
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    private <T> T jsonOf(String text, Class<T> type) {
        return json.readValue(text, type);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    /** the session asked for (a query), else the calendar's current one */
    private String sessionOr(String session) {
        String s = blank(session);
        if (s == null) {
            return jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional()
                    .orElseThrow(() -> new DomainRuleViolation("OVERPAID_SESSION", "No session is current on the academic calendar.", new DomainRuleViolation.Remedy("Name the session.", "You")));
        }
        return sessionNamed(s);
    }

    /** a session written as 2025/2026 (whether the calendar has it is the database's to say) */
    private static String sessionNamed(String session) {
        String s = blank(session);
        if (s == null || !SESSION.matcher(s).matches()) {
            throw new DomainRuleViolation("OVERPAID_SESSION", "Name the session as 2025/2026.", new DomainRuleViolation.Remedy("Choose a session of the academic calendar.", "You"));
        }
        return s;
    }

    /** the confirmation the payments behind each excess were looked at: never a blind one-click */
    private static void confirmed(Act body) {
        if (!Boolean.TRUE.equals(body.confirmed())) {
            throw new DomainRuleViolation("OVERPAID_CONFIRM", "Confirm that the payments behind each excess were looked at.", new DomainRuleViolation.Remedy("Tick the confirmation.", "You"));
        }
    }

    private static String[] students(List<UUID> students) {
        return ids(students, "students");
    }

    private static String[] ids(List<UUID> list, String what) {
        if (list == null || list.isEmpty()) {
            return new String[0];
        }
        if (list.size() > MOST_NAMED) {
            throw new DomainRuleViolation("OVERPAID_TOO_MANY", "Name at most 2,000 " + what + " in one request.",
                    new DomainRuleViolation.Remedy("Filter by a paid-twice cause and use Credit all, or select fewer.", "You"));
        }
        return list.stream().map(UUID::toString).toArray(String[]::new);
    }
}
