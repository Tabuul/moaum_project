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
 * The SMS gateway settings, set by the Directorate of ICT and the Super
 * Administrator: the eBulkSMS account, sender ID and API key. The key is written
 * once, encrypted, and never read back — the screen sees only that one is set.
 */
@RestController
@RequestMapping("/api/v1/platform")
class SmsController {

    private static final String KEEPERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";

    private final SmsService sms;

    SmsController(SmsService sms) {
        this.sms = sms;
    }

    @GetMapping("/sms")
    @PreAuthorize(KEEPERS)
    Map<String, Object> config() {
        return sms.config();
    }

    @PutMapping("/sms")
    @PreAuthorize(KEEPERS)
    Map<String, Object> save(@Valid @RequestBody SmsService.Settings body) {
        return sms.save(body);
    }

    @PostMapping("/sms/clear-key")
    @PreAuthorize(KEEPERS)
    Map<String, Object> clearKey() {
        return sms.clearKey();
    }
}
