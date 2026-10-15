package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * A student's classification (V469) — programme type, admission route, study mode and centre — as
 * people.student_classification reads it, with the decisions and the programme-type history behind it; the
 * classification audit of the whole estate; and the two acts that settle a record: the Academic Office's or the
 * Registry's decision (people.classify_student) and a progression from an earlier JUPEB or Preliminary record
 * (people.record_progression). The database refuses any other office and any act without a reason.
 */
@Service
class ClassificationService {

    private final JdbcClient jdbc;

    ClassificationService(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** one student's classification, its decisions and its history */
    @Transactional(readOnly = true)
    Map<String, Object> of(UUID studentId) {
        Map<String, Object> c = jdbc.sql("""
                SELECT c.student_id, c.programme_type, pt.label AS programme_type_name, c.proposed_type, ppt.label AS proposed_type_name,
                       c.type_source, c.classification_status, c.classification_issue, c.classification_note,
                       c.admission_route, ar.name AS admission_route_name, c.study_mode, c.centre_code, ce.name AS centre_name, c.centre_source,
                       c.study_mode_differs
                  FROM people.student_classification c
                  LEFT JOIN finance.programme_type pt ON pt.code = c.programme_type
                  LEFT JOIN finance.programme_type ppt ON ppt.code = c.proposed_type
                  LEFT JOIN ref.admission_route ar ON ar.code = c.admission_route
                  LEFT JOIN ref.centre ce ON ce.code = c.centre_code
                 WHERE c.student_id = :id
                """).param("id", studentId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("student", studentId));
        Map<String, Object> out = new LinkedHashMap<>(c);
        out.put("history", jdbc.sql("""
                SELECT e.id, e.event, e.kind, e.from_type, ft.label AS from_type_name, e.to_type, tt.label AS to_type_name, e.reason, e.at, e.by_office,
                       coalesce(j.application_no, a.application_no) AS earlier_application_no
                  FROM people.programme_type_event e
                  LEFT JOIN finance.programme_type ft ON ft.code = e.from_type
                  LEFT JOIN finance.programme_type tt ON tt.code = e.to_type
                  LEFT JOIN jupeb.application j ON j.id = e.jupeb_application_id
                  LEFT JOIN admissions.application a ON a.id = e.application_id
                 WHERE e.student_id = :id
                 ORDER BY e.at DESC
                """).param("id", studentId).query().listOfRows());
        return out;
    }

    /**
     * The classification audit: how many learners each source has, how many are classified, how many require
     * classification (unclassified, conflicting) and what is missing, by programme type — the data-quality report of
     * every learner the portal holds.
     */
    @Transactional(readOnly = true)
    Map<String, Object> audit() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("totals", jdbc.sql("""
                SELECT count(*) AS learners,
                       count(*) FILTER (WHERE classification_status = 'CLASSIFIED') AS classified,
                       count(*) FILTER (WHERE classification_status = 'REQUIRES_CLASSIFICATION') AS requires_classification,
                       count(*) FILTER (WHERE classification_issue = 'UNCLASSIFIED') AS unclassified,
                       count(*) FILTER (WHERE classification_issue = 'CONFLICTING') AS conflicting,
                       count(*) FILTER (WHERE programme_type IS NULL) AS missing_programme_type,
                       count(*) FILTER (WHERE source <> 'JUPEB' AND faculty_code IS NULL) AS missing_faculty,
                       count(*) FILTER (WHERE source <> 'JUPEB' AND dept_code IS NULL) AS missing_department,
                       count(*) FILTER (WHERE source <> 'JUPEB' AND programme_code IS NULL) AS missing_programme,
                       count(*) FILTER (WHERE admission_session IS NULL) AS missing_session,
                       count(*) FILTER (WHERE admission_route IS NULL) AS missing_admission_route,
                       count(*) FILTER (WHERE centre_code IS NULL) AS missing_centre,
                       count(*) FILTER (WHERE study_mode_differs) AS study_mode_differs,
                       count(*) FILTER (WHERE type_source = 'DECISION') AS decided
                  FROM people.learner
                """).query().singleRow());
        out.put("bySource", jdbc.sql("""
                SELECT source, count(*) AS learners, count(*) FILTER (WHERE classification_status = 'CLASSIFIED') AS classified,
                       count(*) FILTER (WHERE classification_status = 'REQUIRES_CLASSIFICATION') AS requires_classification
                  FROM people.learner GROUP BY source ORDER BY source
                """).query().listOfRows());
        out.put("byType", jdbc.sql("""
                SELECT l.programme_type, t.label AS name, count(*) AS learners,
                       count(*) FILTER (WHERE l.type_source = 'DECISION') AS decided,
                       count(*) FILTER (WHERE l.type_source = 'ENTRY_MODE') AS by_entry_mode,
                       count(*) FILTER (WHERE l.type_source = 'PROGRAMME_CATEGORY') AS by_programme_category,
                       count(*) FILTER (WHERE l.type_source = 'PRELIMINARY_PROGRAMME') AS by_preliminary_programme
                  FROM people.learner l LEFT JOIN finance.programme_type t ON t.code = l.programme_type
                 GROUP BY l.programme_type, t.label, t.ord ORDER BY t.ord NULLS LAST
                """).query().listOfRows());
        return out;
    }

