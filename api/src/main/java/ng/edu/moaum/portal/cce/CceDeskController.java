package ng.edu.moaum.portal.cce;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
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
 * The CCE desk (V379). The Academic Office loads JAMB's CCE list (preview, then commit or discard), sets how the CCE session
 * follows undergraduate, offers programmes on the route, oversees the review and publishes the admission list; the Centre for
 * Continuing Education reviews each application (documents, recommendation; approval by someone other than the recommender).
 * The Registry reads. Each act is a database function under the signed-in officer and acting office — the office rules are
 * enforced there as well as here — so the audit spine and the application's own history record it.
 */
@RestController
@RequestMapping("/api/v1/cce")
class CceDeskController {

    static final String READ = "hasAnyAuthority('OFFICE_cce','OFFICE_academic','OFFICE_registrar','OFFICE_super')";
    static final String ACADEMIC = "hasAnyAuthority('OFFICE_academic','OFFICE_super')";
    static final String CENTRE = "hasAnyAuthority('OFFICE_cce','OFFICE_super')";
    static final String DECIDE = "hasAnyAuthority('OFFICE_cce','OFFICE_academic','OFFICE_super')";
    static final String FEES_READ = "hasAnyAuthority('OFFICE_cce','OFFICE_academic','OFFICE_registrar','OFFICE_bursar','OFFICE_super')";
    static final String BURSAR = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;
    private final FileObjects files;
    private final tools.jackson.databind.ObjectMapper json;

    CceDeskController(JdbcClient jdbc, FileObjects files, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.files = files;
        this.json = json;
    }

    /** the session asked for, else the current CCE session */
    private String sessionOr(String s) {
        return s == null || s.isBlank() ? jdbc.sql("SELECT policy.route_session('CCE')").query(String.class).single() : s.trim();
    }

    private static String up(String v) {
        return v == null ? "" : v.trim().toUpperCase();
    }

    private static String q(String v) {
        return v == null ? "" : v.trim();
    }

    private Map<String, Object> mapping() {
        return jdbc.sql("SELECT * FROM policy.route_session_mapping('CCE')").query().singleRow();
    }

    private List<Map<String, Object>> sessions() {
        return jdbc.sql("""
                SELECT a.name AS session, a.state,
                       (SELECT count(*) FROM admissions.cce_candidate c WHERE c.session = a.name) AS listed
                  FROM policy.academic_session a WHERE a.state <> 'CANCELLED'
                 ORDER BY a.name DESC LIMIT 12
                """).query().listOfRows();
    }

    /** jsonb read as text, handed on as an object */
    private Map<String, Object> parsed(Map<String, Object> row, String... keys) {
        Map<String, Object> m = new LinkedHashMap<>(row);
        for (String k : keys) {
            Object v = m.get(k);
            if (v instanceof String s && !s.isBlank()) {
                m.put(k, json.readValue(s, Map.class));
            }
        }
        return m;
    }

