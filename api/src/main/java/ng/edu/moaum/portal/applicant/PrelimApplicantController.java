package ng.edu.moaum.portal.applicant;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.ClientAddress;
import ng.edu.moaum.portal.shared.Throttle;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * V446: the Preliminary Science applicant's door and form. {@code register} and the public programme page take no token (the
 * register is counted against the connection, like every applicant door); everything under {@code /me/preliminary} takes the
 * applicant's own token and reaches their own application only. The fee, the documents and the submission are the ordinary
 * applicant endpoints ({@code /me/fee-references}, {@code /me/documents}, {@code /me/submit}).
 */
@RestController
class PrelimApplicantController {

    private static final String APPLICANT = "hasAuthority('OFFICE_applicant')";

    private final PrelimApplicantService service;
    private final Throttle throttle;

    PrelimApplicantController(PrelimApplicantService service, Throttle throttle) {
        this.service = service;
        this.throttle = throttle;
    }

    record Register(@NotBlank @Size(max = 60) String surname, @NotBlank @Size(max = 60) String firstName, @Size(max = 60) String middleName,
                    @NotBlank @Size(max = 1) String sex, @NotBlank @Size(max = 10) String dateOfBirth, @NotBlank @Size(max = 200) String email,
                    @NotBlank @Size(max = 20) String phone, @NotBlank @Size(max = 200) String password) {
    }

    record Biodata(@NotNull @Size(max = 30) Map<String, String> fields, @Size(max = 1) String sex) {
    }

    record Sittings(@NotNull @Size(min = 1, max = 2) List<Map<String, Object>> sittings) {
    }

    record Target(@NotBlank @Size(max = 20) String programmeCode) {
    }

    record Withdraw(@Size(max = 500) String note) {
    }

    /** the programme page: the description, the session, the window, the fee, the requirements, the targets, the documents */
    @GetMapping("/api/v1/public/preliminary-science")
    Map<String, Object> programme() {
        return service.publicInfo();
    }

    @PostMapping("/api/v1/applicant/preliminary/register")
    ApplicantService.SignedIn register(@Valid @RequestBody Register body, HttpServletRequest request) {
        String source = ClientAddress.of(request);
        throttle.take(Throttle.Door.APPLICANT_REGISTER, source);
        return service.register(new PrelimApplicantService.Register(body.surname(), body.firstName(), body.middleName(), body.sex(), body.dateOfBirth(),
                body.email(), body.phone(), body.password()), source);
    }

    @GetMapping("/api/v1/applicant/me/preliminary")
    @PreAuthorize(APPLICANT)
    Map<String, Object> me(Authentication authentication) {
        return service.view(account(authentication));
    }

    @PutMapping("/api/v1/applicant/me/preliminary/biodata")
    @PreAuthorize(APPLICANT)
    Map<String, Object> biodata(Authentication authentication, @Valid @RequestBody Biodata body) {
        return service.biodata(account(authentication), body.fields(), body.sex());
    }

    @PutMapping("/api/v1/applicant/me/preliminary/olevel")
    @PreAuthorize(APPLICANT)
    Map<String, Object> olevel(Authentication authentication, @Valid @RequestBody Sittings body) {
        return service.olevel(account(authentication), body.sittings());
    }

    @PutMapping("/api/v1/applicant/me/preliminary/target")
    @PreAuthorize(APPLICANT)
    Map<String, Object> target(Authentication authentication, @Valid @RequestBody Target body) {
        return service.target(account(authentication), body.programmeCode());
    }

    @PostMapping("/api/v1/applicant/me/preliminary/withdraw")
    @PreAuthorize(APPLICANT)
    Map<String, Object> withdraw(Authentication authentication, @Valid @RequestBody Withdraw body) {
        return service.withdraw(account(authentication), body.note());
    }

    private static UUID account(Authentication authentication) {
        return UUID.fromString(authentication.getName());
    }
}
