package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.stereotype.Component;

import ng.edu.moaum.portal.platform.NoticeRepository;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

/**
 * Who is asking on the support desk, whom they reach and what they may do (V334, V346) — shared by the student and the
 * payment support screens, so the same answer is given everywhere and on the server every time. A student outside the
 * agent's reach is not found. A capability counts for a student only when it comes with a posting whose scope covers that
 * student (helpdesk.agent_capabilities_for); the Head of the Support Desk, the Director of ICT, Admin and Super hold every
 * capability the desk defines — and only those: results, refunds, fees, amounts, matriculation and admission decisions
 * are not among them. Every act lands on the support ledger with its reason and, when a ticket is named, on its timeline.
 */
@Component
class SupportAccess {

    static final String AGENTS = "hasAnyAuthority('OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    static final Set<String> HEADS = Set.of("OFFICE_helpdeskhead", "OFFICE_ict", "OFFICE_admin", "OFFICE_super");
    static final List<String> ALL = List.of("VIEW_STUDENT", "EDIT_CONTACT", "EDIT_PERSONAL", "EDIT_FAMILY", "EDIT_PHOTO", "REQUEST_CHANGE",
            "VIEW_PAYMENTS", "VIEW_DOCUMENTS", "MANAGE_REGISTRATION", "EXPORT_STUDENTS",
            "OVERRIDE_REGISTRATION", "RESET_PASSWORD", "INVESTIGATE_PAYMENT", "VERIFY_PAYMENT", "SYNC_ENTITLEMENT",
            "REGENERATE_RECEIPT", "CREATE_TICKET", "VIEW_SUPPORT_AUDIT");
    static final Map<String, String> WORDS = Map.ofEntries(
            Map.entry("VIEW_STUDENT", "viewing student records"), Map.entry("EDIT_CONTACT", "editing contact details"),
            Map.entry("EDIT_PERSONAL", "editing personal details"), Map.entry("EDIT_FAMILY", "editing family and sponsor details"),
            Map.entry("EDIT_PHOTO", "replacing the photograph"), Map.entry("REQUEST_CHANGE", "requesting a Registry change"),
            Map.entry("VIEW_PAYMENTS", "viewing payments"), Map.entry("VIEW_DOCUMENTS", "viewing documents"),
            Map.entry("MANAGE_REGISTRATION", "managing course registration"), Map.entry("EXPORT_STUDENTS", "exporting lists"),
            Map.entry("OVERRIDE_REGISTRATION", "the support override of course registration"), Map.entry("RESET_PASSWORD", "resetting student passwords"),
            Map.entry("INVESTIGATE_PAYMENT", "investigating payments"), Map.entry("VERIFY_PAYMENT", "verifying payments with the gateway"),
            Map.entry("SYNC_ENTITLEMENT", "refreshing payment entitlements"), Map.entry("REGENERATE_RECEIPT", "regenerating receipts"),
            Map.entry("CREATE_TICKET", "raising tickets for students"), Map.entry("VIEW_SUPPORT_AUDIT", "reading the support audit"));

    private final JdbcClient jdbc;
    private final NoticeRepository notices;
    private final tools.jackson.databind.ObjectMapper json;

    SupportAccess(JdbcClient jdbc, NoticeRepository notices, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.notices = notices;
        this.json = json;
    }

    /** the agent, whether they head the desk, the capabilities in force, and the scope in words */
    record Access(UUID agent, boolean head, Set<String> caps, String scope) {
        boolean has(String cap) {
            return caps.contains(cap);
        }
    }

    static boolean has(Authentication auth, String authority) {
        for (GrantedAuthority a : auth.getAuthorities()) if (authority.equals(a.getAuthority())) return true;
        return false;
    }

    static boolean head(Authentication auth) {
        return HEADS.stream().anyMatch(h -> has(auth, h));
    }

    static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    @SuppressWarnings("unchecked")
    static List<String> texts(Object v) {
        try {
            if (v instanceof java.sql.Array a) return List.of((String[]) a.getArray());
            if (v instanceof List<?> l) return (List<String>) l;
            if (v instanceof String[] s) return List.of(s);
        } catch (java.sql.SQLException e) {
            throw new IllegalStateException(e);
        }
        return List.of();
    }

    /** the agent across the desk: the union of their live postings' capabilities — for the desk-wide lists, each filtered by its own scope */
    Access access(Authentication auth) {
        UUID me = UUID.fromString(auth.getName());
        if (head(auth)) return new Access(me, true, Set.copyOf(ALL), "The University");
        Map<String, Object> row = jdbc.sql("SELECT helpdesk.agent_capabilities(:p) AS caps, (SELECT words FROM helpdesk.agent_student_scope(:p)) AS words")
                .param("p", me).query().singleRow();
        return new Access(me, false, Set.copyOf(texts(row.get("caps"))), row.get("words") == null ? "" : String.valueOf(row.get("words")));
    }

