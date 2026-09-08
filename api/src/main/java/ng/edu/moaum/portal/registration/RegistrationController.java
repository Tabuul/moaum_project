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

    private final RegistrationService service;

    RegistrationController(RegistrationService service) {
        this.service = service;
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
    @PreAuthorize(APPROVERS)
    Map<String, Object> approve(@PathVariable UUID id) {
        return service.approve(id);
    }

    @PostMapping("/course-registrations/{id}/return")
    @PreAuthorize(APPROVERS)
    Map<String, Object> giveBack(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> body) {
        return service.giveBack(id, body == null ? null : body.get("comment"));
    }

    /** The roll of an offering: approved registrations only, and all of them. */
    @GetMapping("/class-list")
    @PreAuthorize(READERS)
    ClassList classList(@RequestParam String course, @RequestParam String session, @RequestParam(defaultValue = "1") int sem) {
        return service.classList(course, session, sem);
    }
}
