package ng.edu.moaum.portal.calendar;

import java.time.LocalDate;
import java.util.List;

/**
 * The whole calendar screen in one read: every session the University has
 * recorded with the number of people enrolled in it, which of them is
 * current, the semesters of the session being looked at, and the unit limits
 * per level.
 */
public record Calendar(List<SessionRow> sessions, String current, String session,
                       List<Semester> semesters, List<LevelLimit> levelLimits) {

    /**
     * One row of {@code policy.academic_session}. {@code students} is the
     * count of {@code people.enrolment} for the session — the register, not
     * an estimate, and zero until the Academic Office brings anybody onto it.
     */
    public record SessionRow(String name, LocalDate startsOn, LocalDate endsOn, String state,
                             String senateMinute, int semesters, long students) {
    }

    /** One row of {@code policy.semester}: every date on it changes what a student can do today. */
    public record Semester(String session, int number, LocalDate lecturesFrom, LocalDate lecturesTo,
                           LocalDate registrationOpens, LocalDate registrationCloses,
                           LocalDate lateRegistrationCloses, LocalDate examsFrom, LocalDate examsTo,
                           LocalDate resultsDue, String queryWindow, String state) {
    }

    /** One row of {@code policy.level_limit}: the ceiling that stops a student registering a timetable they cannot sit. */
    public record LevelLimit(int level, String appliesTo, int minUnits, int maxUnits,
                             boolean carryoverCounts, String instrument, Integer probationMaxUnits) {
    }
}
