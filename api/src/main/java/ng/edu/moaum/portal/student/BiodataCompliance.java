package ng.edu.moaum.portal.student;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

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

    BiodataCompliance(JdbcClient jdbc) {
        this.jdbc = jdbc;
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

    /**
     * V427: for each item that can be required, over the students on the register — how many lack it, how many whose
     * required biodata is complete would be held if it were required, and, for a required item, how many held students it
     * alone holds (unticking it would free them).
     */
    public List<Map<String, Object>> impact() {
        return jdbc.sql("SELECT item, required, students, missing, newly_held, freed FROM people.biodata_requirement_impact()").query().listOfRows();
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
