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
 * V576 and V577, end to end: the Bursary reads the spillover students with no fee line for the current and next session by each
 * basis; Level corrections reads what a correction would do to a spillover student's fees and leaves the level as it was; the GST
 * office's list reads the kept population (worked out on Refresh, then kept); Candidate data and the migrated students' figures
 * answer. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SpilloverReadinessKeptPopulationIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void readinessFeeEffectAndTheKeptPopulation() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        String bursar = TestTokens.token(it.person("ZZ-SRK-BU-" + n, "ZZSRKBU" + n), List.of("bursar"));
        String registrar = TestTokens.token(it.person("ZZ-SRK-RG-" + n, "ZZSRKRG" + n), List.of("registrar"));
        String gst = TestTokens.token(it.person("ZZ-SRK-GS-" + n, "ZZSRKGS" + n), List.of("gst"));
        String academic = TestTokens.token(it.person("ZZ-SRK-AC-" + n, "ZZSRKAC" + n), List.of("academic"));

        // the spillover students with no line, by each basis
        List<Map<String, Object>> ready = (List<Map<String, Object>>) it.getList(bursar, "/api/v1/finance/spillover-basis/readiness").getBody();
        assertThat(ready).isNotEmpty();
        assertThat(ready.get(0)).containsKeys("session", "lines", "byLevel", "byCohort");

        // a spillover student read at 100 Level: what correcting the level does to the fees, nothing changed
        UUID s = it.student("ZZSRKA" + n, "C00023", "MOAUM/ADM/84/" + (100000 + n), "MOAU/SC/SRK/26/" + n, 100);
        it.db(() -> jdbc.sql("""
                UPDATE people.academic_position SET computed_level = 400, final_level = 400, spillover_years = 1, spillover_state = 'SPILLOVER_YEAR_1'
                 WHERE student_id = :s
                """).param("s", s).update());
        ResponseEntity<Map> effect = it.call(registrar, HttpMethod.POST, "/api/v1/cohorts/levels/fee-effect",
                Map.of("studentIds", List.of(s.toString()), "bases", List.of("SPILLOVER"), "limit", 10));
        assertThat(effect.getStatusCode().value()).as(String.valueOf(effect.getBody())).isEqualTo(200);
        assertThat(effect.getBody()).containsEntry("students", 1).containsKeys("session", "basis", "chargedNow", "chargedAfter", "more", "less", "same", "noneAfter");
        assertThat(jdbc.sql("SELECT current_level FROM people.student WHERE id = :s").param("s", s).query(Integer.class).single()).isEqualTo(100);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/cohorts/levels/fee-effect", Map.of("studentIds", List.of(s.toString()))).getStatusCode().value())
                .isEqualTo(403);

        // the GST office's list reads the kept population: worked out on Refresh, then kept
        Map<String, Object> first = it.get(gst, "/api/v1/gst/GST/students?refresh=true&page=0&size=5").getBody();
        assertThat(first.get("keptAt")).isNotNull();
        String session = String.valueOf(first.get("session"));
        assertThat(jdbc.sql("SELECT count(*) FROM finance.gst_population_state WHERE session = :s AND semester = 0 AND NOT invalid").param("s", session)
                .query(Long.class).single()).isEqualTo(1);
        Map<String, Object> again = it.get(gst, "/api/v1/gst/GST/students?page=0&size=5").getBody();
        assertThat(again.get("keptAt")).isEqualTo(first.get("keptAt"));
        assertThat(again.get("total")).isEqualTo(first.get("total"));

        // Candidate data and the migrated students' figures answer
        ResponseEntity<Map> cd = it.get(academic, "/api/v1/admissions/sessions/" + session + "/candidate-data");
        assertThat(cd.getStatusCode().value()).isEqualTo(200);
        assertThat(cd.getBody()).containsKeys("findings", "candidates");
        Map<String, Object> migrated = it.get(registrar, "/api/v1/student/students/migrated?refresh=true").getBody();
        assertThat(migrated).containsKeys("migrated", "cleared", "uncleared");
    }
}
