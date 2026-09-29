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
 * University works to. It is written by the Director of ICT alone, from
 * Portal Management (moved there from the Academic Office, as the Payment &
 * Registration Windows were in V288); every other office is refused. Making
 * a session current, with the Senate minute that authorises it, is the
 * Director of ICT's act or the Registry's (the Registrar, the Deputy
 * Registrar) or the Super Administrator's.
 */
@RestController
@RequestMapping("/api/v1/calendar")
@PreAuthorize("isAuthenticated()")
class CalendarController {

    /** the calendar's settings: the Director of ICT's, under Portal Management */
    private static final String WRITERS = "hasAuthority('OFFICE_ict')";
    /** V289: the session transition is a named act with its Senate minute: the Director of ICT's, the Registrar's or the Super Administrator's */
    private static final String TRANSITIONERS =
            "hasAnyAuthority('OFFICE_ict','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

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
    @PreAuthorize(TRANSITIONERS)
    Calendar makeCurrent(@PathVariable String session, @PathVariable String year,
                         @RequestBody CalendarService.Minute body) {
        return calendar.makeCurrent(session + "/" + year, body.senateMinute());
    }

    /** V289: the readiness checks of the transition into this session, as the dashboard lists them */
    @GetMapping("/sessions/{session}/{year}/readiness")
    java.util.Map<String, Object> readiness(@PathVariable String session, @PathVariable String year) {
        return calendar.readiness(session + "/" + year);
    }

    /** V289: the transition — the current session completed and this one made current, in one transaction, logged */
    @PostMapping("/sessions/{session}/{year}/transition")
    @PreAuthorize(TRANSITIONERS)
    java.util.Map<String, Object> transition(@PathVariable String session, @PathVariable String year,
                                             @Valid @RequestBody CalendarService.TransitionIn body) {
        return calendar.transitionByHand(session + "/" + year, body);
    }

    /** V289: a completed session archived; the record stays */
    @PostMapping("/sessions/{session}/{year}/archive")
    @PreAuthorize(WRITERS)
    Calendar archive(@PathVariable String session, @PathVariable String year,
                     @RequestBody(required = false) CalendarService.Reason body) {
        return calendar.archive(session + "/" + year, body == null ? null : body.reason());
    }

    @PostMapping("/sessions/{session}/{year}/close")
    @PreAuthorize(WRITERS)
    Calendar close(@PathVariable String session, @PathVariable String year) {
        return calendar.closeSession(session + "/" + year);
    }

    /** Enrol every currently-studying student into this session at their current level, without promoting
     *  anyone. The backfill that matches an already-loaded cohort to the session they are in now. */
    @PostMapping("/sessions/{session}/{year}/enrol-all")
    @PreAuthorize(WRITERS)
    java.util.Map<String, Object> enrolAll(@PathVariable String session, @PathVariable String year) {
        return calendar.enrolAll(session + "/" + year);
    }

    /** Roll the register into this session: promote continuing students one level and enrol them. */
    @PostMapping("/sessions/{session}/{year}/roll-over")
    @PreAuthorize(WRITERS)
    java.util.Map<String, Object> rollOver(@PathVariable String session, @PathVariable String year,
                                           @Valid @RequestBody CalendarService.RollOverIn body) {
        return calendar.rollOver(session + "/" + year, body.confirm(), body.reason());
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
