package ng.edu.moaum.portal.transfers;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Inter-departmental transfer (V070): the student's application and the office's queue. V727: the fee is read against every
 *  verified payment, this portal's and the old portal's (people.transfer_entitlement): any payment lets the desks act, the
 *  Academic Office's final approval waits for the whole fee. */
@RestController
class TransferController {

    /** V727: the Bursary and the Students Account Officer read the queue (what is owed), never act on it */
    /** V734: a Dean reads the applications from or into the faculty (a College Dean acts on them; another Dean reads only) */
    private static final String READERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_bursar','OFFICE_studentaccounts')";
    private static final String SAIC = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_super')";
    private static final String SENATE = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_vc','OFFICE_dvc','OFFICE_super')";
    private static final String OFFICERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final String EFFECT = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    /** the offices in the approval chain: the department HODs (V734: and, at a department of a College, the Dean of its faculty), the
     *  Registrar and the Academic office */
    private static final String APPROVERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_super')";

    private final JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    TransferController(JdbcClient jdbc, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    private static String actingOffice() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
    }

    /** the human-readable stage: which desk the application is sitting with (or its terminal state). V727: read from what is paid —
     *  APPLIED is with the current department once anything is paid, else awaiting payment; at the Academic office (and once
     *  approved by Senate) the balance still owed is named. A closed application (declined, not recommended, withdrawn: band CLOSED,
     *  nothing owed) is named by its state alone, never by a payment. */
    static String stageLabel(String state, BigDecimal paid, BigDecimal balance) {
        boolean anyPaid = paid != null && paid.signum() > 0;
        boolean owing = balance != null && balance.signum() > 0;
        return switch (state == null ? "" : state) {
            case "APPLIED" -> anyPaid ? "With current department" : "Awaiting payment";
            case "FROM_OK" -> "With new department";
            case "TO_OK" -> "With Registrar";
            case "REG_OK" -> owing ? "With Academic office — " + naira(balance) + " outstanding" : "With Academic office";
            case "APPROVED" -> owing ? "Approved — " + naira(balance) + " outstanding" : "Approved — awaiting effect";
            case "EFFECTED" -> "Completed";
            case "DECLINED" -> "Declined";
            case "WITHDRAWN" -> "Withdrawn";
            case "RECOMMENDED" -> "Recommended";
            case "NOT_RECOMMENDED" -> "Not recommended";
            default -> state;
        };
    }

    /** naira with comma thousands separators whatever the server's locale: ₦12,500, or ₦12,500.50 when there are kobo */
    static String naira(BigDecimal amount) {
        if (amount == null) {
            return "₦0";
        }
        BigDecimal a = amount.stripTrailingZeros();
        return a.scale() <= 0 ? String.format(java.util.Locale.ROOT, "₦%,d", a.toBigInteger()) : String.format(java.util.Locale.ROOT, "₦%,.2f", amount);
    }

    static BigDecimal money(Object o) {
        return o == null ? null : o instanceof BigDecimal b ? b : new BigDecimal(String.valueOf(o));
    }

    /** whether the acting office (and department, for an HOD) holds the application at this stage. V727: the current department acts
     *  once any verified payment stands (the University's decision of 12 November 2026); the balance at the Academic office's desk is
     *  the database's to refuse (TRANSFER_FEE_OUTSTANDING, TRANSFER_PAYMENT_PENDING), with the figures. */
    private static boolean mayApprove(String office, String myDept, String myFaculty, String state, Sides s, boolean paid) {
        boolean isSuper = "super".equals(office);
        return switch (state == null ? "" : state) {
            case "APPLIED" -> paid && (isSuper || department(office, myDept, myFaculty, s.fromDept(), s.fromFaculty(), s.fromCollege()));
            case "FROM_OK" -> isSuper || department(office, myDept, myFaculty, s.toDept(), s.toFaculty(), s.toCollege());
            case "TO_OK" -> isSuper || "registrar".equals(office) || "dregistrar".equals(office);
            case "REG_OK" -> isSuper || "academic".equals(office);
            default -> false;
        };
    }

    /** V734: a department desk is the department's HOD's, and — for a department of a College — its faculty's Dean's too (the University's
     *  master prompt of 12 November 2026: the College Deans serve as the approving authorities of their Colleges); a Dean of a faculty in
     *  no College acts at no desk */
    static boolean department(String office, String myDept, String myFaculty, String dept, String faculty, String college) {
        if ("hod".equals(office)) {
            return dept != null && dept.equalsIgnoreCase(myDept);
        }
        if ("dean".equals(office)) {
            return college != null && faculty != null && faculty.equalsIgnoreCase(myFaculty);
        }
        return false;
    }

