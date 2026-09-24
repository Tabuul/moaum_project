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
            + "'OFFICE_bursar','OFFICE_library','OFFICE_security','OFFICE_housing','OFFICE_hrm',"
            + "'OFFICE_audit','OFFICE_lecturer')";
    private static final String WRITERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    private final StudentService students;
    private final ChangeService changes;
    private final SearchService search;
    private final RecordsService records;
    private final ng.edu.moaum.portal.studentportal.StudentPortalService portal;
    private final org.springframework.jdbc.core.simple.JdbcClient jdbc;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    StudentController(StudentService students, ChangeService changes, SearchService search, RecordsService records,
                      ng.edu.moaum.portal.studentportal.StudentPortalService portal, org.springframework.jdbc.core.simple.JdbcClient jdbc,
                      ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.students = students;
        this.changes = changes;
        this.search = search;
        this.records = records;
        this.portal = portal;
        this.jdbc = jdbc;
        this.scope = scope;
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
    java.util.Map<String, Object> migrated(@RequestParam(defaultValue = "100") int from, @RequestParam(defaultValue = "400") int to) {
        return jdbc.sql("SELECT * FROM clearance.migrated_summary(:f, :t)").param("f", from).param("t", to).query().singleRow();
    }

    /** Clear the migrated students at these levels who still lack a unit's word — the old portal's clearance, carried over (V231/V233). */
    @PostMapping("/students/migrated/clear")
    @PreAuthorize("hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')")
    @org.springframework.transaction.annotation.Transactional
    java.util.Map<String, Object> clearMigrated(@RequestParam(defaultValue = "100") int from, @RequestParam(defaultValue = "400") int to) {
        java.util.Map<String, Object> done = jdbc.sql("SELECT * FROM clearance.clear_migrated(:f, :t)").param("f", from).param("t", to).query().singleRow();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>(done);
        out.putAll(migrated(from, to));
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

    /** One record entire. The session decides which registrations it shows. */
    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    StudentRecord record(@PathVariable UUID id, @RequestParam(required = false) String session) {
        return students.record(id, blankToNull(session));
    }

    /** The student's own portal view of themselves — fees, GPA and CGPA, standing, carryovers, this session's
     *  registration, graduation — read by an office for the record pop-up. The same figures the student sees. */
    @GetMapping("/students/{id}/portal")
    @PreAuthorize(READERS)
    java.util.Map<String, Object> portal(@PathVariable UUID id) {
        return portal.me(id);
    }

    /** The student's passport photograph, from whichever store holds it (document, JAMB, attachment). */
    @GetMapping("/students/{id}/passport")
    @PreAuthorize(READERS)
    org.springframework.http.ResponseEntity<byte[]> passport(@PathVariable UUID id) {
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
        return records.view(view, Scope.of(fac, dept, prog, level, course, session, sem));
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
