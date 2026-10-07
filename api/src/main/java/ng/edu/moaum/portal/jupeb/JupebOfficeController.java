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
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
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
    private final String portalUrl;
    private final tools.jackson.databind.ObjectMapper json;

    JupebOfficeController(JdbcClient jdbc, JupebView view, FileObjects files, tools.jackson.databind.ObjectMapper json,
                          @org.springframework.beans.factory.annotation.Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.jdbc = jdbc;
        this.view = view;
        this.files = files;
        this.json = json;
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
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
        out.put("checkingWindow", jdbc.sql("SELECT state, opens_at, closes_at FROM policy.window_state('JUPEB_ADMISSION_STATUS_CHECKING', :s, NULL)").param("s", s).query().singleRow());
        out.put("feeRule", jdbc.sql("SELECT application_fee, checking_fee, acceptance_fee, first_percent FROM jupeb.fee_setting_of(:s)").param("s", s).query().singleRow());
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
                       count(*) FILTER (WHERE screening_state IN ('PENDING', 'SCHEDULED', 'IN_PROGRESS', 'CORRECTION_REQUIRED')) AS screening_open,
                       count(*) FILTER (WHERE screening_state = 'CLEARED') AS screening_cleared,
                       count(*) FILTER (WHERE jupeb.paid_at(id, 'STATUS_CHECKING') IS NOT NULL) AS checking_paid,
                       count(*) FILTER (WHERE jupeb.paid_at(id, 'ACCEPTANCE') IS NOT NULL) AS accepted,
                       count(*) FILTER (WHERE stream = 'SCIENCE') AS science,
                       count(*) FILTER (WHERE stream IN ('NON_SCIENCE', 'ARTS')) AS non_science,
                       count(*) FILTER (WHERE state = 'DEFERRED') AS deferred,
                       count(*) FILTER (WHERE state = 'WITHDRAWN') AS withdrawn,
                       (SELECT count(*) FROM jupeb.change_request r WHERE r.state = 'PENDING') AS requests_pending,
                       (SELECT count(DISTINCT st.member_ref) FROM attendance.jupeb_standing(:s) st WHERE st.verdict = 'NOT_ELIGIBLE') AS attendance_below,
                       (SELECT count(DISTINCT st.member_ref) FROM attendance.jupeb_standing(:s) st WHERE st.at_risk) AS attendance_at_risk
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
                 GROUP BY c.id, c.code, c.name HAVING count(a.id) > 0 OR jupeb.combination_offered(c.id) ORDER BY count(a.id) DESC, c.code
                """).param("s", s).query().listOfRows());
        out.put("byStream", jdbc.sql("""
                SELECT CASE WHEN a.stream = 'SCIENCE' THEN 'Science' WHEN a.stream IN ('NON_SCIENCE', 'ARTS') THEN 'Non-Science' ELSE 'Not stated' END AS stream, count(*) AS applications,
                       count(*) FILTER (WHERE a.state IN ('ADMITTED', 'STUDENT', 'COMPLETED')) AS admitted,
                       count(*) FILTER (WHERE a.state IN ('STUDENT', 'COMPLETED')) AS students
                  FROM jupeb.application a WHERE a.session = :s GROUP BY 1 ORDER BY count(*) DESC
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
                   a.nin, a.state_of_origin, a.lga, a.stream, a.programme_code, g.name AS programme_name, f.name AS faculty_name, c.code AS combination_code, c.name AS combination_name,
                   a.state, a.fee_confirmed_at, a.submitted_at, a.admission_ref, a.admission_decided_at, a.exam_no, a.screening_state, cl.name AS class_name,
                   a.subjects_registered_at, a.activated_at, sf.category AS fee_category, sf.indigene, sf.total AS school_fee, sf.paid AS school_fee_paid,
                   sf.outstanding AS school_fee_outstanding, sf.status AS school_fee_status, a.created_at,
                   jupeb.paid_at(a.id, 'STATUS_CHECKING') AS checking_paid_at, jupeb.paid_at(a.id, 'ACCEPTANCE') AS accepted_at, count(*) OVER () AS total_rows
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
               AND (:stream = '' OR a.stream = :stream)
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
                                     @RequestParam(required = false) String stream,
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
                .param("fee", up(fee)).param("screening", up(screening)).param("stream", up(stream)).param("q", q == null ? "" : q.trim())
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
    ResponseEntity<byte[]> document(@PathVariable UUID id, @PathVariable String kind, @RequestParam(required = false) Integer sitting,
                                    @RequestParam(required = false) String format) {
        requireApp(id);
        String k = kind.trim().toUpperCase();
        return JupebDocuments.stream(jdbc, files, id, k, "OLEVEL_RESULT".equals(k) ? (sitting == null ? 1 : sitting) : null, "jpeg".equalsIgnoreCase(format));
    }

    public record Review(@NotBlank @Pattern(regexp = "UNDER_REVIEW|VERIFIED|REJECTED|REPLACEMENT_REQUIRED") String status, @Size(max = 600) String note) {
    }

    @PostMapping("/applications/{id}/documents/{kind}/review")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @PathVariable String kind, @RequestParam(required = false) Integer sitting, @Valid @RequestBody Review body) {
        requireApp(id);
        boolean needsNote = Set.of("REJECTED", "REPLACEMENT_REQUIRED").contains(body.status());
        if (needsNote && (body.note() == null || body.note().isBlank())) {
            throw new DomainRuleViolation("JUPEB_REASON", "Say what is wrong with the document, so the candidate can replace it.",
                    new DomainRuleViolation.Remedy("Write the reason and decide again.", "JUPEB Office"));
        }
        Integer sit = "OLEVEL_RESULT".equalsIgnoreCase(kind.trim()) ? (sitting == null ? 1 : sitting) : null;
        int n = jdbc.sql("UPDATE jupeb.document SET status = :st, review_note = :n, reviewed_by = :by, reviewed_at = now() WHERE application_id = :a AND kind = upper(btrim(:k)) AND coalesce(sitting, 0) = coalesce(:s, 0)")
                .param("st", body.status()).param("n", body.note() == null || body.note().isBlank() ? null : body.note().trim(), Types.VARCHAR)
                .param("by", actor()).param("a", id).param("k", kind).param("s", sit, Types.INTEGER).update();
        if (n == 0) throw new NotFound("document", kind);
        String label = jdbc.sql("SELECT label FROM jupeb.document_kind WHERE code = upper(btrim(:k))").param("k", kind).query(String.class).single()
                + (sit == null ? "" : sit == 1 ? " (first sitting)" : " (second sitting)");
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
    /**
     * The list sent to the Board for examination numbers: every active student of the session whose three subjects are
     * registered (the Board examines those), without a number yet or everyone; with how many students have still to register.
     * Its columns match the examination-number upload, so the list the Board returns with the numbers can be uploaded as it is.
     */
    @GetMapping("/exam-number-list")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> examNumberList(@RequestParam(required = false) String session, @RequestParam(defaultValue = "pending") String which) {
        String s = sessionOr(session);
        boolean all = "all".equalsIgnoreCase(which.trim());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("which", all ? "all" : "pending");
        out.put("notRegistered", jdbc.sql("SELECT count(*) FROM jupeb.application WHERE session = :s AND state = 'STUDENT' AND subjects_registered_at IS NULL")
                .param("s", s).query(Long.class).single());
        out.put("rows", jdbc.sql("""
                SELECT a.id, a.application_no, a.surname, a.first_name, a.middle_name, a.sex, a.date_of_birth::text AS date_of_birth, a.phone, a.email,
                       a.state_of_origin, a.lga, a.nin, a.stream, c.code AS combination_code, cl.name AS class_name, a.exam_no,
                       (SELECT coalesce(array_agg(sj.code ORDER BY sj.code), '{}') FROM jupeb.subject_registration r JOIN jupeb.subject sj ON sj.id = r.subject_id
                         WHERE r.application_id = a.id) AS subject_codes,
                       (SELECT coalesce(array_agg(sj.title ORDER BY sj.code), '{}') FROM jupeb.subject_registration r JOIN jupeb.subject sj ON sj.id = r.subject_id
                         WHERE r.application_id = a.id) AS subject_titles
                  FROM jupeb.application a
                  LEFT JOIN jupeb.combination c ON c.id = a.combination_id
                  LEFT JOIN jupeb.class cl ON cl.id = a.class_id
                 WHERE a.session = :s AND a.state IN ('STUDENT', 'COMPLETED') AND a.subjects_registered_at IS NOT NULL AND (:all OR a.exam_no IS NULL)
                 ORDER BY c.code NULLS LAST, a.surname, a.first_name
                """).param("s", s).param("all", all).query().listOfRows());
        return out;
    }

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

    public record Unit(@NotBlank @Pattern(regexp = "^[A-Za-z]{2,5} ?[0-9]{3}$", message = "a code like BIO 001") String code, @NotBlank @Size(max = 160) String title) {
    }

    public record Units(@NotNull @Size(max = 12) List<@Valid Unit> units) {
    }

    /** a subject's course units (BIO 001: General Biology …), printed in the note of the statement of result (V342) */
    @GetMapping("/subjects/{code}/units")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> units(@PathVariable String code) {
        return jdbc.sql("""
                SELECT u.code, u.title, u.ord FROM jupeb.subject_unit u JOIN jupeb.subject s ON s.id = u.subject_id
                 WHERE upper(s.code) = upper(btrim(:c)) ORDER BY u.ord, u.code
                """).param("c", code).query().listOfRows();
    }

    @PutMapping("/subjects/{code}/units")
    @PreAuthorize(WRITE)
    @Transactional
    List<Map<String, Object>> saveUnits(@PathVariable String code, @Valid @RequestBody Units body) {
        UUID subject = jdbc.sql("SELECT id FROM jupeb.subject WHERE upper(code) = upper(btrim(:c))").param("c", code).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("JUPEB subject", code));
        Set<String> seen = new java.util.HashSet<>();
        for (Unit u : body.units()) {
            if (!seen.add(u.code().trim().toUpperCase().replaceAll("\\s+", " "))) {
                throw new DomainRuleViolation("JUPEB_UNIT_TWICE", u.code() + " appears twice.", new DomainRuleViolation.Remedy("List each course unit once.", "JUPEB Office"));
            }
        }
        jdbc.sql("DELETE FROM jupeb.subject_unit WHERE subject_id = :s").param("s", subject).update();
        int ord = 1;
        for (Unit u : body.units()) {
            String c = u.code().trim().toUpperCase().replaceAll("^([A-Z]+) ?([0-9]{3})$", "$1 $2");
            jdbc.sql("INSERT INTO jupeb.subject_unit (subject_id, code, title, ord) VALUES (:s, :c, :t, :o)").param("s", subject).param("c", c).param("t", u.title().trim()).param("o", ord++).update();
        }
        return units(code);
    }

    @GetMapping("/combinations")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> combinations() {
        return view.combinations(false);
    }

    public record OfferedIn(@NotNull @Size(min = 1, max = 100) List<@NotBlank @Size(max = 40) String> codes, boolean offered, @Size(max = 500) String reason) {
    }

    /** V342: the JUPEB Office disables the subjects or combinations the University does not offer, and reactivates them —
     *  nothing is deleted; a candidate holding a combination that stops being offered, before registering, is told */
    @PostMapping("/{kind:subjects|combinations}/offered")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> setOffered(@PathVariable String kind, @Valid @RequestBody OfferedIn body) {
        String why = body.reason() == null || body.reason().isBlank() ? null : body.reason().trim();
        jdbc.sql("SELECT set_config('moaum.reason', :r, true)")
                .param("r", (body.offered() ? "JUPEB: offered again" : "JUPEB: not offered") + (why == null ? "" : ": " + why)).query().listOfRows();
        Map<String, Object> r = jdbc.sql("SELECT changed, told FROM jupeb.set_offered(:k, :c, :o, :by)")
                .param("k", "subjects".equals(kind) ? "SUBJECT" : "COMBINATION").param("c", body.codes().toArray(String[]::new))
                .param("o", body.offered()).param("by", actor()).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("subjects", subjects());
        out.put("combinations", view.combinations(false));
        return out;
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

    /* ── verifiable papers (V343) ── */

    public record PaperIn(@NotBlank @Pattern(regexp = "RESULT|ADMISSION_LETTER|ACCEPTANCE_LETTER|STATUS_SLIP|REGISTRATION_SLIP|ACKNOWLEDGEMENT|RECEIPT") String kind,
                          @Size(max = 60) String reference) {
    }

    /** the code for a paper the office prints; the same code while the record it states is unchanged */
    @PostMapping("/applications/{id}/papers")
    @PreAuthorize(READ)
    @Transactional
    Map<String, Object> paper(@PathVariable UUID id, @Valid @RequestBody PaperIn body) {
        requireApp(id);
        String code = jdbc.sql("SELECT jupeb.issue_paper(:a, :k, :r, true, :by, nullif(current_setting('moaum.actor_office', true), ''))").param("a", id)
                .param("k", body.kind()).param("r", body.reference(), Types.VARCHAR).param("by", actor()).query(String.class).single();
        return Map.of("code", code, "kind", body.kind());
    }

    public record RevokeIn(@NotBlank @Size(max = 600) String reason) {
    }

    /** a paper issued in error stops verifying; the reason is kept and the candidate's trail says so */
    @PostMapping("/papers/{code}/revoke")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> revoke(@PathVariable String code, @Valid @RequestBody RevokeIn body) {
        jdbc.sql("SELECT jupeb.revoke_paper(:c, :r, :by)").param("c", code).param("r", body.reason()).param("by", actor()).query().listOfRows();
        UUID app = jdbc.sql("SELECT application_id FROM jupeb.paper WHERE code = upper(btrim(:c))").param("c", code).query(UUID.class).single();
        return view.of(app, true);
    }

    /* ── change requests after submission (V343) ── */

    @GetMapping("/requests")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> requests(@RequestParam(required = false) String state, @RequestParam(required = false) String session) {
        String st = state == null ? "PENDING" : state.trim().toUpperCase();
        return jdbc.sql("""
                SELECT r.id, r.kind, r.state, jupeb.change_words(r.id) AS words, r.reason, r.requested_at, r.requested_office, r.decided_at, r.decision_note,
                       a.id AS application_id, a.application_no, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, '') AS name,
                       a.state AS application_state, a.session
                  FROM jupeb.change_request r JOIN jupeb.application a ON a.id = r.application_id
                 WHERE (:st = 'ALL' OR r.state = :st) AND (:s = '' OR a.session = :s OR r.from_session = :s)
                 ORDER BY r.requested_at DESC LIMIT 500
                """).param("st", st).param("s", session == null ? "" : session.trim()).query().listOfRows();
    }

    public record ChangeIn(@NotBlank @Pattern(regexp = "WITHDRAW|DEFER|CHANGE_COMBINATION|CHANGE_PROGRAMME") String kind, @Size(max = 20) String stream,
                           @Size(max = 60) String combination, @Size(max = 9) String toSession, @NotBlank @Size(max = 1000) String reason) {
    }

    /** a request raised at the desk for the candidate, decided like any other */
    @PostMapping("/applications/{id}/requests")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> raise(@PathVariable UUID id, @Valid @RequestBody ChangeIn body) {
        requireApp(id);
        jdbc.sql("SELECT jupeb.request_change(:a, :k, :s, :c, :t, :r, :by, nullif(current_setting('moaum.actor_office', true), ''))").param("a", id)
                .param("k", body.kind()).param("s", body.stream(), Types.VARCHAR).param("c", body.combination(), Types.VARCHAR)
                .param("t", body.toSession(), Types.VARCHAR).param("r", body.reason()).param("by", actor()).query(UUID.class).single();
        return view.of(id, true);
    }

    public record DecideIn(boolean approve, @Size(max = 1000) String note) {
    }

    @PostMapping("/requests/{id}/decide")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        UUID app = jdbc.sql("SELECT application_id FROM jupeb.change_request WHERE id = :id").param("id", id).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("JUPEB change request", id));
        jdbc.sql("SELECT jupeb.decide_change(:r, :ok, :n, :by, nullif(current_setting('moaum.actor_office', true), ''))").param("r", id).param("ok", body.approve())
                .param("n", body.note(), Types.VARCHAR).param("by", actor()).query().listOfRows();
        return view.of(app, true);
    }

    /** a deferred admission resumed in the session it was deferred to */
    @PostMapping("/applications/{id}/resume")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> resume(@PathVariable UUID id) {
        requireApp(id);
        jdbc.sql("SELECT jupeb.resume_deferment(:a, :by)").param("a", id).param("by", actor()).query().listOfRows();
        return view.of(id, true);
    }

    /* ── reminders (V343): the rules, who is due, and sending now ── */

    @GetMapping("/reminders")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> reminders() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rules", jdbc.sql("""
                SELECT r.kind, r.enabled, r.first_after_days, r.every_days, r.max_count, r.sms, r.updated_at,
                       (SELECT count(*) FROM jupeb.reminder_log l WHERE l.kind = r.kind AND l.sent_at > now() - interval '30 days') AS sent_30_days,
                       (SELECT max(l.sent_at) FROM jupeb.reminder_log l WHERE l.kind = r.kind) AS last_sent
                  FROM jupeb.reminder_rule r ORDER BY r.ord
                """).query().listOfRows());
        out.put("dueNow", jdbc.sql("SELECT kind, count(*) AS candidates FROM jupeb.due_reminders(now()) GROUP BY kind").query().listOfRows());
        return out;
    }

    @GetMapping("/reminders/due")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> due() {
        return jdbc.sql("SELECT application_id, application_no, name, kind, sent_before, last_sent FROM jupeb.due_reminders(now()) LIMIT 1000").query().listOfRows();
    }

    public record RuleIn(boolean enabled, @Min(0) @Max(60) int firstAfterDays, @Min(1) @Max(60) int everyDays, @Min(1) @Max(10) int maxCount, boolean sms) {
    }

    @PutMapping("/reminders/{kind}")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> saveRule(@PathVariable String kind, @Valid @RequestBody RuleIn body) {
        int n = jdbc.sql("""
                UPDATE jupeb.reminder_rule SET enabled = :e, first_after_days = :f, every_days = :v, max_count = :m, sms = :s, updated_by = :by, updated_at = now()
                 WHERE kind = upper(btrim(:k))
                """).param("e", body.enabled()).param("f", body.firstAfterDays()).param("v", body.everyDays()).param("m", body.maxCount())
                .param("s", body.sms()).param("by", actor()).param("k", kind).update();
        if (n == 0) throw new NotFound("JUPEB reminder", kind);
        return reminders();
    }

    /** send what is due now, without waiting for the morning run */
    @PostMapping("/reminders/run")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> runReminders() {
        String sent = jdbc.sql("SELECT jupeb.send_reminders(now(), :p, 500, 'OFFICE')::text").param("p", portalUrl).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(reminders());
        out.put("result", sent);
        return out;
    }

    /* ── the students already registered on the old portal, uploaded with their logins (V345) ── */

    public record OldPortalIn(@NotNull @Size(max = 300) List<Map<String, Object>> rows, @NotBlank String session, boolean dayFirst, boolean commit,
                              @Size(max = 200) String fileName, boolean emailLinks) {
    }

    private static final String PASSWORD_LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789abcdefghjkmnpqrstuvwxyz";
    private static final java.security.SecureRandom RANDOM = new java.security.SecureRandom();
    private final org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder encoder = new org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder(12);

    private static String temporaryPassword() {
        StringBuilder b = new StringBuilder(10);
        for (int i = 0; i < 10; i++) b.append(PASSWORD_LETTERS.charAt(RANDOM.nextInt(PASSWORD_LETTERS.length())));
        return b.toString();
    }

    private static String sha256(String s) {
        try {
            return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(s.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /**
     * The old portal's export, judged row by row (a preview writes nothing); on the upload every importable row becomes an
     * account and a student record with a temporary password, returned here once — the office hands them out; they are
     * never stored readable — and, when asked, an email to each student with a link to set their own password. A student
     * already on the portal is skipped; a row to correct is listed and skipped.
     */
    @PostMapping("/old-portal-students/import")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> importOldPortal(@Valid @RequestBody OldPortalIn body) {
        String session = body.session().trim();
        String judged = jdbc.sql("SELECT jupeb.import_old_portal_students(:r::jsonb, :s, :d, false, :f, :by)::text")
                .param("r", json.writeValueAsString(body.rows())).param("s", session).param("d", body.dayFirst()).param("f", body.fileName(), Types.VARCHAR)
                .param("by", actor()).query(String.class).single();
        @SuppressWarnings("unchecked")
        Map<String, Object> preview = json.readValue(judged, Map.class);
        if (!body.commit()) return preview;

        /* a temporary password for each importable row, hashed as every JUPEB password is (bcrypt, cost 12) */
        Set<String> importable = new java.util.HashSet<>();
        for (Object o : (List<?>) preview.get("rows")) {
            Map<?, ?> r = (Map<?, ?>) o;
            if ("VALID".equals(r.get("status")) || "REVIEW".equals(r.get("status"))) importable.add(String.valueOf(r.get("row")));
        }
        Map<String, String> passwords = new java.util.concurrent.ConcurrentHashMap<>();
        List<Map<String, Object>> rows = body.rows().parallelStream().map(r -> {
            Map<String, Object> m = new LinkedHashMap<>(r);
            String row = String.valueOf(r.get("row"));
            if (importable.contains(row)) {
                String pw = temporaryPassword();
                passwords.put(row, pw);
                m.put("passwordHash", encoder.encode(pw));
            }
            return m;
        }).toList();
        String done = jdbc.sql("SELECT jupeb.import_old_portal_students(:r::jsonb, :s, :d, true, :f, :by)::text")
                .param("r", json.writeValueAsString(rows)).param("s", session).param("d", body.dayFirst()).param("f", body.fileName(), Types.VARCHAR)
                .param("by", actor()).query(String.class).single();
        @SuppressWarnings("unchecked")
        Map<String, Object> out = new LinkedHashMap<>(json.readValue(done, Map.class));
        List<Map<String, Object>> credentials = new java.util.ArrayList<>();
        for (Object o : (List<?>) out.getOrDefault("created", List.of())) {
            Map<?, ?> c = (Map<?, ?>) o;
            String row = String.valueOf(c.get("row"));
            UUID app = UUID.fromString(String.valueOf(c.get("applicationId")));
            Map<String, Object> cred = new LinkedHashMap<>();
            cred.put("row", c.get("row"));
            cred.put("applicationNo", c.get("applicationNo"));
            cred.put("name", c.get("name"));
            cred.put("email", c.get("email"));
            cred.put("password", passwords.get(row));
            credentials.add(cred);
            if (body.emailLinks()) {
                byte[] raw = new byte[24];
                RANDOM.nextBytes(raw);
                String token = java.util.HexFormat.of().formatHex(raw);
                jdbc.sql("""
                        INSERT INTO jupeb.password_reset (account_id, token_hash, expires_at)
                        SELECT a.account_id, :h, now() + interval '7 days' FROM jupeb.application a WHERE a.id = :id
                        """).param("h", sha256(token)).param("id", app).update();
                jdbc.sql("SELECT jupeb.tell(:id, :s, :b)").param("id", app).param("s", "Your JUPEB portal account is ready")
                        .param("b", "Your JUPEB record from the old portal is now on the University's portal. Sign in at " + portalUrl + "/login with your "
                                + "application number " + c.get("applicationNo") + " (or this email).\n\nSet your password with this link (it works for seven days): "
                                + portalUrl + "/jupeb/reset?token=" + token + "\n\nIf the JUPEB Office gave you a temporary password, you may sign in with it instead; "
                                + "you will be asked to choose your own.")
                        .query().listOfRows();
            }
        }
        out.remove("created");
        out.put("credentials", credentials);
        return out;
    }

    /* ── V347: the old portal's payments, put on the record ── */

    public record OldPaymentsIn(@NotNull @Size(max = 500) List<Map<String, Object>> rows, boolean dayFirst, boolean commit, @Size(max = 200) String fileName) {
    }

    /** the old portal's payment export judged row by row (a preview writes nothing); on the upload each matched, successful, new payment is a confirmed fee */
    @PostMapping("/old-portal-payments/import")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> importOldPayments(@Valid @RequestBody OldPaymentsIn body) {
        String out = jdbc.sql("SELECT jupeb.import_old_portal_payments(:r::jsonb, :d, :c, :f, :by)::text")
                .param("r", json.writeValueAsString(body.rows())).param("d", body.dayFirst()).param("c", body.commit())
                .param("f", body.fileName(), Types.VARCHAR).param("by", actor()).query(String.class).single();
        return json.readValue(out, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    @GetMapping("/old-portal-payments")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    List<Map<String, Object>> oldPayments(@RequestParam(required = false) String session) {
        return jdbc.sql("""
                SELECT l.batch_ref, l.old_reference, l.app_no, l.kind, l.purpose, l.amount, l.paid_on, l.imported_at, f.reference,
                       a.id AS application_id, a.surname || ', ' || a.first_name AS name, a.session
                  FROM jupeb.legacy_payment l JOIN jupeb.application a ON a.id = l.application_id JOIN jupeb.fee_reference f ON f.id = l.fee_reference_id
                 WHERE (:s::text IS NULL OR a.session = :s) ORDER BY l.imported_at DESC, l.row_no LIMIT 2000
                """).param("s", session == null || session.isBlank() ? null : session.trim(), Types.VARCHAR).query().listOfRows();
    }

    /* ── V347: the timetable ── */

    public record SlotIn(@NotBlank String session, @jakarta.validation.constraints.Min(1) @jakarta.validation.constraints.Max(2) int semester, UUID classId,
                         @NotNull UUID subjectId, @jakarta.validation.constraints.Min(1) @jakarta.validation.constraints.Max(7) int weekday,
                         @NotBlank @jakarta.validation.constraints.Pattern(regexp = "^\\d{2}:\\d{2}$") String startsAt,
                         @NotBlank @jakarta.validation.constraints.Pattern(regexp = "^\\d{2}:\\d{2}$") String endsAt,
                         @Size(max = 120) String venue, @Size(max = 300) String note) {
    }

    @GetMapping("/timetable")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> timetable(@RequestParam String session, @RequestParam(required = false) Integer semester) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("slots", jdbc.sql("""
                SELECT t.id, t.session, t.semester, t.class_id, k.name AS class_name, t.subject_id, s.code, s.title, t.weekday,
                       to_char(t.starts_at, 'HH24:MI') AS starts_at, to_char(t.ends_at, 'HH24:MI') AS ends_at, t.venue, t.note,
                       (SELECT string_agg(p.surname || ', ' || p.given_names, '; ' ORDER BY p.surname) FROM attendance.instructor i JOIN iam.person p ON p.id = i.person_id
                         WHERE i.context = 'JUPEB' AND i.session = t.session AND i.subject_ref = t.subject_id AND i.ended_at IS NULL
                           AND (t.class_id IS NULL OR i.class_ref IS NULL OR i.class_ref = t.class_id)) AS instructors
                  FROM jupeb.timetable_slot t JOIN jupeb.subject s ON s.id = t.subject_id LEFT JOIN jupeb.class k ON k.id = t.class_id
                 WHERE t.active AND t.session = :s AND (:sem::int IS NULL OR t.semester = :sem)
                 ORDER BY t.semester, t.weekday, t.starts_at, k.name NULLS FIRST
                """).param("s", session.trim()).param("sem", semester, Types.INTEGER).query().listOfRows());
        out.put("classes", jdbc.sql("SELECT id, name FROM jupeb.class WHERE session = :s ORDER BY name").param("s", session.trim()).query().listOfRows());
        out.put("subjects", jdbc.sql("SELECT id, code, title FROM jupeb.subject WHERE active ORDER BY code").query().listOfRows());
        return out;
    }

    @PostMapping("/timetable")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> addSlot(@Valid @RequestBody SlotIn b) {
        UUID id = jdbc.sql("""
                INSERT INTO jupeb.timetable_slot (session, semester, class_id, subject_id, weekday, starts_at, ends_at, venue, note, created_by)
                VALUES (:s, :sem, :c, :sub, :w, :st::time, :en::time, :v, :n, :by) RETURNING id
                """).param("s", b.session().trim()).param("sem", b.semester()).param("c", b.classId(), Types.OTHER).param("sub", b.subjectId()).param("w", b.weekday())
                .param("st", b.startsAt()).param("en", b.endsAt()).param("v", blankOf(b.venue()), Types.VARCHAR).param("n", blankOf(b.note()), Types.VARCHAR)
                .param("by", actor()).query(UUID.class).single();
        return Map.of("id", id);
    }

    @PutMapping("/timetable/{id}")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> editSlot(@PathVariable UUID id, @Valid @RequestBody SlotIn b) {
        int n = jdbc.sql("""
                UPDATE jupeb.timetable_slot SET semester = :sem, class_id = :c, subject_id = :sub, weekday = :w, starts_at = :st::time, ends_at = :en::time, venue = :v, note = :n
                 WHERE id = :id AND active
                """).param("sem", b.semester()).param("c", b.classId(), Types.OTHER).param("sub", b.subjectId()).param("w", b.weekday())
                .param("st", b.startsAt()).param("en", b.endsAt()).param("v", blankOf(b.venue()), Types.VARCHAR).param("n", blankOf(b.note()), Types.VARCHAR)
                .param("id", id).update();
        if (n == 0) throw new NotFound("timetable slot", id);
        return Map.of("id", id);
    }

    @PostMapping("/timetable/{id}/remove")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> removeSlot(@PathVariable UUID id) {
        int n = jdbc.sql("UPDATE jupeb.timetable_slot SET active = false WHERE id = :id AND active").param("id", id).update();
        if (n == 0) throw new NotFound("timetable slot", id);
        return Map.of("id", id, "removed", true);
    }

    /* ── V347: practice tests ── */

    public record PracticeIn(@NotNull UUID subjectId, @NotBlank @Size(min = 3, max = 160) String title, @Size(max = 2000) String instructions,
                             @jakarta.validation.constraints.Min(5) @jakarta.validation.constraints.Max(240) int durationMinutes,
                             @jakarta.validation.constraints.Min(1) @jakarta.validation.constraints.Max(200) int questionsPerAttempt,
                             @jakarta.validation.constraints.Min(1) @jakarta.validation.constraints.Max(20) int attemptsAllowed, boolean showAnswers, boolean open) {
    }

    @GetMapping("/practice-tests")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> practiceTests() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("tests", jdbc.sql("""
                SELECT t.id, t.subject_id, s.code, s.title AS subject, t.title, t.instructions, t.duration_minutes, t.questions_per_attempt, t.attempts_allowed,
                       t.show_answers, t.open, t.updated_at,
                       (SELECT count(*) FROM jupeb.practice_question q WHERE q.test_id = t.id AND q.active) AS questions,
                       (SELECT count(*) FROM jupeb.practice_attempt p WHERE p.test_id = t.id AND p.submitted_at IS NOT NULL) AS attempts,
                       (SELECT count(DISTINCT p.application_id) FROM jupeb.practice_attempt p WHERE p.test_id = t.id) AS students,
                       (SELECT round(avg(p.percentage), 1) FROM jupeb.practice_attempt p WHERE p.test_id = t.id AND p.submitted_at IS NOT NULL) AS average
                  FROM jupeb.practice_test t JOIN jupeb.subject s ON s.id = t.subject_id ORDER BY s.code, t.title
                """).query().listOfRows());
        out.put("subjects", jdbc.sql("SELECT id, code, title FROM jupeb.subject WHERE active ORDER BY code").query().listOfRows());
        return out;
    }

    @PostMapping("/practice-tests")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> addPracticeTest(@Valid @RequestBody PracticeIn b) {
        UUID id = jdbc.sql("""
                INSERT INTO jupeb.practice_test (subject_id, title, instructions, duration_minutes, questions_per_attempt, attempts_allowed, show_answers, open, created_by)
                VALUES (:s, :t, :i, :d, :q, :a, :sh, :o, :by) RETURNING id
                """).param("s", b.subjectId()).param("t", b.title().trim()).param("i", blankOf(b.instructions()), Types.VARCHAR).param("d", b.durationMinutes())
                .param("q", b.questionsPerAttempt()).param("a", b.attemptsAllowed()).param("sh", b.showAnswers()).param("o", b.open()).param("by", actor())
                .query(UUID.class).single();
        return Map.of("id", id);
    }

    @PutMapping("/practice-tests/{id}")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> editPracticeTest(@PathVariable UUID id, @Valid @RequestBody PracticeIn b) {
        if (b.open() && Boolean.FALSE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.practice_question WHERE test_id = :id AND active)").param("id", id).query(Boolean.class).single())) {
            throw new DomainRuleViolation("JUPEB_PRACTICE_EMPTY", "A test is opened once it has questions.", new DomainRuleViolation.Remedy("Upload its questions first.", "JUPEB Office"));
        }
        int n = jdbc.sql("""
                UPDATE jupeb.practice_test SET subject_id = :s, title = :t, instructions = :i, duration_minutes = :d, questions_per_attempt = :q, attempts_allowed = :a,
                       show_answers = :sh, open = :o, updated_at = now() WHERE id = :id
                """).param("s", b.subjectId()).param("t", b.title().trim()).param("i", blankOf(b.instructions()), Types.VARCHAR).param("d", b.durationMinutes())
                .param("q", b.questionsPerAttempt()).param("a", b.attemptsAllowed()).param("sh", b.showAnswers()).param("o", b.open()).param("id", id).update();
        if (n == 0) throw new NotFound("practice test", id);
        return Map.of("id", id);
    }

    @GetMapping("/practice-tests/{id}")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> practiceTest(@PathVariable UUID id) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("questions", jdbc.sql("""
                SELECT q.id, q.ordinal, q.stem, q.option_a, q.option_b, q.option_c, q.option_d, q.option_e, q.answer, q.explanation,
                       EXISTS (SELECT 1 FROM jupeb.practice_image i WHERE i.question_id = q.id) AS has_image,
                       (SELECT count(*) FROM jupeb.practice_answer x WHERE x.question_id = q.id AND x.correct IS NOT NULL) AS answered,
                       (SELECT count(*) FROM jupeb.practice_answer x WHERE x.question_id = q.id AND x.correct) AS right_answers
                  FROM jupeb.practice_question q WHERE q.test_id = :id AND q.active ORDER BY q.ordinal
                """).param("id", id).query().listOfRows());
        return out;
    }

    public record QuestionsIn(@NotNull @Size(max = 1000) List<Map<String, Object>> rows, boolean replace) {
    }

    @PostMapping("/practice-tests/{id}/questions")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> uploadQuestions(@PathVariable UUID id, @Valid @RequestBody QuestionsIn body) {
        String out = jdbc.sql("SELECT jupeb.practice_upload(:t, :r::jsonb, :rep)::text").param("t", id).param("r", json.writeValueAsString(body.rows()))
                .param("rep", body.replace()).query(String.class).single();
        return json.readValue(out, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    @PostMapping("/practice-tests/{id}/questions/{question}/remove")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> removeQuestion(@PathVariable UUID id, @PathVariable UUID question) {
        int n = jdbc.sql("UPDATE jupeb.practice_question SET active = false WHERE id = :q AND test_id = :t AND active").param("q", question).param("t", id).update();
        if (n == 0) throw new NotFound("practice question", question);
        return Map.of("removed", true);
    }

    /* ── V347: the office's reports ── */

    @GetMapping("/reports")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> reports(@RequestParam String session) {
        Map<String, Object> out = new LinkedHashMap<>(json.readValue(jdbc.sql("SELECT jupeb.report(:s)::text").param("s", session.trim()).query(String.class).single(),
                new tools.jackson.core.type.TypeReference<Map<String, Object>>() { }));
        out.put("sessions", jdbc.sql("SELECT DISTINCT session FROM jupeb.application ORDER BY session DESC").query(String.class).list());
        return out;
    }

    /* ── V349: one question added or edited (with its image), the announcements, the identity cards ── */

    public record QuestionIn(@NotNull Map<String, Object> row) {
    }

    private void requireQuestion(UUID test, UUID question) {
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.practice_question WHERE id = :q AND test_id = :t)")
                .param("q", question).param("t", test).query(Boolean.class).single())) {
            throw new NotFound("practice question", question);
        }
    }

    /** one question typed by the office (formulas written as $x^2$, $H_2O$, $\frac{1}{2}$); its id back, to attach an image to */
    @PostMapping("/practice-tests/{id}/questions/add")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> addQuestion(@PathVariable UUID id, @Valid @RequestBody QuestionIn body) {
        UUID q = jdbc.sql("SELECT jupeb.practice_add(:t, :r::jsonb)").param("t", id).param("r", json.writeValueAsString(body.row())).query(UUID.class).single();
        return Map.of("id", q);
    }

    /** a question corrected: in place until answered; afterwards a new version, the old one kept with the attempts that drew it */
    @PutMapping("/practice-tests/{id}/questions/{question}")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> editQuestion(@PathVariable UUID id, @PathVariable UUID question, @Valid @RequestBody QuestionIn body) {
        UUID q = jdbc.sql("SELECT jupeb.practice_edit(:t, :q, :r::jsonb)").param("t", id).param("q", question).param("r", json.writeValueAsString(body.row()))
                .query(UUID.class).single();
        return Map.of("id", q, "newVersion", !q.equals(question));
    }

    public record ImageIn(@Size(max = 200) String filename, @NotBlank String contentType, @NotBlank String base64) {
    }

    @PostMapping("/practice-tests/{id}/questions/{question}/image")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> questionImage(@PathVariable UUID id, @PathVariable UUID question, @Valid @RequestBody ImageIn body) {
        requireQuestion(id, question);
        JupebPracticeImages.store(jdbc, files, question, body.filename(), body.contentType(), body.base64(), actor());
        return Map.of("id", question, "image", true);
    }

    @PostMapping("/practice-tests/{id}/questions/{question}/image/remove")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> removeQuestionImage(@PathVariable UUID id, @PathVariable UUID question) {
        requireQuestion(id, question);
        JupebPracticeImages.remove(jdbc, files, question);
        return Map.of("id", question, "image", false);
    }

    @GetMapping("/practice-tests/{id}/questions/{question}/image")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> questionImageContent(@PathVariable UUID id, @PathVariable UUID question) {
        requireQuestion(id, question);
        return JupebPracticeImages.stream(jdbc, files, question);
    }

    public record AnnouncementIn(@NotBlank @Pattern(regexp = "^\\d{4}/\\d{4}$") String session,
                                 @NotBlank @Pattern(regexp = "ALL|APPLICANTS|ADMITTED|STUDENTS|CLASS|COMBINATION|PROGRAMME") String audience,
                                 @Size(max = 80) String audienceRef, @NotBlank @Size(min = 3, max = 160) String title, @NotBlank @Size(min = 3, max = 5000) String body,
                                 Boolean pinned, Boolean email, Boolean sms, LocalDate expiresOn) {
    }

    /** the audience's reference, checked: a class of the session, an existing combination, a programme; none for the others */
    private String audienceRef(String session, String audience, String ref) {
        String r = blankOf(ref);
        switch (audience) {
            case "CLASS" -> {
                if (r == null || !Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.class WHERE id::text = :r AND session = :s)").param("r", r).param("s", session)
                        .query(Boolean.class).single())) {
                    throw new DomainRuleViolation("JUPEB_ANNOUNCE_AUDIENCE", "Choose a class of the " + session + " session.", new DomainRuleViolation.Remedy("Pick the class from the list.", "JUPEB Office"));
                }
                return r;
            }
            case "COMBINATION" -> {
                if (r == null || !Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM jupeb.combination WHERE upper(code) = upper(:r))").param("r", r).query(Boolean.class).single())) {
                    throw new DomainRuleViolation("JUPEB_ANNOUNCE_AUDIENCE", "Choose a subject combination.", new DomainRuleViolation.Remedy("Pick the combination from the list.", "JUPEB Office"));
                }
                return r.toUpperCase();
            }
            case "PROGRAMME" -> {
                if (!"SCIENCE".equals(r) && !"NON_SCIENCE".equals(r)) {
                    throw new DomainRuleViolation("JUPEB_ANNOUNCE_AUDIENCE", "Choose Science or Non-Science.", new DomainRuleViolation.Remedy("Pick the programme.", "JUPEB Office"));
                }
                return r;
            }
            default -> {
                return null;
            }
        }
    }

    @GetMapping("/announcements")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> announcementList(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", sessions());
        out.put("announcements", jdbc.sql("""
                SELECT n.id, n.session, n.audience, n.audience_ref, n.title, n.body, n.pinned, n.send_email, n.send_sms, n.expires_on, n.published_at, n.notified,
                       n.withdrawn_at, n.withdrawn_reason, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = n.created_by) AS created_by_name,
                       CASE n.audience WHEN 'CLASS' THEN (SELECT k.name FROM jupeb.class k WHERE k.id::text = n.audience_ref) ELSE n.audience_ref END AS audience_name,
                       (SELECT count(*) FROM jupeb.application a WHERE jupeb.audience_reaches(n.session, n.audience, n.audience_ref, a)) AS reach,
                       (SELECT count(*) FROM jupeb.announcement_read r WHERE r.announcement_id = n.id) AS reads
                  FROM jupeb.announcement n WHERE n.session = :s
                 ORDER BY (n.withdrawn_at IS NOT NULL), n.pinned DESC, n.published_at DESC
                """).param("s", s).query().listOfRows());
        out.put("classes", jdbc.sql("SELECT id, name FROM jupeb.class WHERE session = :s ORDER BY name").param("s", s).query().listOfRows());
        out.put("combinations", jdbc.sql("SELECT code, name FROM jupeb.combination WHERE active ORDER BY code").query().listOfRows());
        return out;
    }

    /** how many a notice would reach now, before it is published */
    @GetMapping("/announcements/reach")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> announcementReach(@RequestParam String session, @RequestParam String audience, @RequestParam(required = false) String ref) {
        String a = audience.trim().toUpperCase();
        if (!Set.of("ALL", "APPLICANTS", "ADMITTED", "STUDENTS", "CLASS", "COMBINATION", "PROGRAMME").contains(a)) throw new NotFound("audience", a);
        String r = Set.of("CLASS", "COMBINATION", "PROGRAMME").contains(a) ? blankOf(ref) : null;
        if (r == null && Set.of("CLASS", "COMBINATION", "PROGRAMME").contains(a)) return Map.of("count", 0);
        return Map.of("count", jdbc.sql("SELECT jupeb.announcement_reach(:s, :a, :r)").param("s", session.trim()).param("a", a).param("r", r, Types.VARCHAR)
                .query(Integer.class).single());
    }

    /** a notice published to its audience: on their dashboards at once, emailed and texted when asked */
    @PostMapping("/announcements")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> announce(@Valid @RequestBody AnnouncementIn b) {
        String ref = audienceRef(b.session(), b.audience(), b.audienceRef());
        if (b.expiresOn() != null && b.expiresOn().isBefore(LocalDate.now(java.time.ZoneId.of("Africa/Lagos")))) {
            throw new DomainRuleViolation("JUPEB_ANNOUNCE_EXPIRY", "A notice cannot expire before today.", new DomainRuleViolation.Remedy("Choose today or a later date, or none.", "JUPEB Office"));
        }
        UUID id = jdbc.sql("""
                INSERT INTO jupeb.announcement (session, audience, audience_ref, title, body, pinned, send_email, send_sms, expires_on, created_by, created_office)
                VALUES (:s, :a, :r, :t, :b, :p, :e, :m, :x, :by, nullif(current_setting('moaum.actor_office', true), '')) RETURNING id
                """).param("s", b.session().trim()).param("a", b.audience()).param("r", ref, Types.VARCHAR).param("t", b.title().trim()).param("b", b.body().trim())
                .param("p", Boolean.TRUE.equals(b.pinned())).param("e", Boolean.TRUE.equals(b.email())).param("m", Boolean.TRUE.equals(b.sms()))
                .param("x", b.expiresOn(), Types.DATE).param("by", actor()).query(UUID.class).single();
        int notified = jdbc.sql("SELECT jupeb.announcement_notify(:n)").param("n", id).query(Integer.class).single();
        int reach = jdbc.sql("SELECT jupeb.announcement_reach(:s, :a, :r)").param("s", b.session().trim()).param("a", b.audience()).param("r", ref, Types.VARCHAR)
                .query(Integer.class).single();
        return Map.of("id", id, "reach", reach, "notified", notified);
    }

    @PostMapping("/announcements/{id}/withdraw")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> withdrawAnnouncement(@PathVariable UUID id, @Valid @RequestBody RevokeIn body) {
        if (body.reason().trim().length() < 5) {
            throw new DomainRuleViolation("JUPEB_ANNOUNCE_REASON", "Say why the notice is withdrawn.", new DomainRuleViolation.Remedy("Give the reason in a few words.", "JUPEB Office"));
        }
        int n = jdbc.sql("UPDATE jupeb.announcement SET withdrawn_at = now(), withdrawn_by = :by, withdrawn_reason = :r WHERE id = :id AND withdrawn_at IS NULL")
                .param("by", actor()).param("r", body.reason().trim()).param("id", id).update();
        if (n == 0) throw new NotFound("live announcement", id);
        return Map.of("id", id, "withdrawn", true);
    }

    /** the active students of a session (or a class) and their identity cards: the live card's code, or none yet */
    @GetMapping("/id-cards")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> idCards(@RequestParam(required = false) String session, @RequestParam(required = false) UUID classId) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", sessions());
        out.put("classes", jdbc.sql("SELECT id, name FROM jupeb.class WHERE session = :s ORDER BY name").param("s", s).query().listOfRows());
        out.put("students", jdbc.sql("""
                SELECT a.id, a.application_no, a.exam_no, a.surname, a.first_name, a.middle_name, a.session, a.stream, a.next_of_kin_phone, a.state,
                       c.code AS combination_code, c.name AS combination_name, k.name AS class_name,
                       EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = 'PASSPORT' AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED')) AS has_passport,
                       p.code AS card_code, p.issued_at AS card_issued_at,
                       (SELECT count(*) FROM jupeb.paper r WHERE r.application_id = a.id AND r.kind = 'ID_CARD' AND r.revoked_at IS NOT NULL) AS replaced
                  FROM jupeb.application a
                  LEFT JOIN jupeb.combination c ON c.id = a.combination_id
                  LEFT JOIN jupeb.class k ON k.id = a.class_id
                  LEFT JOIN LATERAL (SELECT x.code, x.issued_at FROM jupeb.paper x WHERE x.application_id = a.id AND x.kind = 'ID_CARD' AND x.revoked_at IS NULL
                                      ORDER BY x.issued_at DESC LIMIT 1) p ON true
                 WHERE a.session = :s AND a.state IN ('STUDENT', 'COMPLETED') AND (CAST(:k AS uuid) IS NULL OR a.class_id = :k)
                 ORDER BY k.name NULLS LAST, a.surname, a.first_name
                """).param("s", s).param("k", classId, Types.OTHER).query().listOfRows());
        return out;
    }

    public record IssueIn(@NotNull @Size(min = 1, max = 500) List<UUID> ids) {
    }

    /** cards issued (or their live codes returned) for the students chosen; one not eligible is listed with the reason */
    @PostMapping("/id-cards/issue")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> issueCards(@Valid @RequestBody IssueIn body) {
        List<Map<String, Object>> cards = new java.util.ArrayList<>();
        List<Map<String, Object>> skipped = new java.util.ArrayList<>();
        for (UUID id : new java.util.LinkedHashSet<>(body.ids())) {
            Map<String, Object> a = jdbc.sql("""
                    SELECT a.state, EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = 'PASSPORT' AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED')) AS photo,
                           EXISTS (SELECT 1 FROM jupeb.paper x WHERE x.application_id = a.id AND x.kind = 'ID_CARD' AND x.revoked_at IS NULL) AS had
                      FROM jupeb.application a WHERE a.id = :a
                    """).param("a", id).query().listOfRows().stream().findFirst().orElse(null);
            if (a == null) { skipped.add(Map.of("id", id, "reason", "No such JUPEB record.")); continue; }
            if (!List.of("STUDENT", "COMPLETED").contains(String.valueOf(a.get("state")))) { skipped.add(Map.of("id", id, "reason", "Not an active student.")); continue; }
            if (!Boolean.TRUE.equals(a.get("photo"))) { skipped.add(Map.of("id", id, "reason", "No passport photograph on file.")); continue; }
            String code = jdbc.sql("SELECT jupeb.issue_paper(:a, 'ID_CARD', NULL, true, :by, nullif(current_setting('moaum.actor_office', true), ''))")
                    .param("a", id).param("by", actor()).query(String.class).single();
            if (!Boolean.TRUE.equals(a.get("had"))) {
                jdbc.sql("SELECT jupeb.app_event(:a, 'ID_CARD_ISSUED', :n)").param("a", id).param("n", "Identity card " + code + " issued").query().listOfRows();
            }
            cards.add(Map.of("id", id, "code", code));
        }
        return Map.of("cards", cards, "skipped", skipped);
    }

    /** a lost or damaged card: its code stops verifying (revoked with the reason) and a new card is issued */
    @PostMapping("/id-cards/{id}/replace")
    @PreAuthorize(WRITE)
    @Transactional
    Map<String, Object> replaceCard(@PathVariable UUID id, @Valid @RequestBody RevokeIn body) {
        requireApp(id);
        String old = jdbc.sql("SELECT code FROM jupeb.paper WHERE application_id = :a AND kind = 'ID_CARD' AND revoked_at IS NULL ORDER BY issued_at DESC LIMIT 1")
                .param("a", id).query(String.class).optional().orElseThrow(() -> new NotFound("identity card", id));
        jdbc.sql("SELECT jupeb.revoke_paper(:c, :r, :by)").param("c", old).param("r", "Card replaced: " + body.reason().trim()).param("by", actor()).query().listOfRows();
        String code = jdbc.sql("SELECT jupeb.issue_paper(:a, 'ID_CARD', NULL, true, :by, nullif(current_setting('moaum.actor_office', true), ''))")
                .param("a", id).param("by", actor()).query(String.class).single();
        jdbc.sql("SELECT jupeb.app_event(:a, 'ID_CARD_REPLACED', :n)").param("a", id).param("n", "Identity card " + old + " replaced by " + code + ": " + body.reason().trim())
                .query().listOfRows();
        return Map.of("id", id, "code", code, "replaced", old);
    }

    private static String blankOf(String s) {
        return s == null || s.isBlank() ? null : s.trim();
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
                       screening_instructions, results_published_at, exam_month
                  FROM jupeb.setting_of(:s)
                """).param("s", s).query().singleRow());
        out.put("documentKinds", jdbc.sql("SELECT code, label, required, image, active, ord FROM jupeb.document_kind ORDER BY ord, label").query().listOfRows());
        out.put("fees", jdbc.sql("SELECT application_fee, checking_fee, acceptance_fee, first_percent, allow_full, activation, indigene_state FROM jupeb.fee_setting_of(:s)").param("s", s).query().singleRow());
        return out;
    }

    public record SettingIn(@NotBlank String session, @NotBlank @Pattern(regexp = "^[A-Z][A-Z0-9/-]{1,20}$") String applicationPrefix,
                            boolean screeningRequired, @Size(max = 200) String screeningVenue, LocalDate screeningStartsOn, LocalDate screeningEndsOn,
                            @Size(max = 2000) String screeningInstructions, @Size(max = 40) String examMonth) {
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
                INSERT INTO jupeb.setting (session, application_prefix, screening_required, screening_venue, screening_starts_on, screening_ends_on, screening_instructions, exam_month, updated_by)
                VALUES (:s, :p, :r, :v, :a, :e, :i, :m, :by)
                ON CONFLICT (session) DO UPDATE SET application_prefix = EXCLUDED.application_prefix, screening_required = EXCLUDED.screening_required,
                       screening_venue = EXCLUDED.screening_venue, screening_starts_on = EXCLUDED.screening_starts_on, screening_ends_on = EXCLUDED.screening_ends_on,
                       screening_instructions = EXCLUDED.screening_instructions, exam_month = EXCLUDED.exam_month, updated_by = EXCLUDED.updated_by, updated_at = now()
                """).param("s", s).param("p", b.applicationPrefix()).param("r", b.screeningRequired()).param("v", b.screeningVenue(), Types.VARCHAR)
                .param("a", b.screeningStartsOn(), Types.DATE).param("e", b.screeningEndsOn(), Types.DATE).param("i", b.screeningInstructions(), Types.VARCHAR)
                .param("m", b.examMonth() == null || b.examMonth().isBlank() ? null : b.examMonth().trim().toUpperCase(), Types.VARCHAR)
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
