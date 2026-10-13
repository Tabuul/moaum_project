package ng.edu.moaum.portal.iam;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;
import java.util.Map;
import java.util.UUID;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V425: a staff member's or lecturer's own e-mail address and phone number — the person's record, where every notice and
 * every password reset reaches them. Read and written by the person themselves; the Registry's edit of another person's
 * contact stays on /persons/{id}/contact. A student's contact is on the student portal, not here.
 */
@RestController
@RequestMapping("/api/v1/staff/contact")
@PreAuthorize("isAuthenticated() and !hasAuthority('OFFICE_student') and !hasAuthority('OFFICE_applicant')")
class MeContactController {

    private final JdbcClient jdbc;
    private final PersonRepository people;

    MeContactController(JdbcClient jdbc, PersonRepository people) {
        this.jdbc = jdbc;
        this.people = people;
    }

    @GetMapping
    @Transactional(readOnly = true)
    Map<String, Object> mine() {
        UUID me = AuditContextHolder.required().actorId();
        return jdbc.sql("""
                SELECT p.email, p.phone, p.surname, p.given_names, p.staff_number,
                       platform.email_valid(p.email) AS email_valid, platform.phone_valid(p.phone) AS phone_valid,
                       platform.unread_count('person', p.id) AS unread
                  FROM iam.person p WHERE p.id = :me
                """).param("me", me).query().singleRow();
    }

    record ContactIn(@Size(max = 320) String email, @Size(max = 40) String phone) {
    }

    @PutMapping
    @Transactional
    Map<String, Object> save(@Valid @RequestBody ContactIn in) {
        UUID me = AuditContextHolder.required().actorId();
        String email = in.email() == null || in.email().isBlank() ? null : in.email().trim();
        String phone = in.phone() == null || in.phone().isBlank() ? null : in.phone().trim();
        if (email == null && phone == null) {
            throw new DomainRuleViolation("CONTACT_EMPTY", "An e-mail address or a phone number is needed to reach you.",
                    new DomainRuleViolation.Remedy("Give at least one of the two.", "Directorate of ICT"));
        }
        Map<String, Object> valid = jdbc.sql("SELECT platform.email_valid(:e) AS e, platform.phone_valid(:p) AS p")
                .param("e", email, java.sql.Types.VARCHAR).param("p", phone, java.sql.Types.VARCHAR).query().singleRow();
        if (email != null && !Boolean.TRUE.equals(valid.get("e"))) {
            throw new DomainRuleViolation("CONTACT_EMAIL", "'" + email + "' is not an e-mail address.",
                    new DomainRuleViolation.Remedy("Give the address as name@domain.", "Directorate of ICT"));
        }
        if (phone != null && !Boolean.TRUE.equals(valid.get("p"))) {
            throw new DomainRuleViolation("CONTACT_PHONE", "'" + phone + "' is not a Nigerian phone number.",
                    new DomainRuleViolation.Remedy("Give the number as 0801 234 5678 or 234 801 234 5678.", "Directorate of ICT"));
        }
        people.setContact(me, email, phone);
        return mine();
    }
}
