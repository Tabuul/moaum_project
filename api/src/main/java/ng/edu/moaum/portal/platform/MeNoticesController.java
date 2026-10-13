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
                SELECT n.id, n.channel, n.subject, n.body, n.about_kind, n.about_id, n.created_at, n.state, n.sent_at, n.priority, n.template_key,
                       r.read_at
                  FROM platform.notice n LEFT JOIN platform.notice_read r ON r.notice_id = n.id
                 WHERE (n.about_kind = 'person' AND n.about_id = :me)
                    OR n.recipient IN (SELECT lower(p.email) FROM iam.person p WHERE p.id = :me AND p.email IS NOT NULL
                                       UNION SELECT p.phone FROM iam.person p WHERE p.id = :me AND p.phone IS NOT NULL)
                 ORDER BY n.created_at DESC
                 LIMIT :n
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
}
