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
