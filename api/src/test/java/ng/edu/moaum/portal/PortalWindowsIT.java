package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

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
 * The portal's windows (V288): only the Director of ICT acts on them; school fees payment refuses a new reference while closed or
 * scheduled — through the API and straight against the database — and takes one again when reopened; the late period adds the
 * late payment fee the Bursar stated, and only to a student who had not settled in time; course registration is refused while
 * closed, resumes when reopened, and the late registration fee is charged in its late period; an extension moves the closing
 * and every act is on the history with its reason. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PortalWindowsIT {

    static final String SESSION = "2099/2100";
    static final String BASE = "/api/v1/portal-windows";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String ict = ItSupport.token("ict");
    String registrar = ItSupport.token("registrar");
    String bursar = ItSupport.token("bursar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2099);
        // the residue of an earlier run: the test's own windows and the notices it queued
        it.db(() -> {
            jdbc.sql("DELETE FROM policy.portal_window_event WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("DELETE FROM policy.portal_window WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("DELETE FROM platform.notice WHERE about_kind = 'student' AND about_id IN (SELECT id FROM people.student WHERE entry_session = :s AND other_names = 'Invented')").param("s", SESSION).update();
            return null;
        });
    }

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    Map<String, Object> window(Map<String, Object> page, String type, Integer semester) {
        return l(page.get("windows")).stream().filter(w -> type.equals(w.get("type")) && java.util.Objects.equals(w.get("semesterAsked"), semester)).findFirst().orElseThrow();
    }

    ResponseEntity<Map> act(String token, String type, Map<String, Object> body) {
        java.util.Map<String, Object> b = new java.util.LinkedHashMap<>(body);
        b.putIfAbsent("session", SESSION);
        return it.call(token, HttpMethod.POST, BASE + "/" + type, b);
    }

    @Test
    void theDirectorOpensAndClosesTheWindowsAndTheGatesHold() {
        int n = new Random().nextInt(9000) + 1000;
        UUID s = it.student("ZZWIN" + n, "C00023", "MOAUM/ADM/99/" + String.format("%06d", n), "MOAUM/SCI/99/" + n, 100);
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :id").param("ses", SESSION).param("id", s).update());
        it.db(() -> jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08055557777', :e, now()) ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email").param("s", s).param("e", "zzwin" + n + "@example.edu").update());
        it.db(() -> {
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 150000, 100, 'C00023')").param("s", SESSION).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, kind) VALUES (:s, 'Late payment fee', 20000, 100, 'C00023', 'LATE_PAYMENT')").param("s", SESSION).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, kind) VALUES (:s, 'Late registration fee', 10000, 100, 'C00023', 'LATE_REGISTRATION')").param("s", SESSION).update();
            return null;
        });
        String student = TestTokens.token(s, List.of("student"));
        try {
            // 1 · only the Director of ICT acts; everyone reads by default as OPEN
            assertThat(it.get(registrar, BASE + "?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
            assertThat(act(registrar, "SCHOOL_FEES_PAYMENT", Map.of("action", "CLOSE", "reason", "not mine to do")).getStatusCode().value()).isEqualTo(403);
            Map<String, Object> page = it.get(ict, BASE + "?session=" + SESSION).getBody();
            assertThat(window(page, "SCHOOL_FEES_PAYMENT", null).get("state")).isEqualTo("OPEN");
            assertThat(window(page, "SCHOOL_FEES_PAYMENT", null).get("configured")).isEqualTo(false);

            // 2 · open by default: the charge is the school fees alone, a reference is generated
            Map<String, Object> fees = it.get(student, "/api/v1/me/fees?session=" + SESSION).getBody();
            assertThat(new BigDecimal(String.valueOf(fees.get("due")))).isEqualByComparingTo("150000");
            assertThat(m(fees.get("window")).get("state")).isEqualTo("OPEN");
            ResponseEntity<Map> ref1 = it.call(student, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", SESSION, "amount", 50000));
            assertThat(ref1.getStatusCode().value()).as(String.valueOf(ref1.getBody())).isEqualTo(200);

            // 3 · closed now: the reason is required; the API refuses a new reference with the business code; the database refuses it too
            assertThat(act(ict, "SCHOOL_FEES_PAYMENT", Map.of("action", "CLOSE")).getStatusCode().value()).isEqualTo(422);
            ResponseEntity<Map> closed = act(ict, "SCHOOL_FEES_PAYMENT", Map.of("action", "CLOSE", "reason", "The payment deadline has passed."));
            assertThat(closed.getStatusCode().value()).as(String.valueOf(closed.getBody())).isEqualTo(200);
            assertThat(m(closed.getBody().get("after")).get("state")).isEqualTo("CLOSED");
            ResponseEntity<Map> shut = it.call(student, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", SESSION, "amount", 50000));
            assertThat(shut.getStatusCode().value()).isEqualTo(422);
            assertThat(shut.getBody().get("code")).isEqualTo("SCHOOL_FEES_PAYMENT_CLOSED");
            String direct = it.db(() -> { try { jdbc.sql("SELECT finance.new_reference(:s, :ses, 1000, 'School fees direct')").param("s", s).param("ses", SESSION).query(String.class).single(); return "opened"; } catch (org.springframework.dao.DataAccessException e) { return e.getMostSpecificCause().getMessage(); } });
            assertThat(direct).contains("SCHOOL_FEES_PAYMENT_CLOSED");
            assertThat(m(it.get(student, "/api/v1/me/fees?session=" + SESSION).getBody().get("window")).get("state")).isEqualTo("CLOSED");
            // the reference generated before the closing is still confirmed and counted
            it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", String.valueOf(ref1.getBody().get("reference"))).query(String.class).single());
            assertThat(new BigDecimal(String.valueOf(it.get(student, "/api/v1/me/fees?session=" + SESSION).getBody().get("paid")))).isEqualByComparingTo("50000");

            // 4 · scheduled: not yet open; then reopened now, a reference is generated again
            ResponseEntity<Map> sched = act(ict, "SCHOOL_FEES_PAYMENT", Map.of("action", "SCHEDULE", "opensAt", OffsetDateTime.now().plusDays(3).toString(), "closesAt", OffsetDateTime.now().plusDays(30).toString()));
            assertThat(sched.getStatusCode().value()).as(String.valueOf(sched.getBody())).isEqualTo(200);
            assertThat(m(sched.getBody().get("after")).get("state")).isEqualTo("SCHEDULED");
            assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", SESSION, "amount", 1000)).getStatusCode().value()).isEqualTo(422);
            ResponseEntity<Map> reopened = act(ict, "SCHOOL_FEES_PAYMENT", Map.of("action", "REOPEN", "reason", "Extension approved by management."));
            assertThat(reopened.getStatusCode().value()).as(String.valueOf(reopened.getBody())).isEqualTo(200);
            assertThat(m(reopened.getBody().get("after")).get("state")).isEqualTo("OPEN");
            assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", SESSION, "amount", 1000)).getStatusCode().value()).isEqualTo(200);

            // 5 · the late period: the normal window closed yesterday, late payment runs a week with the fee; the charge grows by the Bursar's late line
            ResponseEntity<Map> late = act(ict, "SCHOOL_FEES_PAYMENT", Map.of("action", "EDIT", "opensAt", OffsetDateTime.now().minusDays(30).toString(), "closesAt", OffsetDateTime.now().minusDays(1).toString(),
                    "lateUntil", OffsetDateTime.now().plusDays(7).toString(), "lateFeeEnabled", true));
            assertThat(late.getStatusCode().value()).as(String.valueOf(late.getBody())).isEqualTo(200);
            it.db(() -> jdbc.sql("UPDATE policy.portal_window SET forced = NULL WHERE window_type = 'SCHOOL_FEES_PAYMENT' AND session = :s AND superseded_at IS NULL").param("s", SESSION).update());
            Map<String, Object> lateFees = it.get(student, "/api/v1/me/fees?session=" + SESSION).getBody();
            assertThat(m(lateFees.get("window")).get("phase")).isEqualTo("LATE");
            assertThat(new BigDecimal(String.valueOf(lateFees.get("due")))).isEqualByComparingTo("170000");
            assertThat(l(lateFees.get("charges")).stream().map(c -> c.get("item"))).contains("Late payment fee");
            // a student who had settled before the deadline owes no late fee
            UUID settled = it.student("ZZWINP" + n, "C00023", "MOAUM/ADM/99/" + String.format("%06d", n + 1), "MOAUM/SCI/99/" + (n + 1), 100);
            it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :id").param("ses", SESSION).param("id", settled).update());
            it.db(() -> jdbc.sql("INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no) VALUES (:s, :ses, :r, 'School fees ' || :ses, 150000, now(), now() - interval '10 days', :s, 'BANK', 'RCPT-T' || :r)")
                    .param("s", settled).param("ses", SESSION).param("r", "MOAUM-FEE-T" + n).update());
            assertThat(jdbc.sql("SELECT due FROM finance.position(:s, :ses)").param("s", settled).param("ses", SESSION).query(BigDecimal.class).single()).isEqualByComparingTo("150000");

            // 6 · after the late period the window is expired: refused until the Director reopens it
            assertThat(act(ict, "SCHOOL_FEES_PAYMENT", Map.of("action", "EDIT", "lateUntil", OffsetDateTime.now().minusHours(1).toString(), "closesAt", OffsetDateTime.now().minusDays(1).toString())).getStatusCode().value()).isEqualTo(200);
            assertThat(m(it.get(student, "/api/v1/me/fees?session=" + SESSION).getBody().get("window")).get("state")).isEqualTo("EXPIRED");
            assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", SESSION, "amount", 1000)).getStatusCode().value()).isEqualTo(422);
            // an extension moves the closing later and is on the history with the previous dates
            ResponseEntity<Map> ext = act(ict, "SCHOOL_FEES_PAYMENT", Map.of("action", "EXTEND", "lateUntil", OffsetDateTime.now().plusDays(5).toString(), "reason", "Ten more days for the late payers."));
            assertThat(ext.getStatusCode().value()).as(String.valueOf(ext.getBody())).isEqualTo(200);
            assertThat(m(ext.getBody().get("after")).get("state")).isEqualTo("OPEN");
            List<Map<String, Object>> events = l(it.get(ict, BASE + "/history?session=" + SESSION + "&type=SCHOOL_FEES_PAYMENT").getBody().get("events"));
            assertThat(events.stream().map(e -> e.get("action"))).contains("CLOSE", "SCHEDULE", "REOPEN", "EDIT", "EXTEND");
            Map<String, Object> extEvent = events.stream().filter(e -> "EXTEND".equals(e.get("action"))).findFirst().orElseThrow();
            assertThat(extEvent.get("previous_late_until")).isNotNull();
            assertThat(extEvent.get("reason")).isEqualTo("Ten more days for the late payers.");
            // the students of the session were told of the closing and the reopening
            assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject LIKE 'School fees payment%'").param("s", s).query(Long.class).single()).isGreaterThanOrEqualTo(2);

            // 7 · course registration: closed for semester 1, the student cannot draft; reopened, they can; late registration charges its fee
            assertThat(it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of())).getStatusCode().value()).isEqualTo(200);
            ResponseEntity<Map> regClosed = act(ict, "COURSE_REGISTRATION", Map.of("action", "CLOSE", "semester", 1, "reason", "Registration closed pending Senate's calendar."));
            assertThat(regClosed.getStatusCode().value()).as(String.valueOf(regClosed.getBody())).isEqualTo(200);
            ResponseEntity<Map> regShut = it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of()));
            assertThat(regShut.getStatusCode().value()).isEqualTo(422);
            assertThat(regShut.getBody().get("code")).isEqualTo("COURSE_REGISTRATION_CLOSED");
            assertThat(m(m(it.get(student, "/api/v1/me/registration?session=" + SESSION + "&semester=1").getBody().get("window")).get("portal")).get("state")).isEqualTo("CLOSED");
            assertThat(act(ict, "COURSE_REGISTRATION", Map.of("action", "REOPEN", "semester", 1, "reason", "Senate's calendar released.")).getStatusCode().value()).isEqualTo(200);
            assertThat(it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of())).getStatusCode().value()).isEqualTo(200);
            assertThat(act(ict, "COURSE_REGISTRATION", Map.of("action", "EDIT", "semester", 1, "opensAt", OffsetDateTime.now().minusDays(20).toString(), "closesAt", OffsetDateTime.now().minusDays(1).toString(),
                    "lateUntil", OffsetDateTime.now().plusDays(7).toString(), "lateFeeEnabled", true)).getStatusCode().value()).isEqualTo(200);
            it.db(() -> jdbc.sql("UPDATE policy.portal_window SET forced = NULL WHERE window_type = 'COURSE_REGISTRATION' AND session = :s AND superseded_at IS NULL").param("s", SESSION).update());
            Map<String, Object> regLate = it.get(student, "/api/v1/me/registration?session=" + SESSION + "&semester=1").getBody();
            assertThat(m(m(regLate.get("window")).get("portal")).get("phase")).isEqualTo("LATE");
            assertThat(l(m(regLate.get("fees")).get("charges")).stream().map(c -> c.get("item"))).contains("Late registration fee");
            // the dashboard's indicators read the same states
            Map<String, Object> me = it.get(student, "/api/v1/me").getBody();
            assertThat(m(m(me.get("windows")).get("courseRegistration")).get("phase")).isEqualTo("LATE");
        } finally {
            it.db(() -> {
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update();
                return null;
            });
        }
    }
}