    private static Map<String, Object> paged(String session, List<Map<String, Object>> rows, int page, int size) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("total", rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue());
        out.put("page", page);
        out.put("size", size);
        out.put("rows", rows);
        return out;
    }

    /* ── the desk ── */

    @GetMapping("/overview")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("office", AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null));
        out.put("mapping", mapping());
        out.put("sessions", sessions());
        out.put("stats", json.readValue(jdbc.sql("SELECT admissions.cce_stats(:s)::text").param("s", s).query(String.class).single(), Map.class));
        out.put("window", jdbc.sql("SELECT state, opens_at, closes_at FROM policy.window_state('CCE_APPLICATION', :s, NULL)").param("s", s).query().singleRow());
        out.put("fees", jdbc.sql("SELECT * FROM admissions.route_fee_rule(:s, 'CCE')").param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("programmesOffered", jdbc.sql("SELECT count(*) FROM ref.programme_route WHERE route = 'CCE' AND active").query(Long.class).single());
        out.put("byProgramme", jdbc.sql("""
                SELECT programme_code, programme, faculty, count(*) AS listed, count(application_id) AS applied, count(*) FILTER (WHERE status = 'ADMITTED') AS admitted,
                       count(student_id) AS students
                  FROM admissions.cce_candidate_status WHERE session = :s GROUP BY programme_code, programme, faculty ORDER BY count(*) DESC, programme
                """).param("s", s).query().listOfRows());
        return out;
    }

    /* ── the CCE session ── */

    @GetMapping("/session-mapping")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> sessionMapping() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("mapping", mapping());
        out.put("sessions", jdbc.sql("SELECT name AS session, state FROM policy.academic_session WHERE state <> 'CANCELLED' ORDER BY name DESC").query().listOfRows());
        out.put("history", jdbc.sql("""
                SELECT e.at, e.what, e.before, e.after, e.reason, e.office, nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS actor_name
                  FROM policy.study_route_event e LEFT JOIN iam.person p ON p.id = e.actor
                 WHERE e.route = 'CCE' ORDER BY e.at DESC LIMIT 200
                """).query().listOfRows().stream().map(r -> {
                    Map<String, Object> m = new LinkedHashMap<>(r);
                    m.put("before", r.get("before") == null ? null : r.get("before").toString());
                    m.put("after", r.get("after") == null ? null : r.get("after").toString());
                    return m;
                }).toList());
        return out;
    }

    public record Mapping(@NotNull @Min(-3) @Max(3) Integer offset, @Size(max = 9) String override, @NotBlank @Size(max = 500) String reason, LocalDate effectiveFrom) {
    }

    @PutMapping("/session-mapping")
    @PreAuthorize(ACADEMIC)
    @Transactional
    Map<String, Object> setSessionMapping(@Valid @RequestBody Mapping body) {
        jdbc.sql("SELECT policy.set_route_session('CCE', :o, :ov, :r, :e)")
                .param("o", body.offset()).param("ov", body.override() == null || body.override().isBlank() ? null : body.override().trim())
                .param("r", body.reason().trim()).param("e", body.effectiveFrom()).query(String.class).single();
        return sessionMapping();
    }

    /* ── the programmes the Centre admits into ── */

    @GetMapping("/programmes")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> programmes(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("defaultDurationYears", jdbc.sql("SELECT default_duration_years FROM policy.study_route WHERE code = 'CCE'").query(Integer.class).single());
        out.put("rows", jdbc.sql("""
                SELECT p.code, p.name, d.name AS department, f.name AS faculty, p.duration_years AS full_time_years, p.final_level AS full_time_final_level,
                       t.configured, t.active, t.duration_years, t.final_level, pr.duration_years AS duration_stated, pr.final_level AS final_level_stated,
                       pr.note, pr.updated_at, (SELECT count(*) FROM admissions.cce_candidate c WHERE c.programme_code = p.code AND c.session = :s) AS listed,
                       (SELECT count(*) FROM people.student x WHERE x.programme_code = p.code AND x.entry_mode = 'CCE') AS students
                  FROM ref.programme p
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  CROSS JOIN LATERAL ref.programme_route_terms(p.code, 'CCE') t
                  LEFT JOIN ref.programme_route pr ON pr.programme_code = p.code AND pr.route = 'CCE'
                 WHERE p.category = 'UNDER GRADUATE' AND (NOT p.archived OR pr.id IS NOT NULL)
                 ORDER BY t.active DESC, f.name NULLS LAST, p.name
                """).param("s", s).query().listOfRows());
        return out;
    }

    public record Terms(@NotNull Boolean active, @Min(1) @Max(10) Integer durationYears, @Min(100) @Max(900) Integer finalLevel, @Size(max = 300) String note) {
    }

    @PutMapping("/programmes/{code}")
    @PreAuthorize(ACADEMIC)
    @Transactional
    Map<String, Object> setProgramme(@PathVariable String code, @Valid @RequestBody Terms body) {
        jdbc.sql("SELECT ref.set_programme_route(:c, 'CCE', :a, :d, :f, :n)").param("c", code.trim().toUpperCase()).param("a", body.active())
                .param("d", body.durationYears()).param("f", body.finalLevel()).param("n", body.note()).query(UUID.class).single();
        return programmes(null);
    }

    /* ── the CCE list ── */

    private static final String BATCH = """
            SELECT b.id, b.session, b.filename, b.rows_read, b.counts::text AS counts, b.state, b.uploaded_at, b.uploaded_office,
                   nullif(btrim(coalesce(u.surname, '') || ', ' || coalesce(u.given_names, '')), ',') AS uploaded_by_name,
                   b.committed_at, nullif(btrim(coalesce(c.surname, '') || ', ' || coalesce(c.given_names, '')), ',') AS committed_by_name, b.applied::text AS applied,
                   b.discarded_at, b.discard_reason
              FROM admissions.cce_batch b
              LEFT JOIN iam.person u ON u.id = b.uploaded_by
              LEFT JOIN iam.person c ON c.id = b.committed_by
            """;

    @GetMapping("/batches")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> batches(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rows", jdbc.sql(BATCH + " WHERE b.session = :s ORDER BY b.uploaded_at DESC LIMIT 200").param("s", s).query().listOfRows()
                .stream().map(r -> parsed(r, "counts", "applied")).toList());
        return out;
    }

    private Map<String, Object> batch(UUID id) {
        return jdbc.sql(BATCH + " WHERE b.id = :id").param("id", id).query().listOfRows().stream().findFirst()
                .map(r -> parsed(r, "counts", "applied")).orElseThrow(() -> new NotFound("CCE list", id));
    }

    @GetMapping("/batches/{id}")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> batchOf(@PathVariable UUID id) {
        return batch(id);
    }

    public record Preview(@NotBlank @Pattern(regexp = "\\d{4}/\\d{4}") String session, @NotBlank @Size(max = 200) String filename,
                          @NotBlank @Pattern(regexp = "[0-9a-fA-F]{64}") String sha256, @NotNull @Size(min = 1, max = 20000) List<Map<String, String>> rows) {
    }

    @PostMapping("/batches")
    @PreAuthorize(ACADEMIC)
    @Transactional
    Map<String, Object> preview(@Valid @RequestBody Preview body) {
        UUID id = jdbc.sql("SELECT admissions.cce_preview(:s, :f, :h, :r::jsonb)").param("s", body.session()).param("f", body.filename().trim())
                .param("h", body.sha256().toLowerCase()).param("r", json.writeValueAsString(body.rows())).query(UUID.class).single();
        return batch(id);
    }

    private static final String ROWS = """
            SELECT r.row_no, r.jamb_reg_no, r.surname, r.first_name, r.middle_name, r.date_of_birth, r.sex, r.phone, r.email, r.state_of_origin, r.lga,
                   r.programme_code, p.name AS programme, r.classification, r.issues, r.notes, r.changes::text AS changes, count(*) OVER () AS total_rows
              FROM admissions.cce_batch_row r LEFT JOIN ref.programme p ON p.code = r.programme_code
             WHERE r.batch_id = :b AND (:cls = '' OR r.classification = ANY (string_to_array(:cls, ',')))
             ORDER BY r.row_no
            """;

    @GetMapping("/batches/{id}/rows")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> batchRows(@PathVariable UUID id, @RequestParam(required = false) String classification,
                                  @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "100") int size) {
        Map<String, Object> b = batch(id);
        int n = Math.max(1, Math.min(size, 1000));
        List<Map<String, Object>> rows = jdbc.sql(ROWS + " LIMIT :n OFFSET :o").param("b", id).param("cls", up(classification))
                .param("n", n).param("o", Math.max(0, page) * n).query().listOfRows().stream().map(CceDeskController::arrays).map(r -> parsed(r, "changes")).toList();
        Map<String, Object> out = paged(String.valueOf(b.get("session")), rows, page, n);
        out.put("batch", b);
        return out;
    }

    /** text[] columns as lists, for the JSON */
    private static Map<String, Object> arrays(Map<String, Object> r) {
        Map<String, Object> m = new LinkedHashMap<>(r);
        for (String k : List.of("issues", "notes")) {
            Object v = m.get(k);
            if (v instanceof java.sql.Array a) {
                try {
                    m.put(k, List.of((Object[]) a.getArray()));
                } catch (java.sql.SQLException e) {
                    m.put(k, List.of());
                }
            }
        }
        return m;
    }

    /** the rows the list did not load, and why — or every row with what it did — for the office to correct and load again */
    @GetMapping("/batches/{id}/report.csv")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> report(@PathVariable UUID id, @RequestParam(defaultValue = "false") boolean all) {
        Map<String, Object> b = batch(id);
        List<Map<String, Object>> rows = jdbc.sql(ROWS).param("b", id).param("cls", all ? "" : "DUPLICATE,REQUIRES_REVIEW,INVALID").query().listOfRows()
                .stream().map(CceDeskController::arrays).toList();
        StringBuilder csv = new StringBuilder("﻿Row,JAMB number,Surname,First name,Middle name,Date of birth,Programme,Result,Why,Notes\r\n");
        for (Map<String, Object> r : rows) {
            csv.append(String.join(",", List.of(cell(r.get("row_no")), cell(r.get("jamb_reg_no")), cell(r.get("surname")), cell(r.get("first_name")),
                    cell(r.get("middle_name")), cell(r.get("date_of_birth")), cell(r.get("programme") == null ? r.get("programme_code") : r.get("programme")),
                    cell(r.get("classification")), cell(join(r.get("issues"))), cell(join(r.get("notes")))))).append("\r\n");
        }
        String name = String.valueOf(b.get("filename")).replaceAll("\\.[A-Za-z0-9]+$", "").replaceAll("[^A-Za-z0-9._-]+", "-") + (all ? "-all-rows.csv" : "-not-loaded.csv");
        return ResponseEntity.ok().contentType(new MediaType("text", "csv", StandardCharsets.UTF_8))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + name + "\"")
                .header("Cache-Control", "no-store").body(csv.toString().getBytes(StandardCharsets.UTF_8));
    }

    private static String join(Object v) {
        return v instanceof List<?> l ? l.stream().map(String::valueOf).collect(Collectors.joining("; ")) : v == null ? "" : String.valueOf(v);
    }

    /** a CSV cell: quoted when it must be; a leading =, +, - or @ neutralised so a spreadsheet never runs it */
    private static String cell(Object v) {
        String s = v == null ? "" : String.valueOf(v);
        if (!s.isEmpty() && "=+-@".indexOf(s.charAt(0)) >= 0) {
            s = "'" + s;
        }
        return s.matches(".*[\",\\r\\n].*") ? "\"" + s.replace("\"", "\"\"") + "\"" : s;
    }

    @PostMapping("/batches/{id}/commit")
    @PreAuthorize(ACADEMIC)
    @Transactional
    Map<String, Object> commit(@PathVariable UUID id) {
        batch(id);
        jdbc.sql("SELECT admissions.cce_commit(:b)::text").param("b", id).query(String.class).single();
        return batch(id);
    }

    public record Reason(@NotBlank @Size(max = 500) String reason) {
    }

    @PostMapping("/batches/{id}/discard")
    @PreAuthorize(ACADEMIC)
    @Transactional
    Map<String, Object> discard(@PathVariable UUID id, @Valid @RequestBody Reason body) {
        batch(id);
        jdbc.sql("SELECT admissions.cce_discard(:b, :r)").param("b", id).param("r", body.reason().trim()).query().singleRow();
        return batch(id);
    }

    /* ── the listed candidates ── */

    private static final String SEARCH = """
            (:q = '' OR x.jamb_reg_no ILIKE '%' || :q || '%' OR coalesce(x.application_no, '') ILIKE '%' || :q || '%'
             OR coalesce(x.matric_no, '') ILIKE '%' || :q || '%' OR coalesce(x.admission_no, '') ILIKE '%' || :q || '%'
             OR (x.surname || ' ' || x.first_name || ' ' || coalesce(x.middle_name, '')) ILIKE '%' || :q || '%'
             OR coalesce(x.phone, '') LIKE '%' || :q || '%' OR coalesce(x.email, '') ILIKE '%' || :q || '%')
            """;

    @GetMapping("/candidates")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> candidates(@RequestParam(required = false) String session, @RequestParam(required = false) String status,
                                   @RequestParam(required = false) String programme, @RequestParam(required = false) String q,
                                   @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String s = sessionOr(session);
        int n = Math.max(1, Math.min(size, 5000));
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT x.id, x.jamb_reg_no, x.surname || ', ' || x.first_name || coalesce(' ' || x.middle_name, '') AS name, x.date_of_birth, x.sex, x.phone, x.email,
                       x.state_of_origin, x.lga, x.programme_code, x.programme, x.department, x.faculty, x.status, x.standing_reason,
                       x.application_id, x.application_no, x.review_state, x.admission_no, x.matric_no, x.created_at, count(*) OVER () AS total_rows
                  FROM admissions.cce_candidate_status x
                 WHERE x.session = :s AND (:st = '' OR x.status = ANY (string_to_array(:st, ','))) AND (:prog = '' OR x.programme_code = :prog) AND
                """ + SEARCH + " ORDER BY x.surname, x.first_name LIMIT :n OFFSET :o")
                .param("s", s).param("st", up(status)).param("prog", up(programme)).param("q", q(q)).param("n", n).param("o", Math.max(0, page) * n)
                .query().listOfRows();
        return paged(s, rows, page, n);
    }

    public record Standing(@NotBlank @Pattern(regexp = "LISTED|WITHDRAWN") String standing, @NotBlank @Size(max = 500) String reason) {
    }

    @PostMapping("/candidates/{id}/standing")
    @PreAuthorize(ACADEMIC)
    @Transactional
    Map<String, Object> standing(@PathVariable UUID id, @Valid @RequestBody Standing body) {
        jdbc.sql("SELECT admissions.cce_set_standing(:c, :st, :r)").param("c", id).param("st", body.standing()).param("r", body.reason().trim()).query(String.class).single();
        return jdbc.sql("SELECT id, status, standing, standing_reason FROM admissions.cce_candidate_status WHERE id = :c").param("c", id).query().singleRow();
    }

    /* ── the applications ── */

    private static final String APPS = """
            SELECT a.id, a.application_no, c.jamb_reg_no, l.surname || ', ' || l.first_name || coalesce(' ' || l.middle_name, '') AS name, l.sex, l.date_of_birth,
                   l.programme_code, p.name AS programme, d.name AS department, f.name AS faculty, r.state, r.submitted_at, r.review_started_at,
                   r.recommended_at, r.decided_at, r.decided_office, r.published_at, r.request_note, r.decision_note, a.fee_confirmed_at, a.accepted_at,
                   acc.email, acc.phone, s.admission_no, s.matric_no, s.id AS student_id, a.created_at,
                   (SELECT count(*) FROM admissions.application_document x WHERE x.application_id = a.id AND x.superseded_at IS NULL AND x.status = 'PENDING') AS documents_pending,
                   count(*) OVER () AS total_rows
              FROM admissions.cce_review r
              JOIN admissions.application a ON a.id = r.application_id
              JOIN admissions.candidate c ON c.id = a.candidate_id
              JOIN admissions.cce_candidate l ON l.id = c.cce_candidate_id
              JOIN admissions.applicant_account acc ON acc.id = a.account_id
              JOIN ref.programme p ON p.code = l.programme_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN people.student s ON s.candidate_id = c.id
            """;

    @GetMapping("/applications")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> applications(@RequestParam(required = false) String session, @RequestParam(required = false) String state,
                                     @RequestParam(required = false) String programme, @RequestParam(required = false) String q,
                                     @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String s = sessionOr(session);
        int n = Math.max(1, Math.min(size, 5000));
        List<Map<String, Object>> rows = jdbc.sql(APPS + """
                 WHERE a.session = :s AND (:st = '' OR r.state = ANY (string_to_array(:st, ','))) AND (:prog = '' OR l.programme_code = :prog)
                   AND (:q = '' OR c.jamb_reg_no ILIKE '%' || :q || '%' OR a.application_no ILIKE '%' || :q || '%'
                        OR (l.surname || ' ' || l.first_name || ' ' || coalesce(l.middle_name, '')) ILIKE '%' || :q || '%'
                        OR acc.email ILIKE '%' || :q || '%' OR acc.phone LIKE '%' || :q || '%' OR coalesce(s.matric_no, '') ILIKE '%' || :q || '%')
                 ORDER BY r.submitted_at NULLS LAST, a.application_no LIMIT :n OFFSET :o
                """).param("s", s).param("st", up(state)).param("prog", up(programme)).param("q", q(q)).param("n", n).param("o", Math.max(0, page) * n)
                .query().listOfRows();
        return paged(s, rows, page, n);
    }

    private void requireCce(UUID app) {
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.cce_review WHERE application_id = :a)").param("a", app).query(Boolean.class).single()) {
            throw new NotFound("CCE application", app);
        }
    }

    @GetMapping("/applications/{id}")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> application(@PathVariable UUID id) {
        requireCce(id);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql(APPS + " WHERE a.id = :a").param("a", id).query().singleRow());
        out.remove("total_rows");
        out.put("listed", jdbc.sql("""
                SELECT l.id, l.session, l.jamb_reg_no, l.surname, l.first_name, l.middle_name, l.date_of_birth, l.sex, l.phone, l.email, l.state_of_origin, l.lga,
                       l.nationality, l.olevel_note, l.remarks, l.extra::text AS extra, l.standing, b.filename AS list_file, b.committed_at AS listed_at
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  JOIN admissions.cce_candidate l ON l.id = c.cce_candidate_id JOIN admissions.cce_batch b ON b.id = l.first_batch_id
                 WHERE a.id = :a
                """).param("a", id).query().singleRow());
        out.put("biodata", jdbc.sql("SELECT field, value FROM admissions.screening_answer WHERE application_id = :a ORDER BY field").param("a", id).query().listOfRows());
        out.put("olevel", jdbc.sql("""
                SELECT sitting, exam_body, exam_number, exam_year, subject, grade FROM admissions.screening_olevel
                 WHERE application_id = :a AND active ORDER BY sitting, ord
                """).param("a", id).query().listOfRows());
        out.put("compulsory", jdbc.sql("""
                SELECT cs.subject, EXISTS (SELECT 1 FROM admissions.screening_olevel o WHERE o.application_id = a.id AND o.active AND o.subject ~ cs.pattern
                                                         AND o.grade IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6')) AS credit
                  FROM admissions.application a CROSS JOIN LATERAL admissions.olevel_compulsory_subjects(a.session) cs WHERE a.id = :a
                """).param("a", id).query().listOfRows());
        out.put("documents", jdbc.sql("""
                SELECT d.id, d.kind, d.filename, d.content_type, d.bytes, d.uploaded_at, d.status, d.reviewed_at, d.review_note,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS reviewed_by_name
                  FROM admissions.application_document d LEFT JOIN iam.person p ON p.id = d.reviewed_by
                 WHERE d.application_id = :a AND d.superseded_at IS NULL ORDER BY d.kind
                """).param("a", id).query().listOfRows());
        out.put("review", jdbc.sql("""
                SELECT r.state, r.programme_confirmed_at, r.submitted_at, r.review_started_at, r.request_note, r.requested_at, r.recommended_at, r.recommendation_note,
                       r.decided_at, r.decided_office, r.decision_note, r.published_at,
                       r.recommended_by, nullif(btrim(coalesce(rp.surname, '') || ', ' || coalesce(rp.given_names, '')), ',') AS recommended_by_name,
                       nullif(btrim(coalesce(dp.surname, '') || ', ' || coalesce(dp.given_names, '')), ',') AS decided_by_name
                  FROM admissions.cce_review r LEFT JOIN iam.person rp ON rp.id = r.recommended_by LEFT JOIN iam.person dp ON dp.id = r.decided_by
                 WHERE r.application_id = :a
                """).param("a", id).query().singleRow());
        out.put("events", jdbc.sql("""
                SELECT e.at, e.action, e.from_state, e.to_state, e.note, e.office,
                       coalesce(nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ','), CASE WHEN e.office = 'applicant' THEN 'The applicant' END) AS actor_name
                  FROM admissions.cce_review_event e LEFT JOIN iam.person p ON p.id = e.actor
                 WHERE e.application_id = :a ORDER BY e.at
                """).param("a", id).query().listOfRows());
        out.put("problems", jdbc.sql("SELECT step, field, message FROM admissions.cce_application_problems(:a)").param("a", id).query().listOfRows());
        out.put("payments", jdbc.sql("""
                SELECT kind, reference, amount, generated_at, confirmed_at, channel, receipt_no FROM admissions.fee_reference
                 WHERE application_id = :a ORDER BY generated_at
                """).param("a", id).query().listOfRows());
        out.put("me", AuditContextHolder.current().map(c -> c.actorId()).orElse(null));
        return out;
    }

    @GetMapping("/applications/{id}/documents/{doc}")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> document(@PathVariable UUID id, @PathVariable UUID doc) {
        requireCce(id);
        Map<String, Object> r = jdbc.sql("""
                SELECT d.filename, d.content_type, b.content, b.object_id
                  FROM admissions.application_document d JOIN admissions.application_document_blob b ON b.document_id = d.id
                 WHERE d.id = :d AND d.application_id = :a
                """).param("d", doc).param("a", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("document", doc));
        byte[] content = files.resolve((byte[]) r.get("content"), (UUID) r.get("object_id"));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(r.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + String.valueOf(r.get("filename")).replace("\"", "") + "\"")
                .header("Cache-Control", "no-store").header("X-Content-Type-Options", "nosniff")
                .header("Content-Security-Policy", "sandbox").body(content);
    }

    public record DocReview(@NotBlank @Pattern(regexp = "ACCEPTED|REJECTED") String status, @Size(max = 600) String note) {
    }

    @PostMapping("/applications/{id}/documents/{doc}/review")
    @PreAuthorize(CENTRE)
    @Transactional
    Map<String, Object> reviewDocument(@PathVariable UUID id, @PathVariable UUID doc, @Valid @RequestBody DocReview body) {
        requireCce(id);
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.application_document WHERE id = :d AND application_id = :a)").param("d", doc).param("a", id).query(Boolean.class).single()) {
            throw new NotFound("document", doc);
        }
        jdbc.sql("SELECT admissions.cce_review_document(:d, :s, :n)").param("d", doc).param("s", body.status()).param("n", body.note()).query(String.class).single();
        return application(id);
    }

    public record Act(@NotBlank @Pattern(regexp = "START|REQUEST_DOCUMENTS|REQUIRE_VERIFICATION|RESUME|RECOMMEND|APPROVE|NOT_ADMIT|REJECT|REOPEN") String action,
                      @Size(max = 1000) String note) {
    }

    /** one step of the review; who may take which step is the database's rule (the Centre reviews and recommends; the Centre or the
     *  Academic Office approves, never the recommender) */
    @PostMapping("/applications/{id}/act")
    @PreAuthorize(DECIDE)
    @Transactional
    Map<String, Object> act(@PathVariable UUID id, @Valid @RequestBody Act body) {
        requireCce(id);
        jdbc.sql("SELECT admissions.cce_act(:a, :x, :n)").param("a", id).param("x", body.action()).param("n", body.note()).query(String.class).single();
        return application(id);
    }

    /* ── the admission list ── */

    @GetMapping("/admission-list")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> admissionList(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rows", jdbc.sql(APPS + """
                 WHERE a.session = :s AND r.state IN ('APPROVED', 'ADMITTED', 'NOT_ADMITTED', 'REJECTED')
                 ORDER BY (r.published_at IS NULL) DESC, r.state, f.name, p.name, l.surname, l.first_name
                """).param("s", s).query().listOfRows());
        return out;
    }

    public record Publish(@NotBlank @Pattern(regexp = "\\d{4}/\\d{4}") String session, List<UUID> applicationIds) {
    }

    @PostMapping("/publish")
    @PreAuthorize(ACADEMIC)
    @Transactional
    Map<String, Object> publish(@Valid @RequestBody Publish body) {
        String ids = body.applicationIds() == null || body.applicationIds().isEmpty() ? null
                : body.applicationIds().stream().map(UUID::toString).collect(Collectors.joining(",", "{", "}"));
        String result = jdbc.sql("SELECT admissions.cce_publish(:s, :ids::uuid[])::text").param("s", body.session()).param("ids", ids).query(String.class).single();
        Map<String, Object> out = admissionList(body.session());
        out.put("published", json.readValue(result, Map.class));
        return out;
    }

    /* ── the CCE students ── */

    @GetMapping("/students")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String session, @RequestParam(required = false) String q,
                                 @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String s = session == null ? "" : session.trim();
        int n = Math.max(1, Math.min(size, 5000));
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT x.id, x.matric_no, x.admission_no, x.jamb_reg_no, x.surname || ', ' || x.other_names AS name, x.sex, x.programme_code, p.name AS programme,
                       d.name AS department, f.name AS faculty, x.entry_session, x.current_level, x.status, x.study_mode,
                       t.duration_years, policy.session_after(x.entry_session, t.duration_years - 1) AS expected_completion, count(*) OVER () AS total_rows
                  FROM people.student x
                  JOIN ref.programme p ON p.code = x.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN LATERAL ref.programme_route_terms(x.programme_code, 'CCE') t ON true
                 WHERE x.entry_mode = 'CCE' AND (:s = '' OR x.entry_session = :s)
                   AND (:q = '' OR coalesce(x.matric_no, '') ILIKE '%' || :q || '%' OR coalesce(x.admission_no, '') ILIKE '%' || :q || '%'
                        OR coalesce(x.jamb_reg_no, '') ILIKE '%' || :q || '%' OR (x.surname || ' ' || x.other_names) ILIKE '%' || :q || '%')
                 ORDER BY x.entry_session DESC, x.surname, x.other_names LIMIT :n OFFSET :o
                """).param("s", s).param("q", q(q)).param("n", n).param("o", Math.max(0, page) * n).query().listOfRows();
        return paged(s, rows, page, n);
    }

    /* ── the history ── */

    @GetMapping("/history")
    @PreAuthorize(READ)
    @Transactional(readOnly = true)
    Map<String, Object> history(@RequestParam(required = false) String session, @RequestParam(defaultValue = "300") int limit) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rows", jdbc.sql("""
                SELECT * FROM (
                    SELECT e.at, 'APPLICATION' AS kind, e.action, a.application_no AS subject, e.from_state, e.to_state, e.note, e.office,
                           coalesce(nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ','), CASE WHEN e.office = 'applicant' THEN 'The applicant' END) AS actor_name
                      FROM admissions.cce_review_event e JOIN admissions.application a ON a.id = e.application_id LEFT JOIN iam.person p ON p.id = e.actor
                     WHERE a.session = :s
                    UNION ALL
                    SELECT b.uploaded_at, 'LIST', 'LOADED FOR PREVIEW', b.filename, NULL, 'PREVIEW', b.rows_read || ' rows', b.uploaded_office,
                           nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',')
                      FROM admissions.cce_batch b LEFT JOIN iam.person p ON p.id = b.uploaded_by WHERE b.session = :s
                    UNION ALL
                    SELECT b.committed_at, 'LIST', 'COMMITTED', b.filename, 'PREVIEW', 'COMMITTED', b.applied::text, NULL,
                           nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',')
                      FROM admissions.cce_batch b LEFT JOIN iam.person p ON p.id = b.committed_by WHERE b.session = :s AND b.committed_at IS NOT NULL
                    UNION ALL
                    SELECT b.discarded_at, 'LIST', 'DISCARDED', b.filename, 'PREVIEW', 'DISCARDED', b.discard_reason, NULL,
                           nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',')
                      FROM admissions.cce_batch b LEFT JOIN iam.person p ON p.id = b.discarded_by WHERE b.session = :s AND b.discarded_at IS NOT NULL
                    UNION ALL
                    SELECT e.at, 'SESSION', e.what, 'CCE', e.before::text, e.after::text, e.reason, e.office,
                           nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',')
                      FROM policy.study_route_event e LEFT JOIN iam.person p ON p.id = e.actor WHERE e.route = 'CCE'
                ) h ORDER BY at DESC LIMIT :n
                """).param("s", s).param("n", Math.max(1, Math.min(limit, 2000))).query().listOfRows());
        return out;
    }

    /* ── the CCE applicant fees: the Bursary's ── */

    @GetMapping("/fees")
    @PreAuthorize(FEES_READ)
    @Transactional(readOnly = true)
    Map<String, Object> fees(@RequestParam(required = false) String session) {
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rule", jdbc.sql("SELECT * FROM admissions.route_fee_rule(:s, 'CCE')").param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("stated", jdbc.sql("""
                SELECT f.session, f.application_fee, f.portal_charge, f.acceptance_fee, f.stated_at, f.stated_office,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS stated_by_name
                  FROM admissions.route_fee f LEFT JOIN iam.person p ON p.id = f.stated_by WHERE f.route = 'CCE' ORDER BY f.session DESC
                """).query().listOfRows());
        out.put("collected", jdbc.sql("""
                SELECT r.kind, count(*) AS paid, coalesce(sum(r.amount), 0) AS amount
                  FROM admissions.fee_reference r JOIN admissions.application a ON a.id = r.application_id
                  JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode = 'CCE'
                 WHERE a.session = :s AND r.confirmed_at IS NOT NULL GROUP BY r.kind ORDER BY r.kind
                """).param("s", s).query().listOfRows());
        out.put("sessions", jdbc.sql("SELECT name AS session, state FROM policy.academic_session WHERE state <> 'CANCELLED' ORDER BY name DESC LIMIT 12").query().listOfRows());
        return out;
    }

    public record Fees(@NotBlank @Pattern(regexp = "\\d{4}/\\d{4}") String session, @NotNull @DecimalMin("0") BigDecimal applicationFee,
                       @DecimalMin("0") BigDecimal portalCharge, @NotNull @DecimalMin("0") BigDecimal acceptanceFee) {
    }

    @PutMapping("/fees")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> setFees(@Valid @RequestBody Fees body) {
        jdbc.sql("SELECT admissions.set_route_fee(:s, 'CCE', :a, :p, :c)").param("s", body.session()).param("a", body.applicationFee())
                .param("p", body.portalCharge() == null ? BigDecimal.ZERO : body.portalCharge()).param("c", body.acceptanceFee()).query().singleRow();
        return fees(body.session());
    }
}
