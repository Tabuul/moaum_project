package ng.edu.moaum.portal.jupeb;

import java.sql.Types;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
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
 * The JUPEB Office's desk (V339): the applications and their documents, eligibility, returns, admission one by one or in
 * bulk after a preview, screening, classes, the official examination numbers and the Board's results (each imported whole
 * after a preview, a correction stating its reason), the subjects and the approved combinations, and the office's settings.
 * The fees are the Bursary's: this desk reads them and never sets an amount. Every act is a database function under the
 * signed-in officer's attribution, so the audit spine and the candidate's own timeline record it.
 */
@RestController
@RequestMapping("/api/v1/jupeb/office")
class JupebOfficeController {

    static final String READ = "hasAnyAuthority('OFFICE_jupeb','OFFICE_super','OFFICE_admin')";
    static final String WRITE = "hasAnyAuthority('OFFICE_jupeb','OFFICE_super')";

    private final JdbcClient jdbc;
    private final JupebView view;
    private final FileObjects files;

    JupebOfficeController(JdbcClient jdbc, JupebView view, FileObjects files) {
        this.jdbc = jdbc;
        this.view = view;
        this.files = files;
    }

    private static UUID actor() {
        return AuditContextHolder.required().actorId();
    }

    private String sessionOr(String s) {
        return s == null || s.isBlank() ? jdbc.sql("SELECT jupeb.current_session()").query(String.class).single() : s.trim();
    }

    private void requireApp(UUID id) {
        if (!jdbc.sql("SELECT true FROM jupeb.application WHERE id = :id").param("id", id).query(Boolean.class).optional().orElse(false)) {
            throw new NotFound("JUPEB application", id);
        }
    }

    /* ── the dashboard ── */

