package ng.edu.moaum.portal.platform;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * A staff member's own notifications: every notice the portal queued for them — filed against their
 * person, or addressed to the email or phone on their record — read back from the outbox that sent it.
 * The same notice the email carried, so the in-app list and the inbox never disagree. Never another
 * person's; read-only. Students read theirs on the student portal.
 */
@RestController
@RequestMapping("/api/v1/me/notices")
class MeNoticesController {

    private final JdbcClient jdbc;

    MeNoticesController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    @PreAuthorize("isAuthenticated() and !hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine(@RequestParam(defaultValue = "100") int limit) {
        UUID me = AuditContextHolder.required().actorId();
        return jdbc.sql("""
                SELECT n.id, n.channel, n.subject, n.body, n.about_kind, n.about_id, n.created_at, n.state, n.sent_at
                  FROM platform.notice n
                 WHERE (n.about_kind = 'person' AND n.about_id = :me)
                    OR n.recipient IN (SELECT lower(p.email) FROM iam.person p WHERE p.id = :me AND p.email IS NOT NULL
                                       UNION SELECT p.phone FROM iam.person p WHERE p.id = :me AND p.phone IS NOT NULL)
                 ORDER BY n.created_at DESC
                 LIMIT :n
                """).param("me", me).param("n", Math.max(1, Math.min(limit, 500))).query().listOfRows();
    }
}
