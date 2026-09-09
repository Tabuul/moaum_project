package ng.edu.moaum.portal.lms;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The student's course spaces under /api/v1/me/courses; the lecturer's under /api/v1/lms. */
@RestController
class LmsController {

    private static final String TEACHERS = "hasAnyAuthority('OFFICE_lecturer','OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_super')";

    public record Submit(@Size(max = 20000) String text, @Size(max = 200) String filename, String contentType, String contentBase64) {
    }

    public record Material(Integer week, @NotBlank @Size(max = 200) String title, String kind, @Size(max = 2000) String description,
                           @Size(max = 200) String filename, String contentType, String contentBase64, @Size(max = 500) String link, Boolean publish) {
    }

    public record Assignment(@NotBlank @Size(max = 200) String title, @Size(max = 4000) String brief, String kind, OffsetDateTime opensAt,
                             @NotNull OffsetDateTime closesAt, Integer lateHours, Integer latePenalty, @NotNull Integer weight, Integer outOf) {
    }

    public record Mark(@NotNull BigDecimal mark, @Size(max = 2000) String feedback) {
    }

    private final LmsService service;

    LmsController(LmsService service) {
        this.service = service;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private static ResponseEntity<byte[]> file(LmsRepository.FileContent f) {
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(f.contentType() == null ? "application/octet-stream" : f.contentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + (f.filename() == null ? "file" : f.filename().replace("\"", "")) + "\"")
                .body(f.content());
    }

    /* ── the student ── */

    @GetMapping("/api/v1/me/courses")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> mine(Authentication auth, @RequestParam(required = false) String session) {
        return service.mine(student(auth), session);
    }

    @GetMapping("/api/v1/me/courses/{offering}")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> space(Authentication auth, @PathVariable UUID offering) {
        return service.space(student(auth), offering);
    }

    @GetMapping("/api/v1/me/courses/materials/{id}/content")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    ResponseEntity<byte[]> read(Authentication auth, @PathVariable UUID id) {
        return file(service.read(student(auth), id));
    }

    @PostMapping("/api/v1/me/courses/materials/{id}/read")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> noteRead(Authentication auth, @PathVariable UUID id) {
        return service.noteRead(student(auth), id);
    }

    @PostMapping("/api/v1/me/courses/assignments/{id}/submit")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> submit(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Submit body) {
        return service.submit(student(auth), id, body.text(), body.filename(), body.contentType(), body.contentBase64());
    }

    /* ── the lecturer ── */

    @GetMapping("/api/v1/lms/teaching")
    @PreAuthorize(TEACHERS)
    Map<String, Object> teaching(@RequestParam(required = false) String session) {
        return service.teaching(session);
    }

    @GetMapping("/api/v1/lms/offerings/{offering}")
    @PreAuthorize(TEACHERS)
    Map<String, Object> desk(@PathVariable UUID offering) {
        return service.desk(offering);
    }

    @PostMapping("/api/v1/lms/offerings/{offering}/materials")
    @PreAuthorize(TEACHERS)
    Map<String, Object> material(@PathVariable UUID offering, @Valid @RequestBody Material body) {
        return service.addMaterial(offering, body.week(), body.title(), body.kind(), body.description(), body.filename(), body.contentType(),
                body.contentBase64(), body.link(), body.publish() == null || body.publish());
    }

    @PostMapping("/api/v1/lms/offerings/{offering}/materials/{id}/publish")
    @PreAuthorize(TEACHERS)
    Map<String, Object> publish(@PathVariable UUID offering, @PathVariable UUID id) {
        return service.publish(offering, id);
    }

    @PostMapping("/api/v1/lms/offerings/{offering}/materials/{id}/end")
    @PreAuthorize(TEACHERS)
    Map<String, Object> end(@PathVariable UUID offering, @PathVariable UUID id) {
        return service.end(offering, id);
    }

    @GetMapping("/api/v1/lms/offerings/{offering}/materials/{id}/content")
    @PreAuthorize(TEACHERS)
    ResponseEntity<byte[]> materialContent(@PathVariable UUID offering, @PathVariable UUID id) {
        return file(service.materialForLecturer(offering, id));
    }

    @PostMapping("/api/v1/lms/offerings/{offering}/assignments")
    @PreAuthorize(TEACHERS)
    Map<String, Object> assignment(@PathVariable UUID offering, @Valid @RequestBody Assignment body) {
        return service.addAssignment(offering, body.title(), body.brief(), body.kind(), body.opensAt(), body.closesAt(), body.lateHours(), body.latePenalty(), body.weight(), body.outOf());
    }

    @GetMapping("/api/v1/lms/offerings/{offering}/assignments/{id}/submissions")
    @PreAuthorize(TEACHERS)
    List<Map<String, Object>> submissions(@PathVariable UUID offering, @PathVariable UUID id) {
        return service.submissions(offering, id);
    }

    @PostMapping("/api/v1/lms/offerings/{offering}/assignments/{id}/submissions/{submission}/mark")
    @PreAuthorize(TEACHERS)
    Map<String, Object> mark(@PathVariable UUID offering, @PathVariable UUID id, @PathVariable UUID submission, @Valid @RequestBody Mark body) {
        return service.mark(offering, id, submission, body.mark(), body.feedback());
    }

    @GetMapping("/api/v1/lms/offerings/{offering}/submissions/{submission}/content")
    @PreAuthorize(TEACHERS)
    ResponseEntity<byte[]> submissionContent(@PathVariable UUID offering, @PathVariable UUID submission) {
        return file(service.submissionFile(offering, submission));
    }

    @PostMapping("/api/v1/lms/offerings/{offering}/promote")
    @PreAuthorize(TEACHERS)
    Map<String, Object> promote(@PathVariable UUID offering) {
        return service.promote(offering);
    }
}
