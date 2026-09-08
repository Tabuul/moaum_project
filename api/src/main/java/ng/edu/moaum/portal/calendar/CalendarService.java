package ng.edu.moaum.portal.calendar;

import java.time.LocalDate;
import java.util.List;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The Academic Office runs the calendar; the Super Administrator can reach
 * the same screen because the platform has to be configurable when the
 * Registry is not at its desk. Both write through here, and the log records
 * which of them it was.
 *
 * <p>The three rules that matter are the database's, and are left there: two
 * sessions may not overlap, only one may be CURRENT, and a CURRENT session
 * must carry the Senate minute that opened it. This service adds one refusal
 * of its own — {@code CAL_MINUTE_REQUIRED} — so that "make this one current"
 * says what is missing before the database has to.
 */
@Service
public class CalendarService {

    private final CalendarRepository calendar;

    CalendarService(CalendarRepository calendar) {
        this.calendar = calendar;
    }

    public record SessionIn(@NotNull LocalDate startsOn, @NotNull LocalDate endsOn,
                            @NotNull @Min(1) @Max(3) Integer semesters,
                            @Size(max = 200) String senateMinute,
                            @Pattern(regexp = "PLANNED|CURRENT|CLOSED") String state) {
    }

    public record SemesterIn(LocalDate lecturesFrom, LocalDate lecturesTo,
                             LocalDate registrationOpens, LocalDate registrationCloses,
                             LocalDate lateRegistrationCloses, LocalDate examsFrom, LocalDate examsTo,
                             LocalDate resultsDue, @Size(max = 200) String queryWindow,
                             @Pattern(regexp = "NOT_YET_OPEN|OPEN|CLOSED") String state) {
    }

    public record LevelIn(@NotNull @Size(max = 200) String appliesTo,
                          @NotNull @Min(0) @Max(60) Integer minUnits,
                          @NotNull @Min(0) @Max(60) Integer maxUnits,
                          @NotNull Boolean carryoverCounts,
                          @Size(max = 200) String instrument) {
    }

    public record Minute(String senateMinute) {
    }

    @Transactional(readOnly = true)
    public Calendar read(String requested) {
        String current = calendar.current().orElse(null);
        String looking = requested == null || requested.isBlank() ? current : requested.trim();
        return new Calendar(calendar.sessions(), current, looking,
                looking == null ? List.<Calendar.Semester>of() : calendar.semesters(looking),
                calendar.levelLimits());
    }

    /**
     * Records the session, or amends it. Asking for CURRENT here closes
     * whatever else is current in the same transaction; the minute is still
     * the database's requirement, and it refuses without one.
     */
    @Transactional
    public Calendar saveSession(String session, SessionIn in) {
        String minute = in.senateMinute() == null || in.senateMinute().isBlank() ? null : in.senateMinute().trim();
        String state = in.state() == null || in.state().isBlank() ? null : in.state().trim();
        if ("CURRENT".equals(state)) {
            calendar.closeOtherCurrent(session);
        }
        calendar.upsertSession(session, in.startsOn(), in.endsOn(), in.semesters(), minute, state);
        return read(session);
    }

    /** One session is current at a time: the one that was becomes CLOSED, in this transaction. */
    @Transactional
    public Calendar makeCurrent(String session, String senateMinute) {
        if (senateMinute == null || senateMinute.isBlank()) {
            throw new DomainRuleViolation("CAL_MINUTE_REQUIRED",
                    "A session stays planned until its Senate minute is recorded against it, and none was given.",
                    new DomainRuleViolation.Remedy(
                            "Quote the Senate minute that resolved to run " + session + ". Opening a session early would let "
                                    + "students register into a session the University has not resolved to run.",
                            "Academic Office"));
        }
        mustExist(session);
        calendar.closeOtherCurrent(session);
        calendar.setCurrent(session, senateMinute.trim());
        return read(session);
    }

    @Transactional
    public Calendar closeSession(String session) {
        mustExist(session);
        calendar.close(session);
        return read(session);
    }

    @Transactional
    public Calendar saveSemester(String session, int number, SemesterIn in) {
        mustExist(session);
        String state = in.state() == null || in.state().isBlank() ? "NOT_YET_OPEN" : in.state().trim();
        calendar.upsertSemester(session, number, in, state);
        return read(session);
    }

    @Transactional
    public Calendar saveLevelLimit(int level, LevelIn in) {
        if (in.maxUnits() < in.minUnits()) {
            throw new DomainRuleViolation("CAL_UNIT_RANGE",
                    "The maximum (" + in.maxUnits() + ") is below the minimum (" + in.minUnits() + ") for level " + level + ".",
                    new DomainRuleViolation.Remedy("State a ceiling at or above the floor.", "Academic Office"));
        }
        calendar.upsertLevelLimit(level, in);
        return read(null);
    }

    private void mustExist(String session) {
        if (!calendar.exists(session)) {
            throw new NotFound("session", session);
        }
    }
}
