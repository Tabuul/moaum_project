package ng.edu.moaum.portal.pgadmissions;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V715: postgraduate record management — the School of Postgraduate Studies and the Director of ICT find a postgraduate applicant
 * or student and open the record to correct it. The search reads applicants and students in one list
 * (admissions.pg_record_search); an applicant's record is corrected here (admissions.pg_applicant_edit_apply: identity, contacts,
 * programme, session, previous education — all checked, then all written, or none, on the reading the page was made from); a
 * student's on the student edit page (V642, opened to the same offices for postgraduate students). What each office may do is
 * admissions.pg_edit_grant's (admissions.pg_edit_may), checked on every call; the screen hides what it may not do, the server
 * refuses it regardless. The application number, the state, the fees, the screening and the decisions keep their own workflows.
 */
@RestController
@RequestMapping("/api/v1/pg/records")
class PgRecordController {

    /** the offices that hold any grant on the pages; each act is then checked against the office's own grants */
    private static final String HOLDERS = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_ict','OFFICE_super',"
            + "'OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_admin','OFFICE_audit','OFFICE_deputyaudit')";

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;

    PgRecordController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String office() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    private List<String> permissions() {
        return jdbc.sql("SELECT unnest(admissions.pg_edit_permissions(:o))").param("o", office()).query(String.class).list();
    }

    private void need(String permission) {
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT admissions.pg_edit_may(:o, :p)").param("o", office()).param("p", permission).query(Boolean.class).single())) {
            throw new AccessDeniedException("Your office does not hold " + permission + " on the postgraduate record pages.");
        }
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> json(String text) {
        return text == null ? Map.of() : JSON.readValue(text, Map.class);
    }

    private void fresh(UUID id, String version) {
        String now = jdbc.sql("SELECT admissions.pg_edit_version(:a)").param("a", id).query(String.class).single();
        if (version == null || !version.equals(now)) {
            throw new DomainRuleViolation("PG_EDIT_STALE", "This record was updated by another user. Refresh the record before saving your changes.",
                    new DomainRuleViolation.Remedy("Refresh the record, check what changed, and make your change again.", "You"));
        }
    }

    /* ── the search: applicants and students in one list ── */

    @GetMapping("/search")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    Map<String, Object> search(@RequestParam(required = false) String q, @RequestParam(required = false) String faculty,
                               @RequestParam(required = false) String department, @RequestParam(required = false) String programme,
                               @RequestParam(required = false) String session, @RequestParam(required = false) String kind,
                               @RequestParam(required = false) String state, @RequestParam(required = false) String award,
                               @RequestParam(defaultValue = "200") @Min(1) @Max(500) int limit) {
        List<String> perms = permissions();
        if (!perms.contains("VIEW_PG_APPLICANTS") && !perms.contains("VIEW_PG_STUDENTS") && !perms.contains("VIEW_PG_CHANGE_HISTORY")) {
            throw new AccessDeniedException("Your office holds no grant on the postgraduate record pages.");
        }
        String t = blank(q);
        boolean narrowed = t != null || blank(faculty) != null || blank(department) != null || blank(programme) != null || blank(session) != null
                || blank(state) != null || blank(award) != null;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("permissions", perms);
        out.put("rows", !narrowed ? List.of() : jdbc.sql("SELECT * FROM admissions.pg_record_search(:q, :f, :d, :p, :s, :k, :st, :aw, :lim)")
                .param("q", t, Types.VARCHAR).param("f", blank(faculty), Types.VARCHAR).param("d", blank(department), Types.VARCHAR)
                .param("p", blank(programme), Types.VARCHAR).param("s", blank(session), Types.VARCHAR).param("k", blank(kind), Types.VARCHAR)
                .param("st", blank(state), Types.VARCHAR).param("aw", blank(award), Types.VARCHAR).param("lim", limit).query().listOfRows());
        out.put("narrowed", narrowed);
        out.put("lists", lists());
        return out;
    }

    private Map<String, Object> lists() {
        Map<String, Object> l = new LinkedHashMap<>();
        l.put("sessions", jdbc.sql("SELECT name, state FROM policy.academic_session WHERE archived_at IS NULL AND merged_into IS NULL ORDER BY name DESC").query().listOfRows());
        l.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        l.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department ORDER BY name").query().listOfRows());
        l.put("programmes", jdbc.sql("""
                SELECT p.code, p.name, p.dept_code, coalesce(d.faculty_code, p.faculty_code) AS faculty_code, admissions.pg_award_of(p.pg_award, p.name) AS award
                  FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE p.category = 'POST GRADUATE' AND NOT coalesce(p.archived, false) ORDER BY p.name
                """).query().listOfRows());
        l.put("awards", List.of("PGD", "MSC", "MA", "MED", "MBA", "MPA", "LLM", "MPHIL", "PHD"));
        l.put("applicationStates", List.of("DRAFT", "SUBMITTED", "RETURNED", "DEPT_RECOMMENDED", "DEPT_DECLINED", "FAC_RECOMMENDED", "FAC_DECLINED",
                "OFFERED", "NOT_OFFERED", "ACCEPTED", "ADMITTED"));
        l.put("studentStatuses", List.of("ADMITTED", "ACTIVE", "PROBATION", "DEFERRED", "SUSPENDED", "GRADUATED", "WITHDRAWN", "DORMANT"));
        return l;
    }

