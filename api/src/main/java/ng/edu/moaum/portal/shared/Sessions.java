package ng.edu.moaum.portal.shared;

import java.time.LocalDate;
import java.time.ZoneId;

/**
 * The academic session by the calendar date, for the one case the University's calendar cannot answer: a calendar with
 * no session on it at all. A session runs from September to August (Africa/Lagos), so 11 October 2026 falls in 2026/2027.
 * Everywhere else the session is the calendar's — {@code policy.university_current_session()}: the CURRENT session, else
 * the latest one run, else the latest on the calendar — and never a year written into the code, which goes stale the
 * day the next session begins.
 */
public final class Sessions {

    private static final ZoneId LAGOS = ZoneId.of("Africa/Lagos");

    private Sessions() {
    }

    /** the session the date falls in, as 2026/2027 */
    public static String byDate() {
        return byDate(LocalDate.now(LAGOS));
    }

    static String byDate(LocalDate d) {
        int y = d.getMonthValue() >= 9 ? d.getYear() : d.getYear() - 1;
        return y + "/" + (y + 1);
    }
}
