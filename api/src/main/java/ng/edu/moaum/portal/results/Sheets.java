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
            "ENTRY", List.of("lecturer", "gst", "eps", "exams"),   // V318: the Programme Examinations Officer may enter and submit on the lecturer's behalf
            "VERIFICATION", List.of("exams"),
            "DEPT_BOARD", List.of("hod"),
            "FACULTY_SCRUTINY", List.of("facultyexams"),
            "FACULTY_COMPILATION", List.of("facultyofficer"),
            "FACULTY_BOARD", List.of("dean"),
            "RECORDS", List.of("records"),
            "SENATE", List.of("registrar", "dregistrar"),
            "PUBLISHED", List.of());

    /** V357: the desk of a stage, in words (assessment.stage_desk_name) */
    public static String deskName(String stage) {
        return switch (stage) {
            case "ENTRY" -> "the lecturer";
            case "VERIFICATION" -> "the Programme Examinations Officer";
            case "DEPT_BOARD" -> "the Head of Department";
            case "FACULTY_SCRUTINY" -> "the Faculty Examinations Officer";
            case "FACULTY_COMPILATION" -> "the Faculty Officer";
            case "FACULTY_BOARD" -> "the Dean";
            case "RECORDS" -> "Exams & Records";
            case "SENATE" -> "the Registrar";
            default -> "no desk";
        };
    }

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
                      long candidates, long received, long graded, long failed, UUID lastActor, int caMax, long heldScripts, String generalOffice) {
    }

    public record Listed(UUID id, String courseCode, String courseTitle, int units, String deptName, String facultyName,
                         String session, int semester, String stage, int spineStage, String sitting, LocalDate dueOn, Integer daysLate,
                         int returnedTimes, String lecturer, long candidates, long received, Integer failRate, boolean mayAct,
                         boolean blockedForYou, int caMax, long heldScripts, Chase chase) {
    }

    /** V359: how a sheet at entry has been chased — reminders to its lecturer, escalations and to whom; null when never */
    public record Chase(int reminders, OffsetDateTime remindedAt, int escalations, OffsetDateTime escalatedAt, String escalatedTo) {
    }

    /** the office a late sheet is escalated to, as the monitor names it — assessment.chase_office's rule (V359) */
    static String escalationOffice(Integer daysLate, String generalOffice) {
        if (daysLate == null || daysLate <= 0) return "—";
        if (generalOffice != null && !generalOffice.isBlank()) return "The " + generalOffice.trim().toUpperCase() + " office";
        return daysLate < 6 ? "Head of Department" : "Dean";
    }

    /* ── V318: the pipeline monitor — the nine stages with their real counts, coverage, what is missing, what needs a desk ── */

    /** a stage of the chain and what sits at it in scope */
    public record StageCount(String stage, String label, String desk, long sheets, long candidates) {
    }

    /** what the scope expects, has received and still lacks */
    public record Coverage(long offerings, long withLecturer, long withoutLecturer, long sheets, long expected, long received,
                           long missing, int percent, long published, long publishedCandidates) {
    }

    /** one sheet as the monitor reads it */
    public record Progress(UUID id, String courseCode, String courseTitle, int units, String deptCode, String deptName, String facultyCode,
                           String facultyName, String session, int semester, String sitting, String stage, String desk, String lecturer,
                           long candidates, long received, long missing, Integer failRate, OffsetDateTime stageSince, Integer daysAtStage,
                           LocalDate dueOn, Integer daysLate, int returnedTimes, long heldScripts, long uploadsOnBehalf, boolean mayAct,
                           boolean blockedForYou, List<String> flags) {
    }

    /** a course whose results are not all in: a sheet still short of marks, or an offering with no sheet at all */
    public record MissingCourse(UUID sheetId, UUID offeringId, String courseCode, String courseTitle, String deptName, String lecturer,
                                long candidates, long received, long missing, String why) {
    }

    /** something a desk should look at: an overdue sheet, a return, a high fail rate, held scripts, a stalled set */
    public record Alert(UUID sheetId, String courseCode, String deptName, String stage, String kind, String detail) {
    }

    /** an event on the record: a decision of the chain, or an upload on behalf */
    public record TimelineEvent(UUID sheetId, String courseCode, String fromStage, String toStage, String kind, String actorOffice,
                                String actor, String comment, OffsetDateTime decidedAt) {
    }

    /** a programme at a level: how far its broadsheet is */
    public record ProgrammeLevel(String programmeCode, String programmeName, String deptCode, String deptName, int level, long students,
                                 long cells, long received, long missing, long published, int percent) {
    }

    public record PipelineView(String session, Integer semester, String fac, String dept, String prog, String desk, String deskStage,
                               List<StageCount> stages, Coverage coverage, List<Progress> sheets, List<MissingCourse> missing,
                               List<Alert> alerts, List<Progress> attention, List<TimelineEvent> timeline, List<ProgrammeLevel> programmes) {
    }

    /** an upload of marks on behalf of the lecturer (V318) */
    public record Upload(UUID id, UUID uploadedById, String uploadedBy, String uploaderOffice, String owner, String reason,
                         int rowsWritten, OffsetDateTime uploadedAt) {
    }

    public record Tiles(long expected, long senateApproved, long inWorkflow, long notSubmitted) {
    }

    public record Listing(Tiles tiles, List<Listed> sheets, String desk) {
    }

    public record Decision(UUID id, String fromStage, String toStage, String kind, UUID actorId, String actor,
                           String actorOffice, String comment, OffsetDateTime decidedAt) {
    }

    public record Mark(UUID studentId, String number, String surname, String otherNames, Integer ca, Integer exam,
                       Integer total, String grade, BigDecimal points, String outcome, int version, boolean amended,
                       String enteredBy, String enteredOffice, boolean onBehalf) {
    }

    /** one sheet in full: the chain it has passed, the marks as they stand, the uploads made on the lecturer's behalf
     *  (V318), and whether the reader teaches the course (so an entry of theirs is the lecturer's own, not on behalf) */
    public record Detail(Listed sheet, String secondExaminer, String senateMinute, OffsetDateTime publishedAt,
                         String engineVersion, List<Decision> chain, List<Mark> marks, List<Upload> uploads, boolean youTeach) {
    }

    public record ExamSession(UUID id, String session, int semester, String kind, LocalDate examsFrom, LocalDate examsTo,
                              LocalDate sheetsDue, String state, OffsetDateTime openedAt, long sheets, long candidates,
                              long outstanding, OffsetDateTime cardsReleasedAt, OffsetDateTime sheetsReleasedAt) {
    }

    public record FacultyProgress(String facultyCode, String facultyName, long expected, long submitted, long verified,
                                  long pastTheBoard, long outstanding, int progress) {
    }

    public record Outstanding(UUID id, String courseCode, String deptName, String facultyCode, String lecturer,
                              long candidates, Integer daysLate, String escalatedTo, Chase chase) {
    }

    public record Monitor(ExamSession examSession, List<FacultyProgress> faculties, List<Outstanding> outstanding) {
    }

    /* ── the lecturer's own sheets, the roll under one, the broadsheet and Senate (proto/part5, 28, 26) ── */

    public record MySheet(UUID id, String courseCode, String courseTitle, int units, String session, int semester, String stage,
                          int spineStage, LocalDate dueOn, Integer daysLate, Integer daysToDue, int returnedTimes, long candidates, long entered,
                          long graded, String secondExaminer, boolean mine, long openQueries, long bankQuestions, long caEntered, long heldScripts,
                          Chase chase) {
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
                                 String entryMode, int courseLevel, UUID sheetId) {
    }

    /** V318: how far one course column of the broadsheet is — its roll in this class, the marks in, the marks still out */
    public record BroadsheetCourseCoverage(String courseCode, String title, UUID sheetId, String stage, long expected, long received, long missing) {
    }

    /** V318: the live coverage of the broadsheet — every cell a registration expects, counted as the marks arrive */
    public record BroadsheetCoverage(long cells, long received, long missing, int percent, long coursesComplete, long coursesTotal,
                                     long candidatesComplete, long setsPublished, List<BroadsheetCourseCoverage> courses,
                                     List<BroadsheetMissing> candidates) {
    }

    /** V318: a candidate with a result still out, and which */
    public record BroadsheetMissing(UUID studentId, String number, String name, List<String> courses) {
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
                                List<String> carryovers, String remarks, String entryMode, int received, int missing) {
    }

    public record Broadsheet(String programme, int level, String session, int semester, List<BroadsheetCourse> courses,
                             List<BroadsheetRow> rows, BigDecimal meanGpa, long passed, long carrying, long pendingSets,
                             List<GradeBand> bands, List<ClassBand> classes, String gradingInstrument, BroadsheetCoverage coverage) {
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
