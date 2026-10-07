package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.payments.PaymentsService;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.studentportal.StudentPortalService;

import static ng.edu.moaum.portal.helpdesk.SupportAccess.AGENTS;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.blank;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.can;

/**
 * Payment support from the ICT Support Desk (V346). ICT Support does not become the Bursary: it finds a student's payment by
 * any number the student holds — the portal's reference (the invoice the portal issues), the receipt, the gateway's or the
 * transaction's reference, the matriculation, JAMB or application number, the name — reads what the gateway said, what the
 * Bursary's ledger holds, what the payment entitles and why registration is or is not open, and says in words what is wrong.
 * It then does only what the existing services do: asks the gateway again (PaymentsService.verify — the reconciler's own
 * requery, which settles the original reference and nothing else), re-applies what a confirmed payment entitles
 * (finance.refresh_entitlement — never a payment, never a credit), tells the student their receipt is ready, or escalates
 * the ticket to the Bursary or the Director of ICT. Nothing here marks a payment paid, changes an amount, or refunds.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/support/payments")
class PaymentSupportController {

    private final JdbcClient jdbc;
    private final SupportAccess support;
    private final PaymentsService payments;
    private final StudentPortalService portal;
    private final TransactionTemplate tx;

    PaymentSupportController(JdbcClient jdbc, SupportAccess support, PaymentsService payments, StudentPortalService portal, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.support = support;
        this.payments = payments;
        this.portal = portal;
        this.tx = new TransactionTemplate(transactions);
    }

    /* ── the search: any number the student holds, within the reach of the postings that carry the investigation ── */

    @GetMapping
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> search(Authentication auth, @RequestParam(required = false) String q, @RequestParam(required = false) String state,
                               @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "25") int size) {
        SupportAccess.Access a = support.access(auth);
        can(a, "INVESTIGATE_PAYMENT");
        String term = blank(q);
        int sz = Math.max(1, Math.min(size, 100));
        int pg = Math.max(1, page);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("page", pg);
        out.put("size", sz);
        if (term == null) {
            out.put("total", 0);
            out.put("rows", List.of());
            return out;
        }
        String st = blank(state) == null ? null : state.trim().toUpperCase();
        String sql = """
                WITH sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(:me, 'INVESTIGATE_PAYMENT')),
                hit AS (
                    SELECT r.id FROM finance.payment_reference r WHERE r.reference = :qu OR r.receipt_no = :qu
                    UNION SELECT r.id FROM finance.gateway_event e JOIN finance.payment_reference r ON r.reference = e.reference WHERE e.gateway_ref = :q
                    UNION SELECT r.id FROM finance.gateway_attempt g JOIN finance.payment_reference r ON r.reference = g.reference WHERE g.txn_ref = :q
                    UNION SELECT r.id FROM people.student s JOIN finance.payment_reference r ON r.student_id = s.id
                           WHERE upper(s.matric_no) = :qu OR upper(s.admission_no) = :qu OR upper(s.jamb_reg_no) = :qu OR s.id = :uid
                              OR s.candidate_id = (SELECT x.candidate_id FROM admissions.application x WHERE x.application_no = :qu)
                              OR (length(:q) >= 3 AND upper(s.surname) LIKE :qp))
                SELECT count(*) OVER () AS total, r.reference, r.purpose, r.session, r.amount, r.generated_at, r.expires_at, r.confirmed_at, r.channel, r.receipt_no,
                       CASE WHEN r.confirmed_at IS NOT NULL THEN 'CONFIRMED' WHEN r.expires_at < now() THEN 'EXPIRED' ELSE 'PENDING' END AS state,
                       s.id AS student_id, s.surname || ', ' || s.other_names AS student, coalesce(s.matric_no, s.admission_no) AS number, s.jamb_reg_no, p.name AS programme,
                       ge.gateway, ge.gateway_ref, ge.outcome AS gateway_outcome, ge.received_at AS gateway_at
                  FROM hit JOIN finance.payment_reference r ON r.id = hit.id
                  JOIN people.student s ON s.id = r.student_id
                  JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN LATERAL (SELECT e.gateway, e.gateway_ref, e.outcome, e.received_at FROM finance.gateway_event e
                                      WHERE e.reference = r.reference ORDER BY e.received_at DESC LIMIT 1) ge ON true
                 WHERE (:head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY(sc.faculties) OR p.dept_code = ANY(sc.departments)))
                   AND (:st::text IS NULL OR CASE WHEN r.confirmed_at IS NOT NULL THEN 'CONFIRMED' WHEN r.expires_at < now() THEN 'EXPIRED' ELSE 'PENDING' END = :st)
                 ORDER BY r.generated_at DESC LIMIT :n OFFSET :o
                """;
        List<Map<String, Object>> rows = jdbc.sql(sql).param("me", a.agent()).param("head", a.head()).param("q", term).param("qu", term.toUpperCase())
                .param("qp", term.toUpperCase() + "%").param("uid", SupportAccess.uuidOrNull(term), Types.OTHER).param("st", st, Types.VARCHAR)
                .param("n", sz).param("o", (long) (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        List<Map<String, Object>> clean = rows.stream().map(r -> { Map<String, Object> m = new LinkedHashMap<>(r); m.remove("total"); return m; }).toList();
        out.put("total", total);
        out.put("rows", clean);
        return out;
    }

    /* ── one payment, diagnosed ── */

    /** the reference and its student, or not found; and the agent on that student — outside their reach it is not found either */
    private Map<String, Object> reference(String referenceIn) {
        String ref = referenceIn == null ? "" : referenceIn.trim().toUpperCase();
        return jdbc.sql("""
                SELECT r.id, r.reference, r.student_id, r.session, r.purpose, r.amount, r.generated_at, r.expires_at, r.confirmed_at, r.channel, r.note, r.receipt_no,
                       s.surname || ', ' || s.other_names AS student, coalesce(s.matric_no, s.admission_no) AS number, p.name AS programme
                  FROM finance.payment_reference r JOIN people.student s ON s.id = r.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE r.reference = :r OR r.receipt_no = :r
                """).param("r", ref).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("payment reference", ref));
    }

    private static String purposeKind(String purpose) {
        if (purpose == null) return "OTHER";
        if (purpose.startsWith("School fees")) return "SCHOOL_FEES";
        if (purpose.startsWith("GST fee")) return "GST";
        if (purpose.startsWith("Hostel accommodation")) return "HOSTEL";
        if (purpose.startsWith("Transcript TRN-")) return "TRANSCRIPT";
        if (purpose.startsWith("Library fine")) return "LIBRARY";
        if (purpose.startsWith("Wallet top-up")) return "WALLET";
        return "OTHER";
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> diagnose(SupportAccess.Access a, Map<String, Object> r) {
        String ref = String.valueOf(r.get("reference"));
        UUID student = (UUID) r.get("student_id");
        String session = String.valueOf(r.get("session"));
        String purpose = String.valueOf(r.get("purpose"));
        String kind = purposeKind(purpose);
        boolean confirmed = r.get("confirmed_at") != null;
        boolean expired = !confirmed && r.get("expires_at") instanceof OffsetDateTime e && e.isBefore(OffsetDateTime.now());

        List<Map<String, Object>> attempts = jdbc.sql("SELECT gateway, kind, opened_at, checked_at, checks, txn_ref FROM finance.gateway_attempt WHERE reference = :r ORDER BY opened_at DESC LIMIT 50")
                .param("r", ref).query().listOfRows();
        List<Map<String, Object>> events = jdbc.sql("""
                SELECT gateway, source, event, gateway_ref, amount, status, signature_ok, outcome, received_at, resolved_at, resolution
                  FROM finance.gateway_event WHERE reference = :r ORDER BY received_at DESC LIMIT 50
                """).param("r", ref).query().listOfRows();
        List<Map<String, Object>> refunds = jdbc.sql("SELECT state, amount, proposed_at, approved_at, paid_at, rejected_why FROM finance.refund WHERE reference = :r ORDER BY proposed_at DESC")
                .param("r", ref).query().listOfRows();
        List<Map<String, Object>> siblings = jdbc.sql("""
                SELECT reference, amount, generated_at, confirmed_at, receipt_no FROM finance.payment_reference
                 WHERE student_id = :s AND session = :ses AND purpose = :p AND reference <> :r ORDER BY generated_at DESC LIMIT 20
                """).param("s", student).param("ses", session).param("p", purpose).param("r", ref).query().listOfRows();
        Map<String, Object> entitlement = support.json().readValue(jdbc.sql("SELECT finance.entitlement_state(:s, :ses)::text").param("s", student).param("ses", session)
                .query(String.class).single(), Map.class);
        Integer openSem = jdbc.sql("SELECT coalesce(max(number), 1) FROM policy.semester WHERE session = :ses AND state = 'OPEN'").param("ses", session).query(Integer.class).single();
        Map<String, Object> registration = new LinkedHashMap<>();
        registration.put("semester", openSem);
        registration.put("gate", jdbc.sql("SELECT registration.registration_gate(:s, :ses, :sem)").param("s", student).param("ses", session).param("sem", openSem).query(String.class).optional().orElse(null));
        registration.put("status", jdbc.sql("SELECT status FROM registration.course_registration WHERE student_id = :s AND session = :ses AND semester = :sem")
                .param("s", student).param("ses", session).param("sem", openSem).query(String.class).optional().orElse("NONE"));
        registration.put("clearsRegistration", entitlement.get("clearsRegistration"));

        /* what the gateway said: the latest settlement-bearing answer wins */
        java.util.function.Predicate<String> said = o -> events.stream().anyMatch(e -> o.equals(e.get("outcome")));
        String gateway = said.test("SETTLED") || said.test("ALREADY_SETTLED") ? "SUCCESS"
                : said.test("SHORT_PAID") ? "SHORT_PAID"
                : said.test("NOT_SUCCESSFUL") ? "FAILED"
                : said.test("GATEWAY_ERROR") ? "NO_ANSWER"
                : !attempts.isEmpty() ? "PENDING"
                : confirmed ? "NOT_USED" : "NOT_STARTED";
        String verification = !confirmed ? "NOT_VERIFIED"
                : events.stream().anyMatch(e -> "SETTLED".equals(e.get("outcome")) && List.of("VERIFY", "SWEEP").contains(String.valueOf(e.get("source")))) ? "VERIFIED_BY_GATEWAY_REQUERY"
                : events.stream().anyMatch(e -> "SETTLED".equals(e.get("outcome"))) ? "CONFIRMED_BY_GATEWAY_NOTIFICATION"
                : "CONFIRMED_BY_BURSARY";

        /* what the payment entitles, and whether it has followed */
        String entitled;
        String entitledWords;
        switch (kind) {
            case "HOSTEL" -> {
                String fee = jdbc.sql("SELECT coalesce(fee_status, 'PAYABLE') FROM hostel.allocation WHERE reference = :r ORDER BY allocated_at DESC LIMIT 1").param("r", ref).query(String.class).optional().orElse(null);
                entitled = !confirmed ? "NOT_APPLICABLE" : fee == null || "PAID".equals(fee) ? "UPDATED" : "NOT_UPDATED";
                entitledWords = fee == null ? "No hostel allocation carries this reference." : "The hostel allocation's fee is " + fee.toLowerCase() + ".";
            }
            case "TRANSCRIPT" -> {
                Boolean paid = jdbc.sql("SELECT paid_at IS NOT NULL FROM credentials.transcript_request WHERE ref = :t").param("t", purpose.length() >= 25 ? purpose.substring(11, 25) : "").query(Boolean.class).optional().orElse(null);
                entitled = !confirmed ? "NOT_APPLICABLE" : paid == null || paid ? "UPDATED" : "NOT_UPDATED";
                entitledWords = paid == null ? "No transcript request matches the purpose." : paid ? "The transcript request stands paid." : "The transcript request is not yet marked paid.";
            }
            case "LIBRARY" -> {
                long open = jdbc.sql("SELECT count(*) FROM library.loan WHERE fine_reference = :r AND fine_settled_at IS NULL").param("r", ref).query(Long.class).single();
                entitled = !confirmed ? "NOT_APPLICABLE" : open == 0 ? "UPDATED" : "NOT_UPDATED";
                entitledWords = open == 0 ? "No library fine against this reference is outstanding." : open + " library fine(s) against this reference are not yet settled.";
            }
            case "WALLET" -> {
                boolean credited = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.wallet_entry WHERE reference = :r)").param("r", ref).query(Boolean.class).single());
                entitled = !confirmed ? "NOT_APPLICABLE" : credited ? "UPDATED" : "NOT_UPDATED";
                entitledWords = credited ? "The wallet is credited." : "No wallet credit stands against the top-up; a credit is the Bursary's to write.";
            }
            case "GST" -> {
                boolean ok = Boolean.TRUE.equals(entitlement.get("gstEntitled"));
                entitled = !confirmed ? "NOT_APPLICABLE" : ok ? "UPDATED" : "NOT_UPDATED";
                entitledWords = ok ? "The GST/EPS entitlement stands." : "The GST/EPS entitlement does not stand (state " + entitlement.get("gstState") + ").";
            }
            case "SCHOOL_FEES" -> {
                entitled = confirmed ? "UPDATED" : "NOT_APPLICABLE";
                entitledWords = "Counted in the session's position: paid " + entitlement.get("paid") + " of " + entitlement.get("due") + "; registration "
                        + (Boolean.TRUE.equals(entitlement.get("clearsRegistration")) ? "cleared" : Boolean.FALSE.equals(entitlement.get("clearsRegistration")) ? "not cleared" : "not decided (no clearance scheme in force)") + ".";
            }
            default -> {
                entitled = confirmed ? "UPDATED" : "NOT_APPLICABLE";
                entitledWords = "Nothing further follows this payment on the portal beyond the receipt.";
            }
        }

        /* the diagnosis, in words, with the one act that answers it */
        List<Map<String, Object>> advice = new ArrayList<>();
        java.util.function.BiConsumer<String, String[]> say = (code, words) -> advice.add(Map.of("code", code, "words", words[0], "action", words[1]));
        long otherConfirmed = siblings.stream().filter(x -> x.get("confirmed_at") != null).count();
        if (!confirmed) {
            if ("SUCCESS".equals(gateway)) say.accept("GATEWAY_PAID_PORTAL_NOT", new String[] {"The gateway reports the payment successful but the portal has not settled it — the callback was missed or failed. Verify with the gateway: it settles this original reference; nothing new is created.", "VERIFY"});
            else if ("SHORT_PAID".equals(gateway)) say.accept("SHORT_PAID", new String[] {"The gateway settled less than this reference's amount; the portal never confirms a short payment. The Bursary decides — escalate the ticket with the evidence.", "ESCALATE_BURSARY"});
            else if ("FAILED".equals(gateway)) say.accept("FAILED", new String[] {"The gateway reports the payment failed. If the student was debited, the bank reverses it or the Bursary decides on the evidence — escalate.", "ESCALATE_BURSARY"});
            else if (!attempts.isEmpty()) say.accept("HANGING", new String[] {"A payment was started on " + attempts.get(0).get("gateway") + " and no settlement has come back. Recheck with the gateway; if it still does not confirm and the student holds a debit alert, escalate to the Bursary with the evidence.", "VERIFY"});
            else say.accept("NO_GATEWAY_ATTEMPT", new String[] {"No payment was started on a gateway against this reference. If the student paid at a bank or by transfer, the Bursary confirms it from the teller or the statement — escalate with the evidence.", "ESCALATE_BURSARY"});
            if (expired) say.accept("EXPIRED", new String[] {"The reference has expired. A new one is generated by the student on the Fees screen, never by the desk; an expired reference the gateway did settle is still verified and kept.", "NONE"});
        } else {
            if ("NOT_UPDATED".equals(entitled)) {
                say.accept("ENTITLEMENT_STALE", "WALLET".equals(kind)
                        ? new String[] {entitledWords + " Escalate to the Bursary.", "ESCALATE_BURSARY"}
                        : new String[] {"The payment stands confirmed but what it entitles has not followed: " + entitledWords + " Refresh the payment entitlement — it re-applies what the confirmation applies; no payment is created.", "REFRESH"});
            }
            if ("SCHOOL_FEES".equals(kind) && Boolean.FALSE.equals(entitlement.get("clearsRegistration"))) {
                say.accept("BALANCE", new String[] {"The payment stands and is counted, but the Bursary's clearance for registration still holds: NGN " + entitlement.get("balance") + " remains for " + session
                        + (Boolean.TRUE.equals(entitlement.get("hasArrears")) ? ", and an earlier session is in arrears" : "") + ". That is a balance, not a fault — the Bursary decides.", "ESCALATE_BURSARY"});
            }
            if (otherConfirmed > 0) {
                say.accept("POSSIBLE_DUPLICATE", new String[] {"Another confirmed payment for the same purpose and session stands (" + otherConfirmed + "). Applying or refunding the excess is the Bursary's decision — escalate; the desk does not refund.", "ESCALATE_BURSARY"});
            }
            if (advice.isEmpty()) say.accept("IN_ORDER", new String[] {"The payment is confirmed and everything it entitles stands. Show the student the receipt.", "VIEW_RECEIPT"});
        }
        if (!refunds.isEmpty()) say.accept("REFUND_RECORDED", new String[] {"A refund is recorded against this reference (" + String.valueOf(refunds.get(0).get("state")).toLowerCase() + "); it is the Bursary's, tracked here, not decided here.", "NONE"});

        /* the acts this agent may take on it now */
        List<String> actions = new ArrayList<>();
        actions.add("VIEW_TRANSACTION");
        if (!confirmed && a.has("VERIFY_PAYMENT")) { actions.add("VERIFY"); actions.add("RECHECK"); }
        if (confirmed && a.has("SYNC_ENTITLEMENT")) actions.add("REFRESH_ENTITLEMENT");
        if (confirmed && (a.has("VIEW_PAYMENTS") || a.has("INVESTIGATE_PAYMENT"))) actions.add("VIEW_RECEIPT");
        if (confirmed && a.has("REGENERATE_RECEIPT")) actions.add("REGENERATE_RECEIPT");
        actions.add("ESCALATE_BURSARY");
        actions.add("ESCALATE_ICT");

        Map<String, Object> status = new LinkedHashMap<>();
        status.put("current", confirmed ? "PAID" : "SHORT_PAID".equals(gateway) ? "SHORT_PAID" : "FAILED".equals(gateway) ? "FAILED" : expired ? "EXPIRED" : "PENDING");
        status.put("gateway", gateway);
        status.put("finance", confirmed ? "VERIFIED" : expired ? "EXPIRED" : "NOT_CONFIRMED");
        status.put("entitlement", entitled);
        status.put("verification", verification);

        Map<String, Object> payment = new LinkedHashMap<>(r);
        payment.remove("id");
        payment.put("kind", kind);
        payment.put("invoice", r.get("reference"));
        payment.put("gatewayRef", events.stream().map(e -> e.get("gateway_ref")).filter(java.util.Objects::nonNull).findFirst().orElse(null));
        payment.put("transactionRef", attempts.stream().map(x -> x.get("txn_ref")).filter(java.util.Objects::nonNull).findFirst().orElse(null));

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("payment", payment);
        out.put("status", status);
        out.put("entitlementWords", entitledWords);
        out.put("entitlementState", entitlement);
        out.put("registration", registration);
        out.put("attempts", attempts);
        out.put("events", events);
        out.put("refunds", refunds);
        out.put("related", siblings);
        out.put("advice", advice);
        out.put("actions", actions);
        out.put("capabilities", List.copyOf(a.caps()));
        out.put("tickets", jdbc.sql("""
                SELECT t.id, t.number, t.subject, t.status, c.name AS category FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
                 WHERE t.requester_kind = 'STUDENT' AND t.requester_id = :s AND t.status NOT IN ('CLOSED') ORDER BY t.updated_at DESC LIMIT 20
                """).param("s", student).query().listOfRows());
        return out;
    }

    @GetMapping("/{reference}")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> diagnosis(Authentication auth, @PathVariable String reference) {
        Map<String, Object> r = reference(reference);
        SupportAccess.Access a = support.on(auth, (UUID) r.get("student_id"));
        can(a, "INVESTIGATE_PAYMENT");
        return diagnose(a, r);
    }

    public record ActIn(@Size(max = 2000) String reason, UUID ticket) {
    }

    private static String reasonOr(ActIn body, String fallback) {
        return body == null || blank(body.reason()) == null ? fallback : body.reason().trim();
    }

    /** the investigation itself goes on the ledger: who looked at which payment, for which ticket, and what they found */
    @PostMapping("/{reference}/investigate")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> investigate(Authentication auth, @PathVariable String reference, @Valid @RequestBody(required = false) ActIn body) {
        Map<String, Object> r = reference(reference);
        UUID student = (UUID) r.get("student_id");
        SupportAccess.Access a = support.on(auth, student);
        can(a, "INVESTIGATE_PAYMENT");
        UUID ticket = support.ticketFor(a, body == null ? null : body.ticket(), student, false);
        Map<String, Object> d = diagnose(a, r);
        @SuppressWarnings("unchecked") Map<String, Object> status = (Map<String, Object>) d.get("status");
        support.act(student, ticket, "PAYMENT_INVESTIGATED", null, null, null, reasonOr(body, "Payment investigated at the desk"), String.valueOf(r.get("session")), null,
                Map.of("paymentReference", String.valueOf(r.get("reference")), "outcome", "NO_CHANGE",
                       "summary", "Payment " + r.get("reference") + " investigated: gateway " + status.get("gateway") + ", finance " + status.get("finance") + ", entitlement " + status.get("entitlement"),
                       "after", status));
        return d;
    }

    /**
     * Verify / recheck / re-sync: the gateway is asked again about the original reference through the payment service's own
     * verification — the requery the reconciler sweeps with. A payment the gateway says is paid is settled exactly as its
     * notification would have settled it; one it does not confirm stays unconfirmed. Nothing is created and nothing is
     * marked paid by the desk. The gateway is asked outside any transaction; the act is written after it answers.
     */
    @PostMapping("/{reference}/verify")
    @PreAuthorize(AGENTS)
    Map<String, Object> verify(Authentication auth, @PathVariable String reference, @Valid @RequestBody(required = false) ActIn body) {
        Map<String, Object> r = reference(reference);
        UUID student = (UUID) r.get("student_id");
        SupportAccess.Access a = support.on(auth, student);
        can(a, "VERIFY_PAYMENT");
        UUID ticket = support.ticketFor(a, body == null ? null : body.ticket(), student, false);
        String ref = String.valueOf(r.get("reference"));
        boolean wasConfirmed = r.get("confirmed_at") != null;
        Map<String, Object> answer = payments.verify(ref, "VERIFY");
        Map<String, Object> after = reference(ref);
        boolean nowConfirmed = after.get("confirmed_at") != null;
        String reason = reasonOr(body, "The student reported the payment as not reflected");
        tx.executeWithoutResult(st -> {
            Map<String, Object> d = new LinkedHashMap<>();
            d.put("paymentReference", ref);
            d.put("method", "GATEWAY_VERIFY");
            d.put("outcome", !wasConfirmed && nowConfirmed ? "COMPLETED" : "NO_CHANGE");
            d.put("summary", !wasConfirmed && nowConfirmed ? "Payment verified with the gateway and synchronized: " + ref + " confirmed, receipt " + after.get("receipt_no")
                    : "Gateway asked about " + ref + ": " + answer.get("outcome"));
            d.put("before", Map.of("confirmed", wasConfirmed));
            d.put("after", Map.of("confirmed", nowConfirmed, "gateway", String.valueOf(answer.get("outcome"))));
            support.act(student, ticket, "PAYMENT_VERIFIED", null, wasConfirmed ? "Confirmed" : "Not confirmed", nowConfirmed ? "Confirmed" : "Not confirmed", reason,
                    String.valueOf(r.get("session")), null, d);
            if (!wasConfirmed && nowConfirmed) {
                support.tell(student, "Your payment issue has been resolved", "Your payment issue has been resolved. Your verified payment has been synchronized with your student portal. "
                        + "Your receipt is on the Fees screen.");
            }
        });
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("gateway", answer);
        out.put("confirmed", nowConfirmed);
        out.put("changed", !wasConfirmed && nowConfirmed);
        out.put("diagnosis", tx.execute(st -> diagnose(a, after)));
        return out;
    }

    /** refresh the entitlement of a CONFIRMED payment: what its confirmation applies is re-applied — never a payment, never a credit */
    @PostMapping("/{reference}/refresh")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> refresh(Authentication auth, @PathVariable String reference, @Valid @RequestBody(required = false) ActIn body) {
        Map<String, Object> r = reference(reference);
        UUID student = (UUID) r.get("student_id");
        SupportAccess.Access a = support.on(auth, student);
        can(a, "SYNC_ENTITLEMENT");
        UUID ticket = support.ticketFor(a, body == null ? null : body.ticket(), student, false);
        String ref = String.valueOf(r.get("reference"));
        @SuppressWarnings("unchecked")
        Map<String, Object> result = support.json().readValue(jdbc.sql("SELECT finance.refresh_entitlement(:r)::text").param("r", ref).query(String.class).single(), Map.class);
        List<?> problems = result.get("problems") instanceof List<?> l ? l : List.of();
        Map<String, Object> d = new LinkedHashMap<>();
        d.put("paymentReference", ref);
        d.put("method", "ENTITLEMENT_REFRESH");
        d.put("summary", problems.isEmpty() ? "Payment verified; portal entitlement synchronized for " + ref + ". The student can continue."
                : "Entitlement refreshed for " + ref + "; for the Bursary: " + String.join(" ", problems.stream().map(String::valueOf).toList()));
        d.put("outcome", problems.isEmpty() ? "COMPLETED" : "ESCALATED");
        d.put("before", result.get("before"));
        d.put("after", result.get("after"));
        support.act(student, ticket, "ENTITLEMENT_REFRESHED", null, null, null, reasonOr(body, "The payment is confirmed but the portal did not reflect it"), String.valueOf(r.get("session")), null, d);
        if (problems.isEmpty()) {
            support.tell(student, "Your payment issue has been resolved", "Your payment issue has been resolved. Your verified payment has been synchronized with your student portal.");
        }
        Map<String, Object> out = new LinkedHashMap<>(result);
        out.put("diagnosis", diagnose(a, reference(ref)));
        return out;
    }

    /** the receipt is drawn from the record whenever it is opened; regenerating it tells the student it is ready — the number and the amount stay the Bursary's */
    @PostMapping("/{reference}/receipt")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> regenerateReceipt(Authentication auth, @PathVariable String reference, @Valid @RequestBody(required = false) ActIn body) {
        Map<String, Object> r = reference(reference);
        UUID student = (UUID) r.get("student_id");
        SupportAccess.Access a = support.on(auth, student);
        can(a, "REGENERATE_RECEIPT");
        if (r.get("confirmed_at") == null) {
            throw new DomainRuleViolation("PAY_NOT_CONFIRMED", "A receipt follows a confirmed payment; this one is not confirmed.",
                    new DomainRuleViolation.Remedy("Verify it with the gateway first, or escalate it to the Bursary.", "ICT Support"));
        }
        UUID ticket = support.ticketFor(a, body == null ? null : body.ticket(), student, false);
        String ref = String.valueOf(r.get("reference"));
        support.act(student, ticket, "RECEIPT_REGENERATED", null, null, String.valueOf(r.get("receipt_no")), reasonOr(body, "The student could not open the receipt"),
                String.valueOf(r.get("session")), null, Map.of("paymentReference", ref, "method", "RECEIPT", "summary", "Receipt " + r.get("receipt_no") + " regenerated and the student told it is ready"));
        support.tell(student, "Your receipt is ready", "The receipt for your payment " + ref + " (receipt " + r.get("receipt_no") + ") is ready on your portal: open Fees, then Receipts, to view or print it.");
        return Map.of("reference", ref, "receiptNo", r.get("receipt_no"), "studentId", student);
    }

    /** the receipt's facts, for the desk's own copy of the student's receipt — the same document the student prints */
    @GetMapping("/{reference}/receipt")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> receipt(Authentication auth, @PathVariable String reference) {
        Map<String, Object> r = reference(reference);
        UUID student = (UUID) r.get("student_id");
        SupportAccess.Access a = support.on(auth, student);
        if (!a.has("VIEW_PAYMENTS") && !a.has("INVESTIGATE_PAYMENT")) can(a, "VIEW_PAYMENTS");
        if (r.get("confirmed_at") == null) throw new NotFound("receipt", String.valueOf(r.get("reference")));
        Map<String, Object> out = new LinkedHashMap<>(portal.receipt(student, String.valueOf(r.get("reference"))));
        out.put("studentId", student);
        return out;
    }
}
