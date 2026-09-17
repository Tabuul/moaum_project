package ng.edu.moaum.portal.registration;

import java.time.LocalDate;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RegistrationService {

    public record CourseIn(@NotBlank String title, @NotNull @Min(0) @Max(12) Integer units, @NotNull @Min(1) @Max(3) Integer semester,
                           @NotNull Integer level, @NotBlank String deptCode, @NotBlank String kind, String state) {
    }

    public record OfferingIn(@NotBlank String courseCode, @NotBlank String session, @NotNull @Min(1) @Max(3) Integer semester,
                             UUID lecturerId, UUID secondExaminerId) {
    }

    public record EntryIn(@NotNull UUID offeringId, @NotNull @Min(0) Integer units, String entryType) {
    }

    public record RegistrationIn(@NotNull UUID studentId, @NotBlank String session, @NotNull @Min(1) @Max(3) Integer semester,
                                 @NotNull Integer level, @NotNull List<EntryIn> entries) {
    }

    private static final Set<String> MAY_GO_LIVE = Set.of("academic", "registrar", "dregistrar", "super");

    private final RegistrationRepository repo;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    RegistrationService(RegistrationRepository repo, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.repo = repo;
        this.scope = scope;
    }

    /** A Head of Department decides only their own department's registrations; a wider office is not confined.
     *  When the acting HOD's department is not resolvable, the check falls through: the approvals list already
     *  shows such an HOD nothing (scopedDept → none), and the role gate still applies, so there is nothing to
     *  confine here. A resolved HOD is held to their own department. */
    private void assertMayDecide(UUID id) {
        if (!scope.actingHod()) {
            return;
        }
        String mine = scope.actingDept();
        if (mine == null) {
            return;
        }
        String regDept = repo.deptOf(id).orElse(null);
        if (!mine.equals(regDept)) {
            throw new DomainRuleViolation("REG_OTHER_DEPT",
                    "This registration is in another department.",
                    new DomainRuleViolation.Remedy("A Head of Department approves only their own department's registrations.", "Registry"));
        }
    }

    @Transactional
    public Map<String, Object> saveCourse(String code, CourseIn c) {
        String office = AuditContextHolder.required().actorOffice();
        String state = c.state() == null ? "BOARD" : c.state();
        if ("LIVE".equals(state) && !MAY_GO_LIVE.contains(office)) {
            throw new DomainRuleViolation("REG_COURSE_NOT_LIVE_BY_DEPARTMENT",
                    "A new course is a curriculum change; the department proposes it and Senate makes it live.",
                    new DomainRuleViolation.Remedy("Submit it at BOARD; the Academic Office records Senate's approval.", "Faculty Board and Senate"));
        }
        repo.upsertCourse(code.trim().toUpperCase(), c, state);
        return Map.of("code", code.trim().toUpperCase(), "state", state);
    }

    @Transactional
    public void endCourse(String code, LocalDate endedOn) {
        if (!repo.courseExists(code)) {
            throw new NotFound("course", code);
        }
        repo.endCourse(code, endedOn == null ? LocalDate.now() : endedOn);
    }

    @Transactional
    public void offer(String course, String programme, int level, String basis) {
        if (!repo.courseExists(course)) {
            throw new NotFound("course", course);
        }
        repo.upsertOffer(course, programme, level, basis == null ? "Core" : basis);
    }

    @Transactional
    public Map<String, Object> offering(OfferingIn o) {
        if (!repo.courseExists(o.courseCode().trim().toUpperCase())) {
            throw new NotFound("course", o.courseCode());
        }
        UUID id = repo.upsertOffering(o);
        return Map.of("id", id);
    }

    @Transactional
    public Map<String, Object> create(RegistrationIn r) {
        UUID id = repo.createRegistration(r);
        return Map.of("id", id, "status", "DRAFT", "units", repo.units(id));
    }

    @Transactional
    public Map<String, Object> submit(UUID id) {
        RegistrationRepository.RegistrationRow r = repo.registration(id).orElseThrow(() -> new NotFound("course registration", id));
        repo.setStatus(id, "SUBMITTED", null);
        return Map.of("id", id, "status", "SUBMITTED", "units", repo.units(id));
    }

    /** The level adviser's or Head of Department's approval: the register grows by this student. */
    @Transactional
    public Map<String, Object> approve(UUID id) {
        RegistrationRepository.RegistrationRow r = repo.registration(id).orElseThrow(() -> new NotFound("course registration", id));
        assertMayDecide(id);
        if (!Set.of("ADMITTED", "ACTIVE", "PROBATION").contains(r.studentStatus())) {
            throw new DomainRuleViolation("REG_STUDENT_NOT_ELIGIBLE",
                    "A student who is " + r.studentStatus().toLowerCase() + " does not register (I-STU-2).",
                    new DomainRuleViolation.Remedy("Only an admitted, active or probation student may register.", "Academic Office"));
        }
        int units = repo.units(id);
        Integer siwes = repo.siwesUnits(id).orElse(null);
        if (siwes != null) {
            // the SIWES / industrial-training semester carries exactly the industrial-training units,
            // not the level's normal 18–24 range (e.g. 300-level science second semester)
            if (units != siwes) {
                throw new DomainRuleViolation("REG_UNITS_OUT_OF_RANGE",
                        "The industrial-training semester carries exactly " + siwes + " units; this registration carries " + units + ".",
                        new DomainRuleViolation.Remedy("This is the SIWES semester — only the industrial-training course is registered.", "Head of Department"));
            }
        } else {
            RegistrationRepository.Limit limit = repo.limit(r.level()).orElse(null);
            if (limit != null && (units < limit.minUnits() || units > limit.maxUnits())) {
                throw new DomainRuleViolation("REG_UNITS_OUT_OF_RANGE",
                        "The registration carries " + units + " units; at " + r.level() + " level the range is "
                                + limit.minUnits() + " to " + limit.maxUnits() + ".",
                        new DomainRuleViolation.Remedy("Add or drop courses to bring it within the range, or obtain an overload approval.",
                                "Head of Department"));
            }
        }
        repo.setStatus(id, "APPROVED", AuditContextHolder.required().actorId());
        return Map.of("id", id, "status", "APPROVED", "units", units);
    }

    @Transactional
    public Map<String, Object> giveBack(UUID id, String comment) {
        repo.registration(id).orElseThrow(() -> new NotFound("course registration", id));
        assertMayDecide(id);
        if (comment == null || comment.isBlank()) {
            throw new DomainRuleViolation("REG_RETURN_SAYS_WHY", "A registration is returned with the reason on the record.",
                    new DomainRuleViolation.Remedy("Say what the student must change.", "Head of Department"));
        }
        repo.setStatus(id, "RETURNED", null);
        return Map.of("id", id, "status", "RETURNED");
    }

    @Transactional(readOnly = true)
    public ClassList classList(String course, String session, int semester) {
        RegistrationRepository.OfferingRow o = repo.offering(course.trim().toUpperCase(), session, semester)
                .orElseThrow(() -> new NotFound("offering of " + course + " in " + session + " semester", semester));
        List<ClassList.Row> rows = repo.roll(o.id());
        int own = 0;
        Set<String> from = new LinkedHashSet<>();
        for (ClassList.Row r : rows) {
            if (r.deptCode().equals(o.deptCode())) {
                own++;
            } else {
                from.add(r.programmeName());
            }
        }
        return new ClassList(o.id(), o.courseCode(), o.courseTitle(), o.units(), o.session(), o.semester(), o.deptCode(),
                o.deptName(), o.lecturer(), rows.size(), own, rows.size() - own, List.copyOf(from), rows);
    }
}
