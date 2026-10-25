package ng.edu.moaum.portal.pgadmissions;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
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
 * V651: postgraduate academic management — the stages of each qualification (700, 700 Extension; 800 A, 800 B, 800 C; 900 A–E),
 * each student's cycle and stage in a session, progression, extension, closing a cycle, the restart workflow, the reconciliation of
 * the existing PG students and the data-quality list. The University's master prompt of 24 October 2026. The database holds every
 * rule (admissions.pg_stages_of, pg_record_stage, pg_progress, pg_close_cycle, pg_restart_*, pg_cycle_scan / pg_cycle_commit,
 * pg_set_qualification) and the grants (admissions.pg_grant); a Head of Department works their department, a Dean their faculty.
 */
@RestController
@RequestMapping("/api/v1/pg/academic")
class PgAcademicController {

    private static final String READERS = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_registrar',"
            + "'OFFICE_dregistrar','OFFICE_vc','OFFICE_dvc','OFFICE_ict','OFFICE_admin','OFFICE_records','OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit',"
            + "'OFFICE_deputyaudit','OFFICE_super')";
    private static final String SESSION = "^[0-9]{4}/[0-9]{4}$";

    public record Qualification(@Size(max = 80) String label, @NotNull @Min(1) @Max(6) Integer normalYears, @NotNull @Min(0) @Max(4) Integer extensionYears,
                                Boolean restartAllowed, @Size(max = 10) List<@Size(max = 60) String> labels) {
    }

    public record Students(@NotNull @NotEmpty @Size(max = 5000) List<UUID> studentIds, @NotBlank @Pattern(regexp = SESSION) String session,
                           @Size(max = 400) String reason) {
    }

    public record StageWord(@NotNull UUID cycleId, @NotBlank @Pattern(regexp = SESSION) String session, @NotBlank @Pattern(regexp = "^[789]00[A-Z]$") String stage,
                            @NotBlank @Size(min = 10, max = 400) String reason) {
    }

    public record Close(@NotBlank @Pattern(regexp = "COMPLETED|GRADUATED|MAXIMUM_PERIOD_EXHAUSTED|CLOSED") String status, @NotBlank @Size(min = 10, max = 400) String reason) {
    }

    public record CloseExhausted(@NotNull @NotEmpty @Size(max = 5000) List<UUID> studentIds, @NotBlank @Size(min = 10, max = 400) String reason) {
    }

    public record Restart(@NotNull UUID studentId, @NotBlank @Pattern(regexp = SESSION) String startSession, @NotBlank @Size(min = 10, max = 1000) String reason) {
    }

    public record Recommend(@NotNull Boolean recommend, @Size(max = 1000) String note) {
    }

    public record Decide(@NotNull Boolean approve, @Size(max = 1000) String note) {
    }

    public record Note(@Size(max = 1000) String note) {
    }

    public record Commit(@Size(max = 5000) List<UUID> studentIds, Boolean all, @NotBlank @Pattern(regexp = SESSION) String session, @Size(max = 400) String reason) {
    }

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    PgAcademicController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /* ── who may, and where ── */

    private static String office() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    private List<String> permissions() {
        return jdbc.sql("SELECT unnest(admissions.pg_permissions(:o))").param("o", office()).query(String.class).list();
    }

    private void need(String permission) {
        if (!permissions().contains(permission)) {
            throw new AccessDeniedException("Your office does not hold " + permission + " in postgraduate academic management.");
        }
    }

    private String boundDept() {
        return scope.actingHod() ? String.valueOf(scope.actingDept()) : null;
    }

    private String boundFaculty() {
        return scope.actingFacultyOffice() ? String.valueOf(scope.actingFaculty()) : null;
    }

