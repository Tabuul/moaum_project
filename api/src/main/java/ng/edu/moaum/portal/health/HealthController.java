package ng.edu.moaum.portal.health;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The student's Health screen under /api/v1/me/health; the clinic under /api/v1/health. */
@RestController
class HealthController {

    private static final String CLINIC = "hasAnyAuthority('OFFICE_services','OFFICE_super')";

    public record Book(@NotBlank @Size(max = 300) String reason, @NotNull OffsetDateTime preferredAt) {
    }

    public record Why(@Size(max = 300) String why) {
    }

    public record Consent(@Size(max = 4) String bloodGroup, @Size(max = 2) String genotype, @Size(max = 300) String allergies) {
    }

    public record Arrive(@Size(max = 40) String number, UUID studentId, @Size(max = 300) String presenting, String triage, UUID appointmentId) {
    }

    public record Conclude(@NotBlank @Size(max = 600) String outcome, @Size(max = 200) String referredTo, @Size(max = 4000) String note, String fitness) {
    }

    private final HealthService service;

    HealthController(HealthService service) {
        this.service = service;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    /* ── the student ── */

    @GetMapping("/api/v1/me/health")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> mine(Authentication auth) {
        return service.mine(student(auth));
    }

    @PostMapping("/api/v1/me/health/appointments")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> book(Authentication auth, @Valid @RequestBody Book body) {
        return service.book(student(auth), body.reason(), body.preferredAt());
    }

    @PostMapping("/api/v1/me/health/appointments/{id}/cancel")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> cancel(Authentication auth, @PathVariable UUID id, @RequestBody(required = false) Why body) {
        return service.cancel(student(auth), id, body == null ? null : body.why());
    }

    @PutMapping("/api/v1/me/health/consent")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> consent(Authentication auth, @Valid @RequestBody Consent body) {
        return service.consent(student(auth), body.bloodGroup(), body.genotype(), body.allergies());
    }

    @PostMapping("/api/v1/me/health/restrict")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> restrict(Authentication auth) {
        return service.restrict(student(auth));
    }

    /* ── the clinic ── */

    @GetMapping("/api/v1/health/desk")
    @PreAuthorize(CLINIC)
    Map<String, Object> desk(@RequestParam(required = false) String number) {
        return service.desk(number);
    }

    @PostMapping("/api/v1/health/visits")
    @PreAuthorize(CLINIC)
    Map<String, Object> arrive(@Valid @RequestBody Arrive body) {
        return service.arrive(body.number(), body.studentId(), body.presenting(), body.triage(), body.appointmentId());
    }

    @PostMapping("/api/v1/health/visits/{id}/open")
    @PreAuthorize(CLINIC)
    Map<String, Object> open(@PathVariable UUID id) {
        return service.open(id);
    }

    @PostMapping("/api/v1/health/visits/{id}/conclude")
    @PreAuthorize(CLINIC)
    Map<String, Object> conclude(@PathVariable UUID id, @Valid @RequestBody Conclude body) {
        return service.conclude(id, body.outcome(), body.referredTo(), body.note(), body.fitness());
    }
}
