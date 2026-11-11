package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.sql.Types;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
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
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
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
 * V654: historical school fees and the graduate's financial clearance. The historical account of a student — every session and
 * semester from the assessment start (or admission) to the graduation session, assessed as the student was then (an approved
 * assessment, else the session's fee lines at the session's level, else nothing: for review), the verified payments allocated
 * first semester first, the outstanding — is read in the database (finance.historical_rows), never in the browser. The Students
 * Account Officer makes and submits assessments where a structure is missing or a student's fee was different (one at a time, or a
 * cohort from a preview); the Bursar — never the officer who made it — approves, returns or rejects; an approved assessment is kept,
 * a correction supersedes it. The lists, dashboards and reports read each graduate's summary (finance.historical_summary), worked
 * out again when a payment is confirmed or an assessment decided. The FINAL clearance's Bursary stage reads the same account (the
 * clearance desk signs it); this desk shows where each graduate stands. Every permission is checked here and again in the functions
 * (finance.historical_grant). V665: approved waivers and adjustments (proposed by one officer, decided by another of the Bursar's office)
 * lower what a period owes; reconciliation runs (CLEARANCE-RECON/YYYY/NNNNNN) keep a population's financial clearance as it was found.
 */
@RestController
@RequestMapping("/api/v1/finance/historical")
class HistoricalFeesController {

    static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super','OFFICE_registrar',"
            + "'OFFICE_dregistrar','OFFICE_academic','OFFICE_records','OFFICE_vc','OFFICE_dvc','OFFICE_ict','OFFICE_admin',"
            + "'OFFICE_pgschool','OFFICE_pgsecretary')";   // V720: the School of Postgraduate Studies, its postgraduate students only
    /** V720: the School of Postgraduate Studies reads postgraduate students alone, whatever the screen asks */
    private static String typeFor(String type) {
        String office = ng.edu.moaum.portal.shared.AuditContextHolder.current().map(ng.edu.moaum.portal.shared.AuditContext::actorOffice).orElse("");
        if ("pgschool".equals(office) || "pgsecretary".equals(office)) return "PG";
        return type == null ? null : "PG".equalsIgnoreCase(type.trim()) ? "PG" : "UG".equalsIgnoreCase(type.trim()) ? "UG" : null;
    }
    /** V720: GRADUATES (graduated, or an approved graduand), ACTIVE (studying: ACTIVE, PROBATION) or ALL */
    private static String scopeOf(String scope) {
        return scope == null ? "GRADUATES" : "ALL".equalsIgnoreCase(scope.trim()) ? "ALL" : "ACTIVE".equalsIgnoreCase(scope.trim()) ? "ACTIVE" : "GRADUATES";
    }
    /** V723: the School of Postgraduate Studies reads postgraduate students alone — on every list and every record read by id */
    private static boolean pgOnly() {
        return "PG".equals(typeFor(null));
    }
    static final String PG_ONLY_WHERE = "\n                  AND (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))\n";
    /** V723: a cohort batch is the School's when it assesses a postgraduate student */
    static final String PG_BATCH = "(NOT CAST(:pgonly AS boolean) OR EXISTS (SELECT 1 FROM finance.historical_assessment a JOIN people.student s ON s.id = a.student_id"
            + " JOIN ref.programme p ON p.code = s.programme_code WHERE a.batch_id = b.id AND people.is_postgraduate(s.entry_mode, p.category)))";
    /** V723: a reconciliation run's counts over its postgraduate rows alone — what the School reads of a run */
    static final String PG_RUN_COUNTS = """
            SELECT count(*) AS students, count(*) FILTER (WHERE y.status = 'CLEARED') AS cleared, count(*) FILTER (WHERE y.status = 'OWING') AS owing,
                   count(*) FILTER (WHERE y.status = 'REQUIRES_REVIEW') AS review, count(*) FILTER (WHERE y.status = 'PENDING_APPROVAL') AS pending,
                   count(*) FILTER (WHERE y.status = 'PAYMENT_REVIEW') AS payment_review, count(*) FILTER (WHERE y.status = 'NO_PERIOD') AS no_period,
                   coalesce(sum(y.assessed), 0) AS assessed, coalesce(sum(y.paid), 0) AS paid, coalesce(sum(y.waived), 0) AS waived,
                   coalesce(sum(y.outstanding), 0) AS outstanding
              FROM finance.clearance_recon_row y JOIN people.student s ON s.id = y.student_id JOIN ref.programme p ON p.code = s.programme_code
             WHERE y.run_id = r.id AND people.is_postgraduate(s.entry_mode, p.category)
            """;
    /** V723: a record outside the office's bound is not found for it, whatever the screen asks */
    private void inScope(UUID student) {
        if (student == null) throw new NotFound("student", "none");
        if (pgOnly() && !Boolean.TRUE.equals(jdbc.sql("SELECT people.is_postgraduate(s.entry_mode, p.category) FROM people.student s JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = :id")
                .param("id", student).query(Boolean.class).optional().orElse(false))) {
            throw new NotFound("student", student);
        }
    }
    private UUID studentOf(String table, UUID id) {
        return jdbc.sql("SELECT student_id FROM " + table + " WHERE id = :id").param("id", id).query(UUID.class).optional().orElse(null);
    }
    static final String SCOPE_WHERE = """
                  AND (CAST(:scope AS text) = 'ALL'
                       OR (:scope = 'ACTIVE' AND s.status IN ('ACTIVE', 'PROBATION'))
                       OR (:scope = 'GRADUATES' AND (s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'))))
                  AND (CAST(:type AS text) IS NULL OR (:type = 'PG') = people.is_postgraduate(s.entry_mode, p.category))
            """;
    static final Set<String> EVIDENCE_TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    static final Set<String> FINANCIAL = Set.of("FINANCIALLY_CLEARED", "FINANCIAL_OBLIGATION", "FINANCIAL_CLEARANCE_PENDING", "HISTORICAL_FEE_REVIEW_REQUIRED",
            "NO_HISTORICAL_PERIOD");
    static final Set<String> STATES = Set.of("DRAFT", "PENDING_BURSAR_APPROVAL", "RETURNED_FOR_CORRECTION", "APPROVED", "REJECTED", "CANCELLED", "SUPERSEDED");
    static final String SESSION = "^[0-9]{4}/[0-9]{4}$";
    static final int PAGE = 50;

    public record Component(@NotBlank @Size(max = 120) String item, @NotNull @DecimalMin("0.01") BigDecimal amount) {
    }

    public record AssessmentIn(UUID studentId, @Pattern(regexp = SESSION) String session, @Min(1) @Max(3) Integer semester,
                               @NotNull @DecimalMin("0.01") BigDecimal amount, @Size(max = 30) List<@Valid Component> components,
                               @NotBlank @Size(max = 40) String source, @Size(max = 300) String sourceReference, @NotBlank @Size(max = 2000) String reason,
                               @Size(max = 2000) String remarks, UUID corrects, Boolean submit) {
    }

    public record DecideIn(@NotBlank @Pattern(regexp = "APPROVE|RETURN|REJECT") String decision, @Size(max = 2000) String note) {
    }

    public record NoteIn(@Size(max = 2000) String note) {
    }

    public record EvidenceIn(@NotBlank @Size(max = 200) String filename, @NotBlank String dataUrl) {
    }

    public record PreviewIn(@NotBlank @Pattern(regexp = SESSION) String session, @NotNull @Min(1) @Max(3) Integer semester, @Size(max = 12) String faculty,
                            @Size(max = 12) String dept, @Size(max = 12) String programme, @Min(100) @Max(900) Integer level, Boolean graduatedOnly) {
    }

    public record BulkIn(@NotEmpty @Size(max = 3000) List<UUID> studentIds, @NotBlank @Pattern(regexp = SESSION) String session,
                         @NotNull @Min(1) @Max(3) Integer semester, @NotNull @DecimalMin("0.01") BigDecimal amount, @Size(max = 30) List<@Valid Component> components,
                         @NotBlank @Size(max = 40) String source, @Size(max = 300) String sourceReference, @NotBlank @Size(max = 2000) String reason,
                         Map<String, Object> scope) {
    }

    public record StartIn(@Pattern(regexp = SESSION) String session, @NotBlank @Size(max = 400) String reason) {
    }

    /** V665: a waiver or adjustment of a past period, with the authority it rests on and (optionally) its evidence file */
    public record WaiverIn(@NotNull UUID studentId, @NotBlank @Pattern(regexp = SESSION) String session, @NotNull @Min(1) @Max(3) Integer semester,
                           @NotBlank @Pattern(regexp = "WAIVER|ADJUSTMENT") String kind, @NotNull @DecimalMin("0.01") BigDecimal amount,
                           @NotBlank @Size(max = 2000) String reason, @NotBlank @Size(max = 300) String authority, @Valid EvidenceIn evidence) {
    }

    /** V683: a graduate's payment evidence decided — verified against the payment on record it shows, sent back for more, or rejected */
    public record EvidenceDecideIn(@NotBlank @Pattern(regexp = "VERIFY|MORE_INFORMATION|REJECT") String decision, @Size(max = 2000) String note, UUID payment) {
    }

    public record WaiverDecideIn(@NotBlank @Pattern(regexp = "APPROVE|REJECT") String decision, @Size(max = 2000) String note) {
    }

    public record ReasonIn(@NotBlank @Size(max = 2000) String reason) {
    }

    /** V665: a reconciliation run's population and filters */
    public record ReconIn(@Pattern(regexp = "AWAITING_GRADUATION|UNDER_CLEARANCE|GRADUATES|ALL") String population, @Size(max = 12) String faculty,
                          @Size(max = 12) String dept, @Size(max = 12) String programme, @Pattern(regexp = SESSION) String admission,
                          @Pattern(regexp = SESSION) String graduation) {
    }

    static final Set<String> WAIVER_STATES = Set.of("PENDING_BURSAR_APPROVAL", "APPROVED", "REJECTED", "WITHDRAWN", "REVOKED");
    static final Set<String> RECON_STATUSES = Set.of("CLEARED", "OWING", "REQUIRES_REVIEW", "PENDING_APPROVAL", "PAYMENT_REVIEW", "NO_PERIOD");

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final FileObjects files;

    HistoricalFeesController(JdbcClient jdbc, FileObjects files) {
        this.jdbc = jdbc;
        this.files = files;
    }

    private static String office() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    private List<String> permissions() {
        return jdbc.sql("SELECT unnest(finance.historical_permissions(:o))").param("o", office()).query(String.class).list();
    }

    private void need(String permission) {
        if (!permissions().contains(permission)) {
            throw new AccessDeniedException("Your office does not hold " + permission + " for historical school fees.");
        }
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private String components(List<Component> list) {
        List<Map<String, Object>> out = new ArrayList<>();
        if (list != null) list.forEach(c -> out.add(Map.of("item", c.item().trim(), "amount", c.amount())));
        return JSON.writeValueAsString(out);
    }

    /** the graduates and graduands whose summary is stale worked out again before a list is read (a few hundred at a time) */
    private void freshen() {
        jdbc.sql("SELECT finance.historical_refresh_stale(500)").query(Integer.class).single();
    }

    /* ── the desk ── */

    @GetMapping("/permissions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> permissionsAndSetting() {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", office());
        out.put("permissions", permissions());
        out.put("setting", jdbc.sql("""
                SELECT s.assess_from, finance.historical_start() AS start, s.online_payment, s.set_at, s.reason, s.refreshed_at,
                       helpdesk.person_name(s.set_by) AS set_by
                  FROM finance.historical_setting s WHERE s.id = 1
                """).query().singleRow());
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session WHERE state NOT IN ('CANCELLED', 'DRAFT') ORDER BY name DESC").query(String.class).list());
        out.put("sources", List.of("HISTORICAL_FEE_STRUCTURE", "HISTORICAL_FEE_VERSION", "COHORT_FEE_RECORD", "STUDENT_SPECIFIC_APPROVED_FEE", "OFFICIAL_FEE_DOCUMENT",
                "MANUAL_HISTORICAL_ASSESSMENT", "LEGACY_MIGRATION", "OTHER_APPROVED_SOURCE"));
        return out;
    }

    /** the Bursar moves the session historical fees are assessed from (none: the first session the fee setup holds a line for) */
    @PutMapping("/setting")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_super')")
    @Transactional
    Map<String, Object> setStart(@Valid @RequestBody StartIn body) {
        jdbc.sql("SELECT finance.historical_set_start(:s, :r)").param("s", blank(body.session()), Types.VARCHAR).param("r", body.reason()).query(Integer.class).single();
        return permissionsAndSetting();
    }

    /** every graduate's and graduand's summary worked out again in full */
    @PostMapping("/refresh")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> refresh() {
        need("REVIEW_HISTORICAL_FEE_ASSESSMENT");
        int n = jdbc.sql("SELECT finance.historical_refresh(NULL)").query(Integer.class).single();
        return Map.of("students", n);
    }

    /** the dashboard: graduates and graduands by financial status, the amounts, the assessments by state — each a filter of the list */
    @GetMapping("/figures")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> figures() {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        freshen();
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("""
                SELECT count(*) AS graduates,
                       count(*) FILTER (WHERE h.outstanding > 0) AS with_outstanding,
                       count(*) FILTER (WHERE h.financial_status = 'FINANCIALLY_CLEARED') AS cleared,
                       count(*) FILTER (WHERE h.financial_status = 'HISTORICAL_FEE_REVIEW_REQUIRED') AS requires_review,
                       count(*) FILTER (WHERE h.financial_status = 'FINANCIAL_CLEARANCE_PENDING') AS pending_approval,
                       count(*) FILTER (WHERE h.partial_periods > 0) AS partially_paid,
                       count(*) FILTER (WHERE h.outstanding = 0 AND h.financial_status <> 'NO_HISTORICAL_PERIOD') AS no_outstanding,
                       count(*) FILTER (WHERE h.credit >= 1) AS with_credit,
                       count(*) FILTER (WHERE h.financial_status = 'NO_HISTORICAL_PERIOD') AS no_period,
                       count(*) FILTER (WHERE h.review_periods = 0 AND h.periods > 0
                                          AND NOT EXISTS (SELECT 1 FROM finance.historical_assessment a WHERE a.student_id = h.student_id AND a.state = 'APPROVED')) AS auto_assessed,
                       count(*) FILTER (WHERE s.status = 'GRADUATED' AND h.outstanding > 0) AS graduated_with_obligation,
                       coalesce(sum(h.assessed), 0) AS assessed, coalesce(sum(h.paid), 0) AS paid, coalesce(sum(h.outstanding), 0) AS outstanding,
                       coalesce(sum(h.credit), 0) AS credit
                  FROM finance.historical_summary h JOIN people.student s ON s.id = h.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'))
                   AND (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))   -- V723
                """).param("pgonly", pgOnly()).query().singleRow());
        // V723 (the School of Postgraduate Studies): every aggregate below counts postgraduate students alone for the School
        out.put("assessments", jdbc.sql("""
                SELECT a.state, count(*) AS n, coalesce(sum(a.amount), 0) AS amount
                  FROM finance.historical_assessment a JOIN people.student s ON s.id = a.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))
                 GROUP BY a.state
                """).param("pgonly", pgOnly()).query().listOfRows());
        out.put("batchesPending", jdbc.sql("SELECT count(*) FROM finance.historical_batch b WHERE b.state = 'PENDING_BURSAR_APPROVAL' AND " + PG_BATCH)
                .param("pgonly", pgOnly()).query(Long.class).single());
        // V683: graduates' payment evidence by state, and graduates with a school-fee payment archived for review
        out.put("evidence", jdbc.sql("""
                SELECT count(*) FILTER (WHERE e.state = 'SUBMITTED') AS submitted, coalesce(sum(e.amount) FILTER (WHERE e.state = 'SUBMITTED'), 0) AS submitted_amount,
                       count(*) FILTER (WHERE e.state = 'MORE_INFORMATION_REQUIRED') AS more_information,
                       count(*) FILTER (WHERE e.state = 'VERIFIED') AS verified,
                       count(*) FILTER (WHERE e.state = 'VERIFIED' AND finance.historical_evidence_payment_state(e.payment_id, e.student_id, e.session) <> 'COUNTED') AS verified_to_put_right,
                       count(*) FILTER (WHERE e.state = 'REJECTED') AS rejected
                  FROM finance.historical_payment_evidence e JOIN people.student s ON s.id = e.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))   -- V723
                """).param("pgonly", pgOnly()).query().singleRow());
        out.put("archivedSchoolFees", jdbc.sql("""
                SELECT count(DISTINCT a.student_id) AS students, coalesce(sum(a.amount), 0) AS amount
                  FROM finance.payment_archive a JOIN people.student s ON s.id = a.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE a.settled_at IS NULL AND a.purpose LIKE 'School fees%'
                   AND (s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'))
                   AND (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))   -- V723
                """).param("pgonly", pgOnly()).query().singleRow());
        // V665: waivers awaiting the Bursar, the approved total, and the approved graduands whose final clearance is still to complete
        out.put("waivers", jdbc.sql("""
                SELECT count(*) FILTER (WHERE w.state = 'PENDING_BURSAR_APPROVAL') AS pending,
                       coalesce(sum(w.amount) FILTER (WHERE w.state = 'PENDING_BURSAR_APPROVAL'), 0) AS pending_amount,
                       count(*) FILTER (WHERE w.state = 'APPROVED') AS approved, coalesce(sum(w.amount) FILTER (WHERE w.state = 'APPROVED'), 0) AS approved_amount
                  FROM finance.historical_waiver w JOIN people.student s ON s.id = w.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))   -- V723
                """).param("pgonly", pgOnly()).query().singleRow());
        // V668: the final clearances waiting only on the Bursary, and how many are ready (nothing owed, for review or pending)
        out.put("readyToGraduate", jdbc.sql("""
                SELECT count(*) FILTER (WHERE r.ready) AS ready, count(*) AS waiting
                  FROM clearance.ready_to_graduate(NULL, NULL, NULL, NULL, 5000) r JOIN people.student s ON s.id = r.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))   -- V723
                """).param("pgonly", pgOnly()).query().singleRow());
        out.put("awaitingGraduation", jdbc.sql("""
                SELECT count(*) FROM people.student s JOIN ref.programme p ON p.code = s.programme_code WHERE s.status <> 'GRADUATED'
                   AND EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
                   AND (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))   -- V723
                """).param("pgonly", pgOnly()).query(Long.class).single());
        out.put("unsummarised", jdbc.sql("""
                SELECT count(*) FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'))
                   AND NOT EXISTS (SELECT 1 FROM finance.historical_summary h WHERE h.student_id = s.id)
                   AND (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))   -- V723
                """).param("pgonly", pgOnly()).query(Long.class).single());
        out.put("refreshedAt", jdbc.sql("SELECT refreshed_at FROM finance.historical_setting WHERE id = 1").query().singleRow().get("refreshed_at"));
        out.put("start", jdbc.sql("SELECT finance.historical_start()").query(String.class).optional().orElse(null));
        // V720: the whole population by standing and programme type — studying or graduated, undergraduate or postgraduate — each with
        // those owing, the sessions owed in whole and in part, and the amounts; the School of Postgraduate Studies sees its own
        String type = typeFor(null);
        out.put("population", jdbc.sql("""
                SELECT CASE WHEN s.status IN ('ACTIVE', 'PROBATION') THEN 'ACTIVE' ELSE 'GRADUATED' END AS standing,
                       CASE WHEN people.is_postgraduate(s.entry_mode, p.category) THEN 'PG' ELSE 'UG' END AS type,
                       count(*) AS students, count(*) FILTER (WHERE h.outstanding > 0) AS with_outstanding,
                       count(*) FILTER (WHERE h.whole_sessions > 0) AS whole_sessions, count(*) FILTER (WHERE h.part_sessions > 0) AS part_sessions,
                       count(*) FILTER (WHERE h.review_periods > 0) AS requires_review,
                       coalesce(sum(h.outstanding), 0) AS outstanding, coalesce(sum(h.paid), 0) AS paid
                  FROM finance.historical_summary h JOIN people.student s ON s.id = h.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE finance.historical_population(s.status, s.id, s.entry_session)
                   AND (CAST(:type AS text) IS NULL OR (:type = 'PG') = people.is_postgraduate(s.entry_mode, p.category))
                 GROUP BY 1, 2 ORDER BY 1, 2
                """).param("type", type, Types.VARCHAR).query().listOfRows());
        return out;
    }

    /** the graduates and graduands a search finds — by name, matriculation, admission, JAMB or application number or the record's id —
     *  narrowed by faculty, department, programme, admission and graduation session and financial status; the summary of each */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> students(@RequestParam(required = false) String q, @RequestParam(required = false) String faculty,
                                 @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                                 @RequestParam(required = false) String admission, @RequestParam(required = false) String graduation,
                                 @RequestParam(required = false) String financial, @RequestParam(required = false) String filter,
                                 @RequestParam(defaultValue = "GRADUATES") String scope, @RequestParam(defaultValue = "0") int page,
                                 @RequestParam(required = false) String type, @RequestParam(required = false) Integer level) {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        freshen();
        String typ = typeFor(type);   // V720
        String fin = blank(financial) != null && FINANCIAL.contains(financial.trim()) ? financial.trim() : null;
        String flt = blank(filter);
        String term = blank(q);
        if (term != null && term.length() > 80) term = term.substring(0, 80);
        int p = Math.max(0, Math.min(page, 2000));
        String where = """
                FROM people.student s
                JOIN ref.programme p ON p.code = s.programme_code
                LEFT JOIN ref.department d ON d.code = p.dept_code
                LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                LEFT JOIN finance.historical_summary h ON h.student_id = s.id
                WHERE true
                """ + SCOPE_WHERE + """
                  AND (CAST(:lvl AS integer) IS NULL OR s.current_level = :lvl)
                  AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac) AND (CAST(:dept AS text) IS NULL OR p.dept_code = :dept)
                  AND (CAST(:prog AS text) IS NULL OR p.code = :prog) AND (CAST(:adm AS text) IS NULL OR s.entry_session = :adm)
                  AND (CAST(:grad AS text) IS NULL OR h.last_session = :grad)
                  AND (CAST(:fin AS text) IS NULL OR h.financial_status = :fin)
                  AND (CAST(:flt AS text) IS NULL
                       OR (:flt = 'OUTSTANDING' AND h.outstanding > 0)
                       OR (:flt = 'GRADUATED_OWING' AND s.status = 'GRADUATED' AND h.outstanding > 0)
                       OR (:flt = 'ACTIVE_OWING' AND s.status IN ('ACTIVE', 'PROBATION') AND h.outstanding > 0)
                       OR (:flt = 'WHOLE_SESSION' AND h.whole_sessions > 0)
                       OR (:flt = 'PART_SESSION' AND h.part_sessions > 0)
                       OR (:flt = 'PARTIALLY_PAID' AND h.partial_periods > 0)
                       OR (:flt = 'NO_OUTSTANDING' AND h.outstanding = 0 AND h.financial_status <> 'NO_HISTORICAL_PERIOD')
                       OR (:flt = 'CREDIT' AND h.credit >= 1)
                       OR (:flt = 'AUTO_ASSESSED' AND h.review_periods = 0 AND h.periods > 0
                           AND NOT EXISTS (SELECT 1 FROM finance.historical_assessment a WHERE a.student_id = s.id AND a.state = 'APPROVED'))
                       OR (:flt = 'WITH_ASSESSMENT' AND EXISTS (SELECT 1 FROM finance.historical_assessment a WHERE a.student_id = s.id AND a.state = 'APPROVED')))
                  AND (CAST(:q AS text) IS NULL
                       OR s.id::text = :q OR upper(s.matric_no) = upper(:q) OR upper(s.admission_no) = upper(:q)
                       OR EXISTS (SELECT 1 FROM people.student_identifier i WHERE i.student_id = s.id AND upper(i.identifier_value) = upper(:q))
                       OR (s.surname || ' ' || s.other_names) ILIKE '%' || :q || '%' OR (s.other_names || ' ' || s.surname) ILIKE '%' || :q || '%')
                """;
        JdbcClient.StatementSpec count = bind(jdbc.sql("SELECT count(*) " + where), scope, faculty, dept, programme, admission, graduation, fin, flt, term)
                .param("type", typ, Types.VARCHAR).param("lvl", level, Types.INTEGER);
        long total = count.query(Long.class).single();
        List<Map<String, Object>> rows = bind(jdbc.sql("""
                SELECT s.id AS student_id, s.surname, s.other_names, s.matric_no, s.admission_no, s.jamb_reg_no, s.status, s.entry_session,
                       p.code AS programme_code, p.name AS programme, d.name AS department, f.name AS faculty,
                       people.is_postgraduate(s.entry_mode, p.category) AS postgraduate, s.current_level, h.whole_sessions, h.part_sessions,   -- V720
                       h.first_session, h.last_session AS graduation_session, h.periods, h.assessed, h.paid, h.outstanding, h.credit, h.owing_periods,
                       h.review_periods, h.pending_periods, h.partial_periods, h.owing, h.financial_status, h.last_payment_at, h.refreshed_at,
                       (SELECT i.state FROM clearance.process q
                          JOIN clearance.item i ON i.process_id = q.id AND i.unit = 'BURSARY' AND i.superseded_by IS NULL
                         WHERE q.student_id = s.id AND q.workflow = 'FINAL' AND q.cancelled_at IS NULL ORDER BY i.decided_at DESC LIMIT 1) AS bursary_clearance,
                       (SELECT q.reference FROM clearance.process q WHERE q.student_id = s.id AND q.workflow = 'FINAL' AND q.cancelled_at IS NULL LIMIT 1) AS clearance_ref
                """ + where + " ORDER BY h.outstanding DESC NULLS LAST, s.surname, s.other_names LIMIT :lim OFFSET :off"),
                scope, faculty, dept, programme, admission, graduation, fin, flt, term)
                .param("type", typ, Types.VARCHAR).param("lvl", level, Types.INTEGER)
                .param("lim", PAGE).param("off", p * PAGE).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", p);
        out.put("size", PAGE);
        out.put("rows", rows);
        return out;
    }

    private static JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, String scope, String faculty, String dept, String programme, String admission,
                                                 String graduation, String fin, String flt, String q) {
        return spec.param("scope", scopeOf(scope)).param("fac", blank(faculty), Types.VARCHAR)
                .param("dept", blank(dept), Types.VARCHAR).param("prog", blank(programme), Types.VARCHAR).param("adm", blank(admission), Types.VARCHAR)
                .param("grad", blank(graduation), Types.VARCHAR).param("fin", fin, Types.VARCHAR).param("flt", flt, Types.VARCHAR).param("q", q, Types.VARCHAR);
    }

    /** a student's historical account, live: the periods, the session totals, the assessments with their timeline, the payments, the
     *  corrections, the old-portal numbers, the final clearance */
    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> student(@PathVariable UUID id) {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        Map<String, Object> st = jdbc.sql("""
                SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.jamb_reg_no, s.status, s.entry_session, s.entry_level, s.current_level,
                       p.code AS programme_code, p.name AS programme, d.name AS department, f.name AS faculty, records.graduation_session(s.id) AS graduation_session
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE s.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", id));
        inScope(id);   // V723
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", st);
        out.put("start", jdbc.sql("SELECT finance.historical_start()").query(String.class).optional().orElse(null));
        // V683: each period with what is under review for it (the graduate's evidence, an archived school-fee payment, a payment under
        // another purpose) — never read as plainly unpaid while a payment is checked
        out.put("periods", jdbc.sql("""
                SELECT x.*, rv.review, rv.evidence_id, rv.evidence_ref, rv.evidence_state, rv.archived_count, rv.archived_amount, rv.other_count, rv.other_amount
                  FROM finance.historical_account(:id) x
                  LEFT JOIN finance.historical_review(ARRAY[CAST(:id AS uuid)]) rv ON rv.session = x.session AND rv.semester = x.semester
                """).param("id", id).query().listOfRows());
        out.put("evidence", jdbc.sql("""
                SELECT e.id, e.reference, e.session, e.semester, e.amount, e.paid_on::text AS paid_on, e.channel, e.payment_reference, e.state, e.submitted_at,
                       e.decided_at, e.decision_note, r.reference AS payment, finance.historical_evidence_payment_state(e.payment_id, e.student_id, e.session) AS payment_state
                  FROM finance.historical_payment_evidence e LEFT JOIN finance.payment_reference r ON r.id = e.payment_id
                 WHERE e.student_id = :id ORDER BY e.submitted_at DESC
                """).param("id", id).query().listOfRows());
        // the student's summary brought up to date with the account just read, so the lists and figures agree with it (V723: every
        // student of the population, studying too)
        jdbc.sql("""
                SELECT finance.historical_refresh(ARRAY[s.id]) FROM people.student s
                 WHERE s.id = :id AND finance.historical_population(s.status, s.id, s.entry_session)
                """).param("id", id).query().listOfRows();
        out.put("assessments", jdbc.sql("""
                SELECT a.id, a.reference, a.session, a.semester, a.level, a.amount, a.components::text AS components, a.source, a.source_reference, a.reason, a.remarks,
                       a.state, a.created_at, a.created_office, helpdesk.person_name(a.created_by) AS created_by_name, a.submitted_at, a.decided_at, a.decided_office,
                       helpdesk.person_name(a.decided_by) AS decided_by_name, a.decision_note,
                       (SELECT b.reference FROM finance.historical_batch b WHERE b.id = a.batch_id) AS batch,
                       (SELECT c.reference FROM finance.historical_assessment c WHERE c.id = a.corrects) AS corrects,
                       (SELECT c.reference FROM finance.historical_assessment c WHERE c.id = a.superseded_by) AS superseded_by
                  FROM finance.historical_assessment a WHERE a.student_id = :id ORDER BY a.session, a.semester, a.created_at
                """).param("id", id).query().listOfRows());
        if (permissions().contains("VIEW_HISTORICAL_PAYMENT")) {
            out.put("payments", jdbc.sql("""
                    SELECT r.reference, r.session, r.purpose, r.amount, r.generated_at, r.confirmed_at, r.channel, r.receipt_no,
                           (SELECT i.original_identifier_type || ' ' || i.original_identifier FROM finance.payment_identity i WHERE i.payment_id = r.id LIMIT 1) AS paid_as
                      FROM finance.payment_reference r
                     WHERE r.student_id = :id AND r.purpose LIKE 'School fees%' AND (r.confirmed_at IS NOT NULL OR r.expires_at > now()) AND r.archived_at IS NULL
                     ORDER BY r.session, r.confirmed_at NULLS LAST
                    """).param("id", id).query().listOfRows());
            out.put("reallocations", jdbc.sql("SELECT * FROM finance.payment_reallocations_of(:id)").param("id", id).query().listOfRows());
            // V665: payments outside school fees in a session the student owes, for the Bursary to look at
            out.put("otherPayments", jdbc.sql("SELECT o.* FROM finance.historical_other_payments(ARRAY[CAST(:id AS uuid)]) o ORDER BY o.session, o.confirmed_at")
                    .param("id", id).query().listOfRows());
        }
        out.put("waivers", jdbc.sql("""
                SELECT w.id, w.reference, w.session, w.semester, w.kind, w.amount, w.reason, w.authority, w.state, w.created_at, w.created_office,
                       helpdesk.person_name(w.created_by) AS created_by_name, w.created_by = CAST(:me AS uuid) AS mine, w.decided_at, w.decided_office,
                       helpdesk.person_name(w.decided_by) AS decided_by_name, w.decision_note, w.revoked_at, helpdesk.person_name(w.revoked_by) AS revoked_by_name,
                       w.revoke_reason, (SELECT count(*) FROM finance.historical_waiver_evidence e WHERE e.waiver_id = w.id) AS evidence
                  FROM finance.historical_waiver w WHERE w.student_id = :id ORDER BY w.session, w.semester, w.created_at
                """).param("id", id).param("me", AuditContextHolder.current().map(AuditContext::actorId).orElse(null), Types.OTHER).query().listOfRows());
        out.put("awaitingFinalClearance", jdbc.sql("SELECT records.awaiting_final_clearance(:id)").param("id", id).query(Boolean.class).single());
        out.put("clearance", jdbc.sql("""
                SELECT q.id, q.reference, q.session, q.started_at, q.completed_at, clearance.overall(q.id) AS overall,
                       (SELECT i.state FROM clearance.item i WHERE i.process_id = q.id AND i.unit = 'BURSARY' AND i.superseded_by IS NULL ORDER BY i.decided_at DESC LIMIT 1) AS bursary,
                       (SELECT i.decided_at FROM clearance.item i WHERE i.process_id = q.id AND i.unit = 'BURSARY' AND i.superseded_by IS NULL ORDER BY i.decided_at DESC LIMIT 1) AS bursary_at,
                       q.verify_code
                  FROM clearance.process q WHERE q.student_id = :id AND q.workflow = 'FINAL' AND q.cancelled_at IS NULL
                 ORDER BY q.started_at DESC LIMIT 1
                """).param("id", id).query().listOfRows().stream().findFirst().orElse(null));
        return out;
    }

    /* ── assessments ── */

    @PostMapping("/assessments")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> create(@Valid @RequestBody AssessmentIn body) {
        if (body.studentId() == null || body.session() == null || body.semester() == null) {
            throw new DomainRuleViolation("HFA_PERIOD", "Name the student, the session and the semester.", new DomainRuleViolation.Remedy("Choose a period of the record.", "Bursary"));
        }
        Map<String, Object> saved = save(null, body);
        return assessment(UUID.fromString(String.valueOf(saved.get("id"))));
    }

    @PutMapping("/assessments/{id}")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> edit(@PathVariable UUID id, @Valid @RequestBody AssessmentIn body) {
        save(id, body);
        return assessment(id);
    }

    private Map<String, Object> save(UUID id, AssessmentIn body) {
        return jdbc.sql("""
                SELECT x.* FROM finance.historical_assessment_save(:id, :st, :ses, :sem, :amt, CAST(:comp AS jsonb), :src, :sref, :reason, :remarks, :corrects, :submit) x
                """).param("id", id, Types.OTHER).param("st", body.studentId(), Types.OTHER).param("ses", blank(body.session()), Types.VARCHAR)
                .param("sem", body.semester(), Types.INTEGER).param("amt", body.amount()).param("comp", components(body.components()))
                .param("src", body.source().trim().toUpperCase()).param("sref", blank(body.sourceReference()), Types.VARCHAR).param("reason", body.reason())
                .param("remarks", blank(body.remarks()), Types.VARCHAR).param("corrects", body.corrects(), Types.OTHER)
                .param("submit", Boolean.TRUE.equals(body.submit())).query().singleRow();
    }

    @PostMapping("/assessments/{id}/submit")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> submit(@PathVariable UUID id) {
        jdbc.sql("SELECT finance.historical_assessment_submit(:id)").param("id", id).query(String.class).single();
        return assessment(id);
    }

    /** the Bursar: approved (in force, the student told), returned for correction or rejected — never by the officer who made it */
    @PostMapping("/assessments/{id}/decide")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_super')")
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        jdbc.sql("SELECT finance.historical_assessment_decide(:id, :d, :n)").param("id", id).param("d", body.decision()).param("n", body.note(), Types.VARCHAR)
                .query(String.class).single();
        return assessment(id);
    }

    @PostMapping("/assessments/{id}/cancel")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody(required = false) NoteIn body) {
        jdbc.sql("SELECT finance.historical_assessment_cancel(:id, :n)").param("id", id).param("n", body == null ? null : body.note(), Types.VARCHAR)
                .query(String.class).single();
        return assessment(id);
    }

    /** the assessments by state — the Bursar's approval queue by default — each with the period's account beside it */
    @GetMapping("/assessments")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> assessments(@RequestParam(defaultValue = "PENDING_BURSAR_APPROVAL") String state, @RequestParam(required = false) String q,
                                    @RequestParam(required = false) String session, @RequestParam(defaultValue = "0") int page) {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        String st = "ALL".equalsIgnoreCase(state) ? null : STATES.contains(state) ? state : "PENDING_BURSAR_APPROVAL";
        String term = blank(q);
        int p = Math.max(0, Math.min(page, 2000));
        String where = """
                FROM finance.historical_assessment a JOIN people.student s ON s.id = a.student_id JOIN ref.programme p ON p.code = s.programme_code
                LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                WHERE (CAST(:st AS text) IS NULL OR a.state = :st) AND (CAST(:ses AS text) IS NULL OR a.session = :ses)
                  AND (CAST(:q AS text) IS NULL OR a.reference ILIKE '%' || :q || '%' OR s.matric_no ILIKE '%' || :q || '%'
                       OR (s.surname || ' ' || s.other_names) ILIKE '%' || :q || '%')
                """ + PG_ONLY_WHERE + """
                """;
        long total = jdbc.sql("SELECT count(*) " + where).param("st", st, Types.VARCHAR).param("ses", blank(session), Types.VARCHAR).param("q", term, Types.VARCHAR).param("pgonly", pgOnly())
                .query(Long.class).single();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT a.id, a.reference, a.session, a.semester, a.level, a.amount, a.source, a.source_reference, a.state, a.created_at, a.submitted_at,
                       helpdesk.person_name(a.created_by) AS created_by_name, a.created_by = CAST(:me AS uuid) AS mine,
                       (SELECT b.reference FROM finance.historical_batch b WHERE b.id = a.batch_id) AS batch,
                       s.id AS student_id, s.surname, s.other_names, s.matric_no, s.jamb_reg_no, p.name AS programme, d.name AS department, f.name AS faculty
                """ + where + " ORDER BY coalesce(a.submitted_at, a.created_at) LIMIT :lim OFFSET :off")
                .param("st", st, Types.VARCHAR).param("ses", blank(session), Types.VARCHAR).param("q", term, Types.VARCHAR).param("pgonly", pgOnly())
                .param("me", AuditContextHolder.current().map(AuditContext::actorId).orElse(null), Types.OTHER)
                .param("lim", PAGE).param("off", p * PAGE).query().listOfRows();
        // the period's account beside each: what is paid towards it and what would be owed
        List<UUID> ids = rows.stream().map(r -> UUID.fromString(String.valueOf(r.get("student_id")))).distinct().toList();
        if (!ids.isEmpty()) {
            List<Map<String, Object>> acct = jdbc.sql("SELECT x.student_id, x.session, x.semester, x.paid, x.outstanding, x.structure_amount FROM finance.historical_rows(CAST(:ids AS uuid[])) x")
                    .param("ids", ids.stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).query().listOfRows();
            for (Map<String, Object> r : rows) {
                acct.stream().filter(x -> String.valueOf(x.get("student_id")).equals(String.valueOf(r.get("student_id")))
                                && String.valueOf(x.get("session")).equals(String.valueOf(r.get("session")))
                                && String.valueOf(x.get("semester")).equals(String.valueOf(r.get("semester"))))
                        .findFirst().ifPresent(x -> {
                            r.put("paid", x.get("paid"));
                            r.put("outstanding", x.get("outstanding"));
                            r.put("structure_amount", x.get("structure_amount"));
                        });
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", p);
        out.put("size", PAGE);
        out.put("rows", rows);
        return out;
    }

    @GetMapping("/assessments/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> assessment(@PathVariable UUID id) {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        Map<String, Object> a = jdbc.sql("""
                SELECT a.id, a.reference, a.student_id, a.session, a.semester, a.level, a.programme_code, a.amount, a.components::text AS components, a.source,
                       a.source_reference, a.reason, a.remarks, a.state, a.created_at, a.created_office, helpdesk.person_name(a.created_by) AS created_by_name,
                       a.created_by = CAST(:me AS uuid) AS mine, a.submitted_at, a.decided_at, a.decided_office, helpdesk.person_name(a.decided_by) AS decided_by_name,
                       a.decision_note, (SELECT b.reference FROM finance.historical_batch b WHERE b.id = a.batch_id) AS batch,
                       (SELECT c.reference FROM finance.historical_assessment c WHERE c.id = a.corrects) AS corrects,
                       (SELECT c.reference FROM finance.historical_assessment c WHERE c.id = a.superseded_by) AS superseded_by,
                       s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.status AS student_status, p.name AS programme
                  FROM finance.historical_assessment a JOIN people.student s ON s.id = a.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE a.id = :id
                """).param("id", id).param("me", AuditContextHolder.current().map(AuditContext::actorId).orElse(null), Types.OTHER)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("historical assessment", id));
        inScope(UUID.fromString(String.valueOf(a.get("student_id"))));   // V723
        Map<String, Object> out = new LinkedHashMap<>(a);
        out.put("period", jdbc.sql("SELECT x.* FROM finance.historical_account(:st) x WHERE x.session = :ses AND x.semester = :sem")
                .param("st", a.get("student_id")).param("ses", a.get("session")).param("sem", a.get("semester")).query().listOfRows().stream().findFirst().orElse(null));
        if (permissions().contains("VIEW_ASSESSMENT_HISTORY")) {
            out.put("events", jdbc.sql("""
                    SELECT e.action, e.at, e.office, e.note, e.amount, helpdesk.person_name(e.actor) AS actor_name
                      FROM finance.historical_assessment_event e WHERE e.assessment_id = :id ORDER BY e.at
                    """).param("id", id).query().listOfRows());
        }
        out.put("evidence", jdbc.sql("""
                SELECT e.id, e.filename, e.content_type, e.size_bytes, e.added_at, helpdesk.person_name(e.added_by) AS added_by
                  FROM finance.historical_assessment_evidence e WHERE e.assessment_id = :id ORDER BY e.added_at
                """).param("id", id).query().listOfRows());
        return out;
    }

    @PostMapping("/assessments/{id}/evidence")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> evidence(@PathVariable UUID id, @Valid @RequestBody EvidenceIn body) {
        need("EDIT_HISTORICAL_FEE_ASSESSMENT");
        String state = jdbc.sql("SELECT state FROM finance.historical_assessment WHERE id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("historical assessment", id));
        if (!Set.of("DRAFT", "PENDING_BURSAR_APPROVAL", "RETURNED_FOR_CORRECTION").contains(state)) {
            throw new DomainRuleViolation("HFA_NOT_EDITABLE", "Evidence is added while the assessment is being made or awaits the Bursar.",
                    new DomainRuleViolation.Remedy("A correction carries its own evidence.", "Bursary"));
        }
        String u = body.dataUrl();
        int comma = u.indexOf(',');
        String meta = comma > 0 && u.startsWith("data:") ? u.substring(5, comma) : "";
        String type = meta.contains(";") ? meta.substring(0, meta.indexOf(';')) : meta;
        if (!EVIDENCE_TYPES.contains(type)) {
            throw new DomainRuleViolation("HFA_EVIDENCE_TYPE", "Evidence is a PDF, JPEG or PNG file.", new DomainRuleViolation.Remedy("Scan or save it as one of those.", "You"));
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(u.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("HFA_EVIDENCE_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > 5 * 1024 * 1024) {
            throw new DomainRuleViolation("HFA_EVIDENCE_SIZE", "Evidence is up to 5 MB.", new DomainRuleViolation.Remedy("Scan it at a lower resolution.", "You"));
        }
        UUID object = files.store("finance.historical_assessment_evidence", id, body.filename(), type, bytes);
        jdbc.sql("""
                INSERT INTO finance.historical_assessment_evidence (assessment_id, filename, content_type, size_bytes, content, object_id, added_by)
                VALUES (:x, :f, :t, :n, :c, :o, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                """).param("x", id).param("f", body.filename().trim()).param("t", type).param("n", (long) bytes.length)
                .param("c", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).update();
        jdbc.sql("SELECT finance.historical_event(:x, 'EVIDENCE_ADDED', :n, NULL)").param("x", id).param("n", body.filename().trim()).query().listOfRows();
        return assessment(id);
    }

    @GetMapping("/assessments/{id}/evidence/{evidence}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> evidenceFile(@PathVariable UUID id, @PathVariable UUID evidence) {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        inScope(studentOf("finance.historical_assessment", id));   // V723
        Map<String, Object> e = jdbc.sql("SELECT filename, content_type, content, object_id FROM finance.historical_assessment_evidence WHERE id = :e AND assessment_id = :x")
                .param("e", evidence).param("x", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("evidence", evidence));
        byte[] bytes = e.get("content") instanceof byte[] b ? b : files.load(UUID.fromString(String.valueOf(e.get("object_id"))));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(e.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + String.valueOf(e.get("filename")).replaceAll("[^A-Za-z0-9._ -]", "_") + "\"")
                .body(bytes);
    }

    /* ── waivers and adjustments (V665) ── */

    /** a waiver or adjustment proposed — the Students Account Officer or the Bursar; another Bursar officer decides it */
    @PostMapping("/waivers")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> proposeWaiver(@Valid @RequestBody WaiverIn body) {
        UUID id = jdbc.sql("SELECT (finance.historical_waiver_propose(:st, :ses, :sem, :k, :amt, :r, :auth)).id")
                .param("st", body.studentId()).param("ses", body.session()).param("sem", body.semester()).param("k", body.kind())
                .param("amt", body.amount()).param("r", body.reason()).param("auth", body.authority()).query(UUID.class).single();
        if (body.evidence() != null) storeWaiverEvidence(id, body.evidence());
        return waiver(id);
    }

    @PostMapping("/waivers/{id}/evidence")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> waiverEvidence(@PathVariable UUID id, @Valid @RequestBody EvidenceIn body) {
        need("CREATE_HISTORICAL_FEE_ASSESSMENT");
        String state = jdbc.sql("SELECT state FROM finance.historical_waiver WHERE id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("waiver", id));
        if (!"PENDING_BURSAR_APPROVAL".equals(state)) {
            throw new DomainRuleViolation("HFW_NOT_PENDING", "Evidence is added while the waiver awaits the Bursar.",
                    new DomainRuleViolation.Remedy("A decided waiver is kept as it was.", "Bursary"));
        }
        storeWaiverEvidence(id, body);
        return waiver(id);
    }

    private void storeWaiverEvidence(UUID id, EvidenceIn body) {
        String u = body.dataUrl();
        int comma = u.indexOf(',');
        String meta = comma > 0 && u.startsWith("data:") ? u.substring(5, comma) : "";
        String type = meta.contains(";") ? meta.substring(0, meta.indexOf(';')) : meta;
        if (!EVIDENCE_TYPES.contains(type)) {
            throw new DomainRuleViolation("HFW_EVIDENCE_TYPE", "Evidence is a PDF, JPEG or PNG file.", new DomainRuleViolation.Remedy("Scan or save it as one of those.", "You"));
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(u.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("HFW_EVIDENCE_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > 5 * 1024 * 1024) {
            throw new DomainRuleViolation("HFW_EVIDENCE_SIZE", "Evidence is up to 5 MB.", new DomainRuleViolation.Remedy("Scan it at a lower resolution.", "You"));
        }
        UUID object = files.store("finance.historical_waiver_evidence", id, body.filename(), type, bytes);
        jdbc.sql("""
                INSERT INTO finance.historical_waiver_evidence (waiver_id, filename, content_type, size_bytes, content, object_id, added_by)
                VALUES (:x, :f, :t, :n, :c, :o, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                """).param("x", id).param("f", body.filename().trim()).param("t", type).param("n", (long) bytes.length)
                .param("c", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).update();
    }

    @GetMapping("/waivers/{id}/evidence/{evidence}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> waiverEvidenceFile(@PathVariable UUID id, @PathVariable UUID evidence) {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        inScope(studentOf("finance.historical_waiver", id));   // V723
        Map<String, Object> e = jdbc.sql("SELECT filename, content_type, content, object_id FROM finance.historical_waiver_evidence WHERE id = :e AND waiver_id = :x")
                .param("e", evidence).param("x", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("evidence", evidence));
        byte[] bytes = e.get("content") instanceof byte[] b ? b : files.load(UUID.fromString(String.valueOf(e.get("object_id"))));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(e.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + String.valueOf(e.get("filename")).replaceAll("[^A-Za-z0-9._ -]", "_") + "\"")
                .body(bytes);
    }

    /** the Bursar: approved (the period owes less, the student told) or rejected with a reason — never by the officer who proposed it */
    @PostMapping("/waivers/{id}/decide")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_super')")
    @Transactional
    Map<String, Object> decideWaiver(@PathVariable UUID id, @Valid @RequestBody WaiverDecideIn body) {
        jdbc.sql("SELECT finance.historical_waiver_decide(:id, :d, :n)").param("id", id).param("d", body.decision()).param("n", body.note(), Types.VARCHAR)
                .query(String.class).single();
        return waiver(id);
    }

    @PostMapping("/waivers/{id}/withdraw")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> withdrawWaiver(@PathVariable UUID id, @Valid @RequestBody(required = false) NoteIn body) {
        jdbc.sql("SELECT finance.historical_waiver_withdraw(:id, :n)").param("id", id).param("n", body == null ? null : body.note(), Types.VARCHAR)
                .query(String.class).single();
        return waiver(id);
    }

    /** an approved waiver revoked by the Bursar with a reason: the amount owed again (a graduated student stays graduated) */
    @PostMapping("/waivers/{id}/revoke")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_super')")
    @Transactional
    Map<String, Object> revokeWaiver(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        jdbc.sql("SELECT finance.historical_waiver_revoke(:id, :r)").param("id", id).param("r", body.reason()).query(String.class).single();
        return waiver(id);
    }

    /** the waivers by state — the Bursar's queue by default — each with the period's account beside it */
    @GetMapping("/waivers")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> waivers(@RequestParam(defaultValue = "PENDING_BURSAR_APPROVAL") String state, @RequestParam(required = false) String q,
                                @RequestParam(defaultValue = "0") int page) {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        String st = "ALL".equalsIgnoreCase(state) ? null : WAIVER_STATES.contains(state) ? state : "PENDING_BURSAR_APPROVAL";
        String term = blank(q);
        int p = Math.max(0, Math.min(page, 2000));
        String where = """
                FROM finance.historical_waiver w JOIN people.student s ON s.id = w.student_id JOIN ref.programme p ON p.code = s.programme_code
                WHERE (CAST(:st AS text) IS NULL OR w.state = :st)
                  AND (CAST(:q AS text) IS NULL OR w.reference ILIKE '%' || :q || '%' OR s.matric_no ILIKE '%' || :q || '%'
                       OR (s.surname || ' ' || s.other_names) ILIKE '%' || :q || '%')
                """ + PG_ONLY_WHERE + """
                """;
        long total = jdbc.sql("SELECT count(*) " + where).param("st", st, Types.VARCHAR).param("q", term, Types.VARCHAR).param("pgonly", pgOnly()).query(Long.class).single();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT w.id, w.reference, w.session, w.semester, w.kind, w.amount, w.reason, w.authority, w.state, w.created_at,
                       helpdesk.person_name(w.created_by) AS created_by_name, w.created_by = CAST(:me AS uuid) AS mine, w.decided_at,
                       s.id AS student_id, s.surname, s.other_names, s.matric_no, s.status AS student_status, p.name AS programme
                """ + where + " ORDER BY w.created_at LIMIT :lim OFFSET :off")
                .param("st", st, Types.VARCHAR).param("q", term, Types.VARCHAR).param("pgonly", pgOnly())
                .param("me", AuditContextHolder.current().map(AuditContext::actorId).orElse(null), Types.OTHER)
                .param("lim", PAGE).param("off", p * PAGE).query().listOfRows();
        List<UUID> ids = rows.stream().map(r -> UUID.fromString(String.valueOf(r.get("student_id")))).distinct().toList();
        if (!ids.isEmpty()) {
            List<Map<String, Object>> acct = jdbc.sql("SELECT x.student_id, x.session, x.semester, x.assessed, x.paid, x.waived, x.outstanding FROM finance.historical_rows(CAST(:ids AS uuid[])) x")
                    .param("ids", ids.stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).query().listOfRows();
            for (Map<String, Object> r : rows) {
                acct.stream().filter(x -> String.valueOf(x.get("student_id")).equals(String.valueOf(r.get("student_id")))
                                && String.valueOf(x.get("session")).equals(String.valueOf(r.get("session")))
                                && String.valueOf(x.get("semester")).equals(String.valueOf(r.get("semester"))))
                        .findFirst().ifPresent(x -> {
                            r.put("assessed", x.get("assessed"));
                            r.put("paid", x.get("paid"));
                            r.put("waived", x.get("waived"));
                            r.put("outstanding", x.get("outstanding"));
                        });
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", p);
        out.put("size", PAGE);
        out.put("rows", rows);
        return out;
    }

    @GetMapping("/waivers/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> waiver(@PathVariable UUID id) {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        Map<String, Object> w = jdbc.sql("""
                SELECT w.id, w.reference, w.student_id, w.session, w.semester, w.kind, w.amount, w.reason, w.authority, w.state, w.created_at, w.created_office,
                       helpdesk.person_name(w.created_by) AS created_by_name, w.created_by = CAST(:me AS uuid) AS mine, w.decided_at, w.decided_office,
                       helpdesk.person_name(w.decided_by) AS decided_by_name, w.decision_note, w.revoked_at, helpdesk.person_name(w.revoked_by) AS revoked_by_name,
                       w.revoke_reason, s.surname, s.other_names, s.matric_no, s.status AS student_status, p.name AS programme
                  FROM finance.historical_waiver w JOIN people.student s ON s.id = w.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE w.id = :id
                """).param("id", id).param("me", AuditContextHolder.current().map(AuditContext::actorId).orElse(null), Types.OTHER)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("waiver", id));
        inScope(UUID.fromString(String.valueOf(w.get("student_id"))));   // V723
        Map<String, Object> out = new LinkedHashMap<>(w);
        out.put("period", jdbc.sql("SELECT x.* FROM finance.historical_account(:st) x WHERE x.session = :ses AND x.semester = :sem")
                .param("st", w.get("student_id")).param("ses", w.get("session")).param("sem", w.get("semester")).query().listOfRows().stream().findFirst().orElse(null));
        out.put("evidence", jdbc.sql("""
                SELECT e.id, e.filename, e.content_type, e.size_bytes, e.added_at, helpdesk.person_name(e.added_by) AS added_by
                  FROM finance.historical_waiver_evidence e WHERE e.waiver_id = :id ORDER BY e.added_at
                """).param("id", id).query().listOfRows());
        return out;
    }

    /* ── payment evidence (V683) ── */

    static final Set<String> EVIDENCE_STATES = Set.of("SUBMITTED", "MORE_INFORMATION_REQUIRED", "VERIFIED", "REJECTED", "WITHDRAWN");

    /** graduates' payment evidence by state — the evidence awaiting the Bursary by default — each with the period's account beside it
     *  and, once verified, where the payment linked stands */
    @GetMapping("/evidence")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> evidenceList(@RequestParam(defaultValue = "SUBMITTED") String state, @RequestParam(required = false) String q,
                                     @RequestParam(defaultValue = "0") int page) {
        need("VIEW_HISTORICAL_PAYMENT");
        String st = "ALL".equalsIgnoreCase(state) ? null : EVIDENCE_STATES.contains(state) ? state : "SUBMITTED";
        String term = blank(q);
        int pg = Math.max(0, Math.min(page, 2000));
        String where = """
                FROM finance.historical_payment_evidence e JOIN people.student s ON s.id = e.student_id JOIN ref.programme p ON p.code = s.programme_code
                WHERE (CAST(:st AS text) IS NULL OR e.state = :st)
                  AND (CAST(:q AS text) IS NULL OR e.reference ILIKE '%' || :q || '%' OR e.payment_reference ILIKE '%' || :q || '%'
                       OR s.matric_no ILIKE '%' || :q || '%' OR s.jamb_reg_no ILIKE '%' || :q || '%' OR (s.surname || ' ' || s.other_names) ILIKE '%' || :q || '%')
                """ + PG_ONLY_WHERE + """
                """;
        long total = jdbc.sql("SELECT count(*) " + where).param("st", st, Types.VARCHAR).param("q", term, Types.VARCHAR).param("pgonly", pgOnly()).query(Long.class).single();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT e.id, e.reference, e.session, e.semester, e.amount, e.paid_on::text AS paid_on, e.channel, e.payment_reference, e.state, e.submitted_at,
                       e.decided_at, (SELECT count(*) FROM finance.historical_payment_evidence_file f WHERE f.evidence_id = e.id) AS files,
                       (SELECT r.reference FROM finance.payment_reference r WHERE r.id = e.payment_id) AS payment,
                       finance.historical_evidence_payment_state(e.payment_id, e.student_id, e.session) AS payment_state,
                       s.id AS student_id, s.surname, s.other_names, s.matric_no, s.status AS student_status, p.name AS programme
                """ + where + " ORDER BY e.submitted_at LIMIT :lim OFFSET :off")
                .param("st", st, Types.VARCHAR).param("q", term, Types.VARCHAR).param("pgonly", pgOnly()).param("lim", PAGE).param("off", pg * PAGE).query().listOfRows();
        List<UUID> ids = rows.stream().map(r -> UUID.fromString(String.valueOf(r.get("student_id")))).distinct().toList();
        if (!ids.isEmpty()) {
            List<Map<String, Object>> acct = jdbc.sql("SELECT x.student_id, x.session, x.semester, x.assessed, x.paid, x.waived, x.outstanding, x.status FROM finance.historical_rows(CAST(:ids AS uuid[])) x")
                    .param("ids", ids.stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).query().listOfRows();
            for (Map<String, Object> r : rows) {
                acct.stream().filter(x -> String.valueOf(x.get("student_id")).equals(String.valueOf(r.get("student_id")))
                                && String.valueOf(x.get("session")).equals(String.valueOf(r.get("session")))
                                && String.valueOf(x.get("semester")).equals(String.valueOf(r.get("semester"))))
                        .findFirst().ifPresent(x -> {
                            r.put("assessed", x.get("assessed"));
                            r.put("paid", x.get("paid"));
                            r.put("outstanding", x.get("outstanding"));
                            r.put("period_status", x.get("status"));
                        });
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", pg);
        out.put("size", PAGE);
        out.put("rows", rows);
        return out;
    }

    /** one evidence: what the graduate said, the files, the timeline, the period's account, and the payments on record it may be */
    @GetMapping("/evidence/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> evidenceOne(@PathVariable UUID id) {
        need("VIEW_HISTORICAL_PAYMENT");
        Map<String, Object> e = jdbc.sql("""
                SELECT e.id, e.reference, e.student_id, e.session, e.semester, e.amount, e.paid_on::text AS paid_on, e.channel, e.payment_reference, e.note, e.state,
                       e.submitted_at, e.updated_at, e.decided_at, e.decided_office, helpdesk.person_name(e.decided_by) AS decided_by_name, e.decision_note,
                       e.payment_id, (SELECT r.reference FROM finance.payment_reference r WHERE r.id = e.payment_id) AS payment,
                       finance.historical_evidence_payment_state(e.payment_id, e.student_id, e.session) AS payment_state,
                       s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.status AS student_status, p.name AS programme
                  FROM finance.historical_payment_evidence e JOIN people.student s ON s.id = e.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE e.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("payment evidence", id));
        inScope(UUID.fromString(String.valueOf(e.get("student_id"))));   // V723
        Map<String, Object> out = new LinkedHashMap<>(e);
        out.put("period", jdbc.sql("SELECT x.* FROM finance.historical_account(:st) x WHERE x.session = :ses AND x.semester = :sem")
                .param("st", e.get("student_id")).param("ses", e.get("session")).param("sem", e.get("semester")).query().listOfRows().stream().findFirst().orElse(null));
        out.put("files", jdbc.sql("""
                SELECT f.id, f.filename, f.content_type, f.size_bytes, f.added_at, f.added_office FROM finance.historical_payment_evidence_file f
                 WHERE f.evidence_id = :id ORDER BY f.added_at
                """).param("id", id).query().listOfRows());
        out.put("events", jdbc.sql("""
                SELECT v.action, v.at, v.office, v.note, CASE WHEN v.office = 'student' THEN 'The graduate' ELSE helpdesk.person_name(v.actor) END AS by_name
                  FROM finance.historical_payment_evidence_event v WHERE v.evidence_id = :id ORDER BY v.at
                """).param("id", id).query().listOfRows());
        // V723: the payer of a candidate is the School's to see only when a postgraduate student; an old-portal hold names no one it may see
        out.put("candidates", jdbc.sql("""
                SELECT c.* FROM finance.historical_evidence_candidates(:id) c
                  LEFT JOIN people.student s ON s.id = c.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE NOT CAST(:pgonly AS boolean) OR coalesce(people.is_postgraduate(s.entry_mode, p.category), false)
                """).param("id", id).param("pgonly", pgOnly()).query().listOfRows());
        // an old-portal record held because its number named no student (V647): reconciled on School Fees History Reconciliation first
        out.put("held", jdbc.sql("""
                SELECT h.payref, h.original_identifier, h.purpose, h.session, h.semester, h.amount, h.status
                  FROM finance.legacy_payment_held h
                 WHERE h.payref IN (btrim(:r), upper(btrim(:r)), lower(btrim(:r))) AND NOT CAST(:pgonly AS boolean) LIMIT 10
                """).param("r", e.get("payment_reference")).param("pgonly", pgOnly()).query().listOfRows());
        return out;
    }

    /** a confirmed payment found by another number than the one on the evidence (from a bank statement, the old portal) */
    @GetMapping("/evidence/{id}/search")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> evidenceSearch(@PathVariable UUID id, @RequestParam String ref) {
        need("VIEW_HISTORICAL_PAYMENT");
        Map<String, Object> e = jdbc.sql("SELECT e.id, e.student_id, e.session FROM finance.historical_payment_evidence e WHERE e.id = :id").param("id", id)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("payment evidence", id));
        inScope(UUID.fromString(String.valueOf(e.get("student_id"))));   // V723
        String r = blank(ref);
        if (r == null || r.length() < 4) return List.of();
        return jdbc.sql("""
                SELECT r.id AS payment_id, r.reference, r.receipt_no, r.student_id, s.matric_no, s.surname || ', ' || s.other_names AS name, r.session, r.purpose, r.amount,
                       r.confirmed_at, r.channel, r.archived_at IS NOT NULL AS archived, 'SEARCH' AS why,
                       finance.historical_evidence_payment_state(r.id, CAST(:st AS uuid), :ses) AS state,
                       (SELECT v.reference FROM finance.historical_payment_evidence v WHERE v.payment_id = r.id AND v.state = 'VERIFIED') AS verified_for
                  FROM finance.payment_reference r LEFT JOIN people.student s ON s.id = r.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE r.confirmed_at IS NOT NULL AND (r.reference IN (:r, upper(:r), lower(:r)) OR r.receipt_no IN (:r, upper(:r), lower(:r)))
                   AND (NOT CAST(:pgonly AS boolean) OR coalesce(people.is_postgraduate(s.entry_mode, p.category), false))   -- V723
                 LIMIT 20
                """).param("r", r).param("pgonly", pgOnly()).param("st", e.get("student_id"), Types.OTHER).param("ses", e.get("session")).query().listOfRows();
    }

    @GetMapping("/evidence/{id}/files/{file}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> evidenceUpload(@PathVariable UUID id, @PathVariable UUID file) {
        need("VIEW_HISTORICAL_PAYMENT");
        inScope(studentOf("finance.historical_payment_evidence", id));   // V723
        Map<String, Object> f = jdbc.sql("SELECT filename, content_type, content, object_id FROM finance.historical_payment_evidence_file WHERE id = :f AND evidence_id = :x")
                .param("f", file).param("x", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("evidence file", file));
        byte[] bytes = f.get("content") instanceof byte[] b ? b : files.load(UUID.fromString(String.valueOf(f.get("object_id"))));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(f.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + String.valueOf(f.get("filename")).replaceAll("[^A-Za-z0-9._ -]", "_") + "\"")
                .body(bytes);
    }

    /** the Students Account Officer or the Bursar decides the evidence (REVIEW_PAYMENT_EVIDENCE, checked again in the database) */
    @PostMapping("/evidence/{id}/decide")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> decideEvidence(@PathVariable UUID id, @Valid @RequestBody EvidenceDecideIn body) {
        need("REVIEW_PAYMENT_EVIDENCE");
        String answer = jdbc.sql("SELECT finance.historical_evidence_decide(:id, :d, :n, :p)::text").param("id", id).param("d", body.decision())
                .param("n", body.note(), Types.VARCHAR).param("p", body.payment(), Types.OTHER).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(evidenceOne(id));
        out.put("decided", JSON.readValue(answer, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { }));
        return out;
    }

    /* ── reconciliation runs (V665) ── */

    /** a run: the population's financial clearance worked out at once (CLEARANCE-RECON/YYYY/NNNNNN) and kept as it was found */
    @PostMapping("/recon-runs")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> startRecon(@Valid @RequestBody ReconIn body) {
        Map<String, Object> scope = new LinkedHashMap<>();
        scope.put("population", blank(body.population()) == null ? "AWAITING_GRADUATION" : body.population());
        if (blank(body.faculty()) != null) scope.put("faculty", body.faculty().trim());
        if (blank(body.dept()) != null) scope.put("dept", body.dept().trim());
        if (blank(body.programme()) != null) scope.put("programme", body.programme().trim());
        if (blank(body.admission()) != null) scope.put("admission", body.admission().trim());
        if (blank(body.graduation()) != null) scope.put("graduation", body.graduation().trim());
        UUID id = jdbc.sql("SELECT (finance.clearance_recon_start(CAST(:scope AS jsonb))).id").param("scope", JSON.writeValueAsString(scope)).query(UUID.class).single();
        return reconRun(id, null, null, 0, false);
    }

    @GetMapping("/recon-runs")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> reconRuns() {
        need("VIEW_FINANCIAL_CLEARANCE");
        if (pgOnly()) {
            // V723: the School reads the runs that hold postgraduate students, each counted over those students alone
            return jdbc.sql("""
                    SELECT r.id, r.reference, r.population, r.scope::text AS scope, x.students, r.capped, x.cleared, x.owing, x.review, x.pending, x.payment_review,
                           x.no_period, x.assessed, x.paid, x.waived, x.outstanding, r.run_at, r.run_office, helpdesk.person_name(r.run_by) AS run_by_name
                      FROM finance.clearance_recon_run r CROSS JOIN LATERAL (""" + PG_RUN_COUNTS + ") x WHERE x.students > 0 ORDER BY r.run_at DESC LIMIT 100")
                    .query().listOfRows();
        }
        return jdbc.sql("""
                SELECT r.id, r.reference, r.population, r.scope::text AS scope, r.students, r.capped, r.cleared, r.owing, r.review, r.pending, r.payment_review,
                       r.no_period, r.assessed, r.paid, r.waived, r.outstanding, r.run_at, r.run_office, helpdesk.person_name(r.run_by) AS run_by_name
                  FROM finance.clearance_recon_run r ORDER BY r.run_at DESC LIMIT 100
                """).query().listOfRows();
    }

    /** a run and its rows, by status, paged; export=true for the report (up to 20,000 rows) */
    @GetMapping("/recon-runs/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> reconRun(@PathVariable UUID id, @RequestParam(required = false) String status, @RequestParam(required = false) String q,
                                 @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "false") boolean export) {
        need("VIEW_FINANCIAL_CLEARANCE");
        Map<String, Object> run = jdbc.sql("""
                SELECT r.id, r.reference, r.population, r.scope::text AS scope, r.students, r.capped, r.cleared, r.owing, r.review, r.pending, r.payment_review,
                       r.no_period, r.assessed, r.paid, r.waived, r.outstanding, r.run_at, r.finished_at, r.run_office, helpdesk.person_name(r.run_by) AS run_by_name
                  FROM finance.clearance_recon_run r WHERE r.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("reconciliation run", id));
        if (pgOnly()) {
            // V723: the School reads a run that holds postgraduate students, its counts over those students alone
            Map<String, Object> mine = jdbc.sql("SELECT x.* FROM finance.clearance_recon_run r CROSS JOIN LATERAL (" + PG_RUN_COUNTS + ") x WHERE r.id = :id")
                    .param("id", id).query().singleRow();
            if (((Number) mine.get("students")).longValue() == 0) throw new NotFound("reconciliation run", id);
            run = new LinkedHashMap<>(run);
            run.putAll(mine);
        }
        String st = blank(status) != null && RECON_STATUSES.contains(status.trim()) ? status.trim() : null;
        String term = blank(q);
        int p = Math.max(0, Math.min(page, 2000));
        int size = export ? 20000 : PAGE;
        String where = """
                FROM finance.clearance_recon_row x JOIN people.student s ON s.id = x.student_id JOIN ref.programme p ON p.code = s.programme_code
                LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                WHERE x.run_id = :id AND (CAST(:st AS text) IS NULL OR x.status = :st)
                  AND (CAST(:q AS text) IS NULL OR s.matric_no ILIKE '%' || :q || '%' OR (s.surname || ' ' || s.other_names) ILIKE '%' || :q || '%')
                """ + PG_ONLY_WHERE + """
                """;
        long total = jdbc.sql("SELECT count(*) " + where).param("id", id).param("st", st, Types.VARCHAR).param("q", term, Types.VARCHAR).param("pgonly", pgOnly()).query(Long.class).single();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT x.student_id, s.surname || ', ' || s.other_names AS student, s.matric_no, s.jamb_reg_no, f.name AS faculty, d.name AS department,
                       p.name AS programme, x.status, x.student_status, x.awaiting_graduation, x.graduation_session, x.periods, x.assessed, x.paid, x.waived,
                       x.outstanding, x.credit, x.owing, x.review_periods, x.pending_periods, x.other_payments, x.other_amount, x.process_id, x.clearance_ref,
                       x.bursary_state
                """ + where + " ORDER BY CASE x.status WHEN 'CLEARED' THEN 9 ELSE 0 END, x.outstanding DESC, s.surname, s.other_names LIMIT :lim OFFSET :off")
                .param("id", id).param("st", st, Types.VARCHAR).param("q", term, Types.VARCHAR).param("pgonly", pgOnly()).param("lim", size).param("off", export ? 0 : p * PAGE)
                .query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("run", run);
        out.put("total", total);
        out.put("page", export ? 0 : p);
        out.put("size", size);
        out.put("rows", rows);
        return out;
    }

    /* ── a cohort ── */

    @PostMapping("/bulk/preview")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional(readOnly = true)
    Map<String, Object> bulkPreview(@Valid @RequestBody PreviewIn body) {
        need("CREATE_HISTORICAL_FEE_ASSESSMENT");
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT x.student_id, x.verdict, x.level, x.structure_amount, x.assessed, x.paid, x.outstanding, x.reference,
                       s.surname, s.other_names, s.matric_no, s.status, p.name AS programme
                  FROM finance.historical_bulk_preview(:ses, :sem, :fac, :dept, :prog, :lvl, :grad, 3000) x
                  JOIN people.student s ON s.id = x.student_id JOIN ref.programme p ON p.code = s.programme_code
                 ORDER BY x.verdict DESC, s.surname, s.other_names
                """).param("ses", body.session()).param("sem", body.semester()).param("fac", blank(body.faculty()), Types.VARCHAR)
                .param("dept", blank(body.dept()), Types.VARCHAR).param("prog", blank(body.programme()), Types.VARCHAR).param("lvl", body.level(), Types.INTEGER)
                .param("grad", !Boolean.FALSE.equals(body.graduatedOnly())).query().listOfRows();
        Map<String, Long> by = new LinkedHashMap<>();
        rows.forEach(r -> by.merge(String.valueOf(r.get("verdict")), 1L, Long::sum));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", rows.size());
        out.put("byVerdict", by);
        out.put("paid", rows.stream().filter(r -> "REQUIRES_ASSESSMENT".equals(r.get("verdict"))).map(r -> new BigDecimal(String.valueOf(r.get("paid"))))
                .reduce(BigDecimal.ZERO, BigDecimal::add));
        out.put("rows", rows);
        return out;
    }

    @PostMapping("/bulk")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')")
    @Transactional
    Map<String, Object> bulk(@Valid @RequestBody BulkIn body) {
        return jdbc.sql("""
                SELECT x.* FROM finance.historical_bulk_create(CAST(:ids AS uuid[]), :ses, :sem, :amt, CAST(:comp AS jsonb), :src, :sref, :reason, CAST(:scope AS jsonb)) x
                """).param("ids", body.studentIds().stream().map(UUID::toString).toArray(String[]::new), Types.ARRAY).param("ses", body.session())
                .param("sem", body.semester()).param("amt", body.amount()).param("comp", components(body.components()))
                .param("src", body.source().trim().toUpperCase()).param("sref", blank(body.sourceReference()), Types.VARCHAR).param("reason", body.reason())
                .param("scope", JSON.writeValueAsString(body.scope() == null ? Map.of() : body.scope())).query().singleRow();
    }

    @GetMapping("/batches")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> batches(@RequestParam(defaultValue = "PENDING_BURSAR_APPROVAL") String state) {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        return jdbc.sql("""
                SELECT b.id, b.reference, b.session, b.semester, b.scope::text AS scope, b.amount, b.source, b.source_reference, b.reason, b.students, b.state,
                       b.created_at, helpdesk.person_name(b.created_by) AS created_by_name, b.created_by = CAST(:me AS uuid) AS mine, b.decided_at, b.decision_note
                  FROM finance.historical_batch b
                 WHERE (:st = 'ALL' OR b.state = :st)
                   AND """ + PG_BATCH + """
                 ORDER BY b.created_at DESC LIMIT 200
                """).param("st", state).param("pgonly", pgOnly()).param("me", AuditContextHolder.current().map(AuditContext::actorId).orElse(null), Types.OTHER).query().listOfRows();
    }

    @PostMapping("/batches/{id}/decide")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_super')")
    @Transactional
    Map<String, Object> decideBatch(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        return jdbc.sql("SELECT x.* FROM finance.historical_batch_decide(:id, :d, :n) x").param("id", id).param("d", body.decision())
                .param("n", body.note(), Types.VARCHAR).query().singleRow();
    }

    /* ── reports and data quality ── */

    /** the historical periods of the graduates in a scope, one row per student, session and semester — the report's rows (up to 20,000) */
    @GetMapping("/report")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> report(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                               @RequestParam(required = false) Integer level, @RequestParam(required = false) String faculty,
                               @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                               @RequestParam(required = false) String status, @RequestParam(required = false) String financial,
                               @RequestParam(required = false) String graduation, @RequestParam(required = false) String source,
                               @RequestParam(required = false) String scope, @RequestParam(required = false) String type,
                               @RequestParam(required = false) String admission) {   // V723: the entry session, as the list takes it
        need("VIEW_HISTORICAL_FEE_REPORT");
        freshen();
        String fin = blank(financial) != null && FINANCIAL.contains(financial.trim()) ? financial.trim() : null;
        // V720: graduates by default, the students studying or everyone on request; undergraduate or postgraduate on request
        List<String> ids = jdbc.sql("""
                SELECT s.id::text FROM people.student s JOIN ref.programme p ON p.code = s.programme_code JOIN finance.historical_summary h ON h.student_id = s.id
                 WHERE true
                """ + SCOPE_WHERE + """
                   AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac) AND (CAST(:dept AS text) IS NULL OR p.dept_code = :dept)
                   AND (CAST(:prog AS text) IS NULL OR p.code = :prog) AND (CAST(:grad AS text) IS NULL OR h.last_session = :grad)
                   AND (CAST(:adm AS text) IS NULL OR s.entry_session = :adm)
                   AND (CAST(:fin AS text) IS NULL OR h.financial_status = :fin) AND h.periods > 0
                 ORDER BY s.surname, s.other_names LIMIT 3000
                """).param("fac", blank(faculty), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(programme), Types.VARCHAR)
                .param("grad", blank(graduation), Types.VARCHAR).param("fin", fin, Types.VARCHAR).param("adm", blank(admission), Types.VARCHAR)
                .param("scope", scopeOf(scope)).param("type", typeFor(type), Types.VARCHAR).query(String.class).list();
        List<Map<String, Object>> rows = ids.isEmpty() ? List.of() : jdbc.sql("""
                SELECT s.surname || ', ' || s.other_names AS student, s.matric_no, s.jamb_reg_no, f.name AS faculty, d.name AS department, p.name AS programme,
                       s.status AS academic_status, CASE WHEN people.is_postgraduate(s.entry_mode, p.category) THEN 'PG' ELSE 'UG' END AS programme_type,   -- V720
                       h.last_session AS graduation_session, x.session, x.semester, x.level, x.assessed, x.paid, x.outstanding, x.credit, x.source, x.source_ref,
                       x.status, a.state AS assessment_state, h.financial_status,
                       (SELECT i.state FROM clearance.process q JOIN clearance.item i ON i.process_id = q.id AND i.unit = 'BURSARY' AND i.superseded_by IS NULL
                         WHERE q.student_id = s.id AND q.workflow = 'FINAL' AND q.cancelled_at IS NULL ORDER BY i.decided_at DESC LIMIT 1) AS bursary_clearance,
                       coalesce(a.decided_at, a.submitted_at, a.created_at) AS dated
                  FROM finance.historical_rows(CAST(:ids AS uuid[])) x
                  JOIN people.student s ON s.id = x.student_id JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  JOIN finance.historical_summary h ON h.student_id = s.id
                  LEFT JOIN finance.historical_assessment a ON a.id = coalesce(x.assessment_id, x.pending_id)
                 WHERE (CAST(:ses AS text) IS NULL OR x.session = :ses) AND (CAST(:sem AS integer) IS NULL OR x.semester = :sem)
                   AND (CAST(:lvl AS integer) IS NULL OR x.level = :lvl) AND (CAST(:st AS text) IS NULL OR x.status = :st)
                   AND (CAST(:src AS text) IS NULL OR x.source = :src)
                 ORDER BY s.surname, s.other_names, x.session, x.semester
                 LIMIT 20000
                """).param("ids", ids.toArray(String[]::new), Types.ARRAY).param("ses", blank(session), Types.VARCHAR).param("sem", semester, Types.INTEGER)
                .param("lvl", level, Types.INTEGER).param("st", blank(status), Types.VARCHAR).param("src", blank(source), Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("students", ids.size());
        out.put("rows", rows);
        out.put("capped", ids.size() >= 3000);
        return out;
    }

    /** the graduates' financial clearance, one row per graduate: the sessions owed, the totals, the clearance */
    @GetMapping("/clearance-report")
    @PreAuthorize(READERS)
    @Transactional
    List<Map<String, Object>> clearanceReport(@RequestParam(required = false) String faculty, @RequestParam(required = false) String programme,
                                              @RequestParam(required = false) String financial, @RequestParam(required = false) String graduation,
                                              @RequestParam(required = false) String scope, @RequestParam(required = false) String type) {
        need("VIEW_HISTORICAL_FEE_REPORT");
        freshen();
        String fin = blank(financial) != null && FINANCIAL.contains(financial.trim()) ? financial.trim() : null;
        return jdbc.sql("""
                SELECT s.surname || ', ' || s.other_names AS student, s.matric_no, s.jamb_reg_no, f.name AS faculty, d.name AS department, p.name AS programme,
                       s.status AS academic_status, CASE WHEN people.is_postgraduate(s.entry_mode, p.category) THEN 'PG' ELSE 'UG' END AS programme_type,   -- V720
                       h.whole_sessions, h.part_sessions,
                       h.last_session AS graduation_session, h.owing, h.assessed, h.paid, h.outstanding, h.credit, h.financial_status, h.last_payment_at,
                       ci.state AS bursary_clearance, helpdesk.person_name(ci.officer_id) AS bursary_officer, ci.decided_at AS bursary_at
                  FROM finance.historical_summary h JOIN people.student s ON s.id = h.student_id JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN LATERAL (SELECT i.state, i.officer_id, i.decided_at FROM clearance.process q
                                       JOIN clearance.item i ON i.process_id = q.id AND i.unit = 'BURSARY' AND i.superseded_by IS NULL
                                      WHERE q.student_id = s.id AND q.workflow = 'FINAL' AND q.cancelled_at IS NULL ORDER BY i.decided_at DESC LIMIT 1) ci ON true
                 WHERE true
                """ + SCOPE_WHERE + """
                   AND (CAST(:fac AS text) IS NULL OR p.faculty_code = :fac) AND (CAST(:prog AS text) IS NULL OR p.code = :prog)
                   AND (CAST(:fin AS text) IS NULL OR h.financial_status = :fin) AND (CAST(:grad AS text) IS NULL OR h.last_session = :grad)
                 ORDER BY h.outstanding DESC, s.surname, s.other_names
                 LIMIT 20000
                """).param("fac", blank(faculty), Types.VARCHAR).param("prog", blank(programme), Types.VARCHAR).param("fin", fin, Types.VARCHAR)
                .param("grad", blank(graduation), Types.VARCHAR).param("scope", scopeOf(scope)).param("type", typeFor(type), Types.VARCHAR).query().listOfRows();
    }

    @GetMapping("/quality")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> quality() {
        need("VIEW_HISTORICAL_FEE_ASSESSMENT");
        freshen();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT q.issue, q.detail, s.id AS student_id, s.surname, s.other_names, s.matric_no, p.name AS programme
                  FROM finance.historical_quality(2000) q JOIN people.student s ON s.id = q.student_id JOIN ref.programme p ON p.code = s.programme_code
                 WHERE (NOT CAST(:pgonly AS boolean) OR people.is_postgraduate(s.entry_mode, p.category))   -- V723
                 ORDER BY q.issue, s.surname
                """).param("pgonly", pgOnly()).query().listOfRows();
        Map<String, Long> by = new LinkedHashMap<>();
        rows.forEach(r -> by.merge(String.valueOf(r.get("issue")), 1L, Long::sum));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("byIssue", by);
        out.put("rows", rows);
        out.put("unmatchedLegacyPayments", jdbc.sql("SELECT count(*) FROM finance.legacy_payment_held h WHERE h.payment_id IS NULL AND h.reconciled_at IS NULL")
                .query(Long.class).optional().orElse(0L));
        return out;
    }
}
