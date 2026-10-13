package ng.edu.moaum.portal.clearance;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * The reads of the clearance workflows (V415): the office's desk, a process in full, the Registry's overview and who
 * is eligible to start. Every list is computed on the server, set-based over clearance.stage_rows, and paged; the
 * screen never holds the register.
 */
@Repository
class ClearanceDesk {

    /** the offices that act for every unit; the units each other office signs come from clearance.unit.office_code */
    static final Set<String> ANY_UNIT = Set.of("registrar", "dregistrar", "academic");
    /** an office that signs a unit beside the unit's own office */
    private static final Map<String, Set<String>> ALSO = Map.of("facultyofficer", Set.of("FACULTY"), "housing", Set.of("HOSTEL"));
    /** who reads the Health stage's evidence (the clinic's fitness finding): the clinic's office and the Registry */
    static final Set<String> HEALTH_READERS = Set.of("services", "registrar", "dregistrar");

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    ClearanceDesk(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** the units the office gives its word on */
    List<String> unitsOf(String office) {
        if (office == null) return List.of();
        if (ANY_UNIT.contains(office)) return jdbc.sql("SELECT code FROM clearance.unit ORDER BY ord").query(String.class).list();
        List<String> own = new ArrayList<>(jdbc.sql("SELECT code FROM clearance.unit WHERE office_code = :o ORDER BY ord").param("o", office).query(String.class).list());
        for (String u : ALSO.getOrDefault(office, Set.of())) if (!own.contains(u)) own.add(u);
        return own;
    }

    Map<String, Object> workflow(String code) {
        return jdbc.sql("SELECT * FROM clearance.workflow WHERE code = :c").param("c", code == null ? "" : code.toUpperCase())
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("clearance", code));
    }

    List<Map<String, Object>> workflows() {
        List<Map<String, Object>> out = jdbc.sql("SELECT * FROM clearance.workflow ORDER BY CASE code WHEN 'FRESH' THEN 1 WHEN 'FINAL' THEN 2 ELSE 3 END").query().listOfRows();
        for (Map<String, Object> w : out) {
            w.put("stages", jdbc.sql("""
                    SELECT ws.unit, u.label, u.office_code, ws.ord, ws.required, ws.waits, ws.condition, ws.programmes, ws.faculties, ws.departments,
                           ws.levels, ws.entry_modes, ws.documents, ws.deadline_days, ws.instructions, ws.active
                      FROM clearance.workflow_stage ws JOIN clearance.unit u ON u.code = ws.unit
                     WHERE ws.workflow = :w ORDER BY ws.active DESC, ws.ord
                    """).param("w", w.get("code")).query().listOfRows());
        }
        return out;
    }

    List<Map<String, Object>> units() {
        return jdbc.sql("SELECT code, label, clears_against, office_code, ord FROM clearance.unit ORDER BY ord").query().listOfRows();
    }

    /** the filters a desk or report is asked with */
    record Filter(String workflow, String session, String unit, String status, String fac, String dept, String prog, Integer level,
                  String sex, String entry, String q, int page, int size) {
    }

