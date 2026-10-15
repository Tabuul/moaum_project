package ng.edu.moaum.portal.results;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.NotBlank;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/results")
class ResultsController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_lecturer',"
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_gst','OFFICE_eps')";
    private static final String DESKS =
            "hasAnyAuthority('OFFICE_lecturer','OFFICE_exams','OFFICE_hod','OFFICE_facultyexams','OFFICE_facultyofficer',"
            + "'OFFICE_dean','OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_gst','OFFICE_eps')";
    /** V314: the GST and EPS offices enter and submit the sheets of their own courses */
    private static final String ENTRY = "hasAnyAuthority('OFFICE_lecturer','OFFICE_exams','OFFICE_academic','OFFICE_gst','OFFICE_eps')";
    /** examination sessions are set up and opened by the Director of ICT alone, from Portal Management (moved there from
     *  the Academic Office and Exams & Records); every office that reads results still reads them and their monitor */
    private static final String EXAM_SESSIONS = "hasAuthority('OFFICE_ict')";

    private final ResultsService service;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;
    private final org.springframework.jdbc.core.simple.JdbcClient jdbc;

    ResultsController(ResultsService service, ng.edu.moaum.portal.shared.OfficeScope scope, org.springframework.jdbc.core.simple.JdbcClient jdbc) {
        this.service = service;
        this.scope = scope;
        this.jdbc = jdbc;
    }

    private static final String MIGRATE =
            "hasAnyAuthority('OFFICE_ict','OFFICE_exams','OFFICE_facultyexams','OFFICE_hod','OFFICE_dean','OFFICE_records',"
            + "'OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    /** the students exported from the old portal — the first migration step, so results and registration can match */
    @PostMapping("/legacy/students")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importStudents(@Valid @RequestBody ResultsService.StudentsIn body) {
        return service.importStudents(body.rows());
    }

    /** V459: what each register upload would change before it changes anyone — shown to the office to confirm */
    @PostMapping("/legacy/students/preview")
    @PreAuthorize(MIGRATE)
    Map<String, Object> previewStudents(@Valid @RequestBody ResultsService.StudentsIn body) {
        return service.previewRegister("students", body.rows());
    }

    @PostMapping("/legacy/biodata/preview")
    @PreAuthorize(MIGRATE)
    Map<String, Object> previewBiography(@Valid @RequestBody ResultsService.StudentsIn body) {
        return service.previewRegister("biodata", body.rows());
    }

    @PostMapping("/legacy/pg-students/preview")
    @PreAuthorize(MIGRATE)
    Map<String, Object> previewPostgraduate(@Valid @RequestBody ResultsService.StudentsIn body) {
        return service.previewRegister("postgraduate", body.rows());
    }

    /** the full student biography exported from the old portal — core, contact, biography and a sign-in account */
    @PostMapping("/legacy/biodata")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importBiography(@Valid @RequestBody ResultsService.StudentsIn body) {
        return service.importBiography(body.rows());
    }

    /** the postgraduate students exported from the old portal — kept at their postgraduate level (700/800/900)
     *  and school (S002), the programme created in the shared table when it is not yet there */
    @PostMapping("/legacy/pg-students")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importPostgraduate(@Valid @RequestBody ResultsService.StudentsIn body) {
        return service.importPostgraduate(body.rows());
    }

    /** post every past result held for a student who was not on the register when the results were
     *  uploaded, but has since been loaded — run after a student/biography upload (V204) */
    @PostMapping("/legacy/reconcile-results")
    @PreAuthorize(MIGRATE)
    Map<String, Object> reconcileResults() {
        return service.reconcileHolding();
    }

    /** the course registration of a past semester, from the old portal */
    @PostMapping("/legacy/registration")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importRegistration(@Valid @RequestBody ResultsService.MigrationIn body) {
        return service.importRegistration(body.session(), body.semester(), body.rows());
    }

    /** V472: what a course registration upload would do, row by row, before it does it — nothing is written */
    @PostMapping("/legacy/registration/preview")
    @PreAuthorize(MIGRATE)
    Map<String, Object> previewRegistration(@Valid @RequestBody ResultsService.MigrationIn body) {
        return service.previewLegacy(body.session(), body.semester(), body.rows(), false);
    }

    /** V472: what a past results upload would do, row by row, before it does it — nothing is written */
    @PostMapping("/legacy/results/preview")
    @PreAuthorize(MIGRATE)
    Map<String, Object> previewResults(@Valid @RequestBody ResultsService.MigrationIn body) {
        return service.previewLegacy(body.session(), body.semester(), body.rows(), true);
    }

    /** the past results of a semester, imported as final under a legacy minute */
    @PostMapping("/legacy/results")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importResults(@Valid @RequestBody ResultsService.MigrationIn body) {
        return service.importResults(body.session(), body.semester(), body.rows());
    }

    /** the postgraduate course registration of a past session/semester, into the postgraduate module (V214) */
    @PostMapping("/legacy/pg-registration")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importPgRegistration(@Valid @RequestBody ResultsService.MigrationIn body) {
        return service.importPgRegistration(body.session(), body.semester(), body.rows());
    }

    /** the postgraduate past results of a session/semester, graded on the postgraduate scale (V214) */
    @PostMapping("/legacy/pg-results")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importPgResults(@Valid @RequestBody ResultsService.MigrationIn body) {
        return service.importPgResults(body.session(), body.semester(), body.rows());
    }

    /** post every past postgraduate result held for a student not on the register when uploaded (V214) */
    @PostMapping("/legacy/reconcile-pg-results")
    @PreAuthorize(MIGRATE)
    Map<String, Object> reconcilePgResults() {
        return service.reconcilePgHolding();
    }

    /** the postgraduate research / thesis records exported from the old portal (V215) */
    @PostMapping("/legacy/pg-research")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importPgResearch(@Valid @RequestBody ResultsService.StudentsIn body) {
        return service.importPgResearch(body.rows());
    }

    /** set students' JAMB registration numbers from a matric → JAMB upload, so passport photos named by the
     *  JAMB number can match a legacy student who carries no candidate. Same offices as the rest of the desk. */
    @PostMapping("/legacy/jamb-numbers")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importJambNumbers(@Valid @RequestBody ResultsService.StudentsIn body) {
        return service.importJambNumbers(body.rows());
    }

    /** bulk passport photos from the old portal, each named by the student's JAMB reg no; a photo whose
     *  number matches no candidate is skipped and reported. Same offices as the rest of the migration desk. */
    @PostMapping("/legacy/passports")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importPassports(@Valid @RequestBody ResultsService.PassportsIn body) {
        return service.importPassports(body.items());
    }

    @GetMapping("/sheets")
    @PreAuthorize(READERS)
    Sheets.Listing sheets(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                          @RequestParam(required = false) String prog, @RequestParam(required = false) String course,
                          @RequestParam(required = false) String session, @RequestParam(required = false) Integer sem,
                          @RequestParam(required = false) String stage) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);   // the office's bound, whatever the parameters say
        if (course != null && !course.isBlank()) scope.assertCourseInScope(course);
        return service.sheets(b.fac(), b.dept(), b.prog(), blank(course), blank(session), sem, blank(stage));
    }

    @GetMapping("/sheets/{id}")
    @PreAuthorize(READERS)
    Sheets.Detail sheet(@PathVariable UUID id) {
        return service.sheet(id);
    }

    /** V318: the pipeline monitor — the nine stages with their real counts in scope, the coverage (expected, received,
     *  missing) counted from the rolls, the courses whose results are not in, what needs a desk, the timeline, and every
     *  programme and level's broadsheet progress. The office's bound applies whatever the parameters say. */
    @GetMapping("/pipeline")
    @PreAuthorize(READERS)
    Sheets.PipelineView pipeline(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                 @RequestParam(required = false) String prog, @RequestParam(required = false) String session,
                                 @RequestParam(required = false) Integer sem) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);
        return service.pipeline(b.fac(), b.dept(), b.prog(), blank(session), sem);
    }

    /** V421: the monitor's "Results not yet in", student by student — every registered candidate in scope with no mark or
     *  outcome, by course, with why: not yet entered, joined after submission, not on the published set, not in the old
     *  portal's results, or no sheet yet. The office's bound applies whatever the parameters say. */
    @GetMapping("/pipeline/missing-students")
    @PreAuthorize(READERS)
    Map<String, Object> missingStudents(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                        @RequestParam(required = false) String prog, @RequestParam(required = false) String session,
                                        @RequestParam(required = false) Integer sem) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);
        return service.missingStudents(b.fac(), b.dept(), b.prog(), blank(session), sem);
    }

    /** V421: the students in scope by result status for a semester — not available, under verification, processing,
     *  incomplete, published — and those on probation or advised to withdraw, counted only from complete published results.
     *  By default the latest semester the University's calendar has closed. The office's bound applies. */
    @GetMapping("/student-status")
    @PreAuthorize(READERS)
    @org.springframework.transaction.annotation.Transactional(readOnly = true)
    Map<String, Object> studentStatus(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                      @RequestParam(required = false) String prog, @RequestParam(required = false) String session,
                                      @RequestParam(required = false) Integer sem) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);
        String s = blank(session);
        Integer n = sem;
        if (s == null || n == null) {
            Map<String, Object> last = jdbc.sql("""
                    SELECT session, number FROM policy.semester WHERE state IN ('CLOSED', 'ARCHIVED') AND (:s::text IS NULL OR session = :s)
                     ORDER BY session DESC, number DESC LIMIT 1
                    """).param("s", s, java.sql.Types.VARCHAR).query().listOfRows().stream().findFirst().orElse(null);
            if (last == null) {
                return Map.of("session", s == null ? "" : s, "counts", Map.of());
            }
            s = (String) last.get("session");
            n = ((Number) last.get("number")).intValue();
        }
        Map<String, Object> counts = new java.util.LinkedHashMap<>();
        jdbc.sql("SELECT status, students FROM assessment.result_status_counts(:d, :f, :p, :s, :n)")
                .param("d", blank(b.dept()), java.sql.Types.VARCHAR).param("f", blank(b.fac()), java.sql.Types.VARCHAR).param("p", blank(b.prog()), java.sql.Types.VARCHAR)
                .param("s", s).param("n", n).query().listOfRows().forEach(r -> counts.put((String) r.get("status"), r.get("students")));
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", n);
        out.put("counts", counts);
        return out;
    }

    /** V424: the Registry and the result desks — never a lecturer or a student — read the held results and who the absent rule touches */
    private static final String REGISTRY_READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_super')";

    /** V424: every result held for the Senate (withheld, incomplete, malpractice) in the office's scope — how long it has waited and
     *  the amendment carrying the decision when one is open — with the days after which the Registry is reminded. Every session
     *  unless one is named: a held result can be old. */
    @GetMapping("/held")
    @PreAuthorize(REGISTRY_READERS)
    @org.springframework.transaction.annotation.Transactional(readOnly = true)
    Map<String, Object> held(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                             @RequestParam(required = false) String prog, @RequestParam(required = false) String session) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("remindDays", jdbc.sql("SELECT policy.held_remind_days()").query(Integer.class).single());
        out.put("rows", jdbc.sql("SELECT * FROM assessment.held_results(:f, :d, :p, :s)")
                .param("f", blank(b.fac()), java.sql.Types.VARCHAR).param("d", blank(b.dept()), java.sql.Types.VARCHAR)
                .param("p", blank(b.prog()), java.sql.Types.VARCHAR).param("s", blank(session), java.sql.Types.VARCHAR).query().listOfRows());
        return out;
    }

    /** V424: the students in the office's scope owing a course only because of a recorded absence (V422) — for the Registry
     *  before registration. Reads only. */
    @GetMapping("/absence-carryovers")
    @PreAuthorize(REGISTRY_READERS)
    @org.springframework.transaction.annotation.Transactional(readOnly = true)
    List<Map<String, Object>> absenceCarryovers(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                                @RequestParam(required = false) String prog) {
        ng.edu.moaum.portal.shared.OfficeScope.Bound b = scope.bound(fac, dept, prog);
        return jdbc.sql("SELECT * FROM assessment.absence_carryovers(:f, :d, :p)")
                .param("f", blank(b.fac()), java.sql.Types.VARCHAR).param("d", blank(b.dept()), java.sql.Types.VARCHAR)
                .param("p", blank(b.prog()), java.sql.Types.VARCHAR).query().listOfRows();
    }

    @PutMapping("/sheets/{id}/scores")
    @PreAuthorize(ENTRY)
    Map<String, Object> scores(@PathVariable UUID id, @Valid @RequestBody ResultsService.ScoresIn body) {
        return service.scores(id, body);
    }

    @PostMapping("/sheets/{id}/advance")
    @PreAuthorize(DESKS)
    Map<String, Object> advance(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> body) {
        return service.advance(id, body == null ? null : body.get("comment"), body == null ? null : body.get("minute"));
    }

    @PostMapping("/sheets/{id}/return")
    @PreAuthorize(DESKS)
    Map<String, Object> giveBack(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> body) {
        return service.giveBack(id, body == null ? null : body.get("comment"));
    }

    /** V359: the lecturer reminded — by email and text to what they have on record — and the reminder kept */
    @PostMapping("/sheets/{id}/remind")
    @PreAuthorize(DESKS)
    Map<String, Object> remind(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> body) {
        return service.chase(id, "REMIND", body == null ? null : body.get("note"));
    }

    /** V359: a late sheet escalated to the Head of Department, the Dean or its own office, the lecturer told — and kept */
    @PostMapping("/sheets/{id}/escalate")
    @PreAuthorize(DESKS)
    Map<String, Object> escalate(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> body) {
        return service.chase(id, "ESCALATE", body == null ? null : body.get("note"));
    }

    /** V359: every reminder and escalation of a sheet, newest first */
    @GetMapping("/sheets/{id}/chases")
    @PreAuthorize(READERS)
    List<Map<String, Object>> chases(@PathVariable UUID id) {
        return service.chaseHistory(id);
    }

    @GetMapping("/exam-sessions")
    @PreAuthorize(READERS)
    List<Sheets.ExamSession> examSessions(@RequestParam(required = false) String session) {
        return service.examSessions(blank(session));
    }

    @PostMapping("/exam-sessions")
    @PreAuthorize(EXAM_SESSIONS)
    Sheets.ExamSession create(@Valid @RequestBody ResultsService.ExamSessionIn body) {
        return service.createExamSession(body);
    }

    @PutMapping("/exam-sessions/{id}")
    @PreAuthorize(EXAM_SESSIONS)
    Sheets.ExamSession editExamSession(@PathVariable UUID id, @Valid @RequestBody ResultsService.ExamEditIn body) {
        return service.editExamSession(id, body);
    }

    @PostMapping("/exam-sessions/{id}/open")
    @PreAuthorize(EXAM_SESSIONS)
    Map<String, Object> open(@PathVariable UUID id) {
        return service.open(id);
    }

    /** V335: release the score sheets to the lecturers (once) */
    @PostMapping("/exam-sessions/{id}/release-sheets")
    @PreAuthorize(EXAM_SESSIONS)
    Map<String, Object> releaseSheets(@PathVariable UUID id) {
        return service.releaseSheets(id);
    }

    /** V335: release the examination cards to the students */
    @PostMapping("/exam-sessions/{id}/release-cards")
    @PreAuthorize(EXAM_SESSIONS)
    Map<String, Object> releaseCards(@PathVariable UUID id) {
        return service.releaseCards(id, true);
    }

    /** V335: withdraw the examination cards (released in error) */
    @PostMapping("/exam-sessions/{id}/withdraw-cards")
    @PreAuthorize(EXAM_SESSIONS)
    Map<String, Object> withdrawCards(@PathVariable UUID id) {
        return service.releaseCards(id, false);
    }

    @GetMapping("/exam-sessions/{id}/monitor")
    @PreAuthorize(READERS)
    Sheets.Monitor monitor(@PathVariable UUID id) {
        return service.monitor(id);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s;
    }

    /* ── the lecturer's own sheets, the roll, the broadsheet and Senate ── */

    @GetMapping("/mine")
    @PreAuthorize(READERS)
    List<Sheets.MySheet> mine(@RequestParam(required = false) String session, @RequestParam(required = false) Integer sem,
                              @RequestParam(required = false, defaultValue = "false") boolean all) {
        return service.mine(blank(session), sem, all);
    }

    @GetMapping("/sheets/{id}/roll")
    @PreAuthorize(READERS)
    List<Sheets.RollRow> roll(@PathVariable UUID id) {
        return service.roll(id);
    }

    @GetMapping("/broadsheet")
    @PreAuthorize(READERS)
    Sheets.Broadsheet broadsheet(@RequestParam String prog, @RequestParam int level, @RequestParam String session, @RequestParam int sem,
                                 @RequestParam(defaultValue = "REGULAR") @jakarta.validation.constraints.Pattern(regexp = "REGULAR|CCE|PG") String stream) {
        scope.bound(null, null, prog);   // a programme outside the office's bound is refused
        return service.broadsheet(prog, level, session, sem, stream);   // V381: the full-time students' unless the Centre's is asked for
    }

    @GetMapping("/senate")
    @PreAuthorize(READERS)
    Sheets.Senate senate(@RequestParam String session, @RequestParam int sem,
                         @RequestParam(defaultValue = "REGULAR") @jakarta.validation.constraints.Pattern(regexp = "REGULAR|CCE|PG") String stream) {
        return service.senate(session, sem, stream);
    }

    /** V381: stream REGULAR (the default) or CCE — a minute publishes one stream's sets */
    public record MinuteIn(@NotBlank String session, @NotNull Integer sem, String fac, @NotBlank String minute,
                           @jakarta.validation.constraints.Pattern(regexp = "REGULAR|CCE|PG") String stream) {
    }

    @PostMapping("/senate/minute")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar')")
    Map<String, Object> minute(@Valid @RequestBody MinuteIn body) {
        return service.recordMinute(body.session(), body.sem(), blank(body.fac()), body.minute(), body.stream() == null ? "REGULAR" : body.stream());
    }
}
