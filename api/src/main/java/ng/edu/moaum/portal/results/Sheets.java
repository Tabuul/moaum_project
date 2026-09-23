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
                      LocalDate dueOn, OffsetDateTime submittedAt, int returnedTimes, UUID lecturerId, String sitting, String lecturer,
                      long candidates, long graded, long failed, UUID lastActor, int caMax, long heldScripts) {
    }

    public record Listed(UUID id, String courseCode, String courseTitle, int units, String deptName, String facultyName,
                         String session, int semester, String stage, int spineStage, String sitting, LocalDate dueOn, Integer daysLate,
                         int returnedTimes, String lecturer, long candidates, Integer failRate, boolean mayAct,
                         boolean blockedForYou, int caMax, long heldScripts) {
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

    /* ── the lecturer's own sheets, the roll under one, the broadsheet and Senate (proto/part5, 28, 26) ── */

    public record MySheet(UUID id, String courseCode, String courseTitle, int units, String session, int semester, String stage,
                          int spineStage, LocalDate dueOn, Integer daysLate, Integer daysToDue, int returnedTimes, long candidates, long entered,
                          long graded, String secondExaminer, boolean mine, long openQueries, long bankQuestions, long caEntered, long heldScripts) {
    }

    /** every approved registration on the sheet, with the latest mark where one exists */
    public record RollRow(UUID studentId, String number, String surname, String otherNames, String programmeCode,
                          String programmeName, int level, Integer ca, Integer exam, Integer total, String grade,
                          BigDecimal points, String outcome, Integer version) {
    }

    public record GradeBand(String grade, int low, int high, BigDecimal points) {
    }

    public record ClassBand(String clazz, BigDecimal low, BigDecimal high, int ord) {
    }

    /** one candidate, one course, on the broadsheet */
    public record BroadsheetCell(UUID studentId, String number, String surname, String otherNames, String courseCode,
                                 String title, int units, String kind, String stage, Integer total, String grade, BigDecimal points, String outcome,
                                 String entryMode, int courseLevel) {
    }

    public record BroadsheetCourse(String courseCode, String title, int units, String kind, int level) {
    }

    public record BroadsheetMark(String courseCode, String stage, Integer total, String grade, BigDecimal points, String outcome, boolean counted) {
    }

    public record Cumulative(int tcr, int tce, BigDecimal twgp, BigDecimal cgpa, BigDecimal prevCgpa) {
    }

    public record BroadsheetRow(UUID studentId, String number, String name, List<BroadsheetMark> marks, int units,
                                int cur, int cue,
                                BigDecimal points, BigDecimal gpa, int pending, String standing,
                                int tcr, int tce, BigDecimal twgp, BigDecimal cgpa, BigDecimal lcgpa,
                                List<String> carryovers, String remarks, String entryMode) {
    }

    public record Broadsheet(String programme, int level, String session, int semester, List<BroadsheetCourse> courses,
                             List<BroadsheetRow> rows, BigDecimal meanGpa, long passed, long carrying, long pendingSets,
                             List<GradeBand> bands, List<ClassBand> classes, String gradingInstrument) {
    }

    public record SenateFaculty(String facultyCode, String facultyName, long sets, long atSenate, long published,
                                long outstanding, long candidates) {
    }

    public record SenateMinute(String minute, OffsetDateTime firstPublishedAt, OffsetDateTime lastPublishedAt, long sets, long candidates) {
    }

    public record Senate(String session, int semester, List<SenateFaculty> faculties, List<SenateMinute> minutes,
                         long sets, long atSenate, long published, long outstanding, long candidatesPublished) {
    }
}
