package ng.edu.moaum.portal.studentportal;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The student's own desk: everything under {@code /me} is the signed-in student's, and nobody else's. */
@RestController
@RequestMapping("/api/v1/me")
@PreAuthorize("hasAuthority('OFFICE_student')")
class MeController {

    public record Contact(@Size(max = 30) String phone, @Size(max = 200) String email, @Size(max = 300) String address) {
    }

    public record NewReference(String session, BigDecimal amount) {
    }

    public record Choice(@NotBlank String session, @Min(1) @Max(3) int semester, List<UUID> offerings) {
    }

    public record Submit(@NotBlank String session, @Min(1) @Max(3) int semester) {
    }

    private final StudentPortalService portal;

    MeController(StudentPortalService portal) {
        this.portal = portal;
    }

    @GetMapping
    Map<String, Object> me(Authentication auth) {
        return portal.me(id(auth));
    }

    @PutMapping("/contact")
    Map<String, Object> contact(Authentication auth, @Valid @RequestBody Contact body) {
        return portal.saveContact(id(auth), body.phone(), body.email(), body.address());
    }

    @GetMapping("/fees")
    Map<String, Object> fees(Authentication auth, @RequestParam(required = false) String session) {
        return portal.fees(id(auth), session == null || session.isBlank() ? portal.session() : session);
    }

    @PostMapping("/fees/references")
    Map<String, Object> reference(Authentication auth, @RequestBody(required = false) NewReference body) {
        return portal.newReference(id(auth), body == null ? null : body.session(), body == null ? null : body.amount());
    }

    @GetMapping("/fees/receipts/{reference}")
    Map<String, Object> receipt(Authentication auth, @PathVariable String reference) {
        return portal.receipt(id(auth), reference);
    }

    @GetMapping("/registration")
    Map<String, Object> registration(Authentication auth, @RequestParam(required = false) String session, @RequestParam(defaultValue = "1") int semester) {
        return portal.registrationView(id(auth), session == null || session.isBlank() ? portal.session() : session, semester);
    }

    @GetMapping("/registration-history")
    Map<String, Object> registrationHistory(Authentication auth) {
        return portal.registrationHistory(id(auth));
    }

    @PutMapping("/registration")
    Map<String, Object> choose(Authentication auth, @Valid @RequestBody Choice body) {
        return portal.choose(id(auth), body.session(), body.semester(), body.offerings());
    }

    @PostMapping("/registration/submit")
    Map<String, Object> submit(Authentication auth, @Valid @RequestBody Submit body) {
        return portal.submit(id(auth), body.session(), body.semester());
    }

    public record AddDrop(@NotBlank String session, @Min(1) @Max(3) int semester, @jakarta.validation.constraints.NotNull UUID offering) {
    }

    /** add a course to a submitted/approved registration during the add/drop window */
    @PostMapping("/registration/add")
    Map<String, Object> addCourse(Authentication auth, @Valid @RequestBody AddDrop body) {
        return portal.addCourse(id(auth), body.session(), body.semester(), body.offering());
    }

    /** drop a non-carryover course from a registration during the add/drop window */
    @PostMapping("/registration/drop")
    Map<String, Object> dropCourse(Authentication auth, @Valid @RequestBody AddDrop body) {
        return portal.dropCourse(id(auth), body.session(), body.semester(), body.offering());
    }

    @GetMapping("/results")
    Map<String, Object> results(Authentication auth) {
        return portal.results(id(auth));
    }

    /* ── the services (V027) ── */

    public record Query(@NotBlank String sheetId, @NotBlank String part, @NotBlank @Size(max = 2000) String said) {
    }

    public record Lost(@Size(max = 200) String reason) {
    }

    public record TranscriptRequest(@NotBlank String destination, @Size(max = 200) String destinationName, String mode, @Min(1) @Max(10) Integer copies) {
    }

    @GetMapping("/queries")
    Map<String, Object> queries(Authentication auth) {
        return portal.queries(id(auth));
    }

    @PostMapping("/queries")
    Map<String, Object> raise(Authentication auth, @Valid @RequestBody Query body) {
        return portal.raiseQuery(id(auth), UUID.fromString(body.sheetId()), body.part(), body.said());
    }

    @GetMapping("/docket")
    Map<String, Object> docket(Authentication auth) {
        return portal.docket(id(auth));
    }

    @GetMapping("/timetable")
    Map<String, Object> timetable(Authentication auth, @RequestParam(defaultValue = "1") int semester) {
        return portal.timetable(id(auth), semester);
    }

    @GetMapping("/id-card")
    Map<String, Object> card(Authentication auth) {
        return portal.card(id(auth));
    }

    @PostMapping("/id-card/lost")
    Map<String, Object> lost(Authentication auth, @RequestBody(required = false) @Valid Lost body) {
        return portal.reportLost(id(auth), body == null ? null : body.reason());
    }

    @GetMapping("/transcripts")
    Map<String, Object> transcripts(Authentication auth) {
        return portal.transcripts(id(auth));
    }

    @PostMapping("/transcripts")
    Map<String, Object> requestTranscript(Authentication auth, @Valid @RequestBody TranscriptRequest body) {
        return portal.requestTranscript(id(auth), body.destination(), body.destinationName(), body.mode(), body.copies());
    }

    private static UUID id(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    @GetMapping("/graduation")
    Map<String, Object> graduation(Authentication auth) {
        return portal.graduation(id(auth));
    }

    /** the student's passport image — resolved from the document store or the JAMB/attachment store, so a
     *  migrated or JAMB-loaded photo also appears on the course form and identity documents. */
    @GetMapping("/passport")
    org.springframework.http.ResponseEntity<byte[]> passport(Authentication auth) {
        return portal.passportImage(id(auth))
                .map(img -> org.springframework.http.ResponseEntity.ok()
                        .contentType(org.springframework.http.MediaType.IMAGE_JPEG)
                        // never cache: the URL is the same for every student, so a cached image would show the
                        // previous person who signed in on this browser until a refresh
                        .cacheControl(org.springframework.http.CacheControl.noStore().cachePrivate())
                        .body(img))
                .orElseGet(() -> org.springframework.http.ResponseEntity.notFound().build());
    }
}
