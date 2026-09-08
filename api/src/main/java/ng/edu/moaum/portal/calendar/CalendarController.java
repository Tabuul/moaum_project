package ng.edu.moaum.portal.calendar;

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
 * The session and semester calendar. Every office that signs in reads it —
 * a registration window and a results-due date are facts the whole
 * University works to. It is written by the Academic Office and the
 * Registry, and by the Super Administrator and the Directorate of ICT so
 * that the platform stays configurable when the Registry is not at its desk.
 */
@RestController
@RequestMapping("/api/v1/calendar")
@PreAuthorize("isAuthenticated()")
class CalendarController {

    private static final String WRITERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super','OFFICE_ict')";

    private final CalendarService calendar;

    CalendarController(CalendarService calendar) {
        this.calendar = calendar;
    }

    /** Every session, which one is current, the semesters of the session asked for, and the unit limits. */
    @GetMapping
    Calendar read(@RequestParam(required = false) String session) {
        return calendar.read(session);
    }

    @PutMapping("/sessions/{session}/{year}")
    @PreAuthorize(WRITERS)
    Calendar saveSession(@PathVariable String session, @PathVariable String year,
                         @Valid @RequestBody CalendarService.SessionIn body) {
        return calendar.saveSession(session + "/" + year, body);
    }

    @PostMapping("/sessions/{session}/{year}/make-current")
    @PreAuthorize(WRITERS)
    Calendar makeCurrent(@PathVariable String session, @PathVariable String year,
                         @RequestBody CalendarService.Minute body) {
        return calendar.makeCurrent(session + "/" + year, body.senateMinute());
    }

    @PostMapping("/sessions/{session}/{year}/close")
    @PreAuthorize(WRITERS)
    Calendar close(@PathVariable String session, @PathVariable String year) {
        return calendar.closeSession(session + "/" + year);
    }

    @PutMapping("/sessions/{session}/{year}/semesters/{number}")
    @PreAuthorize(WRITERS)
    Calendar saveSemester(@PathVariable String session, @PathVariable String year, @PathVariable int number,
                          @Valid @RequestBody CalendarService.SemesterIn body) {
        return calendar.saveSemester(session + "/" + year, number, body);
    }

    @PutMapping("/levels/{level}")
    @PreAuthorize(WRITERS)
    Calendar saveLevel(@PathVariable int level, @Valid @RequestBody CalendarService.LevelIn body) {
        return calendar.saveLevelLimit(level, body);
    }
}
