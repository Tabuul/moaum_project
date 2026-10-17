package ng.edu.moaum.portal.helpdesk;

import java.security.SecureRandom;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.auth.TokenIssuer;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import static ng.edu.moaum.portal.helpdesk.SupportAccess.AGENTS;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.can;

/**
 * ICT Support opens a student's portal as the student, read-only (V521): from the support record, without the student's password,
 * every agent in service (the support baseline) opens the portal of a student they reach and sees what the student sees — for
 * thirty minutes, with a reason and, where there is one, the student's ticket. The session is the portal's own
 * (helpdesk.open_portal_view: a platform session of the student's, the support view, the act on the support ledger); its token names
 * the agent, so the API refuses every change made with it and runs its reads read-only. The agent leaves when done; the session
 * lapses on its own otherwise. The student's password is never read, shown or changed, and their own sessions are untouched.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/support")
class StudentPortalViewController {

    static final int MINUTES = 30;

    public record ViewIn(@NotBlank @Size(min = 10, max = 500) String reason, UUID ticket) {
    }

    private final JdbcClient jdbc;
    private final SupportAccess support;
    private final TokenIssuer tokens;
    private final SecureRandom random = new SecureRandom();

    StudentPortalViewController(JdbcClient jdbc, SupportAccess support, TokenIssuer tokens) {
        this.jdbc = jdbc;
        this.support = support;
        this.tokens = tokens;
    }

    /** the agent opens the student's portal: the token of a read-only session as the student, and what it is */
    @PostMapping("/students/{id}/portal-view")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> open(Authentication auth, @PathVariable UUID id, @Valid @RequestBody ViewIn body) {
        SupportAccess.Access a = support.on(auth, id);   // a student outside the agent's reach is not found
        can(a, "VIEW_STUDENT_PORTAL");
        UUID ticket = support.ticketFor(a, body.ticket(), id, false);
        if (!tokens.available()) {
            throw new DomainRuleViolation("SUPPORT_VIEW_ELSEWHERE", "This portal verifies tokens issued by the University's identity provider; a student view cannot be opened here.",
                    new DomainRuleViolation.Remedy("Open the support record instead.", "Directorate of ICT"));
        }
        byte[] sid = new byte[32];
        random.nextBytes(sid);
        Map<String, Object> view = jsonOf(jdbc.sql("SELECT helpdesk.open_portal_view(:s, :t, :r, :sid, :m)::text")
                .param("s", id).param("t", ticket, java.sql.Types.OTHER).param("r", body.reason().trim()).param("sid", sid).param("m", MINUTES)
                .query(String.class).single());
        Instant ends = OffsetDateTime.parse(String.valueOf(view.get("endsAt"))).toInstant();
        Map<String, Object> out = new LinkedHashMap<>(view);
        out.put("token", tokens.issueSupportView(id, String.valueOf(view.get("name")), sid, ends, a.agent()));
        out.put("studentId", id);
        out.put("minutes", MINUTES);
        return out;
    }

    /** the agent leaves the student's portal: the session ends with the view (the agent who opened it, or the desk's head) */
    @PostMapping("/portal-views/{view}/end")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> end(@PathVariable UUID view) {
        Boolean ended = jdbc.sql("SELECT helpdesk.end_portal_view(:v, 'left by the agent')").param("v", view).query(Boolean.class).single();
        return Map.of("ended", Boolean.TRUE.equals(ended));
    }

    /** the support views of a student's portal, newest first */
    @GetMapping("/students/{id}/portal-views")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> views(Authentication auth, @PathVariable UUID id) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "VIEW_STUDENT");
        return jdbc.sql("""
                SELECT v.id, v.opened_at, v.ends_at, v.ended_at, v.ended_reason, v.reason, v.agent_office, helpdesk.person_name(v.agent_id) AS agent,
                       t.number AS ticket_number
                  FROM helpdesk.portal_view v LEFT JOIN helpdesk.ticket t ON t.id = v.ticket_id
                 WHERE v.student_id = :s ORDER BY v.opened_at DESC LIMIT 50
                """).param("s", id).query().listOfRows();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> jsonOf(String text) {
        return new tools.jackson.databind.ObjectMapper().readValue(text, Map.class);
    }
}
