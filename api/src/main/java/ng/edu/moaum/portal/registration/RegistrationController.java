package ng.edu.moaum.portal.registration;

import java.time.LocalDate;
import java.util.Map;
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

@RestController
@RequestMapping("/api/v1/registration")
class RegistrationController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_lecturer',"
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String CATALOGUE = "hasAnyAuthority('OFFICE_hod','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final String APPROVERS = "hasAnyAuthority('OFFICE_hod','OFFICE_lecturer','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    /** approval is a single step and it is the Head of Department's (super is system break-glass) */
    private static final String HOD_APPROVES = "hasAnyAuthority('OFFICE_hod','OFFICE_super')";

    private final RegistrationService service;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    RegistrationController(RegistrationService service, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.service = service;
        this.scope = scope;
    }

    @PutMapping("/courses/{code}")
    @PreAuthorize(CATALOGUE)
    Map<String, Object> course(@PathVariable String code, @Valid @RequestBody RegistrationService.CourseIn body) {
        return service.saveCourse(code, body);
    }

    @PostMapping("/courses/{code}/end")
    @PreAuthorize(CATALOGUE)
    Map<String, Object> end(@PathVariable String code, @RequestBody(required = false) Map<String, String> body) {
        LocalDate on = body == null || body.get("endedOn") == null ? null : LocalDate.parse(body.get("endedOn"));
        service.endCourse(code.toUpperCase(), on);
        return Map.of("code", code.toUpperCase(), "state", "ENDED");
    }

    @PutMapping("/courses/{code}/offers/{programme}/{level}")
    @PreAuthorize(CATALOGUE)
    Map<String, Object> offer(@PathVariable String code, @PathVariable String programme, @PathVariable int level,
                              @RequestBody(required = false) Map<String, String> body) {
        service.offer(code.toUpperCase(), programme.toUpperCase(), level, body == null ? null : body.get("basis"));
        return Map.of("course", code.toUpperCase(), "programme", programme.toUpperCase(), "level", level);
    }

    @PutMapping("/offerings")
    @PreAuthorize(CATALOGUE)
    Map<String, Object> offering(@Valid @RequestBody RegistrationService.OfferingIn body) {
        return service.offering(body);
    }

    @PostMapping("/course-registrations")
    @PreAuthorize(APPROVERS)
    Map<String, Object> create(@Valid @RequestBody RegistrationService.RegistrationIn body) {
        return service.create(body);
    }

    @PostMapping("/course-registrations/{id}/submit")
    @PreAuthorize(APPROVERS)
    Map<String, Object> submit(@PathVariable UUID id) {
        return service.submit(id);
    }

    @PostMapping("/course-registrations/{id}/approve")
    @PreAuthorize(HOD_APPROVES)
    Map<String, Object> approve(@PathVariable UUID id) {
        return withDeadlockRetry(() -> service.approve(id));
    }

    @PostMapping("/course-registrations/{id}/return")
    @PreAuthorize(HOD_APPROVES)
    Map<String, Object> giveBack(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> body) {
        return withDeadlockRetry(() -> service.giveBack(id, body == null ? null : body.get("comment")));
    }

    /** A deadlock (e.g. this approval colliding with a bulk import over the shared audit spine) is transient:
     *  the transaction rolls back cleanly, so re-running it a few times with a short backoff resolves it. */
    private <T> T withDeadlockRetry(java.util.function.Supplier<T> op) {
        org.springframework.dao.TransientDataAccessException last = null;
        for (int attempt = 1; attempt <= 4; attempt++) {
            try {
                return op.get();
            } catch (org.springframework.dao.TransientDataAccessException e) {   // deadlock / serialization / lock timeout
                last = e;
                try {
                    Thread.sleep(60L * attempt);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        throw last;
    }

    /** The roll of an offering: approved registrations only, and all of them. */
    @GetMapping("/class-list")
    @PreAuthorize(READERS)
    ClassList classList(@RequestParam String course, @RequestParam String session, @RequestParam(defaultValue = "1") int sem) {
        // a course of another department is refused to a department office; a lecturer is bound by allocation instead —
        // the service refuses any offering not allocated to them, in their own department or a course they teach for another
        if (!scope.actingLecturer()) scope.assertCourseInScope(course);
        return service.classList(course, session, sem);
    }
}