    /** a department or faculty office acts on its own students only */
    private void inBound(UUID student) {
        String dept = boundDept(), fac = boundFaculty();
        if (dept == null && fac == null) {
            return;
        }
        boolean ok = jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                                WHERE s.id = :s AND (CAST(:d AS text) IS NULL OR p.dept_code = :d) AND (CAST(:f AS text) IS NULL OR p.faculty_code = :f))
                """).param("s", student).param("d", dept, Types.VARCHAR).param("f", fac, Types.VARCHAR).query(Boolean.class).single();
        if (!ok) {
            throw new AccessDeniedException("That student is outside your department or faculty.");
        }
    }

    private String session(String session) {
        return session != null && session.matches(SESSION) ? session
                : jdbc.sql("SELECT admissions.pg_current_session()").query(String.class).optional().orElse(null);
    }

    private static String[] ids(List<UUID> ids) {
        return ids.stream().map(UUID::toString).toArray(String[]::new);
    }

    /* ── the structure ── */

    /** the qualifications and their stages, the PG School's session and the acting office's grants */
    @GetMapping("/config")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> config() {
        need("VIEW_PG_LEVEL_STRUCTURE");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session(null));
        out.put("qualifications", jdbc.sql("""
                SELECT q.code, q.label, q.level, q.normal_years, q.extension_years, q.restart_allowed, q.updated_at
                  FROM admissions.pg_qualification q ORDER BY q.level
                """).query().listOfRows());
        out.put("stages", jdbc.sql("""
                SELECT s.code, s.qualification, s.label, s.short_label, s.sequence, s.year_number, s.extension_number, s.extension_number IS NOT NULL AS is_extension,
                       s.semesters, s.active, q.level,
                       (SELECT n.label FROM admissions.pg_stage n WHERE n.qualification = s.qualification AND n.sequence = s.sequence + 1 AND n.active) AS next_label
                  FROM admissions.pg_stage s JOIN admissions.pg_qualification q ON q.code = s.qualification
                 ORDER BY q.level, s.sequence
                """).query().listOfRows());
        out.put("permissions", permissions());
        out.put("office", office());
        out.put("boundDept", boundDept());
        out.put("boundFaculty", boundFaculty());
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session WHERE state <> 'CANCELLED' ORDER BY name DESC").query(String.class).list());
        return out;
    }

    /** a qualification's normal and extension years and its stages' labels — the Dean of the PG School */
    @PutMapping("/config/{code}")
    @PreAuthorize("hasAnyAuthority('OFFICE_pgschool','OFFICE_super')")
    @Transactional
    Map<String, Object> setQualification(@PathVariable @Pattern(regexp = "^[A-Z_]{2,20}$") String code, @Valid @RequestBody Qualification body) {
        need("MANAGE_PG_LEVEL_STRUCTURE");
        String labels = body.labels() == null ? null : "[" + String.join(",", body.labels().stream()
                .map(l -> l == null ? "null" : "\"" + l.replace("\\", "\\\\").replace("\"", "\\\"") + "\"").toList()) + "]";
        jdbc.sql("SELECT admissions.pg_set_qualification(:c, :l, :n, :e, :r, CAST(:labels AS jsonb))")
                .param("c", code).param("l", body.label(), Types.VARCHAR).param("n", body.normalYears()).param("e", body.extensionYears())
                .param("r", body.restartAllowed(), Types.BOOLEAN).param("labels", labels, Types.VARCHAR).query(Integer.class).single();
        return config();
    }

    /* ── the register by stage ── */

    /** the counts of each stage in a session (the department's or faculty's own where the office is bound) */
    @GetMapping("/counts")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> counts(@RequestParam(required = false) String session) {
        need("VIEW_PG_ACADEMIC_HISTORY");
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rows", jdbc.sql("SELECT x.*, x.returning_ AS returning FROM admissions.pg_stage_counts(:s, :f, :d) x ORDER BY x.qualification, x.sequence")
                .param("s", s).param("f", boundFaculty(), Types.VARCHAR).param("d", boundDept(), Types.VARCHAR).query().listOfRows());
        return out;
    }

    /** the students of a session by stage, category, recommendation, recorded or calculated, and a search */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String session, @RequestParam(required = false) String qualification,
                                 @RequestParam(required = false) String stage, @RequestParam(required = false) String category,
                                 @RequestParam(required = false) String recommendation, @RequestParam(required = false) Boolean official,
                                 @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") @Min(0) int page,
                                 @RequestParam(defaultValue = "50") @Min(1) @Max(500) int size) {
        need("VIEW_PG_ACADEMIC_HISTORY");
        String s = session(session);
        String where = """
                FROM admissions.pg_stages_of(:s, NULL) x
                JOIN people.student st ON st.id = x.student_id
                JOIN ref.programme p ON p.code = st.programme_code
                LEFT JOIN ref.department d ON d.code = p.dept_code
                WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                  AND (CAST(:qual AS text) IS NULL OR x.qualification = :qual)
                  AND (CAST(:stage AS text) IS NULL OR x.stage_code = :stage OR (:stage = 'BEYOND' AND x.beyond))
                  AND (CAST(:cat AS text) IS NULL OR x.category = :cat)
                  AND (CAST(:rec AS text) IS NULL OR x.recommendation = :rec)
                  AND (CAST(:off AS boolean) IS NULL OR x.official = :off)
                  AND (CAST(:dept AS text) IS NULL OR p.dept_code = :dept) AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac)
                  AND (CAST(:q AS text) IS NULL OR st.matric_no ILIKE '%' || :q || '%' OR st.admission_no ILIKE '%' || :q || '%'
                       OR (st.surname || ' ' || st.other_names) ILIKE '%' || :q || '%')
                """;
        String qq = q == null || q.isBlank() ? null : q.trim();
        long total = bind(jdbc.sql("SELECT count(*) " + where), s, qualification, stage, category, recommendation, official, qq).query(Long.class).single();
        List<Map<String, Object>> rows = bind(jdbc.sql("""
                SELECT x.*, st.matric_no, st.admission_no, st.surname, st.other_names, st.sex, st.current_level, st.entry_session, st.status,
                       p.name AS programme, d.name AS department,
                       EXISTS (SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = st.id AND cr.session = :s) AS registered,
                       EXISTS (SELECT 1 FROM finance.payment_reference pr WHERE pr.student_id = st.id AND pr.session = :s AND pr.confirmed_at IS NOT NULL
                                  AND pr.purpose LIKE 'School fees%') AS paid,
                       (SELECT r.reference || ' ' || r.state FROM people.pg_restart_request r WHERE r.student_id = st.id AND r.state IN ('REQUESTED', 'UNDER_REVIEW') LIMIT 1) AS open_restart
                """ + where + " ORDER BY st.surname, st.other_names LIMIT :lim OFFSET :off2"), s, qualification, stage, category, recommendation, official, qq)
                .param("lim", size).param("off2", page * size).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("total", total);
        out.put("page", page);
        out.put("size", size);
        out.put("rows", rows);
        return out;
    }

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, String s, String qualification, String stage, String category, String recommendation,
                                          Boolean official, String q) {
        return spec.param("s", s).param("qual", blank(qualification), Types.VARCHAR).param("stage", blank(stage), Types.VARCHAR)
                .param("cat", blank(category), Types.VARCHAR).param("rec", blank(recommendation), Types.VARCHAR).param("off", official, Types.BOOLEAN)
                .param("dept", boundDept(), Types.VARCHAR).param("fac", boundFaculty(), Types.VARCHAR).param("q", q, Types.VARCHAR);
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    /** a student's postgraduate history: every cycle, the stage of each session, the restart requests, the stage of the session asked */
    @GetMapping("/students/{id}/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> history(@PathVariable UUID id, @RequestParam(required = false) String session) {
        need("VIEW_PG_ACADEMIC_HISTORY");
        inBound(id);
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        List<Map<String, Object>> now = jdbc.sql("SELECT x.* FROM admissions.pg_stages_of(:s, ARRAY[CAST(:id AS uuid)]) x").param("s", s).param("id", id).query().listOfRows();
        out.put("pg", !now.isEmpty());
        out.put("session", s);
        out.put("current", now.isEmpty() ? null : now.get(0));
        List<Map<String, Object>> cycles = jdbc.sql("""
                SELECT c.id, c.cycle_no, c.qualification, q.label AS qualification_label, c.programme_code, p.name AS programme, c.start_session, c.status,
                       c.status_reason, c.status_at, c.source, c.created_at, c.restart_of
                  FROM people.pg_cycle c JOIN admissions.pg_qualification q ON q.code = c.qualification JOIN ref.programme p ON p.code = c.programme_code
                 WHERE c.student_id = :id ORDER BY c.cycle_no
                """).param("id", id).query().listOfRows();
        for (Map<String, Object> c : cycles) {
            c.put("stages", jdbc.sql("""
                    SELECT cs.session, cs.stage_code, st.label, st.extension_number IS NOT NULL AS is_extension, cs.source, cs.reason, cs.decided_office, cs.at,
                           (SELECT btrim(pe.surname || ', ' || pe.given_names) FROM iam.person pe WHERE pe.id = cs.decided_by) AS decided_by_name
                      FROM people.pg_cycle_stage cs JOIN admissions.pg_stage st ON st.code = cs.stage_code
                     WHERE cs.cycle_id = :c ORDER BY left(cs.session, 4)
                    """).param("c", c.get("id")).query().listOfRows());
        }
        out.put("cycles", cycles);
        out.put("restarts", jdbc.sql("""
                SELECT r.reference, r.state, r.start_session, r.reason, r.requested_office, r.requested_at, r.dept_note, r.dept_at, r.decision_note, r.decided_at,
                       (SELECT c.cycle_no FROM people.pg_cycle c WHERE c.id = r.cycle_id) AS cycle_no,
                       (SELECT c.cycle_no FROM people.pg_cycle c WHERE c.id = r.new_cycle_id) AS new_cycle_no
                  FROM people.pg_restart_request r WHERE r.student_id = :id ORDER BY r.requested_at
                """).param("id", id).query().listOfRows());
        out.put("payments", jdbc.sql("""
                SELECT r.reference, r.session, r.amount, r.confirmed_at IS NOT NULL AS paid, c.cycle_no, c.stage_code, st.label AS stage_label, c.category, c.official
                  FROM finance.payment_pg_context c JOIN finance.payment_reference r ON r.id = c.reference_id LEFT JOIN admissions.pg_stage st ON st.code = c.stage_code
                 WHERE c.student_id = :id ORDER BY r.generated_at DESC LIMIT 200
                """).param("id", id).query().listOfRows());
        return out;
    }

    /* ── progression, extension, closing ── */

    /** the calculated stage recorded for the students chosen (an extension only on the Dean's grant) */
    @PostMapping("/progress")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> progress(@Valid @RequestBody Students body) {
        need("MANAGE_PG_PROGRESSION");
        body.studentIds().forEach(this::inBound);
        List<Map<String, Object>> rows = jdbc.sql("SELECT x.* FROM admissions.pg_progress(CAST(:ids AS uuid[]), :s, :r) x")
                .param("ids", ids(body.studentIds()), Types.ARRAY).param("s", body.session()).param("r", blank(body.reason()), Types.VARCHAR).query().listOfRows();
        return outcomes(rows);
    }

    private static Map<String, Object> outcomes(List<Map<String, Object>> rows) {
        Map<String, Long> by = new LinkedHashMap<>();
        rows.forEach(r -> by.merge(String.valueOf(r.get("outcome")), 1L, Long::sum));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("outcomes", by);
        out.put("rows", rows);
        return out;
    }

    /** a session's stage corrected (or recorded) for a cycle, with the reason */
    @PostMapping("/stage")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> stage(@Valid @RequestBody StageWord body) {
        UUID student = jdbc.sql("SELECT student_id FROM people.pg_cycle WHERE id = :c").param("c", body.cycleId()).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("postgraduate cycle", body.cycleId()));
        inBound(student);
        jdbc.sql("SELECT admissions.pg_record_stage(:c, :s, :st, 'CORRECTION', :r)").param("c", body.cycleId()).param("s", body.session())
                .param("st", body.stage()).param("r", body.reason()).query(UUID.class).single();
        return history(student, body.session());
    }

    /** a cycle closed — completed, graduated, maximum period exhausted, or closed */
    @PostMapping("/cycles/{id}/close")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> close(@PathVariable UUID id, @Valid @RequestBody Close body) {
        UUID student = jdbc.sql("SELECT student_id FROM people.pg_cycle WHERE id = :c").param("c", id).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("postgraduate cycle", id));
        inBound(student);
        jdbc.sql("SELECT admissions.pg_close_cycle(:c, :st, :r)").param("c", id).param("st", body.status()).param("r", body.reason()).query(String.class).single();
        return history(student, null);
    }

    /** the active cycles of the students chosen that are past the maximum period, closed as exhausted together */
    @PostMapping("/close-exhausted")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> closeExhausted(@Valid @RequestBody CloseExhausted body) {
        need("MANAGE_PG_ACADEMIC_CYCLE");
        body.studentIds().forEach(this::inBound);
        List<Map<String, Object>> cycles = jdbc.sql("""
                SELECT x.student_id, x.cycle_id FROM admissions.pg_stages_of(admissions.pg_current_session(), CAST(:ids AS uuid[])) x
                 WHERE x.cycle_id IS NOT NULL AND x.cycle_status = 'ACTIVE' AND x.beyond
                """).param("ids", ids(body.studentIds()), Types.ARRAY).query().listOfRows();
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Map<String, Object> c : cycles) {
            jdbc.sql("SELECT admissions.pg_close_cycle(:c, 'MAXIMUM_PERIOD_EXHAUSTED', :r)").param("c", c.get("cycle_id")).param("r", body.reason()).query(String.class).single();
            rows.add(Map.of("student_id", c.get("student_id"), "outcome", "CLOSED"));
        }
        Map<String, Object> out = outcomes(rows);
        out.put("skipped", body.studentIds().size() - rows.size());
        return out;
    }

    /* ── restart ── */

    @GetMapping("/restarts")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> restarts(@RequestParam(required = false) @Pattern(regexp = "REQUESTED|UNDER_REVIEW|APPROVED|REJECTED|CANCELLED|OPEN") String state) {
        need("VIEW_PG_RESTART");
        return jdbc.sql("""
                SELECT r.reference, r.state, r.start_session, r.reason, r.requested_office, r.requested_at, r.dept_note, r.dept_at, r.decision_note, r.decided_at,
                       st.id AS student_id, st.matric_no, st.surname, st.other_names, p.name AS programme, d.name AS department,
                       (SELECT c.cycle_no FROM people.pg_cycle c WHERE c.id = r.cycle_id) AS cycle_no, q.label AS qualification,
                       (SELECT c.cycle_no FROM people.pg_cycle c WHERE c.id = r.new_cycle_id) AS new_cycle_no,
                       r.requested_by = CAST(:me AS uuid) AS mine
                  FROM people.pg_restart_request r
                  JOIN people.student st ON st.id = r.student_id
                  JOIN ref.programme p ON p.code = st.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  JOIN people.pg_cycle c0 ON c0.id = r.cycle_id
                  JOIN admissions.pg_qualification q ON q.code = c0.qualification
                 WHERE (CAST(:state AS text) IS NULL OR r.state = :state OR (:state = 'OPEN' AND r.state IN ('REQUESTED', 'UNDER_REVIEW')))
                   AND (CAST(:dept AS text) IS NULL OR p.dept_code = :dept) AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac)
                 ORDER BY r.requested_at DESC
                 LIMIT 500
                """).param("state", blank(state), Types.VARCHAR).param("dept", boundDept(), Types.VARCHAR).param("fac", boundFaculty(), Types.VARCHAR)
                .param("me", AuditContextHolder.current().map(AuditContext::actorId).orElse(null), Types.OTHER).query().listOfRows();
    }

    @PostMapping("/restarts")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> requestRestart(@Valid @RequestBody Restart body) {
        inBound(body.studentId());
        String ref = jdbc.sql("SELECT admissions.pg_restart_request(:s, :ses, :r)").param("s", body.studentId()).param("ses", body.startSession())
                .param("r", body.reason()).query(String.class).single();
        return Map.of("reference", ref, "state", "REQUESTED");
    }

    private UUID restartStudent(String ref) {
        UUID student = jdbc.sql("SELECT student_id FROM people.pg_restart_request WHERE reference = :r").param("r", ref).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("restart request", ref));
        inBound(student);
        return student;
    }

    @PostMapping("/restarts/{year}/{seq}/recommend")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> recommend(@PathVariable @Pattern(regexp = "^[0-9]{4}$") String year, @PathVariable @Pattern(regexp = "^[0-9]{6}$") String seq,
                                  @Valid @RequestBody Recommend body) {
        String ref = "PG-RST/" + year + "/" + seq;
        restartStudent(ref);
        String state = jdbc.sql("SELECT admissions.pg_restart_recommend(:r, :y, :n)").param("r", ref).param("y", body.recommend())
                .param("n", blank(body.note()), Types.VARCHAR).query(String.class).single();
        return Map.of("reference", ref, "state", state);
    }

    @PostMapping("/restarts/{year}/{seq}/decide")
    @PreAuthorize("hasAnyAuthority('OFFICE_pgschool','OFFICE_super')")
    @Transactional
    Map<String, Object> decide(@PathVariable @Pattern(regexp = "^[0-9]{4}$") String year, @PathVariable @Pattern(regexp = "^[0-9]{6}$") String seq,
                               @Valid @RequestBody Decide body) {
        String ref = "PG-RST/" + year + "/" + seq;
        restartStudent(ref);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT x.* FROM admissions.pg_restart_decide(:r, :a, :n) x").param("r", ref)
                .param("a", body.approve()).param("n", blank(body.note()), Types.VARCHAR).query().singleRow());
        out.put("reference", ref);
        return out;
    }

    @PostMapping("/restarts/{year}/{seq}/cancel")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> cancel(@PathVariable @Pattern(regexp = "^[0-9]{4}$") String year, @PathVariable @Pattern(regexp = "^[0-9]{6}$") String seq,
                               @Valid @RequestBody(required = false) Note body) {
        String ref = "PG-RST/" + year + "/" + seq;
        restartStudent(ref);
        String state = jdbc.sql("SELECT admissions.pg_restart_cancel(:r, :n)").param("r", ref).param("n", body == null ? null : blank(body.note()), Types.VARCHAR)
                .query(String.class).single();
        return Map.of("reference", ref, "state", state);
    }

    /* ── the reconciliation of the existing PG students, and the data quality ── */

    @GetMapping("/reconciliation")
    @PreAuthorize("hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')")
    @Transactional(readOnly = true)
    Map<String, Object> scan(@RequestParam(required = false) String session, @RequestParam(required = false) @Pattern(regexp = "HIGH|MEDIUM|LOW") String confidence,
                             @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") @Min(0) int page,
                             @RequestParam(defaultValue = "100") @Min(1) @Max(1000) int size) {
        need("VIEW_PG_ACADEMIC_HISTORY");
        String s = session(session);
        List<Map<String, Object>> all = jdbc.sql("""
                SELECT x.*, st.matric_no, st.surname, st.other_names, p.name AS programme, sl.label AS stage_name
                  FROM admissions.pg_cycle_scan(:s) x
                  JOIN people.student st ON st.id = x.student_id
                  JOIN ref.programme p ON p.code = x.programme_code
                  LEFT JOIN admissions.pg_stage sl ON sl.code = x.stage_code
                 ORDER BY x.confidence DESC, st.surname, st.other_names
                """).param("s", s).query().listOfRows();
        Map<String, Long> by = new LinkedHashMap<>();
        Map<String, Long> rec = new LinkedHashMap<>();
        all.forEach(r -> { by.merge(String.valueOf(r.get("confidence")), 1L, Long::sum); rec.merge(String.valueOf(r.get("recommendation")), 1L, Long::sum); });
        String qq = q == null || q.isBlank() ? null : q.trim().toLowerCase();
        List<Map<String, Object>> rows = all.stream()
                .filter(r -> confidence == null || confidence.equals(r.get("confidence")))
                .filter(r -> qq == null || (String.valueOf(r.get("matric_no")) + " " + r.get("surname") + " " + r.get("other_names") + " " + r.get("programme")).toLowerCase().contains(qq))
                .toList();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("total", all.size());
        out.put("byConfidence", by);
        out.put("byRecommendation", rec);
        out.put("matching", rows.size());
        out.put("rows", rows.stream().skip((long) page * size).limit(size).toList());
        return out;
    }

    @PostMapping("/reconciliation/commit")
    @PreAuthorize("hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_super')")
    @Transactional
    Map<String, Object> commit(@Valid @RequestBody Commit body) {
        need("MANAGE_PG_ACADEMIC_CYCLE");
        List<UUID> ids = Boolean.TRUE.equals(body.all())
                ? jdbc.sql("SELECT x.student_id FROM admissions.pg_cycle_scan(:s) x WHERE x.confidence IN ('HIGH', 'MEDIUM')").param("s", body.session()).query(UUID.class).list()
                : body.studentIds();
        if (ids == null || ids.isEmpty()) {
            throw new DomainRuleViolation("PG_RECONCILE_NONE", "Choose the students to record, or all of them.",
                    new DomainRuleViolation.Remedy("Tick the students, or record every one read with high or medium confidence.", "PG School"));
        }
        List<Map<String, Object>> rows = jdbc.sql("SELECT x.* FROM admissions.pg_cycle_commit(CAST(:ids AS uuid[]), :s, :r) x")
                .param("ids", ids(ids), Types.ARRAY).param("s", body.session()).param("r", blank(body.reason()), Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = outcomes(rows);
        Map<String, Long> status = new LinkedHashMap<>();
        rows.stream().filter(r -> r.get("cycle_status") != null).forEach(r -> status.merge(String.valueOf(r.get("cycle_status")), 1L, Long::sum));
        out.put("byStatus", status);
        out.put("rows", rows.size() > 500 ? rows.subList(0, 500) : rows);
        return out;
    }

    @GetMapping("/quality")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> quality(@RequestParam(required = false) String session, @RequestParam(required = false) String issue,
                                @RequestParam(defaultValue = "0") @Min(0) int page, @RequestParam(defaultValue = "100") @Min(1) @Max(1000) int size) {
        need("VIEW_PG_ACADEMIC_HISTORY");
        String s = session(session);
        List<Map<String, Object>> all = jdbc.sql("""
                SELECT q.issue, q.detail, st.id AS student_id, st.matric_no, st.surname, st.other_names, p.name AS programme, d.name AS department
                  FROM admissions.pg_data_quality(:s) q
                  JOIN people.student st ON st.id = q.student_id
                  JOIN ref.programme p ON p.code = st.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE (CAST(:dept AS text) IS NULL OR p.dept_code = :dept) AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac)
                 ORDER BY q.issue, st.surname, st.other_names
                """).param("s", s).param("dept", boundDept(), Types.VARCHAR).param("fac", boundFaculty(), Types.VARCHAR).query().listOfRows();
        Map<String, Long> by = new LinkedHashMap<>();
        all.forEach(r -> by.merge(String.valueOf(r.get("issue")), 1L, Long::sum));
        List<Map<String, Object>> rows = all.stream().filter(r -> issue == null || issue.isBlank() || issue.equals(r.get("issue"))).toList();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("byIssue", by);
        out.put("matching", rows.size());
        out.put("rows", rows.stream().skip((long) page * size).limit(size).toList());
        return out;
    }
}
