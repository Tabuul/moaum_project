package ng.edu.moaum.portal.calendar;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

/**
 * The whole calendar screen in one read: every session the University has
 * recorded with the number of people enrolled in it, which of them is
 * current and which is the next planned one (V289), the semesters of the
 * session being looked at, the unit limits per level, and the last session
 * transitions with their outcome.
 */
public record Calendar(List<SessionRow> sessions, String current, String next, String session,
                       List<Semester> semesters, List<LevelLimit> levelLimits, List<Map<String, Object>> transitions) {

    /**
     * One row of {@code policy.academic_session}. {@code students} is the
     * count of {@code people.enrolment} for the session — the register, not
     * an estimate, and zero until the Academic Office brings anybody onto it.
     * {@code state} is DRAFT, PLANNED, CURRENT, CLOSED (read "Completed") or
     * ARCHIVED (V289); {@code transitionsOn} is the official transition point
     * and {@code transitionMode} says whether the clock acts on it.
     */
    public record SessionRow(String name, LocalDate startsOn, LocalDate endsOn, String state,
                             String senateMinute, int semesters, long students,
                             String transitionMode, LocalDate transitionsOn,
                             OffsetDateTime madeCurrentAt, OffsetDateTime completedAt, OffsetDateTime archivedAt,
                             long freshStudents) {
    }

    /** One row of {@code policy.semester}: every date on it changes what a student can do today. */
    public record Semester(String session, int number, LocalDate lecturesFrom, LocalDate lecturesTo,
                           LocalDate registrationOpens, LocalDate registrationCloses,
                           LocalDate lateRegistrationCloses, LocalDate examsFrom, LocalDate examsTo,
                           LocalDate resultsDue, String queryWindow, String state,
                           /** V287: from this day the session's fresh students register although the semester is not yet open */
                           LocalDate freshRegistrationFrom) {
    }

    /** One row of {@code policy.level_limit}: the ceiling that stops a student registering a timetable they cannot sit. */
    public record LevelLimit(int level, String appliesTo, int minUnits, int maxUnits,
                             boolean carryoverCounts, String instrument, Integer probationMaxUnits) {
    }
}
