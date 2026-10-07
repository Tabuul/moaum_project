package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * The support desk as a requester outside the student register and the staff list sees it (V339: a JUPEB applicant or
 * student). The same tickets, the same routing to a queue and an agent, the same notices — only the requester is named by
 * its own kind, and only its own tickets and the comments meant for it are ever read back.
 */
@Component
public class RequesterTickets {

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final TicketNotifier notifier;

    RequesterTickets(JdbcClient jdbc, TicketNotifier notifier) {
        this.jdbc = jdbc;
        this.notifier = notifier;
    }

    /** who is asking, as the ticket records them */
    public record Requester(String kind, UUID id, String name, String number, String email, String phone) {
    }

    /** the categories this kind of requester raises tickets in, with the fields each asks for */
    public List<Map<String, Object>> categories(Set<String> codes) {
        return jdbc.sql("SELECT code, name, description, fields::text AS fields, attachment_hint FROM helpdesk.category WHERE active AND code = ANY(:c) ORDER BY ordinal")
                .param("c", codes.toArray(String[]::new)).query().listOfRows();
    }

    public List<Map<String, Object>> mine(Requester r) {
        return jdbc.sql("""
                SELECT t.id, t.number, t.subject, c.name AS category, t.status, t.priority, t.created_at, t.updated_at, q.name AS queue
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id LEFT JOIN helpdesk.queue q ON q.code = t.queue_code
                 WHERE t.requester_kind = :k AND t.requester_id = :id
                 ORDER BY (t.status = 'CLOSED'), t.updated_at DESC LIMIT 200
                """).param("k", r.kind()).param("id", r.id()).query().listOfRows();
    }

    /** a new ticket in one of the allowed categories, routed by the category's rule and announced */
    public Map<String, Object> submit(Requester r, Set<String> allowed, String category, String subject, String description, Map<String, String> details) {
        String c = category == null ? "" : category.trim().toUpperCase();
        if (!allowed.contains(c)) throw new NotFound("support category", c);
        Map<String, String> kept = new LinkedHashMap<>();
        Set<String> declared = new java.util.HashSet<>();
        String fields = jdbc.sql("SELECT fields::text FROM helpdesk.category WHERE code = :c").param("c", c).query(String.class).optional().orElse("[]");
        for (tools.jackson.databind.JsonNode f : JSON.readTree(fields)) if (f.hasNonNull("key")) declared.add(f.get("key").asString());
        if (details != null) details.forEach((k, v) -> {
            if (k != null && declared.contains(k) && v != null && !v.isBlank() && kept.size() < 30) kept.put(k, v.trim().substring(0, Math.min(v.trim().length(), 500)));
        });
        UUID id = jdbc.sql("SELECT helpdesk.submit(:k, :id, :n, :num, :e, :ph, NULL, NULL, :c, :s, :desc, :j::jsonb)")
                .param("k", r.kind()).param("id", r.id()).param("n", r.name()).param("num", r.number(), Types.VARCHAR)
                .param("e", r.email(), Types.VARCHAR).param("ph", r.phone(), Types.VARCHAR)
                .param("c", c).param("s", subject.trim()).param("desc", description.trim()).param("j", JSON.writeValueAsString(kept))
                .query(UUID.class).single();
        jdbc.sql("SELECT helpdesk.route(:t)").param("t", id).query(String.class).single();
        notifier.submitted(id);
        String number = jdbc.sql("SELECT number FROM helpdesk.ticket WHERE id = :id").param("id", id).query(String.class).single();
        return Map.of("id", id, "number", number, "status", "SUBMITTED");
    }

    /** V347: a requester's ticket sent by an agent to the office that decides (the JUPEB Office, the Bursary, the Director of ICT), the office told */
    public void escalateToOffice(UUID ticket, String office, UUID by, String reason) {
        jdbc.sql("SELECT helpdesk.escalate_to_office(:t, :o, :by, :r)").param("t", ticket).param("o", office).param("by", by).param("r", reason).query().singleRow();
        notifier.escalatedToOffice(ticket, office, reason);
    }

    /** V347: an internal note on a requester's ticket, the requester never sees it */
    public void internalNote(UUID ticket, UUID agent, String body) {
        String name = jdbc.sql("SELECT helpdesk.person_name(:p)").param("p", agent).query(String.class).optional().orElse("ICT Support");
        jdbc.sql("SELECT helpdesk.comment(:t, 'AGENT', :a, :n, true, :b)").param("t", ticket).param("a", agent).param("n", name).param("b", body).query(UUID.class).single();
    }

    public Map<String, Object> detail(Requester r, UUID ticket) {
        requireMine(r, ticket);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("""
                SELECT t.id, t.number, t.subject, t.description, c.name AS category, t.status, t.priority, t.created_at, t.updated_at,
                       t.resolution_summary, t.closure_reason, q.name AS queue
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id LEFT JOIN helpdesk.queue q ON q.code = t.queue_code
                 WHERE t.id = :id
                """).param("id", ticket).query().singleRow());
        out.put("comments", jdbc.sql("SELECT id, author_kind, author_name, body, created_at FROM helpdesk.ticket_comment WHERE ticket_id = :t AND NOT internal ORDER BY created_at")
                .param("t", ticket).query().listOfRows());
        return out;
    }

    public UUID comment(Requester r, UUID ticket, String body) {
        requireMine(r, ticket);
        UUID c = jdbc.sql("SELECT helpdesk.comment(:t, 'REQUESTER', :a, :n, false, :b)").param("t", ticket).param("a", r.id()).param("n", r.name()).param("b", body.trim())
                .query(UUID.class).single();
        notifier.requesterUpdate(ticket, body.length() > 200 ? body.substring(0, 200) + "…" : body);
        return c;
    }

    private void requireMine(Requester r, UUID ticket) {
        boolean ok = jdbc.sql("SELECT true FROM helpdesk.ticket WHERE id = :id AND requester_kind = :k AND requester_id = :r")
                .param("id", ticket).param("k", r.kind()).param("r", r.id()).query(Boolean.class).optional().orElse(false);
        if (!ok) throw new NotFound("ticket", ticket);
    }
}