    /** V734: an application's two sides — each its department, its faculty and the College the faculty is in (people.transfer_unit) */
    record Sides(String fromDept, String toDept, String fromFaculty, String toFaculty, String fromCollege, String toCollege) {
        static Sides of(Map<String, Object> r) {
            return new Sides(str(r.get("from_dept")), str(r.get("to_dept")), str(r.get("from_faculty")), str(r.get("to_faculty")),
                    str(r.get("from_college")), str(r.get("to_college")));
        }
    }

    /** V734: whether a Dean reads this application — from or into the Dean's faculty */
    private static boolean inFaculty(Map<String, Object> r, String myFaculty) {
        return myFaculty != null && (myFaculty.equalsIgnoreCase(str(r.get("from_faculty"))) || myFaculty.equalsIgnoreCase(str(r.get("to_faculty"))));
    }

    /** V727: the final approval may be given — as people.transfer_fee_settled_or_refuse decides it: the fee stated
     *  (TRANSFER_FEE_NOT_STATED) and nothing owed (TRANSFER_FEE_OUTSTANDING); a payment awaiting the bank refuses it only while a
     *  balance is owed (TRANSFER_PAYMENT_PENDING), so once nothing is owed it no longer matters */
    private static boolean settled(Object feeDue, Object balance) {
        BigDecimal b = money(balance);
        return feeDue != null && b != null && b.signum() <= 0;
    }

    /** V686: the applications the old portal approved, freed from the queue together */
    public record OldPortal(@jakarta.validation.constraints.NotEmpty @Size(max = 2000) List<@jakarta.validation.constraints.NotNull UUID> applications,
                            @NotBlank @Size(max = 600) String reason, @Size(max = 80) String reference, @Size(max = 10) String approvedOn) {
    }

    public record Apply(@NotBlank @Size(max = 6) String toProgramme, @NotBlank @Size(max = 600) String reason, Integer utme) {
    }

    public record Record(@NotBlank @Size(max = 40) String number, @NotBlank @Size(max = 6) String toProgramme, @NotBlank @Size(max = 600) String reason, Integer utme) {
    }

    public record Review(boolean recommend, Integer level, @Size(max = 600) String note) {
    }

    public record Senate(boolean approve, @Size(max = 600) String note) {
    }

    public record Why(@NotBlank @Size(max = 600) String why) {
    }

    /** V734: an approval may carry the approver's comment (kept in the history), and names the state the approver read, so a second press
     *  — or a desk that moved meanwhile — never approves the next stage */
    public record Approve(@Size(max = 600) String note, @Size(max = 20) String expectedState) {
    }

    private static UUID me(Authentication auth) {
        return AuditContextHolder.current().map(c -> c.actorId()).orElseGet(() -> {
            if (auth == null || auth.getName() == null) {
                return null;
            }
            try {
                return UUID.fromString(auth.getName());
            } catch (IllegalArgumentException notUuid) {
                return null;
            }
        });
    }

