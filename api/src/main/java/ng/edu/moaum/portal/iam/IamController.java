package ng.edu.moaum.portal.iam;

import java.net.URI;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/iam")
class IamController {

    private final PersonService people;
    private final WaitingRepository waiting;

    IamController(PersonService people, WaitingRepository waiting) {
        this.people = people;
        this.waiting = waiting;
    }

    /** The current principal: who, acting as what, with which offices available. */
    @GetMapping("/me")
    Map<String, Object> me(Authentication authentication) {
        Map<String, Object> me = new LinkedHashMap<>();
        me.put("actorId", authentication.getName());
        me.put("activeOffice", AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null));
        me.put("offices", authentication.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .filter(a -> a.startsWith("OFFICE_"))
                .map(a -> a.substring("OFFICE_".length()))
                .toList());
        me.put("correlationId", AuditContextHolder.current().map(c -> c.correlationId().toString()).orElse(null));
        try {
            Person person = people.get(UUID.fromString(authentication.getName()));
            me.put("name", person.surname() + ", " + person.givenNames());
            me.put("staffNumber", person.staffNumber());
        } catch (RuntimeException noPerson) {
            me.put("name", null);
            me.put("staffNumber", null);
        }
        /* what waits in each queue, by menu item: the menu draws these, and nothing invented */
        me.put("waiting", waiting.waiting());
        if (authentication instanceof org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken t) {
            me.put("sessionId", t.getToken().getClaimAsString("sid"));
        }
        return me;
    }

    @GetMapping("/persons/{id}")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_hrm','OFFICE_ict','OFFICE_admin','OFFICE_super')")
    Map<String, Object> person(@PathVariable UUID id) {
        Person person = people.get(id);
        List<OfficeAssignment> assignments = people.assignments(id);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("person", person);
        body.put("officeAssignments", assignments);
        return body;
    }

    record NewPerson(@Size(max = 40) String staffNumber,
                     @NotBlank @Size(max = 120) String surname,
                     @NotBlank @Size(max = 200) String givenNames,
                     @Size(max = 320) String email, @Size(max = 40) String phone) {
    }

    @PostMapping("/persons")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_hrm','OFFICE_ict','OFFICE_admin','OFFICE_super')")
    ResponseEntity<Person> create(@Valid @RequestBody NewPerson request) {
        Person person = people.create(request.staffNumber(), request.surname(), request.givenNames(), request.email(), request.phone());
        return ResponseEntity.created(URI.create("/api/v1/iam/persons/" + person.id())).body(person);
    }

    record Contact(@Size(max = 320) String email, @Size(max = 40) String phone) {
    }

    /** the Registry sets a staff member's email and phone — where a reset and any notice are sent */
    @PutMapping("/persons/{id}/contact")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_hrm','OFFICE_ict','OFFICE_admin','OFFICE_super')")
    Person contact(@PathVariable UUID id, @Valid @RequestBody Contact request) {
        return people.setContact(id, request.email(), request.phone());
    }

    record NewGrant(@NotBlank String officeCode,
                    @NotBlank @Pattern(regexp = "institution|college|faculty|department|programme|course|unit|platform|level") String scopeKind,
                    String scopeId,
                    @NotBlank @Size(max = 400) String instrument,
                    LocalDate validFrom,
                    LocalDate validTo) {
    }

    @PostMapping("/persons/{id}/office-assignments")
    @PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_vc','OFFICE_super','OFFICE_ict','OFFICE_admin')")
    ResponseEntity<OfficeAssignment> grant(@PathVariable UUID id, @Valid @RequestBody NewGrant request) {
        OfficeAssignment grant = people.grant(id, request.officeCode(), request.scopeKind(), request.scopeId(),
                request.instrument(), request.validFrom(), request.validTo());
        return ResponseEntity.created(URI.create("/api/v1/iam/persons/" + id + "/office-assignments/" + grant.id())).body(grant);
    }
}