    /* ── the applicant's record: read whole, corrected here ── */

    @GetMapping("/applications/{id}/edit")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    Map<String, Object> page(@PathVariable UUID id) {
        List<String> perms = permissions();
        if (perms.isEmpty()) {
            throw new AccessDeniedException("Your office holds no grant on the postgraduate record pages.");
        }
        Map<String, Object> a = jdbc.sql("""
                SELECT a.id, a.application_no, a.session, a.state, a.entry_level, a.programme_code, g.name AS programme, g.dept_code, d.name AS department,
                       g.faculty_code, f.name AS faculty, admissions.pg_award_of(g.pg_award, g.name) AS award, admissions.pg_research_of(g.pg_research, g.pg_award, g.name) AS research,
                       a.specialisation_id, ps.name AS specialisation,
                       p.id AS applicant_id, p.surname, p.other_names, p.sex, p.date_of_birth, p.state_of_origin, p.lga, p.nationality, p.contact_address, p.email, p.phone,
                       p.last_signed_in_at, p.must_change_password,
                       a.prior_institution, a.prior_award, a.prior_class, a.prior_cgpa, a.prior_year, a.proposal_title,
                       a.fee_confirmed_at, a.submitted_at, a.created_at, a.dept_decided_at, a.dept_note, a.fac_decided_at, a.fac_note, a.spgs_decided_at, a.spgs_note,
                       a.accepted_at, a.admitted_at, a.student_id, a.checking_confirmed_at, a.acceptance_confirmed_at, a.return_note, a.returned_at, a.returned_to,
                       l.legacy_application_no, l.decided_on_old_portal, l.migrated_at,
                       ds.state AS documents_state, ds.required AS documents_required, ds.uploaded AS documents_uploaded, ds.missing AS documents_missing
                  FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  JOIN ref.programme g ON g.code = a.programme_code
                  LEFT JOIN ref.department d ON d.code = g.dept_code
                  LEFT JOIN ref.faculty f ON f.code = g.faculty_code
                  LEFT JOIN catalogue.programme_specialisation ps ON ps.id = a.specialisation_id
                  LEFT JOIN admissions.pg_legacy_application l ON l.application_id = a.id
                 CROSS JOIN LATERAL admissions.pg_document_state(a.id) ds
                 WHERE a.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("postgraduate application", id));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("application", a);
        out.put("version", jdbc.sql("SELECT admissions.pg_edit_version(:a)").param("a", id).query(String.class).single());
        out.put("permissions", perms);
        out.put("priorDegrees", jdbc.sql("""
                SELECT id, kind, institution, award, field, class_of_degree, cgpa, year FROM admissions.pg_prior_degree
                 WHERE application_id = :id ORDER BY CASE kind WHEN 'FIRST' THEN 0 ELSE 1 END, year, award
                """).param("id", id).query().listOfRows());
        out.put("referees", jdbc.sql("SELECT id, name, email, phone, institution, position, submitted_at, verdict FROM admissions.pg_referee WHERE application_id = :id ORDER BY name")
                .param("id", id).query().listOfRows());
        out.put("documents", jdbc.sql("SELECT id, kind, filename, content_type, uploaded_at FROM admissions.pg_document WHERE application_id = :id ORDER BY uploaded_at")
                .param("id", id).query().listOfRows());
        out.put("legacyDocuments", jdbc.sql("SELECT kind, label, legacy_ref, attached_at FROM admissions.pg_legacy_document WHERE application_id = :id ORDER BY label")
                .param("id", id).query().listOfRows());
        out.put("screeningRequired", jdbc.sql("SELECT admissions.pg_screening_required(:id)").param("id", id).query(Boolean.class).single());
        out.put("screening", jdbc.sql("""
                SELECT sc.state, sc.venue, sc.scheduled_for, sc.remarks, sc.reason, sc.decided_at, sc.officer_office, sc.source,
                       people.officer_name(sc.officer_id) AS officer
                  FROM admissions.pg_screening sc WHERE sc.application_id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElse(null));
        // the fees, read only: the references and what each came to; a wrong payment is the Bursary's reallocation
        out.put("fees", jdbc.sql("""
                SELECT kind, reference, amount, generated_at, expires_at, confirmed_at, channel FROM admissions.pg_fee_reference
                 WHERE application_id = :id ORDER BY generated_at DESC
                """).param("id", id).query().listOfRows());
        out.put("legacyFees", jdbc.sql("""
                SELECT kind, legacy_reference, amount, paid_on, state, decision_note FROM admissions.pg_legacy_fee WHERE application_id = :id ORDER BY kind, paid_on
                """).param("id", id).query().listOfRows());
        if (a.get("student_id") != null) {
            out.put("student", jdbc.sql("""
                    SELECT s.id, s.admission_no, s.matric_no, s.status, s.current_level, s.entry_session, s.programme_code, g.name AS programme,
                           (SELECT x.stage_label FROM admissions.pg_stages_of(admissions.pg_current_session(), ARRAY[s.id]) x LIMIT 1) AS stage
                      FROM people.student s LEFT JOIN ref.programme g ON g.code = s.programme_code WHERE s.id = :s
                    """).param("s", a.get("student_id")).query().listOfRows().stream().findFirst().orElse(null));
        }
        out.put("edits", jdbc.sql("SELECT * FROM admissions.pg_applicant_edit_history(:id) ORDER BY at DESC").param("id", id).query().listOfRows());
        out.put("lists", lists());
        out.put("specialisations", jdbc.sql("SELECT id, code, name FROM catalogue.programme_specialisation WHERE programme_code = :p AND active ORDER BY name")
                .param("p", a.get("programme_code")).query().listOfRows());
        out.put("priorKinds", List.of("FIRST", "NCE", "ND", "HND", "PGD", "MASTERS", "PHD", "OTHER"));
        return out;
    }

