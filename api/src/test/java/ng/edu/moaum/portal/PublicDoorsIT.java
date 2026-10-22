package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.security.SecureRandom;
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
 * Oct 2026: a public door reads no token. The portal's browser side forwards whatever session cookie the browser holds to
 * every call, so a token whose session the server had ended, or one that is not a token at all, closed the application
 * forms and the sign-ins with 401 before the door was reached — the JUPEB application failed on submission. The doors
 * that permit anyone now answer as they answer anyone, from their own rules; a door that needs a session still refuses
 * the ended one. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PublicDoorsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    static int status(ResponseEntity<?> r) { return r.getStatusCode().value(); }

    @Test
    void aPublicDoorAnswersWhateverTokenTheBrowserCarries() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        UUID person = it.person("ZZ-DOOR-REG", "ZZDOOR");
        // the cookie the browser keeps after the server ended the session for idleness
        byte[] id = new byte[32];
        new SecureRandom().nextBytes(id);
        it.db(() -> jdbc.sql("""
                INSERT INTO platform.session (id, person_id, active_office, absolute_end, ended_at, ended_reason)
                VALUES (:id, :p, 'registrar', now() + interval '12 hours', now(), 'expired: idle')
                """).param("id", id).param("p", person).update());
        String ended = TestTokens.token(person, List.of("registrar"), HexFormat.of().formatHex(id));

        // where a session is needed, the ended one is refused as before
        ResponseEntity<Map> refused = it.get(ended, "/api/v1/iam/me");
        assertThat(status(refused)).isEqualTo(401);
        assertThat(refused.getBody().get("code")).isEqualTo("SESSION_ENDED");
        assertThat(status(it.get("not.a.token", "/api/v1/iam/me"))).isEqualTo(401);

        // the public doors answer from their own rules, whatever the request carries
        for (String token : List.of(ended, "not.a.token")) {
            assertThat(status(it.get(token, "/api/v1/jupeb/options"))).as("JUPEB options with " + token).isEqualTo(200);
            assertThat(status(it.get(token, "/api/v1/public/institution"))).as("the institution with " + token).isEqualTo(200);
            assertThat(status(it.getList(token, "/api/v1/pg/programmes"))).as("PG programmes with " + token).isEqualTo(200);
            assertThat(status(it.getList(token, "/api/v1/auth/offices"))).as("the offices with " + token).isEqualTo(200);
            // the application and look-up doors reach their validation (400), not the session's refusal (401)
            assertThat(status(it.call(token, HttpMethod.POST, "/api/v1/jupeb/apply", Map.of()))).as("JUPEB apply with " + token).isEqualTo(400);
            assertThat(status(it.call(token, HttpMethod.POST, "/api/v1/pg/apply", Map.of()))).as("PG apply with " + token).isEqualTo(400);
            assertThat(status(it.call(token, HttpMethod.POST, "/api/v1/applicant/lookup", Map.of()))).as("the JAMB look-up with " + token).isEqualTo(400);
            // and a sign-in judges the credentials it is given, not the token
            ResponseEntity<Map> signIn = it.call(token, HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", "nobody@example.com", "password", "not-the-password"));
            assertThat(status(signIn)).as("JUPEB sign-in with " + token).isEqualTo(422);
            assertThat(signIn.getBody().get("code")).isEqualTo("AUTH_BAD_CREDENTIALS");
        }
    }
}
