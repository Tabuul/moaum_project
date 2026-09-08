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

    @PutMapping("/registration")
    Map<String, Object> choose(Authentication auth, @Valid @RequestBody Choice body) {
        return portal.choose(id(auth), body.session(), body.semester(), body.offerings());
    }

    @PostMapping("/registration/submit")
    Map<String, Object> submit(Authentication auth, @Valid @RequestBody Submit body) {
        return portal.submit(id(auth), body.session(), body.semester());
    }

    @GetMapping("/results")
    Map<String, Object> results(Authentication auth) {
        return portal.results(id(auth));
    }

    private static UUID id(Authentication auth) {
        return UUID.fromString(auth.getName());
    }
}
