package ng.edu.moaum.portal.ref;

import java.time.LocalDate;

/** An academic session: PLANNED until its Senate minute is recorded, one CURRENT at a time, then CLOSED. */
public record Session(String name, LocalDate startsOn, LocalDate endsOn, String state, String senateMinute, int semesters) {
}