    /**
     * The desk: the processes of a workflow and session within the bound, with each one's overall word and, when a unit is
     * named, that unit's word — the tiles counted before the status filter, the rows paged after it. An office's own unit
     * lists only the students the stage applies to, unless the not-applicable list is asked for.
     */
    Map<String, Object> desk(Filter f) {
        Map<String, Object> w = workflow(f.workflow());
        String ql = f.q() == null || f.q().isBlank() ? null : "%" + f.q().trim().replace("%", "").replace("_", "") + "%";
        Map<String, Object> row = jdbc.sql("""
                WITH pr AS (
                    SELECT q.id AS process_id, q.reference, q.student_id, q.session, q.started_at, q.completed_at, q.start_basis,
                           s.surname, s.other_names, s.matric_no, s.admission_no, s.jamb_reg_no, s.sex, s.entry_mode, s.current_level AS level,
                           s.programme_code, p.name AS programme, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty, ap.application_no
                      FROM clearance.process q
                      JOIN people.student s ON s.id = q.student_id
                      LEFT JOIN ref.programme p ON p.code = s.programme_code
                      LEFT JOIN ref.department d ON d.code = p.dept_code
                      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                      LEFT JOIN LATERAL (SELECT a.application_no FROM admissions.application a
                                          WHERE s.candidate_id IS NOT NULL AND a.candidate_id = s.candidate_id
                                          ORDER BY a.created_at DESC LIMIT 1) ap ON true
                     WHERE q.workflow = :wf AND q.session = :session AND q.cancelled_at IS NULL
                       AND (:fac::text IS NULL OR p.faculty_code = :fac)
                       AND (:dept::text IS NULL OR p.dept_code = :dept)
                       AND (:prog::text IS NULL OR s.programme_code = :prog)
                       AND (:level::int IS NULL OR s.current_level = :level)
                       AND (:sex::text IS NULL OR s.sex = :sex)
                       AND (:entry::text IS NULL OR s.entry_mode = :entry)
                       AND (:ql::text IS NULL OR q.reference ILIKE :ql OR (s.surname || ' ' || s.other_names) ILIKE :ql
                            OR (s.other_names || ' ' || s.surname) ILIKE :ql OR s.matric_no ILIKE :ql OR s.admission_no ILIKE :ql
                            OR s.jamb_reg_no ILIKE :ql OR ap.application_no ILIKE :ql)
                ),
                r AS (
                    SELECT * FROM clearance.stage_rows(:purpose, :session, (SELECT coalesce(array_agg(student_id), '{}'::uuid[]) FROM pr))
                ),
                agg AS (
                    SELECT r.student_id,
                           jsonb_agg(jsonb_build_object('unit', r.unit, 'label', r.label, 'state', r.state, 'applies', r.applies, 'required', r.required)
                                     ORDER BY r.ord) AS stages,
                           CASE WHEN coalesce(bool_and(r.state = 'CLEARED') FILTER (WHERE r.required AND r.applies), true) THEN :complete
                                WHEN bool_or(r.state = 'REJECTED') FILTER (WHERE r.required AND r.applies) THEN 'REJECTED'
                                WHEN bool_or(r.state = 'NOT_CLEARED') FILTER (WHERE r.required AND r.applies) THEN 'NOT_CLEARED'
                                WHEN bool_or(r.state = 'REQUIRES_ACTION') FILTER (WHERE r.required AND r.applies) THEN 'PENDING_ACTION'
                                WHEN bool_or(r.state = 'CLEARED') FILTER (WHERE r.required AND r.applies) THEN 'PARTIALLY_CLEARED'
                                ELSE 'IN_PROGRESS' END AS overall,
                           max(r.state) FILTER (WHERE r.unit = :unit) AS my_state,
                           max(r.item) FILTER (WHERE r.unit = :unit) AS my_item,
                           bool_or(r.applies) FILTER (WHERE r.unit = :unit) AS my_applies,
                           bool_or(r.opened) FILTER (WHERE r.unit = :unit) AS my_opened,
                           max(r.decided_at) FILTER (WHERE r.unit = :unit) AS my_decided_at
                      FROM r GROUP BY r.student_id
                ),
                joined AS (
                    SELECT pr.*, agg.stages, agg.overall, agg.my_state, agg.my_item, agg.my_applies, agg.my_opened, agg.my_decided_at,
                           CASE WHEN :unit::text IS NULL THEN agg.overall ELSE agg.my_state END AS shown
                      FROM pr JOIN agg ON agg.student_id = pr.student_id
                     WHERE :unit::text IS NULL OR agg.my_state IS NOT NULL
                ),
                filtered AS (
                    SELECT * FROM joined
                     WHERE (:status::text IS NULL OR shown = :status)
                       AND (:unit::text IS NULL OR my_applies OR :status::text = 'NOT_APPLICABLE')
                )
                SELECT (SELECT coalesce(jsonb_object_agg(k, n), '{}'::jsonb) FROM (SELECT shown AS k, count(*) AS n FROM joined GROUP BY shown) t)::text AS tiles,
                       (SELECT count(*) FROM joined) AS processes,
                       (SELECT count(*) FROM filtered) AS total,
                       (SELECT coalesce(jsonb_agg(to_jsonb(x) - 'shown' ORDER BY x.surname, x.other_names), '[]'::jsonb)
                          FROM (SELECT * FROM filtered ORDER BY surname, other_names OFFSET :off LIMIT :lim) x)::text AS rows
                """)
                .param("wf", w.get("code")).param("purpose", w.get("purpose")).param("complete", w.get("complete_word"))
                .param("session", f.session())
                .param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).param("prog", f.prog(), Types.VARCHAR)
                .param("level", f.level(), Types.INTEGER).param("sex", f.sex(), Types.VARCHAR).param("entry", f.entry(), Types.VARCHAR)
                .param("ql", ql, Types.VARCHAR).param("unit", f.unit(), Types.VARCHAR).param("status", f.status(), Types.VARCHAR)
                .param("off", Math.max(0, f.page()) * f.size()).param("lim", f.size())
                .query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("workflow", w);
        out.put("session", f.session());
        out.put("unit", f.unit());
        out.put("status", f.status());
        out.put("tiles", json.readValue(String.valueOf(row.get("tiles")), Map.class));
        out.put("processes", row.get("processes"));
        out.put("total", row.get("total"));
        out.put("page", f.page());
        out.put("size", f.size());
        out.put("rows", json.readValue(String.valueOf(row.get("rows")), List.class));
        return out;
    }

    /** a process with its student, workflow and the student's place (faculty, department) for the scope check */
    Optional<Map<String, Object>> process(UUID id) {
        return jdbc.sql("""
                SELECT q.*, w.label AS workflow_label, w.purpose, w.complete_word, w.certificate, w.per_session, clearance.overall(q.id) AS overall,
                       s.surname, s.other_names, s.matric_no, s.admission_no, s.jamb_reg_no, s.sex, s.entry_mode, s.current_level AS level, s.status AS student_status,
                       s.programme_code, p.name AS programme, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty,
                       (SELECT a.application_no FROM admissions.application a WHERE s.candidate_id IS NOT NULL AND a.candidate_id = s.candidate_id
                         ORDER BY a.created_at DESC LIMIT 1) AS application_no,
                       (SELECT pe.surname || ', ' || pe.given_names FROM iam.person pe WHERE pe.id = q.started_by) AS started_by_name
                  FROM clearance.process q
                  JOIN clearance.workflow w ON w.code = q.workflow
                  JOIN people.student s ON s.id = q.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE q.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst();
    }

    /** the stages of a process, with the officer's name and the deadline as a date */
    List<Map<String, Object>> stages(Map<String, Object> p) {
        return jdbc.sql("""
                SELECT r.unit, r.label, r.office_code, r.ord, r.required, r.waits, r.applies, r.opened, r.state, r.item, r.note,
                       r.decided_at, r.overridden, r.documents, r.instructions,
                       CASE WHEN r.deadline_days IS NULL THEN NULL
                            ELSE (SELECT q.started_at::date FROM clearance.process q WHERE q.id = :pid) + r.deadline_days END AS deadline,
                       (SELECT pe.surname || ', ' || pe.given_names FROM iam.person pe WHERE pe.id = r.officer_id) AS officer
                  FROM clearance.stage_rows(:purpose, :session, ARRAY[:student]::uuid[]) r
                 ORDER BY r.ord
                """).param("purpose", p.get("purpose")).param("session", p.get("session")).param("student", p.get("student_id"))
                .param("pid", p.get("id")).query().listOfRows();
    }

    /** every word given on the student for the purpose, newest first (the internal note only when asked for) */
    List<Map<String, Object>> history(Map<String, Object> p, boolean internal) {
        return jdbc.sql("""
                SELECT c.unit, u.label, c.state, c.item, c.note, CASE WHEN :internal THEN c.internal_note END AS internal_note,
                       c.override, c.previous_state, c.office, c.decided_at,
                       (SELECT pe.surname || ', ' || pe.given_names FROM iam.person pe WHERE pe.id = c.officer_id) AS officer
                  FROM clearance.item c JOIN clearance.unit u ON u.code = c.unit
                 WHERE c.student_id = :s AND c.purpose = :purpose AND (NOT :perSession OR c.process_id = :id)
                 ORDER BY c.decided_at DESC
                """).param("internal", internal).param("s", p.get("student_id")).param("purpose", p.get("purpose"))
                .param("perSession", Boolean.TRUE.equals(p.get("per_session"))).param("id", p.get("id")).query().listOfRows();
    }

    List<Map<String, Object>> documents(UUID process) {
        return jdbc.sql("""
                SELECT d.id, d.unit, u.label AS unit_label, d.label, d.file_name, d.content_type, d.size_bytes, d.state, d.reason,
                       d.uploaded_at, d.uploaded_office, d.reviewed_at, d.superseded_by IS NOT NULL AS superseded,
                       (SELECT pe.surname || ', ' || pe.given_names FROM iam.person pe WHERE pe.id = d.reviewed_by) AS reviewer
                  FROM clearance.document d JOIN clearance.unit u ON u.code = d.unit
                 WHERE d.process_id = :p
                 ORDER BY d.superseded_by IS NOT NULL, d.uploaded_at DESC
                """).param("p", process).query().listOfRows();
    }

    Object evidence(UUID process, String unit) {
        return jdbc.sql("SELECT clearance.evidence(:p, :u)::text").param("p", process).param("u", unit).query(String.class).single();
    }

    /**
     * The Registry's overview of a workflow and session: the processes by overall word, each office's stages by word with
     * the average days from the start to its clearance, and who is eligible but not yet started (with the commonest reasons
     * the others are not).
     */
    Map<String, Object> overview(String workflow, String session) {
        Map<String, Object> w = workflow(workflow);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("workflow", w);
        out.put("session", session);
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH pr AS (SELECT q.id, q.student_id, q.started_at FROM clearance.process q
                             WHERE q.workflow = :wf AND q.session = :session AND q.cancelled_at IS NULL),
                     r AS (SELECT * FROM clearance.stage_rows(:purpose, :session, (SELECT coalesce(array_agg(student_id), '{}'::uuid[]) FROM pr)))
                SELECT r.unit, r.label, r.ord, count(*) FILTER (WHERE r.applies) AS applies,
                       count(*) FILTER (WHERE r.state = 'WAITING') AS waiting, count(*) FILTER (WHERE r.state = 'PENDING') AS pending,
                       count(*) FILTER (WHERE r.state = 'UNDER_REVIEW') AS under_review, count(*) FILTER (WHERE r.state = 'REQUIRES_ACTION') AS requires_action,
                       count(*) FILTER (WHERE r.state = 'NOT_CLEARED') AS not_cleared, count(*) FILTER (WHERE r.state = 'REJECTED') AS rejected,
                       count(*) FILTER (WHERE r.state = 'CLEARED') AS cleared, count(*) FILTER (WHERE r.state = 'NOT_APPLICABLE') AS not_applicable,
                       (SELECT round(avg(extract(epoch FROM (c.decided_at - q.started_at)) / 86400)::numeric, 1)
                          FROM clearance.item c JOIN clearance.process q ON q.id = c.process_id
                         WHERE q.workflow = :wf AND q.session = :session AND c.unit = r.unit AND c.state = 'CLEARED') AS avg_days
                  FROM r GROUP BY r.unit, r.label, r.ord ORDER BY r.ord
                """).param("wf", w.get("code")).param("purpose", w.get("purpose")).param("session", session).query().listOfRows();
        out.put("offices", rows);
        out.put("overall", jdbc.sql("""
                WITH pr AS (SELECT q.id, q.student_id FROM clearance.process q
                             WHERE q.workflow = :wf AND q.session = :session AND q.cancelled_at IS NULL),
                     r AS (SELECT * FROM clearance.stage_rows(:purpose, :session, (SELECT coalesce(array_agg(student_id), '{}'::uuid[]) FROM pr))),
                     o AS (SELECT CASE WHEN coalesce(bool_and(r.state = 'CLEARED') FILTER (WHERE r.required AND r.applies), true) THEN :complete
                                       WHEN bool_or(r.state = 'REJECTED') FILTER (WHERE r.required AND r.applies) THEN 'REJECTED'
                                       WHEN bool_or(r.state = 'NOT_CLEARED') FILTER (WHERE r.required AND r.applies) THEN 'NOT_CLEARED'
                                       WHEN bool_or(r.state = 'REQUIRES_ACTION') FILTER (WHERE r.required AND r.applies) THEN 'PENDING_ACTION'
                                       WHEN bool_or(r.state = 'CLEARED') FILTER (WHERE r.required AND r.applies) THEN 'PARTIALLY_CLEARED'
                                       ELSE 'IN_PROGRESS' END AS overall
                             FROM r GROUP BY r.student_id)
                SELECT coalesce(jsonb_object_agg(overall, n), '{}'::jsonb)::text FROM (SELECT overall, count(*) AS n FROM o GROUP BY overall) t
                """).param("wf", w.get("code")).param("purpose", w.get("purpose")).param("complete", w.get("complete_word"))
                .param("session", session).query(String.class).single());
        out.put("eligible", eligible(String.valueOf(w.get("code")), session));
        return out;
    }

    /** eligible and not started, and the commonest reasons the others are not */
    Map<String, Object> eligible(String workflow, String session) {
        Map<String, Object> e = jdbc.sql("""
                WITH e AS (SELECT * FROM clearance.eligibility_rows(:wf, :session)),
                     live AS (SELECT DISTINCT q.student_id FROM clearance.process q JOIN clearance.workflow w ON w.code = q.workflow
                               WHERE q.workflow = :wf AND q.cancelled_at IS NULL AND (NOT w.per_session OR q.session = :session))
                SELECT count(*) FILTER (WHERE e.eligible AND NOT EXISTS (SELECT 1 FROM live WHERE live.student_id = e.student_id)) AS not_started,
                       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM live WHERE live.student_id = e.student_id)) AS started,
                       count(*) FILTER (WHERE NOT e.eligible AND NOT EXISTS (SELECT 1 FROM live WHERE live.student_id = e.student_id)) AS ineligible,
                       (SELECT coalesce(jsonb_agg(jsonb_build_object('reason', reason, 'students', n) ORDER BY n DESC), '[]'::jsonb)::text
                          FROM (SELECT reason, count(*) AS n FROM e CROSS JOIN LATERAL unnest(e.reasons) reason
                                 WHERE NOT EXISTS (SELECT 1 FROM live WHERE live.student_id = e.student_id)
                                 GROUP BY reason ORDER BY count(*) DESC LIMIT 6) t) AS reasons
                  FROM e
                """).param("wf", workflow.toUpperCase()).param("session", session).query().singleRow();
        return e;
    }

    /**
     * What waits on an office (V416): for each clearance in use and each of the office's units it has, within the faculty or
     * department given — the students whose stage is open and undecided, those with the student to act, those past the
     * stage's deadline, and the documents uploaded for the stage that await review.
     */
    List<Map<String, Object>> awaiting(List<String> units, String fac, String dept) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> w : jdbc.sql("SELECT code, label, purpose FROM clearance.workflow WHERE active ORDER BY CASE code WHEN 'FRESH' THEN 1 WHEN 'FINAL' THEN 2 ELSE 3 END")
                .query().listOfRows()) {
            List<Map<String, Object>> rows = jdbc.sql("""
                    WITH pr AS (
                        SELECT q.id, q.student_id, q.started_at FROM clearance.process q
                          JOIN people.student s ON s.id = q.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code
                         WHERE q.workflow = :w AND q.cancelled_at IS NULL AND q.completed_at IS NULL
                           AND (:fac::text IS NULL OR p.faculty_code = :fac) AND (:dept::text IS NULL OR p.dept_code = :dept)
                    ),
                    r AS (
                        SELECT r.* FROM clearance.stage_rows(:purpose, NULL, (SELECT coalesce(array_agg(student_id), '{}'::uuid[]) FROM pr)) r
                         WHERE r.unit IN (:units)
                    )
                    SELECT r.unit, r.label,
                           count(*) FILTER (WHERE r.opened AND r.state IN ('PENDING', 'UNDER_REVIEW')) AS awaiting,
                           count(*) FILTER (WHERE r.state = 'REQUIRES_ACTION') AS with_student,
                           count(*) FILTER (WHERE r.opened AND r.state IN ('PENDING', 'UNDER_REVIEW') AND r.deadline_days IS NOT NULL
                                              AND pr.started_at::date + r.deadline_days < current_date) AS overdue,
                           (SELECT count(*) FROM clearance.document d JOIN pr p2 ON p2.id = d.process_id
                             WHERE d.unit = r.unit AND d.superseded_by IS NULL AND d.state IN ('PENDING', 'UNDER_REVIEW')) AS documents
                      FROM r JOIN pr ON pr.student_id = r.student_id
                     GROUP BY r.unit, r.label, r.ord
                     ORDER BY r.ord
                    """).param("w", w.get("code")).param("purpose", w.get("purpose")).param("units", units)
                    .param("fac", fac, Types.VARCHAR).param("dept", dept, Types.VARCHAR).query().listOfRows();
            for (Map<String, Object> r : rows) {
                Map<String, Object> one = new LinkedHashMap<>();
                one.put("workflow", w.get("code"));
                one.put("workflow_label", w.get("label"));
                one.putAll(r);
                out.add(one);
            }
        }
        return out;
    }

    /** a student by id, matric, admission or JAMB number */
    Optional<UUID> studentBy(String key) {
        if (key == null || key.isBlank()) return Optional.empty();
        String k = key.trim();
        try {
            UUID id = UUID.fromString(k);
            return jdbc.sql("SELECT id FROM people.student WHERE id = :id").param("id", id).query(UUID.class).optional();
        } catch (IllegalArgumentException e) {
            return jdbc.sql("""
                    SELECT id FROM people.student WHERE upper(matric_no) = upper(:k) OR upper(admission_no) = upper(:k) OR upper(jamb_reg_no) = upper(:k)
                     ORDER BY matric_no NULLS LAST LIMIT 1
                    """).param("k", k).query(UUID.class).optional();
        }
    }
}
