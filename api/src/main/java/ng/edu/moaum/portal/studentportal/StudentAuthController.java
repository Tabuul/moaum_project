package ng.edu.moaum.portal.studentportal;

import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** The student's door: sign-in on the matriculation number, sign-out, a change of password; and the Registry opening an account. */
@RestController
@RequestMapping("/api/v1/student-auth")
class StudentAuthController {

    public record SignIn(@NotBlank @Size(max = 40) String matricNo, @NotBlank @Size(max = 200) String password) {
    }

    public record ChangePassword(@NotBlank String current, @NotBlank String next) {
    }

    public record Open(@NotBlank @Size(max = 200) String password) {
    }

    private final StudentAuthService auth;

    StudentAuthController(StudentAuthService auth) {
        this.auth = auth;
    }

    @PostMapping("/sign-in")
    StudentAuthService.SignedIn signIn(@Valid @RequestBody SignIn body, HttpServletRequest request) {
        return auth.signIn(body.matricNo(), body.password(), request.getRemoteAddr());
    }

    @PostMapping("/sign-out")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> signOut(Authentication authentication) {
        String sid = authentication instanceof JwtAuthenticationToken t ? t.getToken().getClaimAsString("sid") : null;
        auth.signOut(UUID.fromString(authentication.getName()), sid);
        return Map.of("signedOut", true);
    }

    @PostMapping("/change-password")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> changePassword(Authentication authentication, @Valid @RequestBody ChangePassword body) {
        return auth.changePassword(UUID.fromString(authentication.getName()), body.current(), body.next());
    }

    /** the Registry opens or resets a student's portal account with a first password the student must change */
    @PutMapping("/accounts/{studentId}")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records','OFFICE_ict','OFFICE_super')")
    Map<String, Object> open(@PathVariable UUID studentId, @Valid @RequestBody Open body) {
        return auth.open(studentId, body.password());
    }
}
