package ng.edu.moaum.portal.student;

import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The student register: who is on it, the whole of one record, the biodata
 * changes the Registry decides, the search that finds one record, and the
 * queries every list in the estate is a list within.
 *
 * <p>Read by every office that has business with a student record; written
 * by the Academic Office and the Registry.
 */
@RestController
@RequestMapping("/api/v1/student")
class StudentController {

    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_dvc','OFFICE_vc','OFFICE_records','OFFICE_dean','OFFICE_hod','OFFICE_exams',"
            + "'OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            // offices that carry the Records & queries menu and so must be able to read it
            + "'OFFICE_bursar','OFFICE_studentaccounts','OFFICE_library','OFFICE_security','OFFICE_housing','OFFICE_hrm',"
            + "'OFFICE_audit','OFFICE_deputyaudit','OFFICE_lecturer',"
            // the College's offices, whose menu offers the search (V285)
            + "'OFFICE_provost','OFFICE_collegesecretary','OFFICE_financecontroller','OFFICE_mbbscoordinator',"
            // V640: the Database Operations office reads the record; it writes none of it
            + "'OFFICE_dbops')";
    private static final String WRITERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";
    /** V360: the offices that read a student's school fees here — the Bursary, the Registry, the academic heads and their
     *  scopes, audit and the platform; the other readers of the record (a lecturer, the library, security, housing) do not */
    static final java.util.Set<String> FEE_READERS = java.util.Set.of("bursar", "dbops", "studentaccounts", "financecontroller", "registrar", "dregistrar", "academic",
            "records", "vc", "dvc", "dean", "hod", "facultyofficer", "provost", "audit", "ict", "admin", "super");

    private static boolean readsFees() {
        return ng.edu.moaum.portal.shared.AuditContextHolder.current().map(c -> FEE_READERS.contains(c.actorOffice())).orElse(false);
    }

    private final StudentService students;
    private final ChangeService changes;
    private final SearchService search;
    private final RecordsService records;
    private final ng.edu.moaum.portal.studentportal.StudentPortalService portal;
    private final org.springframework.jdbc.core.simple.JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;
    private final ClassificationService classification;
    private final ng.edu.moaum.portal.shared.FigureCache figures;
    private final StudentReach reach;

    StudentController(StudentService students, ChangeService changes, SearchService search, RecordsService records,
                      ng.edu.moaum.portal.studentportal.StudentPortalService portal, org.springframework.jdbc.core.simple.JdbcClient jdbc,
                      ng.edu.moaum.portal.shared.OfficeScope scope, ClassificationService classification,
                      ng.edu.moaum.portal.shared.FigureCache figures, StudentReach reach) {
        this.students = students;
        this.changes = changes;
        this.search = search;
        this.records = records;
        this.portal = portal;
        this.jdbc = jdbc;
        this.scope = scope;
        this.classification = classification;
        this.figures = figures;
        this.reach = reach;
    }

    /** Oct 2026: the migrated students' figures read every clearance decision on the register (2.85 million, about forty
     *  seconds): kept a few minutes for every office that asks, worked out ahead when the service starts. V577: read in one pass
     *  (clearance.migrated_summary), and worked out a few minutes after the start (moaum.figures.migrated-warm-delay-seconds,
     *  300 by default) rather than while the service is still answering its first health checks and requests */
    @org.springframework.beans.factory.annotation.Value("${moaum.figures.migrated-warm-delay-seconds:300}")
    long migratedWarmDelay;

    @org.springframework.context.event.EventListener(org.springframework.boot.context.event.ApplicationReadyEvent.class)
    void warmMigrated() {
        java.util.concurrent.CompletableFuture.delayedExecutor(Math.max(0, migratedWarmDelay), java.util.concurrent.TimeUnit.SECONDS)
                .execute(() -> figures.warm(java.util.List.of("migrated", 100, 400), () -> migratedNow(100, 400)));
    }

