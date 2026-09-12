package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The Reconsiderations "suggest" endpoint (per-candidate programme choice) guards
 * what it is asked to do: it refuses a suggestion against an application that does
 * not exist, an id that is not an application at all, and a programme the candidate
 * does not qualify for — each a clean 4xx, never a 500. The qualified happy path
 * rests on admissions.programme_suggestions, which check.sql already exercises.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class ReconsiderationsIT {

    static final String SESSION = "2094/2095";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic = ItSupport.token("academic");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2094);
    }

    private static String path(String tail) {
        return "/api/v1/admissions/sessions/2094/2095" + tail;
    }

    @Test
    void theSuggestEndpointGuardsTheApplicationAndTheProgramme() {
        int n = new Random().nextInt(90_000_000) + 10_000_000;
        String jamb = "2094" + n + "CA";

        // a candidate with an application, but nothing set up that they would qualify for
        UUID app = it.db(() -> {
            UUID cand = UUID.randomUUID();
            UUID acct = UUID.randomUUID();
            UUID appId = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state) "
                    + "VALUES (:id, :s, :j, 'RECON', 'Test', 'B.Sc. Invented', 'UTME', 100, 'PROPOSED')")
                    .param("id", cand).param("s", SESSION).param("j", jamb).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) "
                    + "VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", SESSION).param("c", cand).param("k", jamb.toUpperCase())
                    .param("e", jamb.toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, submitted_at, score_released_at) "
                    + "VALUES (:id, :a, :c, :s, :no, now(), now())")
                    .param("id", appId).param("a", acct).param("c", cand).param("s", SESSION).param("no", "APP-" + n).update();
            return appId;
        });

        // an application that does not exist → 404
        assertThat(it.call(academic, HttpMethod.POST, path("/reconsiderations/suggest"),
                Map.of("applicationId", UUID.randomUUID().toString(), "programme", "C00061")).getStatusCode().value()).isEqualTo(404);

        // an id that is not an application at all → a clean 422, not a 500
        assertThat(it.call(academic, HttpMethod.POST, path("/reconsiderations/suggest"),
                Map.of("applicationId", "not-an-application", "programme", "C00061")).getStatusCode().value()).isEqualTo(422);

        // a real application, but a programme the candidate does not qualify for → 422
        assertThat(it.call(academic, HttpMethod.POST, path("/reconsiderations/suggest"),
                Map.of("applicationId", app.toString(), "programme", "C00061")).getStatusCode().value()).isEqualTo(422);
    }
}
