package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * V571, end to end: the Bursary reads who is charged the spillover fee lines (by the level, the default), previews the change —
 * an invented student at the final level whom the cohort engine reads in a spillover year moves onto the lines, with the session's
 * charges under each basis — and changes it with a reason; the Bursar alone changes it, and a short reason is refused. The basis is
 * put back to LEVEL however the test ends. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SpilloverFeeBasisIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static final String BASIS = "/api/v1/finance/spillover-basis";

    @Test
    void theBursaryPreviewsAndChangesWhoIsChargedTheSpilloverLines() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        UUID a = it.student("ZZSPB" + n, "C00023", "MOAUM/ADM/87/" + (100000 + n), "MOAU/SC/SPB/26/" + n, 400);
        it.db(() -> jdbc.sql("UPDATE people.academic_position SET spillover_state = 'SPILLOVER_YEAR_1' WHERE student_id = :s").param("s", a).update());
        String bursar = TestTokens.token(it.person("ZZ-SPB-BU-" + n, "ZZSPBBU" + n), List.of("bursar"));
        String audit = TestTokens.token(it.person("ZZ-SPB-AU-" + n, "ZZSPBAU" + n), List.of("audit"));
        try {
            Map<String, Object> now = it.get(bursar, BASIS).getBody();
            assertThat(now).containsEntry("basis", "LEVEL").containsKeys("into_spill", "out_of_spill", "spillLines");
            assertThat(((Number) now.get("into_spill")).longValue()).isGreaterThanOrEqualTo(1);

            // the preview: the student moves onto the lines by the cohort; nothing changed
            Map<String, Object> preview = it.get(audit, BASIS + "/preview?all=true").getBody();
            assertThat(((Number) preview.get("intoSpill")).longValue()).isGreaterThanOrEqualTo(1);
            assertThat((List<Map<String, Object>>) preview.get("rows")).anySatisfy(r -> {
                assertThat(r.get("student_id")).isEqualTo(a.toString());
                assertThat(r).containsEntry("by_level", false).containsEntry("by_cohort", true).containsEntry("spillover_state", "SPILLOVER_YEAR_1");
                assertThat(r).containsKeys("by_level_due", "by_cohort_due");
            });
            assertThat(jdbc.sql("SELECT finance.is_spillover(:s)").param("s", a).query(Boolean.class).single()).isFalse();
            assertThat(it.get(bursar, BASIS).getBody()).containsEntry("basis", "LEVEL");

            // the Bursar alone changes it, with a reason of ten characters
            assertThat(it.call(audit, HttpMethod.PUT, BASIS, Map.of("basis", "COHORT", "reason", "Bursary decision on spillover fees")).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(bursar, HttpMethod.PUT, BASIS, Map.of("basis", "COHORT", "reason", "short")).getStatusCode().value()).isEqualTo(400);
            assertThat(it.call(bursar, HttpMethod.PUT, BASIS, Map.of("basis", "AGE", "reason", "Bursary decision on spillover fees")).getStatusCode().value()).isEqualTo(400);
            ResponseEntity<Map> set = it.call(bursar, HttpMethod.PUT, BASIS, Map.of("basis", "COHORT", "reason", "Bursary decision on spillover fees"));
            assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
            assertThat(set.getBody()).containsEntry("basis", "COHORT").containsEntry("reason", "Bursary decision on spillover fees");
            assertThat(set.getBody().get("set_by")).isNotNull();
            assertThat(jdbc.sql("SELECT finance.is_spillover(:s)").param("s", a).query(Boolean.class).single()).isTrue();
        } finally {
            it.db(() -> jdbc.sql("""
                    UPDATE finance.fee_setting SET spillover_basis = 'LEVEL', spillover_basis_set_at = now(), spillover_basis_set_by = NULL,
                           spillover_basis_reason = 'integration test: put back' WHERE id = 1
                    """).update());
        }
    }
}
