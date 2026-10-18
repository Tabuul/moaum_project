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

/**
 * V546 through the API: ICT reads the database's slowest statements — or why they are not available here — with the screens of
 * the heavier functions; ICT names the screens of a function written as schema.name; the Bursar may not read them and the
 * administrator may not name screens.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class SlowStatementsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String tag;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("ZZSS-ICT-" + k, "ZZSS-ADM-" + k, "ZZSS-BUR-" + k)));
    }

    @SuppressWarnings("unchecked")
    @Test
    void ictReadsTheSlowestStatementsAndNamesTheScreensOfAFunction() {
        String ict = TestTokens.token(it.person("ZZSS-ICT-" + tag, "ZZSSICT"), List.of("ict"));
        String admin = TestTokens.token(it.person("ZZSS-ADM-" + tag, "ZZSSADM"), List.of("admin"));
        String bursar = TestTokens.token(it.person("ZZSS-BUR-" + tag, "ZZSSBUR"), List.of("bursar"));
        String fn = "zzss.slow_" + tag;
        try {
            assertThat(it.get(bursar, "/api/v1/platform/slow-statements").getStatusCode().value()).isEqualTo(403);

            ResponseEntity<Map> read = it.get(admin, "/api/v1/platform/slow-statements?order=TOTAL&minCalls=1&limit=10");
            assertThat(read.getStatusCode().value()).isEqualTo(200);
            Map<String, Object> body = read.getBody();
            assertThat(body.get("available")).isInstanceOf(Boolean.class);
            if ((Boolean) body.get("available")) {
                assertThat(body.get("order")).isEqualTo("TOTAL");
                assertThat((List<Object>) body.get("rows")).hasSizeLessThanOrEqualTo(10);
            } else {
                assertThat((String) body.get("reason")).isNotBlank();
                assertThat((List<Object>) body.get("rows")).isEmpty();
            }
            assertThat((List<Map<String, Object>>) body.get("screens"))
                    .anySatisfy(s -> assertThat(s.get("function_name")).isEqualTo("finance.session_positions"));

            // ICT names a function's screens; the administrator reads but does not name; a name not written as schema.name is refused
            assertThat(it.call(admin, HttpMethod.PUT, "/api/v1/platform/slow-statements/screens/" + fn, Map.of("screens", "Somewhere")).getStatusCode().value())
                    .isEqualTo(403);
            assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/platform/slow-statements/screens/not a function", Map.of("screens", "Somewhere")).getStatusCode().is4xxClientError())
                    .isTrue();
            ResponseEntity<Map> named = it.call(ict, HttpMethod.PUT, "/api/v1/platform/slow-statements/screens/" + fn, Map.of("screens", "  Student Statistics  "));
            assertThat(named.getStatusCode().value()).isEqualTo(200);
            assertThat(named.getBody().get("screens")).isEqualTo("Student Statistics");
            it.call(ict, HttpMethod.PUT, "/api/v1/platform/slow-statements/screens/" + fn.toUpperCase(), Map.of("screens", "Student Statistics · Student Query", "note", "both"));
            assertThat(it.db(() -> jdbc.sql("SELECT screens || '|' || note FROM platform.statement_screen WHERE function_name = :f").param("f", fn).query(String.class).single()))
                    .isEqualTo("Student Statistics · Student Query|both");
        } finally {
            it.db(() -> jdbc.sql("DELETE FROM platform.statement_screen WHERE function_name = :f").param("f", fn).update());
        }
    }
}
