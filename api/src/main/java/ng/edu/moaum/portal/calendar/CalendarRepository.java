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
                       (SELECT count(*) FROM people.enrolment e WHERE e.session = s.name) AS students,
                       s.transition_mode, s.transitions_on, s.made_current_at, s.completed_at, s.archived_at,
                       (SELECT count(*) FROM people.student st WHERE st.entry_session = s.name) AS fresh_students
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

    /** the next planned session: the earliest planned one that begins after the current session (V289) */
    Optional<String> nextPlanned() {
        return jdbc.sql("SELECT policy.next_planned_session()").query(String.class).optional();
    }

    String state(String session) {
        return jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", session).query(String.class).optional().orElse(null);
    }

    /** the readiness checks of the transition into a session (V289): blocking and advisory, each with what it found */
    List<java.util.Map<String, Object>> readiness(String session) {
        return jdbc.sql("SELECT code, ok, blocking, detail FROM policy.transition_readiness(:s)").param("s", session).query().listOfRows();
    }

    /** the transition itself, in the database's one transaction: DONE, BLOCKED (with the checks) or ALREADY */
    String transition(String toSession, String mode, String reason, String minute) {
        return jdbc.sql("SELECT policy.transition_session(:s, :m, :r, :minute)::text")
                .param("s", toSession).param("m", mode).param("r", reason).param("minute", minute, Types.VARCHAR)
                .query(String.class).single();
    }

    void tellOffice(String office, String subject, String body) {
        jdbc.sql("SELECT admissions.tell_office(:o, :s, :b, NULL)").param("o", office).param("s", subject).param("b", body).query().listOfRows();
    }

    void archive(String session, String reason) {
        jdbc.sql("SELECT policy.archive_session(:s, :r)").param("s", session).param("r", reason, Types.VARCHAR).query().listOfRows();
    }

    /** the last session transitions, newest first: who or what asked, from which session to which, and the outcome */
    List<java.util.Map<String, Object>> transitions(int limit) {
        return jdbc.sql("""
                SELECT t.id, t.from_session, t.to_session, t.outcome, t.mode, t.reason, t.senate_minute, t.checks::text AS checks, t.at,
                       t.actor_office, coalesce(p.surname || ', ' || p.given_names, CASE WHEN t.mode = 'AUTOMATIC' THEN 'Session clock' ELSE NULL END) AS actor
                  FROM policy.session_transition t LEFT JOIN iam.person p ON p.id = t.actor_id
                 ORDER BY t.at DESC LIMIT :n
                """).param("n", limit).query().listOfRows();
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
                       late_registration_closes, exams_from, exams_to, results_due, query_window, state, fresh_registration_from
                  FROM policy.semester WHERE session = :session ORDER BY number
                """)
                .param("session", session)
                .query(Calendar.Semester.class)
                .list();
    }

    /** the semester's courses on offer, created for every course the curriculum offers that semester and not yet offered (V287) */
    int openCourses(String session, int number) {
        return jdbc.sql("SELECT registration.open_course_registration(:s, :n)").param("s", session).param("n", number).query(Integer.class).single();
    }

    List<Calendar.LevelLimit> levelLimits() {
        return jdbc.sql("""
                SELECT level, applies_to, min_units, max_units, carryover_counts, instrument, probation_max_units
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
    void upsertSession(String name, LocalDate startsOn, LocalDate endsOn, int semesters, String minute, String state,
                       String transitionMode, LocalDate transitionsOn) {
        jdbc.sql("""
                INSERT INTO policy.academic_session (id, name, starts_on, ends_on, semesters, senate_minute, state, transition_mode, transitions_on)
                VALUES (gen_random_uuid(), :name, :from, :to, :sems, cast(:minute as text), coalesce(cast(:state as text), 'PLANNED'),
                        coalesce(cast(:mode as text), 'MANUAL'), cast(:on as date))
                ON CONFLICT (name) DO UPDATE SET
                       starts_on       = EXCLUDED.starts_on,
                       ends_on         = EXCLUDED.ends_on,
                       semesters       = EXCLUDED.semesters,
                       senate_minute   = coalesce(cast(:minute as text), policy.academic_session.senate_minute),
                       state           = coalesce(cast(:state as text), policy.academic_session.state),
                       transition_mode = coalesce(cast(:mode as text), policy.academic_session.transition_mode),
                       transitions_on  = cast(:on as date)
                """)
                .param("name", name)
                .param("from", startsOn)
                .param("to", endsOn)
                .param("sems", semesters)
                .param("minute", minute, Types.VARCHAR)
                .param("state", state, Types.VARCHAR)
                .param("mode", transitionMode, Types.VARCHAR)
                .param("on", transitionsOn, Types.DATE)
                .update();
    }

    /** a session completed by hand, outside a transition: the record says when (V289) */
    void close(String session) {
        jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED', completed_at = coalesce(completed_at, now()) WHERE name = :name AND state <> 'ARCHIVED'")
                .param("name", session)
                .update();
    }

    void upsertSemester(String session, int number, CalendarService.SemesterIn in, String state) {
        jdbc.sql("""
                INSERT INTO policy.semester (id, session, number, lectures_from, lectures_to, registration_opens,
                       registration_closes, late_registration_closes, exams_from, exams_to, results_due,
                       query_window, state, fresh_registration_from)
                VALUES (gen_random_uuid(), :session, :n, :lf, :lt, :ro, :rc, :lrc, :ef, :et, :due,
                        cast(:query as text), :state, :fresh)
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
                       state                    = EXCLUDED.state,
                       fresh_registration_from  = EXCLUDED.fresh_registration_from
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
                .param("state", state).param("fresh", in.freshRegistrationFrom(), java.sql.Types.DATE)
                .update();
    }

    void upsertLevelLimit(int level, CalendarService.LevelIn in) {
        jdbc.sql("""
                INSERT INTO policy.level_limit (level, applies_to, min_units, max_units, carryover_counts, instrument, probation_max_units)
                VALUES (:level, :who, :min, :max, :carry, cast(:instrument as text), cast(:prob as int))
                ON CONFLICT (level) DO UPDATE SET
                       applies_to       = EXCLUDED.applies_to,
                       min_units        = EXCLUDED.min_units,
                       max_units        = EXCLUDED.max_units,
                       carryover_counts = EXCLUDED.carryover_counts,
                       instrument       = coalesce(cast(:instrument as text), policy.level_limit.instrument),
                       probation_max_units = EXCLUDED.probation_max_units
                """)
                .param("level", level)
                .param("who", in.appliesTo().trim())
                .param("min", in.minUnits())
                .param("max", in.maxUnits())
                .param("carry", in.carryoverCounts())
                .param("prob", in.probationMaxUnits(), java.sql.Types.INTEGER)
                .param("instrument", in.instrument() == null || in.instrument().isBlank() ? null : in.instrument().trim(),
                        Types.VARCHAR)
                .update();
    }
}
