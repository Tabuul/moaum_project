package ng.edu.moaum.portal.hostel;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
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

/** The student's hostel screen under /api/v1/me/hostel; Student Services' desk under /api/v1/hostel. */
@RestController
class HostelController {

    private static final String OFFICE = "hasAnyAuthority('OFFICE_services','OFFICE_housing','OFFICE_bursar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    private static final String READERS = "hasAnyAuthority('OFFICE_services','OFFICE_housing','OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_admin','OFFICE_super','OFFICE_ict','OFFICE_audit','OFFICE_vc','OFFICE_dvc')";

    public record Apply(String session, @Size(max = 8) String hall, @Size(max = 20) String category, @Size(max = 400) String note) {
    }

    public record Issue(String session, @NotBlank @Size(max = 400) String issue) {
    }

    public record Setting(BigDecimal fee, Integer holdHours, LocalDate applicationsClose) {
    }

    public record Hall(@NotBlank @Size(max = 8) String code, @NotBlank @Size(max = 120) String name, String sex) {
    }

    public record Room(@NotBlank String hall, @NotBlank String block, @NotBlank String roomNo, Integer beds, Boolean outOfService, String note) {
    }

    public record Seed(@NotBlank @Size(min = 6, max = 120) String seed) {
    }

    public record Decision(@NotBlank String state, @Size(max = 400) String note) {
    }

    private final HostelService service;

    HostelController(HostelService service) {
        this.service = service;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    /* ── the student ── */

    @GetMapping("/api/v1/me/hostel")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> mine(Authentication auth, @RequestParam(required = false) String session) {
        return service.mine(student(auth), session);
    }

    @PostMapping("/api/v1/me/hostel/apply")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> apply(Authentication auth, @Valid @RequestBody Apply body) {
        return service.apply(student(auth), body.session(), body.hall(), body.category(), body.note());
    }

    @PostMapping("/api/v1/me/hostel/fee-reference")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> feeReference(Authentication auth, @RequestBody(required = false) Map<String, String> body) {
        return service.feeReference(student(auth), body == null ? null : body.get("session"));
    }

    @PostMapping("/api/v1/me/hostel/maintenance")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> raise(Authentication auth, @Valid @RequestBody Issue body) {
        return service.raise(student(auth), body.session(), body.issue());
    }

    /* ── the office ── */

    @GetMapping("/api/v1/hostel/sessions/{s}/{y}")
    @PreAuthorize(READERS)
    Map<String, Object> desk(@PathVariable String s, @PathVariable String y) {
        return service.desk(s + "/" + y);
    }

    @PutMapping("/api/v1/hostel/sessions/{s}/{y}/setting")
    @PreAuthorize(OFFICE)
    Map<String, Object> setting(@PathVariable String s, @PathVariable String y, @RequestBody Setting body) {
        return service.putSetting(s + "/" + y, body.fee(), body.holdHours(), body.applicationsClose());
    }

    @PutMapping("/api/v1/hostel/halls")
    @PreAuthorize(OFFICE)
    Map<String, Object> hall(@Valid @RequestBody Hall body) {
        return service.putHall(body.code(), body.name(), body.sex());
    }

    @PutMapping("/api/v1/hostel/rooms")
    @PreAuthorize(OFFICE)
    Map<String, Object> room(@Valid @RequestBody Room body) {
        return service.putRoom(body.hall(), body.block(), body.roomNo(), body.beds(), body.outOfService(), body.note());
    }

    @PostMapping("/api/v1/hostel/sessions/{s}/{y}/draw")
    @PreAuthorize(OFFICE)
    Map<String, Object> draw(@PathVariable String s, @PathVariable String y, @Valid @RequestBody Seed body) {
        return service.draw(s + "/" + y, body.seed());
    }

    @PostMapping("/api/v1/hostel/sessions/{s}/{y}/lapse")
    @PreAuthorize(OFFICE)
    Map<String, Object> lapse(@PathVariable String s, @PathVariable String y) {
        return service.lapse(s + "/" + y);
    }

    @PostMapping("/api/v1/hostel/maintenance/{id}")
    @PreAuthorize(OFFICE)
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody Decision body) {
        return service.decideMaintenance(id, body.state(), body.note());
    }
}
