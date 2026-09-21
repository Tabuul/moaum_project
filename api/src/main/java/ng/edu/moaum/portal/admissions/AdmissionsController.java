package ng.edu.moaum.portal.admissions;

import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
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

    /** a large download arrives in several requests: the rows join the batch the first request opened */
    @PostMapping("/caps-batches/{id}/rows")
    @PreAuthorize(LOADERS)
    CapsLoadResult append(@PathVariable UUID id, @Valid @RequestBody CapsRowsIn request) {
        return intake.appendRows(id, request.rows());
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

    /** the applicants on committed admission lists — the admitted pool, and who has registered for post-UTME */
    @GetMapping("/applicants")
    @PreAuthorize(READERS)
    Map<String, Object> applicants(@RequestParam String session,
                                   @RequestParam(required = false) String q,
                                   @RequestParam(required = false) String faculty,
                                   @RequestParam(required = false) String programme,
                                   @RequestParam(required = false) String entryMode,
                                   @RequestParam(defaultValue = "200") int limit) {
        return intake.applicants(session, q, faculty, programme, entryMode, limit);
    }

    /** the merit list for a programme: the eligible pool ranked, with the proposed offer that fills the quota */
    @GetMapping("/merit")
    @PreAuthorize(READERS)
    Map<String, Object> merit(@RequestParam String session, @RequestParam String programme) {
        return intake.meritList(session, programme);
    }

    /** the programmes registered for post-UTME and their score-upload status — which programmes'
     *  scores must be uploaded before the admission process proceeds */
    @GetMapping("/post-utme-programmes")
    @PreAuthorize(READERS)
    Map<String, Object> postUtmeProgrammes(@RequestParam String session) {
        return intake.postUtmeProgrammes(session);
    }

    public record MeritRecord(@jakarta.validation.constraints.NotBlank String session, @jakarta.validation.constraints.NotBlank String programme) {
    }

    /** Clear a CAPS upload and start the intake again: deletes the JAMB list, candidates, O'Level and
     *  applicant intake for the session, keeps the admission config and every student on the register. */
    @PostMapping("/sessions/{session}/{year}/reset-intake")
    @PreAuthorize(LOADERS)
    Map<String, Object> resetIntake(@PathVariable String session, @PathVariable String year) {
        return intake.resetIntake(session + "/" + year);
    }

    @PostMapping("/merit/record")
    @PreAuthorize(LOADERS)
    Map<String, Object> recordMerit(@jakarta.validation.Valid @RequestBody MeritRecord body) {
        return intake.recordMerit(body.session(), body.programme());
    }

    public record MeritRecordMany(@jakarta.validation.constraints.NotBlank String session, List<String> programmes) {
    }

    /** record the merit list for several programmes at once — all with a pool when none are named */
    @PostMapping("/merit/record-many")
    @PreAuthorize(LOADERS)
    Map<String, Object> recordMeritMany(@jakarta.validation.Valid @RequestBody MeritRecordMany body) {
        return intake.recordMeritMany(body.session(), body.programmes());
    }

    /** Direct Entry screening for a programme: the DE applicants with the subject gate's verdict (V200).
     *  Screening-only — separate from the UTME merit list and from the offer decision. */
    @GetMapping("/de-screening")
    @PreAuthorize(READERS)
    Map<String, Object> deScreening(@RequestParam String session, @RequestParam String programme) {
        return intake.deScreening(session, programme);
    }

    /** the Direct Entry awards captured for a candidate — the basis and its subjects (V200) */
    @GetMapping("/de-awards")
    @PreAuthorize(READERS)
    List<Map<String, Object>> deAwards(@RequestParam String session, @RequestParam String jambKey) {
        return intake.deAwards(session, jambKey);
    }

    public record DeSubjectIn(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 80) String subject,
                              @jakarta.validation.constraints.Size(max = 20) String grade) {
    }

    public record DeAwardIn(@jakarta.validation.constraints.NotBlank String session,
                            @jakarta.validation.constraints.NotBlank String jambKey,
                            @jakarta.validation.constraints.Pattern(regexp = "A_LEVEL|IJMB|JUPEB|NCE|ND|HND",
                                    message = "basis must be one of A_LEVEL, IJMB, JUPEB, NCE, ND, HND") String basis,
                            @jakarta.validation.constraints.Min(1960) @jakarta.validation.constraints.Max(2100) Integer awardedYear,
                            @jakarta.validation.constraints.Size(max = 200) String institution,
                            @jakarta.validation.constraints.NotNull @Valid List<DeSubjectIn> subjects) {
    }

    /** record (replace whole) a candidate's Direct Entry award and its subjects; returns the candidate's awards (V200) */
    @PostMapping("/de-awards")
    @PreAuthorize(LOADERS)
    List<Map<String, Object>> recordDeAward(@Valid @RequestBody DeAwardIn body) {
        List<Map<String, String>> subs = body.subjects().stream()
                .map(s -> Map.of("subject", s.subject(), "grade", s.grade() == null ? "" : s.grade()))
                .toList();
        return intake.recordDeAward(body.session(), body.jambKey(), body.basis(), body.awardedYear(), body.institution(), subs);
    }

    /** remove one Direct Entry award (V200) */
    @DeleteMapping("/de-awards/{id}")
    @PreAuthorize(LOADERS)
    Map<String, Object> deleteDeAward(@PathVariable UUID id) {
        intake.deleteDeAward(id);
        return Map.of("deleted", true);
    }

    record JambRows(@jakarta.validation.constraints.NotNull List<Map<String, Object>> rows) {
    }

    /** The admission-status list downloaded from JAMB: matched by registration number; the accepted are offered and released here. */
    @PostMapping("/sessions/{session}/{year}/jamb-admissions")
    @PreAuthorize(LOADERS)
    Map<String, Object> loadJambAdmissions(@PathVariable String session, @PathVariable String year, @Valid @RequestBody JambRows body) {
        return intake.loadJambAdmissions(session + "/" + year, body.rows());
    }

    @GetMapping("/sessions/{session}/{year}/jamb-admissions")
    @PreAuthorize(READERS)
    Map<String, Object> jambAdmissions(@PathVariable String session, @PathVariable String year) {
        return intake.jambAdmissions(session + "/" + year);
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
