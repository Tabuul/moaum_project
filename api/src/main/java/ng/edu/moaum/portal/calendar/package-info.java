/**
 * The calendar the rest of the University hangs off (V013 §2): the academic
 * sessions with their state and the Senate minute that opened them, the
 * semesters of a session with every date that changes what a student can do
 * today, and the unit limits per level.
 *
 * <p>Two rules are the database's and are left there deliberately: exactly one
 * session is CURRENT ({@code uq_session_one_current}), no two sessions overlap
 * ({@code ex_session_no_overlap}), and a session may not be CURRENT without a
 * minute ({@code ck_session_current_has_minute}). This module does not
 * re-implement them — it lets them refuse, and passes the refusal on.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Calendar")
package ng.edu.moaum.portal.calendar;
