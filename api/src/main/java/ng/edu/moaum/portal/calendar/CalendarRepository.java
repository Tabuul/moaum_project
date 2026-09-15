package ng.edu.moaum.portal.calendar;

import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** {@code policy.academic_session}, {@code policy.semester} and {@code policy.level_limit}, read and written as they are. */
@Repository
class CalendarRepository {

    private final JdbcClient jdbc;

    CalendarRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    List<Calendar.SessionRow> sessions() {
        return jdbc.sql("""
                SELECT s.name, s.starts_on, s.ends_on, s.state, s.senate_minute, s.semesters,
                       (SELECT count(*) FROM people.enrolment e WHERE e.session = s.name) AS students
                  FROM policy.academic_session s
                 ORDER BY s.name DESC
                """)
                .query(Calendar.SessionRow.class)
                .list();
    }

    String rollOver(String toSession, String confirm, String reason) {
        return jdbc.sql("SELECT people.roll_over_session(:s, :c, :r)::text")
                .param("s", toSession).param("c", confirm).param("r", reason)
                .query(String.class).single();
    }

    java.util.Map<String, Object> enrolCurrent(String session) {
        return jdbc.sql("SELECT * FROM people.enrol_current_session(:s)")
                .param("s", session)
                .query().singleRow();
    }

    Optional<String> current() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'")
                .query(String.class)
                .optional();
    }

    boolean exists(String session) {
        return jdbc.sql("SELECT count(*) FROM policy.academic_session WHERE name = :name")
                .param("name", session)
                .query(Long.class)
                .single() > 0;
    }

    List<Calendar.Semester> semesters(String session) {
        return jdbc.sql("""
                SELECT session, number, lectures_from, lectures_to, registration_opens, registration_closes,
                       late_registration_closes, exams_from, exams_to, results_due, query_window, state
                  FROM policy.semester WHERE session = :session ORDER BY number
                """)
                .param("session", session)
                .query(Calendar.Semester.class)
                .list();
    }

    List<Calendar.LevelLimit> levelLimits() {
        return jdbc.sql("""
                SELECT level, applies_to, min_units, max_units, carryover_counts, instrument
                  FROM policy.level_limit ORDER BY level
                """)
                .query(Calendar.LevelLimit.class)
                .list();
    }

    /**
     * Creates the session or amends it. A minute already recorded is not
     * cleared by a form that did not carry it, and neither is the state: both
     * fall back to what the row already says.
     */
    void upsertSession(String name, LocalDate startsOn, LocalDate endsOn, int semesters, String minute, String state) {
        jdbc.sql("""
                INSERT INTO policy.academic_session (id, name, starts_on, ends_on, semesters, senate_minute, state)
                VALUES (gen_random_uuid(), :name, :from, :to, :sems, cast(:minute as text), coalesce(cast(:state as text), 'PLANNED'))
                ON CONFLICT (name) DO UPDATE SET
                       starts_on     = EXCLUDED.starts_on,
                       ends_on       = EXCLUDED.ends_on,
                       semesters     = EXCLUDED.semesters,
                       senate_minute = coalesce(cast(:minute as text), policy.academic_session.senate_minute),
                       state         = coalesce(cast(:state as text), policy.academic_session.state)
                """)
                .param("name", name)
                .param("from", startsOn)
                .param("to", endsOn)
                .param("sems", semesters)
                .param("minute", minute, Types.VARCHAR)
                .param("state", state, Types.VARCHAR)
                .update();
    }

    /** Whatever else is current stops being current, in the caller's transaction. */
    void closeOtherCurrent(String keep) {
        jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT' AND name <> :name")
                .param("name", keep)
                .update();
    }

    void setCurrent(String session, String minute) {
        jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = :minute WHERE name = :name")
                .param("name", session)
                .param("minute", minute)
                .update();
    }

    void close(String session) {
        jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE name = :name")
                .param("name", session)
                .update();
    }

    void upsertSemester(String session, int number, CalendarService.SemesterIn in, String state) {
        jdbc.sql("""
                INSERT INTO policy.semester (id, session, number, lectures_from, lectures_to, registration_opens,
                       registration_closes, late_registration_closes, exams_from, exams_to, results_due,
                       query_window, state)
                VALUES (gen_random_uuid(), :session, :n, :lf, :lt, :ro, :rc, :lrc, :ef, :et, :due,
                        cast(:query as text), :state)
                ON CONFLICT (session, number) DO UPDATE SET
                       lectures_from            = EXCLUDED.lectures_from,
                       lectures_to              = EXCLUDED.lectures_to,
                       registration_opens       = EXCLUDED.registration_opens,
                       registration_closes      = EXCLUDED.registration_closes,
                       late_registration_closes = EXCLUDED.late_registration_closes,
                       exams_from               = EXCLUDED.exams_from,
                       exams_to                 = EXCLUDED.exams_to,
                       results_due              = EXCLUDED.results_due,
                       query_window             = EXCLUDED.query_window,
                       state                    = EXCLUDED.state
                """)
                .param("session", session)
                .param("n", number)
                .param("lf", in.lecturesFrom(), Types.DATE)
                .param("lt", in.lecturesTo(), Types.DATE)
                .param("ro", in.registrationOpens(), Types.DATE)
                .param("rc", in.registrationCloses(), Types.DATE)
                .param("lrc", in.lateRegistrationCloses(), Types.DATE)
                .param("ef", in.examsFrom(), Types.DATE)
                .param("et", in.examsTo(), Types.DATE)
                .param("due", in.resultsDue(), Types.DATE)
                .param("query", in.queryWindow(), Types.VARCHAR)
                .param("state", state)
                .update();
    }

    void upsertLevelLimit(int level, CalendarService.LevelIn in) {
        jdbc.sql("""
                INSERT INTO policy.level_limit (level, applies_to, min_units, max_units, carryover_counts, instrument)
                VALUES (:level, :who, :min, :max, :carry, cast(:instrument as text))
                ON CONFLICT (level) DO UPDATE SET
                       applies_to       = EXCLUDED.applies_to,
                       min_units        = EXCLUDED.min_units,
                       max_units        = EXCLUDED.max_units,
                       carryover_counts = EXCLUDED.carryover_counts,
                       instrument       = coalesce(cast(:instrument as text), policy.level_limit.instrument)
                """)
                .param("level", level)
                .param("who", in.appliesTo().trim())
                .param("min", in.minUnits())
                .param("max", in.maxUnits())
                .param("carry", in.carryoverCounts())
                .param("instrument", in.instrument() == null || in.instrument().isBlank() ? null : in.instrument().trim(),
                        Types.VARCHAR)
                .update();
    }
}
