package ng.edu.moaum.portal.deferments;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.sql.Types;
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Deferment (V259, revised by V264): the student pays the application fee through the University's payment reference and
 * the form opens on the confirmed payment; the request then goes to the Bursary (the last school-fee payment and the
 * balance read from the finance record), the Head of Department, the faculty, the Academic Office (which sees every
 * stage, downloads only what the faculty has approved, and forwards the approved list to the DVC in a numbered batch),
 * the Deputy Vice-Chancellor (with a comment) and the Senate Business Committee, whose approval applies the academic
 * effect. The student reaches only their own requests (/api/v1/me/deferments); a desk reaches those within its bound —
 * a Head their department, a Dean their faculty, the Bursary, the Academic Office, the DVC and the Registry all — and
 * each acts only at its own stage. The rules are in the database; this is the door to them.
 */
@RestController
class DefermentsController {

    private static final String STUDENT = "hasAuthority('OFFICE_student')";
    private static final String DESK = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_facultyofficer','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_records','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_provost','OFFICE_collegesecretary','OFFICE_super','OFFICE_admin','OFFICE_bursar','OFFICE_dvc','OFFICE_vc')";
    private static final String SETTINGS = "hasAnyAuthority('OFFICE_bursar','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final Set<String> REGISTRY = Set.of("academic", "registrar", "dregistrar", "super");
    private static final Set<String> ALL_SEEING = Set.of("academic", "registrar", "dregistrar", "records", "super", "admin", "bursar", "dvc", "vc");
    private static final Set<String> IN_REVIEW = Set.of("SUBMITTED", "BURSARY_APPROVED", "DEPT_RECOMMENDED", "FAC_RECOMMENDED", "FORWARDED_TO_DVC", "DVC_APPROVED");
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
                   s.surname, s.other_names, coalesce(s.matric_no, s.admission_no) AS number, s.current_level AS level, s.status AS student_status, s.entry_mode, s.entry_session,
                   p.code AS programme_code, p.name AS programme, dp.code AS dept_code, dp.name AS department, f.code AS faculty_code, f.name AS faculty, f.college_code,
                   people.deferment_return_status(d.state, d.return_on) AS return_status,
                   people.deferment_stage_label(d.state) AS stage_label, people.deferment_stage_office_label(d.state) AS stage_office,
                   CASE WHEN db.id IS NULL THEN NULL ELSE db.surname || ', ' || db.given_names END AS dept_officer,
                   CASE WHEN fb.id IS NULL THEN NULL ELSE fb.surname || ', ' || fb.given_names END AS faculty_officer,
                   CASE WHEN ab.id IS NULL THEN NULL ELSE ab.surname || ', ' || ab.given_names END AS decided_officer,
                   CASE WHEN rb.id IS NULL THEN NULL ELSE rb.surname || ', ' || rb.given_names END AS returned_officer,
                   CASE WHEN bb.id IS NULL THEN NULL ELSE bb.surname || ', ' || bb.given_names END AS bursary_officer,
                   CASE WHEN vb.id IS NULL THEN NULL ELSE vb.surname || ', ' || vb.given_names END AS dvc_officer,
                   CASE WHEN wb.id IS NULL THEN NULL ELSE wb.surname || ', ' || wb.given_names END AS forwarded_officer,
                   fe.reference AS fee_reference, fe.amount AS fee_amount, fe.receipt_no AS fee_receipt_no, fe.confirmed_at AS fee_confirmed_at,
                   CASE WHEN fe.id IS NULL THEN NULL WHEN fe.state = 'PENDING' AND pr.expires_at < now() THEN 'EXPIRED' ELSE fe.state END AS fee_state,
                   bt.reference AS batch_reference, bt.forwarded_at AS batch_forwarded_at
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
              LEFT JOIN iam.person bb ON bb.id = d.bursary_by
              LEFT JOIN iam.person vb ON vb.id = d.dvc_by
              LEFT JOIN iam.person wb ON wb.id = d.forwarded_by
              LEFT JOIN people.deferment_fee fe ON fe.id = d.fee_id
              LEFT JOIN finance.payment_reference pr ON pr.reference = fe.reference
              LEFT JOIN people.deferment_batch bt ON bt.id = d.batch_id
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
        d.put("effect", jdbc.sql("SELECT * FROM people.deferment_effect(:id)").param("id", id).query().listOfRows().stream().findFirst().orElse(null));
        d.put("deferredCourses", jdbc.sql("SELECT * FROM people.deferred_courses(:s) WHERE deferment_id = :id").param("s", d.get("student_id")).param("id", id).query().listOfRows());
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
        out.put("fee", jdbc.sql("SELECT * FROM people.deferment_fee_view(:s)").param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("requests", jdbc.sql(ONE + " WHERE d.student_id = :s ORDER BY d.created_at DESC").param("s", s).query().listOfRows());
        out.put("reasons", jdbc.sql("SELECT code, label, needs_document, needs_words FROM people.deferment_reason WHERE active ORDER BY ord").query().listOfRows());
        out.put("sessions", jdbc.sql("SELECT name, semesters, state FROM policy.academic_session WHERE state IN ('CURRENT','PLANNED') ORDER BY name").query().listOfRows());
        out.put("current", jdbc.sql("""
                SELECT a.name AS session, (SELECT max(number) FROM policy.semester sm WHERE sm.session = a.name AND sm.state = 'OPEN') AS semester
                  FROM policy.academic_session a WHERE a.state = 'CURRENT'
                """).query().listOfRows().stream().findFirst().orElse(Map.of()));
        out.put("setting", jdbc.sql("SELECT max_sessions, allow_extension, fee FROM people.deferment_setting WHERE id = 1").query().singleRow());
        out.put("timeline", jdbc.sql("SELECT * FROM people.programme_timeline(:s)").param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("deferredCourses", jdbc.sql("SELECT * FROM people.deferred_courses(:s)").param("s", s).query().listOfRows());
        return out;
    }

    /** the fee reference: generated, or the live one returned; the form opens on its confirmation */
    @PostMapping("/api/v1/me/deferments/fee")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> startFee(Authentication a) {
        UUID s = me(a);
        jdbc.sql("SELECT people.deferment_fee_start(:s)").param("s", s).query(UUID.class).single();
        return jdbc.sql("SELECT * FROM people.deferment_fee_view(:s)").param("s", s).query().singleRow();
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
            throw new DomainRuleViolation("DEF_DOC_CLOSED", "Documents are added while the request is yours to change or awaiting the Bursary.",
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

    /** the stage a desk decides at */
    private static String stageOf(String office) {
        return switch (office) {
            case "bursar" -> "SUBMITTED";
            case "hod" -> "BURSARY_APPROVED";
            case "dean", "facultyofficer" -> "DEPT_RECOMMENDED";
            case "academic" -> "FAC_RECOMMENDED";
            case "dvc" -> "FORWARDED_TO_DVC";
            case "registrar", "dregistrar", "super" -> "DVC_APPROVED";
            default -> "__none__";
        };
    }

    @GetMapping("/api/v1/deferments")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                             @RequestParam(required = false) String state, @RequestParam(required = false) String fac,
                             @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                             @RequestParam(required = false) String kind, @RequestParam(required = false) String q,
                             @RequestParam(required = false) String batch, @RequestParam(required = false) String from, @RequestParam(required = false) String to,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "100") int size) {
        Bound b = bound();
        String st = state == null || state.isBlank() ? null : state.trim().toUpperCase();
        String stPred = st == null ? "" : switch (st) {
            case "PENDING" -> " AND d.state IN ('SUBMITTED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED')";
            case "MINE" -> " AND d.state = '" + stageOf(b.office()) + "'";
            case "FACULTY_APPROVED" -> " AND d.fac_at IS NOT NULL AND d.state IN ('FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED','APPROVED','ACTIVE','COMPLETED')";
            case "DECIDED" -> " AND d.state IN ('APPROVED','ACTIVE','COMPLETED','REJECTED')";
            default -> " AND d.state = :st";
        };
        String needle = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%";
        int sz = Math.max(1, Math.min(size, 500)), pg = Math.max(0, page);
        JdbcClient.StatementSpec spec = jdbc.sql(ONE + """
                 WHERE (:ses::text IS NULL OR d.session = :ses)
                   AND (:sem::int IS NULL OR d.semester = :sem)
                   AND (:fac::text IS NULL OR f.code = :fac)
                   AND (:dept::text IS NULL OR dp.code = :dept)
                   AND (:prog::text IS NULL OR p.code = :prog)
                   AND (:kind::text IS NULL OR d.kind = :kind)
                   AND (:batch::text IS NULL OR lower(bt.reference) = lower(:batch) OR bt.id::text = :batch)
                   AND (:from::date IS NULL OR coalesce(d.submitted_at, d.created_at)::date >= :from::date)
                   AND (:to::date IS NULL OR coalesce(d.submitted_at, d.created_at)::date <= :to::date)
                   AND (:q::text IS NULL OR lower(s.surname || ' ' || s.other_names) LIKE :q OR lower(s.other_names || ' ' || s.surname) LIKE :q
                        OR lower(coalesce(s.matric_no, '')) LIKE :q OR lower(coalesce(s.admission_no, '')) LIKE :q
                        OR lower(d.reference) LIKE :q OR lower(p.name) LIKE :q OR lower(dp.name) LIKE :q OR lower(f.name) LIKE :q OR lower(coalesce(bt.reference, '')) LIKE :q)
                """ + WITHIN + stPred + " ORDER BY s.surname, s.other_names, d.created_at DESC LIMIT :n OFFSET :o")
                .param("ses", blank(session), Types.VARCHAR).param("sem", semester, Types.INTEGER).param("fac", blank(fac), Types.VARCHAR)
                .param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR).param("kind", kind == null || kind.isBlank() ? null : kind.trim().toUpperCase(), Types.VARCHAR)
                .param("batch", blank(batch), Types.VARCHAR).param("from", blank(from), Types.VARCHAR).param("to", blank(to), Types.VARCHAR)
                .param("q", needle, Types.VARCHAR).param("n", sz).param("o", pg * sz);
        if (stPred.contains(":st")) spec = spec.param("st", st);
        List<Map<String, Object>> rows = within(spec, b).query().listOfRows();
        for (Map<String, Object> r : rows) r.put("downloadable", downloadable(b, r));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("scope", Map.of("kind", b.kind(), "office", b.office(), "stage", stageOf(b.office())));
        out.put("rows", rows);
        out.put("page", pg);
        out.put("size", sz);
        out.put("options", options(b));
        return out;
    }

