package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * V438 through the API: three days and one day before a registration window closes, the students of the session who have not
 * submitted a registration are reminded, once per deadline and day, through the WINDOW_CLOSING template; a provider's delivery
 * report lands on the message it names as DELIVERED or BOUNCED and never changes its state.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class ClosingRemindersIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    String ict;
    String tag;
    String ses;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(900_000) + 100_000);
        ict = TestTokens.token(it.person("ZZCLR-ICT-" + tag, "ZZCLRICT"), List.of("ict"));
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
        ses = "2088/2089";
        it.session(ses, 2088);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private UUID studentOfSession(String surname, String adm, String email, String phone) {
        UUID s = it.student(surname, "C00023", adm, null, 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :s").param("ses", ses).param("s", s).update();
            jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:s, :p, :e) ON CONFLICT (student_id) DO UPDATE SET phone = EXCLUDED.phone, email = EXCLUDED.email")
                    .param("s", s).param("p", phone).param("e", email).update();
            return null;
        });
        return s;
    }

    private void drain() {
        for (int i = 0; i < 30; i++) {
            int ran = it.db(() -> jdbc.sql("SELECT count(*) FROM platform.run_notice_job(100000)").query(Integer.class).single());
            if (ran == 0) {
                return;
            }
        }
    }

    private int told(UUID student, UUID window, int days) {
        return it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND template_key LIKE 'WINDOW_CLOSING%' AND event_key LIKE :k")
                .param("s", student).param("k", "window-closing:" + window + ":%:" + days).query(Integer.class).single());
    }

    @Test
    void studentsNotYetRegisteredAreRemindedThreeDaysAndOneDayBeforeRegistrationCloses() {
        int n = new Random().nextInt(9000) + 1000;
        UUID a = studentOfSession("ITCLRA" + n, "MOAUM/ADM/88/00" + n, "clr-a-" + n + "@example.test", "0800" + (1000000 + n));
        UUID b = studentOfSession("ITCLRB" + n, "MOAUM/ADM/88/01" + n, "clr-b-" + n + "@example.test", "0800" + (2000000 + n));
        // the window closes at noon, Lagos, three days from today; B has submitted a registration, A has not
        UUID window = it.db(() -> {
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at) VALUES (gen_random_uuid(), :b, :ses, 1, 100, 'SUBMITTED', now())")
                    .param("b", b).param("ses", ses).update();
            jdbc.sql("UPDATE policy.portal_window SET superseded_at = now() WHERE window_type = 'COURSE_REGISTRATION' AND session = :ses AND semester = 1 AND superseded_at IS NULL")
                    .param("ses", ses).update();   // an earlier run's window gives way
            return jdbc.sql("INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, created_office) VALUES ('COURSE_REGISTRATION', :ses, 1, now() - interval '1 day', "
                    + "(((now() AT TIME ZONE 'Africa/Lagos')::date + 3)::timestamp + interval '12 hours') AT TIME ZONE 'Africa/Lagos', 'ict') RETURNING id")
                    .param("ses", ses).query(UUID.class).single();
        });
        assertThat(it.db(() -> jdbc.sql("SELECT policy.window_done('COURSE_REGISTRATION', :ses, 1, :s)").param("ses", ses).param("s", b).query(Boolean.class).single())).isTrue();
        assertThat(it.db(() -> jdbc.sql("SELECT policy.window_done('COURSE_REGISTRATION', :ses, 1, :s)").param("ses", ses).param("s", a).query(Boolean.class).single())).isFalse();
        // nothing to pay is nothing to be reminded of
        assertThat(it.db(() -> jdbc.sql("SELECT policy.window_done('SCHOOL_FEES_PAYMENT', :ses, NULL, :s)").param("ses", ses).param("s", a).query(Boolean.class).single())).isTrue();
        // the daily pass, run now: the window is three days from closing
        Map<String, Object> run = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/closing-reminders/run", Map.of()));
        assertThat(((Number) run.get("queued")).intValue()).isGreaterThanOrEqualTo(1);
        drain();
        assertThat(told(a, window, 3)).isEqualTo(3);   // e-mail, SMS and the portal
        assertThat(told(b, window, 3)).isEqualTo(0);
        String subject = it.db(() -> jdbc.sql("SELECT subject FROM platform.notice WHERE about_id = :s AND template_key LIKE 'WINDOW_CLOSING%' AND channel = 'EMAIL' AND event_key LIKE :k")
                .param("s", a).param("k", "window-closing:" + window + ":%:3").query(String.class).single());
        assertThat(subject).contains("closes in 3 days").contains(ses);
        // the same day again: queued once per deadline and day
        body(it.call(ict, HttpMethod.POST, "/api/v1/notices/closing-reminders/run", Map.of()));
        drain();
        assertThat(told(a, window, 3)).isEqualTo(3);
        // the day before: the pass as it would run then
        int queued = it.db(() -> jdbc.sql("SELECT platform.queue_closing_reminders((SELECT closes_at - interval '1 day' FROM policy.portal_window WHERE id = :w))").param("w", window).query(Integer.class).single());
        assertThat(queued).isGreaterThanOrEqualTo(1);
        drain();
        assertThat(told(a, window, 1)).isEqualTo(3);
        assertThat(told(b, window, 1)).isEqualTo(0);
        assertThat(it.db(() -> jdbc.sql("SELECT subject FROM platform.notice WHERE about_id = :s AND template_key LIKE 'WINDOW_CLOSING%' AND channel = 'SMS' AND event_key LIKE :k")
                .param("s", a).param("k", "window-closing:" + window + ":%:1").query(String.class).single())).contains("closes tomorrow");
        // the switch
        body(it.call(ict, HttpMethod.PUT, "/api/v1/notices/settings", Map.of("closingReminders", false)));
        assertThat(body(it.get(ict, "/api/v1/notices/settings")).get("closing_reminders")).isEqualTo(false);
        assertThat(it.db(() -> jdbc.sql("SELECT platform.queue_closing_reminders(now() + interval '2 days')").query(Integer.class).single())).isEqualTo(0);
        body(it.call(ict, HttpMethod.PUT, "/api/v1/notices/settings", Map.of("closingReminders", true)));
    }

    @SuppressWarnings("unchecked")
    @Test
    void aProvidersWordLandsOnTheMessageAndNeverChangesItsState() {
        String token = String.valueOf(body(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/receipt-token", Map.of())).get("token"));
        assertThat(token).hasSize(64);
        assertThat(body(it.get(ict, "/api/v1/platform/notices")).get("receiptToken")).isEqualTo(token);
        String to = "rcpt-" + tag + "@example.test";
        UUID sent = it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'IT receipt', 'body', 'test', NULL)").param("to", to).query(UUID.class).single());
        UUID cancelled = it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', :to, 'IT receipt cancelled', 'body', 'test', NULL)").param("to", "rcpt2-" + tag + "@example.test").query(UUID.class).single());
        it.db(() -> {
            jdbc.sql("UPDATE platform.notice SET state = 'SENT', sent_at = now(), provider_id = :p WHERE id = :id").param("p", "rs-" + tag).param("id", sent).update();
            jdbc.sql("UPDATE platform.notice SET state = 'CANCELLED', cancelled_at = now(), cancel_reason = 'IT' WHERE id = :id").param("id", cancelled).update();
            return null;
        });
        // the door refuses a report without the token
        assertThat(open.post().uri("/api/v1/notices/receipts/resend?token=wrong").contentType(MediaType.APPLICATION_JSON)
                .body("{\"type\":\"email.delivered\",\"data\":{\"email_id\":\"rs-" + tag + "\"}}").retrieve().toEntity(String.class).getStatusCode().value()).isEqualTo(403);
        // Resend: delivered, then bounced with the reason
        ResponseEntity<Map> r = open.post().uri("/api/v1/notices/receipts/resend?token=" + token).contentType(MediaType.APPLICATION_JSON)
                .body("{\"type\":\"email.delivered\",\"data\":{\"email_id\":\"rs-" + tag + "\"}}").retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).isEqualTo(200);
        assertThat(((List<Map<String, Object>>) r.getBody().get("outcomes")).get(0).get("outcome")).isEqualTo("DELIVERED");
        Map<String, Object> row = it.db(() -> jdbc.sql("SELECT state, delivery_state, delivery_detail FROM platform.notice WHERE id = :id").param("id", sent).query().singleRow());
        assertThat(row.get("state")).isEqualTo("SENT");
        assertThat(row.get("delivery_state")).isEqualTo("DELIVERED");
        r = open.post().uri("/api/v1/notices/receipts/resend").header("X-Receipt-Token", token).contentType(MediaType.APPLICATION_JSON)
                .body("{\"type\":\"email.bounced\",\"data\":{\"email_id\":\"rs-" + tag + "\",\"bounce\":{\"message\":\"mailbox full\"}}}").retrieve().toEntity(Map.class);
        assertThat(((List<Map<String, Object>>) r.getBody().get("outcomes")).get(0).get("outcome")).isEqualTo("BOUNCED");
        row = it.db(() -> jdbc.sql("SELECT state, delivery_state, delivery_detail FROM platform.notice WHERE id = :id").param("id", sent).query().singleRow());
        assertThat(row.get("delivery_state")).isEqualTo("BOUNCED");
        assertThat(row.get("delivery_detail")).isEqualTo("mailbox full");
        // eBulkSMS, as form fields, on a message the portal cancelled: logged, nothing changed
        r = open.post().uri("/api/v1/notices/receipts/ebulksms?token=" + token).contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body("msgid=" + cancelled + "&status=DELIVRD").retrieve().toEntity(Map.class);
        assertThat(((List<Map<String, Object>>) r.getBody().get("outcomes")).get(0).get("outcome")).isEqualTo("NOT_SENT");
        row = it.db(() -> jdbc.sql("SELECT state, delivery_state FROM platform.notice WHERE id = :id").param("id", cancelled).query().singleRow());
        assertThat(row.get("state")).isEqualTo("CANCELLED");
        assertThat(row.get("delivery_state")).isNull();
        // a report on nothing the portal sent; a list of reports matched by the notice's own id
        r = open.post().uri("/api/v1/notices/receipts/generic?token=" + token).contentType(MediaType.APPLICATION_JSON)
                .body("{\"id\":\"nothing-" + tag + "\",\"status\":\"delivered\"}").retrieve().toEntity(Map.class);
        assertThat(((List<Map<String, Object>>) r.getBody().get("outcomes")).get(0).get("outcome")).isEqualTo("UNMATCHED");
        r = open.post().uri("/api/v1/notices/receipts/ebulksms?token=" + token).contentType(MediaType.APPLICATION_JSON)
                .body("[{\"msgid\":\"" + sent + "\",\"status\":\"DELIVRD\"}]").retrieve().toEntity(Map.class);
        assertThat(((List<Map<String, Object>>) r.getBody().get("outcomes")).get(0).get("outcome")).isEqualTo("DELIVERED");
        // on the record: the receipts, the counts, the message's own line
        Map<String, Object> outbox = body(it.get(ict, "/api/v1/platform/notices?state=SENT&q=" + to));
        assertThat(((List<Map<String, Object>>) outbox.get("receipts")).stream().map(x -> x.get("outcome"))).contains("DELIVERED", "BOUNCED", "NOT_SENT", "UNMATCHED");
        assertThat(((List<Map<String, Object>>) outbox.get("recent")).get(0).get("delivery_state")).isEqualTo("DELIVERED");
        Map<String, Object> emailRow = ((List<Map<String, Object>>) outbox.get("byChannel")).stream().filter(x -> "EMAIL".equals(x.get("channel"))).findFirst().orElseThrow();
        assertThat(((Number) emailRow.get("delivered")).intValue()).isGreaterThanOrEqualTo(1);
    }
}
