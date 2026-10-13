package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

import tools.jackson.databind.ObjectMapper;

/**
 * V423 — the student biodata completion gate, decided in one place (the "BiodataComplianceService"). Whether a
 * student must complete their biodata first is read from the record on every call, never cached and never chosen by
 * hand: people.biodata_gate_state asks whether the ICT Director's switch is ON, whether a live exception lets the
 * student through, and whether people.biodata_completion finds every required item given. The same calculation draws
 * the student's own progress, the ICT Director's figures and lists, and the weekly reminders, so no screen counts
 * differently from the gate.
 */
@Service
public class BiodataCompliance {

    /** the student reaches only the biodata page until the required items are given */
    public static final String REQUIRED = "REQUIRED";

    private final JdbcClient jdbc;
    private final ObjectMapper json;
    private final SearchRepository searches;

    BiodataCompliance(JdbcClient jdbc, ObjectMapper json, SearchRepository searches) {
        this.jdbc = jdbc;
        this.json = json;
        this.searches = searches;
    }

    /** OFF · EXCEPTION · COMPLETE · REQUIRED, from the record as it stands */
    public String gateState(UUID student) {
        return jdbc.sql("SELECT people.biodata_gate_state(:s)").param("s", student).query(String.class).single();
    }

    /** the switch: ON or OFF, when it was last turned, by whom and why */
    public Map<String, Object> gate() {
        return jdbc.sql("""
                SELECT g.enabled, g.changed_at, g.changed_office, g.reason,
                       coalesce(p.surname || ', ' || p.given_names, CASE WHEN g.changed_by IS NULL THEN NULL ELSE 'Unknown' END) AS changed_by
                  FROM people.biodata_gate g LEFT JOIN iam.person p ON p.id = g.changed_by
                """).query().listOfRows().stream().findFirst().orElse(Map.of("enabled", false));
    }

    /** one student's completion: the required items, how many are given, the missing ones in the form's order, when it last changed */
    public Map<String, Object> completion(UUID student) {
        Map<String, Object> row = jdbc.sql("""
                SELECT required, completed, complete, last_updated FROM people.biodata_completion(ARRAY[:s]::uuid[])
                """).param("s", student).query().listOfRows().stream().findFirst().orElse(null);
        Map<String, Object> out = new LinkedHashMap<>();
        if (row == null) {
            out.put("required", 0);
            out.put("completed", 0);
            out.put("complete", true);
            out.put("percent", 100);
            out.put("missing", List.of());
            return out;
        }
        int required = ((Number) row.get("required")).intValue();
        int completed = ((Number) row.get("completed")).intValue();
        out.put("required", required);
        out.put("completed", completed);
        out.put("complete", row.get("complete"));
        out.put("percent", required == 0 ? 100 : (int) Math.floor(100.0 * completed / required));
        out.put("lastUpdated", row.get("last_updated"));
        out.put("missing", jdbc.sql("""
                SELECT m.item, m.label FROM people.biodata_completion(ARRAY[:s]::uuid[]) c, unnest(c.missing, c.missing_labels) AS m(item, label)
                """).param("s", student).query().listOfRows());
        return out;
    }

    /** the items required now, in the form's order: the passport photograph first, then the fields */
    public List<String> requiredItems() {
        return jdbc.sql("""
                SELECT r.item FROM people.biodata_requirement r LEFT JOIN ref.biodata_field f ON f.field = r.field
                 WHERE r.required ORDER BY coalesce(f.ord, -1), r.item
                """).query(String.class).list();
    }

    /** the student's live exception, if one lets them through now */
    public Map<String, Object> liveException(UUID student) {
        return jdbc.sql("""
                SELECT id, starts_at, expires_at FROM people.biodata_gate_exception
                 WHERE student_id = :s AND revoked_at IS NULL AND now() >= starts_at AND now() < expires_at
                 ORDER BY expires_at DESC LIMIT 1
                """).param("s", student).query().listOfRows().stream().findFirst().orElse(null);
    }

    /** what a list is narrowed by; every field optional, the faculty, department and programme already held to the office's bound */
    public record Filter(String fac, String dept, String prog, Integer level, String session, String sex, String status, String missing,
                         String q, int page, int size) {
    }

