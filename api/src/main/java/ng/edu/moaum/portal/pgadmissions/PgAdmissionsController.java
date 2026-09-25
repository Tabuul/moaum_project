package ng.edu.moaum.portal.pgadmissions;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.apache.pdfbox.Loader;
import org.apache.pdfbox.multipdf.PDFMergerUtility;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.security.access.AccessDeniedException;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The postgraduate admissions desks (V202). The department's postgraduate committee recommends a
 * submitted application; the School of Postgraduate Studies offers or refuses; the applicant accepts;
 * and the School admits, which puts the student on the register. Separate from the JAMB/CAPS
 * undergraduate flow — a postgraduate applicant has no CAPS row.
 */
@RestController
@RequestMapping("/api/v1/pg")
class PgAdmissionsController {

    /* who may read the postgraduate applications */
    private static final String READERS =
            "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dean','OFFICE_hod','OFFICE_dvc','OFFICE_vc','OFFICE_super')";
    /* the department's postgraduate committee (the HOD) */
    private static final String DEPT = "hasAnyAuthority('OFFICE_hod','OFFICE_academic','OFFICE_super')";
    /* the faculty (the Dean) vets after the department */
    private static final String FACULTY = "hasAnyAuthority('OFFICE_dean','OFFICE_academic','OFFICE_super')";
    /* the School of Postgraduate Studies */
    private static final String SPGS = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_super')";
    /* admitting onto the register, and confirming a fee */
    private static final String ADMIT = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_registrar','OFFICE_super')";
    private static final String CONFIRMERS = "hasAnyAuthority('OFFICE_pgsecretary','OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    private final String portalUrl;

