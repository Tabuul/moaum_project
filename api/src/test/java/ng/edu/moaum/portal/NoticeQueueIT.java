package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import java.sql.Statement;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import javax.sql.DataSource;
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

import ng.edu.moaum.portal.platform.NoticeRepository;

/**
 * V436 through the API: the delivery switches hold e-mail and SMS while the modules go on generating, and keep a portal notice
 * from being made; the pending queue is cancelled (never deleted) only with queue processing paused and under the dispatcher's
 * own lock, with a reason, leaving sent and failed history as it was; a cancelled message is never picked again, by the
 * dispatcher or by a retry; a job still running is ended so it does not refill the queue.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class NoticeQueueIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    NoticeRepository notices;
    @Autowired
    DataSource dataSource;

    ItSupport it;
    String ict;
    UUID ictPerson;
    String tag;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(900_000) + 100_000);
        ictPerson = it.person("ZZNQ-ICT-" + tag, "ZZNQICT");
        ict = TestTokens.token(ictPerson, List.of("ict"));
        // every switch on, whatever an earlier run left
        body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/delivery", Map.of("dispatch", true, "email", true, "sms", true, "portal", true)));
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        return String.valueOf(r.getBody().get("code"));
    }

    private UUID queue(String channel, String to) {
        return it.db(() -> jdbc.sql("SELECT platform.queue_notice(:c, :to, :s, 'An integration test message', 'test', NULL)")
                .param("c", channel).param("to", to).param("s", "IT queue " + tag).query(UUID.class).single());
    }

    private String state(UUID id) {
        return it.db(() -> jdbc.sql("SELECT state FROM platform.notice WHERE id = :id").param("id", id).query(String.class).single());
    }

    private boolean sendable(UUID id) {
        return notices.sendable(200_000).stream().anyMatch(q -> q.id().equals(id));
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> delivery() {
        return (Map<String, Object>) body(it.get(ict, "/api/v1/platform/notices")).get("delivery");
    }

    @Test
    void theSwitchesHoldDeliveryWhileGenerationGoesOn() {
        UUID e = queue("EMAIL", "nq-" + tag + "@example.test");
        UUID s = queue("SMS", "0803" + tag + "1");
        assertThat(state(e)).isEqualTo("QUEUED");
        assertThat(sendable(e)).isTrue();
        assertThat(sendable(s)).isTrue();
        // e-mail delivery off: the e-mail is generated and held; the SMS still goes
        Map<String, Object> d = body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/delivery", Map.of("email", false)));
        assertThat(d.get("email_delivery")).isEqualTo(false);
        assertThat(delivery().get("email_delivery")).isEqualTo(false);
        UUID e2 = queue("EMAIL", "nq2-" + tag + "@example.test");
        assertThat(state(e2)).isEqualTo("QUEUED");
        assertThat(sendable(e2)).isFalse();
        assertThat(sendable(s)).isTrue();
        assertThat(notices.sendable(200_000).stream().map(NoticeRepository.Queued::channel)).doesNotContain("EMAIL");
        // queue processing paused: nothing goes at all, and the pause is on the record
        d = body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/delivery", Map.of("dispatch", false)));
        assertThat(d.get("dispatch_enabled")).isEqualTo(false);
        assertThat(d.get("dispatch_paused_at")).isNotNull();
        assertThat(notices.sendable(200_000)).isEmpty();
        // back on
        d = body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/delivery", Map.of("dispatch", true, "email", true)));
        assertThat(d.get("dispatch_paused_at")).isNull();
        assertThat(sendable(e)).isTrue();
        assertThat(sendable(e2)).isTrue();
        // the portal switch keeps a portal notice from being made at all
        body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/delivery", Map.of("portal", false)));
        UUID none = it.db(() -> jdbc.sql("SELECT platform.queue_notice('PORTAL', NULL, 'IT portal', 'x', 'person', :p, :k, NULL, NULL)")
                .param("p", ictPerson).param("k", "it-nq:" + tag + ":off").query(UUID.class).optional().orElse(null));
        assertThat(none).isNull();
        body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/delivery", Map.of("portal", true)));
        UUID made = it.db(() -> jdbc.sql("SELECT platform.queue_notice('PORTAL', NULL, 'IT portal', 'x', 'person', :p, :k, NULL, NULL)")
                .param("p", ictPerson).param("k", "it-nq:" + tag + ":on").query(UUID.class).single());
        assertThat(state(made)).isEqualTo("SENT");
        // a student has no say
        String student = TestTokens.token(it.student("ITNQS" + tag, "C00023", "MOAUM/ADM/87/07" + tag.substring(0, 4), null, 100), List.of("student"));
        assertThat(it.call(student, HttpMethod.PUT, "/api/v1/platform/notices/delivery", Map.of("sms", false)).getStatusCode().value()).isIn(403, 422);
    }

    @SuppressWarnings("unchecked")
    @Test
    void thePendingQueueIsCancelledUnderTheLockAndNeverSentAfter() throws Exception {
        UUID e1 = queue("EMAIL", "nqc1-" + tag + "@example.test");
        UUID e2 = queue("EMAIL", "nqc2-" + tag + "@example.test");
        UUID s1 = queue("SMS", "0805" + tag + "1");
        UUID failed = queue("EMAIL", "not an address " + tag);
        assertThat(state(failed)).isEqualTo("FAILED");
        try {
            // refused: no channel, no reason, the portal; the office is told what is wrong, and nothing is cancelled
            assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/clear", Map.of("channels", List.of(), "reason", "x")))).isEqualTo("NOTICE_CLEAR_CHANNEL");
            assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/clear", Map.of("channels", List.of("EMAIL"), "reason", " ")))).isEqualTo("NOTICE_CLEAR_REASON");
            assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/clear", Map.of("channels", List.of("PORTAL"), "reason", "x")))).isEqualTo("NOTICE_CLEAR_CHANNEL");
            assertThat(state(e1)).isEqualTo("QUEUED");
            // a batch in flight holds the dispatcher's lock: the clearance waits for it and, when it does not end, says so rather than cancelling underneath it
            try (Connection c = dataSource.getConnection(); Statement st = c.createStatement()) {
                st.execute("SELECT pg_advisory_lock(hashtext('job:notice-dispatcher'))");
                try {
                    assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/clear", Map.of("channels", List.of("EMAIL", "SMS"), "reason", "x")))).isEqualTo("NOTICE_DISPATCH_BUSY");
                } finally {
                    st.execute("SELECT pg_advisory_unlock(hashtext('job:notice-dispatcher'))");
                }
            }
            assertThat(state(e1)).isEqualTo("QUEUED");
            // only the ICT Director and the Super Administrator clear; an administrator reads
            String admin = TestTokens.token(it.person("ZZNQ-ADM-" + tag, "ZZNQADM"), List.of("admin"));
            assertThat(it.call(admin, HttpMethod.POST, "/api/v1/platform/notices/clear", Map.of("channels", List.of("EMAIL"), "reason", "x")).getStatusCode().value()).isEqualTo(403);
            // cleared: e-mail and SMS cancelled with the reason, by whom; the failed one is history and stays; processing stays paused
            Map<String, Object> done = body(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/clear",
                    Map.of("channels", List.of("EMAIL", "SMS"), "reason", "Pending notification queue cancelled during portal testing")));
            assertThat(((Number) done.get("email_cancelled")).intValue()).isGreaterThanOrEqualTo(2);
            assertThat(((Number) done.get("sms_cancelled")).intValue()).isGreaterThanOrEqualTo(1);
            assertThat(((Number) done.get("email_remaining")).intValue()).isEqualTo(0);
            assertThat(((Number) done.get("sms_remaining")).intValue()).isEqualTo(0);
            assertThat(done.get("channels")).isEqualTo("EMAIL,SMS");
            Map<String, Object> verification = (Map<String, Object>) done.get("verification");
            assertThat(verification.get("dispatch_enabled")).isEqualTo(false);
            for (Map<String, Object> p : (List<Map<String, Object>>) verification.get("pending")) {
                assertThat(((Number) p.get("pending")).intValue()).as(String.valueOf(p)).isEqualTo(0);
            }
            assertThat(state(e1)).isEqualTo("CANCELLED");
            assertThat(state(e2)).isEqualTo("CANCELLED");
            assertThat(state(s1)).isEqualTo("CANCELLED");
            assertThat(state(failed)).isEqualTo("FAILED");
            Map<String, Object> row = it.db(() -> jdbc.sql("SELECT cancel_reason, cancelled_by, cancelled_at FROM platform.notice WHERE id = :id").param("id", e1).query().singleRow());
            assertThat(row.get("cancel_reason")).isEqualTo("Pending notification queue cancelled during portal testing");
            assertThat(row.get("cancelled_by")).isEqualTo(ictPerson);
            assertThat(delivery().get("dispatch_enabled")).isEqualTo(false);
            // resumed: the dispatcher never picks a cancelled message, nor does a retry put it back
            body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/delivery", Map.of("dispatch", true)));
            assertThat(sendable(e1)).isFalse();
            assertThat(sendable(s1)).isFalse();
            body(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/retry-failed", Map.of()));
            assertThat(state(e1)).isEqualTo("CANCELLED");
            assertThat(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/" + e1 + "/retry", Map.of()).getStatusCode().value()).isEqualTo(200);
            assertThat(state(e1)).isEqualTo("CANCELLED");
            // on the record: the outbox counts, the last clearance, the history searched by state
            Map<String, Object> outbox = body(it.get(ict, "/api/v1/platform/notices?state=CANCELLED&q=nqc1-" + tag));
            assertThat(((Number) outbox.get("cancelled")).intValue()).isGreaterThanOrEqualTo(3);
            Map<String, Object> last = (Map<String, Object>) outbox.get("lastClearance");
            assertThat(last).isNotNull();
            assertThat(((Number) last.get("email_cancelled")).intValue()).isGreaterThanOrEqualTo(2);
            assertThat(last.get("reason")).isEqualTo("Pending notification queue cancelled during portal testing");
            assertThat(last.get("cleared_by_name")).isNotNull();
            assertThat(((List<Map<String, Object>>) outbox.get("recent")).stream().map(r -> r.get("state"))).containsOnly("CANCELLED");
            assertThat(it.getList(ict, "/api/v1/platform/notices/clearances").getStatusCode().value()).isEqualTo(200);
        } finally {
            body(it.call(ict, HttpMethod.PUT, "/api/v1/platform/notices/delivery", Map.of("dispatch", true, "email", true, "sms", true, "portal", true)));
        }
    }

    @SuppressWarnings("unchecked")
    @Test
    void aJobStillRunningIsEndedSoItDoesNotRefillTheQueue() {
        UUID job = it.db(() -> jdbc.sql("INSERT INTO platform.notice_job (kind, payload, created_by, created_office) VALUES ('WINDOW', '{\"type\":\"COURSE_REGISTRATION\",\"action\":\"OPENED\",\"session\":\"2099/2100\"}'::jsonb, :p, 'ict') RETURNING id")
                .param("p", ictPerson).query(UUID.class).single());
        Map<String, Object> outbox = body(it.get(ict, "/api/v1/platform/notices"));
        assertThat(((List<Map<String, Object>>) outbox.get("jobs")).stream().map(j -> String.valueOf(j.get("id")))).contains(job.toString());
        Map<String, Object> cancelled = body(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/jobs/" + job + "/cancel", Map.of("reason", "IT: the window's messages are not wanted")));
        assertThat(cancelled.get("kind")).isEqualTo("WINDOW");
        assertThat(((List<Map<String, Object>>) cancelled.get("jobs")).stream().map(j -> String.valueOf(j.get("id")))).doesNotContain(job.toString());
        assertThat(it.db(() -> jdbc.sql("SELECT state FROM platform.notice_job WHERE id = :id").param("id", job).query(String.class).single())).isEqualTo("CANCELLED");
        assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/platform/notices/jobs/" + job + "/cancel", Map.of("reason", "again")))).isEqualTo("NOTICE_JOB_FINISHED");
        // the scheduler's next pass leaves it where it is
        it.db(() -> jdbc.sql("SELECT count(*) FROM platform.run_notice_job(NULL)").query(Integer.class).single());
        assertThat(it.db(() -> jdbc.sql("SELECT state FROM platform.notice_job WHERE id = :id").param("id", job).query(String.class).single())).isEqualTo("CANCELLED");
    }
}
