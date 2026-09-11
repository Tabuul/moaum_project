package ng.edu.moaum.portal.admissions;

import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** The admission settings, per session. Read by every admissions office; written by the Committee's secretariat. */
@RestController
@RequestMapping("/api/v1/admissions")
class AdmissionSettingsController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records','OFFICE_dean','OFFICE_hod','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String SECRETARIAT = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    private final AdmissionSettingsService service;

    AdmissionSettingsController(AdmissionSettingsService service) {
        this.service = service;
    }

    @GetMapping("/policies")
    @PreAuthorize(READERS)
    List<AdmissionPolicy.Summary> policies() {
        return service.policies();
    }

    /** The session's admission settings: the cut-offs that apply, and whether they are in force. */
    @GetMapping("/sessions/{session}/{year}/policy")
    @PreAuthorize(READERS)
    AdmissionPolicy policy(@PathVariable String session, @PathVariable String year) {
        return service.policy(session + "/" + year);
    }

    @PutMapping("/sessions/{session}/{year}/policy")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy save(@PathVariable String session, @PathVariable String year,
                         @Valid @RequestBody AdmissionSettingsService.PolicySettings body) {
        return service.save(session + "/" + year, body);
    }

    @PutMapping("/sessions/{session}/{year}/policy/criteria")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy criteria(@PathVariable String session, @PathVariable String year, @RequestBody Map<String, Integer> body) {
        return service.saveCriteria(session + "/" + year, body);
    }

    @PutMapping("/sessions/{session}/{year}/policy/faculties/{code}")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy faculty(@PathVariable String session, @PathVariable String year, @PathVariable String code,
                            @Valid @RequestBody AdmissionSettingsService.FacultyQuotaIn body) {
        return service.saveFaculty(session + "/" + year, code, body);
    }

    @PutMapping("/sessions/{session}/{year}/policy/programmes/{code}")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy programme(@PathVariable String session, @PathVariable String year, @PathVariable String code,
                              @Valid @RequestBody AdmissionSettingsService.ProgrammeRuleIn body) {
        return service.saveProgrammeRule(session + "/" + year, code, body);
    }

    public record QuotaIn(Integer quota) {
    }

    /* ── capacity, editable in force: a quota is places, not a qualification rule; the NUC ceiling
       can rise mid-cycle and the Deans redistribute it, so these are allowed whether the policy is a draft
       or in force. Cut-offs, weights, ratios and subject rules stay on the draft-only endpoints above. */

    @PutMapping("/sessions/{session}/{year}/policy/nuc-quota")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy nucQuota(@PathVariable String session, @PathVariable String year, @RequestBody QuotaIn body) {
        return service.setNucQuota(session + "/" + year, body.quota());
    }

    @PutMapping("/sessions/{session}/{year}/policy/faculties/{code}/quota")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy facultyQuota(@PathVariable String session, @PathVariable String year, @PathVariable String code, @RequestBody QuotaIn body) {
        return service.setFacultyQuota(session + "/" + year, code, body.quota());
    }

    @PutMapping("/sessions/{session}/{year}/policy/programmes/{code}/quota")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy programmeQuota(@PathVariable String session, @PathVariable String year, @PathVariable String code, @RequestBody QuotaIn body) {
        return service.setProgrammeQuota(session + "/" + year, code, body.quota());
    }

    public record CutoffIn(Integer cutoff) {
    }

    /** a programme's own UTME cut-off, editable in force like its quota — the settings are by programme, not faculty */
    @PutMapping("/sessions/{session}/{year}/policy/programmes/{code}/cutoff")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy programmeCutoff(@PathVariable String session, @PathVariable String year, @PathVariable String code, @RequestBody CutoffIn body) {
        return service.setProgrammeCutoff(session + "/" + year, code, body.cutoff());
    }

    public record Catchment(java.util.List<@jakarta.validation.constraints.Size(max = 120) String> lgas) {
    }

    /** the catchment local governments, for the Locality basis (V054) — replaces the set */
    @PutMapping("/sessions/{session}/{year}/policy/catchment")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy catchment(@PathVariable String session, @PathVariable String year, @RequestBody Catchment body) {
        return service.saveCatchment(session + "/" + year, body.lgas());
    }

    public record Closure(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 400) String reason) {
    }

    public record LoadCutoff(@jakarta.validation.constraints.NotNull Integer cutoff) {
    }

    /** the general UTME cut-off the session loads its JAMB lists under (V024) */
    @GetMapping("/sessions/{session}/{year}/load-cutoff")
    @PreAuthorize(READERS)
    Map<String, Object> loadCutoff(@PathVariable String session, @PathVariable String year) {
        return service.loadCutoff(session + "/" + year);
    }

    @PutMapping("/sessions/{session}/{year}/load-cutoff")
    @PreAuthorize(SECRETARIAT)
    Map<String, Object> stateLoadCutoff(@PathVariable String session, @PathVariable String year, @Valid @RequestBody LoadCutoff body) {
        return service.stateLoadCutoff(session + "/" + year, body.cutoff());
    }

    /** closed for the session: not admitted into, needs no rule (V023) */
    @PostMapping("/sessions/{session}/{year}/policy/programmes/{code}/close")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy close(@PathVariable String session, @PathVariable String year, @PathVariable String code,
                          @Valid @RequestBody Closure body) {
        return service.closeProgramme(session + "/" + year, code, body.reason());
    }

    @PostMapping("/sessions/{session}/{year}/policy/programmes/{code}/reopen")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy reopen(@PathVariable String session, @PathVariable String year, @PathVariable String code) {
        return service.reopenProgramme(session + "/" + year, code);
    }

    @PostMapping("/sessions/{session}/{year}/policy/put-in-force")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy putInForce(@PathVariable String session, @PathVariable String year,
                               @Valid @RequestBody AdmissionSettingsService.Instrument body) {
        return service.putInForce(session + "/" + year, body.instrument());
    }

    @PostMapping("/sessions/{session}/{year}/policy/start-from/{fromSession}/{fromYear}")
    @PreAuthorize(SECRETARIAT)
    AdmissionPolicy startFrom(@PathVariable String session, @PathVariable String year,
                              @PathVariable String fromSession, @PathVariable String fromYear) {
        return service.startFrom(session + "/" + year, fromSession + "/" + fromYear);
    }
}