    /** the learners the Academic Office must classify, a page at a time, names A–Z, with what the fields propose and why */
    @Transactional(readOnly = true)
    Map<String, Object> review(String q, int page, int size) {
        int sz = Math.max(1, Math.min(size, 200));
        int pg = Math.max(0, page);
        String like = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT count(*) OVER () AS total_rows, l.source, l.learner_id, l.student_id, l.surname, l.other_names, l.matric_no, l.jamb_no, l.application_no,
                       l.proposed_type, pt.label AS proposed_type_name, l.classification_issue, l.classification_note, l.admission_route, l.study_mode, l.centre_code,
                       l.faculty, l.department, l.programme_code, l.programme, l.programme_category, l.level, l.admission_session, l.status
                  FROM people.learner l LEFT JOIN finance.programme_type pt ON pt.code = l.proposed_type
                 WHERE l.classification_status = 'REQUIRES_CLASSIFICATION'
                   AND (CAST(:q AS text) IS NULL OR lower(concat_ws(' ', l.surname, l.other_names, l.surname, l.matric_no, l.jamb_no, l.application_no)) LIKE CAST(:q AS text))
                 ORDER BY lower(l.surname), lower(l.other_names), l.learner_id
                 LIMIT :n OFFSET :o
                """).param("q", like, Types.VARCHAR).param("n", sz).param("o", pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        out.put("types", jdbc.sql("""
                SELECT code, label AS name, description FROM finance.programme_type
                 WHERE active AND (allowed_categories IS NULL OR cardinality(allowed_categories) > 0) ORDER BY ord, code
                """).query().listOfRows());
        out.put("routes", jdbc.sql("SELECT code, name, entry_mode FROM ref.admission_route WHERE active ORDER BY ord, code").query().listOfRows());
        out.put("centres", jdbc.sql("SELECT code, name FROM ref.centre WHERE active ORDER BY ord, code").query().listOfRows());
        return out;
    }

    /** the Academic Office's or the Registry's decision of one student's programme type, with its reason */
    @Transactional
    Map<String, Object> decide(UUID studentId, String type, String route, String centre, String reason) {
        AuditContextHolder.required();
        jdbc.sql("SELECT people.classify_student(:s, :t, :r, :c, :why)")
                .param("s", studentId).param("t", type).param("r", route, Types.VARCHAR).param("c", centre, Types.VARCHAR).param("why", reason)
                .query(UUID.class).single();
        return of(studentId);
    }

    /** a JUPEB or Preliminary learner who joined the register: the earlier record kept, the progression on the history */
    @Transactional
    Map<String, Object> progression(UUID studentId, String source, String applicationNo, String reason) {
        AuditContextHolder.required();
        jdbc.sql("SELECT people.record_progression(:s, :src, :no, :why)")
                .param("s", studentId).param("src", source).param("no", applicationNo).param("why", reason)
                .query(UUID.class).single();
        return of(studentId);
    }
}
