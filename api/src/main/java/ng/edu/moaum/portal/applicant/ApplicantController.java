package ng.edu.moaum.portal.applicant;

import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The applicant's door and desk. {@code lookup}, {@code register} and
 * {@code sign-in} take no token; everything under {@code /me} takes the
 * applicant's own, and reaches the applicant's own application only.
 */
@RestController
@RequestMapping("/api/v1/applicant")
class ApplicantController {

    private static final String APPLICANT = "hasAuthority('OFFICE_applicant')";

    public record Lookup(@NotBlank String session, @NotBlank @Size(max = 20) String jambKey) {
    }

    public record Register(@NotBlank String session, @NotBlank @Size(max = 20) String jambKey, @NotBlank @Size(max = 200) String email,
                           @NotBlank @Size(max = 30) String phone, @NotBlank @Size(max = 200) String password) {
    }

    public record SignIn(@NotBlank @Size(max = 200) String identifier, @NotBlank @Size(max = 200) String password) {
    }

    public record NextOfKin(@NotBlank @Size(max = 300) String nextOfKin) {
    }

    public record FeeKind(@NotBlank String kind) {
    }

    public record Upload(@NotBlank String kind, @Size(max = 200) String filename, @NotBlank String contentType, @NotBlank String contentBase64) {
    }

    public record Submit(boolean declaration) {
    }

    public record Accept(boolean undertaking) {
    }

    private final ApplicantService service;

    ApplicantController(ApplicantService service) {
        this.service = service;
    }

    @PostMapping("/lookup")
    Map<String, Object> lookup(@Valid @RequestBody Lookup body) {
        return service.lookup(body.session(), body.jambKey());
    }

    @PostMapping("/register")
    ApplicantService.SignedIn register(@Valid @RequestBody Register body, HttpServletRequest request) {
        return service.register(body.session(), body.jambKey(), body.email(), body.phone(), body.password(), request.getRemoteAddr());
    }

    @PostMapping("/sign-in")
    ApplicantService.SignedIn signIn(@Valid @RequestBody SignIn body, HttpServletRequest request) {
        return service.signIn(body.identifier(), body.password(), request.getRemoteAddr());
    }

    @PostMapping("/sign-out")
    @PreAuthorize(APPLICANT)
    Map<String, Object> signOut(Authentication authentication) {
        String sid = authentication instanceof JwtAuthenticationToken t ? t.getToken().getClaimAsString("sid") : null;
        service.signOut(account(authentication), sid);
        return Map.of("signedOut", true);
    }

    @GetMapping("/me")
    @PreAuthorize(APPLICANT)
    Map<String, Object> me(Authentication authentication) {
        return service.me(account(authentication));
    }

    @PutMapping("/me/next-of-kin")
    @PreAuthorize(APPLICANT)
    Map<String, Object> nextOfKin(Authentication authentication, @Valid @RequestBody NextOfKin body) {
        return service.nextOfKin(account(authentication), body.nextOfKin());
    }

    @PostMapping("/me/fee-references")
    @PreAuthorize(APPLICANT)
    Map<String, Object> feeReference(Authentication authentication, @Valid @RequestBody FeeKind body) {
        return service.feeReference(account(authentication), body.kind());
    }

    @PostMapping("/me/documents")
    @PreAuthorize(APPLICANT)
    Map<String, Object> upload(Authentication authentication, @Valid @RequestBody Upload body) {
        return service.document(account(authentication), body.kind(), body.filename(), body.contentType(), body.contentBase64());
    }

    @GetMapping("/me/documents/{id}/content")
    @PreAuthorize(APPLICANT)
    ResponseEntity<byte[]> content(Authentication authentication, @PathVariable UUID id) {
        DocumentContent c = service.documentContent(account(authentication), id);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(c.contentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + c.filename().replace("\"", "") + "\"")
                .body(c.content());
    }

    @PostMapping("/me/submit")
    @PreAuthorize(APPLICANT)
    Map<String, Object> submit(Authentication authentication, @Valid @RequestBody Submit body, HttpServletRequest request) {
        return service.submit(account(authentication), body.declaration(), request.getRemoteAddr());
    }

    @PostMapping("/me/accept")
    @PreAuthorize(APPLICANT)
    Map<String, Object> accept(Authentication authentication, @Valid @RequestBody Accept body) {
        return service.accept(account(authentication), body.undertaking());
    }

    @PostMapping("/me/decline")
    @PreAuthorize(APPLICANT)
    Map<String, Object> decline(Authentication authentication) {
        return service.decline(account(authentication));
    }

    private static UUID account(Authentication authentication) {
        return UUID.fromString(authentication.getName());
    }
}
