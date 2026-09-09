package ng.edu.moaum.portal.platform;

import java.util.Map;

import jakarta.validation.Valid;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The mail server settings, set by the Directorate of ICT and the Super
 * Administrator: IMAP, POP and SMTP for Microsoft 365. The password is written
 * once, encrypted, and never read back — the screen sees only that one is set.
 */
@RestController
@RequestMapping("/api/v1/platform")
class MailController {

    private static final String KEEPERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";

    private final MailService mail;

    MailController(MailService mail) {
        this.mail = mail;
    }

    @GetMapping("/mail")
    @PreAuthorize(KEEPERS)
    Map<String, Object> config() {
        return mail.config();
    }

    @PutMapping("/mail")
    @PreAuthorize(KEEPERS)
    Map<String, Object> save(@Valid @RequestBody MailService.Settings body) {
        return mail.save(body);
    }

    @PostMapping("/mail/clear-password")
    @PreAuthorize(KEEPERS)
    Map<String, Object> clearPassword() {
        return mail.clearPassword();
    }
}
