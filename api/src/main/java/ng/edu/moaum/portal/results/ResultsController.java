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
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String DESKS =
            "hasAnyAuthority('OFFICE_lecturer','OFFICE_exams','OFFICE_hod','OFFICE_facultyexams','OFFICE_facultyofficer',"
            + "'OFFICE_dean','OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic')";
    private static final String ENTRY = "hasAnyAuthority('OFFICE_lecturer','OFFICE_exams','OFFICE_academic')";
    private static final String EXAMS = "hasAnyAuthority('OFFICE_records','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    private final ResultsService service;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;
    private final org.springframework.jdbc.core.simple.JdbcClient jdbc;

    ResultsController(ResultsService service, ng.edu.moaum.portal.shared.OfficeScope scope, org.springframework.jdbc.core.simple.JdbcClient jdbc) {
        this.service = service;
        this.scope = scope;
        this.jdbc = jdbc;
    }

    /** a department office reads its own department's programmes only; a faculty office its faculty's */
    private void assertProgrammeInScope(String prog) {
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", prog).query(String.class).optional().orElse(null);
        if (scope.actingDepartmentOffice()) {
            String own = scope.actingDept();
            if (dept == null || own == null || !own.equals(dept)) {
                throw new ng.edu.moaum.portal.shared.DomainRuleViolation("SCOPE_DEPARTMENT", "That programme is not in your department.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Choose a programme of your own department from the bar.", "You"));
            }
        } else if (scope.actingFacultyOffice()) {
            String fac = dept == null ? null : jdbc.sql("SELECT faculty_code FROM ref.department WHERE code = :d").param("d", dept).query(String.class).optional().orElse(null);
            String own = scope.actingFaculty();
            if (fac == null || own == null || !own.equals(fac)) {
                throw new ng.edu.moaum.portal.shared.DomainRuleViolation("SCOPE_FACULTY", "That programme is not in your faculty.",
                        new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Choose a programme of your own faculty from the bar.", "You"));
            }
        }
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

    /** set a first password (the student's own number) for migrated accounts still on the random import
     *  password; must_change stays on, so the student replaces it at first sign-in. Same offices as the rest
     *  of the migration desk (MIGRATE), so the button works wherever the desk is shown. */
    @PostMapping("/legacy/default-passwords")
    @PreAuthorize(MIGRATE)
    Map<String, Object> setDefaultPasswords() {
        return service.setDefaultPasswords();
    }

    @GetMapping("/sheets")
    @PreAuthorize(READERS)
    Sheets.Listing sheets(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                          @RequestParam(required = false) String prog, @RequestParam(required = false) String course,
                          @RequestParam(required = false) String session, @RequestParam(required = false) Integer sem,
                          @RequestParam(required = false) String stage) {
        return service.sheets(blank(fac), blank(dept), blank(prog), blank(course), blank(session), sem, blank(stage));
    }

    @GetMapping("/sheets/{id}")
    @PreAuthorize(READERS)
    Sheets.Detail sheet(@PathVariable UUID id) {
        return service.sheet(id);
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

    /** No notification module yet: the reminder is counted, not sent, and says so. */
    @PostMapping("/sheets/{id}/remind")
    @PreAuthorize(DESKS)
    ResponseEntity<Map<String, Object>> remind(@PathVariable UUID id) {
        Sheets.Detail d = service.sheet(id);
        return ResponseEntity.status(HttpStatus.ACCEPTED).body(Map.of("id", id, "wouldNotify", d.sheet().lecturer() == null ? 0 : 1,
                "note", "The notification module is not on the portal yet; nothing was sent."));
    }

    @GetMapping("/exam-sessions")
    @PreAuthorize(READERS)
    List<Sheets.ExamSession> examSessions(@RequestParam(required = false) String session) {
        return service.examSessions(blank(session));
    }

    @PostMapping("/exam-sessions")
    @PreAuthorize(EXAMS)
    Sheets.ExamSession create(@Valid @RequestBody ResultsService.ExamSessionIn body) {
        return service.createExamSession(body);
    }

    @PutMapping("/exam-sessions/{id}")
    @PreAuthorize(EXAMS)
    Sheets.ExamSession editExamSession(@PathVariable UUID id, @Valid @RequestBody ResultsService.ExamEditIn body) {
        return service.editExamSession(id, body);
    }

    @PostMapping("/exam-sessions/{id}/open")
    @PreAuthorize(EXAMS)
    Map<String, Object> open(@PathVariable UUID id) {
        return service.open(id);
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
    Sheets.Broadsheet broadsheet(@RequestParam String prog, @RequestParam int level, @RequestParam String session, @RequestParam int sem) {
        assertProgrammeInScope(prog);
        return service.broadsheet(prog, level, session, sem);
    }

    @GetMapping("/senate")
    @PreAuthorize(READERS)
    Sheets.Senate senate(@RequestParam String session, @RequestParam int sem) {
        return service.senate(session, sem);
    }

    public record MinuteIn(@NotBlank String session, @NotNull Integer sem, String fac, @NotBlank String minute) {
    }

    @PostMapping("/senate/minute")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar')")
    Map<String, Object> minute(@Valid @RequestBody MinuteIn body) {
        return service.recordMinute(body.session(), body.sem(), blank(body.fac()), body.minute());
    }
}
