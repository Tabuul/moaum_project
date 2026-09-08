package ng.edu.moaum.portal.student;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * One request to change a field that changes only on evidence, as the
 * Registry's queue shows it. A refusal is as much a decision as an approval,
 * so the queue counts both, and it counts the days the oldest request has
 * waited: a request that simply sits unanswered is the failure this queue
 * exists to prevent.
 */
record BiodataChangeRow(UUID id, UUID studentId, String surname, String otherNames, String matricNo,
                        String admissionNo, String field, String label, String fromValue, String toValue,
                        String evidence, OffsetDateTime requestedAt, String state, String decision,
                        OffsetDateTime decidedAt) {

    record Counts(int pending, int oldestDays, int approved, int refused, int selfService) {
    }

    record Queue(List<BiodataChangeRow> rows, Counts counts) {
    }

    /** What a decision did: the state it reached, and the value it wrote where it wrote one. */
    record Decided(UUID id, String state, String field, String value) {
    }
}
