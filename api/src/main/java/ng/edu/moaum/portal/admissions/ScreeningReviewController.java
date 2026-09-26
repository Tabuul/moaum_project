package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The screening officers' desk (V269): the submitted screening forms of a session as a queue with its counts, searched and
 * filtered on the server; one form in full — the answers on the catalogue, the institutions, the O'Level results declared
 * beside JAMB's, the documents, the trail, the engine's reading; the decision — successful, unsuccessful with the reason,
 * or returned for correction. The admission pipeline counted for the Admissions dashboard. A faculty office is held to its
 * faculty; nobody outside the office decides.
 */
@RestController
class ScreeningReviewController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String OFFICE = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final String BASE = "/api/v1/admissions/sessions/{session}/{year}/screening-review";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    ScreeningReviewController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    private static UUID actor() {
        return AuditContextHolder.required().actorId();
    }

    private static String office() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse(null);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static final String LIST = """
            SELECT a.id, a.application_no, a.session, a.accepted_at, a.cleared_at, c.surname, c.other_names, c.jamb_reg_no, c.programme, c.entry_mode,
                   p.code AS programme_code, f.code AS faculty_code, f.name AS faculty, d.code AS dept_code, d.name AS department,
                   sf.screening_no, sf.state, sf.version, sf.submitted_at, sf.review_started_at, sf.decided_at, sf.decision_reason, sf.returned_note, sf.remarks,
                   (SELECT pe.surname || ', ' || pe.given_names FROM iam.person pe WHERE pe.id = sf.decided_by) AS decided_officer,
                   (SELECT count(*) FROM admissions.application_document x WHERE x.application_id = a.id AND x.status <> 'REJECTED') AS documents,
                   (SELECT q.state FROM admissions.programme_change_request q WHERE q.application_id = a.id ORDER BY q.requested_at DESC LIMIT 1) AS change_state,
                   (SELECT q.to_programme FROM admissions.programme_change_request q WHERE q.application_id = a.id ORDER BY q.requested_at DESC LIMIT 1) AS change_to,
                   s.id AS student_id, s.admission_no, s.matric_no,
                   CASE WHEN sf.submitted_at IS NOT NULL AND sf.state IN ('SUBMITTED', 'UNDER_REVIEW') AND sf.submitted_at < now() - interval '7 days' THEN true ELSE false END AS overdue
              FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
              LEFT JOIN admissions.screening_form sf ON sf.application_id = a.id
              LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme) LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN people.student s ON s.candidate_id = c.id
            """;

    @GetMapping(BASE)
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@PathVariable String session, @PathVariable String year, @RequestParam(required = false) String state, @RequestParam(required = false) String fac,
                             @RequestParam(required = false) String dept, @RequestParam(required = false) String prog, @RequestParam(required = false) String q,
                             @RequestParam(required = false) String from, @RequestParam(required = false) String to, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "200") int size) {
        String s = session + "/" + year;
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), blank(prog));
        String st = blank(state) == null ? null : state.trim().toUpperCase();
        String pred = st == null ? "" : switch (st) {
            case "PENDING" -> " AND (sf.state IS NULL OR sf.state = 'DRAFT') AND a.accepted_at IS NOT NULL AND admissions.screening_required(a.id)";
            case "SUBMITTED" -> " AND sf.state = 'SUBMITTED'";
            case "UNDER_REVIEW" -> " AND sf.state = 'UNDER_REVIEW'";
            case "REVIEW" -> " AND sf.state IN ('SUBMITTED', 'UNDER_REVIEW')";
            case "SUCCESSFUL", "UNSUCCESSFUL", "RETURNED" -> " AND sf.state = '" + st + "'";
            case "CHANGE" -> " AND sf.state = 'UNSUCCESSFUL' AND EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = a.id AND q.state = 'REQUESTED')";
            case "OVERDUE" -> " AND sf.state IN ('SUBMITTED', 'UNDER_REVIEW') AND sf.submitted_at < now() - interval '7 days'";
            case "COMPLETED" -> " AND (sf.state = 'SUCCESSFUL' OR EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = a.id AND q.state = 'APPROVED'))";
            default -> "";
        };
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        int sz = Math.max(1, Math.min(size, 1000)), pg = Math.max(0, page);
        List<Map<String, Object>> rows = jdbc.sql(LIST + """
                 WHERE a.session = :s AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL AND a.accepted_at IS NOT NULL
                   AND (:fac::text IS NULL OR f.code = :fac) AND (:dept::text IS NULL OR d.code = :dept) AND (:prog::text IS NULL OR p.code = :prog)
                   AND (:from::date IS NULL OR sf.submitted_at::date >= :from::date) AND (:to::date IS NULL OR sf.submitted_at::date <= :to::date)
                   AND (:q::text IS NULL OR lower(c.surname || ' ' || c.other_names) LIKE :q OR lower(c.other_names || ' ' || c.surname) LIKE :q OR lower(c.jamb_reg_no) LIKE :q
                        OR lower(a.application_no) LIKE :q OR lower(coalesce(sf.screening_no, '')) LIKE :q OR lower(c.programme) LIKE :q)
                """ + pred + " ORDER BY c.surname, c.other_names LIMIT :n OFFSET :o")
                .param("s", s).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .param("from", blank(from), Types.VARCHAR).param("to", blank(to), Types.VARCHAR).param("q", needle, Types.VARCHAR).param("n", sz).param("o", pg * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rows", rows);
        out.put("stats", jdbc.sql("""
                SELECT count(*) FILTER (WHERE sf.state IS NOT NULL) AS total,
                       count(*) FILTER (WHERE (sf.state IS NULL OR sf.state = 'DRAFT') AND admissions.screening_required(a.id)) AS pending,
                       count(*) FILTER (WHERE sf.state = 'SUBMITTED') AS submitted,
                       count(*) FILTER (WHERE sf.state = 'UNDER_REVIEW') AS in_review,
                       count(*) FILTER (WHERE sf.state = 'SUCCESSFUL') AS successful,
                       count(*) FILTER (WHERE sf.state = 'UNSUCCESSFUL') AS unsuccessful,
                       count(*) FILTER (WHERE sf.state = 'RETURNED') AS returned,
                       count(*) FILTER (WHERE sf.state = 'UNSUCCESSFUL' AND EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = a.id AND q.state = 'REQUESTED')) AS change_requested,
                       count(*) FILTER (WHERE sf.state = 'SUCCESSFUL' OR EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = a.id AND q.state = 'APPROVED')) AS completed,
                       count(*) FILTER (WHERE sf.state IN ('SUBMITTED', 'UNDER_REVIEW') AND sf.submitted_at < now() - interval '7 days') AS overdue
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id LEFT JOIN admissions.screening_form sf ON sf.application_id = a.id
                  LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme)
                 WHERE a.session = :s AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL AND a.accepted_at IS NOT NULL AND (:fac::text IS NULL OR p.faculty_code = :fac)
                """).param("s", s).param("fac", b.fac(), Types.VARCHAR).query().singleRow());
        out.put("policy", jdbc.sql("SELECT * FROM admissions.screening_policy WHERE session = :s").param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("options", jdbc.sql("""
                SELECT DISTINCT f.code AS faculty_code, f.name AS faculty, d.code AS dept_code, d.name AS department, p.code AS programme_code, p.name AS programme
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme)
                  JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE a.session = :s AND a.accepted_at IS NOT NULL ORDER BY f.name, d.name, p.name
                """).param("s", s).query().listOfRows());
        return out;
    }

    private Map<String, Object> detail(String s, UUID app) {
        Map<String, Object> row = jdbc.sql(LIST + " WHERE a.id = :a AND a.session = :s").param("a", app).param("s", s).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("application in " + s, app));
        scope.bound(String.valueOf(row.get("faculty_code")), null, null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("application", row);
        out.put("form", jdbc.sql("SELECT * FROM admissions.screening_form WHERE application_id = :a").param("a", app).query().listOfRows().stream().findFirst().orElse(null));
        out.put("answers", jdbc.sql("""
                SELECT bf.section, bf.field, bf.label, bf.ord, x.value FROM ref.biodata_field bf JOIN admissions.screening_answer x ON x.field = bf.field AND x.application_id = :a
                 WHERE btrim(x.value) <> '' ORDER BY CASE bf.section WHEN 'personal' THEN 1 WHEN 'origin' THEN 2 WHEN 'contact' THEN 3 WHEN 'family' THEN 4 WHEN 'kin' THEN 5 WHEN 'education' THEN 6 WHEN 'health' THEN 7 ELSE 8 END, bf.ord, bf.label
                """).param("a", app).query().listOfRows());
        out.put("institutions", jdbc.sql("SELECT ord, name, from_year, to_year, certificate, award_year FROM admissions.screening_institution WHERE application_id = :a AND active ORDER BY ord").param("a", app).query().listOfRows());
        out.put("olevel", jdbc.sql("SELECT ord, exam_body, exam_number, exam_year, subject, grade FROM admissions.screening_olevel WHERE application_id = :a AND active ORDER BY ord").param("a", app).query().listOfRows());
        out.put("jambOlevel", jdbc.sql("""
                SELECT st.exam_body, st.exam_year, st.exam_number, g.subject, g.grade FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  JOIN admissions.olevel_sitting st ON st.session = c.session AND st.jamb_key = c.jamb_key JOIN admissions.olevel_grade g ON g.sitting_id = st.id WHERE a.id = :a ORDER BY st.ord, g.subject
                """).param("a", app).query().listOfRows());
        out.put("utme", jdbc.sql("""
                SELECT r.aggregate, (SELECT string_agg(e.value, ', ' ORDER BY e.key) FROM jsonb_each_text(r.raw) e WHERE regexp_replace(lower(e.key), '[^a-z0-9]', '', 'g') IN ('subject1','subject2','subject3','subject4') AND nullif(btrim(e.value), '') IS NOT NULL) AS subjects
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id JOIN admissions.caps_row_live r ON r.session = c.session AND r.jamb_key = c.jamb_key WHERE a.id = :a LIMIT 1
                """).param("a", app).query().listOfRows().stream().findFirst().orElse(null));
        out.put("prefill", jdbc.sql("""
                SELECT r.sex, r.state_of_origin, r.lga, acc.email, acc.phone, a.next_of_kin, c.entry_mode, c.entry_level,
                       (SELECT x.payload ->> 'dob' FROM admissions.attachment x WHERE x.candidate_id = c.id AND x.kind = 'DATE_OF_BIRTH' ORDER BY x.arrived_at DESC LIMIT 1) AS date_of_birth
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id JOIN admissions.applicant_account acc ON acc.id = a.account_id LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from WHERE a.id = :a
                """).param("a", app).query().singleRow());
        out.put("documents", jdbc.sql("SELECT id, kind, filename, content_type, bytes, uploaded_at, status, review_note, reviewed_at FROM admissions.application_document WHERE application_id = :a ORDER BY kind, uploaded_at DESC").param("a", app).query().listOfRows());
        out.put("missing", jdbc.sql("SELECT * FROM admissions.screening_missing(:a)").param("a", app).query().listOfRows());
        out.put("events", jdbc.sql("SELECT e.action, e.detail, e.actor_office, e.at, (SELECT pe.surname || ', ' || pe.given_names FROM iam.person pe WHERE pe.id = e.actor) AS officer FROM admissions.screening_event e WHERE e.application_id = :a ORDER BY e.at DESC").param("a", app).query().listOfRows());
        out.put("eligibility", jdbc.sql("""
                SELECT r.applied_result, r.alternatives, r.evaluated_at, r.rules_version,
                       (SELECT string_agg(x.programme, ' · ' ORDER BY x.ord, x.programme) FROM admissions.eligibility_result x WHERE x.run_id = r.id AND x.kind = 'ALTERNATIVE' AND x.result IN ('ELIGIBLE','ELIGIBLE_SCREENING')) AS eligible_alternatives,
                       (SELECT x.reasons FROM admissions.eligibility_result x WHERE x.run_id = r.id AND x.kind = 'APPLIED') AS reasons
                  FROM admissions.eligibility_run r WHERE r.application_id = :a AND r.superseded_at IS NULL ORDER BY r.evaluated_at DESC LIMIT 1
                """).param("a", app).query().listOfRows().stream().findFirst().orElse(null));
        out.put("changes", jdbc.sql("SELECT id, from_programme, to_programme, state, requested_at, decided_at, decision_note, note FROM admissions.programme_change_request WHERE application_id = :a ORDER BY requested_at DESC").param("a", app).query().listOfRows());
        out.put("status", jdbc.sql("SELECT * FROM admissions.admission_status(:a)").param("a", app).query().singleRow());
        out.put("tracker", jdbc.sql("SELECT admissions.admission_tracker(:a)::text").param("a", app).query(String.class).single());
        out.put("entitlement", jdbc.sql("SELECT * FROM admissions.acceptance_entitlement(:a)").param("a", app).query().singleRow());
        return out;
    }

    @GetMapping(BASE + "/{appId}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable String session, @PathVariable String year, @PathVariable UUID appId) {
        return detail(session + "/" + year, appId);
    }

    @PostMapping(BASE + "/{appId}/start")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> start(@PathVariable String session, @PathVariable String year, @PathVariable UUID appId) {
        String s = session + "/" + year;
        detail(s, appId);
        jdbc.sql("SELECT admissions.screening_start_review(:a, :by)").param("a", appId).param("by", actor(), Types.OTHER).query().singleRow();
        return detail(s, appId);
    }

    public record DecisionIn(@NotBlank String decision, @Size(max = 1000) String reason, @Size(max = 2000) String remarks) {
    }

    @PostMapping(BASE + "/{appId}/decide")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> decide(@PathVariable String session, @PathVariable String year, @PathVariable UUID appId, @Valid @RequestBody DecisionIn body) {
        String s = session + "/" + year;
        detail(s, appId);
        String d = body.decision().trim().toUpperCase();
        if (!List.of("SUCCESSFUL", "UNSUCCESSFUL", "RETURNED").contains(d)) {
            throw new DomainRuleViolation("SCR_DECISION", "'" + body.decision() + "' is not a screening decision.", new DomainRuleViolation.Remedy("SUCCESSFUL, UNSUCCESSFUL with the reason, or RETURNED with what must be corrected.", "Screening officer"));
        }
        jdbc.sql("SELECT admissions.screening_decide(:a, :d, :r, :m, :by, :o)").param("a", appId).param("d", d).param("r", body.reason(), Types.VARCHAR).param("m", body.remarks(), Types.VARCHAR)
                .param("by", actor(), Types.OTHER).param("o", office(), Types.VARCHAR).query().singleRow();
        return detail(s, appId);
    }

    /* ── the pipeline, and the policy ── */

    @GetMapping("/api/v1/admissions/sessions/{session}/{year}/pipeline")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> pipeline(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT * FROM admissions.pipeline_stats(:s)").param("s", s).query().singleRow());
        out.put("session", s);
        return out;
    }

    public record PolicyIn(Boolean enabled, List<@Size(max = 40) String> requiredDocuments, List<@Size(max = 60) String> requiredFields, @Size(max = 2000) String instructions) {
    }

    @PutMapping("/api/v1/admissions/sessions/{session}/{year}/screening-policy")
    @PreAuthorize(OFFICE)
    @Transactional
    Map<String, Object> policy(@PathVariable String session, @PathVariable String year, @RequestBody PolicyIn body) {
        String s = session + "/" + year;
        jdbc.sql("INSERT INTO admissions.screening_policy (session) VALUES (:s) ON CONFLICT (session) DO NOTHING").param("s", s).update();
        jdbc.sql("""
                UPDATE admissions.screening_policy SET enabled = coalesce(:e, enabled), enabled_from = CASE WHEN :e AND NOT enabled THEN now() ELSE enabled_from END,
                       required_documents = coalesce(:d::text[], required_documents), required_fields = coalesce(:f::text[], required_fields), instructions = coalesce(:i, instructions), updated_at = now()
                 WHERE session = :s
                """).param("s", s).param("e", body.enabled(), Types.BOOLEAN)
                .param("d", body.requiredDocuments() == null ? null : body.requiredDocuments().stream().map(x -> x.trim().toUpperCase()).toArray(String[]::new), Types.ARRAY)
                .param("f", body.requiredFields() == null ? null : body.requiredFields().stream().map(String::trim).toArray(String[]::new), Types.ARRAY)
                .param("i", body.instructions(), Types.VARCHAR).update();
        return jdbc.sql("SELECT * FROM admissions.screening_policy WHERE session = :s").param("s", s).query().singleRow();
    }
}
