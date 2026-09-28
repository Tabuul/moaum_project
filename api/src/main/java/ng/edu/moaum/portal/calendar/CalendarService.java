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
    private final tools.jackson.databind.ObjectMapper json;
    /** the transition's own transaction (V289): a BLOCKED attempt commits its log row, and the refusal is raised after */
    private final org.springframework.transaction.support.TransactionTemplate tx;

    CalendarService(CalendarRepository calendar, tools.jackson.databind.ObjectMapper json,
                    org.springframework.transaction.PlatformTransactionManager transactions) {
        this.calendar = calendar;
        this.json = json;
        this.tx = new org.springframework.transaction.support.TransactionTemplate(transactions);
    }

    public record RollOverIn(@NotNull @Size(max = 200) String confirm, @NotNull @Size(max = 400) String reason) {
    }

    /** Promote continuing students one level into the new session and enrol them. The DB function is
     *  guarded (the word ROLLOVER and a reason) and idempotent; it opens the session as PLANNED if new. */
    @Transactional
    public java.util.Map<String, Object> rollOver(String toSession, String confirm, String reason) {
        String result = calendar.rollOver(toSession, confirm, reason);
        return json.readValue(result, new tools.jackson.core.type.TypeReference<java.util.Map<String, Object>>() { });
    }

    /** Enrol every currently-studying student into the session at their current level, without promoting
     *  anyone — the backfill that matches an already-loaded cohort to the session they are in now. */
    @Transactional
    public java.util.Map<String, Object> enrolAll(String session) {
        return calendar.enrolCurrent(session);
    }

    public record SessionIn(@NotNull LocalDate startsOn, @NotNull LocalDate endsOn,
                            @NotNull @Min(1) @Max(3) Integer semesters,
                            @Size(max = 200) String senateMinute,
                            @Pattern(regexp = "DRAFT|PLANNED|CURRENT|CLOSED|ARCHIVED") String state,
                            /** V289: MANUAL (the Registrar makes it current) or AUTOMATIC (the clock does, on transitionsOn) */
                            @Pattern(regexp = "MANUAL|AUTOMATIC") String transitionMode,
                            LocalDate transitionsOn) {
    }

    /** V289: the Registrar's transition, confirmed by the word TRANSITION, with the reason the log keeps and the minute if not yet recorded */
    public record TransitionIn(@NotNull @Size(max = 40) String confirm, @NotNull @Size(max = 400) String reason,
                               @Size(max = 200) String senateMinute) {
    }

    public record Reason(@Size(max = 400) String reason) {
    }

    public record SemesterIn(LocalDate lecturesFrom, LocalDate lecturesTo,
                             LocalDate registrationOpens, LocalDate registrationCloses,
                             LocalDate lateRegistrationCloses, LocalDate examsFrom, LocalDate examsTo,
                             LocalDate resultsDue, @Size(max = 200) String queryWindow,
                             @Pattern(regexp = "NOT_YET_OPEN|OPEN|CLOSED") String state,
                             /** V287: the early window for the session's fresh students; dating it also opens the semester's courses */
                             LocalDate freshRegistrationFrom) {
    }

    public record LevelIn(@NotNull @Size(max = 200) String appliesTo,
                          @NotNull @Min(0) @Max(60) Integer minUnits,
                          @NotNull @Min(0) @Max(60) Integer maxUnits,
                          @NotNull Boolean carryoverCounts,
                          @Size(max = 200) String instrument,
                          @Min(0) @Max(60) Integer probationMaxUnits) {
    }

    public record Minute(String senateMinute) {
    }

    @Transactional(readOnly = true)
    public Calendar read(String requested) {
        String current = calendar.current().orElse(null);
        String looking = requested == null || requested.isBlank() ? current : requested.trim();
        return new Calendar(calendar.sessions(), current, calendar.nextPlanned().orElse(null), looking,
                looking == null ? List.<Calendar.Semester>of() : calendar.semesters(looking),
                calendar.levelLimits(), calendar.transitions(50));
    }

    /** the readiness checks of the transition into a session (V289), as the dashboard lists them */
    @Transactional(readOnly = true)
    public java.util.Map<String, Object> readiness(String session) {
        List<java.util.Map<String, Object>> checks = calendar.readiness(session);
        boolean ready = checks.stream().noneMatch(c -> Boolean.FALSE.equals(c.get("ok")) && Boolean.TRUE.equals(c.get("blocking")));
        boolean clean = checks.stream().noneMatch(c -> Boolean.FALSE.equals(c.get("ok")));
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session);
        out.put("state", calendar.state(session));
        out.put("current", calendar.current().orElse(null));
        out.put("ready", ready);
        out.put("readyForAutomatic", clean);
        out.put("checks", checks);
        return out;
    }

    /**
     * Records the session, or amends it. Asking for CURRENT here is the
     * transition (V289): validated, transactional and logged, never a plain
     * state change; asking for ARCHIVED archives a completed session; an
     * archived session is not edited back to life.
     */
    public Calendar saveSession(String session, SessionIn in) {
        String minute = in.senateMinute() == null || in.senateMinute().isBlank() ? null : in.senateMinute().trim();
        String state = in.state() == null || in.state().isBlank() ? null : in.state().trim();
        String mode = in.transitionMode() == null || in.transitionMode().isBlank() ? null : in.transitionMode().trim();
        java.util.Map<String, Object> result = tx.execute(st -> {
            String was = calendar.state(session);
            if ("ARCHIVED".equals(was) && state != null && !"ARCHIVED".equals(state)) {
                throw new DomainRuleViolation("SESSION_ARCHIVED", session + " is archived and is not reopened from the form.",
                        new DomainRuleViolation.Remedy("An archived session stays on the record as it was.", "Registry"));
            }
            boolean toCurrent = "CURRENT".equals(state) && !"CURRENT".equals(was);
            boolean toArchived = "ARCHIVED".equals(state) && !"ARCHIVED".equals(was);
            calendar.upsertSession(session, in.startsOn(), in.endsOn(), in.semesters(), minute,
                    toCurrent || toArchived ? null : state, mode, in.transitionsOn());
            if (toArchived) {
                calendar.archive(session, "Archived from the calendar");
            }
            return toCurrent ? transition(session, "MANUAL", "Made current from the calendar", minute) : java.util.Map.<String, Object>of();
        });
        refuseIfBlocked(result, session);
        return read(session);
    }

    /** One session is current at a time: the transition (V289) completes the one that was and makes this one current, in one transaction. */
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
        refuseIfBlocked(tx.execute(st -> transition(session, "MANUAL", "Made current from the calendar under " + senateMinute.trim(), senateMinute.trim())), session);
        return read(session);
    }

    /** The Registrar's transition (V289): the word TRANSITION, a reason, and the minute if the session has none. */
    public java.util.Map<String, Object> transitionByHand(String session, TransitionIn in) {
        if (!"TRANSITION".equalsIgnoreCase(in.confirm() == null ? "" : in.confirm().trim())) {
            throw new DomainRuleViolation("SESSION_TRANSITION_UNCONFIRMED",
                    "Type TRANSITION to confirm completing the current session and making " + session + " current.",
                    new DomainRuleViolation.Remedy("The word is the confirmation; the reason is what the log keeps.", "Registry"));
        }
        if (in.reason() == null || in.reason().isBlank()) {
            throw new DomainRuleViolation("SESSION_TRANSITION_UNCONFIRMED", "A session transition names its reason.",
                    new DomainRuleViolation.Remedy("Say why, as it will read in the log.", "Registry"));
        }
        mustExist(session);
        java.util.Map<String, Object> result = tx.execute(st -> transition(session, "MANUAL", in.reason().trim(),
                in.senateMinute() == null || in.senateMinute().isBlank() ? null : in.senateMinute().trim()));
        refuseIfBlocked(result, session);
        result.put("calendar", read(session));
        return result;
    }

    /** a completed session archived (V289): the record stays, the state says it is history */
    @Transactional
    public Calendar archive(String session, String reason) {
        mustExist(session);
        calendar.archive(session, reason == null || reason.isBlank() ? "Archived from the calendar" : reason.trim());
        return read(session);
    }

    /**
     * The one path a planned session becomes current: policy.transition_session
     * does both moves in its transaction and logs the attempt; BLOCKED is turned
     * into the refusal that names each failed check. The offices are told when
     * it is done.
     */
    java.util.Map<String, Object> transition(String session, String mode, String reason, String minute) {
        java.util.Map<String, Object> result = json.readValue(calendar.transition(session, mode, reason, minute),
                new tools.jackson.core.type.TypeReference<java.util.Map<String, Object>>() { });
        if ("DONE".equals(result.get("outcome"))) {
            tell(String.valueOf(result.get("from")), session, mode, reason);
        }
        return result;
    }

    /** a BLOCKED outcome, once its log row is committed, is the refusal that names each failed check */
    @SuppressWarnings("unchecked")
    private static void refuseIfBlocked(java.util.Map<String, Object> result, String session) {
        if (result == null || !"BLOCKED".equals(result.get("outcome"))) {
            return;
        }
        List<java.util.Map<String, Object>> checks = (List<java.util.Map<String, Object>>) result.get("checks");
        String failed = checks.stream().filter(c -> Boolean.FALSE.equals(c.get("ok")))
                .map(c -> String.valueOf(c.get("detail"))).reduce((a, b) -> a + " " + b).orElse("A readiness check failed.");
        throw new DomainRuleViolation("SESSION_TRANSITION_BLOCKED", "The transition into " + session + " is blocked. " + failed,
                new DomainRuleViolation.Remedy("Put right what the checks name on the calendar, then transition again; nothing was changed.", "Registry"));
    }

    /** the offices that work to the session are told the transition happened */
    private void tell(String from, String to, String mode, String reason) {
        String subject = "Academic session transition: " + to + " is now the current session";
        String body = (from == null || "null".equals(from) ? "No session was current; " : from + " is completed and ")
                + to + " is the current academic session from now"
                + ("AUTOMATIC".equals(mode) ? ", by the session clock on the configured transition date." : ", by the Registry's act.")
                + " Reason: " + reason + ". Returning students continue under the progression rules; entrants of " + to
                + " continue under the same accounts. No record was moved or recreated.";
        for (String office : List.of("registrar", "academic", "bursar", "ict")) {
            try {
                calendar.tellOffice(office, subject, body);
            } catch (RuntimeException e) {
                // a notice that cannot be queued does not undo the transition
            }
        }
    }

    @Transactional
    public Calendar closeSession(String session) {
        mustExist(session);
        if ("ARCHIVED".equals(calendar.state(session))) {
            throw new DomainRuleViolation("SESSION_ARCHIVED", session + " is archived; it is already complete.",
                    new DomainRuleViolation.Remedy("Nothing is to be done.", "Registry"));
        }
        calendar.close(session);
        return read(session);
    }

    @Transactional
    public Calendar saveSemester(String session, int number, SemesterIn in) {
        mustExist(session);
        String state = in.state() == null || in.state().isBlank() ? "NOT_YET_OPEN" : in.state().trim();
        calendar.upsertSemester(session, number, in, state);
        // V287 · an early window for fresh students needs the semester's courses on offer: opened here, idempotently, as the Office would
        if (in.freshRegistrationFrom() != null || "OPEN".equals(state)) {
            calendar.openCourses(session, number);
        }
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
