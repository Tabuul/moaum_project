package ng.edu.moaum.portal.student;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * The whole of one person's record, assembled from the modules that own each
 * part of it and copied into none of them: the register line, the biodata as
 * the field list defines it, the documents the Registry holds, the status
 * history, the enrolments, this session's registrations, where clearance
 * stands, and what is waiting on the Registry's decision.
 */
record StudentRecord(StudentRow student,
                     List<BiodataField> biodata,
                     List<Document> documents,
                     List<StatusEntry> statusHistory,
                     List<Enrolment> enrolments,
                     List<Registration> registrations,
                     List<Clearance> convocationClearance,
                     List<Clearance> registrationClearance,
                     List<PendingChange> pendingChanges,
                     List<DecidedChange> decidedChanges,
                     int approvedUnits) {

    /**
     * One field of the biodata: what {@code ref.biodata_field} says it is,
     * and the value where one has been recorded. A field with no value is
     * still a field — the record shows what is missing.
     */
    record BiodataField(String field, String section, String label, String tier, String hint,
                        boolean wide, int ord, String value) {
    }

    record Document(UUID id, String kind, String detail, String source, LocalDate receivedOn, String status) {
    }

    record StatusEntry(UUID id, String fromStatus, String toStatus, String instrument,
                       LocalDate effectiveOn, String reason) {
    }

    record Enrolment(String session, int level, String mode, String feeCategory, OffsetDateTime enrolledAt) {
    }

    record Registration(UUID id, String session, int semester, int level, String status,
                        int units, OffsetDateTime submittedAt) {
    }

    /** One unit's latest word on one candidate, for one purpose (clearance.position). */
    record Clearance(String unit, String label, String state, String item, OffsetDateTime decidedAt, int ord) {
    }

    record PendingChange(UUID id, String field, String label, String fromValue, String toValue,
                         String evidence, OffsetDateTime requestedAt, String state) {
    }

    /**
     * A request the Registry has answered. Both answers are kept: a refusal
     * is as much a decision as an approval, and the student sees both in
     * their own change history.
     */
    record DecidedChange(UUID id, String field, String label, String fromValue, String toValue,
                         String evidence, OffsetDateTime requestedAt, String state,
                         String decision, OffsetDateTime decidedAt) {
    }
}
