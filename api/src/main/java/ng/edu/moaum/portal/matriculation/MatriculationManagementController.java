package ng.edu.moaum.portal.matriculation;

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
 * Matriculation Management (V267): the exercise faculty by faculty — the eligible students grouped by
 * programme, the numbers proposed and reserved, reviewed, corrected with a reason, marked ready, and
 * issued in one transaction that also moves the student's sign-in identity to the number. Preparing is
 * not issuing: nothing reaches the student record until the authorised officer confirms the issue.
 * A Faculty Officer is held to their faculty by {@link OfficeScope}; the all-faculties view is the
 * Registry's and the Academic Office's.
 */
@RestController
class MatriculationManagementController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_facultyofficer','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    /** generate, validate, correct, mark ready */
    private static final String PREPARERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_facultyofficer')";
    /** issue and cancel */
    private static final String ISSUERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";
    private static final String BASE = "/api/v1/matriculation/sessions/{s}/{y}/management";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    MatriculationManagementController(JdbcClient jdbc, OfficeScope scope) {
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

    /** the faculty a request is held to: a Faculty Officer's own, else the one asked for */
    private String facultyOf(String fac) {
        OfficeScope.Bound b = scope.bound(blank(fac) == null ? null : fac.trim().toUpperCase(), null, null);
        return b.fac() == null ? null : b.fac().toUpperCase();
    }

    private boolean canViewAll() {
        return !scope.actingFacultyOffice();
    }

    private Map<String, Object> batch(UUID id) {
        return jdbc.sql("""
                SELECT b.*, f.name AS faculty, r.issued AS run_issued,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.prepared_by) AS prepared_officer,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.reviewed_by) AS reviewed_officer,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.issued_by) AS issued_officer,
                       (SELECT count(*) FROM people.matric_batch_row x WHERE x.batch_id = b.id AND x.state = 'DROPPED') AS dropped,
                       (SELECT count(*) FROM people.matric_batch_row x WHERE x.batch_id = b.id AND x.edited AND x.state <> 'DROPPED') AS edited
                  FROM people.matric_batch b JOIN ref.faculty f ON f.code = b.faculty_code LEFT JOIN people.matriculation_run r ON r.id = b.run_id
                 WHERE b.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("matriculation batch", id));
    }

    private Map<String, Object> batchInScope(String session, UUID id) {
        Map<String, Object> b = batch(id);
        if (!session.equals(b.get("session"))) throw new NotFound("matriculation batch in " + session, id);
        scope.bound(String.valueOf(b.get("faculty_code")), null, null);
        return b;
    }

    private List<Map<String, Object>> rows(UUID batch) {
        return jdbc.sql("""
                SELECT br.id, br.student_id, s.admission_no, s.surname, s.other_names, s.entry_session, s.status, s.matric_no, br.programme_code, p.name AS programme, br.dept_code, d.name AS department,
                       br.series_code, br.sequence, br.proposed_no, br.generated_no, br.edited, br.previous_no, br.edit_reason, br.edited_at, br.problems, br.state, br.drop_reason, br.issued_no, br.issued_at,
                       (SELECT pe.surname || ', ' || pe.given_names FROM iam.person pe WHERE pe.id = br.edited_by) AS edited_officer
                  FROM people.matric_batch_row br JOIN people.student s ON s.id = br.student_id
                  LEFT JOIN ref.programme p ON p.code = br.programme_code LEFT JOIN ref.department d ON d.code = br.dept_code
                 WHERE br.batch_id = :b ORDER BY s.surname, s.other_names
                """).param("b", batch).query().listOfRows();
    }

    private Map<String, Object> detail(UUID id) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("batch", batch(id));
        out.put("rows", rows(id));
        out.put("edits", jdbc.sql("""
                SELECT e.*, s.surname, s.other_names, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = e.edited_by) AS officer
                  FROM people.matric_batch_edit e JOIN people.student s ON s.id = e.student_id WHERE e.batch_id = :b ORDER BY e.edited_at DESC
                """).param("b", id).query().listOfRows());
        return out;
    }

    /* ── the page: the faculty's students, grouped by the client, with the open batch ── */

    @GetMapping(BASE)
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> page(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String fac, @RequestParam(required = false) String prog,
                             @RequestParam(required = false) String status, @RequestParam(required = false) String q) {
        String session = s + "/" + y;
        String faculty = facultyOf(fac);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("canViewAll", canViewAll());
        out.put("boundFaculty", scope.actingFacultyOffice() ? faculty : null);
        out.put("separateDuties", jdbc.sql("SELECT separate_duties FROM people.matric_format WHERE id = 'UNIVERSITY'").query(Boolean.class).optional().orElse(false));
        out.put("faculties", jdbc.sql("SELECT code, name, matric_code, matric_series FROM ref.faculty" + (faculty != null && !canViewAll() ? " WHERE code = :f" : "") + " ORDER BY name")
                .param("f", faculty, Types.VARCHAR).query().listOfRows());
        out.put("batches", jdbc.sql("""
                SELECT b.id, b.ref, b.faculty_code, f.name AS faculty, b.state, b.students, b.valid, b.conflicts, b.issued, b.prepared_at, b.generated_at, b.reviewed_at, b.issued_at, b.cancelled_at, b.cancel_reason,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.prepared_by) AS prepared_officer,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.issued_by) AS issued_officer
                  FROM people.matric_batch b JOIN ref.faculty f ON f.code = b.faculty_code
                 WHERE b.session = :s AND (:f::text IS NULL OR b.faculty_code = :f) ORDER BY b.prepared_at DESC
                """).param("s", session).param("f", canViewAll() ? null : faculty, Types.VARCHAR).query().listOfRows());
        if (faculty == null) {
            return out;
        }
        String name = jdbc.sql("SELECT name FROM ref.faculty WHERE code = :c").param("c", faculty).query(String.class).optional().orElseThrow(() -> new NotFound("faculty", faculty));
        String st = blank(status) == null ? "ALL" : status.trim().toUpperCase();
        String pred = switch (st) {
            case "ELIGIBLE" -> " AND x.eligible";
            case "PREPARED" -> " AND x.row_id IS NOT NULL";
            case "PENDING" -> " AND NOT x.eligible AND x.matric_no IS NULL";
            case "ISSUED", "MATRICULATED" -> " AND x.matric_no IS NOT NULL";
            case "CONFLICTS" -> " AND x.row_id IS NOT NULL AND cardinality(x.problems) > 0";
            case "UNPREPARED" -> " AND x.eligible AND x.row_id IS NULL";
            default -> "";
        };
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        List<Map<String, Object>> students = jdbc.sql("""
                SELECT x.* FROM people.matric_candidates(:s, :f) x
                 WHERE (:p::text IS NULL OR x.programme_code = :p)
                   AND (:q::text IS NULL OR lower(x.surname || ' ' || x.other_names) LIKE :q OR lower(x.other_names || ' ' || x.surname) LIKE :q OR lower(coalesce(x.admission_no, '')) LIKE :q
                        OR lower(coalesce(x.matric_no, '')) LIKE :q OR lower(coalesce(x.proposed_no, '')) LIKE :q OR lower(x.programme) LIKE :q OR x.student_id::text LIKE :q OR lower(coalesce(x.series_code, '')) LIKE :q
                        OR EXISTS (SELECT 1 FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id JOIN people.student st ON st.candidate_id = c.id WHERE st.id = x.student_id AND lower(a.application_no) LIKE :q))
                """ + pred + " ORDER BY x.surname, x.other_names")
                .param("s", session).param("f", faculty).param("p", blank(prog) == null ? null : prog.trim().toUpperCase(), Types.VARCHAR).param("q", needle, Types.VARCHAR).query().listOfRows();
        Map<String, Object> kpis = jdbc.sql("""
                SELECT count(*) FILTER (WHERE x.eligible) AS eligible,
                       count(*) FILTER (WHERE x.row_id IS NOT NULL) AS prepared,
                       count(*) FILTER (WHERE x.eligible AND x.row_id IS NULL) AS unprepared,
                       count(*) FILTER (WHERE NOT x.eligible AND x.matric_no IS NULL) AS pending,
                       count(*) FILTER (WHERE x.matric_no IS NOT NULL) AS already,
                       count(*) FILTER (WHERE x.row_id IS NOT NULL AND cardinality(x.problems) > 0) AS conflicts,
                       (SELECT count(*) FROM people.matric_batch_row br JOIN people.matric_batch b ON b.id = br.batch_id WHERE b.session = :s AND b.faculty_code = :f AND br.state = 'ISSUED') AS issued
                  FROM people.matric_candidates(:s, :f) x
                """).param("s", session).param("f", faculty).query().singleRow();
        Map<String, Object> fx = new LinkedHashMap<>();
        fx.put("code", faculty);
        fx.put("name", name);
        fx.put("listState", jdbc.sql("SELECT state FROM people.faculty_list WHERE session = :s AND faculty_code = :f").param("s", session).param("f", faculty).query(String.class).optional().orElse("NOT_RETURNED"));
        fx.put("kpis", kpis);
        fx.put("programmes", jdbc.sql("""
                SELECT x.programme_code AS code, x.programme AS name, x.dept_code, x.department, count(*) AS students, count(*) FILTER (WHERE x.eligible) AS eligible,
                       count(*) FILTER (WHERE x.row_id IS NOT NULL) AS prepared, count(*) FILTER (WHERE x.matric_no IS NOT NULL) AS matriculated
                  FROM people.matric_candidates(:s, :f) x GROUP BY 1, 2, 3, 4 ORDER BY x.programme
                """).param("s", session).param("f", faculty).query().listOfRows());
        fx.put("students", students);
        UUID open = jdbc.sql("SELECT id FROM people.matric_batch WHERE session = :s AND faculty_code = :f AND state NOT IN ('ISSUED','CANCELLED')").param("s", session).param("f", faculty).query(UUID.class).optional().orElse(null);
        fx.put("batch", open == null ? null : detail(open));
        out.put("faculty", fx);
        return out;
    }

    /* ── every faculty, before the final issuance ── */

    @GetMapping(BASE + "/overview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@PathVariable String s, @PathVariable String y) {
        if (!canViewAll()) {
            throw new DomainRuleViolation("SCOPE_FACULTY", "The all-faculties view is the Registry's and the Academic Office's; your office is bound to its faculty.",
                    new DomainRuleViolation.Remedy("Open your own faculty on the Faculty view.", "You"));
        }
        String session = s + "/" + y;
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM people.matric_overview(:s)").param("s", session).query().listOfRows();
        Map<String, Object> totals = jdbc.sql("""
                SELECT count(*) FILTER (WHERE o.eligible > 0 OR o.prepared > 0 OR o.issued > 0) AS faculties, sum(o.eligible) AS eligible, sum(o.pending) AS pending, sum(o.already) AS already,
                       sum(o.prepared) AS prepared, sum(o.valid) AS valid, sum(o.conflicts) AS conflicts, sum(o.issued) AS issued,
                       count(*) FILTER (WHERE o.batch_state = 'READY_FOR_ISSUANCE') AS ready, count(*) FILTER (WHERE o.batch_state IN ('DRAFT','GENERATED')) AS in_review,
                       (SELECT count(DISTINCT br.programme_code) FROM people.matric_batch_row br JOIN people.matric_batch b ON b.id = br.batch_id WHERE b.session = :s AND b.state NOT IN ('ISSUED','CANCELLED') AND br.state = 'PROPOSED') AS programmes
                  FROM people.matric_overview(:s) o
                """).param("s", session).query().singleRow();
        return Map.of("session", session, "faculties", rows, "totals", totals);
    }

    /* ── generation: preparation, never issuance ── */

    public record GenerateIn(@Size(max = 20) String programme) {
    }

    @PostMapping(BASE + "/faculties/{code}/generate")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> generate(@PathVariable String s, @PathVariable String y, @PathVariable String code, @RequestBody(required = false) GenerateIn body) {
        String session = s + "/" + y;
        String faculty = facultyOf(code);
        String prog = body == null ? null : blank(body.programme());
        if (prog != null) scope.bound(faculty, null, prog.toUpperCase());
        UUID id = jdbc.sql("SELECT people.matric_batch_generate(:s, :f, :p, :by, :o)").param("s", session).param("f", faculty).param("p", prog == null ? null : prog.toUpperCase(), Types.VARCHAR)
                .param("by", actor(), Types.OTHER).param("o", office(), Types.VARCHAR).query(UUID.class).single();
        return detail(id);
    }

    @GetMapping(BASE + "/batches/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable String s, @PathVariable String y, @PathVariable UUID id) {
        batchInScope(s + "/" + y, id);
        return detail(id);
    }

    @PostMapping(BASE + "/batches/{id}/validate")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> validate(@PathVariable String s, @PathVariable String y, @PathVariable UUID id) {
        batchInScope(s + "/" + y, id);
        jdbc.sql("SELECT * FROM people.matric_batch_validate(:b)").param("b", id).query().singleRow();
        return detail(id);
    }

    public record EditIn(@NotBlank @Size(max = 40) String matricNo, @NotBlank @Size(max = 500) String reason) {
    }

    @PutMapping(BASE + "/batches/{id}/rows/{rowId}")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> edit(@PathVariable String s, @PathVariable String y, @PathVariable UUID id, @PathVariable UUID rowId, @Valid @RequestBody EditIn body) {
        batchInScope(s + "/" + y, id);
        if (!jdbc.sql("SELECT count(*) FROM people.matric_batch_row WHERE id = :r AND batch_id = :b").param("r", rowId).param("b", id).query(Long.class).single().equals(1L)) {
            throw new NotFound("row on batch", rowId);
        }
        jdbc.sql("SELECT people.matric_batch_edit_row(:r, :n, :why, :by, :o)").param("r", rowId).param("n", body.matricNo()).param("why", body.reason())
                .param("by", actor(), Types.OTHER).param("o", office(), Types.VARCHAR).query().singleRow();
        return detail(id);
    }

    public record ReasonIn(@NotBlank @Size(max = 500) String reason) {
    }

    @PostMapping(BASE + "/batches/{id}/rows/{rowId}/drop")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> drop(@PathVariable String s, @PathVariable String y, @PathVariable UUID id, @PathVariable UUID rowId, @Valid @RequestBody ReasonIn body) {
        batchInScope(s + "/" + y, id);
        jdbc.sql("SELECT people.matric_batch_drop_row(:r, :why)").param("r", rowId).param("why", body.reason()).query().singleRow();
        return detail(id);
    }

    @PostMapping(BASE + "/batches/{id}/ready")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> ready(@PathVariable String s, @PathVariable String y, @PathVariable UUID id) {
        batchInScope(s + "/" + y, id);
        jdbc.sql("SELECT people.matric_batch_ready(:b, :by, :o)").param("b", id).param("by", actor(), Types.OTHER).param("o", office(), Types.VARCHAR).query().singleRow();
        return detail(id);
    }

    public record IssueIn(Boolean confirm) {
    }

    /** the official act: one transaction, every student or none; the record verified afterwards */
    @PostMapping(BASE + "/batches/{id}/issue")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> issue(@PathVariable String s, @PathVariable String y, @PathVariable UUID id, @RequestBody(required = false) IssueIn body) {
        batchInScope(s + "/" + y, id);
        if (body == null || !Boolean.TRUE.equals(body.confirm())) {
            throw new DomainRuleViolation("MAT_CONFIRM_ISSUE", "Issuing matriculation numbers is confirmed explicitly.",
                    new DomainRuleViolation.Remedy("Read the final review, then press Confirm & Issue.", "You"));
        }
        Map<String, Object> r = jdbc.sql("SELECT * FROM people.matric_batch_issue(:b, :by, :o)").param("b", id).param("by", actor(), Types.OTHER).param("o", office(), Types.VARCHAR).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(detail(id));
        out.put("result", r);
        out.put("verification", jdbc.sql("SELECT * FROM people.matric_batch_verify(:b)").param("b", id).query().singleRow());
        return out;
    }

    @PostMapping(BASE + "/batches/{id}/cancel")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> cancel(@PathVariable String s, @PathVariable String y, @PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        batchInScope(s + "/" + y, id);
        jdbc.sql("SELECT people.matric_batch_cancel(:b, :why, :by)").param("b", id).param("why", body.reason()).param("by", actor(), Types.OTHER).query().singleRow();
        return detail(id);
    }

    /* ── the registers: issued, pending ── */

    @GetMapping(BASE + "/issued")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> issued(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String fac, @RequestParam(required = false) String prog,
                                     @RequestParam(required = false) String q, @RequestParam(required = false) String batch, @RequestParam(required = false) String from, @RequestParam(required = false) String to) {
        String session = s + "/" + y;
        String faculty = facultyOf(fac);
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        return jdbc.sql("""
                SELECT h.matric_no, h.issued_at, h.series_code, h.sequence, h.reason, s.id AS student_id, s.admission_no, s.surname, s.other_names, s.status, s.entry_session,
                       p.code AS programme_code, p.name AS programme, d.name AS department, f.code AS faculty_code, f.name AS faculty, r.ref AS run_ref, b.ref AS batch_ref,
                       (SELECT u.previous_username FROM people.student_username_change u WHERE u.student_id = s.id AND u.new_username = h.matric_no ORDER BY u.changed_at DESC LIMIT 1) AS previous_username,
                       (SELECT pe.surname || ', ' || pe.given_names FROM iam.person pe WHERE pe.id = h.issued_by) AS issued_officer
                  FROM people.matric_history h JOIN people.student s ON s.id = h.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN people.matriculation_run r ON r.id = h.run_id LEFT JOIN people.matric_batch b ON b.id = h.run_id
                 WHERE (r.session = :s OR s.entry_session = :s)
                   AND (:f::text IS NULL OR f.code = :f) AND (:p::text IS NULL OR p.code = :p) AND (:b::text IS NULL OR b.ref = :b OR r.ref = :b)
                   AND (:from::date IS NULL OR h.issued_at::date >= :from::date) AND (:to::date IS NULL OR h.issued_at::date <= :to::date)
                   AND (:q::text IS NULL OR lower(s.surname || ' ' || s.other_names) LIKE :q OR lower(s.other_names || ' ' || s.surname) LIKE :q OR lower(h.matric_no) LIKE :q OR lower(coalesce(s.admission_no, '')) LIKE :q OR lower(coalesce(p.name, '')) LIKE :q)
                 ORDER BY s.surname, s.other_names
                """).param("s", session).param("f", faculty, Types.VARCHAR).param("p", blank(prog) == null ? null : prog.trim().toUpperCase(), Types.VARCHAR)
                .param("b", blank(batch), Types.VARCHAR).param("from", blank(from), Types.VARCHAR).param("to", blank(to), Types.VARCHAR).param("q", needle, Types.VARCHAR).query().listOfRows();
    }

    @GetMapping(BASE + "/pending")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> pending(@PathVariable String s, @PathVariable String y, @RequestParam(required = false) String fac) {
        String session = s + "/" + y;
        String faculty = facultyOf(fac);
        return jdbc.sql("""
                SELECT x.student_id, x.admission_no, x.surname, x.other_names, x.programme_code, x.programme, x.department, x.faculty_code, x.faculty, x.reason, x.registered, x.paid, x.query_reason
                  FROM ref.faculty f CROSS JOIN LATERAL people.matric_candidates(:s, f.code) x
                 WHERE (:f::text IS NULL OR f.code = :f) AND NOT x.eligible AND x.matric_no IS NULL
                 ORDER BY x.faculty, x.surname, x.other_names
                """).param("s", session).param("f", faculty, Types.VARCHAR).query().listOfRows();
    }

    /* ── one student, before and after ── */

    @GetMapping("/api/v1/matriculation/students/{id}/record")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> record(@PathVariable UUID id) {
        Map<String, Object> st = jdbc.sql("""
                SELECT s.id, s.admission_no, s.matric_no, s.matriculated_at, s.status, s.surname, s.other_names, s.entry_session, p.name AS programme, f.name AS faculty, f.code AS faculty_code, d.name AS department,
                       r.ref AS run_ref, b.ref AS batch_ref, b.id AS batch_id,
                       CASE WHEN s.matric_no IS NULL THEN coalesce(s.admission_no, s.jamb_reg_no) ELSE s.matric_no END AS username,
                       CASE WHEN s.matric_no IS NULL THEN 'PRE_MATRICULATION' ELSE 'MATRICULATED' END AS matriculation_status
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN people.matriculation_run r ON r.id = s.matriculation_run LEFT JOIN people.matric_batch b ON b.id = s.matriculation_run
                 WHERE s.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", id));
        scope.bound(String.valueOf(st.get("faculty_code")), null, null);
        Map<String, Object> out = new LinkedHashMap<>(st);
        out.put("usernameHistory", jdbc.sql("""
                SELECT u.previous_username, u.new_username, u.reason, u.changed_at, u.office, b.ref AS batch_ref, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = u.changed_by) AS officer
                  FROM people.student_username_change u LEFT JOIN people.matric_batch b ON b.id = u.batch_id WHERE u.student_id = :id ORDER BY u.changed_at DESC
                """).param("id", id).query().listOfRows());
        out.put("history", jdbc.sql("SELECT h.matric_no, h.series_code, h.sequence, h.issued_at, h.reason, h.actor_office FROM people.matric_history h WHERE h.student_id = :id ORDER BY h.issued_at DESC").param("id", id).query().listOfRows());
        out.put("proposals", jdbc.sql("""
                SELECT br.proposed_no, br.state, br.problems, br.edited, b.ref AS batch_ref, b.state AS batch_state FROM people.matric_batch_row br JOIN people.matric_batch b ON b.id = br.batch_id WHERE br.student_id = :id ORDER BY b.prepared_at DESC
                """).param("id", id).query().listOfRows());
        return out;
    }

    /* ── the one policy switch ── */

    public record DutiesIn(boolean separateDuties) {
    }

    @PutMapping("/api/v1/matriculation/config/duties")
    @PreAuthorize(ISSUERS)
    @Transactional
    Map<String, Object> duties(@RequestBody DutiesIn body) {
        jdbc.sql("UPDATE people.matric_format SET separate_duties = :d, updated_at = now() WHERE id = 'UNIVERSITY'").param("d", body.separateDuties()).update();
        return Map.of("separateDuties", body.separateDuties());
    }
}
