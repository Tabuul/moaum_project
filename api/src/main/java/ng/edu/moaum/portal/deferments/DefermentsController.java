package ng.edu.moaum.portal.deferments;

import java.nio.charset.StandardCharsets;
import java.sql.Types;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Deferment (V259): a student asks to defer a semester or a session; the department recommends, the faculty
 * recommends, the Registry approves; the period is held on every register; the return is confirmed. The student
 * reaches only their own requests (/api/v1/me/deferments); a desk reaches those within its bound — a Head their
 * department, a Dean their faculty, the Postgraduate School its students, the College its own, the Registry all —
 * and each acts only at its own stage. The rules are in the database; this is the door to them.
 */
@RestController
class DefermentsController {

    private static final String STUDENT = "hasAuthority('OFFICE_student')";
    private static final String DESK = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_facultyofficer','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_records','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_provost','OFFICE_collegesecretary','OFFICE_super','OFFICE_admin')";
    private static final Set<String> REGISTRY = Set.of("academic", "registrar", "dregistrar", "super");
    private static final Set<String> ALL_SEEING = Set.of("academic", "registrar", "dregistrar", "records", "super", "admin");
    private static final Set<String> DOC_TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    private static final Set<String> DOC_KINDS = Set.of("MEDICAL", "FINANCIAL", "OFFICIAL_LETTER", "EMPLOYER_LETTER", "OTHER");
    private static final long DOC_MAX = 5L * 1024 * 1024;

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    DefermentsController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /* ── the shared read: one request with everything on it ─────────────── */

    private static final String ONE = """
            SELECT d.*, r.label AS reason, r.needs_document, r.needs_words,
                   s.surname, s.other_names, coalesce(s.matric_no, s.admission_no) AS number, s.current_level AS level, s.status AS student_status, s.entry_mode,
                   p.code AS programme_code, p.name AS programme, dp.code AS dept_code, dp.name AS department, f.code AS faculty_code, f.name AS faculty, f.college_code,
                   people.deferment_return_status(d.state, d.return_on) AS return_status,
                   CASE WHEN db.id IS NULL THEN NULL ELSE db.surname || ', ' || db.given_names END AS dept_officer,
                   CASE WHEN fb.id IS NULL THEN NULL ELSE fb.surname || ', ' || fb.given_names END AS faculty_officer,
                   CASE WHEN ab.id IS NULL THEN NULL ELSE ab.surname || ', ' || ab.given_names END AS decided_officer,
                   CASE WHEN rb.id IS NULL THEN NULL ELSE rb.surname || ', ' || rb.given_names END AS returned_officer
              FROM people.deferment d
              JOIN people.deferment_reason r ON r.code = d.reason_code
              JOIN people.student s ON s.id = d.student_id
              JOIN ref.programme p ON p.code = s.programme_code
              JOIN ref.department dp ON dp.code = p.dept_code
              JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN iam.person db ON db.id = d.dept_by
              LEFT JOIN iam.person fb ON fb.id = d.fac_by
              LEFT JOIN iam.person ab ON ab.id = d.decided_by
              LEFT JOIN iam.person rb ON rb.id = d.returned_by
            """;

