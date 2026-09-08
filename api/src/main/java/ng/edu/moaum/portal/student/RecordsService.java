package ng.edu.moaum.portal.student;

import java.util.List;
import java.util.Set;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The query workbench. Eight views, one scope.
 *
 * <p>Two of the eight are not served: fees are the Bursary's ledger and
 * attendance is taken in the lecture theatre, and neither is on the portal
 * yet. They return no rows and the sentence that says why, because a figure
 * invented for a screen is worse than no figure at all.
 */
@Service
class RecordsService {

    static final Set<String> VIEWS = Set.of("students", "registration", "fees", "results",
            "exams", "allocation", "clearance", "attendance");

    private static final String FEES_NOT_SERVED =
            "School fees are the Bursary's ledger, and the Bursary is not on the portal yet. "
                    + "No billed, collected or outstanding figure is shown here until it comes from that ledger.";

    private static final String ATTENDANCE_NOT_SERVED =
            "Attendance is taken in the lecture theatre and is not yet recorded in the portal. "
                    + "Senate requires 75% to sit; until the register is kept here, this view cannot say who meets it.";

    private final RecordsRepository records;
    private final StudentRepository students;

    RecordsService(RecordsRepository records, StudentRepository students) {
        this.records = records;
        this.students = students;
    }

    @Transactional(readOnly = true)
    RecordsResult view(String view, Scope scope) {
        if (!VIEWS.contains(view)) {
            throw new NotFound("records view", view);
        }
        int total = students.inScope(scope);
        return switch (view) {
            case "students" -> new RecordsResult(view, records.students(scope), total, null);
            case "registration" -> new RecordsResult(view, records.registration(scope), total, null);
            case "results" -> new RecordsResult(view, records.results(scope), total, null);
            case "exams" -> new RecordsResult(view, records.exams(scope), total, null);
            case "allocation" -> new RecordsResult(view, records.allocation(scope), total, null);
            case "clearance" -> new RecordsResult(view, records.clearance(scope), total, null);
            case "fees" -> new RecordsResult(view, List.of(), total, FEES_NOT_SERVED);
            default -> new RecordsResult(view, List.of(), total, ATTENDANCE_NOT_SERVED);
        };
    }
}
