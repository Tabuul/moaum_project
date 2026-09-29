package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import ng.edu.moaum.portal.calendar.SessionTransitionClock;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The academic session lifecycle (V289): a current session and a planned one at once; the entrant of the
 * planned session stands in it (fees, references, dashboard) while the returning student stands in the
 * current one; the transition is the Registrar's, validated, transactional, idempotent and logged, and
 * moves no student; the clock makes an automatic session current on its date and logs a blocked one;
 * a completed session is archived and not edited back. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SessionLifecycleIT {

    static final String A = "2101/2102";   // becomes current by hand
    static final String B = "2102/2103";   // planned; the entrant's session; transitioned by the Registrar
    static final String C = "2103/2104";   // automatic, ready: the clock makes it current
    static final String D = "2104/2105";   // automatic, not ready: the clock logs it blocked
    static final List<String> ALL = List.of(A, B, C, D);

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    SessionTransitionClock clock;

    ItSupport it;
    String academic = ItSupport.token("academic");
    /** the calendar is set from the Director of ICT's Portal Management; the Academic Office reads it */
    String ict = ItSupport.token("ict");
    String registrar = ItSupport.token("registrar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        reset();
    }

    /** the test's sessions planned again with nothing hanging on them: run before (residue) and after (so no far-future session of
     *  this test's stays completed or charged, which would move where every other test's student stands) */
    void reset() {
        it.db(() -> {
            jdbc.sql("DELETE FROM policy.session_transition WHERE to_session = ANY(:s) OR from_session = ANY(:s)").param("s", ALL.toArray(new String[0])).update();
            jdbc.sql("DELETE FROM policy.portal_window_event WHERE session = ANY(:s)").param("s", ALL.toArray(new String[0])).update();
            jdbc.sql("DELETE FROM policy.portal_window WHERE session = ANY(:s)").param("s", ALL.toArray(new String[0])).update();
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = ANY(:s)").param("s", ALL.toArray(new String[0])).update();
            jdbc.sql("DELETE FROM policy.semester WHERE session = ANY(:s)").param("s", ALL.toArray(new String[0])).update();
            jdbc.sql("UPDATE policy.academic_session SET state = 'PLANNED', transition_mode = 'MANUAL', transitions_on = NULL, made_current_at = NULL, completed_at = NULL, archived_at = NULL, senate_minute = NULL WHERE name = ANY(:s)")
                    .param("s", ALL.toArray(new String[0])).update();
            return null;
        });
    }

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    Map<String, Object> session(String starts, String ends, Map<String, Object> more) {
        Map<String, Object> b = new java.util.LinkedHashMap<>(Map.of("startsOn", starts, "endsOn", ends, "semesters", 2, "state", "PLANNED"));
        b.putAll(more);
        return b;
    }

    Map<String, Object> row(Map<String, Object> calendar, String name) {
        return l(calendar.get("sessions")).stream().filter(s -> name.equals(s.get("name"))).findFirst().orElseThrow();
    }

    Map<String, Object> calendar() {
        return it.get(academic, "/api/v1/calendar").getBody();
    }

    @Test
    void aPlannedSessionIsARealContextAndTheTransitionIsOneGuardedAct() {
        int n = new Random().nextInt(9000) + 1000;
        // 1 · the Director of ICT sets both up (the Academic Office no longer may): A with its minute, B planned with a dated first
        //     semester and a fee schedule but no minute yet
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/calendar/sessions/" + A, session("2101-10-01", "2102-08-31", Map.of("senateMinute", "SEN/T/2101/1"))).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/calendar/sessions/" + A, session("2101-10-01", "2102-08-31", Map.of("senateMinute", "SEN/T/2101/1"))).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/calendar/sessions/" + B, session("2102-10-01", "2103-08-31", Map.of())).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/calendar/sessions/" + B + "/semesters/1",
                Map.of("lecturesFrom", "2102-10-05", "state", "NOT_YET_OPEN")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/calendar/sessions/" + B + "/semesters/1",
                Map.of("lecturesFrom", "2102-10-05", "lecturesTo", "2103-02-20", "registrationOpens", "2102-10-01", "registrationCloses", "2102-11-30", "state", "NOT_YET_OPEN")).getStatusCode().value()).isEqualTo(200);
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 150000, 100, 'C00023')").param("s", B).update());

        // 2 · readiness names what is missing: the minute blocks; the calendar names B as the next planned session
        Map<String, Object> ready = it.get(academic, "/api/v1/calendar/sessions/" + B + "/readiness").getBody();
        assertThat(ready.get("ready")).isEqualTo(false);
        assertThat(l(ready.get("checks")).stream().filter(c -> "SENATE_MINUTE".equals(c.get("code"))).findFirst().orElseThrow().get("ok")).isEqualTo(false);
        assertThat(l(ready.get("checks")).stream().filter(c -> "FEE_SCHEDULE".equals(c.get("code"))).findFirst().orElseThrow().get("ok")).isEqualTo(true);

        // 3 · the Registrar makes A current (the Academic Office may not); B stays planned beside it
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/calendar/sessions/" + A + "/make-current", Map.of("senateMinute", "SEN/T/2101/1")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> made = it.call(registrar, HttpMethod.POST, "/api/v1/calendar/sessions/" + A + "/make-current", Map.of("senateMinute", "SEN/T/2101/1"));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        assertThat(made.getBody().get("current")).isEqualTo(A);
        assertThat(made.getBody().get("next")).isEqualTo(B);
        assertThat(row(made.getBody(), B).get("state")).isEqualTo("PLANNED");
        assertThat(row(made.getBody(), A).get("madeCurrentAt")).isNotNull();

        // 4 · the entrant of B stands in B while A is current; the returning student stands in A
        UUID fresh = it.student("ZZLIFE" + n, "C00023", "MOAUM/ADM/01/" + String.format("%06d", n), null, 100);
        UUID returning = it.student("ZZLIFER" + n, "C00023", "MOAUM/ADM/01/" + String.format("%06d", n + 1), "MOAUM/SCI/01/" + n, 200);
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :b WHERE id = :id").param("b", B).param("id", fresh).update());
        String freshToken = TestTokens.token(fresh, List.of("student"));
        // a Registrar with an email on the record, so the offices' notice of the transition has somebody to reach
        UUID clerk = it.person("ZZLIFE-REG-" + n, "Registrarclerk");
        it.db(() -> {
            jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", "zzlife.registrar" + n + "@example.edu").param("p", clerk).update();
            jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from)
                    VALUES (gen_random_uuid(), :p, 'registrar', 'institution', 'SessionLifecycleIT: test grant', :by, current_date)
                    ON CONFLICT DO NOTHING
                    """).param("p", clerk).param("by", UUID.randomUUID()).update();
            return null;
        });
        String returningToken = TestTokens.token(returning, List.of("student"));
        try {
            Map<String, Object> me = it.get(freshToken, "/api/v1/me").getBody();
            assertThat(me.get("session")).isEqualTo(B);
            Map<String, Object> academicCtx = m(me.get("academic"));
            assertThat(academicCtx.get("context")).isEqualTo("PREPARING");
            assertThat(academicCtx.get("current_session")).isEqualTo(A);
            assertThat(academicCtx.get("status")).isEqualTo("FRESH_STUDENT_PREPARING");
            assertThat(m(academicCtx.get("steps")).get("matriculation")).isEqualTo(false);
            Map<String, Object> back = it.get(returningToken, "/api/v1/me").getBody();
            assertThat(back.get("session")).isEqualTo(A);
            assertThat(m(back.get("academic")).get("context")).isEqualTo("CURRENT");
            // the entrant's fees are B's fees, and a reference generated is a B reference - never an A invoice
            Map<String, Object> fees = it.get(freshToken, "/api/v1/me/fees").getBody();
            assertThat(fees.get("session")).isEqualTo(B);
            assertThat(new BigDecimal(String.valueOf(fees.get("due")))).isEqualByComparingTo("150000");
            ResponseEntity<Map> ref = it.call(freshToken, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("amount", 50000));
            assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
            assertThat(jdbc.sql("SELECT session FROM finance.payment_reference WHERE reference = :r").param("r", String.valueOf(ref.getBody().get("reference"))).query(String.class).single()).isEqualTo(B);

            // 5 · the transition is the Registrar's or the Director of ICT's, confirmed, and blocked while the minute is missing - the
            //     blocked attempt is on the log
            assertThat(it.call(academic, HttpMethod.POST, "/api/v1/calendar/sessions/" + B + "/transition", Map.of("confirm", "TRANSITION", "reason", "not mine")).getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> ictUnconfirmed = it.call(ict, HttpMethod.POST, "/api/v1/calendar/sessions/" + B + "/transition", Map.of("confirm", "yes", "reason", "Senate resolved"));
            assertThat(ictUnconfirmed.getStatusCode().value()).isEqualTo(422);
            assertThat(ictUnconfirmed.getBody().get("code")).isEqualTo("SESSION_TRANSITION_UNCONFIRMED");
            ResponseEntity<Map> unconfirmed = it.call(registrar, HttpMethod.POST, "/api/v1/calendar/sessions/" + B + "/transition", Map.of("confirm", "yes", "reason", "Senate resolved"));
            assertThat(unconfirmed.getStatusCode().value()).isEqualTo(422);
            assertThat(unconfirmed.getBody().get("code")).isEqualTo("SESSION_TRANSITION_UNCONFIRMED");
            ResponseEntity<Map> blocked = it.call(registrar, HttpMethod.POST, "/api/v1/calendar/sessions/" + B + "/transition", Map.of("confirm", "TRANSITION", "reason", "Senate resolved to run " + B));
            assertThat(blocked.getStatusCode().value()).isEqualTo(422);
            assertThat(blocked.getBody().get("code")).isEqualTo("SESSION_TRANSITION_BLOCKED");
            assertThat(String.valueOf(blocked.getBody().get("detail"))).contains("Senate minute");
            Map<String, Object> cal = calendar();
            assertThat(cal.get("current")).isEqualTo(A);
            assertThat(l(cal.get("transitions")).stream().anyMatch(t -> B.equals(t.get("to_session")) && "BLOCKED".equals(t.get("outcome")) && "MANUAL".equals(t.get("mode")))).isTrue();

            // 6 · with the minute the transition is done: A completed, B current, in one act; then it is idempotent
            ResponseEntity<Map> done = it.call(registrar, HttpMethod.POST, "/api/v1/calendar/sessions/" + B + "/transition",
                    Map.of("confirm", "TRANSITION", "reason", "Senate resolved to run " + B + "; " + A + " has ended", "senateMinute", "SEN/T/2102/1"));
            assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
            assertThat(done.getBody().get("outcome")).isEqualTo("DONE");
            assertThat(done.getBody().get("from")).isEqualTo(A);
            cal = m(done.getBody().get("calendar"));
            assertThat(cal.get("current")).isEqualTo(B);
            assertThat(row(cal, A).get("state")).isEqualTo("CLOSED");
            assertThat(row(cal, A).get("completedAt")).isNotNull();
            assertThat(row(cal, B).get("state")).isEqualTo("CURRENT");
            assertThat(row(cal, B).get("senateMinute")).isEqualTo("SEN/T/2102/1");
            ResponseEntity<Map> again = it.call(registrar, HttpMethod.POST, "/api/v1/calendar/sessions/" + B + "/transition", Map.of("confirm", "TRANSITION", "reason", "once more"));
            assertThat(again.getStatusCode().value()).isEqualTo(200);
            assertThat(again.getBody().get("outcome")).isEqualTo("ALREADY");
            assertThat(jdbc.sql("SELECT count(*) FROM policy.academic_session WHERE state = 'CURRENT'").query(Long.class).single()).isEqualTo(1L);
            assertThat(jdbc.sql("SELECT count(*) FROM policy.session_transition WHERE to_session = :b AND outcome = 'DONE'").param("b", B).query(Long.class).single()).isEqualTo(1L);
            // the offices were told
            assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE subject LIKE 'Academic session transition: ' || :b || '%'").param("b", B).query(Long.class).single()).isGreaterThan(0L);

            // 7 · no student moved: the entrant continues under the same account, now in the current session; the returning student
            //     stands in the new current session with no enrolment created and their history untouched
            me = it.get(freshToken, "/api/v1/me").getBody();
            assertThat(me.get("id")).isEqualTo(fresh.toString());
            assertThat(me.get("session")).isEqualTo(B);
            assertThat(m(me.get("academic")).get("context")).isEqualTo("CURRENT");
            assertThat(m(me.get("academic")).get("status")).isEqualTo("CURRENT_SESSION");
            assertThat(jdbc.sql("SELECT session FROM finance.payment_reference WHERE reference = :r").param("r", String.valueOf(ref.getBody().get("reference"))).query(String.class).single()).isEqualTo(B);
            back = it.get(returningToken, "/api/v1/me").getBody();
            assertThat(back.get("session")).isEqualTo(B);
            assertThat(back.get("entrySession")).isEqualTo("2020/2021");
            assertThat(jdbc.sql("SELECT count(*) FROM people.enrolment WHERE student_id = :s AND session = :b").param("s", returning).param("b", B).query(Long.class).single()).isEqualTo(0L);
            assertThat(jdbc.sql("SELECT count(*) FROM people.student WHERE surname = :n AND other_names = 'Invented'").param("n", "ZZLIFE" + n).query(Long.class).single()).isEqualTo(1L);

            // 8 · the clock: C is automatic, ready and due today, so it becomes current; D is automatic and due but has no semester or fee, so it is logged blocked
            String today = LocalDate.now().toString();
            assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/calendar/sessions/" + C, session("2103-10-01", "2104-08-31", Map.of("senateMinute", "SEN/T/2103/1", "transitionMode", "AUTOMATIC", "transitionsOn", today))).getStatusCode().value()).isEqualTo(200);
            assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/calendar/sessions/" + C + "/semesters/1", Map.of("lecturesFrom", "2103-10-05", "lecturesTo", "2104-02-20", "state", "NOT_YET_OPEN")).getStatusCode().value()).isEqualTo(200);
            it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 160000, 100, 'C00023')").param("s", C).update());
            assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/calendar/sessions/" + D, session("2104-10-01", "2105-08-31", Map.of("senateMinute", "SEN/T/2104/1", "transitionMode", "AUTOMATIC", "transitionsOn", today))).getStatusCode().value()).isEqualTo(200);
            assertThat(m(it.get(academic, "/api/v1/calendar/sessions/" + C + "/readiness").getBody()).get("readyForAutomatic")).isEqualTo(true);
            List<Map<String, Object>> outcomes = clock.run();
            assertThat(outcomes.stream().filter(o -> C.equals(String.valueOf(o.get("to")))).findFirst().orElseThrow().get("outcome")).isEqualTo("DONE");
            assertThat(outcomes.stream().filter(o -> D.equals(String.valueOf(o.get("to")))).findFirst().orElseThrow().get("outcome")).isEqualTo("BLOCKED");
            cal = calendar();
            assertThat(cal.get("current")).isEqualTo(C);
            assertThat(row(cal, B).get("state")).isEqualTo("CLOSED");
            assertThat(row(cal, D).get("state")).isEqualTo("PLANNED");
            assertThat(l(cal.get("transitions")).stream().anyMatch(t -> C.equals(t.get("to_session")) && "DONE".equals(t.get("outcome")) && "AUTOMATIC".equals(t.get("mode")))).isTrue();
            assertThat(l(cal.get("transitions")).stream().anyMatch(t -> D.equals(t.get("to_session")) && "BLOCKED".equals(t.get("outcome")) && "AUTOMATIC".equals(t.get("mode")))).isTrue();
            // once a day: the clock does not try D again today, and C is no longer due
            assertThat(clock.run()).isEmpty();

            // 9 · a completed session is archived and not edited back; a planned one is not archived
            assertThat(it.call(academic, HttpMethod.POST, "/api/v1/calendar/sessions/" + A + "/archive", Map.of("reason", "History")).getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> archived = it.call(ict, HttpMethod.POST, "/api/v1/calendar/sessions/" + A + "/archive", Map.of("reason", "History"));
            assertThat(archived.getStatusCode().value()).as(String.valueOf(archived.getBody())).isEqualTo(200);
            assertThat(row(archived.getBody(), A).get("state")).isEqualTo("ARCHIVED");
            assertThat(row(archived.getBody(), A).get("archivedAt")).isNotNull();
            ResponseEntity<Map> notYet = it.call(ict, HttpMethod.POST, "/api/v1/calendar/sessions/" + D + "/archive", Map.of("reason", "too early"));
            assertThat(notYet.getStatusCode().value()).isEqualTo(422);
            assertThat(notYet.getBody().get("code")).isEqualTo("SESSION_ARCHIVE_REFUSED");
            ResponseEntity<Map> reopened = it.call(ict, HttpMethod.PUT, "/api/v1/calendar/sessions/" + A, session("2101-10-01", "2102-08-31", Map.of()));
            assertThat(reopened.getStatusCode().value()).isEqualTo(422);
            assertThat(reopened.getBody().get("code")).isEqualTo("SESSION_ARCHIVED");
            // the archived session no longer counts as the one a returning student stands in between sessions: the latest run one does
            assertThat(it.get(returningToken, "/api/v1/me").getBody().get("session")).isEqualTo(C);
        } finally {
            // nothing current and nothing charged when the test is done: the sessions go back to planned
            reset();
        }
    }
}
