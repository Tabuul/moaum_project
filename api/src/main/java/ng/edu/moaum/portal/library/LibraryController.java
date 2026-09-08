package ng.edu.moaum.portal.library;

import java.math.BigDecimal;
import java.util.List;
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

/** The student's Library screen under /api/v1/me/library; the circulation desk under /api/v1/library. */
@RestController
class LibraryController {

    private static final String DESK = "hasAnyAuthority('OFFICE_library','OFFICE_services','OFFICE_admin','OFFICE_super')";
    private static final String READERS = "hasAnyAuthority('OFFICE_library','OFFICE_services','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_bursar','OFFICE_admin','OFFICE_super','OFFICE_ict','OFFICE_audit')";

    public record Issue(@NotBlank @Size(max = 20) String accession, @NotBlank @Size(max = 40) String patron) {
    }

    public record Accession(@NotBlank @Size(max = 20) String accession) {
    }

    public record Why(@NotBlank @Size(max = 400) String why) {
    }

    public record Setting(Integer loanDays, BigDecimal finePerDay, Integer maxLoans, Integer maxRenewals) {
    }

    public record Item(UUID id, @NotBlank @Size(max = 300) String title, @Size(max = 300) String author, @Size(max = 60) String edition, Integer year,
                       @Size(max = 20) String isbn, @Size(max = 120) String subject, String kind, List<String> accessions, @Size(max = 60) String location) {
    }

    public record Reserve(@NotNull UUID itemId) {
    }

    private final LibraryService service;

    LibraryController(LibraryService service) {
        this.service = service;
    }

    private static UUID student(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    /* ── the student ── */

    @GetMapping("/api/v1/me/library")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> mine(Authentication auth, @RequestParam(required = false) String q) {
        return service.mine(student(auth), q);
    }

    @PostMapping("/api/v1/me/library/loans/{id}/renew")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> renew(Authentication auth, @PathVariable UUID id) {
        return service.renew(student(auth), id);
    }

    @PostMapping("/api/v1/me/library/loans/{id}/fine-reference")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> fineReference(Authentication auth, @PathVariable UUID id) {
        return service.fineReference(student(auth), id);
    }

    @PostMapping("/api/v1/me/library/reservations")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> reserve(Authentication auth, @Valid @RequestBody Reserve body) {
        return service.reserve(student(auth), body.itemId());
    }

    /* ── the desk ── */

    @GetMapping("/api/v1/library/desk")
    @PreAuthorize(READERS)
    Map<String, Object> desk(@RequestParam(required = false) String patron, @RequestParam(required = false) String q) {
        return service.desk(patron, q);
    }

    @PostMapping("/api/v1/library/loans")
    @PreAuthorize(DESK)
    Map<String, Object> issue(@Valid @RequestBody Issue body) {
        return service.issue(body.accession(), body.patron());
    }

    @PostMapping("/api/v1/library/returns")
    @PreAuthorize(DESK)
    Map<String, Object> giveBack(@Valid @RequestBody Accession body) {
        return service.giveBack(body.accession());
    }

    @PostMapping("/api/v1/library/loans/{id}/renew")
    @PreAuthorize(DESK)
    Map<String, Object> renewAtDesk(@PathVariable UUID id) {
        return service.renewAtDesk(id);
    }

    @PostMapping("/api/v1/library/loans/{id}/waive")
    @PreAuthorize("hasAnyAuthority('OFFICE_library','OFFICE_super')")
    Map<String, Object> waive(@PathVariable UUID id, @Valid @RequestBody Why body) {
        return service.waive(id, body.why());
    }

    @PutMapping("/api/v1/library/setting")
    @PreAuthorize("hasAnyAuthority('OFFICE_library','OFFICE_super')")
    Map<String, Object> setting(@RequestBody Setting body) {
        return service.putSetting(body.loanDays(), body.finePerDay(), body.maxLoans(), body.maxRenewals());
    }

    @PutMapping("/api/v1/library/items")
    @PreAuthorize(DESK)
    Map<String, Object> item(@Valid @RequestBody Item body) {
        return service.putItem(body.id(), body.title(), body.author(), body.edition(), body.year(), body.isbn(), body.subject(), body.kind(), body.accessions(), body.location());
    }
}