    private Map<String, Object> options(Bound b) {
        Map<String, Object> o = new LinkedHashMap<>();
        o.put("sessions", jdbc.sql("SELECT DISTINCT session FROM people.deferment ORDER BY session DESC").query(String.class).list());
        o.put("programmes", within(jdbc.sql("""
                SELECT DISTINCT f.code AS faculty_code, f.name AS faculty, dp.code AS dept_code, dp.name AS department, p.code AS programme_code, p.name AS programme
                  FROM people.deferment d JOIN people.student s ON s.id = d.student_id JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.department dp ON dp.code = p.dept_code JOIN ref.faculty f ON f.code = p.faculty_code WHERE true""" + WITHIN + " ORDER BY f.name, dp.name, p.name"), b).query().listOfRows());
        o.put("states", List.of("DRAFT", "SUBMITTED", "CORRECTION_REQUIRED", "BURSARY_APPROVED", "DEPT_RECOMMENDED", "FAC_RECOMMENDED", "FORWARDED_TO_DVC", "DVC_APPROVED", "APPROVED", "ACTIVE", "COMPLETED", "REJECTED", "CANCELLED"));
        o.put("batches", jdbc.sql("SELECT id, reference, forwarded_at, count FROM people.deferment_batch ORDER BY forwarded_at DESC LIMIT 200").query().listOfRows());
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
                       count(*) FILTER (WHERE state = 'SUBMITTED') AS waiting_bursary,
                       count(*) FILTER (WHERE state = 'BURSARY_APPROVED') AS waiting_hod,
                       count(*) FILTER (WHERE state = 'DEPT_RECOMMENDED') AS waiting_faculty,
                       count(*) FILTER (WHERE state = 'FAC_RECOMMENDED') AS waiting_academic,
                       count(*) FILTER (WHERE state = 'FORWARDED_TO_DVC') AS forwarded_dvc,
                       count(*) FILTER (WHERE state = 'DVC_APPROVED') AS waiting_sbc,
                       count(*) FILTER (WHERE state IN ('SUBMITTED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED')) AS pending,
                       count(*) FILTER (WHERE state = 'CORRECTION_REQUIRED') AS correction,
                       count(*) FILTER (WHERE state IN ('APPROVED','ACTIVE','COMPLETED')) AS approved,
                       count(*) FILTER (WHERE state = 'REJECTED') AS rejected,
                       count(*) FILTER (WHERE state = 'ACTIVE') AS active,
                       count(*) FILTER (WHERE state = 'COMPLETED') AS completed,
                       count(*) FILTER (WHERE fac_at IS NOT NULL AND state IN ('FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED','APPROVED','ACTIVE','COMPLETED')) AS faculty_approved,
                       count(*) FILTER (WHERE batch_id IS NOT NULL) AS forwarded,
                       count(*) FILTER (WHERE state IN ('ACTIVE','APPROVED') AND return_status = 'DUE') AS returning,
                       count(*) FILTER (WHERE return_status = 'OVERDUE') AS overdue,
                       count(*) FILTER (WHERE extension_of IS NOT NULL AND state NOT IN ('REJECTED','CANCELLED','COMPLETED')) AS extensions,
                       count(*) FILTER (WHERE state = :mine) AS mine
                  FROM x
                """).param("ses", ses, Types.VARCHAR).param("mine", stageOf(b.office())), b).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("scope", Map.of("kind", b.kind(), "office", b.office(), "stage", stageOf(b.office())));
        out.put("session", ses);
        out.put("totals", totals);
        for (String[] g : new String[][]{{"byFaculty", "faculty_code, faculty"}, {"byDepartment", "dept_code, department"}, {"byProgramme", "programme_code, programme"},
                {"byKind", "kind"}, {"bySession", "session"}, {"byReason", "reason"}}) {
            out.put(g[0], within(jdbc.sql(base + "SELECT " + g[1] + ", count(*) AS total, count(*) FILTER (WHERE state IN ('SUBMITTED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC','DVC_APPROVED')) AS pending,"
                    + " count(*) FILTER (WHERE state IN ('APPROVED','ACTIVE','COMPLETED')) AS approved, count(*) FILTER (WHERE state = 'ACTIVE') AS active, count(*) FILTER (WHERE state = 'REJECTED') AS rejected"
                    + " FROM x GROUP BY " + g[1] + " ORDER BY " + g[1].split(",")[g[1].contains(",") ? 1 : 0]).param("ses", ses, Types.VARCHAR), b).query().listOfRows());
        }
        out.put("setting", jdbc.sql("SELECT fee, max_sessions, allow_extension, reminder_days, overdue_after_days FROM people.deferment_setting WHERE id = 1").query().singleRow());
        return out;
    }

    /** students due to resume: every deferment in force within the bound, searched and filtered on the server */
    @GetMapping("/api/v1/deferments/returns")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> returns(@RequestParam(required = false) String status, @RequestParam(required = false) String q, @RequestParam(required = false) String fac,
                                @RequestParam(required = false) String dept, @RequestParam(required = false) String prog, @RequestParam(required = false) String session,
                                @RequestParam(required = false) String kind, @RequestParam(required = false) String returnSession, @RequestParam(required = false) Integer returnSemester) {
        Bound b = bound();
        String st = status == null || status.isBlank() ? null : status.trim().toUpperCase();
        String needle = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%";
        List<Map<String, Object>> rows = within(jdbc.sql(ONE + " WHERE d.state IN ('ACTIVE','APPROVED')" + WITHIN + """
                 AND (:rs::text IS NULL OR people.deferment_return_status(d.state, d.return_on) = :rs)
                 AND (:fac::text IS NULL OR f.code = :fac) AND (:dept::text IS NULL OR dp.code = :dept) AND (:prog::text IS NULL OR p.code = :prog)
                 AND (:ses::text IS NULL OR d.session = :ses) AND (:kind::text IS NULL OR d.kind = :kind)
                 AND (:rses::text IS NULL OR d.return_session = :rses) AND (:rsem::int IS NULL OR d.return_semester = :rsem)
                 AND (:q::text IS NULL OR lower(s.surname || ' ' || s.other_names) LIKE :q OR lower(s.other_names || ' ' || s.surname) LIKE :q
                      OR lower(coalesce(s.matric_no, '')) LIKE :q OR lower(coalesce(s.admission_no, '')) LIKE :q OR lower(d.reference) LIKE :q OR lower(p.name) LIKE :q)
                 ORDER BY d.return_on NULLS LAST, s.surname, s.other_names"""), b)
                .param("rs", st, Types.VARCHAR).param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR)
                .param("ses", blank(session), Types.VARCHAR).param("kind", kind == null || kind.isBlank() ? null : kind.trim().toUpperCase(), Types.VARCHAR)
                .param("rses", blank(returnSession), Types.VARCHAR).param("rsem", returnSemester, Types.INTEGER).param("q", needle, Types.VARCHAR).query().listOfRows();
        for (Map<String, Object> r : rows) {
            r.put("deferred_due", jdbc.sql("SELECT count(*) FROM people.deferred_courses(:s) x WHERE x.deferment_id = :id AND x.status = 'DEFERRED'")
                    .param("s", r.get("student_id")).param("id", r.get("id")).query(Long.class).single());
        }
        return Map.of("scope", Map.of("kind", b.kind()), "rows", rows, "options", options(b));
    }

    /* the batches the Academic Office has forwarded to the DVC */
    @GetMapping("/api/v1/deferments/batches")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> batches() {
        return jdbc.sql("""
                SELECT b.*, CASE WHEN fw.id IS NULL THEN NULL ELSE fw.surname || ', ' || fw.given_names END AS forwarded_officer,
                       (SELECT count(*) FROM people.deferment d WHERE d.batch_id = b.id AND d.state = 'FORWARDED_TO_DVC') AS awaiting_dvc,
                       (SELECT count(*) FROM people.deferment d WHERE d.batch_id = b.id AND d.state = 'DVC_APPROVED') AS waiting_sbc,
                       (SELECT count(*) FROM people.deferment d WHERE d.batch_id = b.id AND d.state IN ('APPROVED','ACTIVE','COMPLETED')) AS approved,
                       (SELECT count(*) FROM people.deferment d WHERE d.batch_id = b.id AND d.state = 'REJECTED') AS rejected,
                       (SELECT count(*) FROM people.deferment d WHERE d.batch_id = b.id AND d.state = 'CORRECTION_REQUIRED') AS returned,
                       CASE WHEN EXISTS (SELECT 1 FROM people.deferment d WHERE d.batch_id = b.id AND d.state = 'FORWARDED_TO_DVC') THEN 'OPEN' ELSE 'DECIDED' END AS dvc_status
                  FROM people.deferment_batch b LEFT JOIN iam.person fw ON fw.id = b.forwarded_by ORDER BY b.forwarded_at DESC
                """).query().listOfRows();
    }

    public record ForwardIn(List<UUID> ids, String session, Integer semester, @Size(max = 1000) String note) {
    }

    /** the Academic Office forwards the faculty-approved requests (named, or the whole list) to the DVC in one batch */
    @PostMapping("/api/v1/deferments/forward")
    @PreAuthorize("hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')")
    @Transactional
    Map<String, Object> forward(@RequestBody(required = false) ForwardIn body) {
        Bound b = bound();
        UUID[] ids = body == null || body.ids() == null || body.ids().isEmpty() ? null : body.ids().toArray(new UUID[0]);
        UUID batch = jdbc.sql("SELECT people.deferment_forward(:ids::uuid[], :ses, :sem, :n, :by, :o)")
                .param("ids", ids, Types.ARRAY).param("ses", body == null ? null : blank(body.session()), Types.VARCHAR).param("sem", body == null ? null : body.semester(), Types.INTEGER)
                .param("n", body == null ? null : body.note(), Types.VARCHAR).param("by", AuditContextHolder.required().actorId()).param("o", b.office()).query(UUID.class).single();
        return batches().stream().filter(x -> batch.equals(x.get("id"))).findFirst().orElse(Map.of("id", batch));
    }

    @GetMapping("/api/v1/deferments/{id}")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> deskOne(@PathVariable UUID id) {
        Bound b = bound();
        inBound(id, b);
        jdbc.sql("SELECT people.deferment_viewed(:id, 'VIEWED', :o)").param("id", id).param("o", "Opened by the " + officeWord(b.office())).query().listOfRows();
        return enriched(id, b);
    }

    private Map<String, Object> enriched(UUID id, Bound b) {
        Map<String, Object> d = full(id);
        UUID student = (UUID) d.get("student_id");
        d.put("previous", jdbc.sql("SELECT reference, kind, session, semester, state, submitted_at, decided_at, people.deferment_stage_label(state) AS stage_label FROM people.deferment WHERE student_id = :s AND id <> :id ORDER BY created_at DESC")
                .param("s", student).param("id", id).query().listOfRows());
        d.put("registration", jdbc.sql("""
                SELECT session, semester, status, submitted_at FROM registration.course_registration WHERE student_id = :s ORDER BY session DESC, semester DESC LIMIT 4
                """).param("s", student).query().listOfRows());
        d.put("fees", jdbc.sql("SELECT payable, paid, outstanding, status FROM finance.payment_position(:s, :ses, NULL)").param("s", student).param("ses", d.get("session")).query().singleRow());
        d.put("financials", jdbc.sql("SELECT * FROM people.deferment_financials(:s, :ses)").param("s", student).param("ses", d.get("session")).query().listOfRows().stream().findFirst().orElse(Map.of()));
        d.put("standing", jdbc.sql("SELECT standing, cgpa FROM assessment.student_standing(:s)").param("s", student).query().listOfRows().stream().findFirst().orElse(Map.of()));
        d.put("timeline", jdbc.sql("SELECT * FROM people.programme_timeline(:s)").param("s", student).query().listOfRows().stream().findFirst().orElse(null));
        d.put("may", may(b, d));
        d.put("downloadable", downloadable(b, d));
        return d;
    }

    private static String officeWord(String o) {
        return switch (o) {
            case "bursar" -> "Bursary"; case "hod" -> "Head of Department"; case "dean" -> "Dean"; case "facultyofficer" -> "Faculty Officer";
            case "academic" -> "Academic Office"; case "dvc" -> "Deputy Vice-Chancellor"; case "registrar" -> "Registrar"; case "dregistrar" -> "Deputy Registrar";
            default -> o;
        };
    }

    /** the Academic Office downloads only what the faculty has approved; the desks that decide before the faculty see their own; the rest read everything in their bound */
    private static boolean downloadable(Bound b, Map<String, Object> d) {
        String o = b.office();
        if ("academic".equals(o)) return d.get("fac_at") != null;
        return true;
    }

    /** what this desk may do with a request at this state — the same rule the database applies */
    private static Map<String, Boolean> may(Bound b, Map<String, Object> d) {
        String o = b.office();
        String state = String.valueOf(d.get("state"));
        boolean sup = "super".equals(o);
        boolean registry = REGISTRY.contains(o);
        boolean stageMine = switch (state) {
            case "SUBMITTED" -> "bursar".equals(o) || sup;
            case "BURSARY_APPROVED" -> "hod".equals(o) || sup;
            case "DEPT_RECOMMENDED" -> Set.of("dean", "facultyofficer").contains(o) || sup;
            case "FAC_RECOMMENDED" -> Set.of("academic", "registrar", "dregistrar").contains(o) || sup;
            case "FORWARDED_TO_DVC" -> "dvc".equals(o) || sup;
            case "DVC_APPROVED" -> Set.of("registrar", "dregistrar").contains(o) || sup;
            default -> false;
        };
        Map<String, Boolean> m = new LinkedHashMap<>();
        m.put("bursaryApprove", "SUBMITTED".equals(state) && stageMine);
        m.put("recommend", "BURSARY_APPROVED".equals(state) && stageMine);
        m.put("facRecommend", "DEPT_RECOMMENDED".equals(state) && stageMine);
        m.put("forward", "FAC_RECOMMENDED".equals(state) && stageMine);
        m.put("dvcApprove", "FORWARDED_TO_DVC".equals(state) && stageMine);
        m.put("sbcApprove", "DVC_APPROVED".equals(state) && stageMine);
        m.put("reject", IN_REVIEW.contains(state) && stageMine);
        m.put("correction", IN_REVIEW.contains(state) && stageMine);
        m.put("cancel", registry && (IN_REVIEW.contains(state) || "APPROVED".equals(state)));
        m.put("confirmReturn", (registry || Set.of("hod", "dean", "facultyofficer").contains(o)) && Set.of("ACTIVE", "APPROVED").contains(state));
        m.put("download", downloadable(b, d));
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
        Map<String, Boolean> m = may(b, d);
        boolean allowed = switch (action) {
            case "BURSARY_APPROVE" -> m.get("bursaryApprove");
            case "RECOMMEND" -> m.get("recommend");
            case "FAC_RECOMMEND" -> m.get("facRecommend");
            case "DVC_APPROVE" -> m.get("dvcApprove");
            case "SBC_APPROVE" -> m.get("sbcApprove");
            case "REJECT" -> m.get("reject");
            case "CORRECTION" -> m.get("correction");
            case "CANCEL" -> m.get("cancel");
            default -> false;
        };
        if (!allowed) {
            throw new DomainRuleViolation("DEF_NOT_YOUR_STAGE", "This request is " + String.valueOf(d.get("stage_label")).toLowerCase() + "; " + action.toLowerCase().replace('_', ' ') + " is not this desk's act at that stage.",
                    new DomainRuleViolation.Remedy("The Bursary verifies a submitted request, the Head of Department decides after the Bursary, the faculty after the department, the Academic Office forwards, the DVC decides a forwarded request, and the Senate Business Committee acts last; each may return or reject at its own stage only.", "Registry"));
        }
        if ("DVC_APPROVE".equals(action) && (body.note() == null || body.note().isBlank())) {
            throw new DomainRuleViolation("DEF_DVC_COMMENT", "The DVC's decision carries a comment.", new DomainRuleViolation.Remedy("Write the recommendation or observation that goes on the record with the approval.", "Deputy Vice-Chancellor"));
        }
        jdbc.sql("SELECT people.deferment_decide(:id, :a, :n, :by, :o)").param("id", id).param("a", action)
                .param("n", body.note(), Types.VARCHAR).param("by", AuditContextHolder.required().actorId()).param("o", b.office()).query(String.class).single();
        return enriched(id, b);
    }

    @PostMapping("/api/v1/deferments/{id}/return")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> confirmReturn(@PathVariable UUID id, @RequestBody(required = false) NoteIn body) {
        Bound b = bound();
        Map<String, Object> d = inBound(id, b);
        if (!may(b, d).get("confirmReturn")) {
            throw new DomainRuleViolation("DEF_NOT_RETURNING", "A return is confirmed on a deferment in force by the department, the faculty or the Registry.", new DomainRuleViolation.Remedy("Nothing to confirm on this request.", "Registry"));
        }
        jdbc.sql("SELECT people.deferment_confirm_return(:id, :n, :by)").param("id", id).param("n", body == null ? null : body.note(), Types.VARCHAR)
                .param("by", AuditContextHolder.required().actorId()).query(String.class).single();
        return enriched(id, b);
    }

    /** the application, whole, for the desk's copy — the Academic Office only once the faculty has approved; every download on the trail */
    @GetMapping("/api/v1/deferments/{id}/application")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> application(@PathVariable UUID id) {
        Bound b = bound();
        Map<String, Object> d = inBound(id, b);
        if (!downloadable(b, d)) {
            throw new DomainRuleViolation("DEF_NOT_DOWNLOADABLE", "The Academic Office downloads an application once the faculty has approved it; this one is " + String.valueOf(d.get("stage_label")).toLowerCase() + ".",
                    new DomainRuleViolation.Remedy("It may be viewed on the desk; it is downloaded when the faculty's approval is on it.", "Academic Office"));
        }
        jdbc.sql("SELECT people.deferment_viewed(:id, 'DOWNLOADED', :o)").param("id", id).param("o", "Application downloaded by the " + officeWord(b.office())).query().listOfRows();
        return enriched(id, b);
    }

    @GetMapping("/api/v1/deferments/{id}/documents/{doc}/content")
    @PreAuthorize(DESK)
    @Transactional
    ResponseEntity<byte[]> deskDocument(@PathVariable UUID id, @PathVariable UUID doc) {
        Bound b = bound();
        inBound(id, b);
        jdbc.sql("SELECT people.deferment_viewed(:id, 'DOCUMENT_VIEWED', :o)").param("id", id).param("o", "Document " + doc + " viewed by the " + officeWord(b.office())).query().listOfRows();
        return serve(id, doc);
    }

    /* ── the settings: the fee is the Bursary's, the limits the Registry's ─ */

    @GetMapping("/api/v1/deferments/settings")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> settings() {
        return jdbc.sql("SELECT fee, fee_updated_at, fee_updated_by, max_sessions, allow_extension, reminder_days, overdue_after_days FROM people.deferment_setting WHERE id = 1").query().singleRow();
    }

    public record SettingsIn(BigDecimal fee, BigDecimal maxSessions, Boolean allowExtension, Integer reminderDays, Integer overdueAfterDays) {
    }

    @PutMapping("/api/v1/deferments/settings")
    @PreAuthorize(SETTINGS)
    @Transactional
    Map<String, Object> saveSettings(@RequestBody SettingsIn body) {
        String office = AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
        if (body.fee() != null) {
            if (!Set.of("bursar", "super").contains(office)) throw new DomainRuleViolation("DEF_FEE_OFFICE", "The deferment application fee is stated by the Bursary.", new DomainRuleViolation.Remedy("The Bursar changes the fee; the Registry changes the limits.", "Bursary"));
            if (body.fee().signum() < 0) throw new DomainRuleViolation("DEF_FEE", "A fee is not negative.", new DomainRuleViolation.Remedy("State the amount, or zero to waive it.", "Bursary"));
            jdbc.sql("UPDATE people.deferment_setting SET fee = :f, fee_updated_at = now(), fee_updated_by = :by WHERE id = 1").param("f", body.fee()).param("by", AuditContextHolder.required().actorId()).update();
        }
        if (body.maxSessions() != null || body.allowExtension() != null || body.reminderDays() != null || body.overdueAfterDays() != null) {
            if (!Set.of("academic", "registrar", "dregistrar", "super").contains(office)) throw new DomainRuleViolation("DEF_LIMIT_OFFICE", "The deferment limits are the Registry's.", new DomainRuleViolation.Remedy("The Bursar changes the fee; the Registry changes the limits.", "Registry"));
            jdbc.sql("UPDATE people.deferment_setting SET max_sessions = coalesce(:m, max_sessions), allow_extension = coalesce(:a, allow_extension), reminder_days = coalesce(:r, reminder_days), overdue_after_days = coalesce(:o, overdue_after_days) WHERE id = 1")
                    .param("m", body.maxSessions(), Types.NUMERIC).param("a", body.allowExtension(), Types.BOOLEAN).param("r", body.reminderDays(), Types.INTEGER).param("o", body.overdueAfterDays(), Types.INTEGER).update();
        }
        return settings();
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
}
