package ng.edu.moaum.portal.student;

import java.util.Set;
import java.util.UUID;

import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The Registry side of a biodata change. A refusal is as much a decision as
 * an approval: both are recorded with their reason, and neither is made
 * twice. Approval is the only thing that writes the value onto the record —
 * which is the whole point of the tier.
 */
@Service
class ChangeService {

    private static final Set<String> DECIDED = Set.of("APPROVED", "REFUSED");

    private final ChangeRepository changes;
    private final StudentRepository students;

    ChangeService(ChangeRepository changes, StudentRepository students) {
        this.changes = changes;
        this.students = students;
    }

    record DecisionIn(@Size(max = 2000) String decision) {
    }

    @Transactional(readOnly = true)
    BiodataChangeRow.Queue queue(String state) {
        return new BiodataChangeRow.Queue(changes.queue(state == null || state.isBlank() ? null : state.trim()),
                changes.counts());
    }

    @Transactional
    BiodataChangeRow.Decided approve(UUID id, DecisionIn in) {
        BiodataChangeRow row = open(id);
        String decision = decision(in);
        changes.decide(id, "APPROVED", decision);
        students.writeBiodata(row.studentId(), row.field(), row.toValue());
        return new BiodataChangeRow.Decided(id, "APPROVED", row.field(), row.toValue());
    }

    @Transactional
    BiodataChangeRow.Decided refuse(UUID id, DecisionIn in) {
        BiodataChangeRow row = open(id);
        changes.decide(id, "REFUSED", decision(in));
        return new BiodataChangeRow.Decided(id, "REFUSED", row.field(), null);
    }

    /** Asking for the document is not a decision; the request stays in the queue. */
    @Transactional
    BiodataChangeRow.Decided askForEvidence(UUID id) {
        BiodataChangeRow row = open(id);
        changes.askForEvidence(id);
        return new BiodataChangeRow.Decided(id, "EVIDENCE_ASKED", row.field(), null);
    }

    private BiodataChangeRow open(UUID id) {
        BiodataChangeRow row = changes.one(id).orElseThrow(() -> new NotFound("biodata change", id));
        if (DECIDED.contains(row.state())) {
            throw new DomainRuleViolation("STU_CHANGE_DECIDED",
                    "This request was already " + row.state().toLowerCase() + ". A decision is made once, and stands on the record.",
                    new DomainRuleViolation.Remedy(
                            "If the decision was wrong, the student asks again and the new request carries the reason.",
                            "Academic Office"));
        }
        return row;
    }

    private String decision(DecisionIn in) {
        String decision = in == null || in.decision() == null ? "" : in.decision().trim();
        if (decision.isEmpty()) {
            throw new DomainRuleViolation("STU_DECISION_REQUIRED",
                    "A decision on a biodata change is recorded with its reason, and none was given.",
                    new DomainRuleViolation.Remedy(
                            "Say what was seen, or why the request is refused. The student sees this in their change history.",
                            "Academic Office"));
        }
        return decision;
    }
}