    /** the running specialisations of a programme, for the picker when the programme is changed on the page */
    @GetMapping("/programmes/{code}/specialisations")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> specialisations(@PathVariable String code) {
        need("EDIT_PG_PROGRAMME");
        return jdbc.sql("SELECT id, code, name FROM catalogue.programme_specialisation WHERE programme_code = :p AND active ORDER BY name")
                .param("p", code).query().listOfRows();
    }

    public record Edit(Map<String, String> changes, @Size(max = 2000) String reason, @NotBlank String version, Boolean confirmCritical,
                       @Size(max = 300) String evidence) {
    }

    @PutMapping("/applications/{id}/edit")
    @PreAuthorize(HOLDERS)
    @Transactional
    Map<String, Object> edit(@PathVariable UUID id, @Valid @RequestBody Edit body) {
        need("EDIT_PG_APPLICANT");
        fresh(id, body.version());
        String changes = JSON.writeValueAsString(body.changes() == null ? Map.of() : body.changes());
        return json(jdbc.sql("SELECT admissions.pg_applicant_edit_apply(:a, :c::jsonb, :r, :v, :k, :e)::text")
                .param("a", id).param("c", changes).param("r", body.reason(), Types.VARCHAR).param("v", body.version())
                .param("k", Boolean.TRUE.equals(body.confirmCritical())).param("e", blank(body.evidence()), Types.VARCHAR).query(String.class).single());
    }

    public record PriorDegrees(List<Map<String, String>> rows, @Size(max = 2000) String reason, @NotBlank String version) {
    }

    @PutMapping("/applications/{id}/edit/prior-degrees")
    @PreAuthorize(HOLDERS)
    @Transactional
    Map<String, Object> priorDegrees(@PathVariable UUID id, @Valid @RequestBody PriorDegrees body) {
        need("EDIT_PG_APPLICANT");
        fresh(id, body.version());
        String rows = JSON.writeValueAsString(body.rows() == null ? List.of() : body.rows());
        return json(jdbc.sql("SELECT admissions.pg_prior_degrees_set(:a, :rows::jsonb, :r, :v)::text")
                .param("a", id).param("rows", rows).param("r", body.reason(), Types.VARCHAR).param("v", body.version()).query(String.class).single());
    }

    @GetMapping("/applications/{id}/edit/history")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history(@PathVariable UUID id) {
        need("VIEW_PG_CHANGE_HISTORY");
        return jdbc.sql("SELECT * FROM admissions.pg_applicant_edit_history(:id) ORDER BY at DESC").param("id", id).query().listOfRows();
    }

    /* ── the latest corrections, applicants' and students' ── */

    @GetMapping("/history")
    @PreAuthorize(HOLDERS)
    @Transactional(readOnly = true)
    Map<String, Object> recent(@RequestParam(defaultValue = "200") @Min(1) @Max(1000) int limit) {
        need("VIEW_PG_CHANGE_HISTORY");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", jdbc.sql("SELECT * FROM admissions.pg_edit_recent(:n)").param("n", limit).query().listOfRows());
        out.put("limit", limit);
        return out;
    }
}
