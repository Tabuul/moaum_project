package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * Signing in: the Registry sets a credential, the person signs in and gets a
 * token carrying the offices they hold today, a wrong password is refused
 * the same way as an unknown name, five wrong ones lock the account, a signed-
 * out token is refused, and the password changes. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class AuthIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient plain;
    String registrar = ItSupport.token("registrar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        plain = RestClient.builder().baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { }).build();
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> post(String path, Object body, String token) {
        RestClient.RequestBodySpec spec = plain.post().uri(path).contentType(MediaType.APPLICATION_JSON);
        if (token != null) {
            spec = spec.header(HttpHeaders.AUTHORIZATION, "Bearer " + token);
        }
        return spec.body(body == null ? Map.of() : body).retrieve().toEntity(Map.class);
    }

    @Test
    @SuppressWarnings("unchecked")
    void theRegistrySetsACredentialAndThePersonSignsIn() {
        UUID person = it.person("ZZA-0001", "ZZAUTHONE");
        String username = "zza-0001-" + UUID.randomUUID().toString().substring(0, 6);
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from)
                    VALUES (gen_random_uuid(), :p, 'dean', 'faculty', 'AuthIT: test grant', :by, current_date)
                    ON CONFLICT DO NOTHING
                    """).param("p", person).param("by", UUID.randomUUID()).update();
            return null;
        });

        // too short a password is refused; then it is set
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/iam/persons/" + person + "/credential",
                Map.of("username", username, "password", "short")).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> set = it.call(registrar, HttpMethod.PUT, "/api/v1/iam/persons/" + person + "/credential",
                Map.of("username", username, "password", "a first password 2026"));
        assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);

        // an unknown name and a wrong password are refused the same way
        assertThat(post("/api/v1/auth/sign-in", Map.of("username", "nobody-" + username, "password", "x"), null).getStatusCode().value()).isEqualTo(422);
        assertThat(post("/api/v1/auth/sign-in", Map.of("username", username, "password", "wrong password"), null).getBody().get("code")).isEqualTo("AUTH_BAD_CREDENTIALS");

        ResponseEntity<Map> signed = post("/api/v1/auth/sign-in", Map.of("username", username.toUpperCase(), "password", "a first password 2026"), null);
        assertThat(signed.getStatusCode().value()).as(String.valueOf(signed.getBody())).isEqualTo(200);
        String token = String.valueOf(signed.getBody().get("token"));
        assertThat(signed.getBody().get("mustChange")).isEqualTo(true);
        List<Map<String, Object>> offices = (List<Map<String, Object>>) signed.getBody().get("offices");
        assertThat(offices).extracting(o -> o.get("code")).contains("dean");

        // the token works, names the person, and lists the offices
        ResponseEntity<Map> me = it.get(token, "/api/v1/iam/me");
        assertThat(me.getStatusCode().value()).isEqualTo(200);
        assertThat(((List<?>) me.getBody().get("offices")).stream().map(String::valueOf)).contains("dean");
        assertThat(me.getBody().get("name")).isEqualTo("ZZAUTHONE, Invented");
        assertThat(me.getBody().get("sessionId")).isNotNull();

        // the person changes the password
        assertThat(post("/api/v1/auth/change-password", Map.of("current", "wrong", "next", "another password 2026"), token).getStatusCode().value()).isEqualTo(422);
        assertThat(post("/api/v1/auth/change-password", Map.of("current", "a first password 2026", "next", "another password 2026"), token).getStatusCode().value()).isEqualTo(200);

        // sessions are listed; signing out ends this one and the token dies with it
        assertThat(it.getList(token, "/api/v1/auth/sessions").getBody()).isNotEmpty();
        assertThat(post("/api/v1/auth/sign-out", null, token).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(token, "/api/v1/iam/me").getStatusCode().value()).isEqualTo(401);

        // five wrong passwords lock the account
        for (int i = 0; i < 5; i++) {
            post("/api/v1/auth/sign-in", Map.of("username", username, "password", "wrong again"), null);
        }
        ResponseEntity<Map> locked = post("/api/v1/auth/sign-in", Map.of("username", username, "password", "another password 2026"), null);
        assertThat(locked.getBody().get("code")).isEqualTo("AUTH_LOCKED");
    }

    @Test
    void theFirstAccountIsMadeOnceWithTheSecret() {
        ResponseEntity<Map> wrong = plain.post().uri("/api/v1/auth/bootstrap").contentType(MediaType.APPLICATION_JSON)
                .header("X-Bootstrap-Secret", "not it")
                .body(Map.of("surname", "ZZBOOT", "givenNames", "Invented", "username", "zzboot", "password", "a bootstrap password"))
                .retrieve().toEntity(Map.class);
        assertThat(wrong.getStatusCode().value()).isEqualTo(422);
        assertThat(wrong.getBody().get("code")).isEqualTo("AUTH_BOOTSTRAP_SECRET");

        long credentials = jdbc.sql("SELECT count(*) FROM iam.credential").query(Long.class).single();
        ResponseEntity<Map> right = plain.post().uri("/api/v1/auth/bootstrap").contentType(MediaType.APPLICATION_JSON)
                .header("X-Bootstrap-Secret", TestTokens.SECRET)
                .body(Map.of("surname", "ZZBOOT", "givenNames", "Invented", "username", "zzboot-" + UUID.randomUUID().toString().substring(0, 6),
                        "password", "a bootstrap password"))
                .retrieve().toEntity(Map.class);
        if (credentials == 0) {
            assertThat(right.getStatusCode().value()).as(String.valueOf(right.getBody())).isEqualTo(200);
            assertThat(right.getBody().get("token")).isNotNull();
        } else {
            assertThat(right.getBody().get("code")).isEqualTo("AUTH_BOOTSTRAPPED");
        }
    }
}
