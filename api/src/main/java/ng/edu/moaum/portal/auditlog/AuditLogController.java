package ng.edu.moaum.portal.auditlog;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** A read over the audit spine (audit.entries). */
@RestController
@RequestMapping("/api/v1/audit")
class AuditLogController {

    private static final String OVERSIGHT = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_audit','OFFICE_deputyaudit','OFFICE_vc')";

    private final JdbcClient jdbc;

    AuditLogController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/entries")
    @PreAuthorize(OVERSIGHT)
    @Transactional(readOnly = true)
    Map<String, Object> entries(@RequestParam(required = false) String action,
                                @RequestParam(required = false) String office,
                                @RequestParam(defaultValue = "200") int limit) {
        int lim = Math.max(1, Math.min(limit, 500));
        // the trail is attributed writes AND sign-ins: staff (iam.sign_in_event) and students (iam.student_event)
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT * FROM (
                    SELECT e.occurred_at, e.actor_id, e.actor_office, e.action, e.subject_type, e.subject_id, e.reason, e.correlation_id,
                           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS actor_name
                      FROM audit.entries e
                      LEFT JOIN iam.person p ON p.id = e.actor_id
                     WHERE (:action::text IS NULL OR e.action ILIKE :action || '%')
                       AND (:office::text IS NULL OR e.actor_office = :office)
                    UNION ALL
                    SELECT se.at, se.person_id, NULL::text, 'auth:' || se.outcome, 'sign_in'::text, se.person_id,
                           se.username || coalesce(' from ' || host(se.source_ip), ''), NULL::uuid,
                           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
                      FROM iam.sign_in_event se
                      LEFT JOIN iam.person p ON p.id = se.person_id
                     WHERE :office::text IS NULL AND (:action::text IS NULL OR ('auth:' || se.outcome) ILIKE :action || '%')
                    UNION ALL
                    SELECT st.at, st.student_id, NULL::text, 'auth:' || st.outcome, 'student_sign_in'::text, st.student_id,
                           st.identifier || coalesce(' from ' || st.ip, ''), NULL::uuid,
                           CASE WHEN s.id IS NULL THEN NULL ELSE s.surname || ', ' || s.other_names END
                      FROM iam.student_event st
                      LEFT JOIN people.student s ON s.id = st.student_id
                     WHERE :office::text IS NULL AND (:action::text IS NULL OR ('auth:' || st.outcome) ILIKE :action || '%')
                ) x
                 ORDER BY x.occurred_at DESC
                 LIMIT :lim
                """).param("action", action == null || action.isBlank() ? null : action.trim(), Types.VARCHAR)
                .param("office", office == null || office.isBlank() ? null : office.trim(), Types.VARCHAR)
                .param("lim", lim).query().listOfRows();

        Map<String, Object> tiles = new LinkedHashMap<>();
        tiles.put("total", jdbc.sql("SELECT (SELECT count(*) FROM audit.entries) + (SELECT count(*) FROM iam.sign_in_event) + (SELECT count(*) FROM iam.student_event)").query(Long.class).single());
        tiles.put("today", jdbc.sql("""
                SELECT (SELECT count(*) FROM audit.entries WHERE occurred_at >= current_date)
                     + (SELECT count(*) FROM iam.sign_in_event WHERE at >= current_date)
                     + (SELECT count(*) FROM iam.student_event WHERE at >= current_date)
                """).query(Long.class).single());
        tiles.put("actorsToday", jdbc.sql("""
                SELECT count(DISTINCT a) FROM (
                    SELECT actor_id a FROM audit.entries WHERE occurred_at >= current_date AND actor_id IS NOT NULL
                    UNION SELECT person_id FROM iam.sign_in_event WHERE at >= current_date AND person_id IS NOT NULL
                    UNION SELECT student_id FROM iam.student_event WHERE at >= current_date AND student_id IS NOT NULL) z
                """).query(Long.class).single());
        tiles.put("refusalsToday", jdbc.sql("""
                SELECT (SELECT count(*) FROM audit.entries WHERE occurred_at >= current_date AND action ILIKE '%REFUS%')
                     + (SELECT count(*) FROM iam.sign_in_event WHERE at >= current_date AND outcome IN ('BAD_PASSWORD','UNKNOWN','LOCKED'))
                     + (SELECT count(*) FROM iam.student_event WHERE at >= current_date AND outcome IN ('BAD_PASSWORD','UNKNOWN','LOCKED','NO_ACCOUNT'))
                """).query(Long.class).single());

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("tiles", tiles);
        out.put("entries", rows);
        return out;
    }

    /** the actions and offices present, for the filters */
    @GetMapping("/facets")
    @PreAuthorize(OVERSIGHT)
    @Transactional(readOnly = true)
    Map<String, Object> facets() {
        List<Map<String, Object>> actions = jdbc.sql("""
                SELECT domain, count(*) AS n FROM (
                    SELECT split_part(action, ':', 1) AS domain FROM audit.entries WHERE occurred_at >= current_date - 30
                    UNION ALL SELECT 'auth' FROM iam.sign_in_event WHERE at >= current_date - 30
                    UNION ALL SELECT 'auth' FROM iam.student_event WHERE at >= current_date - 30) d
                 GROUP BY domain ORDER BY n DESC LIMIT 30
                """).query().listOfRows();
        List<Map<String, Object>> offices = jdbc.sql("""
                SELECT actor_office, count(*) AS n FROM audit.entries WHERE occurred_at >= current_date - 30
                 GROUP BY actor_office ORDER BY n DESC LIMIT 30
                """).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("actions", actions);
        out.put("offices", offices);
        return out;
    }
}
