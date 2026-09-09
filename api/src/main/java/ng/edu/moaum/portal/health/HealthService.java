package ng.edu.moaum.portal.health;

import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class HealthService {

    private static final List<String> TRIAGE = List.of("URGENT", "STANDARD", "ROUTINE");
    private static final List<String> FITNESS = List.of("FIT", "UNFIT", "FIT_WITH_CONDITIONS", "PENDING");

    private final HealthRepository repo;

    HealthService(HealthRepository repo) {
        this.repo = repo;
    }

    private static AuditContext me() {
        return AuditContextHolder.required();
    }

    /* ── the student ── */

    @Transactional(readOnly = true)
    public Map<String, Object> mine(UUID student) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("profile", repo.profile(student).orElse(null));
        out.put("appointments", repo.appointments(student));
        out.put("visits", repo.visits(student));
        out.put("access", repo.accessLog(student));
        return out;
    }

    @Transactional
    public Map<String, Object> book(UUID student, String reason, OffsetDateTime preferred) {
        return Map.of("appointmentId", repo.book(student, reason, preferred), "state", "BOOKED");
    }

    @Transactional
    public Map<String, Object> cancel(UUID student, UUID appointment, String why) {
        repo.cancel(appointment, student, why);
        return Map.of("appointmentId", appointment, "state", "CANCELLED");
    }

    @Transactional
    public Map<String, Object> consent(UUID student, String blood, String genotype, String allergies) {
        repo.consent(student, blood, genotype, allergies);
        return Map.of("consented", true);
    }

    @Transactional
    public Map<String, Object> restrict(UUID student) {
        repo.restrict(student);
        return Map.of("restricted", true);
    }

    /* ── the clinic ── */

    @Transactional(readOnly = true)
    public Map<String, Object> desk(String number) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("tiles", repo.tiles());
        out.put("waiting", repo.waiting());
        out.put("booked", repo.bookedToday());
        out.put("concluded", repo.concludedToday());
        if (number != null && !number.isBlank()) {
            out.put("patron", repo.patron(number.trim()).orElse(null));
        }
        return out;
    }

    @Transactional
    public Map<String, Object> arrive(String number, UUID studentId, String presenting, String triage, UUID appointment) {
        UUID student = studentId;
        if (student == null) {
            student = (UUID) repo.patron(number == null ? "" : number.trim()).orElseThrow(() -> new DomainRuleViolation("HLT_NO_PATIENT",
                    "No student carries the number " + number + ".", new DomainRuleViolation.Remedy("The matriculation or admission number, as issued.", "Clinic"))).get("student_id");
        }
        String t = triage == null || triage.isBlank() ? "STANDARD" : triage.trim().toUpperCase();
        if (!TRIAGE.contains(t)) {
            throw new DomainRuleViolation("HLT_TRIAGE", "Triage is urgent, standard or routine.", new DomainRuleViolation.Remedy("One of the three.", "Clinic"));
        }
        return Map.of("visitId", repo.arrive(student, presenting, t, appointment), "state", "WAITING");
    }

    @Transactional
    public Map<String, Object> open(UUID visit) {
        AuditContext c = me();
        repo.see(visit, c.actorId());
        return repo.open(visit, c.actorId(), c.actorOffice());
    }

    @Transactional
    public Map<String, Object> conclude(UUID visit, String outcome, String referred, String note, String fitness) {
        String f = fitness == null || fitness.isBlank() ? null : fitness.trim().toUpperCase();
        if (f != null && !FITNESS.contains(f)) {
            throw new DomainRuleViolation("HLT_FITNESS", "Fitness is fit, unfit, or fit with conditions.", new DomainRuleViolation.Remedy("One of the three.", "Clinic"));
        }
        repo.conclude(visit, me().actorId(), outcome, referred, note, f);
        return Map.of("visitId", visit, "state", "DONE");
    }
}