    /**
     * The agent on one student: not found outside their reach (the desk never says whether such a student exists), and with
     * only the capabilities of the postings that cover this student — so changing the id in the address reaches nobody new.
     */
    Access on(Authentication auth, UUID student) {
        Access a = access(auth);
        if (a.head()) {
            jdbc.sql("SELECT 1 FROM people.student WHERE id = :s").param("s", student).query(Integer.class).optional().orElseThrow(() -> new NotFound("student", student));
            return a;
        }
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.agent_may_see_student(:p, :s)").param("p", a.agent()).param("s", student).query(Boolean.class).optional().orElse(false))) {
            throw new NotFound("student", student);
        }
        List<String> caps = texts(jdbc.sql("SELECT helpdesk.agent_capabilities_for(:p, :s)").param("p", a.agent()).param("s", student).query().singleValue());
        return new Access(a.agent(), false, Set.copyOf(caps), a.scope());
    }

    static void can(Access a, String cap) {
        if (!a.has(cap)) {
            throw new DomainRuleViolation("SUPPORT_CAPABILITY", "Your posting does not carry " + WORDS.getOrDefault(cap, cap.toLowerCase()) + " for this student.",
                    new DomainRuleViolation.Remedy("Ask the Head of the ICT Support Desk to grant it on a posting that covers the student; until then, document the issue on the ticket and escalate it.", "Head of ICT Support Desk"));
        }
    }

    /** the ticket a support act is done for: it must be the student's own, else it is not the ticket */
    Map<String, Object> ticketOf(UUID ticket, UUID student) {
        if (ticket == null) return null;
        return jdbc.sql("""
                SELECT t.id, t.number, t.subject, t.status, c.name AS category, c.code AS category_code
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
                 WHERE t.id = :t AND t.requester_kind = 'STUDENT' AND t.requester_id = :s
                """).param("t", ticket).param("s", student).query().listOfRows().stream().findFirst().orElse(null);
    }

    /** the ticket named on an act, checked: the student's own, and one the agent's postings reach */
    UUID ticketFor(Access a, UUID ticket, UUID student, boolean required) {
        if (ticket == null) {
            if (required) {
                throw new DomainRuleViolation("SUPPORT_TICKET_REQUIRED", "This act is made on the student's own support ticket.",
                        new DomainRuleViolation.Remedy("Open the student from their ticket, or raise one for them first.", "You"));
            }
            return null;
        }
        if (ticketOf(ticket, student) == null) {
            throw new DomainRuleViolation("SUPPORT_TICKET", "That ticket is not this student's.", new DomainRuleViolation.Remedy("Open the student from their own ticket, or leave the ticket blank.", "You"));
        }
        if (!a.head() && !Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.can_view(:me, :t)").param("me", a.agent()).param("t", ticket).query(Boolean.class).single())) {
            throw new DomainRuleViolation("SUPPORT_TICKET_SCOPE", "That ticket is outside your support scope.",
                    new DomainRuleViolation.Remedy("Ask the Head of the Support Desk to assign it to you, or work it from a queue you are posted to.", "Head of ICT Support Desk"));
        }
        return ticket;
    }

    /** an act on the ledger, and on the ticket's timeline when one is named; detail carries summary, outcome, override, before and after, method */
    UUID act(UUID student, UUID ticket, String action, String field, String old, String now, String reason, String session, Integer semester, Map<String, Object> detail) {
        Map<String, Object> d = new LinkedHashMap<>();
        if (detail != null) detail.forEach((k, v) -> { if (v != null) d.put(k, v); });
        return jdbc.sql("SELECT helpdesk.record_support_action(:s, :t, :a, :f, :o, :n, :r, :ses, :sem, :d::jsonb)")
                .param("s", student).param("t", ticket, Types.OTHER).param("a", action).param("f", field, Types.VARCHAR).param("o", old, Types.VARCHAR)
                .param("n", now, Types.VARCHAR).param("r", reason).param("ses", session, Types.VARCHAR).param("sem", semester, Types.INTEGER)
                .param("d", json.writeValueAsString(d)).query(UUID.class).single();
    }

    UUID act(UUID student, UUID ticket, String action, String field, String old, String now, String reason, String session, Integer semester) {
        return act(student, ticket, action, field, old, now, reason, session, semester, null);
    }

    /** the student is told what ICT Support did, on the address the University reaches them at — never a password, never an amount */
    void tell(UUID student, String subject, String body) {
        String email = jdbc.sql("SELECT email FROM people.student_reach(:s)").param("s", student).query(String.class).optional().orElse(null);
        if (email != null && !email.isBlank()) notices.queueEmail(email, subject, body, "student", student, List.of());
    }

    String agentName(UUID agent) {
        return jdbc.sql("SELECT helpdesk.person_name(:p)").param("p", agent).query(String.class).optional().orElse("ICT Support");
    }

    /** a UUID typed into a search, or null */
    static UUID uuidOrNull(String s) {
        if (s == null) return null;
        try {
            return UUID.fromString(s.trim());
        } catch (IllegalArgumentException notOne) {
            return null;
        }
    }

    tools.jackson.databind.ObjectMapper json() {
        return json;
    }
}
