package ng.edu.moaum.portal.results;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;

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

    ResultsController(ResultsService service) {
        this.service = service;
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
}
