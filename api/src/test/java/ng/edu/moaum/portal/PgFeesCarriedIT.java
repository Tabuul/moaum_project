package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The postgraduate application fees of a session with no earlier session's fees stated read as the default amounts, carried
 * from none — the Fee Schedule's postgraduate panel answered such a session with a server error (an empty "carried from").
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class PgFeesCarriedIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @SuppressWarnings("unchecked")
    @Test
    void aSessionWithNoEarlierFeesStatedReadsTheDefaultCarriedFromNone() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String tag = Integer.toString(new Random().nextInt(9_000) + 1_000);
        String bursar = TestTokens.token(it.person("ZZPGFC-BUR-" + tag, "ZZPGFCBUR"), List.of("bursar"));
        // a session earlier than any with postgraduate fees stated
        String earliest = it.db(() -> jdbc.sql("SELECT coalesce(min(session), '2000/2001') FROM admissions.pg_fee").query(String.class).single());
        int year = Integer.parseInt(earliest.substring(0, 4)) - 10;
        ResponseEntity<Map> r = it.get(bursar, "/api/v1/pg/sessions/" + year + "/" + (year + 1) + "/fees");
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        Map<String, Object> fees = r.getBody();
        assertThat(fees.get("stated")).isEqualTo(false);
        assertThat(fees.get("carriedFrom")).isNull();   // carried from none (the API leaves a null field out)
        assertThat(fees.get("application_fee")).isNotNull();
    }
}
