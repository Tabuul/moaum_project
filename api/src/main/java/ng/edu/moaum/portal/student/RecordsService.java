package ng.edu.moaum.portal.student;

import java.util.List;
import java.util.Set;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The query workbench. Eight views, one scope.
 *
 * <p>V360: all eight are served. Fees are the Bursary's figures for the session — what the fee schedule charges and
 * what has been paid against it; attendance is what the lecturers have marked, with no minimum applied because none is
 * configured for the University's courses. A figure invented for a screen is still worse than no figure at all.
 */
@Service
class RecordsService {

    static final Set<String> VIEWS = Set.of("students", "registration", "fees", "results",
            "exams", "allocation", "clearance", "attendance");

    /** the largest scope whose CGPAs are read with the register — each is computed from the published results */
    static final int CGPA_SCOPE = 1500;

    private static final String FEES_NOTE =
            "School fees charged by the Bursary's fee schedule and confirmed school-fee payments. Earlier sessions' arrears are on each student's record.";

    private static final String ATTENDANCE_NOTE =
            "Attendance as marked by lecturers on approved registrations. No minimum attendance is configured, so no student is marked short.";

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
            case "students" -> new RecordsResult(view, records.students(scope, total <= CGPA_SCOPE), total, null,
                    total <= CGPA_SCOPE ? null : "CGPA is shown for up to " + CGPA_SCOPE + " students; narrow to a department or programme.");
            case "registration" -> new RecordsResult(view, records.registration(scope), total, null);
            case "results" -> new RecordsResult(view, records.results(scope), total, null);
            case "exams" -> new RecordsResult(view, records.exams(scope), total, null);
            case "allocation" -> new RecordsResult(view, records.allocation(scope), total, null);
            case "clearance" -> new RecordsResult(view, records.clearance(scope), total, null);
            case "fees" -> new RecordsResult(view, records.fees(scope), total, null, FEES_NOTE);
            default -> new RecordsResult(view, records.attendance(scope), total, null, ATTENDANCE_NOTE);
        };
    }
}
