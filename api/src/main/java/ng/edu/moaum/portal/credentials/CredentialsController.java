package ng.edu.moaum.portal.credentials;

import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/credentials")
class CredentialsController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String OFFICE = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records')";
    private static final String SIGNERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic')";

    private final CredentialsService service;

    CredentialsController(CredentialsService service) {
        this.service = service;
    }

    @GetMapping("/transcript-requests")
    @PreAuthorize(READERS)
    Credentials.TranscriptQueue transcripts() {
        return service.transcripts();
    }

    @PostMapping("/transcript-requests")
    @PreAuthorize(OFFICE)
    Credentials.Transcript request(@Valid @RequestBody CredentialsService.TranscriptIn body) {
        return service.request(body);
    }

    @PostMapping("/transcript-requests/{id}/mark-paid")
    @PreAuthorize(SIGNERS)
    Credentials.Transcript markPaid(@PathVariable UUID id) {
        return service.markPaid(id);
    }

    @PostMapping("/transcript-requests/{id}/produce")
    @PreAuthorize(OFFICE)
    Credentials.Transcript produce(@PathVariable UUID id) {
        return service.produce(id);
    }

    @PostMapping("/transcript-requests/{id}/release")
    @PreAuthorize(SIGNERS)
    Credentials.Transcript release(@PathVariable UUID id) {
        return service.release(id);
    }

    @GetMapping("/certificates")
    @PreAuthorize(READERS)
    Credentials.CertificateRegister certificates(@RequestParam(required = false) String convocation) {
        return service.register(convocation == null || convocation.isBlank() ? null : convocation);
    }

    @PostMapping("/certificates")
    @PreAuthorize(OFFICE)
    Credentials.Certificate print(@Valid @RequestBody CredentialsService.PrintIn body) {
        return service.print(body);
    }

    @PostMapping("/certificates/{id}/collect")
    @PreAuthorize(OFFICE)
    Credentials.Certificate collect(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> body) {
        return service.collect(id, body == null ? null : body.get("note"));
    }

    @PostMapping("/certificates/{id}/hold")
    @PreAuthorize(OFFICE)
    Credentials.Certificate hold(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> body) {
        return service.hold(id, body == null ? null : body.get("reason"));
    }

    @PostMapping("/certificates/{id}/reissue")
    @PreAuthorize(SIGNERS)
    Credentials.Certificate reissue(@PathVariable UUID id, @RequestBody(required = false) Map<String, String> body) {
        String batch = body == null ? null : body.get("batchId");
        return service.reissue(id, body == null ? null : body.get("reason"), batch == null || batch.isBlank() ? null : UUID.fromString(batch));
    }

    @PostMapping("/stationery")
    @PreAuthorize(OFFICE)
    Credentials.Batch batch(@Valid @RequestBody CredentialsService.BatchIn body) {
        return service.batch(body);
    }

    @PostMapping("/stationery/{id}/spoil")
    @PreAuthorize(OFFICE)
    Credentials.Batch spoil(@PathVariable UUID id, @RequestBody Map<String, Integer> body) {
        return service.count(id, "spoil", body.getOrDefault("count", 0));
    }

    @PostMapping("/stationery/{id}/return")
    @PreAuthorize(OFFICE)
    Credentials.Batch giveBack(@PathVariable UUID id, @RequestBody Map<String, Integer> body) {
        return service.count(id, "return", body.getOrDefault("count", 0));
    }
}