    private static final String POPULATION = """
            pop AS (
                SELECT s.id FROM people.student s
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE people.biodata_applicable(s.status)
                   AND (:fac::text IS NULL OR p.faculty_code = :fac) AND (:dept::text IS NULL OR p.dept_code = :dept)
                   AND (:prog::text IS NULL OR p.code = :prog) AND (:level::int IS NULL OR s.current_level = :level)
                   AND (:session::text IS NULL OR s.entry_session = :session) AND (:sex::text IS NULL OR s.sex = :sex)
                   AND (:ql::text IS NULL OR upper(s.surname || ' ' || s.other_names) LIKE :ql OR upper(s.other_names || ' ' || s.surname) LIKE :ql
                        OR upper(s.matric_no) LIKE :ql OR upper(s.jamb_reg_no) LIKE :ql OR upper(s.admission_no) LIKE :ql
                        OR EXISTS (SELECT 1 FROM admissions.application a WHERE a.candidate_id = s.candidate_id AND upper(a.application_no) LIKE :ql))
            ),
            c AS MATERIALIZED (SELECT * FROM people.biodata_completion((SELECT coalesce(array_agg(id), '{}'::uuid[]) FROM pop)))
            """;

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, Filter f, String ql) {
        return spec.param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).param("prog", f.prog(), Types.VARCHAR)
                .param("level", f.level(), Types.INTEGER).param("session", f.session(), Types.VARCHAR).param("sex", f.sex(), Types.VARCHAR)
                .param("ql", ql, Types.VARCHAR);
    }

    /**
     * The figures within a filter: how many students, how many complete, the percentage; how many miss each required
     * item; the same by faculty and department; and those brought from the old portal (no admission on this one)
     * apart from those admitted here — one pass of the calculation for all of them.
     */
    public Map<String, Object> summary(Filter f) {
        String text = bind(jdbc.sql("WITH " + POPULATION + """
                SELECT jsonb_build_object(
                    'total', (SELECT count(*) FROM c),
                    'complete', (SELECT count(*) FROM c WHERE c.complete),
                    'incomplete', (SELECT count(*) FROM c WHERE NOT c.complete),
                    'items', coalesce((SELECT jsonb_agg(jsonb_build_object('item', x.item, 'missing', x.n) ORDER BY x.n DESC)
                                         FROM (SELECT m AS item, count(*) AS n FROM c, unnest(c.missing) m GROUP BY m) x), '[]'::jsonb),
                    'origin', coalesce((SELECT jsonb_agg(jsonb_build_object('origin', x.origin, 'total', x.total, 'complete', x.done) ORDER BY x.origin)
                                         FROM (SELECT CASE WHEN s.candidate_id IS NULL THEN 'MIGRATED' ELSE 'PORTAL' END AS origin,
                                                      count(*) AS total, count(*) FILTER (WHERE c.complete) AS done
                                                 FROM c JOIN people.student s ON s.id = c.student_id GROUP BY 1) x), '[]'::jsonb),
                    'faculties', coalesce((SELECT jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name, 'total', x.total, 'complete', x.done) ORDER BY x.name)
                                         FROM (SELECT p.faculty_code AS code, coalesce(fa.name, 'No faculty on record') AS name, count(*) AS total, count(*) FILTER (WHERE c.complete) AS done
                                                 FROM c JOIN people.student s ON s.id = c.student_id
                                                 LEFT JOIN ref.programme p ON p.code = s.programme_code
                                                 LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code GROUP BY 1, 2) x), '[]'::jsonb),
                    'departments', coalesce((SELECT jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name, 'faculty', x.fac, 'total', x.total, 'complete', x.done) ORDER BY x.name)
                                         FROM (SELECT p.dept_code AS code, coalesce(d.name, 'No department on record') AS name, p.faculty_code AS fac,
                                                      count(*) AS total, count(*) FILTER (WHERE c.complete) AS done
                                                 FROM c JOIN people.student s ON s.id = c.student_id
                                                 LEFT JOIN ref.programme p ON p.code = s.programme_code
                                                 LEFT JOIN ref.department d ON d.code = p.dept_code GROUP BY 1, 2, 3) x), '[]'::jsonb)
                )::text
                """), f, null).query(String.class).single();
        @SuppressWarnings("unchecked")
        Map<String, Object> out = json.readValue(text, LinkedHashMap.class);
        long total = ((Number) out.get("total")).longValue();
        long complete = ((Number) out.get("complete")).longValue();
        out.put("percent", total == 0 ? 100.0 : Math.round(10000.0 * complete / total) / 100.0);
        return out;
    }

    /** the students within a filter, a page at a time, each with what is missing; a search is written to the search log */
    public Map<String, Object> list(Filter f) {
        String q = f.q() == null || f.q().isBlank() ? null : f.q().trim();
        String ql = q == null ? null : "%" + q.toUpperCase().replace("%", "").replace("_", "") + "%";
        List<Map<String, Object>> rows = bind(jdbc.sql("WITH " + POPULATION + """
                SELECT s.id, s.surname || ', ' || s.other_names AS name, s.matric_no, s.jamb_reg_no, s.admission_no,
                       fa.name AS faculty, d.name AS department, p.name AS programme, s.current_level AS level, s.sex, s.entry_session,
                       coalesce(nullif(btrim(ct.phone), ''), (SELECT nullif(btrim(b.value), '') FROM people.biodata b WHERE b.student_id = s.id AND b.field = 'mobile')) AS phone,
                       coalesce(nullif(btrim(ct.email), ''), (SELECT nullif(btrim(b.value), '') FROM people.biodata b WHERE b.student_id = s.id AND b.field = 'personal_email')) AS email,
                       c.required, c.completed, c.complete, array_to_string(c.missing_labels, ', ') AS missing, c.last_updated,
                       s.candidate_id IS NULL AS migrated,
                       EXISTS (SELECT 1 FROM people.biodata_gate_exception e WHERE e.student_id = s.id AND e.revoked_at IS NULL
                                  AND now() >= e.starts_at AND now() < e.expires_at) AS excepted,
                       count(*) OVER () AS total
                  FROM c
                  JOIN people.student s ON s.id = c.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code
                  LEFT JOIN people.student_contact ct ON ct.student_id = s.id
                 WHERE (:status::text IS NULL OR (:status = 'COMPLETE' AND c.complete) OR (:status = 'INCOMPLETE' AND NOT c.complete))
                   AND (:missing::text IS NULL OR :missing = ANY (c.missing))
                 ORDER BY s.surname, s.other_names, s.id
                 LIMIT :size OFFSET :off
                """), f, ql).param("status", f.status(), Types.VARCHAR).param("missing", f.missing(), Types.VARCHAR)
                .param("size", f.size()).param("off", f.page() * f.size()).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.getFirst().get("total")).longValue();
        if (q != null) {
            searches.log(q, "biodata-compliance", (int) Math.min(total, Integer.MAX_VALUE));
        }
        List<Map<String, Object>> out = new ArrayList<>(rows.size());
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("total");
            m.put("status", Boolean.TRUE.equals(r.get("complete")) ? "UP_TO_DATE" : "INCOMPLETE");
            out.add(m);
        }
        Map<String, Object> page = new LinkedHashMap<>();
        page.put("total", total);
        page.put("page", f.page());
        page.put("size", f.size());
        page.put("rows", out);
        return page;
    }

    /** every item that can be required — the passport photograph and each biodata field — with whether it is, and why one cannot be */
    public List<Map<String, Object>> requirements() {
        return jdbc.sql("""
                SELECT 'PASSPORT' AS item, 'Passport photograph' AS label, 'photo' AS section, -1 AS ord,
                       coalesce((SELECT required FROM people.biodata_requirement WHERE item = 'PASSPORT'), false) AS required, NULL::text AS refused
                UNION ALL
                SELECT f.field, f.label, f.section, f.ord, coalesce(r.required, false),
                       CASE WHEN f.tier = 'locked' THEN 'Read from JAMB: the student cannot enter it'
                            WHEN f.section = 'health' THEN 'Health information is given under consent, never required' END
                  FROM ref.biodata_field f LEFT JOIN people.biodata_requirement r ON r.field = f.field
                 ORDER BY ord, item
                """).query().listOfRows();
    }

    /** the exceptions live now, and those that ended in the last 90 days */
    public List<Map<String, Object>> exceptions() {
        return jdbc.sql("""
                SELECT e.id, e.student_id, s.surname || ', ' || s.other_names AS name, coalesce(s.matric_no, s.jamb_reg_no, s.admission_no) AS number,
                       e.reason, e.starts_at, e.expires_at, e.revoked_at, e.revoke_reason, e.granted_office,
                       coalesce(p.surname || ', ' || p.given_names, 'Unknown') AS granted_by,
                       (e.revoked_at IS NULL AND now() >= e.starts_at AND now() < e.expires_at) AS live
                  FROM people.biodata_gate_exception e
                  JOIN people.student s ON s.id = e.student_id
                  LEFT JOIN iam.person p ON p.id = e.granted_by
                 WHERE e.expires_at > now() - interval '90 days'
                 ORDER BY (e.revoked_at IS NULL AND e.expires_at > now()) DESC, e.expires_at DESC
                 LIMIT 500
                """).query().listOfRows();
    }

    /** the switch and the required items as they were changed, newest first, from the audit spine */
    public List<Map<String, Object>> history() {
        return jdbc.sql("""
                SELECT e.occurred_at, e.subject_type, e.actor_office, e.reason, host(e.source_ip) AS source_ip,
                       coalesce(p.surname || ', ' || p.given_names, CASE WHEN e.actor_id = '00000000-0000-0000-0000-000000000000' THEN 'The portal' ELSE 'Unknown' END) AS actor,
                       e.before_state->>'enabled' AS was_enabled, e.after_state->>'enabled' AS now_enabled,
                       coalesce(e.after_state->>'item', e.before_state->>'item') AS item,
                       e.before_state->>'required' AS was_required, e.after_state->>'required' AS now_required
                  FROM audit.entries e
                  LEFT JOIN iam.person p ON p.id = e.actor_id
                 WHERE e.subject_type IN ('people.biodata_gate', 'people.biodata_requirement')
                 ORDER BY e.occurred_at DESC
                 LIMIT 100
                """).query().listOfRows();
    }
}
