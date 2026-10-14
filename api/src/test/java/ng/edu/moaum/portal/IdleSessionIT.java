package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;

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
 * The idle session timeout (V437), end to end through the API: a session left alone past the timeout is refused on its
 * next request with SESSION_EXPIRED_IDLE, ended on the server with the reason and written to the sign-in record; a
 * request the browser sends on its own (X-Background) is never activity, the person's own request is; the policy is set
 * only by the Directorate of ICT or an administrator, refuses a warning no shorter than the timeout and a timeout under
 * thirty seconds, is applied to the next request without a restart, and turned off lets an old session stand; the monitor
 * counts the open sessions. The policy is put back whatever happens. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class IdleSessionIT {

    static final String P = "/api/v1/auth/session-policy";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    static int status(ResponseEntity<?> r) { return r.getStatusCode().value(); }

    /** a server-side session for the person, last seen some seconds ago */
    private String session(ItSupport it, UUID person, int lastSeenSecondsAgo) {
        byte[] id = new byte[32];
        new SecureRandom().nextBytes(id);
        it.db(() -> jdbc.sql("""
                INSERT INTO platform.session (id, person_id, active_office, absolute_end, last_seen_at)
                VALUES (:id, :p, 'registrar', now() + interval '12 hours', now() - make_interval(secs => :ago))
                """).param("id", id).param("p", person).param("ago", lastSeenSecondsAgo).update());
        return HexFormat.of().formatHex(id);
    }

    private OffsetDateTime lastSeen(String sid) {
        return jdbc.sql("SELECT last_seen_at FROM platform.session WHERE id = decode(:h, 'hex')").param("h", sid).query(OffsetDateTime.class).single();
    }

    private Map<String, Object> policy(ItSupport it, String ict, boolean enabled, int idle, int warning) {
        ResponseEntity<Map> r = it.call(ict, HttpMethod.PUT, P, Map.of("enabled", enabled, "idleSeconds", idle, "warningSeconds", warning, "allowContinue", true, "reason", "integration test"));
        assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @Test
    void anIdleSessionIsEndedByTheServerAndTheSettingIsTheIctDirectors() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        UUID person = it.person("ZZ-IDLE-REG", "ZZIDLE");
        String ict = ItSupport.token("ict");
        String bursar = ItSupport.token("bursar");
        Map<String, Object> before = it.get(ict, P).getBody();
        try {
            policy(it, ict, true, 120, 30);
            // left alone past the timeout: refused with the code, ended with the reason, on the sign-in record
            String old = session(it, person, 600);
            String stale = TestTokens.token(person, List.of("registrar"), old);
            ResponseEntity<Map> refused = it.get(stale, "/api/v1/iam/me");
            assertThat(status(refused)).isEqualTo(401);
            assertThat(refused.getBody().get("code")).isEqualTo("SESSION_EXPIRED_IDLE");
            assertThat(jdbc.sql("SELECT ended_reason FROM platform.session WHERE id = decode(:h, 'hex')").param("h", old).query(String.class).single()).isEqualTo("expired: idle");
            assertThat(jdbc.sql("SELECT count(*) FROM iam.sign_in_event WHERE session_id = decode(:h, 'hex') AND outcome = 'EXPIRED_IDLE'").param("h", old).query(Long.class).single()).isEqualTo(1L);
            // ended, it stays ended: the next request is refused as ended, not revived
            assertThat(it.get(stale, "/api/v1/iam/me").getBody().get("code")).isEqualTo("SESSION_ENDED");

            // the browser's own request is not activity; the person's is
            String live = session(it, person, 60);
            String token = TestTokens.token(person, List.of("registrar"), live);
            OffsetDateTime seen = lastSeen(live);
            assertThat(status(it.callWith(token, HttpMethod.GET, "/api/v1/iam/me", null, Map.of("X-Background", "1")))).isEqualTo(200);
            assertThat(lastSeen(live)).isEqualTo(seen);
            assertThat(status(it.get(token, "/api/v1/iam/me"))).isEqualTo(200);
            assertThat(lastSeen(live)).isAfter(seen);

            // the setting: the ICT Director's, validated by the database, applied to the next request
            assertThat(status(it.call(bursar, HttpMethod.PUT, P, Map.of("enabled", true, "idleSeconds", 300, "warningSeconds", 30)))).isEqualTo(403);
            ResponseEntity<Map> same = it.call(ict, HttpMethod.PUT, P, Map.of("enabled", true, "idleSeconds", 120, "warningSeconds", 120));
            assertThat(status(same)).isEqualTo(422);
            assertThat(same.getBody().get("code")).isEqualTo("SESSION_POLICY_WARNING");
            assertThat(it.call(ict, HttpMethod.PUT, P, Map.of("enabled", true, "idleSeconds", 10, "warningSeconds", 5)).getBody().get("code")).isEqualTo("SESSION_POLICY_IDLE_MIN");
            Map<String, Object> set = policy(it, ict, true, 300, 60);
            assertThat(set.get("idleSeconds")).isEqualTo(300);
            assertThat(set.get("warningSeconds")).isEqualTo(60);
            String fourMinutes = session(it, person, 240);
            assertThat(status(it.get(TestTokens.token(person, List.of("registrar"), fourMinutes), "/api/v1/iam/me"))).as("four minutes idle under a five-minute timeout").isEqualTo(200);
            // off: an old session stands
            policy(it, ict, false, 120, 30);
            String veryOld = session(it, person, 3600);
            assertThat(status(it.get(TestTokens.token(person, List.of("registrar"), veryOld), "/api/v1/iam/me"))).isEqualTo(200);
            // anyone signed in reads the policy; the monitor is the security screen's
            Map<String, Object> read = it.get(bursar, P).getBody();
            assertThat(read.get("enabled")).isEqualTo(false);
            Map<String, Object> monitor = it.get(ict, P + "/monitor").getBody();
            assertThat(((Number) ((Map<String, Object>) monitor.get("counts")).get("open_sessions")).intValue()).isGreaterThanOrEqualTo(3);
            assertThat(((List<Map<String, Object>>) monitor.get("sessions")).stream().anyMatch(x -> "ZZIDLE".equals(String.valueOf(x.get("name")).split(",")[0]))).isTrue();
            assertThat(it.getList(ict, P + "/history").getBody().size()).isGreaterThanOrEqualTo(3);
            assertThat(status(it.get(bursar, P + "/monitor"))).isEqualTo(403);
        } finally {
            policy(it, ict, Boolean.TRUE.equals(before.get("enabled")), ((Number) before.get("idleSeconds")).intValue(), ((Number) before.get("warningSeconds")).intValue());
        }
    }

    /** Oct 2026: a release no longer signs everyone out — a session issued before this instance started still stands */
    @Test
    void aSessionIssuedBeforeThisInstanceStartedStands() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        UUID person = it.person("ZZ-IDLE-DEPLOY", "ZZDEPLOY");
        byte[] id = new byte[32];
        new SecureRandom().nextBytes(id);
        it.db(() -> jdbc.sql("""
                INSERT INTO platform.session (id, person_id, active_office, issued_at, absolute_end, last_seen_at)
                VALUES (:id, :p, 'registrar', now() - interval '1 day', now() + interval '12 hours', now())
                """).param("id", id).param("p", person).update());
        String token = TestTokens.token(person, List.of("registrar"), HexFormat.of().formatHex(id));
        ResponseEntity<Map> me = it.get(token, "/api/v1/iam/me");
        assertThat(status(me)).as(String.valueOf(me.getBody())).isEqualTo(200);
        assertThat(status(it.get(token, "/api/v1/iam/session"))).isEqualTo(204);
    }
}
