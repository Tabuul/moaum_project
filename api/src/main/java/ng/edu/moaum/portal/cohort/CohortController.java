package ng.edu.moaum.portal.cohort;

import java.sql.Types;
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Where every student stands (V331), under /api/v1/cohorts: the computed position of the register
 * (people.academic_position) read by classification, cohort, faculty, programme, level, status and issue; the
 * reconciliation review with the Registry's decisions; the data quality report; the policy — the spillover limit,
 * the programmes' lengths, the sessions merged. Readers are bounded by their office's scope; decisions are the
 * Registry's; nothing here rewrites a student's history.
 */
@RestController
@RequestMapping("/api/v1/cohorts")
class CohortController {

    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dvc','OFFICE_vc',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_facultyofficer','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String DECIDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records')";
    private static final String SETTERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_super')";
    private static final Set<String> CLASSIFICATIONS = Set.of("ACTIVE", "GRADUATED", "SPILLOVER", "SPILLOVER_LIMIT_REACHED", "GRADUATION_ELIGIBLE", "REQUIRES_REVIEW",
            "ADMITTED", "DEFERRED", "WITHDRAWN", "VOLUNTARY_WITHDRAWAL", "EXPELLED", "DECEASED", "TRANSFERRED_OUT", "RUSTICATED", "SUSPENDED", "DORMANT", "HISTORICAL", "REVIEW");

    /** a student's position as the lists show it */
    private static final String ROW = """
            SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.jamb_reg_no, s.sex,
                   p.code AS programme_code, p.name AS programme, d.code AS dept_code, d.name AS department, f.code AS faculty_code, f.name AS faculty,
                   ap.jamb_year, ap.matric_year, ap.entry_session, ap.effective_cohort, ap.cohort_source, ap.entry_level, ap.final_level, ap.duration_years,
                   ap.current_session, ap.current_level, ap.computed_level, ap.expected_completion, ap.deferred_sessions, ap.elapsed_sessions,
                   ap.spillover_years, ap.spillover_state, ap.registered_current, ap.enrolled_current, ap.last_session,
                   ap.graduation_state, ap.graduation_session, ap.existing_status, ap.classification, ap.proposed_status, ap.rule, ap.confidence,
                   array_to_string(ap.issues, ',') AS issues, ap.computed_at
              FROM people.academic_position ap
              JOIN people.student s ON s.id = ap.student_id
              JOIN ref.programme p ON p.code = s.programme_code
              JOIN ref.department d ON d.code = p.dept_code
              JOIN ref.faculty f ON f.code = p.faculty_code
            """;
    private static final String WHERE = """
             WHERE (:fac::text IS NULL OR f.code = :fac) AND (:dept::text IS NULL OR d.code = :dept) AND (:prog::text IS NULL OR p.code = :prog)
               AND (:ncls = 0 OR ap.classification = ANY(string_to_array(:cls, ','))
                    OR (:cls LIKE '%HISTORICAL%' AND ap.existing_status NOT IN ('ACTIVE','PROBATION','ADMITTED'))
                    OR (:cls LIKE '%REVIEW%' AND (ap.confidence = 'REVIEW' OR ap.classification IN ('REQUIRES_REVIEW','SPILLOVER_LIMIT_REACHED'))))
               AND (:cohort::text IS NULL OR ap.effective_cohort = :cohort)
               AND (:entry::text IS NULL OR ap.entry_session = :entry)
               AND (:jamb::int IS NULL OR ap.jamb_year = :jamb)
               AND (:level::int IS NULL OR ap.current_level = :level)
               AND (:duration::int IS NULL OR ap.duration_years = :duration)
               AND (:status::text IS NULL OR ap.existing_status = :status)
               AND (:grad::text IS NULL OR ap.graduation_state = :grad)
               AND (:spill::text IS NULL OR ap.spillover_state = :spill)
               AND (:conf::text IS NULL OR ap.confidence = :conf)
               AND (:issue::text IS NULL OR :issue = ANY(ap.issues))
               AND (:sex::text IS NULL OR s.sex = :sex)
               AND (:entrymode::text IS NULL OR s.entry_mode = :entrymode)
               AND (:like::text IS NULL OR s.matric_no ILIKE :like OR s.admission_no ILIKE :like OR s.jamb_reg_no ILIKE :like
                    OR s.surname ILIKE :like OR s.other_names ILIKE :like OR (s.surname || ' ' || s.other_names) ILIKE :like)
            """;

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    CohortController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the filters, bound to the office's scope whatever the parameters say */
    private JdbcClient.StatementSpec filtered(String sql, String fac, String dept, String prog, String classification, String cohort, String entry, Integer jamb,
                                              Integer level, Integer duration, String status, String grad, String spill, String conf, String issue, String sex, String entryMode, String q) {
        OfficeScope.Bound b = scope.bound(fac, dept, prog);
        List<String> cls = classification == null || classification.isBlank() || "all".equalsIgnoreCase(classification) ? List.of() : List.of(classification.toUpperCase().split(","));
        for (String c : cls) if (!CLASSIFICATIONS.contains(c)) throw new DomainRuleViolation("COHORT_CLASS", "Unknown classification " + c + ".", new DomainRuleViolation.Remedy("Choose one of the standings offered.", "Registry"));
        return jdbc.sql(sql)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .param("ncls", cls.size()).param("cls", String.join(",", cls))
                .param("cohort", blank(cohort), Types.VARCHAR).param("entry", blank(entry), Types.VARCHAR).param("jamb", jamb, Types.INTEGER)
                .param("level", level, Types.INTEGER).param("duration", duration, Types.INTEGER).param("status", blank(status) == null ? null : status.toUpperCase(), Types.VARCHAR)
                .param("grad", blank(grad) == null ? null : grad.toUpperCase(), Types.VARCHAR).param("spill", blank(spill) == null ? null : spill.toUpperCase(), Types.VARCHAR)
                .param("conf", blank(conf) == null ? null : conf.toUpperCase(), Types.VARCHAR).param("issue", blank(issue) == null ? null : issue.toUpperCase(), Types.VARCHAR)
                .param("sex", blank(sex), Types.VARCHAR).param("entrymode", blank(entryMode), Types.VARCHAR)
                .param("like", blank(q) == null ? null : "%" + q.trim() + "%", Types.VARCHAR);
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v;
    }

    /** the figures: who stands where, within the scope and the filters */
    @GetMapping("/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                @RequestParam(required = false) String cohort, @RequestParam(required = false) String entry, @RequestParam(required = false) Integer jamb,
                                @RequestParam(required = false) Integer level, @RequestParam(required = false) Integer duration, @RequestParam(required = false) String status,
                                @RequestParam(required = false) String q) {
        Map<String, Object> out = new LinkedHashMap<>();
        String base = "FROM people.academic_position ap JOIN people.student s ON s.id = ap.student_id JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = p.faculty_code" + WHERE;
        java.util.function.Function<String, JdbcClient.StatementSpec> with = sql -> filtered(sql, fac, dept, prog, null, cohort, entry, jamb, level, duration, status, null, null, null, null, null, null, q);
        out.put("totals", with.apply("""
                SELECT count(*) AS students,
                       count(*) FILTER (WHERE ap.classification = 'ACTIVE') AS current,
                       count(*) FILTER (WHERE ap.classification = 'GRADUATED') AS graduated,
                       count(*) FILTER (WHERE ap.classification = 'SPILLOVER') AS spillover,
                       count(*) FILTER (WHERE ap.classification = 'SPILLOVER_LIMIT_REACHED') AS spillover_limit,
                       count(*) FILTER (WHERE ap.classification = 'GRADUATION_ELIGIBLE') AS eligible,
                       count(*) FILTER (WHERE ap.classification = 'ACTIVE' AND ap.current_session = ap.expected_completion) AS expected_to_complete,
                       count(*) FILTER (WHERE ap.classification = 'REQUIRES_REVIEW') AS requires_review,
                       count(*) FILTER (WHERE ap.confidence = 'REVIEW' OR ap.classification IN ('REQUIRES_REVIEW','SPILLOVER_LIMIT_REACHED')) AS review,
                       count(*) FILTER (WHERE ap.existing_status NOT IN ('ACTIVE','PROBATION','ADMITTED')) AS historical,
                       count(*) FILTER (WHERE ap.classification = 'DEFERRED') AS deferred,
                       count(*) FILTER (WHERE ap.existing_status IN ('WITHDRAWN','VOLUNTARY_WITHDRAWAL')) AS withdrawn,
                       count(*) FILTER (WHERE ap.existing_status IN ('EXPELLED','RUSTICATED','TRANSFERRED_OUT','DECEASED','DORMANT','SUSPENDED')) AS discontinued,
                       count(*) FILTER (WHERE ap.proposed_status <> ap.existing_status) AS proposals,
                       count(*) FILTER (WHERE ap.proposed_status <> ap.existing_status AND ap.confidence = 'VALIDATED') AS proposals_validated,
                       min(ap.computed_at) AS computed_from, max(ap.computed_at) AS computed_to,
                       (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1) AS current_session
                """ + base).query().singleRow());
        out.put("byClassification", with.apply("SELECT ap.classification AS key, count(*) AS n " + base + " GROUP BY ap.classification ORDER BY n DESC").query().listOfRows());
        out.put("byCohort", with.apply("SELECT coalesce(ap.effective_cohort, 'Not stated') AS key, ap.jamb_year, count(*) AS n, count(*) FILTER (WHERE ap.classification = 'ACTIVE') AS current, count(*) FILTER (WHERE ap.classification = 'GRADUATED') AS graduated, count(*) FILTER (WHERE ap.classification IN ('SPILLOVER','SPILLOVER_LIMIT_REACHED')) AS spillover " + base + " GROUP BY ap.effective_cohort, ap.jamb_year ORDER BY ap.effective_cohort DESC NULLS LAST, ap.jamb_year").query().listOfRows());
        out.put("byFaculty", with.apply("SELECT f.name AS key, count(*) AS n, count(*) FILTER (WHERE ap.classification = 'ACTIVE') AS current, count(*) FILTER (WHERE ap.classification = 'GRADUATED') AS graduated, count(*) FILTER (WHERE ap.classification IN ('SPILLOVER','SPILLOVER_LIMIT_REACHED')) AS spillover, count(*) FILTER (WHERE ap.confidence = 'REVIEW' OR ap.classification IN ('REQUIRES_REVIEW','SPILLOVER_LIMIT_REACHED')) AS review " + base + " GROUP BY f.name ORDER BY n DESC").query().listOfRows());
        out.put("byLevel", with.apply("SELECT ap.current_level AS key, count(*) AS n " + base + " AND ap.classification IN ('ACTIVE','SPILLOVER','SPILLOVER_LIMIT_REACHED','GRADUATION_ELIGIBLE') GROUP BY ap.current_level ORDER BY ap.current_level").query().listOfRows());
        out.put("bySpillover", with.apply("SELECT ap.spillover_state AS key, count(*) AS n " + base + " AND ap.spillover_state <> 'NOT_APPLICABLE' GROUP BY ap.spillover_state ORDER BY ap.spillover_state").query().listOfRows());
        out.put("byIssue", with.apply("SELECT i AS key, count(*) AS n " + base.replace("FROM people.academic_position ap", "FROM people.academic_position ap CROSS JOIN LATERAL unnest(ap.issues) AS i") + " GROUP BY i ORDER BY n DESC").query().listOfRows());
        out.put("policy", jdbc.sql("SELECT max_spillover_years, updated_at FROM policy.progression_setting WHERE row_no").query().singleRow());
        return out;
    }

    /** the students, paged, within the scope and the filters; names A–Z unless another sort is asked for */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                 @RequestParam(required = false) String classification, @RequestParam(required = false) String cohort, @RequestParam(required = false) String entry,
                                 @RequestParam(required = false) Integer jamb, @RequestParam(required = false) Integer level, @RequestParam(required = false) Integer duration,
                                 @RequestParam(required = false) String status, @RequestParam(required = false) String grad, @RequestParam(required = false) String spill,
                                 @RequestParam(required = false) String conf, @RequestParam(required = false) String issue, @RequestParam(required = false) String sex,
                                 @RequestParam(required = false) String entryMode, @RequestParam(required = false) String q,
                                 @RequestParam(defaultValue = "name") String sort, @RequestParam(defaultValue = "asc") String dir,
                                 @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        int sz = Math.max(1, Math.min(size, 2000));
        int pg = Math.max(1, page);
        String order = switch (sort) {
            case "matric" -> "s.matric_no";
            case "cohort" -> "ap.effective_cohort";
            case "jamb" -> "ap.jamb_year";
            case "level" -> "ap.current_level";
            case "expected" -> "ap.expected_completion";
            case "spillover" -> "ap.spillover_years";
            case "programme" -> "p.name";
            case "classification" -> "ap.classification";
            default -> "s.surname";
        };
        String direction = "desc".equalsIgnoreCase(dir) ? "DESC" : "ASC";
        List<Map<String, Object>> rows = filtered(ROW.replace("SELECT s.id,", "SELECT count(*) OVER() AS total, s.id,") + WHERE
                + " ORDER BY %s %s NULLS LAST, s.surname, s.other_names LIMIT :n OFFSET :o".formatted(order, direction),
                fac, dept, prog, classification, cohort, entry, jamb, level, duration, status, grad, spill, conf, issue, sex, entryMode, q)
                .param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        rows.forEach(r -> r.remove("total"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows); out.put("total", total); out.put("page", pg); out.put("size", sz);
        return out;
    }

    /** one student's complete lifecycle: the position, the status history, the enrolments, the registrations, the graduation record,
     *  the deferments, the programme changes, the decisions taken, and what is still outstanding */
    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable UUID id, @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog) {
        Map<String, Object> pos = filtered(ROW + WHERE + " AND s.id = :id", fac, dept, prog, null, null, null, null, null, null, null, null, null, null, null, null, null, null)
                .param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", id));
        Map<String, Object> out = new LinkedHashMap<>(pos);
        out.put("statusHistory", jdbc.sql("SELECT from_status, to_status, instrument, effective_on, expires_on, reason FROM people.status_change WHERE student_id = :s ORDER BY effective_on, id").param("s", id).query().listOfRows());
        out.put("enrolments", jdbc.sql("SELECT session, level, mode, enrolled_at FROM people.enrolment WHERE student_id = :s ORDER BY session").param("s", id).query().listOfRows());
        out.put("registrations", jdbc.sql("SELECT session, semester, level, status, submitted_at, approved_at FROM registration.course_registration WHERE student_id = :s ORDER BY session, semester").param("s", id).query().listOfRows());
        out.put("graduands", jdbc.sql("SELECT session, cgpa, award, unmet, senate_state, senate_minute FROM records.graduand WHERE student_id = :s ORDER BY session").param("s", id).query().listOfRows());
        out.put("deferments", jdbc.sql("SELECT reference, kind, session, semester, state, return_session, return_semester, extension_semesters FROM people.deferment WHERE student_id = :s ORDER BY created_at").param("s", id).query().listOfRows());
        out.put("programmeChanges", jdbc.sql("""
                SELECT r.session, r.from_programme_code, r.from_programme, r.to_programme_code, r.to_programme, r.state, r.decided_at, r.kind
                  FROM admissions.programme_change_request r JOIN people.student s ON s.candidate_id = r.candidate_id WHERE s.id = :s ORDER BY r.requested_at
                """).param("s", id).query().listOfRows());
        out.put("decisions", jdbc.sql("""
                SELECT d.id, d.previous_status, d.proposed_status, d.final_status, d.classification, d.previous_cohort, d.effective_cohort, d.rule, d.reason,
                       helpdesk.person_name(d.officer) AS officer, d.actor_office, d.batch_ref, d.decided_at
                  FROM people.cohort_decision d WHERE d.student_id = :s ORDER BY d.decided_at DESC
                """).param("s", id).query().listOfRows());
        out.put("matricHistory", jdbc.sql("SELECT matric_no, issued_at, reason FROM people.matric_history WHERE student_id = :s ORDER BY issued_at").param("s", id).query().listOfRows());
        out.put("outstanding", jdbc.sql("SELECT course_code, title, units, failed_in FROM registration.carryovers(:s) ORDER BY course_code").param("s", id).query().listOfRows());
        out.put("override", jdbc.sql("SELECT effective_cohort, reason, helpdesk.person_name(set_by) AS set_by, set_at FROM people.cohort_override WHERE student_id = :s").param("s", id).query().listOfRows().stream().findFirst().orElse(null));
        out.put("sessions", jdbc.sql("SELECT name, state, merged_into FROM policy.academic_session ORDER BY starts_on").query().listOfRows());
        return out;
    }

    public record Decision(@NotBlank @Size(max = 40) String finalStatus, @NotBlank @Size(max = 2000) String reason, @Size(max = 60) String batch) {
    }

    /** the Registry decides one student's standing, on a reason; the status changes where it differs; GRADUATED stays the Senate's */
    @PostMapping("/students/{id}/decision")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody Decision body) {
        UUID d = jdbc.sql("SELECT people.decide_cohort(:s, :st, :r, :b)").param("s", id).param("st", body.finalStatus().trim().toUpperCase()).param("r", body.reason().trim())
                .param("b", blank(body.batch()), Types.VARCHAR).query(UUID.class).single();
        return Map.of("id", d, "studentId", id, "status", body.finalStatus().trim().toUpperCase());
    }

    public record CohortIn(@Size(max = 9) String cohort, @NotBlank @Size(max = 2000) String reason) {
    }

    /** the effective cohort corrected on evidence (a re-entry, a transfer in), or the correction removed; the entry session stays */
    @PostMapping("/students/{id}/cohort")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> cohort(@PathVariable UUID id, @Valid @RequestBody CohortIn body) {
        jdbc.sql("SELECT people.set_cohort_override(:s, :c, :r)").param("s", id).param("c", blank(body.cohort()), Types.VARCHAR).param("r", body.reason().trim()).query().singleRow();
        return Map.of("studentId", id, "cohort", blank(body.cohort()) == null ? "" : body.cohort());
    }

    public record Apply(@NotBlank String rule, @Size(max = 2000) String reason, @Size(max = 60) String batch, Boolean dryRun) {
    }

    /** a rule's validated proposals applied in one act — only the Senate's approved awards (R1) — or counted first */
    @PostMapping("/apply")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> apply(@Valid @RequestBody Apply body) {
        boolean dry = body.dryRun() == null || body.dryRun();
        Map<String, Object> r = jdbc.sql("SELECT * FROM people.apply_cohort_rule(:rule, :reason, :batch, :dry)")
                .param("rule", body.rule().trim().toUpperCase()).param("reason", blank(body.reason()), Types.VARCHAR).param("batch", blank(body.batch()), Types.VARCHAR).param("dry", dry)
                .query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("dryRun", dry);
        return out;
    }

    /** the whole register recomputed now, after a bulk load or a policy change made under maintenance */
    @PostMapping("/refresh")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> refresh() {
        Integer n = jdbc.sql("SELECT people.refresh_academic_position(NULL)").query(Integer.class).single();
        return Map.of("computed", n);
    }

    /* ── the policy: the spillover limit, the programmes' lengths, the sessions merged ── */

    @GetMapping("/settings")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> settings() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("policy", jdbc.sql("SELECT max_spillover_years, updated_at, helpdesk.person_name(updated_by) AS updated_by FROM policy.progression_setting WHERE row_no").query().singleRow());
        out.put("sessions", jdbc.sql("""
                SELECT a.name, a.state, a.starts_on, a.ends_on, a.merged_into, a.merged_reason, a.merged_minute, a.merged_on, helpdesk.person_name(a.merged_by) AS merged_by,
                       (SELECT count(*) FROM people.student s WHERE s.entry_session = a.name) AS entrants,
                       (SELECT count(*) FROM people.academic_position ap WHERE ap.effective_cohort = a.name) AS cohort_size
                  FROM policy.academic_session a ORDER BY a.starts_on
                """).query().listOfRows());
        out.put("programmes", jdbc.sql("""
                SELECT p.code, p.name, p.category, p.pg_award, p.archived, f.name AS faculty, d.name AS department, p.final_level, p.duration_years, p.final_level_note,
                       CASE WHEN p.final_level IS NULL AND p.duration_years IS NULL AND coalesce(p.category, '') <> 'POST GRADUATE' THEN finance.final_level(p.code) END AS rule_level,
                       (SELECT count(*) FROM people.student s WHERE s.programme_code = p.code AND s.status IN ('ACTIVE','PROBATION')) AS active_students
                  FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE NOT coalesce(p.archived, false) ORDER BY (p.final_level IS NULL AND p.duration_years IS NULL) DESC, f.name, d.name, p.name
                """).query().listOfRows());
        out.put("awards", jdbc.sql("""
                SELECT p.pg_award AS award, count(*) AS programmes, count(*) FILTER (WHERE p.duration_years IS NOT NULL OR p.final_level IS NOT NULL) AS configured,
                       min(p.duration_years) AS min_years, max(p.duration_years) AS max_years,
                       (SELECT count(*) FROM people.student s JOIN ref.programme q ON q.code = s.programme_code WHERE q.pg_award = p.pg_award AND s.status IN ('ACTIVE','PROBATION')) AS active_students
                  FROM ref.programme p WHERE p.pg_award IS NOT NULL AND NOT coalesce(p.archived, false)
                 GROUP BY p.pg_award ORDER BY active_students DESC, p.pg_award
                """).query().listOfRows());
        return out;
    }

    public record Policy(@NotNull @Min(0) @Max(6) Integer maxSpilloverYears) {
    }

    @PutMapping("/settings")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> savePolicy(@Valid @RequestBody Policy body) {
        jdbc.sql("SELECT policy.set_max_spillover(:y)").param("y", body.maxSpilloverYears()).query().singleRow();
        return Map.of("maxSpilloverYears", body.maxSpilloverYears());
    }

    /** a programme's length: its last level (the student's length follows from their entry level), its length in sessions, or both */
    public record Length(Integer finalLevel, @Min(1) @Max(8) Integer years, @Size(max = 300) String note) {
    }

    @PutMapping("/programmes/{code}")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> programmeLength(@PathVariable String code, @Valid @RequestBody Length body) {
        jdbc.sql("SELECT ref.set_programme_length(:c, :l, :y, :n)").param("c", code.trim().toUpperCase())
                .param("l", body.finalLevel(), Types.INTEGER).param("y", body.years(), Types.INTEGER).param("n", blank(body.note()), Types.VARCHAR).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("code", code.trim().toUpperCase());
        out.put("finalLevel", body.finalLevel());
        out.put("years", body.years());
        return out;
    }

    /** every active programme of one postgraduate award takes its length in sessions in one act */
    public record AwardLength(@NotBlank @Size(max = 20) String award, @NotNull @Min(1) @Max(8) Integer years, @Size(max = 300) String note) {
    }

    @PostMapping("/programmes/by-award")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> awardLength(@Valid @RequestBody AwardLength body) {
        Integer n = jdbc.sql("SELECT ref.set_programme_length_by_award(:a, :y, :n)").param("a", body.award().trim()).param("y", body.years()).param("n", blank(body.note()), Types.VARCHAR).query(Integer.class).single();
        return Map.of("award", body.award().trim().toUpperCase(), "years", body.years(), "programmes", n);
    }

    public record Merge(@NotBlank @Size(max = 9) String into, @NotBlank @Size(max = 2000) String reason, @Size(max = 120) String minute) {
    }

    @PostMapping("/sessions/{session}/{year}/merge")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> merge(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Merge body) {
        String name = session + "/" + year;
        jdbc.sql("SELECT policy.merge_session(:s, :into, :r, :m)").param("s", name).param("into", body.into().trim()).param("r", body.reason().trim()).param("m", blank(body.minute()), Types.VARCHAR).query().singleRow();
        return Map.of("session", name, "mergedInto", body.into().trim());
    }

    public record Why(@NotBlank @Size(max = 2000) String reason) {
    }

    @PostMapping("/sessions/{session}/{year}/unmerge")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> unmerge(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Why body) {
        String name = session + "/" + year;
        jdbc.sql("SELECT policy.unmerge_session(:s, :r)").param("s", name).param("r", body.reason().trim()).query().singleRow();
        return Map.of("session", name, "mergedInto", "");
    }
}
