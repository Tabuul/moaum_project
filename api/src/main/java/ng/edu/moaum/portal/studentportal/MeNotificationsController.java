package ng.edu.moaum.portal.studentportal;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V425: the student's own notifications on the portal channel — the bell's unread count, the list, marking read — and where
 * their biodata stands (UP_TO_DATE · INCOMPLETE · REVIEW_REQUIRED · OUTDATED) with the student's own confirmation that the
 * record is correct. Everything here is the signed-in student's and nobody else's.
 */
@RestController
@RequestMapping("/api/v1/me")
@PreAuthorize("hasAuthority('OFFICE_student')")
class MeNotificationsController {

    private final JdbcClient jdbc;

    MeNotificationsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static UUID id(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/notifications")
    @Transactional(readOnly = true)
    Map<String, Object> notifications(Authentication auth, @RequestParam(defaultValue = "50") int limit) {
        UUID me = id(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("unread", jdbc.sql("SELECT platform.unread_count('student', :me)").param("me", me).query(Integer.class).single());
        out.put("notices", jdbc.sql("SELECT id, subject, body, priority, template_key, created_at, read_at FROM platform.portal_notices('student', :me, :n)")
                .param("me", me).param("n", Math.max(1, Math.min(limit, 200))).query().listOfRows());
        return out;
    }

    @GetMapping("/notifications/unread")
    @Transactional(readOnly = true)
    Map<String, Object> unread(Authentication auth) {
        UUID me = id(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("unread", jdbc.sql("SELECT platform.unread_count('student', :me)").param("me", me).query(Integer.class).single());
        out.put("latest", jdbc.sql("SELECT id, subject, body, priority, template_key, created_at, read_at FROM platform.portal_notices('student', :me, 5)")
                .param("me", me).query().listOfRows());
        return out;
    }

    @PostMapping("/notifications/{noticeId}/read")
    @Transactional
    Map<String, Object> read(Authentication auth, @PathVariable UUID noticeId) {
        UUID me = id(auth);
        boolean ok = Boolean.TRUE.equals(jdbc.sql("SELECT platform.mark_notice_read(:n, 'student', :me)").param("n", noticeId).param("me", me).query(Boolean.class).single());
        return Map.of("read", ok, "unread", jdbc.sql("SELECT platform.unread_count('student', :me)").param("me", me).query(Integer.class).single());
    }

    @PostMapping("/notifications/read-all")
    @Transactional
    Map<String, Object> readAll(Authentication auth) {
        UUID me = id(auth);
        int n = jdbc.sql("SELECT platform.mark_all_read('student', :me)").param("me", me).query(Integer.class).single();
        return Map.of("marked", n, "unread", 0);
    }

    /** where the student's biodata stands: the status, what is missing, when it last changed, when they last confirmed it */
    @GetMapping("/biodata-status")
    @Transactional(readOnly = true)
    Map<String, Object> biodataStatus(Authentication auth) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT status, required, completed, missing, missing_labels, last_updated, confirmed_at, migrated, last_reminded_at
                  FROM people.biodata_status(:me)
                """).param("me", id(auth)).query().listOfRows();
        return rows.isEmpty() ? Map.of("status", "UP_TO_DATE", "required", 0, "completed", 0) : rows.get(0);
    }

    /** the student's word that the record is correct as it stands; refused while a required item is missing (BIODATA_INCOMPLETE) */
    @PostMapping("/biodata/confirm")
    @Transactional
    Map<String, Object> confirm(Authentication auth) {
        UUID me = id(auth);
        jdbc.sql("SELECT people.confirm_biodata(:me, :me)").param("me", me).query().listOfRows();
        return biodataStatus(auth);
    }
}
