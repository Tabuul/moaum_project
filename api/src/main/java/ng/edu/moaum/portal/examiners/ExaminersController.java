package ng.edu.moaum.portal.examiners;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.sql.Types;
import java.time.LocalDate;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * External examiners (V254) under /api/v1/examiners.
 *   the desk         — the Academic Office, the Registry, the School of Postgraduate Studies, the administrators, and
 *                      a Head of Department, an Examinations Officer or a Dean within their own unit: examiners,
 *                      appointments, projects and their documents, assignments, the assessments read, locked, reopened,
 *                      the reports, the form
 *   /me/…            — the examiner: their profile, their projects, the documents released, their own assessment
 *   /invitation, /activate — the public activation link
 * An examiner reaches nothing but what is assigned to them; every check is on the server.
 */
@RestController
@RequestMapping("/api/v1/examiners")
class ExaminersController {

    private static final String DESK = "hasAnyAuthority('OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_exams','OFFICE_hod','OFFICE_dean','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_admin','OFFICE_super')";
    private static final String FORM = "hasAnyAuthority('OFFICE_academic','OFFICE_dregistrar','OFFICE_pgschool','OFFICE_admin','OFFICE_super')";
    private static final String EXAMINER = "hasAuthority('OFFICE_extexaminer')";
    private static final Set<String> PRIVATE_TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    private static final Set<String> DOC_TYPES = Set.of("application/pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation", "application/zip");
    private static final Set<String> DOC_KINDS = Set.of("PROPOSAL", "REPORT", "SOURCE", "PRESENTATION", "SUPPORTING");
    private static final Set<String> RECOMMENDATIONS = Set.of("PASS", "PASS_WITH_CORRECTIONS", "REASSESSMENT", "FAIL");
    private static final long MAX_DOC = 25L * 1024 * 1024;
    private static final long MAX_PRIVATE = 5L * 1024 * 1024;
    private static final UUID NOBODY = new UUID(0, 0);
    private static final SecureRandom RANDOM = new SecureRandom();

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final ExaminerNotifier notifier;
    private final TransactionTemplate tx;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);

    ExaminersController(JdbcClient jdbc, OfficeScope scope, ExaminerNotifier notifier, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.notifier = notifier;
        this.tx = new TransactionTemplate(transactions);
    }

    /* ── who is asking, and how far they see ── */

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private String myName(Authentication auth) {
        return jdbc.sql("SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = :id").param("id", me(auth)).query(String.class).optional().orElse("The desk");
    }

    /** a department office sees its department; a faculty office its faculty; the rest the University */
    private record Reach(String dept, String faculty) {
        boolean all() { return dept == null && faculty == null; }
    }

    private Reach reach() {
        if (scope.actingDepartmentOffice()) return new Reach(scope.actingDept() == null ? "__none__" : scope.actingDept(), null);
        if (scope.actingFacultyOffice()) return new Reach(null, scope.actingFaculty() == null ? "__none__" : scope.actingFaculty());
        return new Reach(null, null);
    }

    private static final String IN_REACH = " AND (:rdept::text IS NULL OR pr.dept_code = :rdept OR d.name = :rdept) AND (:rfac::text IS NULL OR pr.faculty_code = :rfac OR f.name = :rfac) ";

    private JdbcClient.StatementSpec reachParams(JdbcClient.StatementSpec spec) {
        Reach r = reach();
        return spec.param("rdept", r.dept(), Types.VARCHAR).param("rfac", r.faculty(), Types.VARCHAR);
    }

    /** the project must be within the desk's reach, or it is not there */
    private void requireProject(UUID project) {
        Boolean ok = reachParams(jdbc.sql("""
                SELECT true FROM extexam.project p JOIN people.student st ON st.id = p.student_id JOIN ref.programme pr ON pr.code = st.programme_code
                  JOIN ref.department d ON d.code = pr.dept_code JOIN ref.faculty f ON f.code = pr.faculty_code
                 WHERE p.id = :id
                """ + IN_REACH).param("id", project)).query(Boolean.class).optional().orElse(false);
        if (!ok) throw new NotFound("project", project);
    }

    private UUID projectOfAssignment(UUID assignment) {
        return jdbc.sql("SELECT project_id FROM extexam.assignment WHERE id = :id").param("id", assignment).query(UUID.class).optional().orElseThrow(() -> new NotFound("assignment", assignment));
    }

    private void requireAssignment(UUID assignment) {
        requireProject(projectOfAssignment(assignment));
    }

    private UUID assignmentOfAssessment(UUID assessment) {
        return jdbc.sql("SELECT assignment_id FROM extexam.assessment WHERE id = :id").param("id", assessment).query(UUID.class).optional().orElseThrow(() -> new NotFound("assessment", assessment));
    }

    /** the examiner behind the sign-in; nobody whose appointment is not active */
    private UUID examinerOf(Authentication auth) {
        UUID id = jdbc.sql("SELECT extexam.examiner_of(:p)").param("p", me(auth)).query(UUID.class).optional().orElse(null);
        if (id == null) {
            throw new DomainRuleViolation("EXAMINER_NOT_ACTIVE", "Your examiner appointment is not active.",
                    new DomainRuleViolation.Remedy("Write to the Academic Office if you believe it should be.", "Academic Office"));
        }
        return id;
    }

    /** an assignment that is the examiner's own and still live, or it is not there */
    private Map<String, Object> myAssignment(UUID examiner, UUID assignment) {
        return jdbc.sql("SELECT id, project_id, status, rubric_id, first_viewed_at FROM extexam.assignment WHERE id = :id AND examiner_id = :e AND ended_at IS NULL")
                .param("id", assignment).param("e", examiner).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("assignment", assignment));
    }

    /* ══════════════════════════════ the desk ══════════════════════════════ */

    private static final String EXAMINER_ROW = """
            SELECT e.id, e.person_id, e.title, p.surname, p.given_names, extexam.examiner_name(e.id) AS name, e.email, e.phone, e.institution, e.department, e.rank,
                   e.specialization, e.qualification, e.professional, e.experience_years, e.country, e.region, e.orcid, e.status, e.notes, e.created_at, e.activated_at,
                   e.pg_examiner_id,
                   (SELECT count(*) FROM extexam.assignment a WHERE a.examiner_id = e.id AND a.ended_at IS NULL) AS assigned,
                   (SELECT count(*) FROM extexam.assignment a WHERE a.examiner_id = e.id AND a.ended_at IS NULL AND a.status IN ('ASSIGNED','IN_REVIEW','REOPENED')) AS pending,
                   (SELECT count(*) FROM extexam.assignment a WHERE a.examiner_id = e.id AND a.ended_at IS NULL AND a.status IN ('SUBMITTED','LOCKED')) AS submitted,
                   (SELECT count(*) FROM extexam.assignment a WHERE a.examiner_id = e.id AND a.ended_at IS NULL AND extexam.overdue(a.status, a.deadline)) AS overdue,
                   (SELECT count(*) FROM extexam.appointment ap WHERE ap.examiner_id = e.id AND ap.status = 'ACTIVE' AND ap.ends_on >= current_date) AS live_appointments,
                   (SELECT max(i.sent_at) FROM extexam.invitation i WHERE i.examiner_id = e.id) AS last_invited_at,
                   (SELECT max(i.expires_at) FROM extexam.invitation i WHERE i.examiner_id = e.id AND i.used_at IS NULL) AS invitation_expires_at,
                   (c.person_id IS NOT NULL) AS has_signin, c.last_sign_in_at
              FROM extexam.examiner e JOIN iam.person p ON p.id = e.person_id LEFT JOIN iam.credential c ON c.person_id = e.person_id
            """;

    @GetMapping("/dashboard")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> dashboard(@RequestParam(required = false) String session) {
        Map<String, Object> out = new LinkedHashMap<>();
        String asg = "FROM extexam.assignment a JOIN extexam.project p ON p.id = a.project_id JOIN people.student st ON st.id = p.student_id JOIN ref.programme pr ON pr.code = st.programme_code "
                + "JOIN ref.department d ON d.code = pr.dept_code JOIN ref.faculty f ON f.code = pr.faculty_code WHERE a.ended_at IS NULL AND (:s::text IS NULL OR p.session = :s)" + IN_REACH;
        java.util.function.Function<String, JdbcClient.StatementSpec> with = sql -> reachParams(jdbc.sql(sql)).param("s", session == null || session.isBlank() ? null : session, Types.VARCHAR);
        out.put("totals", with.apply("""
                SELECT (SELECT count(*) FROM extexam.examiner) AS examiners,
                       (SELECT count(*) FROM extexam.examiner WHERE status = 'ACTIVE') AS active_examiners,
                       (SELECT count(*) FROM extexam.examiner WHERE status IN ('INVITED','PENDING_ACTIVATION')) AS pending_invitations,
                       count(*) AS assigned,
                       count(*) FILTER (WHERE a.status IN ('ASSIGNED','IN_REVIEW','REOPENED')) AS pending,
                       count(*) FILTER (WHERE a.status = 'IN_REVIEW') AS in_review,
                       count(*) FILTER (WHERE a.status IN ('SUBMITTED','LOCKED')) AS submitted,
                       count(*) FILTER (WHERE a.status = 'LOCKED') AS locked,
                       count(*) FILTER (WHERE extexam.overdue(a.status, a.deadline)) AS overdue,
                       round(avg(EXTRACT(EPOCH FROM (s.submitted_at - a.assigned_at)) / 86400) FILTER (WHERE s.submitted_at IS NOT NULL)::numeric, 1) AS avg_days_to_submit
                """ + asg.replace("FROM extexam.assignment a", "FROM extexam.assignment a LEFT JOIN extexam.assessment s ON s.assignment_id = a.id")).query().singleRow());
        out.put("byExaminer", with.apply("SELECT extexam.examiner_name(a.examiner_id) AS key, a.examiner_id, count(*) AS n, count(*) FILTER (WHERE a.status IN ('SUBMITTED','LOCKED')) AS submitted, count(*) FILTER (WHERE extexam.overdue(a.status, a.deadline)) AS overdue " + asg + " GROUP BY a.examiner_id ORDER BY n DESC LIMIT 25").query().listOfRows());
        out.put("byDepartment", with.apply("SELECT d.name AS key, count(*) AS n, count(*) FILTER (WHERE a.status IN ('SUBMITTED','LOCKED')) AS submitted, count(*) FILTER (WHERE extexam.overdue(a.status, a.deadline)) AS overdue " + asg + " GROUP BY d.name ORDER BY n DESC").query().listOfRows());
        out.put("byProgramme", with.apply("SELECT pr.name AS key, count(*) AS n, count(*) FILTER (WHERE a.status IN ('SUBMITTED','LOCKED')) AS submitted " + asg + " GROUP BY pr.name ORDER BY n DESC LIMIT 25").query().listOfRows());
        out.put("byStatus", with.apply("SELECT a.status AS key, count(*) AS n " + asg + " GROUP BY a.status ORDER BY n DESC").query().listOfRows());
        out.put("overdueList", with.apply("SELECT a.id, p.title, st.surname || ', ' || st.other_names AS student, coalesce(st.matric_no, st.admission_no) AS number, extexam.examiner_name(a.examiner_id) AS examiner, a.deadline, a.status " + asg + " AND extexam.overdue(a.status, a.deadline) ORDER BY a.deadline LIMIT 20").query().listOfRows());
        out.put("recent", with.apply("SELECT a.id, p.title, st.surname || ', ' || st.other_names AS student, coalesce(st.matric_no, st.admission_no) AS number, extexam.examiner_name(a.examiner_id) AS examiner, a.status, a.deadline, a.assigned_at " + asg + " ORDER BY a.assigned_at DESC LIMIT 10").query().listOfRows());
        out.put("sessions", jdbc.sql("SELECT DISTINCT session FROM extexam.project ORDER BY session DESC").query(String.class).list());
        return out;
    }

    /* ── the examiners ── */

    @GetMapping("/list")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> examiners(@RequestParam(required = false) String q, @RequestParam(required = false) String status) {
        return jdbc.sql(EXAMINER_ROW + """
                 WHERE (:q::text IS NULL OR p.surname ILIKE '%' || :q || '%' OR p.given_names ILIKE '%' || :q || '%' OR e.email ILIKE '%' || :q || '%' OR e.institution ILIKE '%' || :q || '%')
                   AND (:st::text IS NULL OR e.status = :st)
                 ORDER BY (e.status = 'ACTIVE') DESC, p.surname, p.given_names
                """).param("q", q == null || q.isBlank() ? null : q.trim(), Types.VARCHAR).param("st", status == null || status.isBlank() ? null : status.toUpperCase(), Types.VARCHAR).query().listOfRows();
    }

    public record ExaminerIn(@Size(max = 30) String title, @NotBlank @Size(max = 100) String firstName, @Size(max = 100) String middleName, @NotBlank @Size(max = 100) String lastName,
                             @NotBlank @Size(max = 200) String email, @Size(max = 40) String phone, @NotBlank @Size(max = 200) String institution, @Size(max = 200) String department,
                             @Size(max = 120) String rank, @Size(max = 300) String specialization, @Size(max = 200) String qualification, @Size(max = 300) String professional,
                             @Min(0) @Max(70) Integer experienceYears, @Size(max = 80) String country, @Size(max = 80) String region, @Size(max = 40) String orcid, @Size(max = 2000) String notes,
                             UUID pgExaminerId, Boolean invite) {
    }

    /** a new examiner: a person row without a staff number, and the record; invited at once when asked */
    @PostMapping
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> create(Authentication auth, @Valid @RequestBody ExaminerIn body) {
        String email = body.email().trim().toLowerCase();
        if (jdbc.sql("SELECT count(*) FROM extexam.examiner WHERE email = :e").param("e", email).query(Long.class).single() > 0) {
            throw new DomainRuleViolation("EXAMINER_EXISTS", "An examiner with that email is on the register already.", new DomainRuleViolation.Remedy("Open their record and invite or appoint them from there.", "Academic Office"));
        }
        UUID person = UUID.randomUUID();
        String given = (body.firstName().trim() + (body.middleName() == null || body.middleName().isBlank() ? "" : " " + body.middleName().trim()));
        jdbc.sql("INSERT INTO iam.person (id, staff_number, surname, given_names, email, phone) VALUES (:id, NULL, :s, :g, :e, :ph)")
                .param("id", person).param("s", body.lastName().trim()).param("g", given).param("e", email).param("ph", body.phone(), Types.VARCHAR).update();
        UUID id = jdbc.sql("""
                INSERT INTO extexam.examiner (person_id, pg_examiner_id, title, email, phone, institution, department, rank, specialization, qualification, professional, experience_years, country, region, orcid, notes, created_by)
                VALUES (:p, :pg, :t, :e, :ph, :i, :d, :r, :sp, :q, :pr, :y, :c, :rg, :o, :n, :by) RETURNING id
                """).param("p", person).param("pg", body.pgExaminerId(), Types.OTHER).param("t", body.title(), Types.VARCHAR).param("e", email).param("ph", body.phone(), Types.VARCHAR)
                .param("i", body.institution().trim()).param("d", body.department(), Types.VARCHAR).param("r", body.rank(), Types.VARCHAR).param("sp", body.specialization(), Types.VARCHAR)
                .param("q", body.qualification(), Types.VARCHAR).param("pr", body.professional(), Types.VARCHAR).param("y", body.experienceYears(), Types.INTEGER).param("c", body.country(), Types.VARCHAR)
                .param("rg", body.region(), Types.VARCHAR).param("o", body.orcid(), Types.VARCHAR).param("n", body.notes(), Types.VARCHAR).param("by", me(auth)).query(UUID.class).single();
        logEvent(auth, "EXAMINER_CREATED", id, null, null, null, body.institution(), null);
        Map<String, Object> out = new LinkedHashMap<>(Map.of("id", id, "personId", person));
        if (Boolean.TRUE.equals(body.invite())) out.put("invitation", invite(auth, id));
        return out;
    }

    @GetMapping("/{id}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> examiner(@PathVariable UUID id) {
        Map<String, Object> e = jdbc.sql(EXAMINER_ROW + " WHERE e.id = :id").param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("examiner", id));
        Map<String, Object> out = new LinkedHashMap<>(e);
        out.put("appointments", jdbc.sql("""
                SELECT ap.id, ap.session, ap.semester, ap.faculty_code, f.name AS faculty, ap.dept_code, d.name AS department, ap.programme_code, pr.name AS programme, ap.period,
                       ap.starts_on, ap.ends_on, ap.status, ap.instrument, ap.appointed_at, (SELECT p2.surname || ', ' || p2.given_names FROM iam.person p2 WHERE p2.id = ap.appointed_by) AS appointed_by
                  FROM extexam.appointment ap JOIN ref.faculty f ON f.code = ap.faculty_code JOIN ref.department d ON d.code = ap.dept_code LEFT JOIN ref.programme pr ON pr.code = ap.programme_code
                 WHERE ap.examiner_id = :id ORDER BY ap.starts_on DESC
                """).param("id", id).query().listOfRows());
        out.put("assignments", jdbc.sql(ASSIGNMENT_ROW + " WHERE a.examiner_id = :id ORDER BY a.ended_at IS NOT NULL, a.deadline").param("id", id).query().listOfRows());
        out.put("files", jdbc.sql("SELECT id, kind, filename, content_type, bytes, uploaded_at FROM extexam.examiner_file WHERE examiner_id = :id ORDER BY uploaded_at DESC").param("id", id).query().listOfRows());
        out.put("history", jdbc.sql("SELECT at, actor_name, actor_office, action, from_value, to_value, reason FROM extexam.event WHERE examiner_id = :id ORDER BY at DESC LIMIT 40").param("id", id).query().listOfRows());
        return out;
    }

    @PutMapping("/{id}")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> edit(Authentication auth, @PathVariable UUID id, @Valid @RequestBody ExaminerIn body) {
        UUID person = jdbc.sql("SELECT person_id FROM extexam.examiner WHERE id = :id").param("id", id).query(UUID.class).optional().orElseThrow(() -> new NotFound("examiner", id));
        String email = body.email().trim().toLowerCase();
        String given = (body.firstName().trim() + (body.middleName() == null || body.middleName().isBlank() ? "" : " " + body.middleName().trim()));
        jdbc.sql("UPDATE iam.person SET surname = :s, given_names = :g, email = :e, phone = :ph WHERE id = :id").param("id", person).param("s", body.lastName().trim()).param("g", given).param("e", email).param("ph", body.phone(), Types.VARCHAR).update();
        jdbc.sql("""
                UPDATE extexam.examiner SET title = :t, email = :e, phone = :ph, institution = :i, department = :d, rank = :r, specialization = :sp, qualification = :q, professional = :pr,
                       experience_years = :y, country = :c, region = :rg, orcid = :o, notes = :n, pg_examiner_id = coalesce(:pg, pg_examiner_id) WHERE id = :id
                """).param("id", id).param("t", body.title(), Types.VARCHAR).param("e", email).param("ph", body.phone(), Types.VARCHAR).param("i", body.institution().trim()).param("d", body.department(), Types.VARCHAR)
                .param("r", body.rank(), Types.VARCHAR).param("sp", body.specialization(), Types.VARCHAR).param("q", body.qualification(), Types.VARCHAR).param("pr", body.professional(), Types.VARCHAR)
                .param("y", body.experienceYears(), Types.INTEGER).param("c", body.country(), Types.VARCHAR).param("rg", body.region(), Types.VARCHAR).param("o", body.orcid(), Types.VARCHAR)
                .param("n", body.notes(), Types.VARCHAR).param("pg", body.pgExaminerId(), Types.OTHER).update();
        // the username follows the email while no sign-in exists yet
        jdbc.sql("UPDATE iam.credential SET username = :u WHERE person_id = :p AND NOT EXISTS (SELECT 1 FROM iam.credential c2 WHERE c2.username = :u AND c2.person_id <> :p)").param("u", email).param("p", person).update();
        logEvent(auth, "EXAMINER_EDITED", id, null, null, null, null, null);
        return Map.of("id", id);
    }

    /** the invitation: a token kept as a hash, a fortnight's life, spent once; the email carries the link */
    @PostMapping("/{id}/invite")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> invite(Authentication auth, @PathVariable UUID id) {
        Map<String, Object> e = jdbc.sql("SELECT status, email FROM extexam.examiner WHERE id = :id").param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("examiner", id));
        if ("SUSPENDED".equals(e.get("status")) || "INACTIVE".equals(e.get("status"))) {
            throw new DomainRuleViolation("EXAMINER_NOT_INVITABLE", "A suspended or inactive examiner is not invited.", new DomainRuleViolation.Remedy("Set the examiner active first.", "Academic Office"));
        }
        boolean again = jdbc.sql("SELECT count(*) FROM extexam.invitation WHERE examiner_id = :id").param("id", id).query(Long.class).single() > 0;
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        String token = HexFormat.of().formatHex(bytes);
        LocalDate expires = LocalDate.now().plusDays(14);
        jdbc.sql("UPDATE extexam.invitation SET used_at = now() WHERE examiner_id = :id AND used_at IS NULL").param("id", id).update();
        jdbc.sql("INSERT INTO extexam.invitation (examiner_id, token_hash, sent_by, expires_at) VALUES (:id, :h, :by, now() + interval '14 days')").param("id", id).param("h", sha256(token)).param("by", me(auth)).update();
        if (!"ACTIVE".equals(e.get("status"))) jdbc.sql("UPDATE extexam.examiner SET status = 'PENDING_ACTIVATION' WHERE id = :id").param("id", id).update();
        String appointment = jdbc.sql("""
                SELECT string_agg(d.name || ' (' || ap.session || ')', '; ' ORDER BY ap.starts_on DESC) FROM extexam.appointment ap JOIN ref.department d ON d.code = ap.dept_code
                 WHERE ap.examiner_id = :id AND ap.status = 'ACTIVE'
                """).param("id", id).query(String.class).optional().orElse(null);
        String link = portalUrl() + "/login/activate?token=" + token;
        notifier.invited(id, link, expires, appointment);
        logEvent(auth, again ? "INVITATION_RESENT" : "EXAMINER_INVITED", id, null, null, null, expires.toString(), null);
        return Map.of("id", id, "expiresOn", expires.toString(), "resent", again);
    }

    private String portalUrl() {
        return portalUrlProperty.endsWith("/") ? portalUrlProperty.substring(0, portalUrlProperty.length() - 1) : portalUrlProperty;
    }

    @org.springframework.beans.factory.annotation.Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}")
    private String portalUrlProperty;

    public record StatusIn(@NotBlank String status, @Size(max = 1000) String reason) {
    }

    /** active, suspended or inactive; the office grant follows, so a suspended examiner cannot act */
    @PostMapping("/{id}/status")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> status(Authentication auth, @PathVariable UUID id, @Valid @RequestBody StatusIn body) {
        String to = body.status().trim().toUpperCase();
        if (!Set.of("ACTIVE", "SUSPENDED", "INACTIVE").contains(to)) throw new DomainRuleViolation("EXAMINER_STATUS", "An examiner is set active, suspended or inactive.", new DomainRuleViolation.Remedy("Choose one of the three.", "Academic Office"));
        Map<String, Object> e = jdbc.sql("SELECT status, person_id, activated_at FROM extexam.examiner WHERE id = :id").param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("examiner", id));
        String from = (String) e.get("status");
        UUID person = (UUID) e.get("person_id");
        if ("ACTIVE".equals(to) && e.get("activated_at") == null) {
            throw new DomainRuleViolation("EXAMINER_NOT_ACTIVATED", "An examiner becomes active by activating their account through the invitation link.", new DomainRuleViolation.Remedy("Send or resend the invitation instead.", "Academic Office"));
        }
        if (!"ACTIVE".equals(to) && (body.reason() == null || body.reason().isBlank())) {
            throw new DomainRuleViolation("EXAMINER_STATUS_REASON", "Suspending or deactivating an examiner records the reason.", new DomainRuleViolation.Remedy("Say why, in a line.", "Academic Office"));
        }
        jdbc.sql("UPDATE extexam.examiner SET status = :s WHERE id = :id").param("id", id).param("s", to).update();
        if ("ACTIVE".equals(to)) grantOffice(person, me(auth));
        else jdbc.sql("""
                SELECT iam.end_grant(a.id, current_date, :r) FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'extexaminer' AND a.valid_to IS NULL
                """).param("p", person).param("r", "Examiner " + to.toLowerCase() + ": " + body.reason().trim()).query().listOfRows();
        logEvent(auth, "EXAMINER_STATUS", id, null, null, from, to, body.reason());
        return Map.of("id", id, "status", to);
    }

    private void grantOffice(UUID person, UUID by) {
        jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'extexaminer', 'institution', NULL, 'Appointment as External Examiner (V254)', :by, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'extexaminer' AND a.valid_to IS NULL)
                """).param("p", person).param("by", by).update();
    }

    public record Upload(@NotBlank @Size(max = 200) String filename, @NotBlank String contentType, @NotBlank @Size(max = 36_000_000) String contentBase64, String kind) {
    }

    @PostMapping("/{id}/files")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> examinerFile(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Upload body) {
        jdbc.sql("SELECT id FROM extexam.examiner WHERE id = :id").param("id", id).query(UUID.class).optional().orElseThrow(() -> new NotFound("examiner", id));
        String kind = body.kind() == null ? "CV" : body.kind().trim().toUpperCase();
        if (!Set.of("CV", "PHOTO").contains(kind)) throw new DomainRuleViolation("EXAMINER_FILE_KIND", "An examiner's file is a CV or a photo.", new DomainRuleViolation.Remedy("Choose one.", "Academic Office"));
        byte[] bytes = decoded(body, PRIVATE_TYPES, MAX_PRIVATE);
        String type = normalType(body.contentType());
        UUID f = jdbc.sql("INSERT INTO extexam.examiner_file (examiner_id, kind, filename, content_type, bytes, uploaded_by) VALUES (:e, :k, :f, :t, :b, :by) RETURNING id")
                .param("e", id).param("k", kind).param("f", safeName(body.filename())).param("t", type).param("b", (long) bytes.length).param("by", me(auth)).query(UUID.class).single();
        jdbc.sql("INSERT INTO extexam.examiner_file_blob (file_id, content) VALUES (:f, :c)").param("f", f).param("c", bytes).update();
        return Map.of("id", f, "kind", kind);
    }

    @GetMapping("/{id}/files/{file}/content")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> examinerFileContent(@PathVariable UUID id, @PathVariable UUID file) {
        Map<String, Object> r = jdbc.sql("SELECT f.filename, f.content_type, b.content FROM extexam.examiner_file f JOIN extexam.examiner_file_blob b ON b.file_id = f.id WHERE f.id = :f AND f.examiner_id = :e")
                .param("f", file).param("e", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("file", file));
        return serve(r);
    }

    /* ── the appointments ── */

    public record AppointmentIn(@NotBlank @Size(max = 12) String session, @Min(1) @Max(3) Integer semester, @NotBlank String facultyCode, @NotBlank String deptCode, String programmeCode,
                                @Size(max = 200) String period, @NotNull LocalDate startsOn, @NotNull LocalDate endsOn, @Size(max = 200) String instrument) {
    }

    @PostMapping("/{id}/appointments")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> appoint(Authentication auth, @PathVariable UUID id, @Valid @RequestBody AppointmentIn body) {
        jdbc.sql("SELECT id FROM extexam.examiner WHERE id = :id").param("id", id).query(UUID.class).optional().orElseThrow(() -> new NotFound("examiner", id));
        Reach r = reach();
        if (r.dept() != null && !r.dept().equals(body.deptCode())) throw new DomainRuleViolation("EXAMINER_REACH", "A department appoints examiners for its own department.", new DomainRuleViolation.Remedy("Choose your own department.", "Academic Office"));
        UUID ap = jdbc.sql("""
                INSERT INTO extexam.appointment (examiner_id, session, semester, faculty_code, dept_code, programme_code, period, starts_on, ends_on, instrument, appointed_by)
                VALUES (:e, :s, :sem, :f, :d, :p, :per, :from, :to, :i, :by) RETURNING id
                """).param("e", id).param("s", body.session().trim()).param("sem", body.semester(), Types.INTEGER).param("f", body.facultyCode()).param("d", body.deptCode()).param("p", body.programmeCode(), Types.VARCHAR)
                .param("per", body.period(), Types.VARCHAR).param("from", body.startsOn()).param("to", body.endsOn()).param("i", body.instrument(), Types.VARCHAR).param("by", me(auth)).query(UUID.class).single();
        String dept = jdbc.sql("SELECT name FROM ref.department WHERE code = :d").param("d", body.deptCode()).query(String.class).single();
        logEvent(auth, "APPOINTED", id, null, null, null, dept + " · " + body.session().trim(), body.instrument());
        notifier.appointed(id, dept + ", " + body.session().trim(), body.startsOn(), body.endsOn());
        return Map.of("id", ap);
    }

    public record Reason(@Size(max = 2000) String reason) {
    }

    @PostMapping("/appointments/{id}/end")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> endAppointment(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Reason body) {
        Map<String, Object> ap = jdbc.sql("SELECT examiner_id, status FROM extexam.appointment WHERE id = :id").param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("appointment", id));
        jdbc.sql("UPDATE extexam.appointment SET status = 'ENDED', ends_on = least(ends_on, current_date) WHERE id = :id").param("id", id).update();
        logEvent(auth, "APPOINTMENT_ENDED", (UUID) ap.get("examiner_id"), null, null, (String) ap.get("status"), "ENDED", body.reason());
        return Map.of("id", id, "status", "ENDED");
    }

    @GetMapping("/appointments")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> appointments(@RequestParam(required = false) String session) {
        return reachParams(jdbc.sql("""
                SELECT ap.id, ap.examiner_id, extexam.examiner_name(ap.examiner_id) AS examiner, e.institution, e.status AS examiner_status, ap.session, ap.semester,
                       ap.faculty_code, f.name AS faculty, ap.dept_code, d.name AS department, ap.programme_code, pr.name AS programme, ap.period, ap.starts_on, ap.ends_on, ap.status, ap.instrument, ap.appointed_at,
                       (SELECT count(*) FROM extexam.assignment a WHERE a.appointment_id = ap.id AND a.ended_at IS NULL) AS assignments
                  FROM extexam.appointment ap JOIN extexam.examiner e ON e.id = ap.examiner_id JOIN ref.faculty f ON f.code = ap.faculty_code JOIN ref.department d ON d.code = ap.dept_code
                  LEFT JOIN ref.programme pr ON pr.code = ap.programme_code
                 WHERE (:s::text IS NULL OR ap.session = :s) AND (:rdept::text IS NULL OR ap.dept_code = :rdept OR d.name = :rdept) AND (:rfac::text IS NULL OR ap.faculty_code = :rfac OR f.name = :rfac)
                 ORDER BY ap.session DESC, ap.starts_on DESC
                """)).param("s", session == null || session.isBlank() ? null : session, Types.VARCHAR).query().listOfRows();
    }

    /* ── the projects ── */

    private static final String PROJECT_ROW = """
            SELECT p.id, p.kind, p.session, p.title, p.abstract, p.keywords, p.project_type, p.submitted_on, p.supervisor_id, coalesce((SELECT sp.surname || ', ' || sp.given_names FROM iam.person sp WHERE sp.id = p.supervisor_id), p.supervisor_name) AS supervisor,
                   p.co_supervisor, p.pg_research_id, p.course_code, p.created_at,
                   st.id AS student_id, st.surname || ', ' || st.other_names AS student, coalesce(st.matric_no, st.admission_no) AS number, st.current_level AS level,
                   pr.code AS programme_code, pr.name AS programme, d.code AS dept_code, d.name AS department, f.code AS faculty_code, f.name AS faculty,
                   (SELECT count(*) FROM extexam.project_document pd WHERE pd.project_id = p.id AND pd.released) AS documents,
                   (SELECT count(*) FROM extexam.assignment a WHERE a.project_id = p.id AND a.ended_at IS NULL) AS examiners,
                   (SELECT string_agg(extexam.examiner_name(a.examiner_id) || ' (' || lower(replace(a.status, '_', ' ')) || ')', '; ') FROM extexam.assignment a WHERE a.project_id = p.id AND a.ended_at IS NULL) AS examiner_names,
                   (SELECT count(*) FROM extexam.assignment a WHERE a.project_id = p.id AND a.ended_at IS NULL AND a.status IN ('SUBMITTED','LOCKED')) AS submitted
              FROM extexam.project p JOIN people.student st ON st.id = p.student_id JOIN ref.programme pr ON pr.code = st.programme_code
              JOIN ref.department d ON d.code = pr.dept_code JOIN ref.faculty f ON f.code = pr.faculty_code
            """;

    @GetMapping("/projects")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> projects(@RequestParam(required = false) String session, @RequestParam(required = false) String q, @RequestParam(required = false) String dept) {
        return reachParams(jdbc.sql(PROJECT_ROW + """
                 WHERE (:s::text IS NULL OR p.session = :s) AND (:dept::text IS NULL OR d.code = :dept)
                   AND (:q::text IS NULL OR p.title ILIKE '%' || :q || '%' OR st.surname ILIKE '%' || :q || '%' OR st.other_names ILIKE '%' || :q || '%' OR st.matric_no ILIKE '%' || :q || '%')
                """ + IN_REACH + " ORDER BY p.session DESC, st.surname LIMIT 500"))
                .param("s", session == null || session.isBlank() ? null : session, Types.VARCHAR).param("dept", dept == null || dept.isBlank() ? null : dept, Types.VARCHAR)
                .param("q", q == null || q.isBlank() ? null : q.trim(), Types.VARCHAR).query().listOfRows();
    }

    /** the students a project can be registered for: finalists, and postgraduates with a research record, within reach */
    @GetMapping("/students")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> students(@RequestParam String q) {
        return reachParams(jdbc.sql("""
                SELECT st.id, st.surname || ', ' || st.other_names AS name, coalesce(st.matric_no, st.admission_no) AS number, st.current_level AS level, pr.name AS programme, d.name AS department,
                       (st.entry_mode = 'POSTGRADUATE' OR pr.category = 'POST GRADUATE') AS postgraduate, r.id AS pg_research_id, r.topic AS pg_topic, r.degree_kind
                  FROM people.student st JOIN ref.programme pr ON pr.code = st.programme_code JOIN ref.department d ON d.code = pr.dept_code JOIN ref.faculty f ON f.code = pr.faculty_code
                  LEFT JOIN admissions.pg_research r ON r.student_id = st.id
                 WHERE st.status IN ('ACTIVE','PROBATION') AND (st.surname ILIKE '%' || :q || '%' OR st.other_names ILIKE '%' || :q || '%' OR st.matric_no ILIKE '%' || :q || '%')
                   AND (st.current_level >= finance.final_level(st.programme_code) OR st.entry_mode = 'POSTGRADUATE' OR pr.category = 'POST GRADUATE')
                """ + IN_REACH + " ORDER BY st.surname, st.other_names LIMIT 30")).param("q", q.trim()).query().listOfRows();
    }

    /** internal staff who may supervise: the lecturers, for the supervisor picker */
    @GetMapping("/supervisors")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> supervisors(@RequestParam String q) {
        return jdbc.sql("""
                SELECT DISTINCT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number, d.name AS department
                  FROM iam.person p JOIN iam.office_assignment a ON a.person_id = p.id AND a.office_code = 'lecturer' AND a.valid_to IS NULL LEFT JOIN ref.department d ON d.code = a.scope_id
                 WHERE p.ended_on IS NULL AND (p.surname ILIKE '%' || :q || '%' OR p.given_names ILIKE '%' || :q || '%' OR p.staff_number ILIKE '%' || :q || '%')
                 ORDER BY name LIMIT 25
                """).param("q", q.trim()).query().listOfRows();
    }

    public record ProjectIn(@NotNull UUID studentId, @NotBlank @Size(max = 12) String session, @NotBlank @Size(max = 400) String title, @Size(max = 8000) String abstractText, @Size(max = 400) String keywords,
                            @Size(max = 120) String projectType, LocalDate submittedOn, UUID supervisorId, @Size(max = 200) String supervisorName, @Size(max = 200) String coSupervisor, @Size(max = 12) String courseCode) {
    }

    @PostMapping("/projects")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> newProject(Authentication auth, @Valid @RequestBody ProjectIn body) {
        Map<String, Object> st = reachParams(jdbc.sql("""
                SELECT st.id, (st.entry_mode = 'POSTGRADUATE' OR pr.category = 'POST GRADUATE') AS pg, r.id AS research_id
                  FROM people.student st JOIN ref.programme pr ON pr.code = st.programme_code JOIN ref.department d ON d.code = pr.dept_code JOIN ref.faculty f ON f.code = pr.faculty_code
                  LEFT JOIN admissions.pg_research r ON r.student_id = st.id WHERE st.id = :id
                """ + IN_REACH).param("id", body.studentId())).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", body.studentId()));
        boolean pg = Boolean.TRUE.equals(st.get("pg"));
        UUID id = jdbc.sql("""
                INSERT INTO extexam.project (student_id, kind, pg_research_id, course_code, session, title, abstract, keywords, project_type, submitted_on, supervisor_id, supervisor_name, co_supervisor, created_by)
                VALUES (:st, :k, :r, :cc, :s, :t, :a, :kw, :pt, :so, :sup, :supn, :co, :by) RETURNING id
                """).param("st", body.studentId()).param("k", pg ? "POSTGRADUATE" : "UNDERGRADUATE").param("r", st.get("research_id"), Types.OTHER).param("cc", body.courseCode(), Types.VARCHAR)
                .param("s", body.session().trim()).param("t", body.title().trim()).param("a", body.abstractText(), Types.VARCHAR).param("kw", body.keywords(), Types.VARCHAR).param("pt", body.projectType(), Types.VARCHAR)
                .param("so", body.submittedOn(), Types.DATE).param("sup", body.supervisorId(), Types.OTHER).param("supn", body.supervisorName(), Types.VARCHAR).param("co", body.coSupervisor(), Types.VARCHAR).param("by", me(auth)).query(UUID.class).single();
        logEvent(auth, "PROJECT_CREATED", null, id, null, null, body.title().trim(), null);
        return Map.of("id", id, "kind", pg ? "POSTGRADUATE" : "UNDERGRADUATE");
    }

    @GetMapping("/projects/{id}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> project(@PathVariable UUID id) {
        requireProject(id);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql(PROJECT_ROW + " WHERE p.id = :id").param("id", id).query().singleRow());
        out.put("documents", jdbc.sql("SELECT id, kind, filename, content_type, bytes, released, uploaded_at FROM extexam.project_document WHERE project_id = :id ORDER BY kind, uploaded_at").param("id", id).query().listOfRows());
        out.put("assignments", jdbc.sql(ASSIGNMENT_ROW + " WHERE a.project_id = :id ORDER BY a.ended_at IS NOT NULL, a.assigned_at").param("id", id).query().listOfRows());
        out.put("history", jdbc.sql("SELECT at, actor_name, actor_office, action, from_value, to_value, reason FROM extexam.event WHERE project_id = :id ORDER BY at DESC LIMIT 40").param("id", id).query().listOfRows());
        return out;
    }

    @PutMapping("/projects/{id}")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> editProject(Authentication auth, @PathVariable UUID id, @Valid @RequestBody ProjectIn body) {
        requireProject(id);
        jdbc.sql("""
                UPDATE extexam.project SET title = :t, abstract = :a, keywords = :kw, project_type = :pt, submitted_on = :so, supervisor_id = :sup, supervisor_name = :supn, co_supervisor = :co, course_code = :cc WHERE id = :id
                """).param("id", id).param("t", body.title().trim()).param("a", body.abstractText(), Types.VARCHAR).param("kw", body.keywords(), Types.VARCHAR).param("pt", body.projectType(), Types.VARCHAR)
                .param("so", body.submittedOn(), Types.DATE).param("sup", body.supervisorId(), Types.OTHER).param("supn", body.supervisorName(), Types.VARCHAR).param("co", body.coSupervisor(), Types.VARCHAR).param("cc", body.courseCode(), Types.VARCHAR).update();
        logEvent(auth, "PROJECT_EDITED", null, id, null, null, body.title().trim(), null);
        return Map.of("id", id);
    }

    @PostMapping("/projects/{id}/documents")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> releaseDocument(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Upload body) {
        requireProject(id);
        String kind = body.kind() == null ? "REPORT" : body.kind().trim().toUpperCase();
        if (!DOC_KINDS.contains(kind)) throw new DomainRuleViolation("PROJECT_DOC_KIND", "A project document is the proposal, the report, the source, the presentation or a supporting document.", new DomainRuleViolation.Remedy("Choose one of those.", "Academic Office"));
        byte[] bytes = decoded(body, DOC_TYPES, MAX_DOC);
        String type = normalType(body.contentType());
        UUID d = jdbc.sql("INSERT INTO extexam.project_document (project_id, kind, filename, content_type, bytes, uploaded_by) VALUES (:p, :k, :f, :t, :b, :by) RETURNING id")
                .param("p", id).param("k", kind).param("f", safeName(body.filename())).param("t", type).param("b", (long) bytes.length).param("by", me(auth)).query(UUID.class).single();
        jdbc.sql("INSERT INTO extexam.project_document_blob (document_id, content) VALUES (:d, :c)").param("d", d).param("c", bytes).update();
        logEvent(auth, "DOCUMENT_RELEASED", null, id, null, null, kind + ": " + safeName(body.filename()), null);
        return Map.of("id", d, "kind", kind, "bytes", bytes.length);
    }

    public record Released(@NotNull Boolean released) {
    }

    @PutMapping("/projects/{id}/documents/{doc}")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> toggleDocument(Authentication auth, @PathVariable UUID id, @PathVariable UUID doc, @Valid @RequestBody Released body) {
        requireProject(id);
        int n = jdbc.sql("UPDATE extexam.project_document SET released = :r WHERE id = :d AND project_id = :p").param("r", body.released()).param("d", doc).param("p", id).update();
        if (n == 0) throw new NotFound("document", doc);
        logEvent(auth, body.released() ? "DOCUMENT_RELEASED" : "DOCUMENT_WITHDRAWN", null, id, null, null, doc.toString(), null);
        return Map.of("id", doc, "released", body.released());
    }

    @GetMapping("/projects/{id}/documents/{doc}/content")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> deskDocument(@PathVariable UUID id, @PathVariable UUID doc) {
        requireProject(id);
        return serve(document(id, doc, false));
    }

    private Map<String, Object> document(UUID project, UUID doc, boolean releasedOnly) {
        return jdbc.sql("SELECT d.filename, d.content_type, b.content FROM extexam.project_document d JOIN extexam.project_document_blob b ON b.document_id = d.id WHERE d.id = :d AND d.project_id = :p AND (NOT :ro OR d.released)")
                .param("d", doc).param("p", project).param("ro", releasedOnly).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("document", doc));
    }

    /* ── the form ── */

    @GetMapping("/rubrics")
    @PreAuthorize(DESK + " or " + EXAMINER)
    @Transactional(readOnly = true)
    List<Map<String, Object>> rubrics() {
        List<Map<String, Object>> rubrics = jdbc.sql("SELECT id, code, name, kind, active, has_defence, note, (SELECT count(*) FROM extexam.assignment a WHERE a.rubric_id = r.id) AS used FROM extexam.rubric r ORDER BY kind, code").query().listOfRows();
        for (Map<String, Object> r : rubrics) {
            r.put("criteria", jdbc.sql("SELECT id, section, name, guidance, max_score, ordinal, active FROM extexam.criterion WHERE rubric_id = :r ORDER BY ordinal").param("r", r.get("id")).query().listOfRows());
        }
        return rubrics;
    }

    public record RubricIn(@NotBlank @Size(max = 120) String name, @Size(max = 32) String code, String kind, Boolean active, Boolean hasDefence, @Size(max = 500) String note) {
    }

    @PostMapping("/rubrics")
    @PreAuthorize(FORM)
    @Transactional
    Map<String, Object> newRubric(@Valid @RequestBody RubricIn body) {
        String code = body.code() == null || body.code().isBlank() ? body.name().trim().toUpperCase().replaceAll("[^A-Z0-9]+", "_").replaceAll("^_+|_+$", "") : body.code().trim().toUpperCase();
        String kind = body.kind() == null ? "UNDERGRADUATE" : body.kind().trim().toUpperCase();
        UUID id = jdbc.sql("INSERT INTO extexam.rubric (code, name, kind, active, has_defence, note) VALUES (:c, :n, :k, :a, :d, :no) RETURNING id")
                .param("c", code).param("n", body.name().trim()).param("k", kind).param("a", body.active() == null || body.active()).param("d", body.hasDefence() == null || body.hasDefence()).param("no", body.note(), Types.VARCHAR).query(UUID.class).single();
        return Map.of("id", id, "code", code);
    }

    @PutMapping("/rubrics/{id}")
    @PreAuthorize(FORM)
    @Transactional
    Map<String, Object> editRubric(@PathVariable UUID id, @Valid @RequestBody RubricIn body) {
        int n = jdbc.sql("UPDATE extexam.rubric SET name = :n, active = :a, has_defence = :d, note = :no WHERE id = :id").param("id", id).param("n", body.name().trim())
                .param("a", body.active() == null || body.active()).param("d", body.hasDefence() == null || body.hasDefence()).param("no", body.note(), Types.VARCHAR).update();
        if (n == 0) throw new NotFound("rubric", id);
        return Map.of("id", id);
    }

    public record CriterionIn(@NotBlank @Size(max = 200) String name, @Size(max = 500) String guidance, @NotNull java.math.BigDecimal maxScore, String section, Integer ordinal, Boolean active) {
    }

    @PostMapping("/rubrics/{id}/criteria")
    @PreAuthorize(FORM)
    @Transactional
    Map<String, Object> newCriterion(@PathVariable UUID id, @Valid @RequestBody CriterionIn body) {
        String section = body.section() == null ? "WRITTEN" : body.section().trim().toUpperCase();
        Integer ordinal = body.ordinal() != null ? body.ordinal() : jdbc.sql("SELECT coalesce(max(ordinal), 0) + 1 FROM extexam.criterion WHERE rubric_id = :r").param("r", id).query(Integer.class).single();
        UUID c = jdbc.sql("INSERT INTO extexam.criterion (rubric_id, section, name, guidance, max_score, ordinal, active) VALUES (:r, :s, :n, :g, :m, :o, :a) RETURNING id")
                .param("r", id).param("s", section).param("n", body.name().trim()).param("g", body.guidance(), Types.VARCHAR).param("m", body.maxScore()).param("o", ordinal).param("a", body.active() == null || body.active()).query(UUID.class).single();
        return Map.of("id", c);
    }

    @PutMapping("/criteria/{id}")
    @PreAuthorize(FORM)
    @Transactional
    Map<String, Object> editCriterion(@PathVariable UUID id, @Valid @RequestBody CriterionIn body) {
        String section = body.section() == null ? "WRITTEN" : body.section().trim().toUpperCase();
        int n = jdbc.sql("UPDATE extexam.criterion SET name = :n, guidance = :g, max_score = :m, section = :s, ordinal = coalesce(:o, ordinal), active = :a WHERE id = :id")
                .param("id", id).param("n", body.name().trim()).param("g", body.guidance(), Types.VARCHAR).param("m", body.maxScore()).param("s", section).param("o", body.ordinal(), Types.INTEGER).param("a", body.active() == null || body.active()).update();
        if (n == 0) throw new NotFound("criterion", id);
        return Map.of("id", id);
    }

    /* ── the assignments ── */

    private static final String ASSIGNMENT_ROW = """
            SELECT a.id, a.project_id, a.examiner_id, extexam.examiner_name(a.examiner_id) AS examiner, e.institution, e.status AS examiner_status, a.appointment_id, a.rubric_id, r.name AS rubric,
                   a.deadline, a.exam_date, a.status, a.assigned_at, a.first_viewed_at, a.ended_at, a.ended_reason, a.replaced_by,
                   (SELECT p2.surname || ', ' || p2.given_names FROM iam.person p2 WHERE p2.id = a.assigned_by) AS assigned_by,
                   extexam.overdue(a.status, a.deadline) AS overdue, (a.deadline - current_date) AS days_left,
                   p.title, p.kind, p.session, st.surname || ', ' || st.other_names AS student, coalesce(st.matric_no, st.admission_no) AS number,
                   pr.name AS programme, d.name AS department, d.code AS dept_code, f.name AS faculty,
                   coalesce((SELECT sp.surname || ', ' || sp.given_names FROM iam.person sp WHERE sp.id = p.supervisor_id), p.supervisor_name) AS supervisor, p.submitted_on,
                   s.id AS assessment_id, s.state AS assessment_state, s.total, s.max_total, s.percentage, s.grade, s.final_recommendation, s.submitted_at, s.locked_at, s.reopened_at
              FROM extexam.assignment a JOIN extexam.examiner e ON e.id = a.examiner_id JOIN extexam.rubric r ON r.id = a.rubric_id
              JOIN extexam.project p ON p.id = a.project_id JOIN people.student st ON st.id = p.student_id JOIN ref.programme pr ON pr.code = st.programme_code
              JOIN ref.department d ON d.code = pr.dept_code JOIN ref.faculty f ON f.code = pr.faculty_code
              LEFT JOIN extexam.assessment s ON s.assignment_id = a.id
            """;

    public record AssignIn(@NotNull UUID projectId, @NotNull UUID examinerId, UUID appointmentId, UUID rubricId, @NotNull LocalDate deadline, LocalDate examDate) {
    }

    @PostMapping("/assignments")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> assign(Authentication auth, @Valid @RequestBody AssignIn body) {
        requireProject(body.projectId());
        Map<String, Object> ex = jdbc.sql("SELECT status FROM extexam.examiner WHERE id = :id").param("id", body.examinerId()).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("examiner", body.examinerId()));
        if (!"ACTIVE".equals(ex.get("status"))) {
            throw new DomainRuleViolation("EXAMINER_NOT_ACTIVE", "A project is assigned to an examiner whose account is active.", new DomainRuleViolation.Remedy("Invite the examiner and wait for the activation, or set them active.", "Academic Office"));
        }
        if (body.deadline().isBefore(LocalDate.now())) throw new DomainRuleViolation("ASSIGNMENT_DEADLINE", "The review deadline is today or later.", new DomainRuleViolation.Remedy("Choose a later date.", "Academic Office"));
        UUID id = doAssign(auth, body.projectId(), body.examinerId(), body.appointmentId(), body.rubricId(), body.deadline(), body.examDate());
        notifier.assigned(id);
        return Map.of("id", id);
    }

    private UUID doAssign(Authentication auth, UUID project, UUID examiner, UUID appointment, UUID rubric, LocalDate deadline, LocalDate examDate) {
        if (appointment != null) {
            Boolean ok = jdbc.sql("SELECT true FROM extexam.appointment WHERE id = :a AND examiner_id = :e AND status = 'ACTIVE'").param("a", appointment).param("e", examiner).query(Boolean.class).optional().orElse(false);
            if (!ok) throw new DomainRuleViolation("ASSIGNMENT_APPOINTMENT", "The appointment named is not this examiner's live appointment.", new DomainRuleViolation.Remedy("Choose one of the examiner's active appointments, or none.", "Academic Office"));
        } else {
            appointment = jdbc.sql("""
                    SELECT ap.id FROM extexam.appointment ap JOIN extexam.project p ON p.id = :p JOIN people.student st ON st.id = p.student_id JOIN ref.programme pr ON pr.code = st.programme_code
                     WHERE ap.examiner_id = :e AND ap.status = 'ACTIVE' AND ap.session = p.session AND ap.dept_code = pr.dept_code ORDER BY ap.starts_on DESC LIMIT 1
                    """).param("p", project).param("e", examiner).query(UUID.class).optional().orElse(null);
        }
        if (rubric == null) {
            rubric = jdbc.sql("SELECT r.id FROM extexam.rubric r JOIN extexam.project p ON p.id = :p WHERE r.active AND r.kind = p.kind ORDER BY r.code LIMIT 1").param("p", project).query(UUID.class).optional()
                    .orElseThrow(() -> new DomainRuleViolation("ASSIGNMENT_RUBRIC", "No active assessment form exists for this kind of project.", new DomainRuleViolation.Remedy("Set one up under the assessment criteria.", "Academic Office")));
        }
        if (jdbc.sql("SELECT count(*) FROM extexam.assignment WHERE project_id = :p AND examiner_id = :e AND ended_at IS NULL").param("p", project).param("e", examiner).query(Long.class).single() > 0) {
            throw new DomainRuleViolation("ASSIGNMENT_EXISTS", "This project is with that examiner already.", new DomainRuleViolation.Remedy("Reassign or extend the deadline instead.", "Academic Office"));
        }
        UUID id = jdbc.sql("INSERT INTO extexam.assignment (project_id, examiner_id, appointment_id, rubric_id, deadline, exam_date, assigned_by) VALUES (:p, :e, :ap, :r, :d, :x, :by) RETURNING id")
                .param("p", project).param("e", examiner).param("ap", appointment, Types.OTHER).param("r", rubric).param("d", deadline).param("x", examDate, Types.DATE).param("by", me(auth)).query(UUID.class).single();
        logEvent(auth, "PROJECT_ASSIGNED", examiner, project, id, null, deadline.toString(), null);
        return id;
    }

    @GetMapping("/assignments")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> assignments(@RequestParam(required = false) String session, @RequestParam(required = false) String status, @RequestParam(required = false) UUID examiner,
                                          @RequestParam(required = false) String dept, @RequestParam(required = false) String programme, @RequestParam(required = false) Boolean overdue,
                                          @RequestParam(required = false) String q) {
        List<String> statuses = status == null || status.isBlank() ? List.of() : "pending".equalsIgnoreCase(status) ? List.of("ASSIGNED", "IN_REVIEW", "REOPENED") : "done".equalsIgnoreCase(status) ? List.of("SUBMITTED", "LOCKED") : List.of(status.toUpperCase().split(","));
        return reachParams(jdbc.sql(ASSIGNMENT_ROW + """
                 WHERE a.ended_at IS NULL AND (:s::text IS NULL OR p.session = :s) AND (:nst = 0 OR a.status = ANY(string_to_array(:st, ','))) AND (:e::uuid IS NULL OR a.examiner_id = :e)
                   AND (:dept::text IS NULL OR d.code = :dept) AND (:prog::text IS NULL OR pr.code = :prog) AND (NOT :ov OR extexam.overdue(a.status, a.deadline))
                   AND (:q::text IS NULL OR p.title ILIKE '%' || :q || '%' OR st.surname ILIKE '%' || :q || '%' OR st.matric_no ILIKE '%' || :q || '%' OR extexam.examiner_name(a.examiner_id) ILIKE '%' || :q || '%')
                """ + IN_REACH + " ORDER BY extexam.overdue(a.status, a.deadline) DESC, a.deadline LIMIT 500"))
                .param("s", session == null || session.isBlank() ? null : session, Types.VARCHAR).param("nst", statuses.size()).param("st", String.join(",", statuses)).param("e", examiner, Types.OTHER)
                .param("dept", dept == null || dept.isBlank() ? null : dept, Types.VARCHAR).param("prog", programme == null || programme.isBlank() ? null : programme, Types.VARCHAR).param("ov", Boolean.TRUE.equals(overdue))
                .param("q", q == null || q.isBlank() ? null : q.trim(), Types.VARCHAR).query().listOfRows();
    }

    /** the assignment with its assessment in full: the desk reads every score and comment */
    @GetMapping("/assignments/{id}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> assignment(@PathVariable UUID id) {
        requireAssignment(id);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql(ASSIGNMENT_ROW + " WHERE a.id = :id").param("id", id).query().singleRow());
        out.put("assessment", assessmentOf(id));
        out.put("documents", jdbc.sql("SELECT id, kind, filename, content_type, bytes, released, uploaded_at FROM extexam.project_document WHERE project_id = :p ORDER BY kind, uploaded_at").param("p", out.get("project_id")).query().listOfRows());
        out.put("history", jdbc.sql("SELECT at, actor_name, actor_office, action, from_value, to_value, reason FROM extexam.event WHERE assignment_id = :id ORDER BY at").param("id", id).query().listOfRows());
        return out;
    }

    /** the assessment as it stands, with the form's lines and the scores on each */
    private Map<String, Object> assessmentOf(UUID assignment) {
        Map<String, Object> a = jdbc.sql("""
                SELECT s.id, s.state, s.total, s.max_total, s.percentage, s.grade, s.general_comments, s.strengths, s.weaknesses, s.recommendations, s.corrections, s.final_recommendation,
                       s.version, s.started_at, s.saved_at, s.submitted_at, s.locked_at, s.reopened_at, s.reopen_reason
                  FROM extexam.assessment s WHERE s.assignment_id = :a
                """).param("a", assignment).query().listOfRows().stream().findFirst().orElse(null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("assessment", a);
        out.put("lines", jdbc.sql("""
                SELECT c.id AS criterion_id, c.section, c.name, c.guidance, c.max_score, c.ordinal, sc.score, sc.comment
                  FROM extexam.assignment g JOIN extexam.criterion c ON c.rubric_id = g.rubric_id AND c.active
                  LEFT JOIN extexam.assessment s ON s.assignment_id = g.id LEFT JOIN extexam.assessment_score sc ON sc.assessment_id = s.id AND sc.criterion_id = c.id
                 WHERE g.id = :a ORDER BY c.ordinal
                """).param("a", assignment).query().listOfRows());
        return out;
    }

    public record ReassignIn(@NotNull UUID examinerId, @NotBlank @Size(max = 2000) String reason, LocalDate deadline) {
    }

    @PostMapping("/assignments/{id}/reassign")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> reassign(Authentication auth, @PathVariable UUID id, @Valid @RequestBody ReassignIn body) {
        requireAssignment(id);
        Map<String, Object> old = jdbc.sql("SELECT project_id, examiner_id, rubric_id, deadline, exam_date, status, ended_at FROM extexam.assignment WHERE id = :id").param("id", id).query().singleRow();
        if (old.get("ended_at") != null) throw new DomainRuleViolation("ASSIGNMENT_ENDED", "This assignment has ended already.", new DomainRuleViolation.Remedy("Open the one that replaced it.", "Academic Office"));
        if ("LOCKED".equals(old.get("status"))) throw new DomainRuleViolation("ASSIGNMENT_LOCKED", "A locked assessment is not reassigned.", new DomainRuleViolation.Remedy("Reopen it first if the University wants it revised, or assign a second examiner.", "Academic Office"));
        if (!"ACTIVE".equals(jdbc.sql("SELECT status FROM extexam.examiner WHERE id = :id").param("id", body.examinerId()).query(String.class).optional().orElse(""))) {
            throw new DomainRuleViolation("EXAMINER_NOT_ACTIVE", "A project is reassigned to an examiner whose account is active.", new DomainRuleViolation.Remedy("Invite the examiner first.", "Academic Office"));
        }
        LocalDate deadline = body.deadline() != null ? body.deadline() : ((java.sql.Date) old.get("deadline")).toLocalDate();
        UUID fresh = doAssign(auth, (UUID) old.get("project_id"), body.examinerId(), null, (UUID) old.get("rubric_id"), deadline, old.get("exam_date") == null ? null : ((java.sql.Date) old.get("exam_date")).toLocalDate());
        jdbc.sql("UPDATE extexam.assignment SET status = 'REASSIGNED', ended_at = now(), ended_reason = :r, replaced_by = :n WHERE id = :id").param("id", id).param("r", body.reason().trim()).param("n", fresh).update();
        logEvent(auth, "PROJECT_REASSIGNED", (UUID) old.get("examiner_id"), (UUID) old.get("project_id"), id,
                jdbc.sql("SELECT extexam.examiner_name(:e)").param("e", old.get("examiner_id")).query(String.class).single(), jdbc.sql("SELECT extexam.examiner_name(:e)").param("e", body.examinerId()).query(String.class).single(), body.reason().trim());
        notifier.reassignedAway(id, body.reason().trim());
        notifier.assigned(fresh);
        return Map.of("id", fresh, "replaced", id);
    }

    public record DeadlineIn(@NotNull LocalDate deadline, @Size(max = 1000) String reason) {
    }

    @PostMapping("/assignments/{id}/deadline")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> deadline(Authentication auth, @PathVariable UUID id, @Valid @RequestBody DeadlineIn body) {
        requireAssignment(id);
        Map<String, Object> a = jdbc.sql("SELECT examiner_id, project_id, deadline, ended_at FROM extexam.assignment WHERE id = :id").param("id", id).query().singleRow();
        if (a.get("ended_at") != null) throw new DomainRuleViolation("ASSIGNMENT_ENDED", "This assignment has ended.", new DomainRuleViolation.Remedy("Open the one that replaced it.", "Academic Office"));
        LocalDate was = ((java.sql.Date) a.get("deadline")).toLocalDate();
        jdbc.sql("UPDATE extexam.assignment SET deadline = :d, reminded_at = CASE WHEN :d > deadline THEN NULL ELSE reminded_at END, overdue_told_at = CASE WHEN :d >= current_date THEN NULL ELSE overdue_told_at END WHERE id = :id")
                .param("id", id).param("d", body.deadline()).update();
        logEvent(auth, "DEADLINE_CHANGED", (UUID) a.get("examiner_id"), (UUID) a.get("project_id"), id, was.toString(), body.deadline().toString(), body.reason());
        notifier.deadlineChanged(id, was, body.reason());
        return Map.of("id", id, "deadline", body.deadline().toString());
    }

    @PostMapping("/assignments/{id}/withdraw")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> withdraw(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Reason body) {
        requireAssignment(id);
        if (body.reason() == null || body.reason().isBlank()) throw new DomainRuleViolation("ASSIGNMENT_REASON", "Withdrawing an assignment records the reason.", new DomainRuleViolation.Remedy("Say why, in a line.", "Academic Office"));
        Map<String, Object> a = jdbc.sql("SELECT examiner_id, project_id, status, ended_at FROM extexam.assignment WHERE id = :id").param("id", id).query().singleRow();
        if (a.get("ended_at") != null) throw new DomainRuleViolation("ASSIGNMENT_ENDED", "This assignment has ended already.", new DomainRuleViolation.Remedy("Nothing more to do.", "Academic Office"));
        if ("LOCKED".equals(a.get("status"))) throw new DomainRuleViolation("ASSIGNMENT_LOCKED", "A locked assessment is not withdrawn.", new DomainRuleViolation.Remedy("It stands as the record.", "Academic Office"));
        jdbc.sql("UPDATE extexam.assignment SET status = 'WITHDRAWN', ended_at = now(), ended_reason = :r WHERE id = :id").param("id", id).param("r", body.reason().trim()).update();
        logEvent(auth, "ASSIGNMENT_WITHDRAWN", (UUID) a.get("examiner_id"), (UUID) a.get("project_id"), id, (String) a.get("status"), "WITHDRAWN", body.reason().trim());
        notifier.withdrawn(id, body.reason().trim());
        return Map.of("id", id, "status", "WITHDRAWN");
    }

    /* ── the assessments: locked, reopened ── */

    @PostMapping("/assessments/{id}/lock")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> lock(Authentication auth, @PathVariable UUID id) {
        UUID assignment = assignmentOfAssessment(id);
        requireAssignment(assignment);
        jdbc.sql("SELECT extexam.lock(:a, :by, :n)").param("a", id).param("by", me(auth)).param("n", myName(auth)).query().singleRow();
        notifier.locked(assignment);
        return Map.of("id", id, "state", "LOCKED");
    }

    @PostMapping("/assessments/{id}/reopen")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> reopen(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Reason body) {
        UUID assignment = assignmentOfAssessment(id);
        requireAssignment(assignment);
        jdbc.sql("SELECT extexam.reopen(:a, :by, :n, :r)").param("a", id).param("by", me(auth)).param("n", myName(auth)).param("r", body.reason(), Types.VARCHAR).query().singleRow();
        notifier.reopened(assignment, body.reason() == null ? "" : body.reason().trim());
        return Map.of("id", id, "state", "REOPENED");
    }

    /* ── the reports, and the feed for moderation ── */

    @GetMapping("/reports")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> reports(@RequestParam(defaultValue = "assessments") String kind, @RequestParam(required = false) String session, @RequestParam(required = false) String faculty,
                                @RequestParam(required = false) String dept, @RequestParam(required = false) String programme, @RequestParam(required = false) UUID examiner,
                                @RequestParam(required = false) String status, @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to) {
        String where = """
                 WHERE a.ended_at IS NULL AND (:s::text IS NULL OR p.session = :s) AND (:fac::text IS NULL OR f.code = :fac) AND (:dept::text IS NULL OR d.code = :dept) AND (:prog::text IS NULL OR pr.code = :prog)
                   AND (:e::uuid IS NULL OR a.examiner_id = :e) AND (:st::text IS NULL OR a.status = :st) AND (:from::date IS NULL OR a.assigned_at >= :from) AND (:to::date IS NULL OR a.assigned_at < :to + 1)
                """ + IN_REACH;
        java.util.function.Function<String, JdbcClient.StatementSpec> with = sql -> reachParams(jdbc.sql(sql))
                .param("s", session == null || session.isBlank() ? null : session, Types.VARCHAR).param("fac", faculty == null || faculty.isBlank() ? null : faculty, Types.VARCHAR)
                .param("dept", dept == null || dept.isBlank() ? null : dept, Types.VARCHAR).param("prog", programme == null || programme.isBlank() ? null : programme, Types.VARCHAR)
                .param("e", examiner, Types.OTHER).param("st", status == null || status.isBlank() ? null : status.toUpperCase(), Types.VARCHAR).param("from", from, Types.DATE).param("to", to, Types.DATE);
        String base = "FROM extexam.assignment a JOIN extexam.examiner e ON e.id = a.examiner_id JOIN extexam.project p ON p.id = a.project_id JOIN people.student st ON st.id = p.student_id "
                + "JOIN ref.programme pr ON pr.code = st.programme_code JOIN ref.department d ON d.code = pr.dept_code JOIN ref.faculty f ON f.code = pr.faculty_code LEFT JOIN extexam.assessment s ON s.assignment_id = a.id" + where;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", kind);
        switch (kind) {
            case "examiners" -> out.put("rows", with.apply("""
                    SELECT extexam.examiner_name(e.id) AS examiner, e.institution, e.status, count(*) AS assigned, count(*) FILTER (WHERE a.status IN ('SUBMITTED','LOCKED')) AS submitted,
                           count(*) FILTER (WHERE a.status IN ('ASSIGNED','IN_REVIEW','REOPENED')) AS pending, count(*) FILTER (WHERE extexam.overdue(a.status, a.deadline)) AS overdue,
                           round(avg(EXTRACT(EPOCH FROM (s.submitted_at - a.assigned_at)) / 86400) FILTER (WHERE s.submitted_at IS NOT NULL)::numeric, 1) AS avg_days, round(avg(s.percentage)::numeric, 1) AS avg_percentage
                    """ + base + " GROUP BY e.id ORDER BY examiner").query().listOfRows());
            case "workload" -> out.put("rows", with.apply("""
                    SELECT extexam.examiner_name(e.id) AS examiner, e.institution, p.session, count(*) AS assigned, count(*) FILTER (WHERE a.status IN ('ASSIGNED','IN_REVIEW','REOPENED')) AS open,
                           count(*) FILTER (WHERE a.status IN ('SUBMITTED','LOCKED')) AS done, min(a.deadline) FILTER (WHERE a.status IN ('ASSIGNED','IN_REVIEW','REOPENED')) AS next_deadline
                    """ + base + " GROUP BY e.id, p.session ORDER BY assigned DESC").query().listOfRows());
            case "department" -> out.put("rows", with.apply("""
                    SELECT f.name AS faculty, d.name AS department, count(*) AS assigned, count(*) FILTER (WHERE a.status IN ('SUBMITTED','LOCKED')) AS submitted,
                           count(*) FILTER (WHERE a.status IN ('ASSIGNED','IN_REVIEW','REOPENED')) AS pending, count(*) FILTER (WHERE extexam.overdue(a.status, a.deadline)) AS overdue, round(avg(s.percentage)::numeric, 1) AS avg_percentage
                    """ + base + " GROUP BY f.name, d.name ORDER BY f.name, d.name").query().listOfRows());
            case "programme" -> out.put("rows", with.apply("""
                    SELECT d.name AS department, pr.name AS programme, count(*) AS assigned, count(*) FILTER (WHERE a.status IN ('SUBMITTED','LOCKED')) AS submitted,
                           count(*) FILTER (WHERE a.status IN ('ASSIGNED','IN_REVIEW','REOPENED')) AS pending, round(avg(s.percentage)::numeric, 1) AS avg_percentage,
                           count(*) FILTER (WHERE s.final_recommendation = 'PASS') AS pass, count(*) FILTER (WHERE s.final_recommendation = 'PASS_WITH_CORRECTIONS') AS pass_corrections,
                           count(*) FILTER (WHERE s.final_recommendation = 'REASSESSMENT') AS reassess, count(*) FILTER (WHERE s.final_recommendation = 'FAIL') AS fail
                    """ + base + " GROUP BY d.name, pr.name ORDER BY d.name, pr.name").query().listOfRows());
            case "pending", "overdue", "submitted", "assessments" -> out.put("rows", with.apply(ASSIGNMENT_ROW.replace("FROM extexam.assignment a JOIN extexam.examiner e", "FROM extexam.assignment a JOIN extexam.examiner e") + where
                    + (kind.equals("pending") ? " AND a.status IN ('ASSIGNED','IN_REVIEW','REOPENED')" : kind.equals("overdue") ? " AND extexam.overdue(a.status, a.deadline)" : kind.equals("submitted") ? " AND a.status IN ('SUBMITTED','LOCKED')" : "")
                    + " ORDER BY p.session DESC, d.name, st.surname LIMIT 2000").query().listOfRows());
            default -> throw new DomainRuleViolation("REPORT_KIND", "The report is one of: examiners, assessments, workload, department, programme, pending, overdue, submitted.", new DomainRuleViolation.Remedy("Choose one.", "Academic Office"));
        }
        return out;
    }

    /** what moderation reads: every submitted or locked external assessment in a department for a session, beside the internal course result where one is recorded */
    @GetMapping("/moderation")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> moderation(@RequestParam String session, @RequestParam(required = false) String dept) {
        return reachParams(jdbc.sql("""
                SELECT p.id AS project_id, p.title, p.kind, p.course_code, st.surname || ', ' || st.other_names AS student, coalesce(st.matric_no, st.admission_no) AS number, pr.name AS programme, d.name AS department,
                       coalesce((SELECT sp.surname || ', ' || sp.given_names FROM iam.person sp WHERE sp.id = p.supervisor_id), p.supervisor_name) AS supervisor,
                       (SELECT jsonb_agg(jsonb_build_object('examiner', extexam.examiner_name(a.examiner_id), 'total', s.total, 'max', s.max_total, 'percentage', s.percentage, 'grade', s.grade, 'recommendation', s.final_recommendation, 'state', s.state, 'submitted_at', s.submitted_at) ORDER BY s.submitted_at)
                          FROM extexam.assignment a JOIN extexam.assessment s ON s.assignment_id = a.id WHERE a.project_id = p.id AND a.ended_at IS NULL AND s.state IN ('SUBMITTED','LOCKED'))::text AS external,
                       (SELECT round(avg(s.percentage), 1) FROM extexam.assignment a JOIN extexam.assessment s ON s.assignment_id = a.id WHERE a.project_id = p.id AND a.ended_at IS NULL AND s.state IN ('SUBMITTED','LOCKED')) AS external_avg,
                       (SELECT sc.ca + sc.exam FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id JOIN catalogue.offering o ON o.id = sh.offering_id
                         WHERE p.course_code IS NOT NULL AND o.course_code = p.course_code AND sc.student_id = st.id AND o.session = p.session AND sc.outcome = 'GRADED' ORDER BY sc.version DESC LIMIT 1) AS internal_total
                  FROM extexam.project p JOIN people.student st ON st.id = p.student_id JOIN ref.programme pr ON pr.code = st.programme_code JOIN ref.department d ON d.code = pr.dept_code JOIN ref.faculty f ON f.code = pr.faculty_code
                 WHERE p.session = :s AND (:dept::text IS NULL OR d.code = :dept)
                """ + IN_REACH + " ORDER BY d.name, st.surname")).param("s", session).param("dept", dept == null || dept.isBlank() ? null : dept, Types.VARCHAR).query().listOfRows();
    }

    /* ══════════════════════════════ the examiner ══════════════════════════════ */

    @GetMapping("/me")
    @PreAuthorize(EXAMINER)
    @Transactional(readOnly = true)
    Map<String, Object> myWorkspace(Authentication auth) {
        UUID ex = examinerOf(auth);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql(EXAMINER_ROW + " WHERE e.id = :id").param("id", ex).query().singleRow());
        out.remove("notes");
        out.put("appointments", jdbc.sql("""
                SELECT ap.id, ap.session, ap.semester, f.name AS faculty, d.name AS department, pr.name AS programme, ap.period, ap.starts_on, ap.ends_on, ap.status
                  FROM extexam.appointment ap JOIN ref.faculty f ON f.code = ap.faculty_code JOIN ref.department d ON d.code = ap.dept_code LEFT JOIN ref.programme pr ON pr.code = ap.programme_code
                 WHERE ap.examiner_id = :id AND ap.status = 'ACTIVE' ORDER BY ap.starts_on DESC
                """).param("id", ex).query().listOfRows());
        out.put("counts", jdbc.sql("""
                SELECT count(*) AS assigned, count(*) FILTER (WHERE status = 'ASSIGNED') AS not_started, count(*) FILTER (WHERE status IN ('IN_REVIEW','REOPENED')) AS in_review,
                       count(*) FILTER (WHERE status IN ('ASSIGNED','IN_REVIEW','REOPENED')) AS pending, count(*) FILTER (WHERE status IN ('SUBMITTED','LOCKED')) AS submitted,
                       count(*) FILTER (WHERE extexam.overdue(status, deadline)) AS overdue
                  FROM extexam.assignment WHERE examiner_id = :id AND ended_at IS NULL
                """).param("id", ex).query().singleRow());
        out.put("recent", jdbc.sql(MY_ROW + " WHERE a.examiner_id = :id AND a.ended_at IS NULL ORDER BY a.assigned_at DESC LIMIT 5").param("id", ex).query().listOfRows());
        out.put("upcoming", jdbc.sql(MY_ROW + " WHERE a.examiner_id = :id AND a.ended_at IS NULL AND a.status IN ('ASSIGNED','IN_REVIEW','REOPENED') ORDER BY a.deadline LIMIT 5").param("id", ex).query().listOfRows());
        out.put("submitted", jdbc.sql(MY_ROW + " WHERE a.examiner_id = :id AND a.ended_at IS NULL AND a.status IN ('SUBMITTED','LOCKED') ORDER BY s.submitted_at DESC LIMIT 5").param("id", ex).query().listOfRows());
        return out;
    }

    /** the examiner's own view of an assignment: the project and the student as a candidate, never the internal side */
    private static final String MY_ROW = """
            SELECT a.id, a.project_id, a.deadline, a.exam_date, a.status, a.assigned_at, a.first_viewed_at, extexam.overdue(a.status, a.deadline) AS overdue, (a.deadline - current_date) AS days_left,
                   p.title, p.kind, p.session, p.submitted_on, p.project_type, st.surname || ', ' || st.other_names AS student, coalesce(st.matric_no, st.admission_no) AS number,
                   pr.name AS programme, d.name AS department, f.name AS faculty,
                   coalesce((SELECT sp.surname || ', ' || sp.given_names FROM iam.person sp WHERE sp.id = p.supervisor_id), p.supervisor_name) AS supervisor, p.co_supervisor,
                   (SELECT count(*) FROM extexam.project_document pd WHERE pd.project_id = p.id AND pd.released) AS documents,
                   s.id AS assessment_id, s.state AS assessment_state, s.total, s.max_total, s.percentage, s.grade, s.final_recommendation, s.submitted_at, s.saved_at
              FROM extexam.assignment a JOIN extexam.project p ON p.id = a.project_id JOIN people.student st ON st.id = p.student_id JOIN ref.programme pr ON pr.code = st.programme_code
              JOIN ref.department d ON d.code = pr.dept_code JOIN ref.faculty f ON f.code = pr.faculty_code LEFT JOIN extexam.assessment s ON s.assignment_id = a.id
            """;

    public record ProfileIn(@Size(max = 40) String phone, @Size(max = 200) String department, @Size(max = 120) String rank, @Size(max = 300) String specialization, @Size(max = 200) String qualification,
                            @Size(max = 300) String professional, @Min(0) @Max(70) Integer experienceYears, @Size(max = 80) String country, @Size(max = 80) String region, @Size(max = 40) String orcid) {
    }

    @PutMapping("/me/profile")
    @PreAuthorize(EXAMINER)
    @Transactional
    Map<String, Object> profile(Authentication auth, @Valid @RequestBody ProfileIn body) {
        UUID ex = examinerOf(auth);
        jdbc.sql("""
                UPDATE extexam.examiner SET phone = :ph, department = :d, rank = :r, specialization = :sp, qualification = :q, professional = :pr, experience_years = :y, country = :c, region = :rg, orcid = :o WHERE id = :id
                """).param("id", ex).param("ph", body.phone(), Types.VARCHAR).param("d", body.department(), Types.VARCHAR).param("r", body.rank(), Types.VARCHAR).param("sp", body.specialization(), Types.VARCHAR)
                .param("q", body.qualification(), Types.VARCHAR).param("pr", body.professional(), Types.VARCHAR).param("y", body.experienceYears(), Types.INTEGER).param("c", body.country(), Types.VARCHAR)
                .param("rg", body.region(), Types.VARCHAR).param("o", body.orcid(), Types.VARCHAR).update();
        jdbc.sql("UPDATE iam.person SET phone = :ph WHERE id = :p").param("ph", body.phone(), Types.VARCHAR).param("p", me(auth)).update();
        logEvent(auth, "EXAMINER_EDITED", ex, null, null, null, "by the examiner", null);
        return Map.of("id", ex);
    }

    @GetMapping("/me/projects")
    @PreAuthorize(EXAMINER)
    @Transactional(readOnly = true)
    List<Map<String, Object>> myProjects(Authentication auth, @RequestParam(required = false) String filter) {
        UUID ex = examinerOf(auth);
        String f = "pending".equalsIgnoreCase(filter) ? " AND a.status IN ('ASSIGNED','IN_REVIEW','REOPENED')" : "submitted".equalsIgnoreCase(filter) ? " AND a.status IN ('SUBMITTED','LOCKED')" : "";
        return jdbc.sql(MY_ROW + " WHERE a.examiner_id = :id AND a.ended_at IS NULL" + f + " ORDER BY (a.status IN ('SUBMITTED','LOCKED')), a.deadline").param("id", ex).query().listOfRows();
    }

    /** the project opened: its details, the documents released, the examiner's own assessment; the first opening is recorded */
    @GetMapping("/me/projects/{id}")
    @PreAuthorize(EXAMINER)
    @Transactional
    Map<String, Object> myProject(Authentication auth, @PathVariable UUID id) {
        UUID ex = examinerOf(auth);
        Map<String, Object> a = myAssignment(ex, id);
        if (a.get("first_viewed_at") == null) {
            jdbc.sql("UPDATE extexam.assignment SET first_viewed_at = now() WHERE id = :id").param("id", id).update();
            logEvent(auth, "PROJECT_VIEWED", ex, (UUID) a.get("project_id"), id, null, null, null);
        }
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql(MY_ROW + " WHERE a.id = :id").param("id", id).query().singleRow());
        Map<String, Object> project = jdbc.sql("SELECT abstract, keywords FROM extexam.project WHERE id = :p").param("p", a.get("project_id")).query().singleRow();
        out.put("abstract", project.get("abstract"));
        out.put("keywords", project.get("keywords"));
        out.put("documents", jdbc.sql("SELECT id, kind, filename, content_type, bytes, uploaded_at FROM extexam.project_document WHERE project_id = :p AND released ORDER BY kind, uploaded_at").param("p", a.get("project_id")).query().listOfRows());
        out.put("rubric", jdbc.sql("SELECT r.id, r.name, r.kind, r.has_defence, r.note FROM extexam.rubric r WHERE r.id = :r").param("r", a.get("rubric_id")).query().singleRow());
        out.putAll(assessmentOf(id));
        out.put("history", jdbc.sql("SELECT at, action, from_value, to_value, reason FROM extexam.event WHERE assignment_id = :id AND action IN ('PROJECT_ASSIGNED','DEADLINE_CHANGED','ASSESSMENT_STARTED','ASSESSMENT_SUBMITTED','ASSESSMENT_REOPENED','ASSESSMENT_RESUBMITTED','ASSESSMENT_LOCKED') ORDER BY at").param("id", id).query().listOfRows());
        return out;
    }

    @GetMapping("/me/projects/{id}/documents/{doc}/content")
    @PreAuthorize(EXAMINER)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> myDocument(Authentication auth, @PathVariable UUID id, @PathVariable UUID doc) {
        UUID ex = examinerOf(auth);
        Map<String, Object> a = myAssignment(ex, id);
        return serve(document((UUID) a.get("project_id"), doc, true));
    }

    @PostMapping("/me/projects/{id}/assessment/start")
    @PreAuthorize(EXAMINER)
    @Transactional
    Map<String, Object> start(Authentication auth, @PathVariable UUID id) {
        UUID ex = examinerOf(auth);
        Map<String, Object> a = myAssignment(ex, id);
        UUID assessment = ensureAssessment(auth, ex, a);
        return Map.of("id", assessment, "state", jdbc.sql("SELECT state FROM extexam.assessment WHERE id = :id").param("id", assessment).query(String.class).single());
    }

    private UUID ensureAssessment(Authentication auth, UUID ex, Map<String, Object> a) {
        UUID existing = jdbc.sql("SELECT id FROM extexam.assessment WHERE assignment_id = :a").param("a", a.get("id")).query(UUID.class).optional().orElse(null);
        if (existing != null) return existing;
        UUID id = jdbc.sql("INSERT INTO extexam.assessment (assignment_id) VALUES (:a) RETURNING id").param("a", a.get("id")).query(UUID.class).single();
        jdbc.sql("UPDATE extexam.assignment SET status = 'IN_REVIEW' WHERE id = :id AND status = 'ASSIGNED'").param("id", a.get("id")).update();
        logEvent(auth, "ASSESSMENT_STARTED", ex, (UUID) a.get("project_id"), (UUID) a.get("id"), "ASSIGNED", "IN_REVIEW", null);
        return id;
    }

    public record ScoreIn(@NotNull UUID criterionId, java.math.BigDecimal score, @Size(max = 2000) String comment) {
    }

    public record DraftIn(List<@Valid ScoreIn> scores, @Size(max = 8000) String generalComments, @Size(max = 4000) String strengths, @Size(max = 4000) String weaknesses,
                          @Size(max = 4000) String recommendations, @Size(max = 4000) String corrections, String finalRecommendation) {
    }

    /** the draft saved: the scores each checked against their maximum, the comments, the recommendation; the total computed */
    @PutMapping("/me/projects/{id}/assessment")
    @PreAuthorize(EXAMINER)
    @Transactional
    Map<String, Object> save(Authentication auth, @PathVariable UUID id, @Valid @RequestBody DraftIn body) {
        UUID ex = examinerOf(auth);
        Map<String, Object> a = myAssignment(ex, id);
        UUID assessment = ensureAssessment(auth, ex, a);
        String state = jdbc.sql("SELECT state FROM extexam.assessment WHERE id = :id").param("id", assessment).query(String.class).single();
        if ("SUBMITTED".equals(state) || "LOCKED".equals(state)) {
            throw new DomainRuleViolation("ASSESSMENT_READ_ONLY", "A submitted assessment is read-only.", new DomainRuleViolation.Remedy("Ask the Academic Office to reopen it if a correction is needed.", "Academic Office"));
        }
        String rec = body.finalRecommendation() == null || body.finalRecommendation().isBlank() ? null : body.finalRecommendation().trim().toUpperCase();
        if (rec != null && !RECOMMENDATIONS.contains(rec)) throw new DomainRuleViolation("ASSESSMENT_RECOMMENDATION", "The recommendation is pass, pass subject to corrections, reassessment required, or fail.", new DomainRuleViolation.Remedy("Choose one.", "Academic Office"));
        if (body.scores() != null) {
            for (ScoreIn s : body.scores()) {
                jdbc.sql("SELECT extexam.score(:a, :c, :s, :m)").param("a", assessment).param("c", s.criterionId()).param("s", s.score(), Types.NUMERIC).param("m", s.comment(), Types.VARCHAR).query().singleRow();
            }
        }
        jdbc.sql("""
                UPDATE extexam.assessment SET general_comments = :g, strengths = :s, weaknesses = :w, recommendations = :r, corrections = :c, final_recommendation = :f WHERE id = :id
                """).param("id", assessment).param("g", body.generalComments(), Types.VARCHAR).param("s", body.strengths(), Types.VARCHAR).param("w", body.weaknesses(), Types.VARCHAR)
                .param("r", body.recommendations(), Types.VARCHAR).param("c", body.corrections(), Types.VARCHAR).param("f", rec, Types.VARCHAR).update();
        jdbc.sql("SELECT extexam.compute(:a)").param("a", assessment).query().singleRow();
        logEvent(auth, "ASSESSMENT_SAVED", ex, (UUID) a.get("project_id"), id, null, null, null);
        return assessmentOf(id);
    }

    @PostMapping("/me/projects/{id}/assessment/submit")
    @PreAuthorize(EXAMINER)
    @Transactional
    Map<String, Object> submit(Authentication auth, @PathVariable UUID id) {
        UUID ex = examinerOf(auth);
        Map<String, Object> a = myAssignment(ex, id);
        UUID assessment = ensureAssessment(auth, ex, a);
        boolean again = "REOPENED".equals(jdbc.sql("SELECT state FROM extexam.assessment WHERE id = :id").param("id", assessment).query(String.class).single());
        jdbc.sql("SELECT extexam.submit(:a, :by, :n)").param("a", assessment).param("by", me(auth)).param("n", jdbc.sql("SELECT extexam.examiner_name(:e)").param("e", ex).query(String.class).single()).query().singleRow();
        notifier.submitted(id, again);
        return assessmentOf(id);
    }

    /* ══════════════════════════════ the public activation ══════════════════════════════ */

    /** who the link invites, before anything is typed */
    @GetMapping("/invitation/{token}")
    @Transactional(readOnly = true)
    Map<String, Object> invitation(@PathVariable String token) {
        Map<String, Object> r = jdbc.sql("""
                SELECT extexam.examiner_name(e.id) AS name, e.institution, e.email, e.status, i.expires_at,
                       (SELECT string_agg(d.name || ' (' || ap.session || ')', '; ' ORDER BY ap.starts_on DESC) FROM extexam.appointment ap JOIN ref.department d ON d.code = ap.dept_code WHERE ap.examiner_id = e.id AND ap.status = 'ACTIVE') AS appointment
                  FROM extexam.invitation i JOIN extexam.examiner e ON e.id = i.examiner_id
                 WHERE i.token_hash = :h AND i.used_at IS NULL AND i.expires_at > now()
                """).param("h", sha256(token.trim())).query().listOfRows().stream().findFirst().orElseThrow(ExaminersController::badLink);
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("university", ExaminerNotifier.UNIVERSITY);
        return out;
    }

    public record ActivateIn(@NotBlank String token, @NotBlank @Size(min = 10, max = 200) String password) {
    }

    /** the account made live: the password set, the office granted, the examiner active; the desk told */
    @PostMapping("/activate")
    Map<String, Object> activate(@Valid @RequestBody ActivateIn body) {
        Map<String, Object> r = jdbc.sql("""
                SELECT i.id AS invitation_id, i.sent_by, e.id AS examiner_id, e.person_id, e.email, e.status
                  FROM extexam.invitation i JOIN extexam.examiner e ON e.id = i.examiner_id
                 WHERE i.token_hash = :h AND i.used_at IS NULL AND i.expires_at > now()
                """).param("h", sha256(body.token().trim())).query().listOfRows().stream().findFirst().orElseThrow(ExaminersController::badLink);
        if ("SUSPENDED".equals(r.get("status")) || "INACTIVE".equals(r.get("status"))) throw badLink();
        String email = (String) r.get("email");
        String pw = body.password();
        if (pw.toLowerCase().contains(email.toLowerCase()) || pw.trim().length() < 10) {
            throw new DomainRuleViolation("AUTH_WEAK_PASSWORD", "A password is at least ten characters and does not contain your email address.", new DomainRuleViolation.Remedy("Choose a longer password.", "You"));
        }
        UUID person = (UUID) r.get("person_id");
        UUID examiner = (UUID) r.get("examiner_id");
        UUID sentBy = (UUID) r.get("sent_by");
        String hash = encoder.encode(pw);
        AuditContextHolder.with(new AuditContext(person, "academic", "external examiner account activated", null, null), () -> tx.execute(st -> {
            Long taken = jdbc.sql("SELECT count(*) FROM iam.credential WHERE username = :u AND person_id <> :p").param("u", email).param("p", person).query(Long.class).single();
            if (taken > 0) throw new DomainRuleViolation("EXAMINER_USERNAME_TAKEN", "That email address is already a username on the portal.", new DomainRuleViolation.Remedy("Write to the Academic Office to have your record corrected.", "Academic Office"));
            int n = jdbc.sql("UPDATE iam.credential SET username = :u, password_hash = :h, must_change = false, failed_attempts = 0, locked_until = NULL, set_at = now(), set_by = :p WHERE person_id = :p")
                    .param("u", email).param("h", hash).param("p", person).update();
            if (n == 0) jdbc.sql("INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by) VALUES (:p, :u, :h, false, :p)").param("p", person).param("u", email).param("h", hash).update();
            jdbc.sql("INSERT INTO iam.credential_event (id, person_id, kind, by_person, note) VALUES (gen_random_uuid(), :p, :k, :p, 'External examiner activation (V254)')").param("p", person).param("k", n == 0 ? "SET" : "RESET").update();
            grantOffice(person, sentBy == null ? NOBODY : sentBy);
            jdbc.sql("UPDATE extexam.examiner SET status = 'ACTIVE', activated_at = coalesce(activated_at, now()) WHERE id = :id").param("id", examiner).update();
            jdbc.sql("UPDATE extexam.invitation SET used_at = now() WHERE id = :id").param("id", r.get("invitation_id")).update();
            jdbc.sql("SELECT extexam.record('ACCOUNT_ACTIVATED', :p, :n, :e, NULL, NULL, :from, 'ACTIVE', NULL)").param("p", person).param("n", jdbc.sql("SELECT extexam.examiner_name(:e)").param("e", examiner).query(String.class).single())
                    .param("e", examiner).param("from", r.get("status")).query().singleRow();
            notifier.activated(examiner, sentBy);
            return null;
        }));
        return Map.of("activated", true, "username", email);
    }

    private static DomainRuleViolation badLink() {
        return new DomainRuleViolation("EXAMINER_INVITE_TOKEN", "This invitation link has expired or was already used.", new DomainRuleViolation.Remedy("Ask the Academic Office to resend the invitation; each link is good for fourteen days and works once.", "Academic Office"));
    }

    /* ══════════════════════════════ helpers ══════════════════════════════ */

    private void logEvent(Authentication auth, String action, UUID examiner, UUID project, UUID assignment, String from, String to, String reason) {
        jdbc.sql("SELECT extexam.record(:a, :p, :n, :e, :pr, :as, :f, :t, :r)").param("a", action).param("p", me(auth)).param("n", myName(auth)).param("e", examiner, Types.OTHER)
                .param("pr", project, Types.OTHER).param("as", assignment, Types.OTHER).param("f", from, Types.VARCHAR).param("t", to, Types.VARCHAR).param("r", reason, Types.VARCHAR).query().singleRow();
    }

    private static String sha256(String s) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String normalType(String t) {
        String type = t.trim().toLowerCase();
        return "image/jpg".equals(type) ? "image/jpeg" : type;
    }

    private static String safeName(String name) {
        return name.trim().replaceAll("[\\\\/\\r\\n\\t]", "_");
    }

    /** the bytes decoded, sized, and sniffed: a PDF begins %PDF-, an image with its signature, a Word, PowerPoint or ZIP file with PK */
    private static byte[] decoded(Upload body, Set<String> allowed, long max) {
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(body.contentBase64());
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("EXAMINER_FILE_BAD", "The file could not be read.", new DomainRuleViolation.Remedy("Attach it again.", "Academic Office"));
        }
        if (bytes.length == 0 || bytes.length > max) {
            throw new DomainRuleViolation("EXAMINER_FILE_SIZE", "A file is between 1 byte and " + (max / (1024 * 1024)) + " MB.", new DomainRuleViolation.Remedy("Attach a smaller file.", "Academic Office"));
        }
        String type = normalType(body.contentType());
        String seen = sniff(bytes);
        boolean ok = allowed.contains(type) && (("application/pdf".equals(type) && "pdf".equals(seen)) || ("image/png".equals(type) && "png".equals(seen)) || ("image/jpeg".equals(type) && "jpeg".equals(seen))
                || (!"application/pdf".equals(type) && !type.startsWith("image/") && "zip".equals(seen)));
        if (!ok) {
            throw new DomainRuleViolation("EXAMINER_FILE_TYPE", "The file is not of a kind accepted here, or its contents are not what its name says.", new DomainRuleViolation.Remedy("Attach a PDF, a Word or PowerPoint file, or a ZIP, as the field says.", "Academic Office"));
        }
        return bytes;
    }

    private static String sniff(byte[] b) {
        if (b.length >= 5 && b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F' && b[4] == '-') return "pdf";
        if (b.length >= 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') return "png";
        if (b.length >= 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF) return "jpeg";
        if (b.length >= 4 && b[0] == 'P' && b[1] == 'K' && (b[2] == 3 || b[2] == 5 || b[2] == 7)) return "zip";
        return "unknown";
    }

    private static ResponseEntity<byte[]> serve(Map<String, Object> r) {
        String type = (String) r.get("content_type");
        boolean inline = "application/pdf".equals(type) || type.startsWith("image/");
        ContentDisposition cd = (inline ? ContentDisposition.inline() : ContentDisposition.attachment()).filename(String.valueOf(r.get("filename")), StandardCharsets.UTF_8).build();
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(type)).cacheControl(CacheControl.noStore())
                .header("Content-Disposition", cd.toString()).header("X-Content-Type-Options", "nosniff").header("Content-Security-Policy", "sandbox")
                .body((byte[]) r.get("content"));
    }
}
