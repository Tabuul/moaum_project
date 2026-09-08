package ng.edu.moaum.portal.clearance;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public final class Clearance {

    private Clearance() {
    }

    public record Unit(String code, String label, String clearsAgainst, String holdsFor, String typicalReason, String officeCode, int ord) {
    }

    public record Position(String unit, String label, String state, String item, UUID officerId, String officer,
                           OffsetDateTime decidedAt, String note, int ord) {
    }

    public record Candidate(UUID id, String number, String surname, String otherNames, String programmeName, String deptName,
                            String facultyCode, int level, List<String> states, boolean cleared) {
    }

    public record UnitCount(String code, String label, String clearsAgainst, String holdsFor, String typicalReason, long holding, int progress) {
    }

    public record Totals(long candidates, long fullyCleared, long outstandingAtOne, long outstandingAtTwoOrMore) {
    }

    public record Listing(String purpose, Totals totals, List<UnitCount> units, List<Candidate> candidates, long total) {
    }
}