    @GetMapping("/dashboard")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> dashboard(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", sessions());
        out.put("window", jdbc.sql("SELECT state, opens_at, closes_at FROM policy.window_state('JUPEB_APPLICATION', :s, NULL)").param("s", s).query().singleRow());
        out.put("counts", jdbc.sql("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE created_at >= date_trunc('day', now() AT TIME ZONE 'Africa/Lagos') AT TIME ZONE 'Africa/Lagos') AS today,
                       count(*) FILTER (WHERE fee_confirmed_at IS NOT NULL) AS fee_paid,
                       count(*) FILTER (WHERE state = 'DRAFT') AS draft,
                       count(*) FILTER (WHERE state = 'SUBMITTED') AS submitted,
                       count(*) FILTER (WHERE state = 'RETURNED') AS returned,
                       count(*) FILTER (WHERE state = 'ELIGIBLE') AS eligible,
                       count(*) FILTER (WHERE state = 'INELIGIBLE') AS ineligible,
                       count(*) FILTER (WHERE state = 'PENDING') AS pending,
                       count(*) FILTER (WHERE state = 'NOT_ADMITTED') AS not_admitted,
                       count(*) FILTER (WHERE state IN ('ADMITTED', 'STUDENT', 'COMPLETED')) AS admitted,
                       count(*) FILTER (WHERE state IN ('STUDENT', 'COMPLETED')) AS students,
                       count(*) FILTER (WHERE subjects_registered_at IS NOT NULL) AS registered,
                       count(*) FILTER (WHERE exam_no IS NOT NULL) AS exam_numbers,
                       count(*) FILTER (WHERE state = 'COMPLETED') AS completed,
                       count(*) FILTER (WHERE screening_state IN ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 'CORRECTION_REQUIRED')) AS screening_open
                  FROM jupeb.application WHERE session = :s
                """).param("s", s).query().singleRow());
        out.put("money", jdbc.sql("""
                SELECT kind, count(*) FILTER (WHERE confirmed_at IS NOT NULL) AS paid, coalesce(sum(amount) FILTER (WHERE confirmed_at IS NOT NULL), 0) AS amount
                  FROM jupeb.fee_reference WHERE session = :s GROUP BY kind ORDER BY kind
                """).param("s", s).query().listOfRows());
        out.put("byCombination", jdbc.sql("""
                SELECT c.code, c.name, count(a.id) AS applications, count(a.id) FILTER (WHERE a.state IN ('ADMITTED', 'STUDENT', 'COMPLETED')) AS admitted,
                       count(a.id) FILTER (WHERE a.state IN ('STUDENT', 'COMPLETED')) AS students
                  FROM jupeb.combination c LEFT JOIN jupeb.application a ON a.combination_id = c.id AND a.session = :s
                 GROUP BY c.code, c.name HAVING count(a.id) > 0 OR bool_or(c.active) ORDER BY count(a.id) DESC, c.code
                """).param("s", s).query().listOfRows());
        out.put("byFaculty", jdbc.sql("""
                SELECT f.name AS faculty, count(*) AS applications, count(*) FILTER (WHERE a.state IN ('ADMITTED', 'STUDENT', 'COMPLETED')) AS admitted
                  FROM jupeb.application a JOIN ref.programme g ON g.code = a.programme_code JOIN ref.faculty f ON f.code = g.faculty_code
                 WHERE a.session = :s GROUP BY f.name ORDER BY count(*) DESC
                """).param("s", s).query().listOfRows());
        out.put("tickets", jdbc.sql("SELECT count(*) FROM helpdesk.ticket WHERE queue_code = 'JUPEB_SUPPORT' AND status <> 'CLOSED'").query(Long.class).single());
        out.put("resultsPublished", jdbc.sql("SELECT jupeb.results_published(:s)").param("s", s).query(Boolean.class).single());
        return out;
    }

    private List<Map<String, Object>> sessions() {
        return jdbc.sql("""
                SELECT x.session, (SELECT count(*) FROM jupeb.application a WHERE a.session = x.session) AS applications
                  FROM (SELECT DISTINCT session FROM jupeb.application UNION SELECT jupeb.current_session()) x
                 WHERE x.session IS NOT NULL ORDER BY x.session DESC
                """).query().listOfRows();
    }

    /* ── the applications ── */

    private static final String LIST = """
            SELECT a.id, a.application_no, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, '') AS name, a.sex, a.date_of_birth::text AS date_of_birth, a.phone, a.email,
                   a.nin, a.state_of_origin, a.lga, a.programme_code, g.name AS programme_name, f.name AS faculty_name, c.code AS combination_code, c.name AS combination_name,
                   a.state, a.fee_confirmed_at, a.submitted_at, a.admission_ref, a.admission_decided_at, a.exam_no, a.screening_state, cl.name AS class_name,
                   a.subjects_registered_at, a.activated_at, sf.category AS fee_category, sf.indigene, sf.total AS school_fee, sf.paid AS school_fee_paid,
                   sf.outstanding AS school_fee_outstanding, sf.status AS school_fee_status, a.created_at, count(*) OVER () AS total_rows
              FROM jupeb.application a
              LEFT JOIN ref.programme g ON g.code = a.programme_code
              LEFT JOIN ref.faculty f ON f.code = g.faculty_code
              LEFT JOIN jupeb.combination c ON c.id = a.combination_id
              LEFT JOIN jupeb.class cl ON cl.id = a.class_id
              CROSS JOIN LATERAL jupeb.school_fees(a.id) sf
             WHERE a.session = :s
               AND (:state = '' OR a.state = ANY(string_to_array(:state, ',')))
               AND (:comb = '' OR c.code = :comb)
               AND (:prog = '' OR a.programme_code = :prog)
               AND (:fac = '' OR g.faculty_code = :fac)
               AND (:fee = '' OR (:fee = 'PAID') = (a.fee_confirmed_at IS NOT NULL))
               AND (:screening = '' OR a.screening_state = :screening)
               AND (:q = '' OR a.application_no ILIKE '%' || :q || '%' OR coalesce(a.exam_no, '') ILIKE '%' || :q || '%'
                    OR (a.surname || ' ' || a.first_name || ' ' || coalesce(a.middle_name, '')) ILIKE '%' || :q || '%'
                    OR a.email ILIKE '%' || :q || '%' OR coalesce(a.phone, '') LIKE '%' || :q || '%' OR coalesce(a.nin, '') = :q)
            """;

    @GetMapping("/applications")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> applications(@RequestParam(required = false) String session, @RequestParam(required = false) String state,
                                     @RequestParam(required = false) String combination, @RequestParam(required = false) String programme,
                                     @RequestParam(required = false) String faculty, @RequestParam(required = false) String fee,
                                     @RequestParam(required = false) String screening, @RequestParam(required = false) String q,
                                     @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size,
                                     @RequestParam(defaultValue = "submitted") String sort) {
        String s = sessionOr(session);
        int n = Math.max(1, Math.min(size, 20000));
        String order = switch (sort) {
            case "name" -> "a.surname, a.first_name";
            case "number" -> "a.application_no";
            case "created" -> "a.created_at DESC";
            default -> "a.submitted_at NULLS LAST, a.application_no";
        };
        List<Map<String, Object>> rows = jdbc.sql(LIST + " ORDER BY " + order + " LIMIT :n OFFSET :o")
                .param("s", s).param("state", up(state)).param("comb", up(combination)).param("prog", up(programme)).param("fac", up(faculty))
                .param("fee", up(fee)).param("screening", up(screening)).param("q", q == null ? "" : q.trim())
                .param("n", n).param("o", Math.max(0, page) * n).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("total", total);
        out.put("page", page);
        out.put("size", n);
        out.put("rows", rows);
        return out;
    }

    private static String up(String v) {
        return v == null ? "" : v.trim().toUpperCase();
    }

    @GetMapping("/applications/{id}")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> application(@PathVariable UUID id) {
        return view.of(id, true);
    }

    @GetMapping("/applications/{id}/documents/{kind}/content")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> document(@PathVariable UUID id, @PathVariable String kind) {
        requireApp(id);
        return JupebDocuments.stream(jdbc, files, id, kind);
    }

    public record Review(@NotBlank @Pattern(regexp = "UNDER_REVIEW|VERIFIED|REJECTED|REPLACEMENT_REQUIRED") String status, @Size(max = 600) String note) {
    }

    @PostMapping("/applications/{id}/documents/{kind}/review")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @PathVariable String kind, @Valid @RequestBody Review body) {
        requireApp(id);
        boolean needsNote = Set.of("REJECTED", "REPLACEMENT_REQUIRED").contains(body.status());
        if (needsNote && (body.note() == null || body.note().isBlank())) {
            throw new DomainRuleViolation("JUPEB_REASON", "Say what is wrong with the document, so the candidate can replace it.",
                    new DomainRuleViolation.Remedy("Write the reason and decide again.", "JUPEB Office"));
        }
        int n = jdbc.sql("UPDATE jupeb.document SET status = :st, review_note = :n, reviewed_by = :by, reviewed_at = now() WHERE application_id = :a AND kind = upper(btrim(:k))")
                .param("st", body.status()).param("n", body.note() == null || body.note().isBlank() ? null : body.note().trim(), Types.VARCHAR)
                .param("by", actor()).param("a", id).param("k", kind).update();
        if (n == 0) throw new NotFound("document", kind);
        String label = jdbc.sql("SELECT label FROM jupeb.document_kind WHERE code = upper(btrim(:k))").param("k", kind).query(String.class).single();
        jdbc.sql("SELECT jupeb.app_event(:a, :kind, :note)").param("a", id).param("kind", "DOCUMENT_" + body.status())
                .param("note", label + (body.note() == null || body.note().isBlank() ? "" : " — " + body.note().trim())).query().listOfRows();
        if (needsNote) {
            jdbc.sql("SELECT jupeb.tell(:a, :s, :b)").param("a", id).param("s", "A JUPEB document needs replacing")
                    .param("b", "The JUPEB Office could not accept your " + label + ": " + body.note().trim() + " Sign in and upload it again.").query().listOfRows();
        }
        return view.of(id, true);
    }

    public record Eligibility(@NotNull Boolean eligible, @Size(max = 1000) String note) {
    }

    @PostMapping("/applications/{id}/eligibility")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> eligibility(@PathVariable UUID id, @Valid @RequestBody Eligibility body) {
        requireApp(id);
        jdbc.sql("SELECT jupeb.decide_eligibility(:a, :e, :n, :by)").param("a", id).param("e", body.eligible()).param("n", body.note(), Types.VARCHAR).param("by", actor()).query().listOfRows();
        return view.of(id, true);
    }

    public record Note(@NotBlank @Size(max = 1000) String note) {
    }

    @PostMapping("/applications/{id}/return")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> returnIt(@PathVariable UUID id, @Valid @RequestBody Note body) {
        requireApp(id);
        jdbc.sql("SELECT jupeb.return_application(:a, :n, :by)").param("a", id).param("n", body.note()).param("by", actor()).query().listOfRows();
        return view.of(id, true);
    }

    public record Decision(@NotBlank @Pattern(regexp = "ADMITTED|NOT_ADMITTED|PENDING") String decision, @Size(max = 1000) String note) {
    }

    @PostMapping("/applications/{id}/admission")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> admission(@PathVariable UUID id, @Valid @RequestBody Decision body) {
        requireApp(id);
        jdbc.sql("SELECT jupeb.decide_admission(:a, :d, :n, :by)").param("a", id).param("d", body.decision()).param("n", body.note(), Types.VARCHAR).param("by", actor()).query(String.class).single();
        return view.of(id, true);
    }

    public record Bulk(@NotNull @Size(min = 1, max = 2000) List<UUID> ids, @NotBlank @Pattern(regexp = "ADMITTED|NOT_ADMITTED|PENDING") String decision,
                       @Size(max = 1000) String note, boolean commit) {
    }

    /** admission for many: the preview says what each would become; the commit decides those that can be decided and lists the rest */
    @PostMapping("/admission/bulk")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> bulk(@Valid @RequestBody Bulk body) {
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM jupeb.bulk_admission(:ids, :d, :n, :by, :c)")
                .param("ids", body.ids().toArray(UUID[]::new)).param("d", body.decision()).param("n", body.note(), Types.VARCHAR).param("by", actor()).param("c", body.commit())
                .query().listOfRows();
        long ok = rows.stream().filter(r -> Boolean.TRUE.equals(r.get("ok"))).count();
        return Map.of("rows", rows, "ok", ok, "skipped", rows.size() - ok, "committed", body.commit(), "decision", body.decision());
    }

    public record Screening(@NotBlank @Pattern(regexp = "SCHEDULED|IN_PROGRESS|CLEARED|NOT_CLEARED|CORRECTION_REQUIRED") String decision,
                            @Size(max = 1000) String reason, @Size(max = 200) String venue, OffsetDateTime at) {
    }

    @PostMapping("/applications/{id}/screening")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> screening(@PathVariable UUID id, @Valid @RequestBody Screening body) {
        requireApp(id);
        jdbc.sql("SELECT jupeb.decide_screening(:a, :d, :r, :v, :at, :by)").param("a", id).param("d", body.decision()).param("r", body.reason(), Types.VARCHAR)
                .param("v", body.venue(), Types.VARCHAR).param("at", body.at(), Types.TIMESTAMP_WITH_TIMEZONE).param("by", actor()).query(String.class).single();
        if (Set.of("SCHEDULED", "NOT_CLEARED", "CORRECTION_REQUIRED", "CLEARED").contains(body.decision())) {
            String subject = switch (body.decision()) {
                case "SCHEDULED" -> "Your JUPEB screening is scheduled";
                case "CLEARED" -> "You are cleared at JUPEB screening";
                default -> "Your JUPEB screening needs your attention";
            };
            jdbc.sql("SELECT jupeb.tell(:a, :s, :b)").param("a", id).param("s", subject)
                    .param("b", "Sign in to the JUPEB portal for the details of your screening." + (body.reason() == null || body.reason().isBlank() ? "" : " " + body.reason().trim()))
                    .query().listOfRows();
        }
        return view.of(id, true);
    }

    /* ── classes ── */

    @GetMapping("/classes")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> classes(@RequestParam(required = false) String session) {
        return jdbc.sql("""
                SELECT cl.id, cl.session, cl.name, cl.capacity, c.code AS combination_code, c.name AS combination_name,
                       (SELECT count(*) FROM jupeb.application a WHERE a.class_id = cl.id) AS members
                  FROM jupeb.class cl LEFT JOIN jupeb.combination c ON c.id = cl.combination_id
                 WHERE cl.session = :s ORDER BY cl.name
                """).param("s", sessionOr(session)).query().listOfRows();
    }

    public record ClassIn(@NotBlank String session, @NotBlank @Size(max = 80) String name, UUID combinationId, Integer capacity) {
    }

    @PostMapping("/classes")
    @PreAuthorize(WRITE)
    @Transactional
    List<Map<String, Object>> addClass(@Valid @RequestBody ClassIn body) {
        if (body.capacity() != null && body.capacity() < 1) {
            throw new DomainRuleViolation("JUPEB_CAPACITY", "A class holds at least one student.", new DomainRuleViolation.Remedy("Give a capacity of one or more, or leave it blank.", "JUPEB Office"));
        }
        try {
            jdbc.sql("INSERT INTO jupeb.class (session, name, combination_id, capacity, created_by) VALUES (:s, :n, :c, :cap, :by)")
                    .param("s", body.session().trim()).param("n", body.name().trim()).param("c", body.combinationId(), Types.OTHER)
                    .param("cap", body.capacity(), Types.INTEGER).param("by", actor()).update();
        } catch (org.springframework.dao.DuplicateKeyException twice) {
            throw new DomainRuleViolation("JUPEB_CLASS_EXISTS", "There is already a class " + body.name().trim() + " in " + body.session() + ".",
                    new DomainRuleViolation.Remedy("Give the class another name.", "JUPEB Office"));
        }
        return classes(body.session());
    }

    public record Placement(UUID classId) {
    }

    @PostMapping("/applications/{id}/class")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> place(@PathVariable UUID id, @RequestBody Placement body) {
        requireApp(id);
        Map<String, Object> a = jdbc.sql("SELECT state, session, combination_id FROM jupeb.application WHERE id = :id FOR UPDATE").param("id", id).query().singleRow();
        if (!Set.of("STUDENT", "COMPLETED").contains(String.valueOf(a.get("state")))) {
            throw new DomainRuleViolation("JUPEB_NOT_STUDENT", "A class takes an active JUPEB student.",
                    new DomainRuleViolation.Remedy("Place the candidate once their school fee activates them.", "JUPEB Office"));
        }
        if (body.classId() != null) {
            Map<String, Object> c = jdbc.sql("SELECT session, combination_id, capacity, (SELECT count(*) FROM jupeb.application x WHERE x.class_id = cl.id AND x.id <> :a) AS members FROM jupeb.class cl WHERE id = :c FOR UPDATE")
                    .param("a", id).param("c", body.classId()).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("class", body.classId()));
            if (!String.valueOf(c.get("session")).equals(a.get("session"))) {
                throw new DomainRuleViolation("JUPEB_CLASS_SESSION", "That class is for another session.", new DomainRuleViolation.Remedy("Choose a class of the candidate's session.", "JUPEB Office"));
            }
            if (c.get("combination_id") != null && !c.get("combination_id").equals(a.get("combination_id"))) {
                throw new DomainRuleViolation("JUPEB_CLASS_COMBINATION", "That class is for another combination.", new DomainRuleViolation.Remedy("Choose a class of the candidate's combination.", "JUPEB Office"));
            }
            if (c.get("capacity") != null && ((Number) c.get("members")).intValue() >= ((Number) c.get("capacity")).intValue()) {
                throw new DomainRuleViolation("JUPEB_CLASS_FULL", "That class is full.", new DomainRuleViolation.Remedy("Choose another class or raise its capacity.", "JUPEB Office"));
            }
        }
        jdbc.sql("UPDATE jupeb.application SET class_id = :c WHERE id = :id").param("c", body.classId(), Types.OTHER).param("id", id).update();
        jdbc.sql("SELECT jupeb.app_event(:a, 'CLASS', :n)").param("a", id)
                .param("n", body.classId() == null ? "Removed from class" : "Placed in " + jdbc.sql("SELECT name FROM jupeb.class WHERE id = :c").param("c", body.classId()).query(String.class).single())
                .query().listOfRows();
        return view.of(id, true);
    }

    /* ── the official examination numbers ── */

    public record ExamNo(@NotBlank @Size(max = 40) String examNo, @Size(max = 600) String reason) {
    }

    @PostMapping("/applications/{id}/exam-no")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> examNo(@PathVariable UUID id, @Valid @RequestBody ExamNo body) {
        requireApp(id);
        jdbc.sql("SELECT jupeb.set_exam_no(:a, :n, :r, 'DESK', NULL)").param("a", id).param("n", body.examNo()).param("r", body.reason(), Types.VARCHAR).query(String.class).single();
        return view.of(id, true);
    }

    public record ImportIn(@NotNull @Size(max = 20000) List<Map<String, Object>> rows, boolean commit, @Size(max = 200) String fileName) {
    }

    private Object runImport(String fn, ImportIn body) {
        tools.jackson.databind.ObjectMapper m = new tools.jackson.databind.ObjectMapper();
        String result = jdbc.sql("SELECT " + fn + "(:rows::jsonb, :c, :f, :by)::text").param("rows", m.writeValueAsString(body.rows())).param("c", body.commit())
                .param("f", body.fileName(), Types.VARCHAR).param("by", actor()).query(String.class).single();
        return m.readValue(result, Object.class);
    }

    /** the Board's examination numbers, matched by application number: a preview, then a commit that writes nothing while a row is invalid */
    @PostMapping("/exam-numbers/import")
    @PreAuthorize(WRITE)
    @Transactional
    Object importExamNumbers(@Valid @RequestBody ImportIn body) {
        return runImport("jupeb.import_exam_numbers", body);
    }

    /* ── results ── */

    @PostMapping("/results/import")
    @PreAuthorize(WRITE)
    @Transactional
    Object importResults(@Valid @RequestBody ImportIn body) {
        return runImport("jupeb.import_results", body);
    }

    @GetMapping("/results")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> results(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("published", jdbc.sql("SELECT results_published_at FROM jupeb.setting WHERE session = :s").param("s", s).query().listOfRows().stream().findFirst()
                .map(r -> r.get("results_published_at")).orElse(null));
        out.put("rows", jdbc.sql("""
                SELECT a.id, a.application_no, a.exam_no, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, '') AS name, c.code AS combination_code, a.state,
                       string_agg(s.code || ' ' || coalesce(r.grade, '—'), ' · ' ORDER BY s.code) AS grades,
                       sum(r.points) AS points, count(r.id) AS graded, count(sr.id) AS registered
                  FROM jupeb.application a JOIN jupeb.subject_registration sr ON sr.application_id = a.id JOIN jupeb.subject s ON s.id = sr.subject_id
                  LEFT JOIN jupeb.result r ON r.application_id = a.id AND r.subject_id = sr.subject_id
                  LEFT JOIN jupeb.combination c ON c.id = a.combination_id
                 WHERE a.session = :s
                 GROUP BY a.id, c.code ORDER BY a.exam_no NULLS LAST, a.application_no
                """).param("s", s).query().listOfRows());
        return out;
    }

    public record Publish(@NotBlank String session) {
    }

    @PostMapping("/results/publish")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> publish(@Valid @RequestBody Publish body) {
        int n = jdbc.sql("SELECT jupeb.publish_results(:s, :by)").param("s", body.session().trim()).param("by", actor()).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(results(body.session()));
        out.put("completed", n);
        return out;
    }

    @GetMapping("/batches")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> batches() {
        return jdbc.sql("""
                SELECT b.ref, b.kind, b.file_name, b.rows, b.applied, b.result::text AS result, b.imported_at, p.surname || ', ' || p.given_names AS imported_by
                  FROM jupeb.import_batch b LEFT JOIN iam.person p ON p.id = b.imported_by ORDER BY b.imported_at DESC LIMIT 200
                """).query().listOfRows();
    }

    /* ── subjects and the approved combinations ── */

    @GetMapping("/subjects")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> subjects() {
        return jdbc.sql("""
                SELECT s.id, s.code, s.title, s.description, s.active,
                       (SELECT count(*) FROM jupeb.combination c WHERE s.id IN (c.subject1, c.subject2, c.subject3)) AS combinations
                  FROM jupeb.subject s ORDER BY s.title
                """).query().listOfRows();
    }

    public record SubjectIn(@NotBlank @Size(max = 40) String code, @NotBlank @Size(max = 160) String title, @Size(max = 600) String description, Boolean active) {
    }

    @PostMapping("/subjects")
    @PreAuthorize(WRITE)
    @Transactional
    List<Map<String, Object>> saveSubject(@Valid @RequestBody SubjectIn body) {
        String code = body.code().trim().toUpperCase();
        if (!code.matches("^[A-Z0-9][A-Z0-9 /&-]{1,39}$")) {
            throw new DomainRuleViolation("JUPEB_SUBJECT_CODE", "A subject code is letters, digits, spaces, / & or -, at most 40.",
                    new DomainRuleViolation.Remedy("Use the subject's code as the University writes it.", "JUPEB Office"));
        }
        jdbc.sql("""
                INSERT INTO jupeb.subject (code, title, description, active, created_by, updated_by) VALUES (:c, :t, :d, coalesce(:a, true), :by, :by)
                ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, description = EXCLUDED.description, active = coalesce(:a, jupeb.subject.active),
                       updated_by = :by, updated_at = now()
                """).param("c", code).param("t", body.title().trim()).param("d", body.description(), Types.VARCHAR).param("a", body.active(), Types.BOOLEAN)
                .param("by", actor()).update();
        return subjects();
    }

    @GetMapping("/combinations")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> combinations() {
        return view.combinations(false);
    }

    /** one combination, entered on the desk: the same judgement the import makes, for one row */
    @PostMapping("/combinations")
    @PreAuthorize(WRITE)
    @Transactional
    Object saveCombination(@RequestBody Map<String, Object> row) {
        Map<String, Object> r = new LinkedHashMap<>(row);
        r.put("row", 1);
        return runImport("jupeb.import_combinations", new ImportIn(List.of(r), true, null));
    }

    @PostMapping("/combinations/import")
    @PreAuthorize(WRITE)
    @Transactional
    Object importCombinations(@Valid @RequestBody ImportIn body) {
        return runImport("jupeb.import_combinations", body);
    }

    /* ── the office's settings: numbering, screening, the documents asked for ── */

    @GetMapping("/settings")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> settings(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", sessions());
        out.put("own", jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.setting WHERE session = :s)").param("s", s).query(Boolean.class).single());
        out.put("setting", jdbc.sql("""
                SELECT application_prefix, screening_required, screening_venue, screening_starts_on::text AS screening_starts_on, screening_ends_on::text AS screening_ends_on,
                       screening_instructions, results_published_at
                  FROM jupeb.setting_of(:s)
                """).param("s", s).query().singleRow());
        out.put("documentKinds", jdbc.sql("SELECT code, label, required, image, active, ord FROM jupeb.document_kind ORDER BY ord, label").query().listOfRows());
        out.put("fees", jdbc.sql("SELECT application_fee, first_percent, allow_full, activation, indigene_state FROM jupeb.fee_setting_of(:s)").param("s", s).query().singleRow());
        return out;
    }

    public record SettingIn(@NotBlank String session, @NotBlank @Pattern(regexp = "^[A-Z][A-Z0-9/-]{1,20}$") String applicationPrefix,
                            boolean screeningRequired, @Size(max = 200) String screeningVenue, LocalDate screeningStartsOn, LocalDate screeningEndsOn,
                            @Size(max = 2000) String screeningInstructions) {
    }

    @PutMapping("/settings")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> saveSettings(@Valid @RequestBody SettingIn b) {
        String s = b.session().trim();
        if (!"*".equals(s) && !s.matches("^\\d{4}/\\d{4}$")) throw new NotFound("session", s);
        if (b.screeningStartsOn() != null && b.screeningEndsOn() != null && b.screeningEndsOn().isBefore(b.screeningStartsOn())) {
            throw new DomainRuleViolation("JUPEB_SCREENING_DATES", "Screening ends before it starts.", new DomainRuleViolation.Remedy("Correct the dates.", "JUPEB Office"));
        }
        jdbc.sql("""
                INSERT INTO jupeb.setting (session, application_prefix, screening_required, screening_venue, screening_starts_on, screening_ends_on, screening_instructions, updated_by)
                VALUES (:s, :p, :r, :v, :a, :e, :i, :by)
                ON CONFLICT (session) DO UPDATE SET application_prefix = EXCLUDED.application_prefix, screening_required = EXCLUDED.screening_required,
                       screening_venue = EXCLUDED.screening_venue, screening_starts_on = EXCLUDED.screening_starts_on, screening_ends_on = EXCLUDED.screening_ends_on,
                       screening_instructions = EXCLUDED.screening_instructions, updated_by = EXCLUDED.updated_by, updated_at = now()
                """).param("s", s).param("p", b.applicationPrefix()).param("r", b.screeningRequired()).param("v", b.screeningVenue(), Types.VARCHAR)
                .param("a", b.screeningStartsOn(), Types.DATE).param("e", b.screeningEndsOn(), Types.DATE).param("i", b.screeningInstructions(), Types.VARCHAR)
                .param("by", actor()).update();
        return settings("*".equals(s) ? null : s);
    }

    public record DocumentKindIn(@NotBlank @Pattern(regexp = "^[A-Z][A-Z0-9_]{1,30}$") String code, @NotBlank @Size(max = 120) String label,
                                 boolean required, boolean image, boolean active, Integer ord) {
    }

    @PostMapping("/document-kinds")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> saveDocumentKind(@Valid @RequestBody DocumentKindIn b) {
        jdbc.sql("""
                INSERT INTO jupeb.document_kind (code, label, required, image, active, ord) VALUES (:c, :l, :r, :i, :a, coalesce(:o, 100))
                ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label, required = EXCLUDED.required, image = EXCLUDED.image, active = EXCLUDED.active,
                       ord = coalesce(:o, jupeb.document_kind.ord)
                """).param("c", b.code()).param("l", b.label().trim()).param("r", b.required()).param("i", b.image()).param("a", b.active()).param("o", b.ord(), Types.INTEGER).update();
        return settings(null);
    }
}