    private UUID studentByNumber(String number) {
        return jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) OR upper(admission_no) = upper(:n) LIMIT 1")
                .param("n", number == null ? "" : number.trim()).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("student", number));
    }

    /* ── the student's side ── */

    @GetMapping("/api/v1/me/transfer")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth) {
        UUID student = me(auth);
        Map<String, Object> me = jdbc.sql("""
                SELECT s.surname || ', ' || s.other_names AS name, s.matric_no, s.current_level, s.entry_mode, s.status,
                       p.name AS programme, p.code AS programme_code
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = :s
                """).param("s", student).query().singleRow();
        List<Map<String, Object>> apps = jdbc.sql("""
                SELECT * FROM people.transfer_list(NULL, NULL) WHERE student_id = :s ORDER BY applied_at DESC
                """).param("s", student).query().listOfRows();
        List<Map<String, Object>> programmes = jdbc.sql("""
                SELECT p.code, p.name, f.name AS faculty FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE NOT p.archived AND p.code <> (SELECT programme_code FROM people.student WHERE id = :s) ORDER BY f.name, p.name
                """).param("s", student).query().listOfRows();
        BigDecimal fee = jdbc.sql("SELECT people.transfer_fee()").query(BigDecimal.class).optional().orElse(null);
        java.util.Map<String, Object> out = new java.util.HashMap<>();
        out.put("student", me);
        out.put("applications", apps);
        out.put("programmes", programmes);
        out.put("fee", fee);   // null until the Bursary sets the transfer fee
        // V727: the application the payment panel reads — the live one, else the newest effected or declined
        UUID app = jdbc.sql("""
                SELECT t.id FROM people.transfer_application t
                 WHERE t.student_id = :s AND (t.state = ANY (people.transfer_live_states()) OR t.state IN ('EFFECTED', 'DECLINED'))
                 ORDER BY (t.state = ANY (people.transfer_live_states())) DESC, t.applied_at DESC LIMIT 1
                """).param("s", student).query(UUID.class).optional().orElse(null);
        out.put("payment", app == null ? null : payment(app));
        out.put("paymentsMade", app == null ? List.of() : paymentsMade(app));
        out.put("credit", credit(student));
        out.put("legacy", app == null ? null : legacy(app));
        return out;
    }

    /** V727: what the application owes and what is paid (people.transfer_entitlement), and the next thing the student does: pay
     *  the whole fee, pay the balance, complete the payment awaiting the bank, or wait for the desks — nothing once the application
     *  is no longer live (effected, or closed: band CLOSED, nothing owed) */
    private Map<String, Object> payment(UUID app) {
        Map<String, Object> e = jdbc.sql("""
                SELECT t.id, t.state, t.state = ANY (people.transfer_live_states()) AS live, e.*
                  FROM people.transfer_application t CROSS JOIN LATERAL people.transfer_entitlement(t.id) e WHERE t.id = :a
                """).param("a", app).query().singleRow();
        String state = str(e.get("state"));
        BigDecimal paid = money(e.get("paid_total")), balance = money(e.get("balance"));
        String next;
        if (!Boolean.TRUE.equals(e.get("live")) || "CLOSED".equals(e.get("band"))) {
            next = "NONE";
        } else if (balance == null || balance.signum() <= 0) {
            next = "AWAIT_APPROVAL";   // paid in full — or no fee stated to pay yet, which the band says
        } else if (Boolean.TRUE.equals(e.get("pending"))) {
            next = "COMPLETE_PAYMENT";
        } else if (paid == null || paid.signum() <= 0) {
            next = "PAY_NOW";
        } else {
            next = "PAY_BALANCE";
        }
        Map<String, Object> m = new java.util.LinkedHashMap<>();
        m.put("applicationId", e.get("id"));
        m.put("state", state);
        m.put("stageLabel", stageLabel(state, paid, balance));
        m.put("feeDue", e.get("fee_due"));
        m.put("portalPaid", e.get("portal_paid"));
        m.put("oldPortalPaid", e.get("old_portal_paid"));
        m.put("paidTotal", e.get("paid_total"));
        m.put("balance", e.get("balance"));
        m.put("excess", e.get("excess"));
        m.put("payments", e.get("payments"));
        m.put("settled", e.get("settled"));
        m.put("pending", e.get("pending"));
        m.put("openReference", e.get("open_reference"));
        m.put("openAmount", e.get("open_amount"));
        m.put("openExpiresAt", e.get("open_expires_at"));
        m.put("band", e.get("band"));
        m.put("nextAction", next);
        return m;
    }

    /** V727: the payments counted toward the application — the old portal's (with their reconciliation status) and this portal's,
     *  confirmed or awaiting the bank (an expired or archived reference is none) */
    private List<Map<String, Object>> paymentsMade(UUID app) {
        return jdbc.sql("""
                SELECT tp.source, r.reference,
                       CASE WHEN tp.source = 'OLD_PORTAL'
                            THEN coalesce(l.payref, (SELECT lp.payref FROM finance.legacy_payref lp WHERE lp.reference = r.reference ORDER BY lp.recorded_at LIMIT 1)) END AS payref,
                       CASE WHEN tp.source = 'OLD_PORTAL' THEN coalesce(l.item, r.purpose) ELSE r.purpose END AS item,
                       r.amount,
                       CASE WHEN tp.source = 'OLD_PORTAL' THEN coalesce(l.paid_on, (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date)
                            ELSE (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date END AS paid_on,
                       CASE WHEN tp.source = 'OLD_PORTAL' THEN coalesce(l.status, 'LINKED')
                            WHEN r.confirmed_at IS NOT NULL THEN 'CONFIRMED' ELSE 'AWAITING_BANK' END AS status
                  FROM people.transfer_payment tp
                  JOIN finance.payment_reference r ON r.id = tp.payment_id
                  LEFT JOIN people.legacy_transfer_payment l ON l.payment_id = tp.payment_id
                 WHERE tp.application_id = :a AND r.archived_at IS NULL
                   AND (r.confirmed_at IS NOT NULL OR (tp.source = 'PORTAL' AND r.expires_at > now()))
                 ORDER BY coalesce(r.confirmed_at, r.generated_at)
                """).param("a", app).query().listOfRows().stream().map(r -> {
                    Map<String, Object> m = new java.util.LinkedHashMap<>();
                    m.put("source", r.get("source"));
                    m.put("reference", r.get("reference"));
                    m.put("payref", r.get("payref"));
                    m.put("item", r.get("item"));
                    m.put("amount", r.get("amount"));
                    m.put("paidOn", r.get("paid_on"));
                    m.put("status", r.get("status"));
                    return m;
                }).toList();
    }

    /** V727: the student's old-portal transfer payments that await an application (they count once one is made), or null */
    private Map<String, Object> credit(UUID student) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT l.payref, l.item, l.amount, l.paid_on
                  FROM people.legacy_transfer_payment l JOIN finance.payment_reference r ON r.id = l.payment_id AND r.archived_at IS NULL
                 WHERE l.student_id = :s AND l.status = 'AWAITING_APPLICATION'
                 ORDER BY l.paid_on, l.payref
                """).param("s", student).query().listOfRows();
        if (rows.isEmpty()) {
            return null;
        }
        BigDecimal total = BigDecimal.ZERO;
        List<Map<String, Object>> payments = new java.util.ArrayList<>();
        for (Map<String, Object> r : rows) {
            total = total.add(money(r.get("amount")));
            Map<String, Object> m = new java.util.LinkedHashMap<>();
            m.put("payref", r.get("payref"));
            m.put("item", r.get("item"));
            m.put("amount", r.get("amount"));
            m.put("paidOn", r.get("paid_on"));
            payments.add(m);
        }
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("total", total);
        out.put("payments", payments);
        return out;
    }

    /** V727: the old portal's record of the application, as its export gave it, or null */
    private Map<String, Object> legacy(UUID app) {
        return jdbc.sql("SELECT legacy_ref, applied_on, stage, approvals, documents, payrefs FROM people.transfer_legacy WHERE application_id = :a")
                .param("a", app).query().listOfRows().stream().findFirst().map(r -> {
                    Map<String, Object> m = new java.util.LinkedHashMap<>();
                    m.put("legacyRef", r.get("legacy_ref"));
                    m.put("appliedOn", r.get("applied_on"));
                    m.put("stage", r.get("stage"));
                    m.put("approvals", r.get("approvals"));
                    m.put("documents", r.get("documents"));
                    m.put("payrefs", texts(r.get("payrefs")));
                    return m;
                }).orElse(null);
    }

    /** a text[] column as a list */
    static List<String> texts(Object v) {
        try {
            if (v instanceof java.sql.Array a) {
                Object[] items = (Object[]) a.getArray();
                return java.util.Arrays.stream(items).map(x -> x == null ? null : String.valueOf(x)).toList();
            }
        } catch (java.sql.SQLException e) {
            throw new IllegalStateException("reading a text[] column", e);
        }
        return v instanceof String[] arr ? List.of(arr) : List.of();
    }

    @PostMapping("/api/v1/me/transfer")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> apply(Authentication auth, @Valid @RequestBody Apply body) {
        UUID id = jdbc.sql("SELECT people.apply_transfer(:s, :p, :r, :u)")
                .param("s", me(auth)).param("p", body.toProgramme()).param("r", body.reason()).param("u", body.utme(), Types.INTEGER)
                .query(UUID.class).single();
        tellDesk(id);   // V734: the current department (its HOD, or the College's Dean) told it awaits them
        return Map.of("id", id, "state", "APPLIED");
    }

    @PostMapping("/api/v1/me/transfer/{id}/fee")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> myFee(Authentication auth, @PathVariable UUID id) {
        boolean mine = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.transfer_application WHERE id = :id AND student_id = :s)")
                .param("id", id).param("s", me(auth)).query(Boolean.class).single());
        if (!mine) {
            throw new NotFound("transfer application", id.toString());
        }
        // V727: the reference for the balance (the whole fee before anything is paid) — the one still open for it again, never a second
        String ref = jdbc.sql("SELECT people.transfer_fee_reference(:id)").param("id", id).query(String.class).single();
        BigDecimal amount = jdbc.sql("SELECT amount FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(BigDecimal.class).single();
        return Map.of("reference", ref, "amount", amount);
    }

    /* ── the office's side ── */

    @GetMapping("/api/v1/transfers")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session, @RequestParam(required = false) String state) {
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM people.transfer_list(:s, :st)")
                .param("s", session == null || session.isBlank() ? null : session, Types.VARCHAR)
                .param("st", state == null || state.isBlank() ? null : state.toUpperCase(), Types.VARCHAR)
                .query().listOfRows();
        String office = actingOffice();
        String myDept = scope.actingDept();
        String myFaculty = "dean".equals(office) ? scope.actingFaculty() : null;
        if ("dean".equals(office)) {
            // V734: a Dean reads the applications from or into the faculty, no other
            rows = new java.util.ArrayList<>(rows.stream().filter(r -> inFaculty(r, myFaculty)).toList());
        }
        // V669, V686: a withdrawn application whose transfer the old portal approved, restored — named by the restoration
        Map<String, String> restored = new java.util.HashMap<>();
        for (Map<String, Object> x : jdbc.sql("""
                SELECT DISTINCT ON (t.id) t.id::text AS id, coalesce(pt.reference, sw.swap_ref, 'recorded') AS ref
                  FROM people.transfer_application t
                  JOIN people.prior_transfer pt ON pt.student_id = t.student_id AND pt.to_programme = t.to_programme_code
                  LEFT JOIN people.programme_swap sw ON sw.id = pt.swap_id
                 WHERE t.state = 'WITHDRAWN'
                 ORDER BY t.id, pt.recorded_at DESC
                """).query().listOfRows()) {
            restored.put(String.valueOf(x.get("id")), String.valueOf(x.get("ref")));
        }
        for (Map<String, Object> r : rows) {
            String st = String.valueOf(r.get("state"));
            // V727: paid is any verified payment (this portal's or the old portal's); the final approval needs the fee stated and nothing
            // owed — as the database decides it (people.transfer_fee_settled_or_refuse)
            BigDecimal paidTotal = money(r.get("paid_total"));
            boolean paid = paidTotal != null && paidTotal.signum() > 0;
            boolean holds = mayApprove(office, myDept, myFaculty, st, Sides.of(r), paid);
            r.put("stageLabel", stageLabel(st, paidTotal, money(r.get("balance"))));
            r.put("canApprove", holds && (!"REG_OK".equals(st) || settled(r.get("fee_due"), r.get("balance"))));
            // the desk holding the application may decline it whatever is paid
            r.put("canDecline", mayApprove(office, myDept, myFaculty, st, Sides.of(r), true));
            r.put("restoredRef", restored.get(String.valueOf(r.get("id"))));
        }
        return Map.of("rows", rows);
    }

    private static String str(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    /** V734: one application for its review — the student's academic profile, each side's department, faculty and College, the reason,
     *  the old portal's documents and approvals where it came from there, what is paid and owed, every decision so far and the desk that
     *  holds it now; Approve and Decline as the list offers them. A Dean reads only the applications from or into the faculty. */
    @GetMapping("/api/v1/transfers/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> review(@PathVariable UUID id) {
        Map<String, Object> r = jdbc.sql("SELECT * FROM people.transfer_list(NULL, NULL) WHERE id = :id").param("id", id)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("transfer application", id.toString()));
        String office = actingOffice();
        String myFaculty = "dean".equals(office) ? scope.actingFaculty() : null;
        if ("dean".equals(office) && !inFaculty(r, myFaculty)) {
            throw new NotFound("transfer application", id.toString());
        }
        String st = str(r.get("state"));
        BigDecimal paidTotal = money(r.get("paid_total"));
        boolean holds = mayApprove(office, scope.actingDept(), myFaculty, st, Sides.of(r), paidTotal != null && paidTotal.signum() > 0);
        r.put("stageLabel", stageLabel(st, paidTotal, money(r.get("balance"))));
        r.put("canApprove", holds && (!"REG_OK".equals(st) || settled(r.get("fee_due"), r.get("balance"))));
        r.put("canDecline", mayApprove(office, scope.actingDept(), myFaculty, st, Sides.of(r), true));
        Map<String, Object> student = jdbc.sql("""
                SELECT s.matric_no, s.admission_no, s.surname || ', ' || s.other_names AS name, s.current_level, s.status, s.entry_mode,
                       s.entry_session, s.entry_level, p.code AS programme_code, p.name AS programme
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = :s
                """).param("s", r.get("student_id")).query().singleRow();
        List<Map<String, Object>> history = jdbc.sql("""
                SELECT e.at, e.from_state, e.to_state, e.decision, e.desk, e.office, e.note, e.next_desk, e.source,
                       d.name AS dept_name, f.name AS faculty_name, c.name AS college_name,
                       (SELECT trim(coalesce(pe.given_names, '') || ' ' || pe.surname) FROM iam.person pe WHERE pe.id = e.actor) AS actor_name
                  FROM people.transfer_event e
                  LEFT JOIN ref.department d ON d.code = e.dept_code
                  LEFT JOIN ref.faculty f ON f.code = e.faculty_code
                  LEFT JOIN ref.college c ON c.code = e.college_code
                 WHERE e.application_id = :a
                 ORDER BY e.at, array_position(ARRAY['APPLIED','FROM_OK','TO_OK','REG_OK','RECOMMENDED','NOT_RECOMMENDED','APPROVED','EFFECTED','DECLINED','WITHDRAWN'], e.to_state), e.id
                """).param("a", id).query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("application", r);
        out.put("student", student);
        out.put("history", history);
        out.put("payments", paymentsMade(id));
        out.put("legacy", legacy(id));
        return out;
    }

    /** V686: the applications the old portal approved, freed from the queue together — each student restored onto the programme the
     *  application names at the level they are at (people.restore_approved_transfer: the number unchanged, the transfer recorded, the
     *  application withdrawn; no approval, fee or new application), each answered MOVED, RECORDED or REFUSED with the reason. The offices
     *  that restore a transfer (the database checks again). */
    @PostMapping("/api/v1/transfers/old-portal")
    @PreAuthorize(EFFECT)
    @Transactional
    Map<String, Object> freeOldPortal(@Valid @RequestBody OldPortal body) {
        java.sql.Date on = null;
        if (body.approvedOn() != null && !body.approvedOn().isBlank()) {
            try {
                on = java.sql.Date.valueOf(java.time.LocalDate.parse(body.approvedOn().trim()));
            } catch (java.time.format.DateTimeParseException e) {
                throw new DomainRuleViolation("PTR_APPROVED_ON", "The approval date is not a date.",
                        new DomainRuleViolation.Remedy("Pick the date the transfers were approved, or leave it empty.", "You"));
            }
        }
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM people.free_old_portal_transfers(CAST(:ids AS uuid[]), :r, :ref, :on)")
                .param("ids", body.applications().stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY)
                .param("r", body.reason()).param("ref", body.reference(), Types.VARCHAR).param("on", on, Types.DATE)
                .query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("moved", rows.stream().filter(r -> "MOVED".equals(r.get("outcome"))).count());
        out.put("recorded", rows.stream().filter(r -> "RECORDED".equals(r.get("outcome"))).count());
        out.put("refused", rows.stream().filter(r -> "REFUSED".equals(r.get("outcome"))).count());
        out.put("rows", rows);
        return out;
    }

    @GetMapping("/api/v1/transfers/programmes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> programmes() {
        return jdbc.sql("SELECT p.code, p.name, f.name AS faculty FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code WHERE NOT p.archived ORDER BY f.name, p.name").query().listOfRows();
    }

    @PostMapping("/api/v1/transfers")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> record(@Valid @RequestBody Record body) {
        UUID student = studentByNumber(body.number());
        UUID id = jdbc.sql("SELECT people.apply_transfer(:s, :p, :r, :u)")
                .param("s", student).param("p", body.toProgramme()).param("r", body.reason()).param("u", body.utme(), Types.INTEGER)
                .query(UUID.class).single();
        tellDesk(id);   // V734
        return Map.of("id", id, "state", "APPLIED");
    }

    /** one desk's Approve, moving the application to the next office in the chain. The stage decides which
     *  office may act: the current-department HOD, then the new-department HOD, then the Registrar, then
     *  the Academic office. */
    private Map<String, Object> stageOf(UUID id) {
        // V727: what is paid read from every verified payment (people.transfer_entitlement), not from the first reference alone
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT t.state, fp.dept_code AS from_dept, tp.dept_code AS to_dept, e.paid_total, e.balance, e.pending,
                       coalesce(e.paid_total, 0) > 0 AS paid,
                       fu.faculty_code AS from_faculty, fu.college_code AS from_college, tu.faculty_code AS to_faculty, tu.college_code AS to_college
                  FROM people.transfer_application t
                  LEFT JOIN ref.programme fp ON fp.code = t.from_programme_code
                  LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
                  LEFT JOIN LATERAL people.transfer_entitlement(t.id) e ON true
                  LEFT JOIN LATERAL people.transfer_unit(t.from_programme_code) fu ON true
                  LEFT JOIN LATERAL people.transfer_unit(t.to_programme_code) tu ON true
                 WHERE t.id = :id
                """).param("id", id).query().listOfRows();
        if (rows.isEmpty()) {
            throw new NotFound("transfer application", id.toString());
        }
        return rows.get(0);
    }

    @PostMapping("/api/v1/transfers/{id}/approve")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id, @Valid @RequestBody(required = false) Approve body) {
        lock(id);
        Map<String, Object> row = stageOf(id);
        String state = str(row.get("state"));
        boolean paid = Boolean.TRUE.equals(row.get("paid"));
        if (body != null && body.expectedState() != null && !body.expectedState().isBlank() && !body.expectedState().equalsIgnoreCase(state)) {
            // V734: approved meanwhile (a second press, or another holder of the desk): never the next stage by mistake
            throw new DomainRuleViolation("TR_STATE_MOVED", "This application has moved on since you opened it: it is now " + stageLabel(state, money(row.get("paid_total")), money(row.get("balance"))) + ".",
                    new DomainRuleViolation.Remedy("Open the application again to see where it stands.", "You"));
        }
        String office = actingOffice();
        if (!mayApprove(office, scope.actingDept(), "dean".equals(office) ? scope.actingFaculty() : null, state, Sides.of(row), paid)) {
            throw new DomainRuleViolation("TR_NOT_YOUR_STAGE",
                    "This application is not ready at your desk. " + stageLabel(state, money(row.get("paid_total")), money(row.get("balance"))) + ".",
                    new DomainRuleViolation.Remedy("The current department approves once the student has paid toward the transfer fee, here or on the old portal; "
                            + "each later office approves in turn, and the Academic office's final approval waits until the fee is paid in full.", "Registry"));
        }
        String passed = deskWords(id);
        if (body != null && body.note() != null && !body.note().isBlank()) {
            // V734: the approver's comment, kept in the history by the state change's own trigger (people.transfer_event)
            jdbc.sql("SELECT set_config('moaum.transfer_note', :n, true)").param("n", body.note().trim()).query().singleRow();
        }
        String next = jdbc.sql("SELECT people.approve_transfer(:id)").param("id", id).query(String.class).single();
        jdbc.sql("SELECT set_config('moaum.transfer_note', '', true)").query().singleRow();
        String now = deskWords(id);
        tell(id, "Your transfer application moved forward", "Your application to transfer has been approved by " + passed
                + (now == null ? (("EFFECTED".equals(next)) ? ". Your new programme now stands on your record." : ".") : " and is now with " + now + ".")
                + " You will be told at each stage.");
        tellDesk(id);
        return Map.of("id", id, "state", next);
    }

    /** any desk currently holding the application may decline it, with the reason on the record (payment not required) */
    @PostMapping("/api/v1/transfers/{id}/decline")
    @PreAuthorize(APPROVERS)
    @Transactional
    Map<String, Object> decline(@PathVariable UUID id, @Valid @RequestBody Why body) {
        lock(id);
        Map<String, Object> row = stageOf(id);
        String state = str(row.get("state"));
        String office = actingOffice();
        if (!mayApprove(office, scope.actingDept(), "dean".equals(office) ? scope.actingFaculty() : null, state, Sides.of(row), true)) {
            throw new DomainRuleViolation("TR_NOT_YOUR_STAGE",
                    "This application is not at your desk. " + stageLabel(state, money(row.get("paid_total")), money(row.get("balance"))) + ".",
                    new DomainRuleViolation.Remedy("Only the office holding the application at this stage may decline it.", "Registry"));
        }
        String desk = deskWords(id);
        jdbc.sql("SELECT people.decline_transfer(:id, :w)").param("id", id).param("w", body.why()).query().singleRow();
        tell(id, "Your transfer application was declined", "Your application to transfer was declined by " + (desk == null ? "the " + stageWord(state) : desk) + ".\n\nReason: " + body.why() + "\n\nWrite to the Academic Office if you wish to take it further.");
        return Map.of("id", id, "state", "DECLINED");
    }

    @PostMapping("/api/v1/transfers/{id}/review")
    @PreAuthorize(SAIC)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @Valid @RequestBody Review body) {
        if (body.recommend() && (body.level() == null)) {
            throw new DomainRuleViolation("TR_LEVEL", "A recommendation names the level to admit into.", new DomainRuleViolation.Remedy("Choose the level.", "Academic Office"));
        }
        jdbc.sql("SELECT people.review_transfer(:id, :rec, :lvl, :note)")
                .param("id", id).param("rec", body.recommend()).param("lvl", body.level(), Types.INTEGER).param("note", body.note(), Types.VARCHAR)
                .query().singleRow();
        tell(id, body.recommend() ? "Your transfer is recommended to Senate" : "Your transfer was not recommended",
                body.recommend() ? "The Senate Admissions Committee recommends your transfer, into " + body.level() + " Level. Senate decides next; you will be told." : "The Senate Admissions Committee did not recommend your transfer." + (body.note() == null ? "" : "\n\nNote: " + body.note()));
        return Map.of("id", id, "state", body.recommend() ? "RECOMMENDED" : "NOT_RECOMMENDED");
    }

    @PostMapping("/api/v1/transfers/{id}/senate")
    @PreAuthorize(SENATE)
    @Transactional
    Map<String, Object> senate(@PathVariable UUID id, @Valid @RequestBody Senate body) {
        jdbc.sql("SELECT people.senate_transfer(:id, :ap, :note)")
                .param("id", id).param("ap", body.approve()).param("note", body.note(), Types.VARCHAR)
                .query().singleRow();
        tell(id, body.approve() ? "Senate approved your transfer" : "Senate did not approve your transfer",
                body.approve() ? "Senate approved your transfer. You will be told when the Registry gives it effect on your record." : "Senate did not approve your transfer." + (body.note() == null ? "" : "\n\nNote: " + body.note()));
        return Map.of("id", id, "state", body.approve() ? "APPROVED" : "DECLINED");
    }

    @PostMapping("/api/v1/transfers/{id}/withdraw")
    @PreAuthorize(OFFICERS)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id, @Valid @RequestBody Why body) {
        jdbc.sql("SELECT people.withdraw_transfer(:id, :w)").param("id", id).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "state", "WITHDRAWN");
    }

    @PostMapping("/api/v1/transfers/{id}/effect")
    @PreAuthorize(EFFECT)
    @Transactional
    Map<String, Object> effect(@PathVariable UUID id) {
        jdbc.sql("SELECT people.effect_transfer(:id)").param("id", id).query().singleRow();
        tell(id, "Your transfer has taken effect", "Your new programme and level now stand on your record. Register your courses for the current semester.");
        return Map.of("id", id, "state", "EFFECTED");
    }

    /* ── V286 · the student told at every stage ── */

    private static String stageWord(String state) {
        return state == null ? "desk" : state.replace('_', ' ').toLowerCase();
    }

    /** V734: the application held for this request before its state is read — a second press, or another holder of the desk at the
     *  same moment, waits and then reads the state the first left (TR_STATE_MOVED), never approving the next desk */
    private void lock(UUID id) {
        jdbc.sql("SELECT id FROM people.transfer_application WHERE id = :id FOR UPDATE").param("id", id).query().listOfRows();
    }

    /** V734: the words of the desk holding the application now (people.transfer_desk), or null when nothing is pending */
    private String deskWords(UUID id) {
        return jdbc.sql("SELECT label FROM people.transfer_desk(:id) WHERE desk IS NOT NULL").param("id", id).query(String.class).optional().orElse(null);
    }

    /** V734: the holders of the desk the application has reached told it awaits them (the University's master prompt of 12 November 2026:
     *  "notify the relevant student and next approving officer") — an HOD of the department, the College's Dean, the Registry, the
     *  Academic Office, as people.transfer_desk_people finds them */
    private void tellDesk(UUID transfer) {
        jdbc.sql("""
                SELECT platform.queue_notice('EMAIL', p.email, 'A transfer application awaits you',
                           'The inter-departmental transfer application of ' || s.surname || ', ' || s.other_names || coalesce(' (' || s.matric_no || ')', '')
                           || ' from ' || coalesce(fp.name, t.from_programme_code) || ' to ' || coalesce(tp.name, t.to_programme_code)
                           || ' is now with ' || d.label || E'.\n\nReview it on the portal: Inter-Departmental Transfer.\n\nOffice of the Registrar, ' || :uni,
                           'transfer', t.id)
                  FROM people.transfer_application t
                  JOIN people.student s ON s.id = t.student_id
                  LEFT JOIN ref.programme fp ON fp.code = t.from_programme_code
                  LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
                 CROSS JOIN LATERAL people.transfer_desk(t.id) d
                 CROSS JOIN LATERAL people.transfer_desk_people(t.id) p
                 WHERE t.id = :id AND d.desk IS NOT NULL AND p.email IS NOT NULL
                """).param("id", transfer).param("uni", ng.edu.moaum.portal.platform.Branding.name()).query().listOfRows();
    }

    private void tell(UUID transfer, String subject, String body) {
        jdbc.sql("""
                SELECT platform.queue_notice('EMAIL', r.email, :s, :b || E'\\n\\nOffice of the Registrar, ' || :uni, 'student', t.student_id),
                       platform.queue_notice('SMS', r.phone, :s, left(:sms, 150), 'student', t.student_id)
                  FROM people.transfer_application t CROSS JOIN LATERAL people.student_reach(t.student_id) r WHERE t.id = :id
                """).param("s", subject).param("b", body).param("uni", ng.edu.moaum.portal.platform.Branding.name()).param("sms", "MOAUM: " + subject + ". See the portal.").param("id", transfer).query().listOfRows();
    }
}
