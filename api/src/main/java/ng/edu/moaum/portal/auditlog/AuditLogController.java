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

    private static final String OVERSIGHT = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_audit','OFFICE_deputyaudit','OFFICE_vc','OFFICE_registrar','OFFICE_dvc')";

    private final JdbcClient jdbc;
    private final AuditChainVerifier verifier;

    AuditLogController(JdbcClient jdbc, AuditChainVerifier verifier) {
        this.jdbc = jdbc;
        this.verifier = verifier;
    }

    /** the chain's verification (V286): the last runs, nightly and on demand, with any break named */
    @GetMapping("/chain")
    @PreAuthorize(OVERSIGHT)
    @Transactional(readOnly = true)
    Map<String, Object> chain() {
        return verifier.status();
    }

    /** the chain recomputed now, by the desk; the same run the night makes */
    @org.springframework.web.bind.annotation.PostMapping("/chain/verify")
    @PreAuthorize(OVERSIGHT)
    Map<String, Object> verifyNow() {
        return verifier.run("ON_DEMAND");
    }

    /**
     * V623: how far back the filters (and the counts beside them) read — the latest entries of the trail, never the whole of it,
     * so a filter costs the same on a trail of any size
     */
    static final int FILTER_WINDOW = 50_000;

    /** midnight in Lagos as a timestamptz: "today" on the tiles starts there, not at the database's UTC midnight (V539's rule) */
    static final String LAGOS_MIDNIGHT = "((now() AT TIME ZONE 'Africa/Lagos')::date::timestamp AT TIME ZONE 'Africa/Lagos')";

    /** the latest entries of the trail (attributed writes, staff sign-ins, student sign-ins), each source read from the end of its index */
    private static String recent(String limit) {
        return """
                SELECT * FROM (
                    (SELECT e.occurred_at, e.actor_id, e.actor_office, e.action, e.subject_type, e.subject_id, e.reason, e.correlation_id,
                            'audit'::text AS src
                       FROM audit.entries e ORDER BY e.occurred_at DESC LIMIT %1$s)
                    UNION ALL
                    (SELECT se.at, se.person_id, NULL::text, 'auth:' || se.outcome, 'sign_in'::text, se.person_id,
                            se.username || coalesce(' from ' || host(se.source_ip), ''), NULL::uuid, 'staff'::text
                       FROM iam.sign_in_event se ORDER BY se.at DESC LIMIT %1$s)
                    UNION ALL
                    (SELECT st.at, st.student_id, NULL::text, 'auth:' || st.outcome, 'student_sign_in'::text, st.student_id,
                            st.identifier || coalesce(' from ' || st.ip, ''), NULL::uuid, 'student'::text
                       FROM iam.student_event st ORDER BY st.at DESC LIMIT %1$s)
                ) u ORDER BY u.occurred_at DESC LIMIT %1$s
                """.formatted(limit);
    }

    @GetMapping("/entries")
    @PreAuthorize(OVERSIGHT)
    @Transactional(readOnly = true)
    Map<String, Object> entries(@RequestParam(required = false) String action,
                                @RequestParam(required = false) String office,
                                @RequestParam(defaultValue = "200") int limit) {
        int lim = Math.max(1, Math.min(limit, 500));
        String act = action == null || action.isBlank() ? null : action.trim();
        String off = office == null || office.isBlank() ? null : office.trim();
        boolean filtered = act != null || off != null;
        // unfiltered: the latest :lim of each source; filtered: the latest FILTER_WINDOW of the trail, then the filter (V623)
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT x.occurred_at, x.actor_id, x.actor_office, x.action, x.subject_type, x.subject_id, x.reason, x.correlation_id,
                       CASE WHEN x.src = 'student' THEN s.surname || ', ' || s.other_names
                            WHEN p.id IS NOT NULL THEN p.surname || ', ' || p.given_names END AS actor_name
                  FROM (%s) x
                  LEFT JOIN iam.person p ON x.src <> 'student' AND p.id = x.actor_id
                  LEFT JOIN people.student s ON x.src = 'student' AND s.id = x.actor_id
                 WHERE (:action::text IS NULL OR x.action ILIKE :action || '%%')
                   AND (:office::text IS NULL OR x.actor_office = :office)
                 ORDER BY x.occurred_at DESC
                 LIMIT :lim
                """.formatted(recent(filtered ? ":window" : ":lim")))
                .param("action", act, Types.VARCHAR)
                .param("office", off, Types.VARCHAR)
                .param("window", FILTER_WINDOW)
                .param("lim", lim).query().listOfRows();

        // the tiles: the total from the chain (V623 audit.entry_count), today's (since midnight in Lagos) from the end of the indexes
        Map<String, Object> tiles = new LinkedHashMap<>();
        tiles.put("total", jdbc.sql("SELECT audit.entry_count() + (SELECT count(*) FROM iam.sign_in_event) + (SELECT count(*) FROM iam.student_event)").query(Long.class).single());
        tiles.put("today", jdbc.sql("""
                SELECT (SELECT count(*) FROM audit.entries WHERE occurred_at >= %1$s)
                     + (SELECT count(*) FROM iam.sign_in_event WHERE at >= %1$s)
                     + (SELECT count(*) FROM iam.student_event WHERE at >= %1$s)
                """.formatted(LAGOS_MIDNIGHT)).query(Long.class).single());
        tiles.put("actorsToday", jdbc.sql("""
                SELECT count(DISTINCT a) FROM (
                    SELECT actor_id a FROM audit.entries WHERE occurred_at >= %1$s AND actor_id IS NOT NULL
                    UNION SELECT person_id FROM iam.sign_in_event WHERE at >= %1$s AND person_id IS NOT NULL
                    UNION SELECT student_id FROM iam.student_event WHERE at >= %1$s AND student_id IS NOT NULL) z
                """.formatted(LAGOS_MIDNIGHT)).query(Long.class).single());
        tiles.put("refusalsToday", jdbc.sql("""
                SELECT (SELECT count(*) FROM audit.entries WHERE occurred_at >= %1$s AND action ILIKE '%%REFUS%%')
                     + (SELECT count(*) FROM iam.sign_in_event WHERE at >= %1$s AND outcome IN ('BAD_PASSWORD','UNKNOWN','LOCKED'))
                     + (SELECT count(*) FROM iam.student_event WHERE at >= %1$s AND outcome IN ('BAD_PASSWORD','UNKNOWN','LOCKED','NO_ACCOUNT'))
                """.formatted(LAGOS_MIDNIGHT)).query(Long.class).single());

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("tiles", tiles);
        out.put("entries", rows);
        out.put("filterWindow", FILTER_WINDOW);
        return out;
    }

    /** the actions and offices present in the latest FILTER_WINDOW entries of the trail, for the filters (V623: not thirty days of it) */
    @GetMapping("/facets")
    @PreAuthorize(OVERSIGHT)
    @Transactional(readOnly = true)
    Map<String, Object> facets() {
        String window = recent(":window");
        List<Map<String, Object>> actions = jdbc.sql("""
                SELECT split_part(r.action, ':', 1) AS domain, count(*) AS n FROM (%s) r
                 GROUP BY 1 ORDER BY n DESC, 1 LIMIT 30
                """.formatted(window)).param("window", FILTER_WINDOW).query().listOfRows();
        List<Map<String, Object>> offices = jdbc.sql("""
                SELECT r.actor_office, count(*) AS n FROM (%s) r
                 WHERE r.src = 'audit'
                 GROUP BY 1 ORDER BY n DESC, 1 LIMIT 30
                """.formatted(window)).param("window", FILTER_WINDOW).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("actions", actions);
        out.put("offices", offices);
        out.put("window", FILTER_WINDOW);
        return out;
    }
}
