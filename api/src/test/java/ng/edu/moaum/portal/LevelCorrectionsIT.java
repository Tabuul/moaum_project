package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Spillover students brought to their level (V475): a spillover student at 100 Level on the record is listed for correction
 * with the cohort engine's level and the record reads the spillover; only the Academic Office or the Registry corrects it, on a
 * reason; a dry run counts; the correction raises the record and goes on the cohort decision history. The engine's position is
 * set for the test student directly — this database keeps no current session for the engine to count from. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class LevelCorrectionsIT {

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
    void aSpilloverStudentIsBroughtToTheirLevelOnAReason() {
        int n = new Random().nextInt(8000) + 1000;
        String tag = "ZZLV" + n;
        UUID student = it.student(tag, "C00023", "MOAUM/ADM/96/" + (400000 + n), "MOAUM/MTC/96/" + (40000 + n), 100);
        // the engine's position for a student two sessions past a four-year programme (SP2), as it reads with a current session
        jdbc.sql("""
                UPDATE people.academic_position SET computed_level = 400, final_level = 400, spillover_years = 2, spillover_state = 'SPILLOVER_YEAR_2',
                       classification = 'SPILLOVER', issues = ARRAY['LEVEL_CONFLICT', 'BEYOND_PROGRAMME_LENGTH']
                 WHERE student_id = :s
                """).param("s", student).update();

        // the list: the record below the engine's level, its basis, and the record reads the spillover
        ResponseEntity<Map> list = it.get(academic, "/api/v1/cohorts/levels?q=" + tag);
        assertThat(list.getStatusCode().value()).as(String.valueOf(list.getBody())).isEqualTo(200);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) list.getBody().get("rows");
        assertThat(rows).hasSize(1);
        assertThat(rows.get(0).get("basis")).isEqualTo("SPILLOVER");
        assertThat(rows.get(0).get("current_level")).isEqualTo(100);
        assertThat(rows.get(0).get("proposed_level")).isEqualTo(400);
        Map<String, Object> record = (Map<String, Object>) it.get(academic, "/api/v1/student/students/" + student).getBody().get("student");
        assertThat(record.get("spilloverState")).isEqualTo("SPILLOVER_YEAR_2");

        // only the Academic Office or the Registry corrects levels, and never without a reason
        Map<String, Object> body = Map.of("studentIds", List.of(student.toString()), "dryRun", false, "reason", "Migrated at 100 Level; a spillover student is at the final level");
        assertThat(it.call(it.officer("hod", "department", "MTC"), HttpMethod.POST, "/api/v1/cohorts/levels/apply", body).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("records"), HttpMethod.POST, "/api/v1/cohorts/levels/apply", body).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/cohorts/levels/apply", Map.of("studentIds", List.of(student.toString()), "dryRun", false))
                .getStatusCode().is4xxClientError()).isTrue();

        // a dry run counts; the correction raises the record and goes on the cohort history
        Map<String, Object> dry = it.call(academic, HttpMethod.POST, "/api/v1/cohorts/levels/apply", Map.of("studentIds", List.of(student.toString()))).getBody();
        assertThat(((Number) dry.get("selected")).intValue()).isEqualTo(1);
        assertThat(((Number) dry.get("corrected")).intValue()).isZero();
        ResponseEntity<Map> done = it.call(academic, HttpMethod.POST, "/api/v1/cohorts/levels/apply", body);
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(((Number) done.getBody().get("corrected")).intValue()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT current_level FROM people.student WHERE id = :s").param("s", student).query(Integer.class).single()).isEqualTo(400);
        Map<String, Object> decision = jdbc.sql("SELECT rule, previous_level, new_level, reason FROM people.cohort_decision WHERE student_id = :s ORDER BY decided_at DESC LIMIT 1")
                .param("s", student).query().singleRow();
        assertThat(decision.get("rule")).isEqualTo("LEVEL_SPILLOVER");
        assertThat(decision.get("previous_level")).isEqualTo(100);
        assertThat(decision.get("new_level")).isEqualTo(400);
    }
}
