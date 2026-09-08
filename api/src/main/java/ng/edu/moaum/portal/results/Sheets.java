package ng.edu.moaum.portal.results;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** What the desks read. */
public final class Sheets {

    private Sheets() {
    }

    /** The desk each stage belongs to (proto/part28 CHAIN). */
    public static final Map<String, List<String>> DESK = Map.of(
            "ENTRY", List.of("lecturer"),
            "VERIFICATION", List.of("exams"),
            "DEPT_BOARD", List.of("hod"),
            "FACULTY_SCRUTINY", List.of("facultyexams"),
            "FACULTY_COMPILATION", List.of("facultyofficer"),
            "FACULTY_BOARD", List.of("dean"),
            "RECORDS", List.of("records"),
            "SENATE", List.of("registrar", "dregistrar"),
            "PUBLISHED", List.of());

    /** The spine a student sees: six stages over nine desks. */
    public static int spine(String stage) {
        return switch (stage) {
            case "ENTRY" -> 1;
            case "VERIFICATION" -> 2;
            case "DEPT_BOARD" -> 3;
            case "FACULTY_SCRUTINY", "FACULTY_COMPILATION", "FACULTY_BOARD" -> 4;
            case "RECORDS", "SENATE" -> 5;
            default -> 6;
        };
    }

    public record Row(UUID id, String courseCode, String courseTitle, int units, String deptCode, String deptName,
                      String facultyCode, String facultyName, String session, int semester, String stage,
                      LocalDate dueOn, OffsetDateTime submittedAt, int returnedTimes, UUID lecturerId, String lecturer,
                      long candidates, long graded, long failed, UUID lastActor) {
    }

    public record Listed(UUID id, String courseCode, String courseTitle, int units, String deptName, String facultyName,
                         String session, int semester, String stage, int spineStage, LocalDate dueOn, Integer daysLate,
                         int returnedTimes, String lecturer, long candidates, Integer failRate, boolean mayAct,
                         boolean blockedForYou) {
    }

    public record Tiles(long expected, long senateApproved, long inWorkflow, long notSubmitted) {
    }

    public record Listing(Tiles tiles, List<Listed> sheets, String desk) {
    }

    public record Decision(UUID id, String fromStage, String toStage, String kind, UUID actorId, String actor,
                           String actorOffice, String comment, OffsetDateTime decidedAt) {
    }

    public record Mark(UUID studentId, String number, String surname, String otherNames, Integer ca, Integer exam,
                       Integer total, String grade, BigDecimal points, String outcome, int version, boolean amended) {
    }

    public record Detail(Listed sheet, String secondExaminer, String senateMinute, OffsetDateTime publishedAt,
                         String engineVersion, List<Decision> chain, List<Mark> marks) {
    }

    public record ExamSession(UUID id, String session, int semester, String kind, LocalDate examsFrom, LocalDate examsTo,
                              LocalDate sheetsDue, String state, OffsetDateTime openedAt, long sheets, long candidates,
                              long outstanding) {
    }

    public record FacultyProgress(String facultyCode, String facultyName, long expected, long submitted, long verified,
                                  long pastTheBoard, long outstanding, int progress) {
    }

    public record Outstanding(UUID id, String courseCode, String deptName, String facultyCode, String lecturer,
                              long candidates, Integer daysLate, String escalatedTo) {
    }

    public record Monitor(ExamSession examSession, List<FacultyProgress> faculties, List<Outstanding> outstanding) {
    }
}
