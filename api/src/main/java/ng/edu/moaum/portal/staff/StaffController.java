package ng.edu.moaum.portal.staff;

import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
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
