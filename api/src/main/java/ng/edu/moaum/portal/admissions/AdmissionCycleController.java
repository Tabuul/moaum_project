package ng.edu.moaum.portal.admissions;

import java.util.ArrayList;
import java.util.List;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** The admission cycle as the register shows it: applications, offers, acceptances, and who is on the register. */
@RestController
@RequestMapping("/api/v1/admissions")
class AdmissionCycleController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_records',"
            + "'OFFICE_dean','OFFICE_hod','OFFICE_ict','OFFICE_admin','OFFICE_super')";

    private final AdmissionCycleRepository cycle;
    private final CapsIntakeService intake;

    AdmissionCycleController(AdmissionCycleRepository cycle, CapsIntakeService intake) {
        this.cycle = cycle;
        this.intake = intake;
    }

    @GetMapping("/sessions/{session}/{year}/cycle")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    AdmissionCycle cycle(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        AdmissionCycle.Counts c = cycle.counts(s);
        boolean inForce = cycle.inForce(s);
        List<AdmissionCycle.ProgrammeLine> lines = new ArrayList<>();
        for (AdmissionCycle.ProgrammeRow p : cycle.programmes(s, inForce)) {
            String stage = !inForce ? "Awaiting settings"
                    : p.quota() != null && p.offered() > p.quota() ? "Over quota"
                    : p.quota() != null && p.offered() < p.quota() ? "Under quota"
                    : "Settings in force";
            lines.add(new AdmissionCycle.ProgrammeLine(p.code(), p.name(), p.facultyCode(), p.facultyName(), p.applied(), p.quota(),
                    p.offered(), p.accepted(), p.cutoff(), stage));
        }
        return new AdmissionCycle(s, c.applications(), c.screened(), c.offers(), c.accepted(), c.onTheRegister(), c.notYetOnRegister(),
                cycle.capacity(s).orElse(null), inForce, lines, intake.reconcile(s));
    }
}
