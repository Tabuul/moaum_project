package ng.edu.moaum.portal.finance;

import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Bursary's own audit trail and the users who hold its offices, for the Bursar's dashboard. The users: every person who holds,
 * or has held, the Bursar's office or the Students Account Officer's (the Bursary's sub-office) — the account, the posting, the
 * last sign-in, whether the account is locked, and how much they did. The trail: every change those people made acting under a
 * Bursary office (audit.entries — what, on which record, why, what changed) and their sign-ins (iam.sign_in_event), newest first,
 * filtered by person, office, date, kind of change, the record's kind or a word of the reason. Read through the actors' index, so
 * it stays quick however long the University's trail grows. The Bursar and Internal Audit read it; nothing is written.
 */
@RestController
@RequestMapping("/api/v1/finance/bursary")
class BursaryAuditController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    /** the Bursary's offices: the Bursar and the Students Account Officer */
    private static final String OFFICES = "ARRAY['bursar','studentaccounts']";
    private static final Set<String> OFFICE_CODES = Set.of("bursar", "studentaccounts");
    private static final Set<String> ACTIONS = Set.of("INSERT", "UPDATE", "DELETE");
    private static final Set<String> KINDS = Set.of("ALL", "CHANGES", "SIGN_INS");

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    BursaryAuditController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    /** the users with the Bursar's role (and the Students Account Officer's), those in post first */
    @GetMapping("/users")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> users() {
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH today AS (SELECT (now() AT TIME ZONE 'Africa/Lagos')::date AS d)
                SELECT p.id AS person_id, p.surname || ', ' || p.given_names AS name, p.staff_number, p.email, p.phone,
                       a.office_code, o.label AS office, a.scope_kind, a.scope_id, a.valid_from, a.valid_to, a.instrument,
                       (a.valid_from <= t.d AND (a.valid_to IS NULL OR a.valid_to >= t.d) AND p.ended_on IS NULL) AS in_post,
                       c.username, c.last_sign_in_at, (c.locked_until IS NOT NULL AND c.locked_until > now()) AS locked, c.must_change,
                       (SELECT count(*) FROM audit.entries e WHERE e.actor_id = p.id AND e.actor_office = a.office_code
                           AND e.occurred_at >= now() - interval '30 days') AS changes_30d,
                       (SELECT max(e.occurred_at) FROM audit.entries e WHERE e.actor_id = p.id AND e.actor_office = a.office_code) AS last_change_at,
                       (SELECT count(*) FROM iam.sign_in_event s WHERE s.person_id = p.id AND s.outcome IN ('BAD_PASSWORD', 'LOCKED')
                           AND s.at >= now() - interval '30 days') AS failed_sign_ins_30d
                  FROM iam.office_assignment a
                  JOIN iam.person p ON p.id = a.person_id
                  JOIN ref.office o ON o.code = a.office_code
                  LEFT JOIN iam.credential c ON c.person_id = p.id
                  CROSS JOIN today t
                 WHERE a.office_code = ANY (""" + OFFICES + """
                )
                 ORDER BY (a.valid_from <= t.d AND (a.valid_to IS NULL OR a.valid_to >= t.d) AND p.ended_on IS NULL) DESC,
                          (a.office_code = 'bursar') DESC, lower(p.surname), lower(p.given_names), a.valid_from DESC
                """).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("inPost", rows.stream().filter(r -> Boolean.TRUE.equals(r.get("in_post"))).map(r -> r.get("person_id")).distinct().count());
        out.put("bursars", rows.stream().filter(r -> Boolean.TRUE.equals(r.get("in_post")) && "bursar".equals(r.get("office_code"))).map(r -> r.get("person_id")).distinct().count());
        return out;
    }

    /** the Bursary's trail: the changes its people made under its offices, and their sign-ins, newest first, a page at a time */
    @GetMapping("/audit")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> audit(@RequestParam(required = false) UUID person, @RequestParam(required = false) String office,
                              @RequestParam(required = false) String kind, @RequestParam(required = false) String action,
                              @RequestParam(required = false) String subject, @RequestParam(required = false) String q,
                              @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                              @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        String off = blank(office) == null ? null : office.trim().toLowerCase();
        if (off != null && !OFFICE_CODES.contains(off)) off = null;
        String k = blank(kind) == null ? "ALL" : kind.trim().toUpperCase();
        if (!KINDS.contains(k)) k = "ALL";
        String act = blank(action) == null ? null : action.trim().toUpperCase();
        if (act != null && !ACTIONS.contains(act)) act = null;
        String like = blank(q) == null ? null : "%" + q.trim() + "%";
        int sz = Math.max(1, Math.min(size, 500));
        int pg = Math.max(1, page);
        boolean changes = !"SIGN_INS".equals(k);
        // a sign-in has no office, kind of change or record: a filter on those reads the changes only
        boolean signIns = !"CHANGES".equals(k) && off == null && act == null && blank(subject) == null && like == null;
        String sql = """
                WITH who AS (SELECT DISTINCT a.person_id FROM iam.office_assignment a WHERE a.office_code = ANY (""" + OFFICES + """
                )
                               AND (CAST(:person AS uuid) IS NULL OR a.person_id = CAST(:person AS uuid))),
                     t AS (
                    SELECT e.occurred_at AS at, 'CHANGE' AS kind, e.actor_id AS person_id, e.actor_office AS office, e.action, e.subject_type, e.subject_id,
                           e.reason, host(e.source_ip) AS source_ip,
                           CASE WHEN e.action = 'UPDATE' THEN (
                               SELECT coalesce(jsonb_agg(jsonb_build_object('field', c.k, 'before', e.before_state -> c.k, 'after', e.after_state -> c.k) ORDER BY c.k), '[]'::jsonb)
                                 FROM (SELECT x.k FROM jsonb_object_keys(coalesce(e.after_state, '{}'::jsonb)) x(k)
                                        WHERE (e.before_state -> x.k) IS DISTINCT FROM (e.after_state -> x.k)
                                          AND x.k NOT IN ('rows', 'result', 'updated_at', 'before_state', 'after_state', 'item_codes')
                                        ORDER BY x.k LIMIT 8) c) END AS changes,
                           (SELECT coalesce(jsonb_object_agg(x.k, s.st -> x.k), '{}'::jsonb)
                              FROM (SELECT CASE WHEN e.action = 'DELETE' THEN e.before_state ELSE e.after_state END AS st) s,
                                   unnest(ARRAY['ref', 'reference', 'item', 'purpose', 'amount', 'session', 'semester', 'level', 'state', 'status',
                                                'matric_no', 'payref', 'receipt_no', 'channel', 'decision', 'outcome']) x(k)
                             WHERE jsonb_typeof(s.st -> x.k) IS DISTINCT FROM 'null' AND (s.st -> x.k) IS NOT NULL) AS summary
                      FROM audit.entries e
                     WHERE :changes AND e.actor_id IN (SELECT person_id FROM who)
                       AND e.actor_office = ANY (""" + OFFICES + """
                )
                       AND (CAST(:office AS text) IS NULL OR e.actor_office = CAST(:office AS text))
                       AND (CAST(:action AS text) IS NULL OR e.action = CAST(:action AS text))
                       AND (CAST(:subject AS text) IS NULL OR e.subject_type = CAST(:subject AS text))
                       AND (CAST(:like AS text) IS NULL OR e.reason ILIKE CAST(:like AS text) OR e.subject_type ILIKE CAST(:like AS text))
                       AND (CAST(:from AS date) IS NULL OR e.occurred_at >= (CAST(:from AS date)::timestamp AT TIME ZONE 'Africa/Lagos'))
                       AND (CAST(:to AS date) IS NULL OR e.occurred_at < ((CAST(:to AS date) + 1)::timestamp AT TIME ZONE 'Africa/Lagos'))
                    UNION ALL
                    SELECT s.at, 'SIGN_IN', s.person_id, NULL, s.outcome, 'sign_in', s.person_id, s.username, host(s.source_ip), NULL::jsonb, '{}'::jsonb
                      FROM iam.sign_in_event s
                     WHERE :signins AND s.person_id IN (SELECT person_id FROM who)
                       AND (CAST(:from AS date) IS NULL OR s.at >= (CAST(:from AS date)::timestamp AT TIME ZONE 'Africa/Lagos'))
                       AND (CAST(:to AS date) IS NULL OR s.at < ((CAST(:to AS date) + 1)::timestamp AT TIME ZONE 'Africa/Lagos')))
                """;
        List<Map<String, Object>> rows = bind(jdbc.sql(sql + """
                SELECT count(*) OVER () AS total_rows, t.at, t.kind, t.person_id, p.surname || ', ' || p.given_names AS name, t.office, t.action,
                       t.subject_type, t.subject_id, t.reason, t.source_ip, t.changes::text AS changes, t.summary::text AS summary
                  FROM t LEFT JOIN iam.person p ON p.id = t.person_id
                 ORDER BY t.at DESC
                 LIMIT :n OFFSET :o
                """), person, off, act, subject, like, from, to, changes, signIns).param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        List<Map<String, Object>> shaped = rows.stream().map(r -> {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("total_rows");
            m.put("changes", r.get("changes") == null ? null : json.readValue(r.get("changes").toString(), List.class));
            m.put("summary", r.get("summary") == null ? Map.of() : json.readValue(r.get("summary").toString(), Map.class));
            return m;
        }).toList();
        Map<String, Object> tiles = bind(jdbc.sql(sql + """
                SELECT count(*) FILTER (WHERE t.kind = 'CHANGE') AS changes,
                       count(*) FILTER (WHERE t.kind = 'CHANGE' AND t.at >= ((now() AT TIME ZONE 'Africa/Lagos')::date::timestamp AT TIME ZONE 'Africa/Lagos')) AS changes_today,
                       count(*) FILTER (WHERE t.kind = 'SIGN_IN' AND t.action = 'SIGNED_IN') AS sign_ins,
                       count(*) FILTER (WHERE t.kind = 'SIGN_IN' AND t.action IN ('BAD_PASSWORD', 'LOCKED')) AS failed_sign_ins,
                       count(DISTINCT t.person_id) AS people
                  FROM t
                """), person, off, act, subject, like, from, to, changes, signIns).query().singleRow();
        List<Map<String, Object>> subjects = bind(jdbc.sql(sql + """
                SELECT t.subject_type, count(*) AS n FROM t WHERE t.kind = 'CHANGE' GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 40
                """), person, off, act, null, like, from, to, changes, false).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("tiles", tiles);
        out.put("subjects", subjects);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", shaped);
        return out;
    }

    private static JdbcClient.StatementSpec bind(JdbcClient.StatementSpec s, UUID person, String office, String action, String subject, String like,
                                                 LocalDate from, LocalDate to, boolean changes, boolean signIns) {
        return s.param("person", person == null ? null : person.toString(), Types.VARCHAR).param("office", office, Types.VARCHAR)
                .param("action", action, Types.VARCHAR).param("subject", blank(subject), Types.VARCHAR).param("like", like, Types.VARCHAR)
                .param("from", from == null ? null : from.toString(), Types.VARCHAR).param("to", to == null ? null : to.toString(), Types.VARCHAR)
                .param("changes", changes).param("signins", signIns);
    }
}
