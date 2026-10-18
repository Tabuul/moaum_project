package ng.edu.moaum.portal.cohort;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.graduation.GraduationService;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.postgresql.util.PSQLException;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V558: the student lifecycle reconciliation, under /api/v1/cohorts/lifecycle — the cohort engine's position of every active student
 * (people.academic_position) turned into a recommendation (people.lifecycle_recommendation): graduation candidates, spillover year 1
 * and 2, the maximum spillover reached, records to review or to correct. The figures are clickable down to the students; the
 * Registry reviews and verifies a recommendation, previews a batch, and reconciles it a page at a time (RECON/YYYY/NNNNNN) — each
 * student all or nothing, revalidated at that moment; a reconciliation is corrected on a reason and never rewritten. Readers are held
 * to their office's scope; the acts are the Academic Office's and the Registry's, and the database holds the office and the scope too.
 */
@RestController
@RequestMapping("/api/v1/cohorts/lifecycle")
class LifecycleController {

    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dvc','OFFICE_vc',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_facultyofficer','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String ACTORS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records')";
    private static final Set<String> RECOMMENDATIONS = Set.of("GRADUATION_CANDIDATE", "SPILLOVER", "SPILLOVER_YEAR_1", "SPILLOVER_YEAR_2", "SPILLOVER_YEAR_3",
            "SPILLOVER_YEAR_4", "SPILLOVER_YEAR_5", "SPILLOVER_YEAR_6", "MAXIMUM_SPILLOVER_REACHED", "ON_GRADUATION_LIST", "WITHIN_NORMAL_DURATION",
            "DATA_INCOMPLETE", "REQUIRES_REVIEW");
    private static final Set<String> STATES = Set.of("PENDING", "UNDER_REVIEW", "VERIFIED", "REJECTED", "REQUIRES_CORRECTION", "RECONCILED");
    private static final Set<String> CONFIDENCES = Set.of("HIGH", "MEDIUM", "LOW");
    private static final Set<String> COMPLETIONS = Set.of("COMPLETED", "OUTSTANDING_COURSES", "AWAITING_RESULT", "FINAL_LEVEL_NOT_REACHED", "NO_PUBLISHED_RESULT", "NOT_CHECKED");
    private static final int PAGE_CHECKED = 1000;
    private static final int STEP = 200;

    /** the recommendations within the scope and the filters, read once (a scoped list read the view in a loop: 0.9 s, now 0.1 s on
     *  the live-shaped copy), then joined to the student and the structure */
    private static final String FROM = """
             FROM (WITH x AS MATERIALIZED (
                      SELECT * FROM people.lifecycle_recommendation lr
                       WHERE lr.programme_code IN (SELECT p0.code FROM ref.programme p0
                                                    WHERE (:fac::text IS NULL OR p0.faculty_code = :fac) AND (:dept::text IS NULL OR p0.dept_code = :dept)
                                                      AND (:prog::text IS NULL OR p0.code = :prog))
                         AND (:nrec = 0 OR lr.recommendation = ANY(string_to_array(:rec, ','))
                              OR (',' || :rec || ',' LIKE '%,SPILLOVER,%' AND lr.recommendation LIKE 'SPILLOVER_YEAR_%'))
                         AND (:state::text IS NULL OR lr.review_state = :state)
                         AND (:conf::text IS NULL OR lr.confidence = :conf)
                         AND (:basis::text IS NULL OR lr.candidate_basis = :basis)
                         AND (:completion::text IS NULL OR coalesce(lr.completion, CASE WHEN lr.in_pool THEN 'NOT_CHECKED' END) = :completion)
                         AND (:cohort::text IS NULL OR lr.effective_cohort = :cohort)
                         AND (:entry::text IS NULL OR lr.entry_session = :entry)
                         AND (:matric::int IS NULL OR lr.matric_year = :matric)
                         AND (:level::int IS NULL OR lr.current_level = :level)
                         AND (:status::text IS NULL OR lr.existing_status = :status)
                         AND (:batch::text IS NULL OR lr.batch_ref = :batch)
                         AND (CAST(:one AS uuid) IS NULL OR lr.student_id = CAST(:one AS uuid)))
                   SELECT * FROM x) lr
             JOIN people.student s ON s.id = lr.student_id
             JOIN ref.programme p ON p.code = s.programme_code
             JOIN ref.department d ON d.code = p.dept_code
             JOIN ref.faculty f ON f.code = p.faculty_code
            WHERE (:fac::text IS NULL OR f.code = :fac) AND (:dept::text IS NULL OR d.code = :dept) AND (:prog::text IS NULL OR p.code = :prog)
              AND (:like::text IS NULL OR s.matric_no ILIKE :like OR s.admission_no ILIKE :like OR s.surname ILIKE :like OR s.other_names ILIKE :like
                   OR (s.surname || ' ' || s.other_names) ILIKE :like)
            """;

    private static final String ROW = """
            SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.sex, s.entry_mode,
                   p.code AS programme_code, p.name AS programme, d.code AS dept_code, d.name AS department, f.code AS faculty_code, f.name AS faculty,
                   lr.entry_session, lr.effective_cohort, lr.cohort_source, lr.matric_year, lr.duration_years, lr.duration_source, lr.final_level,
                   lr.current_level, lr.computed_level, lr.expected_completion, lr.current_session, lr.deferred_sessions, lr.spillover_years,
                   lr.registered_current, lr.enrolled_current, lr.last_session, lr.existing_status, lr.recommendation, lr.candidate_basis, lr.confidence,
                   lr.confidence_reasons, lr.explanation, lr.actionable, coalesce(lr.completion, CASE WHEN lr.in_pool THEN 'NOT_CHECKED' END) AS completion,
                   lr.outstanding_courses, lr.awaiting_courses, lr.completion_checked_at, lr.review_state, lr.review_note,
                   helpdesk.person_name(lr.reviewed_by) AS reviewed_by, lr.reviewed_at, lr.batch_ref, lr.reconciled_at, lr.computed_at
            """;

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final GraduationService graduation;
    private final TransactionTemplate tx;
    private final tools.jackson.databind.ObjectMapper json;

    LifecycleController(JdbcClient jdbc, OfficeScope scope, GraduationService graduation, PlatformTransactionManager transactions,
                        tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.graduation = graduation;
        this.tx = new TransactionTemplate(transactions);
        this.json = json;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String upper(String v) {
        return blank(v) == null ? null : v.trim().toUpperCase();
    }

    /** the filters a list, a summary and a selection share */
    public record Filter(String rec, String state, String conf, String basis, String completion, String cohort, String entry, Integer matricYear,
                         Integer level, String status, String batch, String fac, String dept, String prog, String q) {
    }

    private JdbcClient.StatementSpec filtered(String sql, Filter in) {
        OfficeScope.Bound b = scope.bound(in.fac(), in.dept(), in.prog());
        List<String> recs = blank(in.rec()) == null ? List.of() : List.of(in.rec().trim().toUpperCase().split(","));
        for (String r : recs) if (!RECOMMENDATIONS.contains(r)) throw unknown("recommendation", r);
        String state = upper(in.state());
        if (state != null && !STATES.contains(state)) throw unknown("review state", state);
        String conf = upper(in.conf());
        if (conf != null && !CONFIDENCES.contains(conf)) throw unknown("confidence", conf);
        String completion = upper(in.completion());
        if (completion != null && !COMPLETIONS.contains(completion)) throw unknown("completion", completion);
        return jdbc.sql(sql)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .param("nrec", recs.size()).param("rec", String.join(",", recs))
                .param("state", state, Types.VARCHAR).param("conf", conf, Types.VARCHAR).param("basis", upper(in.basis()), Types.VARCHAR)
                .param("completion", completion, Types.VARCHAR).param("cohort", blank(in.cohort()), Types.VARCHAR).param("entry", blank(in.entry()), Types.VARCHAR)
                .param("matric", in.matricYear(), Types.INTEGER).param("level", in.level(), Types.INTEGER).param("status", upper(in.status()), Types.VARCHAR)
                .param("batch", blank(in.batch()), Types.VARCHAR).param("one", null, Types.VARCHAR)
                .param("like", blank(in.q()) == null ? null : "%" + in.q().trim() + "%", Types.VARCHAR);
    }

    private static DomainRuleViolation unknown(String what, String value) {
        return new DomainRuleViolation("LIFECYCLE_FILTER", "Unknown " + what + " " + value + ".", new DomainRuleViolation.Remedy("Choose one of the values offered.", "Registry"));
    }

    private Filter filterOf(String rec, String state, String conf, String basis, String completion, String cohort, String entry, Integer matricYear, Integer level,
                            String status, String batch, String fac, String dept, String prog, String q) {
        return new Filter(rec, state, conf, basis, completion, cohort, entry, matricYear, level, status, batch, fac, dept, prog, q);
    }

    /* ── the figures, every one a way into its students ── */

    @SuppressWarnings("unchecked")
    @GetMapping("/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                @RequestParam(required = false) String cohort, @RequestParam(required = false) String entry, @RequestParam(required = false) Integer matricYear,
                                @RequestParam(required = false) Integer level, @RequestParam(required = false) String q) {
        Filter in = filterOf(null, null, null, null, null, cohort, entry, matricYear, level, null, null, fac, dept, prog, q);
        // one pass: the recommendations read once, every breakdown taken from that
        String sql = """
                WITH v AS MATERIALIZED (
                    SELECT lr.recommendation, lr.confidence, lr.review_state, lr.candidate_basis, lr.effective_cohort, lr.in_pool,
                           coalesce(lr.completion, CASE WHEN lr.in_pool THEN 'NOT_CHECKED' END) AS completion, lr.completion_checked_at, lr.computed_at,
                           f.code AS fc, f.name AS fn, d.code AS dc, d.name AS dn, p.code AS pc, p.name AS pn
                """ + FROM + """
                )
                SELECT jsonb_build_object(
                    'total', (SELECT count(*) FROM v),
                    'byRecommendation', coalesce((SELECT jsonb_agg(x ORDER BY x.recommendation) FROM (
                        SELECT recommendation, count(*) AS n,
                               count(*) FILTER (WHERE confidence = 'HIGH') AS high, count(*) FILTER (WHERE confidence = 'MEDIUM') AS medium,
                               count(*) FILTER (WHERE confidence = 'LOW') AS low,
                               count(*) FILTER (WHERE review_state = 'PENDING') AS pending, count(*) FILTER (WHERE review_state = 'UNDER_REVIEW') AS under_review,
                               count(*) FILTER (WHERE review_state = 'VERIFIED') AS verified, count(*) FILTER (WHERE review_state = 'REJECTED') AS rejected,
                               count(*) FILTER (WHERE review_state = 'REQUIRES_CORRECTION') AS requires_correction,
                               count(*) FILTER (WHERE review_state = 'RECONCILED') AS reconciled,
                               count(*) FILTER (WHERE candidate_basis = 'FINAL_YEAR') AS final_year,
                               count(*) FILTER (WHERE candidate_basis = 'COMPLETED_BEYOND_LENGTH') AS completed_beyond
                          FROM v GROUP BY recommendation) x), '[]'::jsonb),
                    'byCompletion', coalesce((SELECT jsonb_agg(x ORDER BY x.n DESC) FROM (
                        SELECT completion, count(*) AS n FROM v WHERE in_pool GROUP BY completion) x), '[]'::jsonb),
                    'byCohort', coalesce((SELECT jsonb_agg(x ORDER BY x.cohort DESC NULLS LAST, x.recommendation) FROM (
                        SELECT effective_cohort AS cohort, recommendation, count(*) AS n FROM v GROUP BY effective_cohort, recommendation) x), '[]'::jsonb),
                    'byFaculty', coalesce((SELECT jsonb_agg(x ORDER BY x.name, x.recommendation) FROM (
                        SELECT fc AS code, fn AS name, recommendation, count(*) AS n FROM v GROUP BY fc, fn, recommendation) x), '[]'::jsonb),
                    'byDepartment', coalesce((SELECT jsonb_agg(x ORDER BY x.name, x.recommendation) FROM (
                        SELECT dc AS code, dn AS name, fc AS faculty, recommendation, count(*) AS n FROM v GROUP BY dc, dn, fc, recommendation) x), '[]'::jsonb),
                    'byProgramme', coalesce((SELECT jsonb_agg(x ORDER BY x.name, x.recommendation) FROM (
                        SELECT pc AS code, pn AS name, dc AS department, recommendation, count(*) AS n FROM v GROUP BY pc, pn, dc, recommendation) x), '[]'::jsonb),
                    'pool', (SELECT count(*) FROM v WHERE in_pool),
                    'checked', (SELECT count(*) FROM v WHERE in_pool AND completion <> 'NOT_CHECKED'),
                    'checkedFrom', (SELECT min(completion_checked_at) FROM v WHERE in_pool),
                    'checkedTo', (SELECT max(completion_checked_at) FROM v WHERE in_pool),
                    'computedFrom', (SELECT min(computed_at) FROM v),
                    'computedTo', (SELECT max(computed_at) FROM v)
                )::text
                """;
        Map<String, Object> out = new LinkedHashMap<>(json.readValue(filtered(sql, in).query(String.class).single(), Map.class));
        out.put("currentSession", jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1").query(String.class).optional().orElse(null));
        out.put("maxSpilloverYears", jdbc.sql("SELECT max_spillover_years FROM policy.progression_setting WHERE row_no").query(Integer.class).single());
        out.put("batches", jdbc.sql("SELECT count(*) FROM people.lifecycle_batch").query(Long.class).single());
        return out;
    }

    /** the students behind a figure, paged, names A–Z */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String rec, @RequestParam(required = false) String state, @RequestParam(required = false) String conf,
                                 @RequestParam(required = false) String basis, @RequestParam(required = false) String completion, @RequestParam(required = false) String cohort,
                                 @RequestParam(required = false) String entry, @RequestParam(required = false) Integer matricYear, @RequestParam(required = false) Integer level,
                                 @RequestParam(required = false) String status, @RequestParam(required = false) String batch,
                                 @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                 @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        int sz = Math.max(1, Math.min(size, 2000));
        int pg = Math.max(1, page);
        Filter in = filterOf(rec, state, conf, basis, completion, cohort, entry, matricYear, level, status, batch, fac, dept, prog, q);
        List<Map<String, Object>> rows = filtered(ROW.replace("SELECT s.id,", "SELECT count(*) OVER () AS total_rows, s.id,") + FROM
                + " ORDER BY lower(s.surname), lower(s.other_names), s.id LIMIT :n OFFSET :o", in).param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    /** one student's recommendation, how it was reached, and every reconciliation of theirs */
    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable UUID id) {
        Filter in = filterOf(null, null, null, null, null, null, null, null, null, null, null, null, null, null, null);
        Map<String, Object> out = new LinkedHashMap<>(filtered(ROW + FROM, in).param("one", id.toString(), Types.VARCHAR).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("student", id)));
        List<Map<String, Object>> mine = reconciliations(" AND x.student_id = :id", in, Map.of("id", id), 100, 0);
        mine.forEach(r -> r.remove("total_rows"));
        out.put("reconciliations", mine);
        return out;
    }

    /* ── completion checked, a page at a time ── */

    public record Refresh(UUID after, String fac, String dept, String prog) {
    }

    /** the next page of students at or beyond their programme's length whose completion is checked now; the screen calls until done */
    @PostMapping("/refresh")
    @PreAuthorize(ACTORS)
    @Transactional
    Map<String, Object> refresh(@RequestBody(required = false) Refresh body) {
        Refresh in = body == null ? new Refresh(null, null, null, null) : body;
        OfficeScope.Bound b = scope.bound(in.fac(), in.dept(), in.prog());
        String[] ids = jdbc.sql("SELECT x::text FROM unnest(people.lifecycle_pool(CAST(:after AS uuid), :n, :fac, :dept, :prog)) x")
                .param("after", in.after() == null ? null : in.after().toString(), Types.VARCHAR).param("n", PAGE_CHECKED)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query(String.class).list().toArray(String[]::new);
        int checked = ids.length == 0 ? 0 : jdbc.sql("SELECT people.refresh_lifecycle_completion(CAST(:ids AS uuid[]))").param("ids", ids, Types.ARRAY).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("checked", checked);
        out.put("next", ids.length < PAGE_CHECKED ? null : ids[ids.length - 1]);
        out.put("done", ids.length < PAGE_CHECKED);
        if (in.after() == null) {
            out.put("pool", jdbc.sql("""
                    SELECT count(*) FROM people.academic_position ap JOIN people.student s ON s.id = ap.student_id JOIN ref.programme p ON p.code = s.programme_code
                     WHERE ap.existing_status IN ('ACTIVE','PROBATION') AND ap.rule IN ('R3','R3L','R4','R4L')
                       AND (ap.spillover_years > 0 OR ap.expected_completion = ap.current_session)
                       AND (:fac::text IS NULL OR p.faculty_code = :fac) AND (:dept::text IS NULL OR p.dept_code = :dept) AND (:prog::text IS NULL OR p.code = :prog)
                    """).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR).query(Long.class).single());
        }
        return out;
    }

    /* ── review: the chosen students, or every student a filter names ── */

    public record Mark(List<UUID> studentIds, Filter filter, @NotBlank @Size(max = 30) String state, @Size(max = 2000) String note, Boolean single) {
    }

    /** the students a request names: its own list, or every student its filter names (at most 5,000) — always within the scope */
    private String[] chosen(List<UUID> ids, Filter filter) {
        if (ids != null && !ids.isEmpty()) {
            if (ids.size() > 5000) throw tooMany();
            return ids.stream().map(UUID::toString).distinct().toArray(String[]::new);
        }
        if (filter == null) {
            throw new DomainRuleViolation("LIFECYCLE_CHOOSE", "Choose the students, or a figure to act on.", new DomainRuleViolation.Remedy("Tick the students, or open a figure first.", "You"));
        }
        List<String> all = filtered("SELECT s.id::text" + FROM + " ORDER BY s.id LIMIT 5001", filter).query(String.class).list();
        if (all.size() > 5000) throw tooMany();
        return all.toArray(String[]::new);
    }

    private static DomainRuleViolation tooMany() {
        return new DomainRuleViolation("LIFECYCLE_SIZE", "Act on at most 5,000 students at a time.",
                new DomainRuleViolation.Remedy("Narrow the figure by faculty, department, programme or cohort.", "You"));
    }

    @PostMapping("/mark")
    @PreAuthorize(ACTORS)
    @Transactional
    Map<String, Object> mark(@Valid @RequestBody Mark body) {
        OfficeScope.Bound b = scope.bound(null, null, null);
        String[] ids = chosen(body.studentIds(), body.filter());
        boolean single = Boolean.TRUE.equals(body.single()) && ids.length == 1;
        Map<String, Object> r = jdbc.sql("SELECT * FROM people.lifecycle_mark(CAST(:ids AS uuid[]), :state, :note, :single, :fac, :dept, :prog)")
                .param("ids", ids, Types.ARRAY).param("state", body.state().trim().toUpperCase()).param("note", blank(body.note()), Types.VARCHAR).param("single", single)
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("chosen", ids.length);
        out.put("state", body.state().trim().toUpperCase());
        return out;
    }

    /* ── a batch: previewed, opened, reconciled a step at a time, closed ── */

    public record Preview(List<UUID> studentIds, Filter filter, @Size(max = 40) String limitOutcome, @Size(max = 40) String limitStatus) {
    }

    /** what a batch would do, written nowhere: who is reconciled and how, who is left out and why — with the students to send */
    @PostMapping("/preview")
    @PreAuthorize(ACTORS)
    @Transactional(readOnly = true)
    Map<String, Object> preview(@RequestBody Preview body) {
        OfficeScope.Bound b = scope.bound(null, null, null);
        String[] ids = chosen(body.studentIds(), body.filter());
        String limit = limitOutcome(body.limitOutcome(), body.limitStatus());
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT lr.student_id::text AS id, lr.recommendation, lr.confidence, lr.review_state, lr.actionable, lr.existing_status, lr.current_level, lr.final_level,
                       EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = lr.student_id AND g.session = lr.current_session) AS on_list
                  FROM people.lifecycle_recommendation lr
                  JOIN people.student s ON s.id = lr.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE lr.student_id = ANY (CAST(:ids AS uuid[]))
                   AND (:fac::text IS NULL OR p.faculty_code = :fac) AND (:dept::text IS NULL OR p.dept_code = :dept) AND (:prog::text IS NULL OR p.code = :prog)
                 ORDER BY lr.student_id
                """).param("ids", ids, Types.ARRAY).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query().listOfRows();
        List<String> eligible = new ArrayList<>();
        Map<String, Integer> byRec = new LinkedHashMap<>();
        Map<String, Integer> byConf = new LinkedHashMap<>();
        Map<String, Integer> excluded = new LinkedHashMap<>();
        Map<String, Integer> statusMoves = new LinkedHashMap<>();
        int levelsRaised = 0;
        int toList = 0;
        int alreadyOnList = 0;
        for (Map<String, Object> r : rows) {
            String rec = (String) r.get("recommendation");
            String state = (String) r.get("review_state");
            String why = null;
            if ("RECONCILED".equals(state)) why = "ALREADY_RECONCILED";
            else if (!Boolean.TRUE.equals(r.get("actionable"))) why = "NOT_RECONCILABLE";
            else if (!"VERIFIED".equals(state)) why = "NOT_VERIFIED";
            else if ("MAXIMUM_SPILLOVER_REACHED".equals(rec) && limit == null) why = "LIMIT_OUTCOME_NOT_CHOSEN";
            if (why != null) {
                excluded.merge(why, 1, Integer::sum);
                continue;
            }
            eligible.add((String) r.get("id"));
            byRec.merge(rec, 1, Integer::sum);
            byConf.merge((String) r.get("confidence"), 1, Integer::sum);
            String from = (String) r.get("existing_status");
            boolean statusChange = "MAXIMUM_SPILLOVER_REACHED".equals(rec) && limit != null && limit.startsWith("STATUS_");
            String to = statusChange ? limit.substring("STATUS_".length()) : from;
            statusMoves.merge(from + "→" + to, 1, Integer::sum);
            Number cur = (Number) r.get("current_level");
            Number fin = (Number) r.get("final_level");
            if (!statusChange && cur != null && fin != null && cur.intValue() < fin.intValue()) levelsRaised++;
            if ("GRADUATION_CANDIDATE".equals(rec)) {
                if (Boolean.TRUE.equals(r.get("on_list"))) alreadyOnList++;
                else toList++;
            }
        }
        excluded.merge("NOT_IN_SCOPE_OR_NOT_ACTIVE", ids.length - rows.size(), Integer::sum);
        excluded.values().removeIf(v -> v == 0);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("chosen", ids.length);
        out.put("eligible", eligible.size());
        out.put("studentIds", eligible);
        out.put("byRecommendation", byRec);
        out.put("byConfidence", byConf);
        out.put("statusMoves", statusMoves);
        out.put("levelsRaised", levelsRaised);
        out.put("toGraduationList", toList);
        out.put("alreadyOnGraduationList", alreadyOnList);
        out.put("excluded", excluded);
        out.put("limitOutcome", limit);
        out.put("currentSession", jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1").query(String.class).optional().orElse(null));
        return out;
    }

    /** the officer's choice at the maximum spillover: kept active and flagged, or dormant or withdrawn — nothing else, never by default */
    private static String limitOutcome(String outcome, String status) {
        String o = upper(outcome);
        if (o == null) return null;
        if ("KEPT_ACTIVE_LIMIT_REACHED".equals(o)) return o;
        if ("STATUS_CHANGED".equals(o)) {
            String st = upper(status);
            if ("DORMANT".equals(st) || "WITHDRAWN".equals(st)) return "STATUS_" + st;
        }
        throw new DomainRuleViolation("LIFECYCLE_LIMIT_OUTCOME", "At the maximum spillover choose: keep active and flagged, or dormant, or withdrawn.",
                new DomainRuleViolation.Remedy("Choose what the batch does for students at the maximum.", "Registry"));
    }

    public record Open(@NotBlank @Size(max = 300) String description) {
    }

    @PostMapping("/batches")
    @PreAuthorize(ACTORS)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody Open body) {
        OfficeScope.Bound b = scope.bound(null, null, null);
        String words = b.prog() != null ? "Programme " + b.prog() : b.dept() != null ? "Department " + b.dept() : b.fac() != null ? "Faculty " + b.fac() : "The University";
        String ref = jdbc.sql("SELECT people.lifecycle_open_batch(:d, :s)").param("d", body.description().trim()).param("s", words).query(String.class).single();
        return batchRow(ref);
    }

    public record Step(@jakarta.validation.constraints.NotNull List<UUID> studentIds, @Size(max = 40) String limitOutcome, @Size(max = 40) String limitStatus,
                       @NotBlank @Size(max = 2000) String reason) {
    }

    /**
     * One step of a batch: up to 200 students, each reconciled all or nothing in its own savepoint — revalidated against the record at
     * that moment and refused, with the reason, when anything changed — a graduation candidate put on the list by the graduation audit;
     * the positions brought up to date together at the end of the step.
     */
    @PostMapping("/batches/{year}/{seq}/reconcile")
    @PreAuthorize(ACTORS)
    Map<String, Object> reconcile(@PathVariable String year, @PathVariable String seq, @Valid @RequestBody Step body) {
        String ref = "RECON/" + year + "/" + seq;
        if (body.studentIds().size() > STEP) {
            throw new DomainRuleViolation("LIFECYCLE_SIZE", "Reconcile at most " + STEP + " students in one step.", new DomainRuleViolation.Remedy("Send the batch in steps.", "You"));
        }
        String limit = limitOutcome(body.limitOutcome(), body.limitStatus());
        OfficeScope.Bound b = scope.bound(null, null, null);
        String[] ids = body.studentIds().stream().map(UUID::toString).distinct().toArray(String[]::new);
        return tx.execute(st -> {
            jdbc.sql("SELECT people.lifecycle_prepare(CAST(:ids AS uuid[]))").param("ids", ids, Types.ARRAY).query(Integer.class).single();
            Boolean deferred = jdbc.sql("SELECT people.defer_positions()").query(Boolean.class).single();
            List<Map<String, Object>> done = new ArrayList<>();
            List<Map<String, Object>> skipped = new ArrayList<>();
            for (String id : ids) {
                UUID student = UUID.fromString(id);
                Object sp = st.createSavepoint();
                try {
                    String expect = jdbc.sql("SELECT recommendation FROM people.lifecycle_review WHERE student_id = :s").param("s", student).query(String.class).optional().orElse(null);
                    boolean atLimit = "MAXIMUM_SPILLOVER_REACHED".equals(expect);
                    String outcome = atLimit && limit != null ? (limit.startsWith("STATUS_") ? "STATUS_CHANGED" : limit) : null;
                    String status = atLimit && limit != null && limit.startsWith("STATUS_") ? limit.substring("STATUS_".length()) : null;
                    UUID rec = jdbc.sql("SELECT people.lifecycle_reconcile(:b, :s, :expect, :outcome, :status, :reason, :fac, :dept, :prog)")
                            .param("b", ref).param("s", student).param("expect", expect, Types.VARCHAR).param("outcome", outcome, Types.VARCHAR)
                            .param("status", status, Types.VARCHAR).param("reason", body.reason().trim())
                            .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                            .query(UUID.class).single();
                    Map<String, Object> row = jdbc.sql("SELECT student_id, outcome, previous_status, new_status, previous_level, new_level, effective_session FROM people.lifecycle_reconciliation WHERE id = :id")
                            .param("id", rec).query().singleRow();
                    if ("GRADUATION_LIST".equals(row.get("outcome"))) {
                        GraduationService.Placed placed = graduation.placeOnList(student, (String) row.get("effective_session"));
                        jdbc.sql("SELECT people.lifecycle_graduand_placed(:r, :g, :a, :u)").param("r", rec).param("g", placed.graduandId()).param("a", placed.added())
                                .param("u", placed.unmet(), Types.VARCHAR).query().singleRow();
                        row.put("graduandAdded", placed.added());
                        row.put("unmet", placed.unmet());
                    }
                    st.releaseSavepoint(sp);
                    row.put("id", rec);
                    done.add(row);
                } catch (DataAccessException | DomainRuleViolation e) {
                    st.rollbackToSavepoint(sp);
                    skipped.add(skip(student, e));
                }
            }
            if (Boolean.TRUE.equals(deferred)) {
                jdbc.sql("SELECT people.refresh_deferred_positions()").query(Integer.class).single();
            }
            if (!skipped.isEmpty()) {
                jdbc.sql("SELECT people.lifecycle_batch_skipped(:b, :n)").param("b", ref).param("n", skipped.size()).query().singleRow();
            }
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("batchRef", ref);
            out.put("reconciled", done.size());
            out.put("skipped", skipped);
            out.put("results", done);
            return out;
        });
    }

    /** why a student was left out of a step, in the database's words, with the student named */
    private Map<String, Object> skip(UUID student, RuntimeException e) {
        String code = "LIFECYCLE_REFUSED";
        String message = e.getMessage();
        if (e instanceof DomainRuleViolation d) {
            code = d.code();
        } else {
            Throwable t = e;
            while (t != null && !(t instanceof PSQLException)) t = t.getCause();
            if (t instanceof PSQLException pg && pg.getServerErrorMessage() != null) {
                String m = pg.getServerErrorMessage().getMessage();
                java.util.regex.Matcher coded = java.util.regex.Pattern.compile("^([A-Z][A-Z0-9_]{3,60}): (.+)$", java.util.regex.Pattern.DOTALL).matcher(m == null ? "" : m);
                if (coded.matches()) {
                    code = coded.group(1);
                    message = coded.group(2);
                } else {
                    message = m;
                }
            }
        }
        Map<String, Object> who = jdbc.sql("SELECT s.id, s.surname, s.other_names, s.matric_no FROM people.student s WHERE s.id = :s").param("s", student).query().listOfRows()
                .stream().findFirst().orElseGet(() -> new LinkedHashMap<>(Map.of("id", student)));
        Map<String, Object> out = new LinkedHashMap<>(who);
        out.put("code", code);
        out.put("message", message);
        return out;
    }

    @PostMapping("/batches/{year}/{seq}/close")
    @PreAuthorize(ACTORS)
    @Transactional
    Map<String, Object> close(@PathVariable String year, @PathVariable String seq) {
        String ref = "RECON/" + year + "/" + seq;
        jdbc.sql("SELECT batch_ref FROM people.lifecycle_close_batch(:b, 0)").param("b", ref).query(String.class).single();
        return batchRow(ref);
    }

    private Map<String, Object> batchRow(String ref) {
        return jdbc.sql("""
                SELECT b.batch_ref, b.description, b.effective_session, b.scope, b.reconciled, b.skipped, b.corrected, helpdesk.person_name(b.created_by) AS created_by,
                       b.actor_office, b.created_at, b.closed_at
                  FROM people.lifecycle_batch b WHERE b.batch_ref = :b
                """).param("b", ref).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("reconciliation batch", ref));
    }

    /** every batch, newest first, with what each did — counted within the reader's scope */
    @GetMapping("/batches")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> batches() {
        OfficeScope.Bound b = scope.bound(null, null, null);
        return jdbc.sql("""
                SELECT b.batch_ref, b.description, b.effective_session, b.scope, b.reconciled, b.skipped, b.corrected, helpdesk.person_name(b.created_by) AS created_by,
                       b.actor_office, b.created_at, b.closed_at,
                       count(x.id) AS in_scope,
                       count(x.id) FILTER (WHERE x.outcome = 'SPILLOVER_CONFIRMED') AS spillover_confirmed,
                       count(x.id) FILTER (WHERE x.outcome = 'KEPT_ACTIVE_LIMIT_REACHED') AS kept_at_limit,
                       count(x.id) FILTER (WHERE x.outcome = 'STATUS_CHANGED') AS status_changed,
                       count(x.id) FILTER (WHERE x.outcome = 'GRADUATION_LIST') AS graduation_list,
                       count(x.id) FILTER (WHERE x.corrected_at IS NOT NULL) AS corrected_in_scope
                  FROM people.lifecycle_batch b
                  LEFT JOIN (people.lifecycle_reconciliation x JOIN people.student s ON s.id = x.student_id JOIN ref.programme p ON p.code = s.programme_code)
                         ON x.batch_ref = b.batch_ref
                        AND (:fac::text IS NULL OR p.faculty_code = :fac) AND (:dept::text IS NULL OR p.dept_code = :dept) AND (:prog::text IS NULL OR p.code = :prog)
                 GROUP BY b.batch_ref
                 ORDER BY b.created_at DESC
                 LIMIT 500
                """).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR).query().listOfRows();
    }

    /** the reconciliations (history), paged, names A–Z — of a batch, an outcome, corrected or not — within the reader's scope */
    @GetMapping("/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> history(@RequestParam(required = false) String batch, @RequestParam(required = false) String outcome, @RequestParam(required = false) Boolean corrected,
                                @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        int sz = Math.max(1, Math.min(size, 2000));
        int pg = Math.max(1, page);
        Filter in = filterOf(null, null, null, null, null, null, null, null, null, null, null, fac, dept, prog, q);
        String where = " AND (:hb::text IS NULL OR x.batch_ref = :hb) AND (:ho::text IS NULL OR x.outcome = :ho)"
                + " AND (CAST(:hc AS boolean) IS NULL OR (x.corrected_at IS NOT NULL) = CAST(:hc AS boolean))";
        Map<String, Object> extra = new LinkedHashMap<>();
        extra.put("hb", blank(batch));
        extra.put("ho", upper(outcome));
        extra.put("hc", corrected);
        List<Map<String, Object>> rows = reconciliations(where, in, extra, sz, (pg - 1) * sz);
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    private List<Map<String, Object>> reconciliations(String where, Filter in, Map<String, Object> extra, int limit, int offset) {
        OfficeScope.Bound b = scope.bound(in.fac(), in.dept(), in.prog());
        JdbcClient.StatementSpec spec = jdbc.sql("""
                SELECT count(*) OVER () AS total_rows, x.id, x.batch_ref, x.student_id, s.surname, s.other_names, s.matric_no, p.name AS programme, d.name AS department,
                       f.name AS faculty, x.effective_session, x.recommendation, x.confidence, x.outcome, x.previous_status, x.new_status, x.previous_level, x.new_level,
                       x.effective_cohort, x.expected_completion, x.spillover_years, x.completion, x.explanation, x.reason, x.graduand_added, x.graduand_unmet,
                       helpdesk.person_name(x.reconciled_by) AS reconciled_by, x.actor_office, x.reconciled_at,
                       x.corrected_at, helpdesk.person_name(x.corrected_by) AS corrected_by, x.correction_reason, x.level_restored
                  FROM people.lifecycle_reconciliation x
                  JOIN people.student s ON s.id = x.student_id
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.department d ON d.code = p.dept_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE (:fac::text IS NULL OR f.code = :fac) AND (:dept::text IS NULL OR d.code = :dept) AND (:prog::text IS NULL OR p.code = :prog)
                   AND (:like::text IS NULL OR s.matric_no ILIKE :like OR s.surname ILIKE :like OR s.other_names ILIKE :like OR (s.surname || ' ' || s.other_names) ILIKE :like)
                """ + where + """
                 ORDER BY lower(s.surname), lower(s.other_names), x.reconciled_at DESC
                 LIMIT :n OFFSET :o
                """).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .param("like", blank(in.q()) == null ? null : "%" + in.q().trim() + "%", Types.VARCHAR).param("n", limit).param("o", offset);
        for (Map.Entry<String, Object> e : extra.entrySet()) {
            Object v = e.getValue();
            spec = v instanceof Boolean ? spec.param(e.getKey(), v, Types.BOOLEAN) : v instanceof UUID ? spec.param(e.getKey(), v) : spec.param(e.getKey(), v, Types.VARCHAR);
        }
        return spec.query().listOfRows();
    }

    /* ── corrections: a reconciliation reversed on a reason ── */

    public record Correct(@NotBlank @Size(max = 2000) String reason) {
    }

    @PostMapping("/reconciliations/{id}/correct")
    @PreAuthorize(ACTORS)
    @Transactional
    Map<String, Object> correct(@PathVariable UUID id, @Valid @RequestBody Correct body) {
        OfficeScope.Bound b = scope.bound(null, null, null);
        UUID d = jdbc.sql("SELECT people.lifecycle_correct(:id, :r, :fac, :dept, :prog)").param("id", id).param("r", body.reason().trim())
                .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR).query(UUID.class).single();
        return Map.of("id", id, "decisionId", d);
    }

    /** a whole batch corrected, a step at a time: the next 200 of its reconciliations not yet corrected, each all or nothing */
    @PostMapping("/batches/{year}/{seq}/correct")
    @PreAuthorize(ACTORS)
    Map<String, Object> correctBatch(@PathVariable String year, @PathVariable String seq, @Valid @RequestBody Correct body) {
        String ref = "RECON/" + year + "/" + seq;
        OfficeScope.Bound b = scope.bound(null, null, null);
        return tx.execute(st -> {
            List<UUID> next = jdbc.sql("""
                    SELECT x.id FROM people.lifecycle_reconciliation x WHERE x.batch_ref = :b AND x.corrected_at IS NULL
                       AND people.lifecycle_in_scope(x.student_id, :fac, :dept, :prog)
                     ORDER BY x.id LIMIT :n
                    """).param("b", ref).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                    .param("n", STEP).query(UUID.class).list();
            Boolean deferred = jdbc.sql("SELECT people.defer_positions()").query(Boolean.class).single();
            int n = 0;
            List<Map<String, Object>> refused = new ArrayList<>();
            for (UUID id : next) {
                Object sp = st.createSavepoint();
                try {
                    jdbc.sql("SELECT people.lifecycle_correct(:id, :r, :fac, :dept, :prog)").param("id", id).param("r", body.reason().trim())
                            .param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR).query(UUID.class).single();
                    st.releaseSavepoint(sp);
                    n++;
                } catch (DataAccessException | DomainRuleViolation e) {
                    st.rollbackToSavepoint(sp);
                    UUID student = jdbc.sql("SELECT student_id FROM people.lifecycle_reconciliation WHERE id = :id").param("id", id).query(UUID.class).single();
                    Map<String, Object> r = skip(student, e);
                    r.put("reconciliationId", id);
                    refused.add(r);
                }
            }
            if (Boolean.TRUE.equals(deferred)) {
                jdbc.sql("SELECT people.refresh_deferred_positions()").query(Integer.class).single();
            }
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("batchRef", ref);
            out.put("corrected", n);
            out.put("refused", refused);
            // a refused one stays uncorrected; the screen stops when a step corrects nothing
            out.put("done", next.size() < STEP || n == 0);
            return out;
        });
    }
}
