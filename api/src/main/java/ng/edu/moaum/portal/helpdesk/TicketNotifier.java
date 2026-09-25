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
             String requesterEmail, UUID assignedTo, String resolutionSummary, String closureReason) {
    }

    T load(UUID id) {
        Map<String, Object> r = jdbc.sql("""
                SELECT t.id, t.number, t.subject, c.name AS category, t.status, t.requester_kind, t.requester_id, t.requester_name, t.requester_email,
                       t.assigned_to, t.resolution_summary, t.closure_reason
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id WHERE t.id = :id
                """).param("id", id).query().singleRow();
        return new T((UUID) r.get("id"), (String) r.get("number"), (String) r.get("subject"), (String) r.get("category"), (String) r.get("status"),
                (String) r.get("requester_kind"), (UUID) r.get("requester_id"), (String) r.get("requester_name"), (String) r.get("requester_email"),
                (UUID) r.get("assigned_to"), (String) r.get("resolution_summary"), (String) r.get("closure_reason"));
    }

    private String trackingLines(T t) {
        return "Track the ticket at " + portalUrl + "/track with the number and this email address, or sign in to the portal and open Support → My Tickets.\n";
    }

    private void toRequester(T t, String subject, String body) {
        if (t.requesterEmail() == null || t.requesterEmail().isBlank()) return;
        String kind = "STUDENT".equals(t.requesterKind()) ? "student" : "person";
        notices.queueEmail(t.requesterEmail(), subject, body, kind, t.requesterId(), List.of());
    }

    private void toPerson(UUID person, String subject, String body) {
        if (person == null) return;
        String email = jdbc.sql("SELECT email FROM iam.person WHERE id = :id").param("id", person).query(String.class).optional().orElse(null);
        if (email == null || email.isBlank()) return;
        notices.queueEmail(email, subject, body, "person", person, List.of());
    }

    /** everyone who holds the ICT Support Agent office or the Director's, today, and has an email */
    private List<Map<String, Object>> desk() {
        return jdbc.sql("""
                SELECT DISTINCT p.id, p.email FROM iam.person p JOIN iam.office_assignment a ON a.person_id = p.id
                 WHERE a.office_code IN ('ictagent','ict') AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                   AND p.email IS NOT NULL AND btrim(p.email) <> '' AND p.ended_on IS NULL
                """).query().listOfRows();
    }

    private String deskLink(T t) {
        return portalUrl + "/helpdesk/tickets/" + t.id();
    }

    /* ── the events ── */

    void submitted(UUID id) {
        T t = load(id);
        toRequester(t, "ICT Support Ticket Received — " + t.number(),
                "Dear " + t.requesterName() + ",\n\nYour ticket has been received by the Directorate of ICT.\n\n"
                        + "Ticket number: " + t.number() + "\nSubject: " + t.subject() + "\nCategory: " + t.category() + "\nSubmitted: " + java.time.LocalDate.now() + "\n\n"
                        + "Quote the ticket number in any follow-up. You will be told when the desk opens it, when work begins, and when it is resolved.\n"
                        + trackingLines(t) + "\nDirectorate of ICT");
        boolean tellDesk = jdbc.sql("SELECT notify_agents_on_new FROM helpdesk.setting WHERE row_no").query(Boolean.class).optional().orElse(true);
        if (tellDesk) {
            for (Map<String, Object> p : desk()) {
                notices.queueEmail((String) p.get("email"), "New ICT support ticket " + t.number() + " — " + t.category(),
                        t.number() + " from " + t.requesterName() + ": " + t.subject() + "\n\nOpen it: " + deskLink(t) + "\n", "person", (UUID) p.get("id"), List.of());
            }
        }
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
            case "OPENED" -> "has been opened by the ICT desk";
            case "IN_PROGRESS" -> "is being worked on";
            case "REOPENED" -> "has been reopened";
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

    void reopened(UUID id, String reason) {
        T t = load(id);
        String body = t.number() + " from " + t.requesterName() + " (" + t.category() + ") has been reopened: " + reason + "\n\nOpen it: " + deskLink(t) + "\n";
        if (t.assignedTo() != null) {
            toPerson(t.assignedTo(), "Ticket reopened — " + t.number(), body);
        } else {
            for (Map<String, Object> p : desk()) {
                notices.queueEmail((String) p.get("email"), "Ticket reopened — " + t.number(), body, "person", (UUID) p.get("id"), List.of());
            }
        }
    }

    void agentUpdate(UUID id, String excerpt) {
        T t = load(id);
        toRequester(t, "The ICT desk has an update on " + t.number(),
                "On your ticket " + t.number() + " (" + t.subject() + "), the ICT desk says:\n\n" + excerpt + "\n\n" + trackingLines(t) + "\nDirectorate of ICT");
    }

    void requesterUpdate(UUID id, String excerpt) {
        T t = load(id);
        String body = t.requesterName() + " added to " + t.number() + " (" + t.subject() + "):\n\n" + excerpt + "\n\nOpen it: " + deskLink(t) + "\n";
        if (t.assignedTo() != null) {
            toPerson(t.assignedTo(), "Update from the requester — " + t.number(), body);
        }
    }
}
