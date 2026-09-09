package ng.edu.moaum.portal.wallet;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
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
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The student's wallet under /api/v1/me/wallet; the Bursary's NELFUND desk under /api/v1/nelfund. */
@RestController
class WalletController {

    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_admin','OFFICE_super')";
    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_deputyaudit','OFFICE_admin','OFFICE_super','OFFICE_ict','OFFICE_vc','OFFICE_dvc')";

    public record Amount(String session, BigDecimal amount) {
    }

    public record Batch(@NotBlank @Size(max = 60) String ref, String session, LocalDate receivedOn, @Size(max = 400) String note, List<Map<String, Object>> rows) {
    }

    public record Match(@NotBlank @Size(max = 40) String number, @NotBlank @Size(max = 400) String note) {
    }

    public record Why(@NotBlank @Size(max = 400) String why) {
    }

    public record StatusList(String session, List<Map<String, Object>> rows) {
    }

    private final WalletService service;

    WalletController(WalletService service) {
        this.service = service;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    /* ── the student ── */

    @GetMapping("/api/v1/me/wallet")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> mine(Authentication auth, @RequestParam(required = false) String session) {
        return service.mine(student(auth), session);
    }

    @PostMapping("/api/v1/me/wallet/apply")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> apply(Authentication auth, @RequestBody(required = false) Amount body) {
        return service.apply(student(auth), body == null ? null : body.session(), body == null ? null : body.amount());
    }

    @PostMapping("/api/v1/me/wallet/topup-reference")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> topup(Authentication auth, @Valid @RequestBody Amount body) {
        return service.topup(student(auth), body.session(), body.amount());
    }

    /* ── the Bursary ── */

    @GetMapping("/api/v1/nelfund/sessions/{s}/{y}")
    @PreAuthorize(READERS)
    Map<String, Object> desk(@PathVariable String s, @PathVariable String y) {
        return service.desk(s + "/" + y);
    }

    @PostMapping("/api/v1/nelfund/batches")
    @PreAuthorize(BURSARY)
    Map<String, Object> load(@Valid @RequestBody Batch body) {
        return service.load(body.ref(), body.session(), body.receivedOn(), body.note(), body.rows());
    }

    @PostMapping("/api/v1/nelfund/rows/{id}/match")
    @PreAuthorize("hasAnyAuthority('OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_super')")
    Map<String, Object> match(@PathVariable UUID id, @Valid @RequestBody Match body) {
        return service.match(id, body.number(), body.note());
    }

    @PostMapping("/api/v1/nelfund/rows/{id}/reverse")
    @PreAuthorize(BURSARY)
    Map<String, Object> reverse(@PathVariable UUID id, @Valid @RequestBody Why body) {
        return service.reverse(id, body.why());
    }

    @PostMapping("/api/v1/nelfund/status")
    @PreAuthorize(BURSARY)
    Map<String, Object> status(@RequestBody StatusList body) {
        return service.loadStatus(body.session(), body.rows());
    }
}
