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
            "hasAnyAuthority('OFFICE_ict','OFFICE_dbops','OFFICE_exams','OFFICE_facultyexams','OFFICE_hod','OFFICE_dean','OFFICE_records',"
            + "'OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";   // V662: a Database Operator granted over the University

    /**
     * Past results go onto the record as final, with no approval chain — they were approved on the old portal — so only the
     * Directorate of ICT uploads them (the University's word of 21 October 2026). The other migration steps stay with MIGRATE, and
     * so does posting results already uploaded and held for a student not yet loaded: that brings in no new result.
     */
    private static final String PAST_RESULTS = "hasAnyAuthority('OFFICE_ict','OFFICE_dbops','OFFICE_super')";   // V662: and a Database Operator granted over the University

    /** the students exported from the old portal — the first migration step, so results and registration can match */
    @PostMapping("/legacy/students")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importStudents(@Valid @RequestBody ResultsService.StudentsIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.importStudents(body.rows());
    }

    /** V721: old-portal students' dates of birth re-read from the migration file — the rows (matric or JAMB number, the date as the file
     *  writes it) read against the register; commit writes the record and the Biodata form with the reason (people.jamb_dob_officer's
     *  offices; the database refuses the rest), preview writes nothing */
    public record DatesOfBirthIn(@NotNull List<Map<String, Object>> rows, boolean commit, String reason) { }
    private static final tools.jackson.databind.ObjectMapper DOB_JSON = new tools.jackson.databind.ObjectMapper();

    @PostMapping("/legacy/dates-of-birth")
    @PreAuthorize(MIGRATE)
    @org.springframework.transaction.annotation.Transactional
    Map<String, Object> datesOfBirth(@Valid @RequestBody DatesOfBirthIn body) {
        scope.requireUniversityOperator("The old-portal migration");
        String rowsJson;
        try {
            rowsJson = DOB_JSON.writeValueAsString(body.rows());
        } catch (RuntimeException e) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("DOB_FILE_ROWS", "The rows could not be read.", new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Upload the file again.", "You"));
        }
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT row_no, matric_no, jamb_reg_no, student_id, surname, other_names, programme_code, file_text, file_date::text AS file_date, held::text AS held, form_value, action
                  FROM people.file_dates_of_birth(:rows::jsonb, :commit, :reason)
                """).param("rows", rowsJson).param("commit", body.commit()).param("reason", body.reason(), java.sql.Types.VARCHAR).query().listOfRows();
        Map<String, Long> counts = new java.util.TreeMap<>();
        for (Map<String, Object> r : rows) counts.merge(String.valueOf(r.get("action")), 1L, Long::sum);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("applied", body.commit());
        out.put("total", rows.size());
        out.put("counts", counts);
        out.put("rows", rows);
        return out;
    }

    /** V459: what each register upload would change before it changes anyone — shown to the office to confirm */
    @PostMapping("/legacy/students/preview")
    @PreAuthorize(MIGRATE)
    Map<String, Object> previewStudents(@Valid @RequestBody ResultsService.StudentsIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.previewRegister("students", body.rows());
    }

    @PostMapping("/legacy/biodata/preview")
    @PreAuthorize(MIGRATE)
    Map<String, Object> previewBiography(@Valid @RequestBody ResultsService.StudentsIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.previewRegister("biodata", body.rows());
    }

    @PostMapping("/legacy/pg-students/preview")
    @PreAuthorize(MIGRATE)
    Map<String, Object> previewPostgraduate(@Valid @RequestBody ResultsService.StudentsIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.previewRegister("postgraduate", body.rows());
    }

    /** the full student biography exported from the old portal — core, contact, biography and a sign-in account */
    @PostMapping("/legacy/biodata")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importBiography(@Valid @RequestBody ResultsService.StudentsIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.importBiography(body.rows());
    }

    /** the postgraduate students exported from the old portal — kept at their postgraduate level (700/800/900)
     *  and school (S002), the programme created in the shared table when it is not yet there */
    @PostMapping("/legacy/pg-students")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importPostgraduate(@Valid @RequestBody ResultsService.StudentsIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.importPostgraduate(body.rows());
    }

    /** post every past result held for a student who was not on the register when the results were
     *  uploaded, but has since been loaded — run after a student/biography upload (V204).
     *
     *  <p>V775: the reconcile takes the held rows before it reads them and then each holding upload's row; a results batch takes its
     *  own upload's row and then the held rows of its students, and a rollback its upload's row and then its holds. Two of them
     *  meeting on the same rows at one instant, PostgreSQL ends one whole — this door, the results import, its check and the
     *  rollback are run again in a fresh transaction (DeadlockRetry) */
    @PostMapping("/legacy/reconcile-results")
    @PreAuthorize(MIGRATE)
    Map<String, Object> reconcileResults() {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return ng.edu.moaum.portal.shared.DeadlockRetry.run(service::reconcileHolding);
    }

    /** the offices that upload past results (PAST_RESULTS), by their codes */
    private static final java.util.Set<String> PAST_RESULT_OFFICES = java.util.Set.of("ict", "dbops", "super");

    /** who reads the old-portal uploads and their reports: the offices that load them, and the Registry and the Academic Office the
     *  graduates whose units a corrected template changed are listed for */
    private static final String UPLOAD_READERS =
            "hasAnyAuthority('OFFICE_ict','OFFICE_dbops','OFFICE_super','OFFICE_records','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    /** an import names the confirmed upload it loads under; without one it is refused before anything is read */
    private static void requireUpload(ResultsService.MigrationIn body) {
        if (body.uploadId() == null) {
            org.springframework.http.ProblemDetail p = org.springframework.http.ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST,
                    "A file is loaded under its confirmed upload, and none was named.");
            p.setTitle("The upload is not named");
            p.setProperty("code", "LEGACY_UPLOAD_REQUIRED");
            p.setProperty("remedy", Map.of("message", "Confirm the upload with its reason, then load the file under it.", "office", "You"));
            throw new org.springframework.web.ErrorResponseException(HttpStatus.BAD_REQUEST, p, null);
        }
    }

    /** an old-portal upload confirmed with its reason (Past results or Course registration): its batches then load under it, and
     *  its ledger keeps every change with what was there before. Past results are the Directorate of ICT's to load (PAST_RESULTS;
     *  the database checks it too), a registration the migration desk's */
    @PostMapping("/legacy/uploads")
    @PreAuthorize(MIGRATE)
    Map<String, Object> beginUpload(@Valid @RequestBody ResultsService.UploadIn body) {
        scope.requireUniversityOperator("The old-portal migration");
        String office = ng.edu.moaum.portal.shared.AuditContextHolder.current().map(ng.edu.moaum.portal.shared.AuditContext::actorOffice).orElse("");
        if ("RESULTS".equals(body.kind()) && !PAST_RESULT_OFFICES.contains(office)) {
            throw new org.springframework.security.access.AccessDeniedException("Past results are uploaded by the Directorate of ICT.");
        }
        return service.beginUpload(body);
    }

    /** the upload closed by the person who opened it: complete (every batch loaded) or not (stopped part way) */
    @PostMapping("/legacy/uploads/{id}/finish")
    @PreAuthorize(MIGRATE)
    Map<String, Object> finishUpload(@PathVariable UUID id, @Valid @RequestBody ResultsService.FinishIn body) {
        scope.requireUniversityOperator("The old-portal migration");
        return service.finishUpload(id, body.complete());
    }

    /** a closed upload rolled back from its ledger, with the reason — by the offices that load past results (the database checks it
     *  too: LEGACY_REVERT_OFFICE); what the record has since moved on from is left as it is and listed */
    @PostMapping("/legacy/uploads/{id}/revert")
    @PreAuthorize(PAST_RESULTS)
    Map<String, Object> revertUpload(@PathVariable UUID id, @Valid @RequestBody ResultsService.RevertIn body) {
        scope.requireUniversityOperator("The old-portal migration");
        // V775: in the service's own transaction, run again on a passing clash with a reconcile of its held rows (see reconcileResults)
        return ng.edu.moaum.portal.shared.DeadlockRetry.run(() -> service.revertUpload(id, body.reason()));
    }

    /** the old-portal uploads, newest first */
    @GetMapping("/legacy/uploads")
    @PreAuthorize(UPLOAD_READERS)
    List<Map<String, Object>> uploads(@RequestParam(required = false) Integer limit) {
        scope.requireUniversityOperator("The old-portal migration");
        return service.uploads(limit);
    }

    /** one upload's report: its changes by kind and in order, and each student's CGPA before and after — the Senate-approved
     *  graduates listed apart for the Registry */
    @GetMapping("/legacy/uploads/{id}")
    @PreAuthorize(UPLOAD_READERS)
    Map<String, Object> upload(@PathVariable UUID id) {
        scope.requireUniversityOperator("The old-portal migration");
        return service.uploadReport(id);
    }

    /** the course registration of a past semester, from the old portal, under its confirmed upload */
    @PostMapping("/legacy/registration")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importRegistration(@Valid @RequestBody ResultsService.MigrationIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        requireUpload(body);
        return service.importRegistration(body.session(), body.semester(), body.rows(), body.uploadId());
    }

    /** V472: what a course registration upload would do, row by row, before it does it — nothing is written */
    @PostMapping("/legacy/registration/preview")
    @PreAuthorize(MIGRATE)
    Map<String, Object> previewRegistration(@Valid @RequestBody ResultsService.MigrationIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.previewLegacy(body.session(), body.semester(), body.rows(), false);
    }

    /** V472: what a past results upload would do, row by row, before it does it — nothing is written */
    @PostMapping("/legacy/results/preview")
    @PreAuthorize(PAST_RESULTS)
    Map<String, Object> previewResults(@Valid @RequestBody ResultsService.MigrationIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return ng.edu.moaum.portal.shared.DeadlockRetry.run(() -> service.previewLegacy(body.session(), body.semester(), body.rows(), true));   // V775
    }

    /** the past results of a semester, imported as final under a legacy minute, under their confirmed upload */
    @PostMapping("/legacy/results")
    @PreAuthorize(PAST_RESULTS)
    Map<String, Object> importResults(@Valid @RequestBody ResultsService.MigrationIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        requireUpload(body);
        return ng.edu.moaum.portal.shared.DeadlockRetry.run(   // V775: a batch that loses a passing clash keeps nothing and is loaded again
                () -> service.importResults(body.session(), body.semester(), body.rows(), body.uploadId()));
    }

    /** the postgraduate course registration of a past session/semester, into the postgraduate module (V214) */
    @PostMapping("/legacy/pg-registration")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importPgRegistration(@Valid @RequestBody ResultsService.MigrationIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.importPgRegistration(body.session(), body.semester(), body.rows());
    }

    /** the postgraduate past results of a session/semester, graded on the postgraduate scale (V214) */
    @PostMapping("/legacy/pg-results")
    @PreAuthorize(PAST_RESULTS)
    Map<String, Object> importPgResults(@Valid @RequestBody ResultsService.MigrationIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.importPgResults(body.session(), body.semester(), body.rows());
    }

    /** post every past postgraduate result held for a student not on the register when uploaded (V214) */
    @PostMapping("/legacy/reconcile-pg-results")
    @PreAuthorize(MIGRATE)
    Map<String, Object> reconcilePgResults() {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.reconcilePgHolding();
    }

    /** the postgraduate research / thesis records exported from the old portal (V215) */
    @PostMapping("/legacy/pg-research")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importPgResearch(@Valid @RequestBody ResultsService.StudentsIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.importPgResearch(body.rows());
    }

    /** set students' JAMB registration numbers from a matric → JAMB upload, so passport photos named by the
     *  JAMB number can match a legacy student who carries no candidate. Same offices as the rest of the desk. */
    @PostMapping("/legacy/jamb-numbers")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importJambNumbers(@Valid @RequestBody ResultsService.StudentsIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
        return service.importJambNumbers(body.rows());
    }

    /** bulk passport photos from the old portal, each named by the student's JAMB reg no; a photo whose
     *  number matches no candidate is skipped and reported. Same offices as the rest of the migration desk. */
    @PostMapping("/legacy/passports")
    @PreAuthorize(MIGRATE)
    Map<String, Object> importPassports(@Valid @RequestBody ResultsService.PassportsIn body) {
        scope.requireUniversityOperator("The old-portal migration");   // V662
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

    /** V624: who takes a course off a programme's broadsheet and puts it back — the department and the offices that keep the sheet,
     *  each within the programmes of their own bound */
    private static final String OMITTERS =
            "hasAnyAuthority('OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    /** V624: a course taken off this broadsheet, with its reason; the registrations and results are untouched */
    @PostMapping("/broadsheet/omissions")
    @PreAuthorize(OMITTERS)
    Map<String, Object> omitFromBroadsheet(@Valid @RequestBody ResultsService.OmissionIn body) {
        scope.bound(null, null, body.prog());
        return service.omitFromBroadsheet(body);
    }

    /** V624: the course put back on this broadsheet */
    @PostMapping("/broadsheet/omissions/restore")
    @PreAuthorize(OMITTERS)
    Map<String, Object> restoreToBroadsheet(@Valid @RequestBody ResultsService.OmissionIn body) {
        scope.bound(null, null, body.prog());
        return service.restoreToBroadsheet(body);
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
