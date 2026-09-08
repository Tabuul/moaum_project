package ng.edu.moaum.portal.matriculation;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public final class Matriculation {

    private Matriculation() {
    }

    public record FacultyLine(String code, String name, String officer, long registered, long confirmed, long queried, String state,
                              OffsetDateTime confirmedAt) {
    }

    public record Run(UUID id, String ref, String session, OffsetDateTime runAt, int issued) {
    }

    public record Allocation(String admissionNo, String matricNo, String surname, String otherNames, String deptName) {
    }

    public record Held(UUID studentId, String admissionNo, String surname, String otherNames, String facultyName, String reason, String office) {
    }

    public record Totals(long registered, long confirmed, long pending, long queried) {
    }

    public record Overview(String session, Totals totals, List<FacultyLine> faculties, List<Held> heldBack, List<Run> runs,
                           List<Allocation> sample, Integer minUnits) {
    }

    public record Row(UUID studentId, String admissionNo, String surname, String otherNames, String deptCode, String deptName,
                      int units, String registrationStatus, String queryReason, String queryOffice) {
    }

    public record FacultyList(String session, String code, String name, String state, OffsetDateTime confirmedAt, Integer minUnits,
                              List<Row> rows) {
    }
}
