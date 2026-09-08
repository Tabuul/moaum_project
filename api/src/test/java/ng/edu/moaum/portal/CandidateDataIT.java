package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;

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

/** A download recorded for nobody on any list is held, not discarded, and counted. Needs DATABASE_URL. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class CandidateDataIT {

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
    }

    @Test
    @SuppressWarnings("unchecked")
    void aDateOfBirthForNobodyIsHeld() {
        ResponseEntity<Map> recorded = it.call(academic, HttpMethod.POST, "/api/v1/admissions/sessions/2091/2092/candidate-data",
                Map.of("kind", "DATE_OF_BIRTH", "items", List.of(Map.of("sourceName", "209999999999ZZ ", "jambKey", "209999999999ZZ",
                        "readAs", "COLUMN", "payload", Map.of("dob", "05-07-2002", "ambiguous", true)))));
        assertThat(recorded.getStatusCode().value()).as(String.valueOf(recorded.getBody())).isEqualTo(200);

        ResponseEntity<Map> state = it.get(academic, "/api/v1/admissions/sessions/2091/2092/candidate-data");
        assertThat(state.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> attachments = (List<Map<String, Object>>) state.getBody().get("attachments");
        assertThat(attachments).anySatisfy(a -> {
            assertThat(a.get("jambKey")).isEqualTo("209999999999ZZ");
            assertThat(a.get("matched")).isEqualTo(false);
        });
        List<Map<String, Object>> findings = (List<Map<String, Object>>) state.getBody().get("findings");
        assertThat(findings.stream().filter(f -> "Arrived for nobody on any list".equals(f.get("finding")))
                .mapToLong(f -> ((Number) f.get("n")).longValue()).sum()).isGreaterThanOrEqualTo(1);

        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/admissions/sessions/2091/2092/candidate-data",
                Map.of("kind", "PHOTO", "items", List.of())).getStatusCode().value()).isEqualTo(422);
    }
}
