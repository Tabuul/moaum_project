package ng.edu.moaum.portal.graduation;

import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import tools.jackson.databind.ObjectMapper;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.JobLock;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
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
 * V638: students outside the maximum academic period graduated by status reconciliation, under /api/v1/graduation/reconciliation.
 * The cohort engine (people.academic_position) already counts the sessions since a student's expected completion against the
 * configured spillover limit; people.graduation_candidates lists those beyond it who are still kept in study, with the timeline and a
 * confidence for this rule (HIGH, MEDIUM, LOW: requires review). The Academic Office (or the Registry) previews the students chosen —
 * nothing written — opens a GRAD-RECON/YYYY/NNNNNN batch, and executes it a step at a time: each student revalidated, the status
 * changed to GRADUATED with its history, the calculation kept, the graduation session the last permitted one, final clearance
 * started, the student told; never twice. Where the Directorate of ICT or the Registrar has switched automatic reconciliation on,
 * the portal does the same each night for HIGH-confidence records alone, on the existing scheduler and job lock. Readers are held
 * to their office's scope; every act and every refusal is the database's.
 */
@RestController
@RequestMapping("/api/v1/graduation/reconciliation")
public class GraduationReconciliationController {

    private static final Logger LOG = LoggerFactory.getLogger(GraduationReconciliationController.class);
    private static final UUID NOBODY = new UUID(0, 0);
    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            // V640: the Database Operations office reads; reconciling stays with the Academic Office and the Registry
            + "'OFFICE_dbops')";
    /** who reconciles: the Academic Office and the Registry (the database holds the same rule) */
    private static final String ACTORS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";
    /** who switches the nightly run on or off: the Directorate of ICT and the Registrar */
    private static final String SETTERS = "hasAnyAuthority('OFFICE_ict','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final Set<String> CONFIDENCES = Set.of("HIGH", "MEDIUM", "LOW");
    private static final Set<String> REPORT_BY = Set.of("faculty", "department", "programme", "entry", "session", "spillover", "batch");
    /** a step of 100: each student is revalidated, changed, recomputed, cleared and told — well inside the 30-second limit in front of the API */
    private static final int STEP = 100;
    private static final int MAX_CHOSEN = 5000;
    private static final int ALL = 10000;
    private static final String CANDIDATES = "SELECT * FROM people.graduation_candidates(:f, :d, :p, :q, :c, nullif(CAST(:ids AS uuid[]), '{}'), :n)";

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final JobLock lock;
    private final TransactionTemplate tx;
    private final ObjectMapper json = new ObjectMapper();

    GraduationReconciliationController(JdbcClient jdbc, OfficeScope scope, JobLock lock, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.lock = lock;
        this.tx = new TransactionTemplate(transactions);
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parse(String text) {
        return text == null ? new LinkedHashMap<>() : json.readValue(text, LinkedHashMap.class);
    }

    private static String ref(String year, String seq) {
        if (year == null || !year.matches("[0-9]{4}") || seq == null || !seq.matches("[0-9]{6}")) {
            throw new NotFound("graduation-status reconciliation batch", year + "/" + seq);
        }
        return "GRAD-RECON/" + year + "/" + seq;
    }

    private static String[] idsOf(List<UUID> ids) {
        return ids == null ? new String[0] : ids.stream().map(UUID::toString).distinct().toArray(String[]::new);
    }

    private List<Map<String, Object>> candidates(OfficeScope.Bound b, String q, String confidence, List<UUID> ids, int limit) {
        return jdbc.sql(CANDIDATES)
                .param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR)
                .param("q", blank(q), Types.VARCHAR).param("c", confidence, Types.VARCHAR).param("ids", idsOf(ids), Types.ARRAY).param("n", limit)
                .query().listOfRows();
    }

    private static String confidenceOf(String v) {
        String c = blank(v) == null ? null : v.trim().toUpperCase();
        if (c != null && !CONFIDENCES.contains(c)) {
            throw new DomainRuleViolation("GRADRECON_FILTER", "Unknown confidence " + c + ".", new DomainRuleViolation.Remedy("Choose high, medium or low.", "You"));
        }
        return c;
    }

