package ng.edu.moaum.portal.staff;

import java.util.Base64;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * What the portal knows about the person signed in as an employee, and about
 * the College tier. Both are readable by anybody who signs in: a person may
 * always see their own record, and where the College's academic system sits
 * is not a secret from anyone.
 */
@RestController
@RequestMapping("/api/v1/staff")
@PreAuthorize("isAuthenticated()")
class StaffController {

    private final StaffService staff;

    StaffController(StaffService staff) {
        this.staff = staff;
    }

    /** The acting person and the offices they hold. Never another person's. */
    @GetMapping("/me")
    StaffMe me(Authentication authentication) {
        return staff.me(actor(authentication));
    }

    /** The acting person's own academic profile — their CV as the portal holds it. Never another person's. */
    @GetMapping("/profile")
    Map<String, Object> profile(Authentication authentication) {
        return staff.profile(actor(authentication));
    }

    /** The acting person edits their own profile whole. The DB takes the person from the audit context. */
    @PutMapping("/profile")
    Map<String, Object> saveProfile(Authentication authentication, @RequestBody Map<String, Object> body) {
        return staff.saveProfile(actor(authentication), body);
    }

    /** The acting person's photograph, base64 in a small object; 404 when none is set. */
    @GetMapping("/profile/photo")
    StaffMe.Photo photo(Authentication authentication) {
        return staff.photo(actor(authentication));
    }

    record PhotoIn(String contentType, String dataBase64) {
    }

    /** Upload or replace the acting person's photograph — JPEG or PNG, up to 2 MB, sent base64 in JSON. */
    @PutMapping("/profile/photo")
    Map<String, Object> savePhoto(@RequestBody PhotoIn body) {
        String type = body == null || body.contentType() == null ? "" : body.contentType().trim().toLowerCase();
        if (!type.equals("image/jpeg") && !type.equals("image/png")) {
            throw new DomainRuleViolation("STAFF_PHOTO_TYPE", "A photograph is a JPEG or PNG image.",
                    new DomainRuleViolation.Remedy("Save the picture as JPEG or PNG and upload it again.", null));
        }
        byte[] content;
        try {
            content = Base64.getDecoder().decode(body.dataBase64() == null ? "" : body.dataBase64());
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("STAFF_PHOTO_DATA", "The picture could not be read.",
                    new DomainRuleViolation.Remedy("Choose the picture again and upload it.", null));
        }
        if (content.length < 1 || content.length > 2_097_152) {
            throw new DomainRuleViolation("STAFF_PHOTO_SIZE", "A photograph is between 1 byte and 2 MB.",
                    new DomainRuleViolation.Remedy("Upload a picture no larger than 2 MB.", null));
        }
        staff.savePhoto(type, content);
        return Map.of("ok", true, "bytes", content.length);
    }

    @GetMapping("/college/{code}")
    College college(@PathVariable String code) {
        return staff.college(code);
    }

    /**
     * The acting person is the token's subject, exactly as the audit context
     * takes it — never a parameter, so this endpoint cannot be asked for
     * somebody else's record.
     */
    private static UUID actor(Authentication authentication) {
        return AuditContextHolder.current()
                .map(context -> context.actorId())
                .orElseGet(() -> {
                    if (authentication == null || authentication.getName() == null) {
                        return null;
                    }
                    try {
                        return UUID.fromString(authentication.getName());
                    } catch (IllegalArgumentException notAUuid) {
                        return null;
                    }
                });
    }
}
