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

    /** V423: a passport photograph as a data URL (JPEG or PNG, up to 2 MB) */
    public record Photo(@NotBlank String dataUrl) {
    }

    public record Choice(@NotBlank String session, @Min(1) @Max(3) int semester, List<UUID> offerings) {
    }

    public record Submit(@NotBlank String session, @Min(1) @Max(3) int semester) {
    }

    /** V528: the bank account a refund raised to the student is paid into (the account number is the ten-digit NUBAN) */
    public record RefundAccount(@NotBlank @Size(max = 120) String bank, @NotBlank @Size(max = 200) String accountName,
                                @NotBlank @Size(max = 20) String accountNumber) {
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
        return portal.fees(id(auth), session == null || session.isBlank() ? portal.sessionFor(id(auth)) : session);
    }

    @PostMapping("/fees/references")
    Map<String, Object> reference(Authentication auth, @RequestBody(required = false) NewReference body) {
        return portal.newReference(id(auth), body == null ? null : body.session(), body == null ? null : body.amount());
    }

    /** V528: the student gives (or, while it awaits approval, changes) the account a refund of overpaid fees is paid into */
    @PostMapping("/fees/refunds/{reference}/account")
    Map<String, Object> refundAccount(Authentication auth, @PathVariable String reference, @Valid @RequestBody RefundAccount body) {
        return portal.giveRefundAccount(id(auth), reference, body.bank(), body.accountName(), body.accountNumber());
    }

    /** V533: the banks a refund is paid into, and whether a number at each is checked against the bank */
    @GetMapping("/banks")
    List<Map<String, Object>> banks() {
        return portal.banks();
    }

    @GetMapping("/fees/receipts/{reference}")
    Map<String, Object> receipt(Authentication auth, @PathVariable String reference) {
        return portal.receipt(id(auth), reference);
    }

    /** GST & EPS (V314): the fee the Bursar stated, whether it is paid, the GST/EPS courses and their registration */
    @GetMapping("/gst")
    Map<String, Object> gst(Authentication auth, @RequestParam(required = false) String session) {
        return portal.gst(id(auth), session == null || session.isBlank() ? portal.sessionFor(id(auth)) : session);
    }

    /** the reference the GST fee is paid against, on the same ledger and gateway as every other payment */
    @PostMapping("/gst/reference")
    Map<String, Object> gstReference(Authentication auth, @RequestBody(required = false) NewReference body) {
        return portal.newGstReference(id(auth), body == null ? null : body.session());
    }

    @GetMapping("/registration")
    Map<String, Object> registration(Authentication auth, @RequestParam(required = false) String session, @RequestParam(defaultValue = "1") int semester) {
        return portal.registrationView(id(auth), session == null || session.isBlank() ? portal.sessionFor(id(auth)) : session, semester);
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

    public record ResetIn(@NotBlank String session, @Min(1) @Max(3) int semester, @jakarta.validation.constraints.Size(max = 500) String reason) {
    }

    /** V491: the student resets their own registration for the semester and registers again — the student is the token's, never
     *  a number the browser sends */
    @PostMapping("/registration/reset")
    Map<String, Object> resetRegistration(Authentication auth, @Valid @RequestBody ResetIn body) {
        return portal.reset(id(auth), body.session(), body.semester(), body.reason());
    }

    public record AddDrop(@NotBlank String session, @Min(1) @Max(3) int semester, @jakarta.validation.constraints.NotNull UUID offering) {
    }

    /** add a course to a submitted/approved registration during the add/drop window */
    @PostMapping("/registration/add")
    Map<String, Object> addCourse(Authentication auth, @Valid @RequestBody AddDrop body) {
        return portal.addCourse(id(auth), body.session(), body.semester(), body.offering());
    }

    /** V504: Add Other Course — the courses a search finds, each judged by the engine for the signed-in student and semester */
    @GetMapping("/registration/courses")
    Map<String, Object> searchCourses(Authentication auth, @RequestParam(required = false) String session, @RequestParam(defaultValue = "1") int semester,
                                      @RequestParam(required = false) String q, @RequestParam(required = false) Integer level,
                                      @RequestParam(required = false) String dept, @RequestParam(required = false) String faculty,
                                      @RequestParam(required = false) String category, @RequestParam(defaultValue = "0") int page) {
        if (semester < 1 || semester > 3) semester = 1;
        return portal.searchCourses(id(auth), session == null || session.isBlank() ? portal.sessionFor(id(auth)) : session, semester,
                q, level, dept, faculty, category, page);
    }

    /** V504: the departments and faculties the search narrows to */
    @GetMapping("/registration/courses/filters")
    Map<String, Object> searchFilters() {
        return portal.searchFilters();
    }

    /** V504: the student adds a course the search found; the engine judges it, and refuses with its reason */
    @PostMapping("/registration/courses")
    Map<String, Object> addOtherCourse(Authentication auth, @Valid @RequestBody AddDrop body) {
        return portal.addOtherCourse(id(auth), body.session(), body.semester(), body.offering());
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

    /** V360: the signed check code for the student's own examination card (EXAM), course form (REG) or results statement (RESULT) */
    @GetMapping("/check-code")
    Map<String, Object> checkCode(Authentication auth, @RequestParam String kind, @RequestParam String session, @RequestParam(defaultValue = "1") int semester) {
        return portal.checkCode(id(auth), kind, session, semester);
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
    /** V423: the student's own first passport photograph, when the portal finds none anywhere; replacing one stays with ICT Support */
    @PutMapping("/passport")
    Map<String, Object> uploadPassport(Authentication auth, @Valid @RequestBody Photo body) {
        return portal.uploadPassport(id(auth), body.dataUrl());
    }

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
