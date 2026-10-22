package ng.edu.moaum.portal.auditlog;

import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.format.annotation.DateTimeFormat;
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
    private final AuditTilesCache tilesCache;

    AuditLogController(JdbcClient jdbc, AuditChainVerifier verifier, AuditTilesCache tilesCache) {
        this.jdbc = jdbc;
        this.verifier = verifier;
        this.tilesCache = tilesCache;
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
     * so a filter costs the same on a trail of any size. V627: within the dates and the people asked for, when they are.
     */
    static final int FILTER_WINDOW = 50_000;

    /** midnight in Lagos as a timestamptz: "today" on the tiles starts there, not at the database's UTC midnight (V539's rule) */
    static final String LAGOS_MIDNIGHT = "((now() AT TIME ZONE 'Africa/Lagos')::date::timestamp AT TIME ZONE 'Africa/Lagos')";

    /** V627: the people a "who" may name — at most this many, the trail read for each from the end of their own index */
    static final int WHO_MATCHES = 10;

    /**
     * V627: what a read is limited to — a Lagos date range (from and to inclusive) and the people a "who" named (staff and
     * students, by id). Each source is then read from the end of its index within those limits: audit.entries by time
     * (ix_entries_recent) or by actor (ix_entries_actor), the sign-ins by time or by person (V627's indexes).
     */
    record Scope(LocalDate from, LocalDate to, List<String> people) {
        boolean byPerson() {
            return people != null;
        }

        String time(String column) {
            List<String> c = new ArrayList<>();
            if (from != null) {
                c.add(column + " >= (CAST(:from AS date)::timestamp AT TIME ZONE 'Africa/Lagos')");
            }
            if (to != null) {
                c.add(column + " < ((CAST(:to AS date) + 1)::timestamp AT TIME ZONE 'Africa/Lagos')");
            }
            return c.isEmpty() ? "" : " AND " + String.join(" AND ", c);
        }

        String ids() {
            return "{" + String.join(",", people) + "}";
        }
    }

    /** the latest entries of the trail (attributed writes, staff sign-ins, student sign-ins), each source read from the end of its index */
    private static String recent(String limit, Scope scope) {
        String audit = "SELECT e.occurred_at, e.actor_id, e.actor_office, e.action, e.subject_type, e.subject_id, e.reason, e.correlation_id, "
                + "'audit'::text AS src FROM audit.entries e";
        String staff = "SELECT se.at, se.person_id, NULL::text, 'auth:' || se.outcome, 'sign_in'::text, se.person_id, "
                + "se.username || coalesce(' from ' || host(se.source_ip), ''), NULL::uuid, 'staff'::text FROM iam.sign_in_event se";
        String student = "SELECT st.at, st.student_id, NULL::text, 'auth:' || st.outcome, 'student_sign_in'::text, st.student_id, "
                + "st.identifier || coalesce(' from ' || st.ip, ''), NULL::uuid, 'student'::text FROM iam.student_event st";
        if (scope.byPerson()) {
            // one person at a time, each from the end of their own index, then the newest of them all
            audit = "SELECT x.* FROM unnest(CAST(:people AS uuid[])) w(id) CROSS JOIN LATERAL (" + audit
                    + " WHERE e.actor_id = w.id" + scope.time("e.occurred_at") + " ORDER BY e.occurred_at DESC LIMIT " + limit + ") x";
            staff = "SELECT x.* FROM unnest(CAST(:people AS uuid[])) w(id) CROSS JOIN LATERAL (" + staff
                    + " WHERE se.person_id = w.id" + scope.time("se.at") + " ORDER BY se.at DESC LIMIT " + limit + ") x";
            student = "SELECT x.* FROM unnest(CAST(:people AS uuid[])) w(id) CROSS JOIN LATERAL (" + student
                    + " WHERE st.student_id = w.id" + scope.time("st.at") + " ORDER BY st.at DESC LIMIT " + limit + ") x";
            return """
                    SELECT * FROM (
                        (%s ORDER BY 1 DESC LIMIT %s)
                        UNION ALL
                        (%s ORDER BY 1 DESC LIMIT %s)
                        UNION ALL
                        (%s ORDER BY 1 DESC LIMIT %s)
                    ) u ORDER BY u.occurred_at DESC LIMIT %s
                    """.formatted(audit, limit, staff, limit, student, limit, limit);
        }
        return """
                SELECT * FROM (
                    (%s WHERE true%s ORDER BY e.occurred_at DESC LIMIT %s)
                    UNION ALL
                    (%s WHERE true%s ORDER BY se.at DESC LIMIT %s)
                    UNION ALL
                    (%s WHERE true%s ORDER BY st.at DESC LIMIT %s)
                ) u ORDER BY u.occurred_at DESC LIMIT %s
                """.formatted(audit, scope.time("e.occurred_at"), limit, staff, scope.time("se.at"), limit,
                student, scope.time("st.at"), limit, limit);
    }

    /** a statement over the scope, its dates and people bound */
    private JdbcClient.StatementSpec bound(String sql, Scope scope) {
        JdbcClient.StatementSpec q = jdbc.sql(sql);
        if (scope.from() != null) {
            q = q.param("from", scope.from().toString());
        }
        if (scope.to() != null) {
            q = q.param("to", scope.to().toString());
        }
        if (scope.byPerson()) {
            q = q.param("people", scope.ids());
        }
        return q;
    }

    /**
     * V627: the people a "who" names — staff by staff number, name or id, students by matriculation number, name or id; at most
     * WHO_MATCHES, staff first. Null when no "who" was asked; an empty list when it names nobody.
     */
    private List<Map<String, Object>> people(String who) {
        if (who == null || who.isBlank()) {
            return null;
        }
        return jdbc.sql("""
                SELECT id, name, kind, number FROM (
                    SELECT p.id, p.surname || ', ' || p.given_names AS name, 'staff' AS kind, p.staff_number AS number, 0 AS o
                      FROM iam.person p
                     WHERE p.id::text = :w OR upper(p.staff_number) = upper(:w)
                        OR (p.surname || ' ' || p.given_names) ILIKE '%' || :w || '%' OR (p.given_names || ' ' || p.surname) ILIKE '%' || :w || '%'
                    UNION ALL
                    SELECT s.id, s.surname || ', ' || s.other_names, 'student', s.matric_no, 1
                      FROM people.student s
                     WHERE s.id::text = :w OR upper(s.matric_no) = upper(:w)
                        OR (s.surname || ' ' || s.other_names) ILIKE '%' || :w || '%' OR (s.other_names || ' ' || s.surname) ILIKE '%' || :w || '%'
                ) x ORDER BY o, name LIMIT :n
                """).param("w", who.trim()).param("n", WHO_MATCHES).query().listOfRows();
    }

    private static Scope scope(LocalDate from, LocalDate to, List<Map<String, Object>> people) {
        return new Scope(from, to, people == null ? null : people.stream().map(m -> String.valueOf(m.get("id"))).collect(Collectors.toList()));
    }

    @GetMapping("/entries")
    @PreAuthorize(OVERSIGHT)
    @Transactional(readOnly = true)
    Map<String, Object> entries(@RequestParam(required = false) String action,
                                @RequestParam(required = false) String office,
                                @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                                @RequestParam(required = false) String who,
                                @RequestParam(defaultValue = "200") int limit) {
        int lim = Math.max(1, Math.min(limit, 500));
        String act = action == null || action.isBlank() ? null : action.trim();
        String off = office == null || office.isBlank() ? null : office.trim();
        List<Map<String, Object>> named = people(who);
        Scope scope = scope(from, to, named);
        boolean filtered = act != null || off != null;
        List<Map<String, Object>> rows = List.of();
        if (named == null || !named.isEmpty()) {
            // unfiltered: the latest :lim of each source within the scope; filtered: the latest FILTER_WINDOW of it, then the filter
            rows = bound("""
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
                    """.formatted(recent(filtered ? String.valueOf(FILTER_WINDOW) : String.valueOf(lim), scope)), scope)
                    .param("action", act, Types.VARCHAR)
                    .param("office", off, Types.VARCHAR)
                    .param("lim", lim).query().listOfRows();
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("tiles", tilesCache.get(this::tiles));
        out.put("entries", rows);
        out.put("filterWindow", FILTER_WINDOW);
        out.put("who", named);
        return out;
    }

    /** the tiles: the total from the chain (V623 audit.entry_count), today's (since midnight in Lagos) from the end of the indexes */
    private Map<String, Object> tiles() {
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
        return tiles;
    }

    /** the actions and offices present in the latest FILTER_WINDOW entries of the trail within the scope, for the filters */
    @GetMapping("/facets")
    @PreAuthorize(OVERSIGHT)
    @Transactional(readOnly = true)
    Map<String, Object> facets(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                               @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                               @RequestParam(required = false) String who) {
        List<Map<String, Object>> named = people(who);
        Scope scope = scope(from, to, named);
        List<Map<String, Object>> actions = List.of();
        List<Map<String, Object>> offices = List.of();
        if (named == null || !named.isEmpty()) {
            String window = recent(String.valueOf(FILTER_WINDOW), scope);
            actions = bound("""
                    SELECT split_part(r.action, ':', 1) AS domain, count(*) AS n FROM (%s) r
                     GROUP BY 1 ORDER BY n DESC, 1 LIMIT 30
                    """.formatted(window), scope).query().listOfRows();
            offices = bound("""
                    SELECT r.actor_office, count(*) AS n FROM (%s) r
                     WHERE r.src = 'audit'
                     GROUP BY 1 ORDER BY n DESC, 1 LIMIT 30
                    """.formatted(window), scope).query().listOfRows();
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("actions", actions);
        out.put("offices", offices);
        out.put("window", FILTER_WINDOW);
        return out;
    }
}
