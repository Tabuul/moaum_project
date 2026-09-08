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
import org.springframework.web.bind.annotation.PutMapping;
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
    ResponseEntity<CapsLoadResult> load(@Valid @RequestBody NewCapsBatch request) {
        CapsLoadResult result = intake.load(request);
        return ResponseEntity.created(URI.create("/api/v1/admissions/caps-batches/" + result.batch().id())).body(result);
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

    record Withdrawal(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 400) String reason) {
    }

    /** A list loaded in error: kept as evidence, marked withdrawn for the reason given, and out of every count. */
    @PostMapping("/caps-batches/{id}/withdraw")
    @PreAuthorize(LOADERS)
    Map<String, Object> withdraw(@PathVariable UUID id, @Valid @RequestBody Withdrawal request) {
        String outcome = intake.withdraw(id, request.reason());
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

    record NewAlias(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 200) String jambName) {
    }

    /** What JAMB calls this programme — the name a CAPS download is matched on. */
    @PutMapping("/programmes/{code}/jamb-alias")
    @PreAuthorize(LOADERS)
    Programme jambAlias(@PathVariable String code, @Valid @RequestBody NewAlias request) {
        return intake.setJambAlias(code, request.jambName());
    }

    record ProgrammeEdit(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 200) String name,
                         @jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 10) String deptCode,
                         @jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 20) String category,
                         boolean archived) {
    }

    /** The University's own words for a programme; the code is for ever, and JAMB's name is set separately. */
    @PutMapping("/programmes/{code}")
    @PreAuthorize(LOADERS)
    Programme editProgramme(@PathVariable String code, @Valid @RequestBody ProgrammeEdit request) {
        return intake.editProgramme(code, request.name(), request.deptCode(), request.category(), request.archived());
    }

    /** {@code ?in=202699168863AH_Face.jpg} → the number the database reads out of it, or none. */
    @GetMapping("/reg-no")
    @PreAuthorize(READERS)
    Map<String, Object> regNo(@RequestParam("in") String text) {
        return Map.of("in", text, "regNo", intake.regNoIn(text).orElse(""));
    }
}