    private Map<String, Object> one(UUID id) {
        return jdbc.sql(ONE + " WHERE d.id = :id").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("deferment", id));
    }

    private Map<String, Object> full(UUID id) {
        Map<String, Object> d = new LinkedHashMap<>(one(id));
        d.put("documents", jdbc.sql("""
                SELECT id, kind, filename, content_type, size_bytes, uploaded_at, verified_at FROM people.deferment_document WHERE deferment_id = :id ORDER BY uploaded_at
                """).param("id", id).query().listOfRows());
        d.put("history", jdbc.sql("""
                SELECT e.action, e.from_state, e.to_state, e.actor_office, e.note, e.at,
                       CASE WHEN x.id IS NULL THEN NULL ELSE x.surname || ', ' || x.given_names END AS actor
                  FROM people.deferment_event e LEFT JOIN iam.person x ON x.id = e.actor_id WHERE e.deferment_id = :id ORDER BY e.at
                """).param("id", id).query().listOfRows());
        return d;
    }

    /* ── the student's own ───────────────────────────────────────────────── */

    private static UUID me(Authentication a) {
        return UUID.fromString(a.getName());
    }

    @GetMapping("/api/v1/me/deferments")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication a) {
        UUID s = me(a);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("eligibility", jdbc.sql("SELECT * FROM people.deferment_eligibility(:s)").param("s", s).query().singleRow());
        out.put("requests", jdbc.sql(ONE + " WHERE d.student_id = :s ORDER BY d.created_at DESC").param("s", s).query().listOfRows());
        out.put("reasons", jdbc.sql("SELECT code, label, needs_document, needs_words FROM people.deferment_reason WHERE active ORDER BY ord").query().listOfRows());
        out.put("sessions", jdbc.sql("SELECT name, semesters, state FROM policy.academic_session WHERE state IN ('CURRENT','PLANNED') ORDER BY name").query().listOfRows());
        out.put("current", jdbc.sql("""
                SELECT a.name AS session, (SELECT max(number) FROM policy.semester sm WHERE sm.session = a.name AND sm.state = 'OPEN') AS semester
                  FROM policy.academic_session a WHERE a.state = 'CURRENT'
                """).query().listOfRows().stream().findFirst().orElse(Map.of()));
        out.put("setting", jdbc.sql("SELECT max_sessions, allow_extension FROM people.deferment_setting WHERE id = 1").query().singleRow());
        return out;
    }

    public record RequestIn(@NotBlank String kind, @NotBlank String session, Integer semester, @NotBlank String reason,
                            @Size(max = 3000) String explanation, Boolean declared, UUID extensionOf) {
    }

    @PostMapping("/api/v1/me/deferments")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> open(Authentication a, @Valid @RequestBody RequestIn body) {
        UUID id = jdbc.sql("SELECT people.deferment_save(:s, NULL, :k, :ses, :sem, :r, :x, :d, :ext)")
                .param("s", me(a)).param("k", body.kind().trim().toUpperCase()).param("ses", body.session().trim()).param("sem", body.semester(), Types.INTEGER)
                .param("r", body.reason().trim().toUpperCase()).param("x", body.explanation(), Types.VARCHAR).param("d", Boolean.TRUE.equals(body.declared()))
                .param("ext", body.extensionOf(), Types.OTHER).query(UUID.class).single();
        return full(id);
    }

    @PutMapping("/api/v1/me/deferments/{id}")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> change(Authentication a, @PathVariable UUID id, @Valid @RequestBody RequestIn body) {
        jdbc.sql("SELECT people.deferment_save(:s, :id, :k, :ses, :sem, :r, :x, :d, NULL)")
                .param("s", me(a)).param("id", id).param("k", body.kind().trim().toUpperCase()).param("ses", body.session().trim()).param("sem", body.semester(), Types.INTEGER)
                .param("r", body.reason().trim().toUpperCase()).param("x", body.explanation(), Types.VARCHAR).param("d", Boolean.TRUE.equals(body.declared()))
                .query(UUID.class).single();
        return full(id);
    }

    @GetMapping("/api/v1/me/deferments/{id}")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> myOne(Authentication a, @PathVariable UUID id) {
        return full(owned(me(a), id));
    }

    @PostMapping("/api/v1/me/deferments/{id}/submit")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> submit(Authentication a, @PathVariable UUID id) {
        jdbc.sql("SELECT people.deferment_submit(:s, :id)").param("s", me(a)).param("id", id).query(String.class).single();
        return full(id);
    }

    public record NoteIn(@Size(max = 2000) String note) {
    }

    @PostMapping("/api/v1/me/deferments/{id}/cancel")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> myCancel(Authentication a, @PathVariable UUID id, @RequestBody(required = false) NoteIn body) {
        owned(me(a), id);
        jdbc.sql("SELECT people.deferment_decide(:id, 'CANCEL', :n, NULL, 'student')").param("id", id)
                .param("n", body == null || body.note() == null || body.note().isBlank() ? "Withdrawn by the student" : body.note().trim()).query(String.class).single();
        return full(id);
    }

    public record DocumentIn(@NotBlank String kind, @NotBlank @Size(max = 200) String filename, @NotBlank String contentType, @NotBlank @Size(max = 7_200_000) String contentBase64) {
    }

    @PostMapping("/api/v1/me/deferments/{id}/documents")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> upload(Authentication a, @PathVariable UUID id, @Valid @RequestBody DocumentIn body) {
        UUID s = me(a);
        Map<String, Object> d = one(owned(s, id));
        if (!Set.of("DRAFT", "CORRECTION_REQUIRED", "SUBMITTED").contains(String.valueOf(d.get("state")))) {
            throw new DomainRuleViolation("DEF_DOC_CLOSED", "Documents are added while the request is yours to change or awaiting the department.",
                    new DomainRuleViolation.Remedy("Write to the Registry if a document must be added later.", "Registry"));
        }
        String kind = body.kind().trim().toUpperCase();
        if (!DOC_KINDS.contains(kind)) throw new DomainRuleViolation("DEF_DOC_KIND", "'" + kind + "' is not a kind of supporting document.", new DomainRuleViolation.Remedy("Medical, financial, official letter, employer letter or other.", "You"));
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(body.contentBase64());
        } catch (IllegalArgumentException e) {
            throw new DomainRuleViolation("DEF_DOC_BAD", "The file could not be read.", new DomainRuleViolation.Remedy("Attach it again.", "You"));
        }
        String type = body.contentType().trim().toLowerCase().replace("image/jpg", "image/jpeg");
        if (bytes.length == 0 || bytes.length > DOC_MAX) throw new DomainRuleViolation("DEF_DOC_SIZE", "A supporting document is at most 5 MB.", new DomainRuleViolation.Remedy("Attach a smaller scan.", "You"));
        if (!DOC_TYPES.contains(type) || !sniff(bytes).equals(type)) throw new DomainRuleViolation("DEF_DOC_TYPE", "A supporting document is a PDF, JPEG or PNG, and its contents must be what its name says.", new DomainRuleViolation.Remedy("Attach the PDF or image.", "You"));
        long n = jdbc.sql("SELECT count(*) FROM people.deferment_document WHERE deferment_id = :id").param("id", id).query(Long.class).single();
        if (n >= 6) throw new DomainRuleViolation("DEF_DOC_MANY", "At most six documents support a request.", new DomainRuleViolation.Remedy("Combine them into one PDF.", "You"));
        UUID doc = UUID.randomUUID();
        jdbc.sql("INSERT INTO people.deferment_document (id, deferment_id, kind, filename, content_type, size_bytes, uploaded_by) VALUES (:d, :id, :k, :f, :t, :n, :s)")
                .param("d", doc).param("id", id).param("k", kind).param("f", body.filename().trim().replaceAll("[\\\\/\\r\\n\\t]", "_")).param("t", type).param("n", bytes.length).param("s", s).update();
        jdbc.sql("INSERT INTO people.deferment_document_blob (document_id, bytes) VALUES (:d, :b)").param("d", doc).param("b", bytes).update();
        jdbc.sql("SELECT people.deferment_log(:id, 'DOCUMENT', :st, :st, :n)").param("id", id).param("st", d.get("state")).param("n", kind.toLowerCase().replace('_', ' ') + " uploaded: " + body.filename().trim()).query().listOfRows();
        return full(id);
    }

    @GetMapping("/api/v1/me/deferments/{id}/documents/{doc}/content")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> myDocument(Authentication a, @PathVariable UUID id, @PathVariable UUID doc) {
        owned(me(a), id);
        return serve(id, doc);
    }

    private UUID owned(UUID student, UUID id) {
        long n = jdbc.sql("SELECT count(*) FROM people.deferment WHERE id = :id AND student_id = :s").param("id", id).param("s", student).query(Long.class).single();
        if (n == 0) throw new AccessDeniedException("That deferment request is not yours.");
        return id;
    }

    /* ── the desks ───────────────────────────────────────────────────────── */

    /** the bound the acting office is held to, as predicates on the shared read */
    private record Bound(String office, String faculty, String dept, boolean pg, boolean chs) {
        String kind() { return dept != null ? "DEPARTMENT" : faculty != null ? "FACULTY" : pg ? "PG_SCHOOL" : chs ? "COLLEGE" : "UNIVERSITY"; }
    }

    private Bound bound() {
        String office = AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
        if (ALL_SEEING.contains(office)) return new Bound(office, null, null, false, false);
        if (Set.of("pgschool", "pgsecretary").contains(office)) return new Bound(office, null, null, true, false);
        if (Set.of("provost", "collegesecretary").contains(office)) return new Bound(office, null, null, false, true);
        if (scope.actingFacultyOffice()) { String f = scope.actingFaculty(); return new Bound(office, f == null ? "__none__" : f, null, false, false); }
        if (scope.actingDepartmentOffice()) { String d = scope.actingDept(); return new Bound(office, null, d == null ? "__none__" : d, false, false); }
        return new Bound(office, "__none__", null, false, false);
    }

    private static final String WITHIN = """
             AND (:bf::text IS NULL OR f.code = :bf)
             AND (:bd::text IS NULL OR dp.code = :bd)
             AND (NOT :pg OR s.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE')
             AND (NOT :chs OR coalesce(f.college_code, '') = 'CHS')
            """;

    private JdbcClient.StatementSpec within(JdbcClient.StatementSpec q, Bound b) {
        return q.param("bf", b.faculty(), Types.VARCHAR).param("bd", b.dept(), Types.VARCHAR).param("pg", b.pg()).param("chs", b.chs());
    }

    private Map<String, Object> inBound(UUID id, Bound b) {
        Map<String, Object> d = within(jdbc.sql(ONE + " WHERE d.id = :id" + WITHIN), b).param("id", id).query().listOfRows().stream().findFirst().orElse(null);
        if (d == null) {
            if (jdbc.sql("SELECT count(*) FROM people.deferment WHERE id = :id").param("id", id).query(Long.class).single() == 0) throw new NotFound("deferment", id);
            throw new AccessDeniedException("This deferment is outside your office's bound; a desk reads and decides the requests of its own students only.");
        }
        return d;
    }

    @GetMapping("/api/v1/deferments")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                             @RequestParam(required = false) String state, @RequestParam(required = false) String fac,
                             @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                             @RequestParam(required = false) String kind, @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "100") int size) {
        Bound b = bound();
        String st = state == null || state.isBlank() ? null : state.trim().toUpperCase();
        String stPred = st == null ? "" : "PENDING".equals(st) ? " AND d.state IN ('SUBMITTED','DEPT_RECOMMENDED','FAC_RECOMMENDED')"
                : "MINE".equals(st) ? " AND d.state = " + stageOf(b.office()) : " AND d.state = :st";
        String needle = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%";
        int sz = Math.max(1, Math.min(size, 500)), pg = Math.max(0, page);
        JdbcClient.StatementSpec spec = jdbc.sql(ONE + """
                 WHERE (:ses::text IS NULL OR d.session = :ses)
                   AND (:sem::int IS NULL OR d.semester = :sem)
                   AND (:fac::text IS NULL OR f.code = :fac)
                   AND (:dept::text IS NULL OR dp.code = :dept)
                   AND (:prog::text IS NULL OR p.code = :prog)
                   AND (:kind::text IS NULL OR d.kind = :kind)
                   AND (:q::text IS NULL OR lower(s.surname || ' ' || s.other_names) LIKE :q OR lower(coalesce(s.matric_no, s.admission_no, '')) LIKE :q
                        OR lower(d.reference) LIKE :q OR lower(p.name) LIKE :q OR lower(dp.name) LIKE :q)
                """ + WITHIN + stPred + " ORDER BY s.surname, s.other_names, d.created_at DESC LIMIT :n OFFSET :o")
                .param("ses", blank(session), Types.VARCHAR).param("sem", semester, Types.INTEGER).param("fac", blank(fac), Types.VARCHAR)
                .param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR).param("kind", kind == null || kind.isBlank() ? null : kind.trim().toUpperCase(), Types.VARCHAR)
                .param("q", needle, Types.VARCHAR).param("n", sz).param("o", pg * sz);
        if (stPred.contains(":st")) spec = spec.param("st", st);
        List<Map<String, Object>> rows = within(spec, b).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("scope", Map.of("kind", b.kind(), "office", b.office(), "stage", stageOf(b.office()).replace("'", "")));
        out.put("rows", rows);
        out.put("page", pg);
        out.put("size", sz);
        out.put("options", options(b));
        return out;
    }

    /** the stage a desk decides at, as a quoted SQL literal */
    private static String stageOf(String office) {
        return switch (office) {
            case "hod" -> "'SUBMITTED'";
            case "dean", "facultyofficer" -> "'DEPT_RECOMMENDED'";
            default -> "'FAC_RECOMMENDED'";
        };
    }

    private Map<String, Object> options(Bound b) {
        Map<String, Object> o = new LinkedHashMap<>();
        o.put("sessions", jdbc.sql("SELECT DISTINCT session FROM people.deferment ORDER BY session DESC").query(String.class).list());
        o.put("programmes", within(jdbc.sql("""
                SELECT DISTINCT f.code AS faculty_code, f.name AS faculty, dp.code AS dept_code, dp.name AS department, p.code AS programme_code, p.name AS programme
                  FROM people.deferment d JOIN people.student s ON s.id = d.student_id JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.department dp ON dp.code = p.dept_code JOIN ref.faculty f ON f.code = p.faculty_code WHERE true""" + WITHIN + " ORDER BY f.name, dp.name, p.name"), b).query().listOfRows());
        o.put("states", List.of("DRAFT", "SUBMITTED", "CORRECTION_REQUIRED", "DEPT_RECOMMENDED", "FAC_RECOMMENDED", "APPROVED", "ACTIVE", "COMPLETED", "REJECTED", "CANCELLED"));
        return o;
    }

    @GetMapping("/api/v1/deferments/dashboard")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> dashboard(@RequestParam(required = false) String session) {
        Bound b = bound();
        String ses = blank(session);
        String base = """
                WITH x AS (SELECT d.*, f.code AS faculty_code, f.name AS faculty, dp.code AS dept_code, dp.name AS department, p.code AS programme_code, p.name AS programme, r.label AS reason,
                                  people.deferment_return_status(d.state, d.return_on) AS return_status
                             FROM people.deferment d JOIN people.deferment_reason r ON r.code = d.reason_code JOIN people.student s ON s.id = d.student_id
                             JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department dp ON dp.code = p.dept_code JOIN ref.faculty f ON f.code = p.faculty_code
                            WHERE (:ses::text IS NULL OR d.session = :ses)""" + WITHIN + ")\n";
        Map<String, Object> totals = within(jdbc.sql(base + """
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE state = 'SUBMITTED') AS pending,
                       count(*) FILTER (WHERE state IN ('DEPT_RECOMMENDED','FAC_RECOMMENDED')) AS under_review,
                       count(*) FILTER (WHERE state = 'CORRECTION_REQUIRED') AS correction,
                       count(*) FILTER (WHERE state IN ('APPROVED','ACTIVE','COMPLETED')) AS approved,
                       count(*) FILTER (WHERE state = 'REJECTED') AS rejected,
                       count(*) FILTER (WHERE state = 'ACTIVE') AS active,
                       count(*) FILTER (WHERE state IN ('ACTIVE','APPROVED') AND return_status = 'DUE') AS returning,
                       count(*) FILTER (WHERE return_status = 'OVERDUE') AS overdue,
                       count(*) FILTER (WHERE extension_of IS NOT NULL AND state NOT IN ('REJECTED','CANCELLED','COMPLETED')) AS extensions
                  FROM x
                """).param("ses", ses, Types.VARCHAR), b).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("scope", Map.of("kind", b.kind(), "office", b.office()));
        out.put("session", ses);
        out.put("totals", totals);
        for (String[] g : new String[][]{{"byFaculty", "faculty_code, faculty"}, {"byDepartment", "dept_code, department"}, {"byProgramme", "programme_code, programme"},
                {"byKind", "kind"}, {"bySession", "session"}, {"byReason", "reason"}}) {
            out.put(g[0], within(jdbc.sql(base + "SELECT " + g[1] + ", count(*) AS total, count(*) FILTER (WHERE state IN ('SUBMITTED','DEPT_RECOMMENDED','FAC_RECOMMENDED')) AS pending,"
                    + " count(*) FILTER (WHERE state IN ('APPROVED','ACTIVE','COMPLETED')) AS approved, count(*) FILTER (WHERE state = 'ACTIVE') AS active, count(*) FILTER (WHERE state = 'REJECTED') AS rejected"
                    + " FROM x GROUP BY " + g[1] + " ORDER BY " + g[1].split(",")[g[1].contains(",") ? 1 : 0]).param("ses", ses, Types.VARCHAR), b).query().listOfRows());
        }
        return out;
    }

    @GetMapping("/api/v1/deferments/returns")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> returns(@RequestParam(required = false) String status) {
        Bound b = bound();
        String st = status == null || status.isBlank() ? null : status.trim().toUpperCase();
        List<Map<String, Object>> rows = within(jdbc.sql(ONE + " WHERE d.state IN ('ACTIVE','APPROVED')" + WITHIN
                + " AND (:rs::text IS NULL OR people.deferment_return_status(d.state, d.return_on) = :rs) ORDER BY d.return_on NULLS LAST, s.surname, s.other_names"), b)
                .param("rs", st, Types.VARCHAR).query().listOfRows();
        return Map.of("scope", Map.of("kind", b.kind()), "rows", rows);
    }

    @GetMapping("/api/v1/deferments/{id}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> deskOne(@PathVariable UUID id) {
        Bound b = bound();
        inBound(id, b);
        Map<String, Object> d = full(id);
        UUID student = (UUID) d.get("student_id");
        d.put("previous", jdbc.sql("SELECT reference, kind, session, semester, state, submitted_at, decided_at FROM people.deferment WHERE student_id = :s AND id <> :id ORDER BY created_at DESC")
                .param("s", student).param("id", id).query().listOfRows());
        d.put("registration", jdbc.sql("""
                SELECT session, semester, status, submitted_at FROM registration.course_registration WHERE student_id = :s ORDER BY session DESC, semester DESC LIMIT 4
                """).param("s", student).query().listOfRows());
        d.put("fees", jdbc.sql("SELECT payable, paid, outstanding, status FROM finance.payment_position(:s, :ses, NULL)").param("s", student).param("ses", d.get("session")).query().singleRow());
        d.put("standing", jdbc.sql("SELECT standing, cgpa FROM assessment.student_standing(:s)").param("s", student).query().listOfRows().stream().findFirst().orElse(Map.of()));
        d.put("may", may(b, String.valueOf(d.get("state"))));
        return d;
    }

    /** what this desk may do with a request at this state — the same rule the action applies */
    private static Map<String, Boolean> may(Bound b, String state) {
        String o = b.office();
        boolean registry = REGISTRY.contains(o);
        boolean deptDesk = "hod".equals(o) || registry;
        boolean facDesk = Set.of("dean", "facultyofficer").contains(o) || registry;
        boolean inReview = Set.of("SUBMITTED", "DEPT_RECOMMENDED", "FAC_RECOMMENDED").contains(state);
        boolean atMine = ("hod".equals(o) && "SUBMITTED".equals(state)) || (Set.of("dean", "facultyofficer").contains(o) && "DEPT_RECOMMENDED".equals(state)) || registry;
        Map<String, Boolean> m = new LinkedHashMap<>();
        m.put("recommend", deptDesk && "SUBMITTED".equals(state));
        m.put("facRecommend", facDesk && "DEPT_RECOMMENDED".equals(state));
        m.put("approve", registry && Set.of("FAC_RECOMMENDED", "DEPT_RECOMMENDED").contains(state));
        m.put("reject", inReview && atMine);
        m.put("correction", inReview && atMine);
        m.put("cancel", registry && Set.of("SUBMITTED", "DEPT_RECOMMENDED", "FAC_RECOMMENDED", "APPROVED").contains(state));
        m.put("confirmReturn", (registry || "hod".equals(o) || Set.of("dean", "facultyofficer").contains(o)) && Set.of("ACTIVE", "APPROVED").contains(state));
        return m;
    }

    public record ActionIn(@NotBlank String action, @Size(max = 2000) String note) {
    }

    @PostMapping("/api/v1/deferments/{id}/action")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> act(@PathVariable UUID id, @Valid @RequestBody ActionIn body) {
        Bound b = bound();
        Map<String, Object> d = inBound(id, b);
        String action = body.action().trim().toUpperCase();
        Map<String, Boolean> m = may(b, String.valueOf(d.get("state")));
        boolean allowed = switch (action) {
            case "RECOMMEND" -> m.get("recommend");
            case "FAC_RECOMMEND" -> m.get("facRecommend");
            case "APPROVE" -> m.get("approve");
            case "REJECT" -> m.get("reject");
            case "CORRECTION" -> m.get("correction");
            case "CANCEL" -> m.get("cancel");
            default -> false;
        };
        if (!allowed) {
            throw new DomainRuleViolation("DEF_NOT_YOUR_STAGE", "This request is " + String.valueOf(d.get("state")).toLowerCase().replace('_', ' ') + "; " + action.toLowerCase().replace('_', ' ') + " is not this desk's act at that stage.",
                    new DomainRuleViolation.Remedy("The department recommends a submitted request, the faculty a recommended one, and the Registry approves; each may return or reject at its own stage.", "Registry"));
        }
        jdbc.sql("SELECT people.deferment_decide(:id, :a, :n, :by, :o)").param("id", id).param("a", action)
                .param("n", body.note(), Types.VARCHAR).param("by", AuditContextHolder.required().actorId()).param("o", b.office()).query(String.class).single();
        return deskOne(id);
    }

    @PostMapping("/api/v1/deferments/{id}/return")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> confirmReturn(@PathVariable UUID id, @RequestBody(required = false) NoteIn body) {
        Bound b = bound();
        Map<String, Object> d = inBound(id, b);
        if (!may(b, String.valueOf(d.get("state"))).get("confirmReturn")) {
            throw new DomainRuleViolation("DEF_NOT_RETURNING", "A return is confirmed on a deferment in force by the department, the faculty or the Registry.", new DomainRuleViolation.Remedy("Nothing to confirm on this request.", "Registry"));
        }
        jdbc.sql("SELECT people.deferment_confirm_return(:id, :n, :by)").param("id", id).param("n", body == null ? null : body.note(), Types.VARCHAR)
                .param("by", AuditContextHolder.required().actorId()).query(String.class).single();
        return deskOne(id);
    }

    @GetMapping("/api/v1/deferments/{id}/documents/{doc}/content")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> deskDocument(@PathVariable UUID id, @PathVariable UUID doc) {
        inBound(id, bound());
        return serve(id, doc);
    }

    /** the tick, callable by the Registry (the clock also runs it each morning) */
    @PostMapping("/api/v1/deferments/tick")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_ict','OFFICE_super')")
    @Transactional
    Map<String, Object> tick() {
        return Map.of("changed", jdbc.sql("SELECT people.deferments_tick()").query(Integer.class).single());
    }

    /* ── helpers ─────────────────────────────────────────────────────────── */

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private ResponseEntity<byte[]> serve(UUID id, UUID doc) {
        Map<String, Object> r = jdbc.sql("""
                SELECT d.filename, d.content_type, b.bytes FROM people.deferment_document d JOIN people.deferment_document_blob b ON b.document_id = d.id
                 WHERE d.id = :d AND d.deferment_id = :id
                """).param("d", doc).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("document", doc));
        String type = String.valueOf(r.get("content_type"));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(type)).cacheControl(CacheControl.noStore())
                .header("Content-Disposition", ContentDisposition.inline().filename(String.valueOf(r.get("filename")), StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Type-Options", "nosniff").header("Content-Security-Policy", "sandbox")
                .body((byte[]) r.get("bytes"));
    }

    private static String sniff(byte[] b) {
        if (b.length >= 5 && b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F' && b[4] == '-') return "application/pdf";
        if (b.length >= 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') return "image/png";
        if (b.length >= 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF) return "image/jpeg";
        return "unknown";
    }

    @SuppressWarnings("unused")
    private static List<String> names(List<Map<String, Object>> rows) {
        List<String> out = new ArrayList<>();
        for (Map<String, Object> r : rows) out.add(String.valueOf(r.get("reference")));
        return out;
    }
}
