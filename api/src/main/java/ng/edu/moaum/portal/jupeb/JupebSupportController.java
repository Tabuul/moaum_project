package ng.edu.moaum.portal.jupeb;

import java.security.SecureRandom;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.helpdesk.RequesterTickets;
import ng.edu.moaum.portal.payments.PaymentsService;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

/**
 * ICT Support on JUPEB records (V347): the same desk, the same capabilities and the same ledger as the students' (V346), for
 * the candidates and students of the JUPEB programme. An agent reaches JUPEB records through a live posting on the JUPEB
 * Support queue, a University-wide posting or a posting on the JUPEB Office, and does only what those postings carry: reads
 * the record, corrects the contact details, resets the password (the JUPEB portal's own one-hour link, or a temporary password
 * at the desk on the candidate's ticket — random, hashed, one sign-in within 24 hours, changed at it), asks the gateway again
 * about a JUPEB payment through the payment service, re-applies the activation a paid school fee earns, raises and escalates
 * the candidate's tickets. Nothing here admits, grades, refunds or marks a payment paid. Every act is on the support ledger
 * and the JUPEB ticket's timeline; the candidate is told.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/support/jupeb")
@PreAuthorize("hasAnyAuthority('OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_ict','OFFICE_admin','OFFICE_super')")
class JupebSupportController {

    private static final Set<String> HEADS = Set.of("OFFICE_helpdeskhead", "OFFICE_ict", "OFFICE_admin", "OFFICE_super");
    private static final List<String> ALL = List.of("VIEW_STUDENT", "EDIT_CONTACT", "RESET_PASSWORD", "VIEW_PAYMENTS", "INVESTIGATE_PAYMENT", "VERIFY_PAYMENT",
            "SYNC_ENTITLEMENT", "VIEW_DOCUMENTS", "CREATE_TICKET", "VIEW_SUPPORT_AUDIT");
    private static final Set<String> ESCALATE_TO = Set.of("jupeb", "bursar", "ict");
    private static final String LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final JupebView view;
    private final PaymentsService payments;
    private final RequesterTickets tickets;
    private final TransactionTemplate tx;
    private final String portalUrl;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);

    JupebSupportController(JdbcClient jdbc, JupebView view, PaymentsService payments, RequesterTickets tickets, PlatformTransactionManager transactions,
                           @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.view = view;
        this.payments = payments;
        this.tickets = tickets;
        this.tx = new TransactionTemplate(transactions);
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    /* ── who is asking, and what they may do on JUPEB records ── */

    record Agent(UUID id, boolean head, Set<String> caps) {
        boolean has(String c) {
            return caps.contains(c);
        }
    }

    @SuppressWarnings("unchecked")
    private static List<String> texts(Object v) {
        try {
            if (v instanceof java.sql.Array a) return List.of((String[]) a.getArray());
            if (v instanceof List<?> l) return (List<String>) l;
        } catch (java.sql.SQLException e) {
            throw new IllegalStateException(e);
        }
        return List.of();
    }

    private Agent agent(Authentication auth) {
        UUID me = UUID.fromString(auth.getName());
        for (GrantedAuthority a : auth.getAuthorities()) if (HEADS.contains(a.getAuthority())) return new Agent(me, true, Set.copyOf(ALL));
        return new Agent(me, false, Set.copyOf(texts(jdbc.sql("SELECT helpdesk.agent_jupeb_capabilities(:p)").param("p", me).query().singleValue())));
    }

    /** the agent on one JUPEB record: not found unless a posting reaches JUPEB records */
    private Agent on(Authentication auth, UUID app) {
        Agent a = agent(auth);
        boolean reach = a.head() || Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.agent_reaches_jupeb(:p)").param("p", a.id()).query(Boolean.class).single());
        if (!reach || !Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.application WHERE id = :a)").param("a", app).query(Boolean.class).single())) {
            throw new NotFound("JUPEB record", app);
        }
        return a;
    }

    private static void can(Agent a, String cap) {
        if (!a.has(cap)) {
            throw new DomainRuleViolation("SUPPORT_CAPABILITY", "Your postings do not carry this act on JUPEB records.",
                    new DomainRuleViolation.Remedy("Ask the Head of the ICT Support Desk to grant it on your JUPEB Support posting; until then, escalate the ticket.", "Head of ICT Support Desk"));
        }
    }

    /** the ticket an act is done for: the candidate's own, and one the agent's postings reach */
    private UUID ticketFor(Agent a, UUID ticket, UUID app, boolean required) {
        if (ticket == null) {
            if (required) throw new DomainRuleViolation("SUPPORT_TICKET_REQUIRED", "This act is made on the candidate's own support ticket.",
                    new DomainRuleViolation.Remedy("Open the record from the candidate's ticket, or raise one for them first.", "You"));
            return null;
        }
        boolean mine = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM helpdesk.ticket WHERE id = :t AND requester_kind = 'JUPEB' AND requester_id = :a)")
                .param("t", ticket).param("a", app).query(Boolean.class).single());
        if (!mine) throw new DomainRuleViolation("SUPPORT_TICKET", "That ticket is not this candidate's.", new DomainRuleViolation.Remedy("Open the record from the candidate's own ticket.", "You"));
        if (!a.head() && !Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.can_view(:me, :t)").param("me", a.id()).param("t", ticket).query(Boolean.class).single())) {
            throw new DomainRuleViolation("SUPPORT_TICKET_SCOPE", "That ticket is outside your support scope.", new DomainRuleViolation.Remedy("Ask the Head of the Support Desk to assign it to you.", "Head of ICT Support Desk"));
        }
        return ticket;
    }

    private UUID act(UUID app, UUID ticket, String action, String field, String old, String now, String reason, Map<String, Object> detail) {
        Map<String, Object> d = new LinkedHashMap<>();
        if (detail != null) detail.forEach((k, v) -> { if (v != null) d.put(k, v); });
        return jdbc.sql("SELECT helpdesk.record_jupeb_support_action(:a, :t, :ac, :f, :o, :n, :r, :d::jsonb)")
                .param("a", app).param("t", ticket, Types.OTHER).param("ac", action).param("f", field, Types.VARCHAR).param("o", old, Types.VARCHAR)
                .param("n", now, Types.VARCHAR).param("r", reason).param("d", JSON.writeValueAsString(d)).query(UUID.class).single();
    }

    private void tell(UUID app, String subject, String body) {
        jdbc.sql("SELECT jupeb.tell(:a, :s, :b)").param("a", app).param("s", subject).param("b", body).query().listOfRows();
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    /* ── the search ── */

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> search(Authentication auth, @RequestParam(required = false) String q, @RequestParam(required = false) String session,
                               @RequestParam(required = false) String state, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        Agent a = agent(auth);
        boolean reach = a.head() || Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.agent_reaches_jupeb(:p)").param("p", a.id()).query(Boolean.class).single());
        if (!reach) {
            throw new DomainRuleViolation("SUPPORT_JUPEB_SCOPE", "None of your postings reaches JUPEB records.",
                    new DomainRuleViolation.Remedy("The Head of the ICT Support Desk posts you on the JUPEB Support queue.", "Head of ICT Support Desk"));
        }
        can(a, "VIEW_STUDENT");
        String term = blank(q);
        int sz = Math.max(1, Math.min(size, 200));
        int pg = Math.max(1, page);
        UUID uid = null;
        try { if (term != null) uid = UUID.fromString(term); } catch (IllegalArgumentException notOne) { uid = null; }
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT count(*) OVER () AS total, a.id, a.application_no, a.legacy_ref, a.exam_no, a.surname, a.first_name, a.middle_name, a.email, a.phone, a.session,
                       a.state, a.stream, c.code AS combination_code, a.legacy_source
                  FROM jupeb.application a LEFT JOIN jupeb.combination c ON c.id = a.combination_id
                 WHERE (:s::text IS NULL OR a.session = :s) AND (:st::text IS NULL OR a.state = :st)
                   AND (:q::text IS NULL OR upper(a.application_no) = upper(:q) OR upper(a.legacy_ref) = upper(:q) OR upper(a.exam_no) = upper(:q)
                        OR lower(a.email) = lower(:q) OR a.phone = :q OR a.id = :uid
                        OR upper(a.surname) LIKE upper(:q) || '%' OR upper(a.first_name) LIKE upper(:q) || '%')
                 ORDER BY a.surname, a.first_name LIMIT :n OFFSET :o
                """).param("s", blank(session), Types.VARCHAR).param("st", blank(state) == null ? null : state.trim().toUpperCase(), Types.VARCHAR)
                .param("q", term, Types.VARCHAR).param("uid", uid, Types.OTHER).param("n", sz).param("o", (long) (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows.stream().map(r -> { Map<String, Object> m = new LinkedHashMap<>(r); m.remove("total"); return m; }).toList());
        out.put("capabilities", List.copyOf(a.caps()));
        out.put("sessions", jdbc.sql("SELECT DISTINCT session FROM jupeb.application ORDER BY session DESC").query(String.class).list());
        return out;
    }

    /* ── one record, in support mode ── */

    private List<Map<String, Object>> references(UUID app) {
        return jdbc.sql("""
                SELECT f.reference, f.kind, f.amount, f.session, f.semester, f.created_at, f.expires_at, f.confirmed_at, f.channel,
                       CASE WHEN f.confirmed_at IS NOT NULL THEN 'CONFIRMED' WHEN f.expires_at < now() THEN 'EXPIRED' ELSE 'PENDING' END AS state,
                       ge.gateway, ge.gateway_ref, ge.outcome AS gateway_outcome, ge.received_at AS gateway_at,
                       (SELECT count(*) FROM finance.gateway_attempt g WHERE g.reference = f.reference) AS attempts,
                       (SELECT l.old_reference FROM jupeb.legacy_payment l WHERE l.fee_reference_id = f.id) AS old_reference
                  FROM jupeb.fee_reference f
                  LEFT JOIN LATERAL (SELECT e.gateway, e.gateway_ref, e.outcome, e.received_at FROM finance.gateway_event e WHERE e.reference = f.reference
                                      ORDER BY e.received_at DESC LIMIT 1) ge ON true
                 WHERE f.application_id = :a ORDER BY f.created_at DESC
                """).param("a", app).query().listOfRows();
    }

    @GetMapping("/{id}")
    @Transactional(readOnly = true)
    Map<String, Object> profile(Authentication auth, @PathVariable UUID id, @RequestParam(required = false) UUID ticket) {
        Agent a = on(auth, id);
        can(a, "VIEW_STUDENT");
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> record = new LinkedHashMap<>(view.of(id, false));
        if (!a.has("VIEW_DOCUMENTS")) record.remove("documents");
        if (!a.has("VIEW_PAYMENTS") && !a.has("INVESTIGATE_PAYMENT")) { record.remove("fees"); record.remove("references"); }
        out.put("record", record);
        out.put("payments", a.has("VIEW_PAYMENTS") || a.has("INVESTIGATE_PAYMENT") ? references(id) : List.of());
        out.put("account", jdbc.sql("""
                SELECT acc.email, acc.last_signed_in_at, acc.locked_until > now() AS locked, acc.must_change_password, acc.temp_expires_at IS NOT NULL AS temporary
                  FROM jupeb.account acc JOIN jupeb.application a ON a.account_id = acc.id WHERE a.id = :a
                """).param("a", id).query().singleRow());
        out.put("tickets", jdbc.sql("""
                SELECT t.id, t.number, t.subject, t.status, t.priority, c.name AS category, t.created_at, t.updated_at, helpdesk.person_name(t.assigned_to) AS agent, t.escalated_office
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
                 WHERE t.requester_kind = 'JUPEB' AND t.requester_id = :a ORDER BY (t.status = 'CLOSED'), t.updated_at DESC LIMIT 100
                """).param("a", id).query().listOfRows());
        out.put("actions", jdbc.sql("""
                SELECT x.id, x.at, x.action, helpdesk.support_module(x.action) AS module, x.field, x.old_value, x.new_value, x.reason, x.summary, x.outcome, x.method,
                       x.payment_reference, helpdesk.person_name(x.agent_id) AS agent, x.agent_office, x.ticket_id, t.number AS ticket_number,
                       CASE WHEN t.status IN ('RESOLVED', 'CLOSED') THEN 'RESOLVED' ELSE x.outcome END AS result
                  FROM helpdesk.support_action x LEFT JOIN helpdesk.ticket t ON t.id = x.ticket_id
                 WHERE x.jupeb_application_id = :a ORDER BY x.at DESC LIMIT 200
                """).param("a", id).query().listOfRows());
        out.put("ticket", ticket == null ? null : jdbc.sql("""
                SELECT t.id, t.number, t.subject, t.status, c.name AS category, c.code AS category_code FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
                 WHERE t.id = :t AND t.requester_kind = 'JUPEB' AND t.requester_id = :a
                """).param("t", ticket).param("a", id).query().listOfRows().stream().findFirst().orElse(null));
        out.put("capabilities", List.copyOf(a.caps()));
        out.put("agent", jdbc.sql("SELECT helpdesk.person_name(:p)").param("p", a.id()).query(String.class).optional().orElse(""));
        out.put("categories", tickets.categories(Set.of("JUPEB")));
        return out;
    }

    /* ── the contact details ── */

    public record ContactIn(@Pattern(regexp = "^0[0-9]{10}$", message = "an eleven-digit Nigerian number") String phone,
                            @Size(max = 300) String contactAddress, @Size(max = 300) String permanentAddress,
                            @Size(max = 120) String guardianName, @Pattern(regexp = "^(0[0-9]{10})?$", message = "an eleven-digit Nigerian number") String guardianPhone,
                            @Size(max = 300) String guardianAddress, @Size(max = 120) String nextOfKinName,
                            @Pattern(regexp = "^(0[0-9]{10})?$", message = "an eleven-digit Nigerian number") String nextOfKinPhone,
                            @Size(max = 60) String nextOfKinRelationship, @NotBlank @Size(max = 2000) String reason, UUID ticket) {
    }

    @PutMapping("/{id}/contact")
    @Transactional
    Map<String, Object> contact(Authentication auth, @PathVariable UUID id, @Valid @RequestBody ContactIn b) {
        Agent a = on(auth, id);
        can(a, "EDIT_CONTACT");
        UUID ticket = ticketFor(a, b.ticket(), id, false);
        Map<String, Object> before = jdbc.sql("SELECT phone, contact_address, permanent_address, guardian_name, guardian_phone, guardian_address, next_of_kin_name, next_of_kin_phone, next_of_kin_relationship FROM jupeb.application WHERE id = :id")
                .param("id", id).query().singleRow();
        if (blank(b.phone()) == null) {
            throw new DomainRuleViolation("JUPEB_PHONE_REQUIRED", "A JUPEB record keeps a phone number.", new DomainRuleViolation.Remedy("Enter it as 08012345678.", "You"));
        }
        Map<String, Object> after = new LinkedHashMap<>();
        after.put("phone", blank(b.phone()));
        after.put("contact_address", blank(b.contactAddress()));
        after.put("permanent_address", blank(b.permanentAddress()));
        after.put("guardian_name", blank(b.guardianName()));
        after.put("guardian_phone", blank(b.guardianPhone()));
        after.put("guardian_address", blank(b.guardianAddress()));
        after.put("next_of_kin_name", blank(b.nextOfKinName()));
        after.put("next_of_kin_phone", blank(b.nextOfKinPhone()));
        after.put("next_of_kin_relationship", blank(b.nextOfKinRelationship()));
        List<String> changed = new ArrayList<>();
        for (var e : after.entrySet()) {
            Object was = before.get(e.getKey());
            if (!java.util.Objects.equals(was == null ? null : String.valueOf(was), e.getValue())) changed.add(e.getKey().replace('_', ' '));
        }
        if (changed.isEmpty()) {
            throw new DomainRuleViolation("SUPPORT_NOTHING_CHANGED", "Nothing differs from what the record holds.", new DomainRuleViolation.Remedy("Correct the field the candidate reported.", "You"));
        }
        jdbc.sql("""
                UPDATE jupeb.application SET phone = :phone, contact_address = :ca, permanent_address = :pa, guardian_name = :gn, guardian_phone = :gp,
                       guardian_address = :ga, next_of_kin_name = :kn, next_of_kin_phone = :kp, next_of_kin_relationship = :kr WHERE id = :id
                """).param("phone", after.get("phone")).param("ca", after.get("contact_address"), Types.VARCHAR).param("pa", after.get("permanent_address"), Types.VARCHAR)
                .param("gn", after.get("guardian_name"), Types.VARCHAR).param("gp", after.get("guardian_phone"), Types.VARCHAR).param("ga", after.get("guardian_address"), Types.VARCHAR)
                .param("kn", after.get("next_of_kin_name"), Types.VARCHAR).param("kp", after.get("next_of_kin_phone"), Types.VARCHAR).param("kr", after.get("next_of_kin_relationship"), Types.VARCHAR)
                .param("id", id).update();
        jdbc.sql("SELECT jupeb.app_event(:a, 'CONTACT_UPDATED', :n)").param("a", id).param("n", "Corrected by ICT Support: " + String.join(", ", changed)).query().listOfRows();
        Map<String, Object> d = new LinkedHashMap<>();
        d.put("summary", "Contact details corrected: " + String.join(", ", changed));
        d.put("before", before);
        d.put("after", after);
        act(id, ticket, "CONTACT_EDITED", String.join(", ", changed), null, null, b.reason().trim(), d);
        tell(id, "Your contact details were updated by ICT Support", "ICT Support corrected your " + String.join(", ", changed) + " on the JUPEB portal. Reason: "
                + b.reason().trim() + ". If this is not what you asked for, reply to your support ticket.");
        return profile(auth, id, ticket);
    }

    /* ── the password: the JUPEB portal's own reset, or a temporary one at the desk on the ticket ── */

    public record PasswordIn(@NotBlank String method, @NotBlank @Size(max = 2000) String reason, UUID ticket) {
    }

    private static String sha256(String s) {
        try {
            return HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(s.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    @PostMapping("/{id}/password")
    @Transactional
    Map<String, Object> password(Authentication auth, @PathVariable UUID id, @Valid @RequestBody PasswordIn body) {
        Agent a = on(auth, id);
        can(a, "RESET_PASSWORD");
        String method = body.method().trim().toUpperCase();
        String reason = body.reason().trim();
        UUID account = jdbc.sql("SELECT account_id FROM jupeb.application WHERE id = :a").param("a", id).query(UUID.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        if ("LINK".equals(method) || "RESET_LINK".equals(method)) {
            UUID ticket = ticketFor(a, body.ticket(), id, false);
            byte[] raw = new byte[32];
            RANDOM.nextBytes(raw);
            String token = HexFormat.of().formatHex(raw);
            UUID reset = jdbc.sql("INSERT INTO jupeb.password_reset (account_id, token_hash, expires_at) VALUES (:acc, :h, now() + interval '1 hour') RETURNING id")
                    .param("acc", account).param("h", sha256(token)).query(UUID.class).single();
            tell(id, "Your JUPEB portal password reset", "Your JUPEB portal password reset has been initiated by ICT Support. Follow the secure instructions to create a new password: open this link within the hour and choose a new one.\n\n"
                    + portalUrl + "/jupeb/reset?token=" + token + "\n\nThe link works once. ICT Support never sees or sets your password. If you did not ask for this, ignore this message and tell ICT Support.");
            String email = jdbc.sql("SELECT email FROM jupeb.account WHERE id = :acc").param("acc", account).query(String.class).single();
            String masked = email.indexOf('@') > 1 ? email.charAt(0) + "***" + email.substring(email.indexOf('@') - 1) : "***";
            act(id, ticket, "PASSWORD_RESET", null, null, null, reason, Map.of("method", "RESET_LINK", "authEventId", reset.toString(),
                    "summary", "Password reset initiated: a one-hour link sent to " + masked));
            out.put("method", "RESET_LINK");
            out.put("sentTo", masked);
        } else if ("TEMPORARY".equals(method) || "TEMPORARY_PASSWORD".equals(method)) {
            UUID ticket = ticketFor(a, body.ticket(), id, true);
            StringBuilder pw = new StringBuilder(12);
            for (int i = 0; i < 12; i++) pw.append(LETTERS.charAt(RANDOM.nextInt(LETTERS.length())));
            OffsetDateTime until = OffsetDateTime.now().plusHours(24);
            jdbc.sql("""
                    UPDATE jupeb.account SET password_hash = :h, must_change_password = true, failed_attempts = 0, locked_until = NULL,
                           temp_expires_at = :until, temp_issued_by = :by, temp_used_at = NULL WHERE id = :acc
                    """).param("h", encoder.encode(pw.toString())).param("until", until).param("by", a.id()).param("acc", account).update();
            JupebView.endSessions(jdbc, account, null, "temporary password issued by ICT Support");
            jdbc.sql("SELECT jupeb.app_event(:a, 'PASSWORD_RESET', 'A temporary password was issued by ICT Support at the desk')").param("a", id).query().listOfRows();
            act(id, ticket, "PASSWORD_RESET", null, null, null, reason, Map.of("method", "TEMPORARY_PASSWORD",
                    "summary", "Temporary password issued at the desk: one sign-in, changed at it, within 24 hours"));
            tell(id, "Your JUPEB portal password was reset by ICT Support", "Your JUPEB portal password reset has been initiated by ICT Support at the desk. Sign in with the temporary password you were given; it works once, within 24 hours, and you will be asked to choose your own at once. If you did not ask for this, contact ICT Support.");
            out.put("method", "TEMPORARY_PASSWORD");
            out.put("temporaryPassword", pw.toString());
            out.put("expiresAt", until.toString());
        } else {
            throw new DomainRuleViolation("SUPPORT_RESET_METHOD", "A reset is a link to the candidate's email, or a temporary password at the desk.", new DomainRuleViolation.Remedy("Choose LINK or TEMPORARY.", "You"));
        }
        return out;
    }

    /* ── payments: asked again of the gateway through the payment service; the activation a paid fee earns re-applied ── */

    public record ActIn(@Size(max = 2000) String reason, UUID ticket) {
    }

    /** asked of the gateway outside any transaction; the act written after it answers. Never a payment created or marked paid. */
    @PostMapping("/{id}/payments/{reference}/verify")
    Map<String, Object> verify(Authentication auth, @PathVariable UUID id, @PathVariable String reference, @Valid @RequestBody(required = false) ActIn body) {
        Agent a = on(auth, id);
        can(a, "VERIFY_PAYMENT");
        String ref = reference.trim().toUpperCase();
        Boolean was = jdbc.sql("SELECT confirmed_at IS NOT NULL FROM jupeb.fee_reference WHERE upper(reference) = :r AND application_id = :a")
                .param("r", ref).param("a", id).query(Boolean.class).optional().orElseThrow(() -> new NotFound("JUPEB payment reference", ref));
        UUID ticket = ticketFor(a, body == null ? null : body.ticket(), id, false);
        Map<String, Object> answer = payments.verify(ref, "VERIFY");
        boolean now = Boolean.TRUE.equals(jdbc.sql("SELECT confirmed_at IS NOT NULL FROM jupeb.fee_reference WHERE upper(reference) = :r").param("r", ref).query(Boolean.class).single());
        String reason = body == null || blank(body.reason()) == null ? "The candidate reported the payment as not reflected" : body.reason().trim();
        tx.executeWithoutResult(st -> {
            Map<String, Object> d = new LinkedHashMap<>();
            d.put("paymentReference", ref);
            d.put("method", "GATEWAY_VERIFY");
            d.put("outcome", !was && now ? "COMPLETED" : "NO_CHANGE");
            d.put("summary", !was && now ? "Payment " + ref + " verified with the gateway and confirmed" : "Gateway asked about " + ref + ": " + answer.get("outcome"));
            act(id, ticket, "PAYMENT_VERIFIED", null, was ? "Confirmed" : "Not confirmed", now ? "Confirmed" : "Not confirmed", reason, d);
            if (!was && now) tell(id, "Your payment issue has been resolved", "Your payment issue has been resolved. Your verified payment has been synchronized with your JUPEB portal.");
        });
        return Map.of("gateway", answer, "confirmed", now, "changed", !was && now);
    }

    /** the studentship a paid school fee earns, re-applied by the same rule the payment applies (jupeb.activate_if_due) */
    @PostMapping("/{id}/refresh")
    @Transactional
    Map<String, Object> refresh(Authentication auth, @PathVariable UUID id, @Valid @RequestBody(required = false) ActIn body) {
        Agent a = on(auth, id);
        can(a, "SYNC_ENTITLEMENT");
        UUID ticket = ticketFor(a, body == null ? null : body.ticket(), id, false);
        String before = jdbc.sql("SELECT state FROM jupeb.application WHERE id = :a").param("a", id).query(String.class).single();
        boolean activated = Boolean.TRUE.equals(jdbc.sql("SELECT jupeb.activate_if_due(:a)").param("a", id).query(Boolean.class).single());
        String after = jdbc.sql("SELECT state FROM jupeb.application WHERE id = :a").param("a", id).query(String.class).single();
        String reason = body == null || blank(body.reason()) == null ? "The school fee is paid but the studentship did not follow" : body.reason().trim();
        act(id, ticket, "ENTITLEMENT_REFRESHED", "state", before, after, reason, Map.of("method", "ENTITLEMENT_REFRESH", "outcome", activated ? "COMPLETED" : "NO_CHANGE",
                "summary", activated ? "Studentship activated: the paid school fee now stands on the record" : "Nothing to re-apply: the record already follows its payments (" + after.toLowerCase() + ")"));
        if (activated) tell(id, "Your payment issue has been resolved", "Your payment issue has been resolved. Your verified payment has been synchronized with your JUPEB portal, and your studentship is active.");
        return Map.of("activated", activated, "state", after);
    }

    /* ── tickets ── */

    public record TicketIn(@NotBlank @Size(max = 200) String subject, @NotBlank @Size(max = 8000) String description, Map<String, String> details) {
    }

    @PostMapping("/{id}/tickets")
    @Transactional
    Map<String, Object> raise(Authentication auth, @PathVariable UUID id, @Valid @RequestBody TicketIn body) {
        Agent a = on(auth, id);
        can(a, "CREATE_TICKET");
        Map<String, Object> r = jdbc.sql("SELECT surname || ', ' || first_name || coalesce(' ' || middle_name, '') AS name, application_no, email, phone FROM jupeb.application WHERE id = :a")
                .param("a", id).query().singleRow();
        Map<String, Object> made = tickets.submit(new RequesterTickets.Requester("JUPEB", id, (String) r.get("name"), (String) r.get("application_no"), (String) r.get("email"), (String) r.get("phone")),
                Set.of("JUPEB"), "JUPEB", body.subject(), body.description(), body.details());
        UUID t = (UUID) made.get("id");
        tickets.internalNote(t, a.id(), "Raised at the support desk on the candidate's behalf.");
        act(id, t, "TICKET_CREATED", null, null, String.valueOf(made.get("number")), "Raised at the desk: " + body.subject().trim(),
                Map.of("summary", "Ticket " + made.get("number") + " raised for the candidate: " + body.subject().trim()));
        return made;
    }

    public record EscalateIn(@NotNull UUID ticket, @NotBlank @Size(max = 40) String office, @NotBlank @Size(max = 2000) String reason) {
    }

    @PostMapping("/{id}/escalate")
    @Transactional
    Map<String, Object> escalate(Authentication auth, @PathVariable UUID id, @Valid @RequestBody EscalateIn body) {
        Agent a = on(auth, id);
        can(a, "VIEW_STUDENT");
        UUID ticket = ticketFor(a, body.ticket(), id, true);
        String office = body.office().trim().toLowerCase();
        if (!ESCALATE_TO.contains(office)) {
            throw new DomainRuleViolation("SUPPORT_ESCALATE_OFFICE", "A JUPEB ticket is escalated to the JUPEB Office, the Bursary or the Director of ICT.", new DomainRuleViolation.Remedy("Choose one of those.", "You"));
        }
        tickets.escalateToOffice(ticket, office, a.id(), body.reason().trim());
        String words = jdbc.sql("SELECT label FROM ref.office WHERE code = :o").param("o", office).query(String.class).optional().orElse(office);
        act(id, ticket, "ESCALATED", null, null, words, body.reason().trim(), Map.of("summary", "Escalated to " + words, "outcome", "ESCALATED"));
        return Map.of("ticket", ticket, "office", office, "status", "WAITING_FOR_OFFICE");
    }
}
