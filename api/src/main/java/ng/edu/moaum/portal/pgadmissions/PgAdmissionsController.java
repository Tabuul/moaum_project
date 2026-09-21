package ng.edu.moaum.portal.pgadmissions;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;

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
    /* the department's postgraduate committee */
    private static final String DEPT = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_super')";
    /* the School of Postgraduate Studies */
    private static final String SPGS = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_super')";
    /* admitting onto the register, and confirming a fee */
    private static final String ADMIT = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_registrar','OFFICE_super')";
    private static final String CONFIRMERS = "hasAnyAuthority('OFFICE_pgsecretary','OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;

    PgAdmissionsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
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
                       g.name AS programme_name, g.pg_award, g.pg_research,
                       p.surname, p.other_names, p.email, p.phone, p.state_of_origin,
                       a.prior_institution, a.prior_award, a.prior_class, a.prior_cgpa,
                       a.fee_confirmed_at, a.submitted_at, a.dept_decided_at, a.spgs_decided_at,
                       a.accepted_at, a.admitted_at, a.student_id
                  FROM admissions.pg_application a
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  JOIN ref.programme g ON g.code = a.programme_code
                 WHERE a.session = :s
                   AND (:prog::text IS NULL OR a.programme_code = :prog)
                   AND (:state::text IS NULL OR a.state = :state)
                 ORDER BY a.submitted_at DESC NULLS LAST, p.surname, p.other_names
                """)
                .param("s", session)
                .param("prog", programme == null || programme.isBlank() ? null : programme.trim(), Types.VARCHAR)
                .param("state", state == null || state.isBlank() ? null : state.trim().toUpperCase(), Types.VARCHAR)
                .query().listOfRows();
        Map<String, Object> counts = jdbc.sql("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE state = 'SUBMITTED') AS submitted,
                       count(*) FILTER (WHERE state = 'DEPT_RECOMMENDED') AS recommended,
                       count(*) FILTER (WHERE state = 'OFFERED') AS offered,
                       count(*) FILTER (WHERE state = 'ACCEPTED') AS accepted,
                       count(*) FILTER (WHERE state = 'ADMITTED') AS admitted
                  FROM admissions.pg_application WHERE session = :s
                """).param("s", session).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
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
                       count(*) FILTER (WHERE state = 'OFFERED') AS offered,
                       count(*) FILTER (WHERE state = 'ACCEPTED') AS accepted,
                       count(*) FILTER (WHERE state = 'ADMITTED') AS admitted
                  FROM admissions.pg_application WHERE session = :s
                """).param("s", session).query().singleRow();
        long students = jdbc.sql("SELECT count(*) FROM people.student WHERE entry_mode = 'POSTGRADUATE'")
                .query(Long.class).single();
        List<Map<String, Object>> byProgramme = jdbc.sql("""
                SELECT g.name AS programme_name, g.pg_award,
                       count(*) AS applications,
                       count(*) FILTER (WHERE a.state IN ('SUBMITTED','DEPT_RECOMMENDED')) AS in_progress,
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
        out.put("byProgramme", byProgramme);
        out.put("recent", recent);
        return out;
    }

    /** the postgraduate register: every PG student with their coursework CGPA, academic standing and research stage */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String programme,
                                 @RequestParam(required = false) Integer level) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.entry_level, s.entry_session, s.status,
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
                       a.fee_confirmed_at, a.submitted_at, a.dept_decided_at, a.dept_note, a.spgs_decided_at, a.spgs_note,
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
        List<Map<String, Object>> referees = jdbc.sql("""
                SELECT id, name, email, institution, position, reference_text, submitted_at
                  FROM admissions.pg_referee WHERE application_id = :id ORDER BY name
                """).param("id", id).query().listOfRows();
        List<Map<String, Object>> documents = jdbc.sql("""
                SELECT id, kind, filename, content_type, uploaded_at
                  FROM admissions.pg_document WHERE application_id = :id ORDER BY uploaded_at
                """).param("id", id).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("found", true);
        out.put("application", app);
        out.put("referees", referees);
        out.put("documents", documents);
        return out;
    }

    public record DeptDecision(boolean recommend, String note) {
    }

    /** the department's postgraduate committee recommends (or declines) a submitted application */
    @PostMapping("/applications/{id}/dept-decision")
    @PreAuthorize(DEPT)
    @Transactional
    Map<String, Object> deptDecision(@PathVariable UUID id, @Valid @RequestBody DeptDecision body) {
        UUID actor = AuditContextHolder.required().actorId();
        jdbc.sql("SELECT admissions.pg_dept_decide(:id, :rec, :note, :actor)")
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
        jdbc.sql("SELECT admissions.pg_confirm_fee(:ref, :ch)")
                .param("ref", body.reference() == null ? "" : body.reference().trim())
                .param("ch", body.channel() == null || body.channel().isBlank() ? "bank" : body.channel().trim(), Types.VARCHAR)
                .query().listOfRows();
        return application(id);
    }
}
