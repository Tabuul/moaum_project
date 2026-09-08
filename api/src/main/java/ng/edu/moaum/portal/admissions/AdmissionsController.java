package ng.edu.moaum.portal.admissions;

import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admissions")
class AdmissionsController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String LOADERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar')";

    private final CapsIntakeService intake;

    AdmissionsController(CapsIntakeService intake) {
        this.intake = intake;
    }

    @PostMapping("/caps-batches")
    @PreAuthorize(LOADERS)
    ResponseEntity<CapsBatch> load(@Valid @RequestBody NewCapsBatch request) {
        CapsBatch batch = intake.load(request);
        return ResponseEntity.created(URI.create("/api/v1/admissions/caps-batches/" + batch.id())).body(batch);
    }

    @GetMapping("/caps-batches")
    @PreAuthorize(READERS)
    List<CapsBatch> list(@RequestParam String session) {
        return intake.bySession(session);
    }

    @GetMapping("/caps-batches/{id}")
    @PreAuthorize(READERS)
    CapsBatch get(@PathVariable UUID id) {
        return intake.get(id);
    }

    @PostMapping("/caps-batches/{id}/commit")
    @PreAuthorize(LOADERS)
    Map<String, Object> commit(@PathVariable UUID id) {
        String outcome = intake.commit(id);
        return Map.of("batchId", id, "outcome", outcome);
    }

    @GetMapping("/sessions/{session}/{year}/reconciliation")
    @PreAuthorize(READERS)
    List<Finding> reconciliation(@PathVariable String session, @PathVariable String year) {
        return intake.reconcile(session + "/" + year);
    }

    @GetMapping("/sessions/{session}/{year}/attachments")
    @PreAuthorize(READERS)
    List<Finding> attachments(@PathVariable String session, @PathVariable String year) {
        return intake.attachmentState(session + "/" + year);
    }

    @GetMapping("/sessions/{session}/{year}/policy-findings")
    @PreAuthorize(READERS)
    List<PolicyFinding> policy(@PathVariable String session, @PathVariable String year) {
        return intake.policyFindings(session + "/" + year);
    }

    /** The programmes and their JAMB names, so a list can be resolved before it is loaded. */
    @GetMapping("/programmes")
    @PreAuthorize(READERS)
    List<Programme> programmes() {
        return intake.programmes();
    }

    /** {@code ?in=202699168863AH_Face.jpg} → the number the database reads out of it, or none. */
    @GetMapping("/reg-no")
    @PreAuthorize(READERS)
    Map<String, Object> regNo(@RequestParam("in") String text) {
        return Map.of("in", text, "regNo", intake.regNoIn(text).orElse(""));
    }
}