    private java.util.Map<String, Object> migratedNow(int from, int to) {
        return jdbc.sql("SELECT * FROM clearance.migrated_summary(:f, :t)").param("f", from).param("t", to).query().singleRow();
    }

    /** The register in a scope, and how many the University has on it altogether. */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    StudentRow.Register register(@RequestParam(required = false) String fac,
                                 @RequestParam(required = false) String dept,
                                 @RequestParam(required = false) String prog,
                                 @RequestParam(required = false) Integer level,
                                 @RequestParam(required = false) String session,
                                 @RequestParam(required = false) String q) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);   // the office's bound, whatever the parameters say
        return students.register(Scope.of(b.fac(), b.dept(), b.prog(), level, null, session, null), q);
    }

    /** The students migrated from the old portal at these levels: how many, how many stand cleared at every unit, how many do not (V233). */
    @GetMapping("/students/migrated")
    @PreAuthorize(READERS)
    java.util.Map<String, Object> migrated(@RequestParam(defaultValue = "100") int from, @RequestParam(defaultValue = "400") int to,
                                           @RequestParam(defaultValue = "false") boolean refresh) {
        ng.edu.moaum.portal.shared.FigureCache.Answer<java.util.Map<String, Object>> a =
                figures.get(java.util.List.of("migrated", from, to), refresh, () -> migratedNow(from, to));
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>(a.value());
        out.put("computedAt", a.at().toString());   // the figures as of then
        out.put("refreshing", a.refreshing());
        return out;
    }

    /** Clear the migrated students at these levels who still lack a unit's word — the old portal's clearance, carried over (V231/V233). */
    @PostMapping("/students/migrated/clear")
    @PreAuthorize("hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')")
    @org.springframework.transaction.annotation.Transactional
    java.util.Map<String, Object> clearMigrated(@RequestParam(defaultValue = "100") int from, @RequestParam(defaultValue = "400") int to) {
        java.util.Map<String, Object> done = jdbc.sql("SELECT * FROM clearance.clear_migrated(:f, :t)").param("f", from).param("t", to).query().singleRow();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>(done);
        java.util.Map<String, Object> now = migratedNow(from, to);   // read in this transaction: the clearing just done
        out.putAll(now);
        out.put("computedAt", java.time.Instant.now().toString());
        // the kept figure forgotten now, and replaced by this one once the clearing is committed
        java.util.List<Object> key = java.util.List.of("migrated", from, to);
        figures.forget(key);
        org.springframework.transaction.support.TransactionSynchronizationManager.registerSynchronization(
                new org.springframework.transaction.support.TransactionSynchronization() {
                    @Override
                    public void afterCommit() {
                        figures.put(key, now);
                    }
                });
        return out;
    }

    /** Voluntary withdrawals (V247): the students four consecutive closed semesters without an approved registration have made due,
     *  named by the record, and how many records stand closed so far. */
    @GetMapping("/students/voluntary-withdrawals")
    @PreAuthorize("hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')")
    java.util.Map<String, Object> voluntaryWithdrawals() {
        java.util.List<java.util.Map<String, Object>> due = jdbc.sql("SELECT * FROM registration.voluntary_withdrawals_due()").query().listOfRows();
        long closed = jdbc.sql("SELECT count(*) FROM people.student WHERE status = 'VOLUNTARY_WITHDRAWAL'").query(Long.class).single();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("due", due);
        out.put("closed", closed);
        return out;
    }

    public record CloseVoluntaryIn(java.util.List<UUID> studentIds, String instrument) {
    }

    /** The Registry's act: the students due (the ones named, or all) become VOLUNTARY_WITHDRAWAL on the regulation as the instrument. */
    @PostMapping("/students/voluntary-withdrawals/close")
    @PreAuthorize("hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')")
    @org.springframework.transaction.annotation.Transactional
    java.util.Map<String, Object> closeVoluntary(@org.springframework.web.bind.annotation.RequestBody(required = false) CloseVoluntaryIn in) {
        String instrument = in != null && in.instrument() != null && !in.instrument().isBlank() ? in.instrument().trim()
                : "University regulation: four consecutive semesters without course registration";
        int closed = 0;
        if (in != null && in.studentIds() != null && !in.studentIds().isEmpty()) {
            for (UUID id : in.studentIds()) {
                closed += jdbc.sql("SELECT registration.effect_voluntary_withdrawals(:i, :s)").param("i", instrument).param("s", id).query(Integer.class).single();
            }
        } else {
            closed = jdbc.sql("SELECT registration.effect_voluntary_withdrawals(:i, NULL)").param("i", instrument).query(Integer.class).single();
        }
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>(voluntaryWithdrawals());
        out.put("closed", closed);
        return out;
    }

    /** V361: one student's record is read within the office's bound — the rule is StudentReach's (Oct 2026: shared with the full record) */
    private void reachStudent(UUID id) {
        reach.check(id);
    }

    /** One record entire. The session decides which registrations it shows. */
    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    StudentRecord record(@PathVariable UUID id, @RequestParam(required = false) String session) {
        reachStudent(id);
        return students.record(id, blankToNull(session));
    }

    /** V469: the record's classification — programme type, admission route, study mode, centre — and its history, in the record's own scope */
    @GetMapping("/students/{id}/classification")
    @PreAuthorize(READERS)
    java.util.Map<String, Object> classification(@PathVariable UUID id) {
        reachStudent(id);
        return classification.of(id);
    }

    /** The student's own portal view of themselves — fees, GPA and CGPA, standing, carryovers, this session's
     *  registration, graduation — read by an office for the record pop-up. The same figures the student sees. */
    @GetMapping("/students/{id}/portal")
    @PreAuthorize(READERS)
    java.util.Map<String, Object> portal(@PathVariable UUID id) {
        reachStudent(id);
        java.util.Map<String, Object> out = portal.me(id);
        // V360: the school fees go only to the offices that read them
        if (!readsFees()) {
            out = new java.util.LinkedHashMap<>(out);
            out.remove("fees");
        }
        return out;
    }

    /** The student's passport photograph, from whichever store holds it (document, JAMB, attachment). */
    @GetMapping("/students/{id}/passport")
    @PreAuthorize(READERS)
    org.springframework.http.ResponseEntity<byte[]> passport(@PathVariable UUID id) {
        reachStudent(id);
        return portal.passportImage(id)
                .map(img -> org.springframework.http.ResponseEntity.ok()
                        .contentType(org.springframework.http.MediaType.IMAGE_JPEG)
                        .cacheControl(org.springframework.http.CacheControl.maxAge(java.time.Duration.ofMinutes(10)).cachePrivate())
                        .body(img))
                .orElseGet(() -> org.springframework.http.ResponseEntity.notFound().build());
    }

    @PutMapping("/students/{id}/biodata/{field}")
    @PreAuthorize(WRITERS)
    StudentService.BiodataWritten biodata(@PathVariable UUID id, @PathVariable String field,
                                          @Valid @RequestBody StudentService.BiodataIn body) {
        return students.writeBiodata(id, field, body);
    }

    @PostMapping("/students/{id}/status")
    @PreAuthorize(WRITERS)
    StudentRecord status(@PathVariable UUID id, @Valid @RequestBody StudentService.StatusIn body,
                         @RequestParam(required = false) String session) {
        return students.changeStatus(id, body, blankToNull(session));
    }

    @PutMapping("/students/{id}/level")
    @PreAuthorize(WRITERS)
    StudentRecord level(@PathVariable UUID id, @Valid @RequestBody StudentService.LevelIn body,
                        @RequestParam(required = false) String session) {
        return students.correctLevel(id, body, blankToNull(session));
    }

    @GetMapping("/biodata-changes")
    @PreAuthorize(READERS)
    BiodataChangeRow.Queue queue(@RequestParam(required = false) String state) {
        return changes.queue(state);
    }

    @PostMapping("/biodata-changes/{id}/approve")
    @PreAuthorize(WRITERS)
    BiodataChangeRow.Decided approve(@PathVariable UUID id, @Valid @RequestBody ChangeService.DecisionIn body) {
        return changes.approve(id, body);
    }

    @PostMapping("/biodata-changes/{id}/refuse")
    @PreAuthorize(WRITERS)
    BiodataChangeRow.Decided refuse(@PathVariable UUID id, @Valid @RequestBody ChangeService.DecisionIn body) {
        return changes.refuse(id, body);
    }

    @PostMapping("/biodata-changes/{id}/ask-evidence")
    @PreAuthorize(WRITERS)
    BiodataChangeRow.Decided askForEvidence(@PathVariable UUID id) {
        return changes.askForEvidence(id);
    }

    /** Every search with a term is written to the audit trail before it answers. */
    @GetMapping("/search")
    @PreAuthorize(READERS)
    SearchHit.Result find(@RequestParam(required = false) String q,
                          @RequestParam(required = false) String kind) {
        return search.find(q, kind);
    }

    /** V429: the students who may be one person on the register twice (the same JAMB number, or every name, the programme and the
     *  entry session), with what each record carries — for the Registry to reconcile. Read only: nothing is merged or deleted here. */
    @GetMapping("/duplicates")
    @PreAuthorize("hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_ict','OFFICE_super')")
    @org.springframework.transaction.annotation.Transactional(readOnly = true)
    java.util.List<java.util.Map<String, Object>> duplicates() {
        return jdbc.sql("SELECT * FROM people.duplicate_students()").query().listOfRows();
    }

    public record ResolveDuplicateIn(@jakarta.validation.constraints.NotNull UUID keep, @jakarta.validation.constraints.NotNull UUID end,
                                     @jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 500) String reason) {
    }

    /** V431: the Registry keeps one record of a duplicate pair and ends the other — withdrawn, pointing at the kept record, nothing
     *  deleted; refused when the record to end carries a matriculation number, a registration, a fee reference or a mark. */
    @PostMapping("/duplicates/resolve")
    @PreAuthorize("hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_super')")
    @org.springframework.transaction.annotation.Transactional
    java.util.Map<String, Object> resolveDuplicate(@Valid @RequestBody ResolveDuplicateIn in) {
        return jdbc.sql("""
                SELECT r ->> 'keptNumber' AS kept_number, r ->> 'endedNumber' AS ended_number, (r ->> 'candidateMoved')::boolean AS candidate_moved
                  FROM people.resolve_duplicate(:k, :e, :why) r
                """).param("k", in.keep()).param("e", in.end()).param("why", in.reason().trim()).query().singleRow();
    }

    @GetMapping("/records/{view}")
    @PreAuthorize(READERS)
    RecordsResult records(@PathVariable String view,
                          @RequestParam(required = false) String fac,
                          @RequestParam(required = false) String dept,
                          @RequestParam(required = false) String prog,
                          @RequestParam(required = false) Integer level,
                          @RequestParam(required = false) String course,
                          @RequestParam(required = false) String session,
                          @RequestParam(required = false) Integer sem) {
        // V360: held to the office's own bound, whatever the parameters say — as the register is (a Head of Department reads
        // their own department, a Dean their faculty); and the school fees only by the offices that read them
        if ("fees".equals(view) && !readsFees()) {
            throw new org.springframework.security.access.AccessDeniedException("School fees in Records & queries are read by the Bursary, the Registry and the academic heads, not by this office.");
        }
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);
        return records.view(view, Scope.of(b.fac(), b.dept(), b.prog(), level, course, session, sem));
    }

    /** The intake run: the session's admitted candidates, brought onto the register. */
    @PostMapping("/intake/{session}/{year}")
    @PreAuthorize(WRITERS)
    StudentService.Intake intake(@PathVariable String session, @PathVariable String year) {
        return students.intake(session + "/" + year);
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
