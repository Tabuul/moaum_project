package ng.edu.moaum.portal.student;

import java.time.LocalDate;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The register, one record, and the two writes the Academic Office makes to
 * it. The rule this service exists to hold is the tier: a field is the
 * student's own, or it is read from JAMB, or it changes only on evidence the
 * Registry has seen — and which of the three it is decides what a write to
 * it does, here rather than in a form.
 */
@Service
public class StudentService {

    private final StudentRepository students;

    StudentService(StudentRepository students) {
        this.students = students;
    }

    public record BiodataIn(@NotNull @Size(max = 4000) String value, @Size(max = 2000) String evidence) {
    }

    public record StatusIn(@NotBlank @Size(max = 40) String to,
                           @NotBlank @Size(max = 200) String instrument,
                           LocalDate effectiveOn,
                           @Size(max = 2000) String reason) {
    }

    /** What a write to one field did: the value it wrote, or the request it raised. */
    public record BiodataWritten(String field, String tier, String value, UUID changeId, boolean pending) {
    }

    public record Intake(String session, int broughtOnto) {
    }

    @Transactional(readOnly = true)
    StudentRow.Register register(Scope scope, String q) {
        return new StudentRow.Register(students.register(scope, q == null || q.isBlank() ? null : q.trim()),
                students.total());
    }

    /** The whole record, assembled from the modules that own each part of it. */
    @Transactional(readOnly = true)
    StudentRecord record(UUID id, String session) {
        StudentRow row = students.student(id).orElseThrow(() -> new NotFound("student", id));
        return new StudentRecord(row,
                students.biodata(id),
                students.documents(id),
                students.statusHistory(id),
                students.enrolments(id),
                students.registrations(id, session),
                students.clearance(id, "CONVOCATION"),
                students.clearance(id, "REGISTRATION"),
                students.pendingChanges(id),
                students.decidedChanges(id),
                students.approvedUnits(id));
    }

    /**
     * Open: written straight away. On approval: a request, with the value on
     * the record as it stands attached to it. Locked: refused, and the
     * refusal says where the correction is actually made.
     */
    @Transactional
    BiodataWritten writeBiodata(UUID id, String field, BiodataIn in) {
        students.student(id).orElseThrow(() -> new NotFound("student", id));
        String tier = students.tierOf(field).orElseThrow(() -> new NotFound("biodata field", field));
        String value = in.value().trim();
        if ("locked".equals(tier)) {
            throw new DomainRuleViolation("STU_FIELD_LOCKED",
                    "This field is read from the JAMB record and is not changed on the portal. "
                            + "Correcting it here would put one name on the portal and another on the degree.",
                    new DomainRuleViolation.Remedy("Corrected with JAMB, not here", "Academic Office"));
        }
        if ("approval".equals(tier)) {
            if (value.isEmpty()) {
                throw new DomainRuleViolation("STU_VALUE_REQUIRED",
                        "A change request carries the value asked for, and none was given.",
                        new DomainRuleViolation.Remedy("Type the new value before asking for the change.", "Academic Office"));
            }
            String from = students.valueOf(id, field).orElse(null);
            UUID change = students.askForChange(id, field, from, value, blankToNull(in.evidence()));
            return new BiodataWritten(field, tier, value, change, true);
        }
        students.writeBiodata(id, field, value);
        return new BiodataWritten(field, tier, value, null, false);
    }

    /** A change of status is made on an instrument; the database refuses one without. */
    @Transactional
    StudentRecord changeStatus(UUID id, StatusIn in, String session) {
        students.student(id).orElseThrow(() -> new NotFound("student", id));
        students.changeStatus(id, in.to().trim(), in.instrument().trim(),
                in.effectiveOn() == null ? LocalDate.now() : in.effectiveOn(), blankToNull(in.reason()));
        return record(id, session);
    }

    /** Bringing a session's admitted candidates onto the register, each with an admission number. */
    @Transactional
    Intake intake(String session) {
        return new Intake(session, students.intake(session));
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
