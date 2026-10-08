package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
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
 * The limits on the public doors (V359), through the API, from addresses of the documentation ranges (RFC 5737) that no
 * other suite uses — a request from the machine itself is not counted, so the rest of the suite never meets them. The
 * address counted is the one the edge wrote: off Railway, the last X-Forwarded-For entry, whatever the client put before
 * it. A sign-in door counts wrong passwords on accounts that exist, not unknown names; a verification counts the checks
 * that do not match; a JAMB look-up counts every look-up. Past the number: 429 with Retry-After. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings("rawtypes")
class ThrottleIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient plain;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        plain = RestClient.builder().baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { }).build();
    }

    private ResponseEntity<Map> from(String forwarded, HttpMethod method, String path, Object body) {
        RestClient.RequestBodySpec spec = plain.method(method).uri(path).contentType(MediaType.APPLICATION_JSON);
        if (forwarded != null) spec = spec.header("X-Forwarded-For", forwarded);
        return (body == null ? spec : spec.body(body)).retrieve().toEntity(Map.class);
    }

    /** a fresh documentation address for each run, so a rerun on the same API instance starts its own count */
    private static String address(int net) {
        int r = new java.util.Random().nextInt(250) + 1;
        return switch (net) {
            case 1 -> "192.0.2." + r;
            case 2 -> "198.51.100." + r;
            default -> "203.0.113." + r;
        };
    }

    @Test
    void verificationsThatDoNotMatchAreCountedByTheAddressTheEdgeWrote() {
        String me = address(3);
        // forty checks that do not match, each with a different forged first entry: the edge's last entry is what counts
        for (int i = 0; i < 40; i++) {
            ResponseEntity<Map> r = from("10.9.8." + i + ", " + me, HttpMethod.GET, "/api/v1/verify/putme/00000000000000" + String.format("%02d", i), null);
            assertThat(r.getStatusCode().value()).as("check " + i).isEqualTo(200);
            assertThat(r.getBody().get("genuine")).isEqualTo(false);
        }
        ResponseEntity<Map> refused = from("10.9.8.99, " + me, HttpMethod.GET, "/api/v1/verify/putme/0000000000000099", null);
        assertThat(refused.getStatusCode().value()).isEqualTo(429);
        assertThat(refused.getBody().get("code")).isEqualTo("VERIFY_THROTTLED");
        assertThat(refused.getHeaders().getFirst("Retry-After")).matches("[0-9]+");
        // the hostel page too, the same connection; another connection, and the machine itself, are not refused
        assertThat(from(me, HttpMethod.GET, "/api/v1/verify/hostel/ALC-0000-00000?c=000000000000000000", null).getStatusCode().value()).isEqualTo(429);
        assertThat(from(address(1), HttpMethod.GET, "/api/v1/verify/putme/0000000000000099", null).getStatusCode().value()).isEqualTo(200);
        assertThat(from(null, HttpMethod.GET, "/api/v1/verify/putme/0000000000000099", null).getStatusCode().value()).isEqualTo(200);
    }

    @Test
    void aSignInDoorCountsWrongPasswordsOnAccountsThatExistNotUnknownNames() {
        String me = address(2);
        // unknown names — the portal's own page tries the staff door for every email — are not counted
        for (int i = 0; i < 35; i++) {
            ResponseEntity<Map> r = from(me, HttpMethod.POST, "/api/v1/auth/sign-in", Map.of("username", "nobody-" + UUID.randomUUID(), "password", "x"));
            assertThat(r.getStatusCode().value()).as("unknown " + i).isEqualTo(422);
        }
        // a real account: five wrong passwords lock it, and each attempt on it counts, locked or not; the thirty-first is refused
        UUID person = it.person("ZZT-" + UUID.randomUUID().toString().substring(0, 6), "ZZTHROTTLE");
        String username = "zzt-" + UUID.randomUUID().toString().substring(0, 8);
        ResponseEntity<Map> set = it.call(ItSupport.token("registrar"), HttpMethod.PUT, "/api/v1/iam/persons/" + person + "/credential",
                Map.of("username", username, "password", "a first password 2026"));
        assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
        for (int i = 0; i < 30; i++) {
            ResponseEntity<Map> r = from(me, HttpMethod.POST, "/api/v1/auth/sign-in", Map.of("username", username, "password", "wrong password " + i));
            assertThat(r.getStatusCode().value()).as("wrong " + i).isEqualTo(422);
            assertThat(r.getBody().get("code")).isIn("AUTH_BAD_CREDENTIALS", "AUTH_LOCKED");
        }
        ResponseEntity<Map> refused = from(me, HttpMethod.POST, "/api/v1/auth/sign-in", Map.of("username", "nobody-at-all", "password", "x"));
        assertThat(refused.getStatusCode().value()).isEqualTo(429);
        assertThat(refused.getBody().get("code")).isEqualTo("AUTH_THROTTLED");
        // the sign-in records the person's address, not the portal's
        assertThat(jdbc.sql("SELECT count(*) FROM iam.sign_in_event WHERE username = :u AND host(source_ip) = :a").param("u", username).param("a", me)
                .query(Long.class).single()).isEqualTo(30L);
    }

    @Test
    void everyJambLookUpIsCounted() {
        String me = address(1);
        for (int i = 0; i < 60; i++) {
            ResponseEntity<Map> r = from(me, HttpMethod.POST, "/api/v1/applicant/lookup", Map.of("session", "2077/2078", "jambKey", "20779" + String.format("%07d", i) + "ZZ"));
            assertThat(r.getStatusCode().value()).as("look-up " + i).isEqualTo(200);
        }
        ResponseEntity<Map> refused = from(me, HttpMethod.POST, "/api/v1/applicant/lookup", Map.of("session", "2077/2078", "jambKey", "207790000099ZZ"));
        assertThat(refused.getStatusCode().value()).isEqualTo(429);
        assertThat(refused.getBody().get("code")).isEqualTo("APP_THROTTLED");
    }
}
