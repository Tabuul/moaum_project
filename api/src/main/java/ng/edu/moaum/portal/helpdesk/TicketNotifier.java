package ng.edu.moaum.portal.helpdesk;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.platform.NoticeRepository;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * What the desk says, and to whom, through the portal's one outbox (V025): the requester at each turn of
 * the ticket, the agent it is given to, the person it is escalated to, the desk when a ticket arrives or
 * comes back. A student's notices are filed against the student, so they show on the student's own
 * notifications page as well as reaching their email. Queued in the caller's transaction, so nothing is
 * announced that was not written.
 */
@Component
class TicketNotifier {

    private final NoticeRepository notices;
    private final JdbcClient jdbc;
    private final String portalUrl;

    TicketNotifier(NoticeRepository notices, JdbcClient jdbc, @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.notices = notices;
        this.jdbc = jdbc;
        this.portalUrl = portalUrl.endsWith("/") ? portalUrl.substring(0, portalUrl.length() - 1) : portalUrl;
    }

    /** the ticket as the notices need it */
    record T(UUID id, String number, String subject, String category, String status, String requesterKind, UUID requesterId, String requesterName,
             String requesterEmail, UUID assignedTo, String resolutionSummary, String closureReason, String queueCode, String queue) {
    }

    T load(UUID id) {
        Map<String, Object> r = jdbc.sql("""
                SELECT t.id, t.number, t.subject, c.name AS category, t.status, t.requester_kind, t.requester_id, t.requester_name, t.requester_email,
                       t.assigned_to, t.resolution_summary, t.closure_reason, t.queue_code, q.name AS queue
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id LEFT JOIN helpdesk.queue q ON q.code = t.queue_code WHERE t.id = :id
                """).param("id", id).query().singleRow();
        return new T((UUID) r.get("id"), (String) r.get("number"), (String) r.get("subject"), (String) r.get("category"), (String) r.get("status"),
                (String) r.get("requester_kind"), (UUID) r.get("requester_id"), (String) r.get("requester_name"), (String) r.get("requester_email"),
                (UUID) r.get("assigned_to"), (String) r.get("resolution_summary"), (String) r.get("closure_reason"), (String) r.get("queue_code"), (String) r.get("queue"));
    }

    private String trackingLines(T t) {
        return "Track the ticket at " + portalUrl + "/track with the number and this email address, or sign in to the portal and open Support → My Tickets.\n";
    }

    private void toRequester(T t, String subject, String body) {
        if (t.requesterEmail() == null || t.requesterEmail().isBlank()) return;
        // V363: a request from the sign-in page names no one; its notices are about the ticket itself
        String kind = "STUDENT".equals(t.requesterKind()) ? "student" : "PUBLIC".equals(t.requesterKind()) ? "ticket" : "person";
        notices.queueEmail(t.requesterEmail(), subject, body, kind, t.requesterId(), List.of());
    }

    private void toPerson(UUID person, String subject, String body) {
        if (person == null) return;
        String email = jdbc.sql("SELECT email FROM iam.person WHERE id = :id").param("id", person).query(String.class).optional().orElse(null);
        if (email == null || email.isBlank()) return;
        notices.queueEmail(email, subject, body, "person", person, List.of());
    }

    /** everyone who holds the ICT Support Agent office, the Head's or the Director's, today, and has an email */
    private List<Map<String, Object>> desk() {
        return holders("ictagent", "helpdeskhead", "ict");
    }

    /** the Head of ICT Support Desk and the Director of ICT: told of what is queued with no agent, returned, or critical */
    private List<Map<String, Object>> heads() {
        return holders("helpdeskhead", "ict");
    }

    private List<Map<String, Object>> holders(String... offices) {
        return jdbc.sql("""
                SELECT DISTINCT p.id, p.email FROM iam.person p JOIN iam.office_assignment a ON a.person_id = p.id
                 WHERE a.office_code = ANY(string_to_array(:o, ',')) AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                   AND p.email IS NOT NULL AND btrim(p.email) <> '' AND p.ended_on IS NULL
                """).param("o", String.join(",", offices)).query().listOfRows();
    }

