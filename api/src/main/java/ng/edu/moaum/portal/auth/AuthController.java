package ng.edu.moaum.portal.auth;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
class AuthController {

    public record SignIn(@NotBlank @Size(max = 200) String username, @NotBlank @Size(max = 200) String password, String office) {
    }

    public record Bootstrap(@Size(max = 40) String staffNumber, @NotBlank @Size(max = 120) String surname,
                            @NotBlank @Size(max = 200) String givenNames, @NotBlank @Size(max = 200) String username,
                            @NotBlank @Size(max = 200) String password) {
    }

    public record ChangePassword(@NotBlank String current, @NotBlank String next) {
    }

    public record SsoCallback(@NotBlank String code, @NotBlank String state, @NotBlank String redirectUri) {
    }

    private final AuthService auth;
    private final SsoService sso;
    private final String bootstrapSecret;

    AuthController(AuthService auth, SsoService sso, @Value("${moaum.auth.hmac-secret:}") String bootstrapSecret) {
        this.auth = auth;
        this.sso = sso;
        this.bootstrapSecret = bootstrapSecret;
    }

    /* ── single sign-on through the University's identity provider (Keycloak), for staff ── */

    @GetMapping("/sso")
    Map<String, Object> ssoDescribe() {
        return sso.describe();
    }

    @GetMapping("/sso/start")
    Map<String, Object> ssoStart(@RequestParam String redirectUri) {
        return sso.start(redirectUri);
    }

    @PostMapping("/sso/callback")
    AuthService.SignedIn ssoCallback(@Valid @RequestBody SsoCallback body, HttpServletRequest request) {
        return sso.callback(body.code(), body.state(), body.redirectUri(), request.getRemoteAddr());
    }

    @PostMapping("/sign-in")
    AuthService.SignedIn signIn(@Valid @RequestBody SignIn body, HttpServletRequest request) {
        return auth.signIn(body.username(), body.password(), request.getRemoteAddr(), body.office());
    }

    @PostMapping("/sign-out")
    Map<String, Object> signOut(Authentication authentication) {
        auth.signOut(UUID.fromString(authentication.getName()), sid(authentication));
        return Map.of("signedOut", true);
    }

    @GetMapping("/sessions")
    List<AuthRepository.Session> sessions(Authentication authentication) {
        return auth.sessions(UUID.fromString(authentication.getName()));
    }

    @PostMapping("/sessions/{id}/end")
    Map<String, Object> end(@PathVariable String id, Authentication authentication) {
        auth.endSession(UUID.fromString(authentication.getName()), id);
        return Map.of("ended", id);
    }

    @PostMapping("/change-password")
    Map<String, Object> change(@Valid @RequestBody ChangePassword body, Authentication authentication) {
        auth.changePassword(UUID.fromString(authentication.getName()), body.current(), body.next());
        return Map.of("changed", true);
    }

    /** The first account, once, with the secret the API already trusts. */
    @PostMapping("/bootstrap")
    AuthService.SignedIn bootstrap(@Valid @RequestBody Bootstrap body, @RequestHeader(value = "X-Bootstrap-Secret", required = false) String secret,
                                   HttpServletRequest request) {
        return auth.bootstrap(secret, bootstrapSecret, body.staffNumber(), body.surname(), body.givenNames(), body.username(),
                body.password(), request.getRemoteAddr());
    }

    /** the office register, for the sign-in page's "Your office" */
    @GetMapping("/offices")
    List<AuthRepository.OfficeRow> offices() {
        return auth.offices();
    }

    private static String sid(Authentication authentication) {
        return authentication instanceof JwtAuthenticationToken t ? t.getToken().getClaimAsString("sid") : null;
    }
}