    /** the cards: active, current, SP1, SP2, outside the maximum period (eligible by confidence, requiring review), graduation
     *  candidates, graduated, graduated by reconciliation, data incomplete — counted by the engines, never by hand */
    @GetMapping("/figures")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> figures(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog) {
        OfficeScope.Bound b = scope.bound(fac, dept, prog);
        return parse(jdbc.sql("SELECT people.graduation_reconciliation_figures(:f, :d, :p)::text")
                .param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR).query(String.class).single());
    }

    /** the students outside the maximum academic period, names A to Z, paged; the S/N is the screen's, never an id */
    @GetMapping("/candidates")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                             @RequestParam(required = false) String q, @RequestParam(required = false) String confidence,
                             @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = scope.bound(fac, dept, prog);
        List<Map<String, Object>> all = candidates(b, q, confidenceOf(confidence), null, ALL);
        int sz = Math.max(1, Math.min(size, ALL));
        int pg = Math.max(1, page);
        int from = Math.min(all.size(), (pg - 1) * sz);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", all.subList(from, Math.min(all.size(), from + sz)));
        out.put("total", all.size());
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    /** one student's review: the engine's reading, the timeline, the reconciliation, the status history — within the reader's scope */
    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable UUID id) {
        OfficeScope.Bound b = scope.bound(null, null, null);
        Map<String, Object> who = inScope(id, b);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", who);
        out.put("candidate", candidates(b, null, null, List.of(id), 1).stream().findFirst().orElse(null));
        out.put("position", jdbc.sql("SELECT * FROM people.academic_position WHERE student_id = :s").param("s", id).query().listOfRows().stream().findFirst().orElse(null));
        out.put("reconciliations", jdbc.sql("""
                SELECT g.id, g.batch_ref, b.mode, g.previous_status, g.new_status, g.matric_no, g.entry_session, g.effective_cohort, g.cohort_source, g.programme_code,
                       g.duration_years, g.final_level, g.current_level, g.deferred_sessions, g.expected_completion, g.max_spillover_years, g.maximum_session,
                       g.current_session, g.spillover_years, g.spillover_state, g.confidence, g.confidence_reasons, g.graduation_session, g.graduation_date,
                       g.date_confirmed, helpdesk.person_name(g.date_confirmed_by) AS date_confirmed_by, g.date_confirmed_at, g.date_note, g.clearance, g.reason,
                       coalesce(helpdesk.person_name(g.reconciled_by), CASE WHEN b.mode = 'AUTOMATIC' THEN 'The portal (automatic reconciliation)' END) AS reconciled_by,
                       g.actor_office, g.reconciled_at, g.corrected_at, helpdesk.person_name(g.corrected_by) AS corrected_by, g.correction_reason
                  FROM people.graduation_reconciliation g JOIN people.graduation_reconciliation_batch b ON b.batch_ref = g.batch_ref
                 WHERE g.student_id = :s ORDER BY g.reconciled_at DESC
                """).param("s", id).query().listOfRows());
        out.put("statusHistory", jdbc.sql("SELECT from_status, to_status, instrument, effective_on, reason FROM people.status_change WHERE student_id = :s ORDER BY effective_on, id")
                .param("s", id).query().listOfRows());
        out.put("registrations", jdbc.sql("""
                SELECT session, semester, level, status FROM registration.course_registration
                 WHERE student_id = :s AND status IN ('SUBMITTED', 'APPROVED', 'LOCKED') ORDER BY session, semester
                """).param("s", id).query().listOfRows());
        out.put("deferments", jdbc.sql("SELECT reference, kind, session, semester, state FROM people.deferment WHERE student_id = :s ORDER BY session, created_at")
                .param("s", id).query().listOfRows());
        out.put("programmeHistory", jdbc.sql("SELECT at, session, kind, programme_code, programme, level, from_programme, reference FROM people.programme_history(:s)")
                .param("s", id).query().listOfRows());
        return out;
    }

    /** the student, when the reader's scope holds them (a dean reads their faculty's students, never another's) */
    private Map<String, Object> inScope(UUID id, OfficeScope.Bound b) {
        return jdbc.sql("""
                SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.jamb_reg_no, s.status, s.programme_code, p.name AS programme,
                       d.name AS department, f.name AS faculty, s.entry_session, s.entry_level, s.current_level
                  FROM people.student s
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE s.id = :s AND (:f::text IS NULL OR p.faculty_code = :f) AND (:d::text IS NULL OR p.dept_code = :d) AND (:p::text IS NULL OR p.code = :p)
                """).param("s", id).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", id.toString()));
    }

    public record Choice(List<UUID> studentIds, Boolean includeMedium, @Size(max = 80) String q, @Size(max = 20) String fac, @Size(max = 20) String dept,
                         @Size(max = 20) String prog) {
    }

    private static void sized(List<UUID> ids) {
        if (ids != null && ids.size() > MAX_CHOSEN) {
            throw new DomainRuleViolation("GRADRECON_SIZE", "Choose at most 5,000 students at a time.",
                    new DomainRuleViolation.Remedy("Narrow the list by faculty, department or programme.", "You"));
        }
    }

    /** nothing written: how many the choice names, how many are eligible, how many require review — and each one with its verdict */
    @PostMapping("/preview")
    @PreAuthorize(ACTORS)
    @Transactional(readOnly = true)
    Map<String, Object> preview(@Valid @RequestBody Choice body) {
        sized(body.studentIds());
        OfficeScope.Bound b = scope.bound(body.fac(), body.dept(), body.prog());
        boolean medium = Boolean.TRUE.equals(body.includeMedium());
        List<Map<String, Object>> rows = new ArrayList<>();
        int high = 0;
        int med = 0;
        int low = 0;
        for (Map<String, Object> r : candidates(b, body.q(), null, body.studentIds(), ALL)) {
            String c = String.valueOf(r.get("confidence"));
            if ("HIGH".equals(c)) high++;
            else if ("MEDIUM".equals(c)) med++;
            else low++;
            Map<String, Object> row = new LinkedHashMap<>(r);
            row.put("verdict", "HIGH".equals(c) || ("MEDIUM".equals(c) && medium) ? "ELIGIBLE" : "REVIEW");
            rows.add(row);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("identified", rows.size());
        out.put("eligible", high + (medium ? med : 0));
        out.put("review", low + (medium ? 0 : med));
        out.put("high", high);
        out.put("medium", med);
        out.put("low", low);
        out.put("includeMedium", medium);
        out.put("rows", rows);
        return out;
    }

    public record Open(@NotBlank @Size(max = 300) String description, List<UUID> studentIds, Boolean includeMedium, @Size(max = 80) String q,
                       @Size(max = 20) String fac, @Size(max = 20) String dept, @Size(max = 20) String prog) {
    }

    /** the batch opened on the confirmation, with its rows; nothing on any student changes until it is executed */
    @PostMapping("/batches")
    @PreAuthorize(ACTORS)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody Open body) {
        sized(body.studentIds());
        OfficeScope.Bound b = scope.bound(body.fac(), body.dept(), body.prog());
        String ref = jdbc.sql("SELECT people.graduation_reconciliation_open(:t, 'MANUAL', :m, nullif(CAST(:ids AS uuid[]), '{}'), :f, :d, :p, :q)")
                .param("t", body.description().trim()).param("m", Boolean.TRUE.equals(body.includeMedium())).param("ids", idsOf(body.studentIds()), Types.ARRAY)
                .param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR).param("q", blank(body.q()), Types.VARCHAR)
                .query(String.class).single();
        return batchRow(ref);
    }

    public record Run(@Size(max = 2000) String reason) {
    }

    /** one step: up to 100 eligible students reconciled, each on its own; called again until done */
    @PostMapping("/batches/{year}/{seq}/run")
    @PreAuthorize(ACTORS)
    @Transactional
    Map<String, Object> run(@PathVariable String year, @PathVariable String seq, @Valid @RequestBody(required = false) Run body) {
        String ref = ref(year, seq);
        Map<String, Object> out = parse(jdbc.sql("SELECT people.graduation_reconciliation_run(:b, :r, :n)::text")
                .param("b", ref).param("r", body == null ? null : blank(body.reason()), Types.VARCHAR).param("n", STEP).query(String.class).single());
        out.put("batch", batchRow(ref));
        return out;
    }

    @PostMapping("/batches/{year}/{seq}/close")
    @PreAuthorize(ACTORS)
    @Transactional
    Map<String, Object> close(@PathVariable String year, @PathVariable String seq) {
        String ref = ref(year, seq);
        jdbc.sql("SELECT people.graduation_reconciliation_close(:b)").param("b", ref).query().singleRow();
        return batchRow(ref);
    }

    private static final String BATCH = """
            SELECT b.batch_ref, b.description, b.mode, b.effective_session, b.scope, b.min_confidence, b.selected, b.eligible, b.review, b.graduated,
                   b.skipped, b.refused, b.corrected, coalesce(helpdesk.person_name(b.created_by), CASE WHEN b.mode = 'AUTOMATIC' THEN 'The portal' END) AS created_by,
                   b.actor_office, b.created_at, b.executed_at, b.closed_at
              FROM people.graduation_reconciliation_batch b
            """;

    private Map<String, Object> batchRow(String ref) {
        return jdbc.sql(BATCH + " WHERE b.batch_ref = :b").param("b", ref).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("graduation-status reconciliation batch", ref));
    }

    /** every batch, newest first, with the students of it within the reader's scope */
    @GetMapping("/batches")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> batches(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog) {
        OfficeScope.Bound b = scope.bound(fac, dept, prog);
        return jdbc.sql("""
                SELECT x.*, s.in_scope, s.graduated_in_scope
                  FROM (%s) x
                  JOIN LATERAL (SELECT count(r.student_id) AS in_scope, count(r.student_id) FILTER (WHERE r.outcome = 'GRADUATED') AS graduated_in_scope
                                  FROM people.graduation_reconciliation_row r JOIN people.student st ON st.id = r.student_id
                                  LEFT JOIN ref.programme p ON p.code = st.programme_code
                                 WHERE r.batch_ref = x.batch_ref AND (:f::text IS NULL OR p.faculty_code = :f) AND (:d::text IS NULL OR p.dept_code = :d)
                                   AND (:p::text IS NULL OR p.code = :p)) s ON true
                 WHERE (:f::text IS NULL AND :d::text IS NULL AND :p::text IS NULL) OR s.in_scope > 0
                 ORDER BY x.created_at DESC
                 LIMIT 300
                """.formatted(BATCH)).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR).query().listOfRows();
    }

    /** a batch with its students (those within the reader's scope), names A to Z */
    @GetMapping("/batches/{year}/{seq}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> batch(@PathVariable String year, @PathVariable String seq) {
        String ref = ref(year, seq);
        OfficeScope.Bound b = scope.bound(null, null, null);
        Map<String, Object> out = new LinkedHashMap<>(batchRow(ref));
        out.put("rows", jdbc.sql("""
                SELECT r.student_id, s.surname, s.other_names, s.matric_no, s.status, s.programme_code, p.name AS programme, r.confidence, r.verdict, r.reasons,
                       r.outcome, r.note, r.decided_at, g.graduation_session, g.graduation_date, g.date_confirmed, g.corrected_at
                  FROM people.graduation_reconciliation_row r
                  JOIN people.student s ON s.id = r.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN people.graduation_reconciliation g ON g.batch_ref = r.batch_ref AND g.student_id = r.student_id
                 WHERE r.batch_ref = :b AND (:f::text IS NULL OR p.faculty_code = :f) AND (:d::text IS NULL OR p.dept_code = :d) AND (:p::text IS NULL OR p.code = :p)
                 ORDER BY s.surname, s.other_names
                """).param("b", ref).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR).query().listOfRows());
        return out;
    }

    public record GraduationDate(@NotNull LocalDate date, @Size(max = 9) String session, @Size(max = 300) String note) {
    }

    /** the official graduation date (and session) confirmed by the Academic Office — never the day the status was reconciled */
    @PostMapping("/students/{id}/graduation-date")
    @PreAuthorize(ACTORS)
    @Transactional
    Map<String, Object> confirmDate(@PathVariable UUID id, @Valid @RequestBody GraduationDate body) {
        inScope(id, scope.bound(null, null, null));
        return parse(jdbc.sql("SELECT people.confirm_graduation_date(:s, :d, :n, :t)::text")
                .param("s", id).param("d", body.date()).param("n", blank(body.session()), Types.VARCHAR).param("t", blank(body.note()), Types.VARCHAR)
                .query(String.class).single());
    }

    /** the reconciled graduates by faculty, department, programme, admission session, graduation session, spillover state or batch */
    @GetMapping("/report")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> report(@RequestParam(defaultValue = "faculty") String by, @RequestParam(required = false) String fac,
                               @RequestParam(required = false) String dept, @RequestParam(required = false) String prog) {
        if (!REPORT_BY.contains(by)) {
            throw new DomainRuleViolation("GRADRECON_REPORT", "Unknown grouping " + by + ".", new DomainRuleViolation.Remedy("Choose one of the groupings offered.", "You"));
        }
        OfficeScope.Bound b = scope.bound(fac, dept, prog);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("by", by);
        out.put("rows", jdbc.sql("SELECT * FROM people.graduation_reconciliation_report(:by, :f, :d, :p)").param("by", by)
                .param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR).query().listOfRows());
        return out;
    }

    @GetMapping("/setting")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> setting() {
        return jdbc.sql("""
                SELECT ps.auto_graduation, ps.max_spillover_years, ps.updated_at, helpdesk.person_name(ps.updated_by) AS updated_by,
                       (SELECT max(b.executed_at) FROM people.graduation_reconciliation_batch b WHERE b.mode = 'AUTOMATIC') AS last_automatic_run
                  FROM policy.progression_setting ps WHERE ps.row_no
                """).query().singleRow();
    }

    public record Setting(@NotNull Boolean autoGraduation) {
    }

    /** the Directorate of ICT or the Registrar switches the nightly reconciliation on or off (the database checks the office too) */
    @PostMapping("/setting")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> set(@Valid @RequestBody Setting body) {
        jdbc.sql("SELECT policy.set_auto_graduation(:on)").param("on", body.autoGraduation()).query().singleRow();
        return setting();
    }

    /* ── the nightly run, on the existing scheduler and job lock: nothing unless switched on, HIGH confidence alone, never twice ── */

    @Scheduled(cron = "${moaum.graduation.reconciliation-cron:0 50 2 * * *}", zone = "Africa/Lagos")
    public void nightly() {
        lock.runExclusively("graduation-reconciliation", this::nightlyNow);
    }

    /** opens an AUTOMATIC batch when automatic reconciliation is on and a HIGH-confidence student is outside the maximum, and runs it
     *  to the end; a student already graduated is never a candidate, so a second run the same night finds nobody */
    public String nightlyNow() {
        try {
            return AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "students outside the maximum academic period graduated by the nightly reconciliation", null, null), () -> {
                Boolean on = tx.execute(st -> jdbc.sql("SELECT auto_graduation FROM policy.progression_setting WHERE row_no").query(Boolean.class).single());
                if (!Boolean.TRUE.equals(on)) return null;
                Integer high = tx.execute(st -> jdbc.sql("SELECT count(*)::int FROM people.graduation_candidates(NULL, NULL, NULL, NULL, 'HIGH', NULL, 10000)").query(Integer.class).single());
                if (high == null || high == 0) return null;
                String ref = tx.execute(st -> jdbc.sql("SELECT people.graduation_reconciliation_open(:t, 'AUTOMATIC', false, NULL, NULL, NULL, NULL, NULL)")
                        .param("t", "Nightly reconciliation: students outside the maximum academic period, high confidence").query(String.class).single());
                int graduated = 0;
                for (int i = 0; i < 100; i++) {
                    Map<String, Object> step = parse(tx.execute(st -> jdbc.sql("SELECT people.graduation_reconciliation_run(:b, NULL, :n)::text").param("b", ref).param("n", STEP)
                            .query(String.class).single()));
                    graduated += ((Number) step.getOrDefault("graduated", 0)).intValue();
                    if (Boolean.TRUE.equals(step.get("done"))) break;
                }
                tx.executeWithoutResult(st -> jdbc.sql("SELECT people.graduation_reconciliation_close(:b)").param("b", ref).query().singleRow());
                LOG.info("graduation reconciliation {}: {} graduated", ref, graduated);
                return ref;
            });
        } catch (RuntimeException e) {
            LOG.warn("graduation reconciliation did not run: {}", e.getMessage());
            return null;
        }
    }
}