    /** the agents posted on a queue, available or busy, with an email */
    private List<Map<String, Object>> queueAgents(String queue) {
        if (queue == null) return List.of();
        return jdbc.sql("""
                SELECT DISTINCT p.id, p.email FROM helpdesk.agent_assignment a JOIN iam.person p ON p.id = a.person_id
                 WHERE a.queue_code = :q AND a.active AND a.availability IN ('AVAILABLE','BUSY')
                   AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                   AND p.email IS NOT NULL AND btrim(p.email) <> '' AND p.ended_on IS NULL
                """).param("q", queue).query().listOfRows();
    }

    private void toAll(List<Map<String, Object>> people, String subject, String body) {
        for (Map<String, Object> p : people) notices.queueEmail((String) p.get("email"), subject, body, "person", (UUID) p.get("id"), List.of());
    }

    /** the assigned agent when one is named and reachable; otherwise everyone at the desk */
    private void toAgentOrDesk(T t, String subject, String body) {
        boolean reachable = t.assignedTo() != null && jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM iam.person p WHERE p.id = :id AND p.ended_on IS NULL AND p.email IS NOT NULL AND btrim(p.email) <> '' AND helpdesk.is_agent(p.id))
                """).param("id", t.assignedTo()).query(Boolean.class).single();
        if (reachable) {
            toPerson(t.assignedTo(), subject, body);
            return;
        }
        for (Map<String, Object> p : desk()) {
            notices.queueEmail((String) p.get("email"), subject, body, "person", (UUID) p.get("id"), List.of());
        }
    }

    private String deskLink(T t) {
        return portalUrl + "/helpdesk/tickets/" + t.id();
    }

    /* ── the events ── */

    void submitted(UUID id) {
        T t = load(id);
        if ("PUBLIC".equals(t.requesterKind())) {
            // V363: asked from the sign-in page by someone not signed in, to an address nobody has confirmed — the notice says only
            // what the University says, and nothing the request typed (no name, no subject), so it cannot carry another's words
            toRequester(t, "ICT Support Ticket Received — " + t.number(),
                    "Your request for help signing in has been received by the Directorate of ICT.\n\n"
                            + "Ticket number: " + t.number() + "\nSubmitted: " + java.time.LocalDate.now() + "\n\n"
                            + "The desk confirms who you are before it changes anything on an account, and may call the phone number you gave. "
                            + "It never asks for your password.\n"
                            + "If you did not ask for help signing in, ignore this email; nothing has been changed.\n"
                            + trackingLines(t) + "\nDirectorate of ICT");
        } else {
            toRequester(t, "ICT Support Ticket Received — " + t.number(),
                    "Dear " + t.requesterName() + ",\n\nYour ticket has been received by the Directorate of ICT.\n\n"
                            + "Ticket number: " + t.number() + "\nSubject: " + t.subject() + "\nCategory: " + t.category() + "\nSubmitted: " + java.time.LocalDate.now() + "\n\n"
                            + "Quote the ticket number in any follow-up. You will be told when the desk opens it, when work begins, and when it is resolved.\n"
                            + trackingLines(t) + "\nDirectorate of ICT");
        }
        String line = t.number() + " from " + t.requesterName() + " (" + t.category() + (t.queue() == null ? "" : " · " + t.queue() + " queue") + "): " + t.subject() + "\n\nOpen it: " + deskLink(t) + "\n";
        if (t.assignedTo() != null) {
            // V328: routed straight to an agent — they are told, nobody else need be
            toPerson(t.assignedTo(), "New ticket assigned to you — " + t.number(), line);
            return;
        }
        // queued with no agent: the Head of ICT Support Desk is told, and — when the desk asks for it — the queue's agents
        toAll(heads(), "Ticket queued with no agent — " + t.number(), line + "\nNo available agent on the " + (t.queue() == null ? "desk" : t.queue() + " queue") + " covers this ticket. Assign it, or post an agent.\n");
        boolean tellDesk = jdbc.sql("SELECT notify_agents_on_new FROM helpdesk.setting WHERE row_no").query(Boolean.class).optional().orElse(true);
        if (tellDesk) {
            List<Map<String, Object>> agents = queueAgents(t.queueCode());
            toAll(agents.isEmpty() ? desk() : agents, "New ICT support ticket " + t.number() + " — " + t.category(), line);
        }
    }

    /* ── V328: the desk across the University ── */

    void waiting(UUID id, String reason) {
        T t = load(id);
        toRequester(t, "Your ticket " + t.number() + " needs something from you",
                "On your ticket " + t.number() + " (" + t.subject() + "), the support desk needs something from you before it can go on:\n\n" + reason
                        + "\n\nReply on the ticket — sign in and open Support → My Tickets — and work resumes at once.\n" + trackingLines(t) + "\nDirectorate of ICT");
    }

    void transferred(UUID id, String fromQueue, String toQueue, String reason, UUID newAgent) {
        T t = load(id);
        toRequester(t, "Your ticket " + t.number() + " has been passed to " + toQueue,
                "Your ticket " + t.number() + " (" + t.subject() + ") is now with " + toQueue + ", which handles matters of this kind. Its number is unchanged.\n\n" + trackingLines(t) + "\nDirectorate of ICT");
        String line = t.number() + " from " + t.requesterName() + " (" + t.category() + "): " + t.subject() + "\n\nTransferred from " + fromQueue + " to " + toQueue + ": " + reason + "\n\nOpen it: " + deskLink(t) + "\n";
        if (newAgent != null) toPerson(newAgent, "Ticket transferred to you — " + t.number(), line);
        else toAll(heads(), "Ticket transferred and queued with no agent — " + t.number(), line);
    }

    void escalatedToOffice(UUID id, String office, String reason) {
        T t = load(id);
        String label = jdbc.sql("SELECT label FROM ref.office WHERE code = :c").param("c", office).query(String.class).optional().orElse(office);
        toAll(holders(office), "A support ticket awaits your decision — " + t.number(),
                t.number() + " from " + t.requesterName() + " (" + t.category() + "): " + t.subject() + "\n\nThe support desk asks " + label + " to decide: " + reason
                        + "\n\nOpen it: " + portalUrl + "/helpdesk/office/" + t.id() + "\nYour answer goes to the agent; the ticket waits until it comes.\n");
        toRequester(t, "Update on your ICT support ticket " + t.number(),
                "Your ticket " + t.number() + " (" + t.subject() + ") has been referred to " + label + " for a decision. You will be told when it comes back.\n\n" + trackingLines(t) + "\nDirectorate of ICT");
    }

    void officeAnswered(UUID id, UUID by) {
        T t = load(id);
        String body = t.number() + " (" + t.subject() + "): the office has answered. Open the ticket and act on its instruction.\n\nOpen it: " + deskLink(t) + "\n";
        toAgentOrDesk(t, "The office has answered on " + t.number(), body);
    }

    void critical(UUID id, UUID by) {
        T t = load(id);
        toAll(heads(), "CRITICAL ticket — " + t.number(), t.number() + " from " + t.requesterName() + " (" + t.category() + "): " + t.subject()
                + "\n\nMarked critical by " + jdbc.sql("SELECT helpdesk.person_name(:p)").param("p", by).query(String.class).optional().orElse("the desk") + ". Open it: " + deskLink(t) + "\n");
    }

    /** tickets returned to their queue because the agent is no longer available: the Head is told once, with the numbers */
    void returned(List<UUID> ids) {
        if (ids == null || ids.isEmpty()) return;
        List<String> lines = jdbc.sql("SELECT t.number || ' · ' || coalesce(q.name, 'no queue') || ' · ' || t.subject FROM helpdesk.ticket t LEFT JOIN helpdesk.queue q ON q.code = t.queue_code WHERE t.id = ANY(string_to_array(:ids, ',')::uuid[]) ORDER BY t.number")
                .param("ids", ids.stream().map(UUID::toString).reduce((a, b) -> a + "," + b).orElse("")).query(String.class).list();
        toAll(heads(), ids.size() + " ticket" + (ids.size() == 1 ? "" : "s") + " returned to the queue",
                "The agent holding these tickets is no longer available (left, lost the office, or on leave), so they are back on their queue with no agent:\n\n"
                        + String.join("\n", lines) + "\n\nAssign them, or post an agent: " + portalUrl + "/helpdesk?agent=none\n");
    }

    void bulkAssigned(UUID agent, int n, String reason) {
        toPerson(agent, n + " ticket" + (n == 1 ? "" : "s") + " moved to you", n + " open ticket" + (n == 1 ? " has" : "s have") + " been moved to you: " + reason + "\n\nSee them: " + portalUrl + "/helpdesk?agent=me\n");
    }

    void assigned(UUID id, UUID agent, boolean reassigned) {
        T t = load(id);
        toPerson(agent, (reassigned ? "Ticket reassigned to you — " : "Ticket assigned to you — ") + t.number(),
                t.number() + " from " + t.requesterName() + " (" + t.category() + "): " + t.subject() + "\n\nOpen it: " + deskLink(t) + "\n");
    }

    void escalated(UUID id, UUID to, String reason) {
        T t = load(id);
        toPerson(to, "Ticket escalated to you — " + t.number(),
                t.number() + " from " + t.requesterName() + " (" + t.category() + "): " + t.subject() + "\n\nReason: " + reason + "\n\nOpen it: " + deskLink(t) + "\n");
    }

    void statusChanged(UUID id) {
        T t = load(id);
        String word = switch (t.status()) {
            case "OPENED" -> "has been opened by the support desk";
            case "IN_PROGRESS" -> "is being worked on";
            case "REOPENED" -> "has been reopened";
            case "WAITING_FOR_OFFICE" -> "has been referred to a University office for a decision";
            case "WAITING_FOR_STUDENT" -> "is waiting for something from you";
            default -> "is now " + t.status().toLowerCase().replace('_', ' ');
        };
        toRequester(t, "Update on your ICT support ticket " + t.number(),
                "Your ticket " + t.number() + " (" + t.subject() + ") " + word + ".\n\n" + trackingLines(t) + "\nDirectorate of ICT");
    }

    void resolved(UUID id) {
        T t = load(id);
        toRequester(t, "Your ICT support ticket is resolved — " + t.number(),
                "Your ticket " + t.number() + " (" + t.subject() + ") has been marked as resolved.\n\n"
                        + "Resolution: " + t.resolutionSummary() + "\nResolved: " + java.time.LocalDate.now() + "\n\n"
                        + "If this settles it, sign in and confirm the resolution, which closes the ticket. If it does not, reopen the ticket and say what is still wrong.\n"
                        + trackingLines(t) + "\nDirectorate of ICT");
    }

    void closed(UUID id) {
        T t = load(id);
        toRequester(t, "Your ICT support ticket is closed — " + t.number(),
                "Your ticket " + t.number() + " (" + t.subject() + ") is closed.\n\n"
                        + (t.closureReason() == null ? "" : "Reason: " + t.closureReason() + "\n\n")
                        + "Thank you. If the problem returns, raise a new ticket and quote this number.\n\nDirectorate of ICT");
    }

    void reopened(UUID id, String reason, boolean byDesk) {
        T t = load(id);
        String body = t.number() + " from " + t.requesterName() + " (" + t.category() + ") has been reopened" + (byDesk ? " by the desk" : " by the requester") + ": " + reason
                + "\n\nOpen it: " + deskLink(t) + "\n";
        toAgentOrDesk(t, "Ticket reopened — " + t.number(), body);
    }

    void agentUpdate(UUID id, String excerpt) {
        T t = load(id);
        toRequester(t, "The ICT desk has an update on " + t.number(),
                "On your ticket " + t.number() + " (" + t.subject() + "), the ICT desk says:\n\n" + excerpt + "\n\n" + trackingLines(t) + "\nDirectorate of ICT");
    }

    void requesterUpdate(UUID id, String excerpt) {
        T t = load(id);
        String body = t.requesterName() + " added to " + t.number() + " (" + t.subject() + "):\n\n" + excerpt + "\n\nOpen it: " + deskLink(t) + "\n";
        toAgentOrDesk(t, "Update from the requester — " + t.number(), body);
    }
}