    PgAdmissionsController(JdbcClient jdbc,
                          @org.springframework.beans.factory.annotation.Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl,
                          OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    /* the Bursary (and the School) set the postgraduate application and acceptance fees */
    private static final String FEES = "hasAnyAuthority('OFFICE_bursar','OFFICE_pgsecretary','OFFICE_pgschool','OFFICE_super')";

    /** the postgraduate application and acceptance fees in force for a session (the stated ones, else the default) */
    @GetMapping("/sessions/{session}/{year}/fees")
    @PreAuthorize(FEES)
    @Transactional(readOnly = true)
    Map<String, Object> fees(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        Map<String, Object> rule = jdbc.sql("SELECT application_fee, acceptance_fee, checking_fee FROM admissions.pg_fee_rule(:s)")
                .param("s", s).query().singleRow();
        boolean stated = jdbc.sql("SELECT count(*) FROM admissions.pg_fee WHERE session = :s")
                .param("s", s).query(Long.class).single() > 0;
        Map<String, Object> out = new LinkedHashMap<>(rule);
        out.put("stated", stated);
        return out;
    }

    public record FeesIn(java.math.BigDecimal applicationFee, java.math.BigDecimal acceptanceFee, java.math.BigDecimal checkingFee) {
    }

    /** the Bursary states the postgraduate fees for a session */
    @org.springframework.web.bind.annotation.PutMapping("/sessions/{session}/{year}/fees")
    @PreAuthorize(FEES)
    @Transactional
    Map<String, Object> setFees(@PathVariable String session, @PathVariable String year, @Valid @RequestBody FeesIn body) {
        String s = session + "/" + year;
        jdbc.sql("""
                INSERT INTO admissions.pg_fee (session, application_fee, acceptance_fee, checking_fee)
                VALUES (:s, :a, :c, :k)
                ON CONFLICT (session) DO UPDATE SET application_fee = EXCLUDED.application_fee,
                    acceptance_fee = EXCLUDED.acceptance_fee, checking_fee = EXCLUDED.checking_fee
                """)
                .param("s", s)
                .param("a", body.applicationFee() == null ? java.math.BigDecimal.ZERO : body.applicationFee())
                .param("c", body.acceptanceFee() == null ? java.math.BigDecimal.ZERO : body.acceptanceFee())
                .param("k", body.checkingFee() == null ? new java.math.BigDecimal("3000") : body.checkingFee())
                .update();
        return fees(session, year);
    }

    /** the postgraduate applications for a session, newest submission first, with a per-state count */
    @GetMapping("/applications")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> applications(@RequestParam String session,
                                     @RequestParam(required = false) String programme,
                                     @RequestParam(required = false) String state) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT a.id, a.application_no, a.session, a.state, a.entry_level, a.programme_code,
                       g.name AS programme_name, g.pg_award, g.pg_research, g.dept_code, g.faculty_code,
                       d.name AS department_name, f.name AS faculty_name,
                       p.surname, p.other_names, p.email, p.phone, p.state_of_origin,
                       a.prior_institution, a.prior_award, a.prior_class, a.prior_cgpa,
                       a.fee_confirmed_at, a.checking_confirmed_at, a.acceptance_confirmed_at,
                       a.submitted_at, a.dept_decided_at, a.fac_decided_at, a.spgs_decided_at,
                       a.accepted_at, a.admitted_at, a.student_id,
                       (SELECT count(*) FROM admissions.pg_document x WHERE x.application_id = a.id AND x.kind <> 'PASSPORT') AS documents,
                       (SELECT count(*) FROM admissions.pg_referee x WHERE x.application_id = a.id AND x.submitted_at IS NOT NULL) AS references_in
                  FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  JOIN ref.programme g ON g.code = a.programme_code
                  JOIN ref.department d ON d.code = g.dept_code
                  JOIN ref.faculty f ON f.code = g.faculty_code
                 WHERE a.session = :s
                   AND (:prog::text IS NULL OR a.programme_code = :prog)
                   AND (:state::text IS NULL OR a.state = :state)
                   AND (:dept::text IS NULL OR g.dept_code = :dept)
                   AND (:fac::text IS NULL OR g.faculty_code = :fac)
                 ORDER BY p.surname, p.other_names, a.application_no
                """)
                .param("s", session)
                .param("prog", programme == null || programme.isBlank() ? null : programme.trim(), Types.VARCHAR)
                .param("state", state == null || state.isBlank() ? null : state.trim().toUpperCase(), Types.VARCHAR)
                .param("dept", boundDept(), Types.VARCHAR).param("fac", boundFaculty(), Types.VARCHAR)
                .query().listOfRows();
        Map<String, Object> counts = jdbc.sql("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE a.state = 'SUBMITTED') AS submitted,
                       count(*) FILTER (WHERE a.state = 'DEPT_RECOMMENDED') AS recommended,
                       count(*) FILTER (WHERE a.state = 'FAC_RECOMMENDED') AS faculty,
                       count(*) FILTER (WHERE a.state = 'OFFERED') AS offered,
                       count(*) FILTER (WHERE a.state = 'ACCEPTED') AS accepted,
                       count(*) FILTER (WHERE a.state = 'ADMITTED') AS admitted,
                       count(*) FILTER (WHERE a.state IN ('DEPT_DECLINED','FAC_DECLINED','NOT_OFFERED')) AS declined
                  FROM admissions.pg_application a JOIN ref.programme g ON g.code = a.programme_code
                 WHERE a.session = :s
                   AND (:dept::text IS NULL OR g.dept_code = :dept)
                   AND (:fac::text IS NULL OR g.faculty_code = :fac)
                """).param("s", session).param("dept", boundDept(), Types.VARCHAR).param("fac", boundFaculty(), Types.VARCHAR).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("bound", Map.of("department", String.valueOf(boundDept()), "faculty", String.valueOf(boundFaculty())));
        out.put("counts", counts);
        out.put("rows", rows);
        return out;
    }

    /** the School of Postgraduate Studies' home: what waits on the School, the register, and the pipeline by programme */
    @GetMapping("/dashboard")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> dashboard(@RequestParam String session) {
        Map<String, Object> counts = jdbc.sql("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE state = 'SUBMITTED') AS submitted,
                       count(*) FILTER (WHERE state = 'DEPT_RECOMMENDED') AS recommended,
                       count(*) FILTER (WHERE state = 'FAC_RECOMMENDED') AS faculty,
                       count(*) FILTER (WHERE state = 'OFFERED') AS offered,
                       count(*) FILTER (WHERE state = 'ACCEPTED') AS accepted,
                       count(*) FILTER (WHERE state = 'ADMITTED') AS admitted
                  FROM admissions.pg_application WHERE session = :s
                """).param("s", session).query().singleRow();
        long students = jdbc.sql("SELECT count(*) FROM people.student WHERE entry_mode = 'POSTGRADUATE'")
                .query(Long.class).single();
        // the register's end of the lifecycle: who is active, on research, before the examiners, cleared, graduated
        Map<String, Object> pipeline = jdbc.sql("""
                SELECT count(*) FILTER (WHERE s.status IN ('ACTIVE','ADMITTED','PROBATION')) AS active,
                       count(*) FILTER (WHERE s.status = 'ADMITTED' AND s.entry_session = :s) AS newly_admitted,
                       count(*) FILTER (WHERE r.stage IN ('SUPERVISED','PROPOSAL_SUBMITTED','PROPOSAL_APPROVED','SEMINAR_HELD','TITLE_REGISTERED')) AS on_research,
                       count(*) FILTER (WHERE r.stage IN ('PANEL_CONSTITUTED','DRAFT_SUBMITTED')) AS awaiting_defence,
                       count(*) FILTER (WHERE r.stage IN ('VIVA_HELD','CORRECTIONS','FINAL_SUBMITTED')) AS finishing,
                       count(*) FILTER (WHERE r.stage IN ('CLEARED','AWARD_RECOMMENDED')) AS graduation_eligible,
                       count(*) FILTER (WHERE s.status = 'GRADUATED') AS graduated,
                       count(*) FILTER (WHERE s.status IN ('DEFERRED','WITHDRAWN','VOLUNTARY_WITHDRAWAL','SUSPENDED')) AS not_in_study
                  FROM people.student s LEFT JOIN admissions.pg_research r ON r.student_id = s.id
                 WHERE s.entry_mode = 'POSTGRADUATE'
                """).param("s", session).query().singleRow();
        List<Map<String, Object>> byProgramme = jdbc.sql("""
                SELECT g.name AS programme_name, g.pg_award,
                       count(*) AS applications,
                       count(*) FILTER (WHERE a.state IN ('SUBMITTED','DEPT_RECOMMENDED','FAC_RECOMMENDED')) AS in_progress,
                       count(*) FILTER (WHERE a.state = 'OFFERED') AS offered,
                       count(*) FILTER (WHERE a.state IN ('ACCEPTED','ADMITTED')) AS taken
                  FROM admissions.pg_application a
                  JOIN ref.programme g ON g.code = a.programme_code
                 WHERE a.session = :s
                 GROUP BY g.name, g.pg_award ORDER BY g.name
                """).param("s", session).query().listOfRows();
        /* the latest applicants themselves, so the School sees who has applied without leaving the home;
           newest first, and across sessions so a just-submitted application is never hidden by a session default */
        List<Map<String, Object>> recent = jdbc.sql("""
                SELECT a.application_no, a.session, a.state, a.entry_level,
                       p.surname, p.other_names, p.email, p.phone,
                       g.name AS programme_name, g.pg_award,
                       a.submitted_at, a.fee_confirmed_at
                  FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  JOIN ref.programme g ON g.code = a.programme_code
                 ORDER BY a.submitted_at DESC NULLS LAST, a.created_at DESC
                 LIMIT 50
                """).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("counts", counts);
        out.put("pgStudents", students);
        out.put("pipeline", pipeline);
        out.put("byProgramme", byProgramme);
        out.put("recent", recent);
        return out;
    }

    /**
     * The Secretary's home: what waits on the Secretary this session — students yet to register, fee
     * references awaiting confirmation, registered courses awaiting a result, and theses awaiting the
     * Secretary's clearance before binding — with the lists behind the figures.
     */
    @GetMapping("/secretary/dashboard")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> secretaryDashboard(@RequestParam String session) {
        long toRegister = jdbc.sql("""
                SELECT count(*) FROM people.student s
                 WHERE s.entry_mode = 'POSTGRADUATE' AND s.status = 'ACTIVE'
                   AND NOT EXISTS (SELECT 1 FROM admissions.pg_registration r
                                    WHERE r.student_id = s.id AND r.session = :s AND r.state IN ('SUBMITTED','ENDORSED'))
                """).param("s", session).query(Long.class).single();
        List<Map<String, Object>> toEndorse = jdbc.sql("""
                SELECT r.id, r.semester, r.mode, r.updated_at, st.surname, st.other_names, st.matric_no,
                       g.name AS programme_name, g.pg_award,
                       (SELECT count(*) FROM admissions.pg_registration_entry e WHERE e.registration_id = r.id) AS courses
                  FROM admissions.pg_registration r
                  JOIN people.student st ON st.id = r.student_id
                  JOIN ref.programme g ON g.code = st.programme_code
                 WHERE r.session = :s AND r.state = 'SUBMITTED'
                 ORDER BY r.updated_at DESC LIMIT 50
                """).param("s", session).query().listOfRows();
        List<Map<String, Object>> feesToConfirm = jdbc.sql("""
                SELECT f.reference, f.kind, f.amount, f.expires_at, a.id AS application_id, a.application_no, p.surname, p.other_names
                  FROM admissions.pg_fee_reference f
                  JOIN admissions.pg_application a ON a.id = f.application_id
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                 WHERE f.confirmed_at IS NULL AND f.expires_at > now()
                 ORDER BY f.expires_at LIMIT 50
                """).query().listOfRows();
        long examsPending = jdbc.sql("""
                SELECT count(*) FROM admissions.pg_registration_entry e
                  JOIN admissions.pg_registration r ON r.id = e.registration_id
                 WHERE r.session = :s AND r.state = 'ENDORSED'
                   AND NOT EXISTS (SELECT 1 FROM admissions.pg_score sc WHERE sc.entry_id = e.id)
                """).param("s", session).query(Long.class).single();
        List<Map<String, Object>> clearances = jdbc.sql("""
                SELECT rs.id, rs.degree_kind, rs.topic, rs.final_submitted_at, rs.updated_at,
                       st.surname, st.other_names, st.matric_no, g.name AS programme_name, g.pg_award
                  FROM admissions.pg_research rs
                  JOIN people.student st ON st.id = rs.student_id
                  JOIN ref.programme g ON g.code = st.programme_code
                 WHERE rs.stage = 'FINAL_SUBMITTED'
                 ORDER BY rs.final_submitted_at NULLS LAST, rs.updated_at DESC LIMIT 50
                """).query().listOfRows();
        Map<String, Object> counts = new LinkedHashMap<>();
        counts.put("toRegister", toRegister);
        counts.put("toEndorse", toEndorse.size());
        counts.put("feesToConfirm", feesToConfirm.size());
        counts.put("examsPending", examsPending);
        counts.put("clearances", clearances.size());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("counts", counts);
        out.put("toEndorse", toEndorse);
        out.put("feesToConfirm", feesToConfirm);
        out.put("clearances", clearances);
        return out;
    }

    /** the postgraduate register: every PG student with their coursework CGPA, academic standing and research stage */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String programme,
                                 @RequestParam(required = false) Integer level) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.sex, s.entry_level, s.entry_session, s.status,
                       g.name AS programme_name, g.pg_award, d.name AS department_name, f.name AS faculty_name,
                       admissions.pg_cgpa(s.id) AS cgpa,
                       r.stage AS research_stage,
                       (SELECT reg.mode FROM admissions.pg_registration reg WHERE reg.student_id = s.id
                         ORDER BY reg.session DESC, reg.semester DESC LIMIT 1) AS mode,
                       EXISTS (SELECT 1 FROM admissions.pg_registration reg
                                JOIN admissions.pg_registration_entry e ON e.registration_id = reg.id
                                JOIN admissions.pg_score sc ON sc.entry_id = e.id WHERE reg.student_id = s.id) AS has_results
                  FROM people.student s
                  JOIN ref.programme g ON g.code = s.programme_code
                  JOIN ref.department d ON d.code = g.dept_code
                  JOIN ref.faculty f ON f.code = g.faculty_code
                  LEFT JOIN admissions.pg_research r ON r.student_id = s.id
                 WHERE s.entry_mode = 'POSTGRADUATE'
                   AND (:prog::text IS NULL OR s.programme_code = :prog)
                   AND (:lvl::int IS NULL OR s.entry_level = :lvl)
                 ORDER BY s.surname, s.other_names
                """)
                .param("prog", programme == null || programme.isBlank() ? null : programme.trim(), Types.VARCHAR)
                .param("lvl", level, Types.INTEGER)
                .query().listOfRows();
        for (Map<String, Object> row : rows) {
            java.math.BigDecimal cgpa = row.get("cgpa") == null ? java.math.BigDecimal.ZERO : new java.math.BigDecimal(row.get("cgpa").toString());
            boolean scored = Boolean.TRUE.equals(row.get("has_results"));
            row.put("standing", !scored ? "NEW" : cgpa.compareTo(new java.math.BigDecimal("2.50")) >= 0 ? "GOOD" : "PROBATION");
        }
        Map<String, Object> counts = jdbc.sql("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE entry_level = 700) AS pgd,
                       count(*) FILTER (WHERE entry_level = 800) AS masters,
                       count(*) FILTER (WHERE entry_level = 900) AS doctoral
                  FROM people.student WHERE entry_mode = 'POSTGRADUATE'
                """).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("counts", counts);
        out.put("rows", rows);
        return out;
    }

    /** the external examiners of the School (Policy 18) */
    @GetMapping("/examiners")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> examiners() {
        return jdbc.sql("""
                SELECT id, name, institution, field, tenure_from, tenure_to, active FROM admissions.pg_examiner
                 ORDER BY active DESC, name
                """).query().listOfRows();
    }

    public record ExaminerIn(@NotBlank @Size(max = 200) String name,
                             @NotBlank @Size(max = 200) String institution,
                             @Size(max = 160) String field, String tenureFrom, String tenureTo) {
    }

    /** appoint an external examiner (the School, on the Board's approval) */
    @PostMapping("/examiners")
    @PreAuthorize(SPGS)
    @Transactional
    Map<String, Object> addExaminer(@Valid @RequestBody ExaminerIn body) {
        jdbc.sql("""
                INSERT INTO admissions.pg_examiner (name, institution, field, tenure_from, tenure_to)
                VALUES (:n, :i, :f, :tf::date, :tt::date)
                """)
                .param("n", body.name().trim()).param("i", body.institution().trim())
                .param("f", body.field() == null || body.field().isBlank() ? null : body.field().trim(), Types.VARCHAR)
                .param("tf", body.tenureFrom() == null || body.tenureFrom().isBlank() ? null : body.tenureFrom().trim(), Types.VARCHAR)
                .param("tt", body.tenureTo() == null || body.tenureTo().isBlank() ? null : body.tenureTo().trim(), Types.VARCHAR)
                .update();
        return Map.of("ok", true);
    }

    public record StatusIn(@NotBlank String to, @NotBlank @Size(max = 400) String instrument, @Size(max = 400) String reason) {
    }

    /** defer, withdraw or reinstate a postgraduate student (Policy 19–20), on a cited instrument */
    @PostMapping("/students/{id}/status")
    @PreAuthorize(SPGS)
    @Transactional
    Map<String, Object> setStatus(@PathVariable UUID id, @Valid @RequestBody StatusIn body) {
        String to = body.to().trim().toUpperCase();
        if (!List.of("DEFERRED", "WITHDRAWN", "ACTIVE").contains(to)) {
            throw new DomainRuleViolation("PG_STATUS", "A postgraduate status change here is deferment, withdrawal, or reinstatement.",
                    new DomainRuleViolation.Remedy("Choose Defer, Withdraw or Reinstate.", "School of Postgraduate Studies"));
        }
        boolean isPg = jdbc.sql("SELECT count(*) FROM people.student WHERE id = :id AND entry_mode = 'POSTGRADUATE'")
                .param("id", id).query(Long.class).single() == 1L;
        if (!isPg) {
            throw new NotFound("postgraduate student", id);
        }
        jdbc.sql("SELECT people.change_status(:id, :to, :inst, current_date, :reason)")
                .param("id", id).param("to", to).param("inst", body.instrument().trim())
                .param("reason", body.reason() == null || body.reason().isBlank() ? null : body.reason().trim(), Types.VARCHAR)
                .query().listOfRows();
        return Map.of("ok", true, "status", to);
    }

    /** one application in full: the applicant, the first degree, the proposal, its referees and documents */
    @GetMapping("/applications/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> application(@PathVariable UUID id) {
        List<Map<String, Object>> found = jdbc.sql("""
                SELECT a.id, a.application_no, a.session, a.state, a.entry_level, a.programme_code,
                       g.name AS programme_name, g.pg_award, g.pg_research,
                       p.surname, p.other_names, p.sex, p.date_of_birth, p.state_of_origin, p.lga, p.email, p.phone,
                       a.prior_institution, a.prior_award, a.prior_class, a.prior_cgpa, a.prior_year,
                       a.proposal_title, a.proposal_text,
                       a.fee_confirmed_at, a.submitted_at, a.dept_decided_at, a.dept_note,
                       a.fac_decided_at, a.fac_note, a.spgs_decided_at, a.spgs_note,
                       a.accepted_at, a.admitted_at, a.student_id
                  FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  JOIN ref.programme g ON g.code = a.programme_code
                 WHERE a.id = :id
                """).param("id", id).query().listOfRows();
        if (found.isEmpty()) {
            return Map.of("found", false);
        }
        Map<String, Object> app = found.get(0);
        inBound(id);
        List<Map<String, Object>> history = jdbc.sql("""
                SELECT e.kind, e.note, e.at, e.actor_office,
                       CASE WHEN x.id IS NULL THEN NULL ELSE x.surname || ', ' || x.given_names END AS actor
                  FROM admissions.pg_application_event e LEFT JOIN iam.person x ON x.id = e.actor_id
                 WHERE e.application_id = :id ORDER BY e.at, e.kind
                """).param("id", id).query().listOfRows();
        List<Map<String, Object>> referees = jdbc.sql("""
                SELECT id, name, email, phone, institution, position, reference_text, submitted_at,
                       relationship, known_duration, attestation, recommendation, verdict
                  FROM admissions.pg_referee WHERE application_id = :id ORDER BY name
                """).param("id", id).query().listOfRows();
        List<Map<String, Object>> documents = jdbc.sql("""
                SELECT id, kind, filename, content_type, uploaded_at
                  FROM admissions.pg_document WHERE application_id = :id ORDER BY uploaded_at
                """).param("id", id).query().listOfRows();
        List<Map<String, Object>> priorDegrees = jdbc.sql("""
                SELECT kind, institution, award, field, class_of_degree, cgpa, year
                  FROM admissions.pg_prior_degree WHERE application_id = :id
                 ORDER BY CASE kind WHEN 'FIRST' THEN 0 ELSE 1 END, year
                """).param("id", id).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("found", true);
        out.put("application", app);
        out.put("referees", referees);
        out.put("priorDegrees", priorDegrees);
        out.put("documents", documents);
        out.put("history", history);
        return out;
    }

    /* ── the office's bound: a Head of Department reads and decides their own department's applications, a Dean
          their faculty's; the School, the Academic Office and the Registry read them all. The check is on the
          record, so an application id typed into the address bar is refused the same way. ── */

    private String boundDept() {
        return scope.actingHod() ? String.valueOf(scope.actingDept()) : null;
    }

    private String boundFaculty() {
        return scope.actingFacultyOffice() ? String.valueOf(scope.actingFaculty()) : null;
    }

    private void inBound(UUID applicationId) {
        String dept = boundDept(), fac = boundFaculty();
        if (dept == null && fac == null) return;
        Map<String, Object> g = jdbc.sql("""
                SELECT g.dept_code, g.faculty_code FROM admissions.pg_application a JOIN ref.programme g ON g.code = a.programme_code WHERE a.id = :id
                """).param("id", applicationId).query().listOfRows().stream().findFirst().orElse(null);
        if (g == null) return;
        if (dept != null && !dept.equalsIgnoreCase(String.valueOf(g.get("dept_code")))) {
            throw new AccessDeniedException("This application is for another department's programme; the Head of Department reads and decides their own department's applications only.");
        }
        if (fac != null && !fac.equalsIgnoreCase(String.valueOf(g.get("faculty_code")))) {
            throw new AccessDeniedException("This application is for another faculty's programme; the Dean reads and decides their own faculty's applications only.");
        }
    }

    /** the credentials document an applicant uploaded, streamed for the desk to read inline (the O'/A'Level
     *  and birth-certificate PDF). Scoped to its application, so an id alone cannot reach another's file. */
    @GetMapping("/applications/{id}/documents/{docId}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> document(@PathVariable UUID id, @PathVariable UUID docId) {
        inBound(id);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT filename, content_type, bytes
                  FROM admissions.pg_document WHERE id = :d AND application_id = :a
                """).param("d", docId).param("a", id).query().listOfRows();
        if (rows.isEmpty() || rows.get(0).get("bytes") == null) {
            throw new NotFound("postgraduate document", docId);
        }
        Map<String, Object> row = rows.get(0);
        byte[] bytes = (byte[]) row.get("bytes");
        String ct = String.valueOf(row.getOrDefault("content_type", "application/pdf"));
        String fn = String.valueOf(row.getOrDefault("filename", "document.pdf")).replaceAll("[\"\\r\\n]", "");
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(ct))
                .header(HttpHeaders.CACHE_CONTROL, "private, max-age=600")
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + fn + "\"")
                .body(bytes);
    }

    /** every document the applicant uploaded, merged into one PDF for the School to read and keep — the PDF
     *  certificates concatenated, and the passport added as an image page. Scoped to the application. */
    @GetMapping("/applications/{id}/documents.pdf")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> mergedDocuments(@PathVariable UUID id) {
        inBound(id);
        List<Map<String, Object>> docs = jdbc.sql("""
                SELECT kind, content_type, bytes FROM admissions.pg_document
                 WHERE application_id = :id
                 ORDER BY CASE kind WHEN 'PASSPORT' THEN 1 ELSE 0 END, kind
                """).param("id", id).query().listOfRows();
        if (docs.isEmpty()) {
            throw new NotFound("postgraduate documents", id);
        }
        try (PDDocument out = new PDDocument(); ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
            PDFMergerUtility merger = new PDFMergerUtility();
            for (Map<String, Object> d : docs) {
                byte[] b = (byte[]) d.get("bytes");
                if (b == null) {
                    continue;
                }
                String ct = String.valueOf(d.getOrDefault("content_type", ""));
                if (ct.contains("pdf")) {
                    try (PDDocument src = Loader.loadPDF(b)) {
                        merger.appendDocument(out, src);
                    } catch (RuntimeException | IOException badPdf) { /* skip an unreadable PDF */ }
                } else if (ct.contains("jpeg") || ct.contains("jpg") || ct.contains("png")) {
                    try {
                        PDImageXObject img = PDImageXObject.createFromByteArray(out, b, String.valueOf(d.get("kind")));
                        PDPage page = new PDPage(PDRectangle.A4);
                        out.addPage(page);
                        float maxW = PDRectangle.A4.getWidth() - 72, maxH = PDRectangle.A4.getHeight() - 72;
                        float scale = Math.min(maxW / img.getWidth(), maxH / img.getHeight());
                        float w = img.getWidth() * scale, h = img.getHeight() * scale;
                        float x = (PDRectangle.A4.getWidth() - w) / 2, y = (PDRectangle.A4.getHeight() - h) / 2;
                        try (PDPageContentStream cs = new PDPageContentStream(out, page)) {
                            cs.drawImage(img, x, y, w, h);
                        }
                    } catch (RuntimeException | IOException badImg) { /* skip an unreadable image */ }
                }
            }
            if (out.getNumberOfPages() == 0) {
                throw new NotFound("postgraduate documents", id);
            }
            out.save(baos);
            return ResponseEntity.ok().contentType(MediaType.APPLICATION_PDF)
                    .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"pg-documents-" + id + ".pdf\"")
                    .body(baos.toByteArray());
        } catch (IOException e) {
            throw new DomainRuleViolation("PG_DOC_MERGE", "The documents could not be combined into one PDF.",
                    new DomainRuleViolation.Remedy("Open each document individually from the list.", "Postgraduate School"));
        }
    }

    public record DeptDecision(boolean recommend, String note) {
    }

    /** the department's postgraduate committee recommends (or declines) a submitted application */
    @PostMapping("/applications/{id}/dept-decision")
    @PreAuthorize(DEPT)
    @Transactional
    Map<String, Object> deptDecision(@PathVariable UUID id, @Valid @RequestBody DeptDecision body) {
        inBound(id);
        UUID actor = AuditContextHolder.required().actorId();
        jdbc.sql("SELECT admissions.pg_dept_decide(:id, :rec, :note, :actor)")
                .param("id", id).param("rec", body.recommend())
                .param("note", body.note(), Types.VARCHAR).param("actor", actor).query().listOfRows();
        return application(id);
    }

    public record FacultyDecision(boolean recommend, String note) {
    }

    /** the faculty (the Dean) recommends (or declines) an application the department recommended */
    @PostMapping("/applications/{id}/faculty-decision")
    @PreAuthorize(FACULTY)
    @Transactional
    Map<String, Object> facultyDecision(@PathVariable UUID id, @Valid @RequestBody FacultyDecision body) {
        inBound(id);
        UUID actor = AuditContextHolder.required().actorId();
        jdbc.sql("SELECT admissions.pg_faculty_decide(:id, :rec, :note, :actor)")
                .param("id", id).param("rec", body.recommend())
                .param("note", body.note(), Types.VARCHAR).param("actor", actor).query().listOfRows();
        return application(id);
    }

    public record SpgsDecision(boolean offer, String note) {
    }

    /** the School of Postgraduate Studies offers (or refuses) admission */
    @PostMapping("/applications/{id}/spgs-decision")
    @PreAuthorize(SPGS)
    @Transactional
    Map<String, Object> spgsDecision(@PathVariable UUID id, @Valid @RequestBody SpgsDecision body) {
        UUID actor = AuditContextHolder.required().actorId();
        jdbc.sql("SELECT admissions.pg_spgs_decide(:id, :offer, :note, :actor)")
                .param("id", id).param("offer", body.offer())
                .param("note", body.note(), Types.VARCHAR).param("actor", actor).query().listOfRows();
        // tell the applicant a decision is ready — they pay the checking fee to see it
        Map<String, Object> who = jdbc.sql("""
                SELECT p.email, a.application_no, r.checking_fee
                  FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  CROSS JOIN LATERAL admissions.pg_fee_rule(a.session) r
                 WHERE a.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElse(null);
        if (who != null && who.get("email") != null && !String.valueOf(who.get("email")).isBlank()) {
            String fee = "₦" + who.get("checking_fee");
            String body2 = "A decision has been made on your postgraduate application " + who.get("application_no") + ".\n\n"
                    + "Pay the checking fee of " + fee + " on the applicant portal to view your admission status:\n"
                    + portalUrl + "/pg/portal\n\nIf you are admitted, you then pay the acceptance fee to accept and print your offer of admission.";
            jdbc.sql("SELECT platform.queue_notice('EMAIL', :r, :sub, :b, 'pg_application', :ai)")
                    .param("r", who.get("email")).param("sub", "A decision on your MOAUM postgraduate application")
                    .param("b", body2).param("ai", id).query().listOfRows();
        }
        return application(id);
    }

    /** record the applicant's acceptance of the offer (they may also do this themselves once the portal is open) */
    @PostMapping("/applications/{id}/accept")
    @PreAuthorize(SPGS)
    @Transactional
    Map<String, Object> accept(@PathVariable UUID id) {
        jdbc.sql("SELECT admissions.pg_accept(:id)").param("id", id).query().listOfRows();
        return application(id);
    }

    /** admit the accepted applicant: create the student on the register (entry_mode POSTGRADUATE) */
    @PostMapping("/applications/{id}/admit")
    @PreAuthorize(ADMIT)
    @Transactional
    Map<String, Object> admit(@PathVariable UUID id) {
        UUID student = jdbc.sql("SELECT admissions.pg_admit(:id)").param("id", id).query(UUID.class).single();
        Map<String, Object> out = new LinkedHashMap<>(application(id));
        out.put("studentId", student);
        return out;
    }

    public record FeeConfirm(String reference, String channel) {
    }

    /** confirm a postgraduate fee payment by its reference (a bank confirmation, or a gateway callback) */
    @PostMapping("/applications/{id}/confirm-fee")
    @PreAuthorize(CONFIRMERS)
    @Transactional
    Map<String, Object> confirmFee(@PathVariable UUID id, @Valid @RequestBody FeeConfirm body) {
        String ref = body.reference() == null ? "" : body.reference().trim();
        long owned = jdbc.sql("SELECT count(*) FROM admissions.pg_fee_reference WHERE upper(reference) = upper(:r) AND application_id = :id")
                .param("r", ref).param("id", id).query(Long.class).single();
        if (owned == 0) {
            throw new DomainRuleViolation("PG_FEE_REF_MISMATCH", "That reference does not belong to this application.",
                    new DomainRuleViolation.Remedy("Confirm the reference against the application it was generated for; the Secretary's dashboard lists each with its application.", "Secretary, Postgraduate School"));
        }
        jdbc.sql("SELECT admissions.pg_confirm_fee(:ref, :ch)")
                .param("ref", ref)
                .param("ch", body.channel() == null || body.channel().isBlank() ? "bank" : body.channel().trim(), Types.VARCHAR)
                .query().listOfRows();
        return application(id);
    }
}
