package ng.edu.moaum.portal.platform;

import java.util.Map;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V430: the "how do we reach you" prompt a student or staff member sees at sign-in while the portal holds no usable e-mail or
 * phone for them. The answer is the contact they already keep (the student's own contact, the person's record); this door only
 * records that they put the prompt off, which keeps it away for seven days. Nobody is locked out.
 */
@RestController
@RequestMapping("/api/v1/me/contact-prompt")
@PreAuthorize("isAuthenticated()")
class ContactPromptController {

    private final JdbcClient jdbc;

    ContactPromptController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    static String kindOf(Authentication auth) {
        return auth.getAuthorities().stream().anyMatch(a -> "OFFICE_student".equals(a.getAuthority())) ? "student" : "person";
    }

    @PostMapping("/skip")
    @Transactional
    Map<String, Object> skip(Authentication auth) {
        UUID me = UUID.fromString(auth.getName());
        String kind = kindOf(auth);
        jdbc.sql("SELECT platform.contact_prompt_skip(:k, :me)").param("k", kind).param("me", me).query().listOfRows();
        return Map.of("state", "NONE", "kind", kind);
    }
}
