package ng.edu.moaum.portal.platform;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * A staff member's own notifications: every notice the portal queued for them — filed against their
 * person, or addressed to the email or phone on their record — read back from the outbox that sent it.
 * The same notice the email carried, so the in-app list and the inbox never disagree. Never another
 * person's. Students read theirs on the student portal.
 * <p>
 * V425: the portal channel — a notice delivered on the dashboard itself — with how many are unread (the
 * bell), and marking one or all of them read.
 * <p>
 * V749: the list is platform.person_notices — by address only for the e-mail the person verified (and,
 * for the notices of their work — an office's notice among them, never an applicant's own message or a
 * sign-in ticket's reply — an address or phone no other record holds), newest first and stopping at the
 * limit however many a person has been sent, and never a message that
 * carries a code or a link for its mailbox alone (a verification or confirmation code, a password reset or
 * first sign-in link): an address typed on someone's record no longer shows them another person's mail,
 * and a code is proved by the mailbox, never read back from the portal.
 */
@RestController
@RequestMapping("/api/v1/me/notices")
@PreAuthorize("isAuthenticated() and !hasAuthority('OFFICE_student')")
class MeNoticesController {

    private final JdbcClient jdbc;

    MeNoticesController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine(@RequestParam(defaultValue = "100") int limit) {
        UUID me = AuditContextHolder.required().actorId();
        return jdbc.sql("""
                SELECT id, channel, subject, body, about_kind, about_id, created_at, state, sent_at, priority, template_key, read_at
                  FROM platform.person_notices(:me, :n)
                """).param("me", me).param("n", Math.max(1, Math.min(limit, 500))).query().listOfRows();
    }

    /** the bell: how many portal notices the person has not opened, and the latest few */
    @GetMapping("/unread")
    @Transactional(readOnly = true)
    Map<String, Object> unread() {
        UUID me = AuditContextHolder.required().actorId();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("unread", jdbc.sql("SELECT platform.unread_count('person', :me)").param("me", me).query(Integer.class).single());
        out.put("latest", jdbc.sql("SELECT id, subject, body, priority, template_key, created_at, read_at FROM platform.portal_notices('person', :me, 5)")
                .param("me", me).query().listOfRows());
        return out;
    }

    @PostMapping("/{id}/read")
    @Transactional
    Map<String, Object> read(@PathVariable UUID id) {
        UUID me = AuditContextHolder.required().actorId();
        boolean ok = Boolean.TRUE.equals(jdbc.sql("SELECT platform.mark_notice_read(:n, 'person', :me)").param("n", id).param("me", me).query(Boolean.class).single());
        return Map.of("read", ok, "unread", jdbc.sql("SELECT platform.unread_count('person', :me)").param("me", me).query(Integer.class).single());
    }

    @PostMapping("/read-all")
    @Transactional
    Map<String, Object> readAll() {
        UUID me = AuditContextHolder.required().actorId();
        int n = jdbc.sql("SELECT platform.mark_all_read('person', :me)").param("me", me).query(Integer.class).single();
        return Map.of("marked", n, "unread", 0);
    }

    /** V426: the person's own switches for e-mail and SMS on optional messages; mandatory ones are always sent */
    @GetMapping("/preferences")
    @Transactional(readOnly = true)
    Map<String, Object> preferences() {
        return preferencesOf(AuditContextHolder.required().actorId());
    }

    record PreferencesIn(Boolean email, Boolean sms) {
    }

    @PutMapping("/preferences")
    @Transactional
    Map<String, Object> savePreferences(@RequestBody PreferencesIn in) {
        UUID me = AuditContextHolder.required().actorId();
        if (in != null && in.email() != null) {
            jdbc.sql("SELECT platform.set_preference('person', :me, 'EMAIL', :on)").param("me", me).param("on", in.email()).query().listOfRows();
        }
        if (in != null && in.sms() != null) {
            jdbc.sql("SELECT platform.set_preference('person', :me, 'SMS', :on)").param("me", me).param("on", in.sms()).query().listOfRows();
        }
        return preferencesOf(me);
    }

    private Map<String, Object> preferencesOf(UUID me) {
        Map<String, Object> out = new LinkedHashMap<>();
        for (Map<String, Object> r : jdbc.sql("SELECT channel, enabled FROM platform.preferences('person', :me)").param("me", me).query().listOfRows()) {
            out.put(String.valueOf(r.get("channel")).toLowerCase(), r.get("enabled"));
        }
        return out;
    }
}
