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

    private void position(UUID student, int computed, String state, int years) {
        jdbc.sql("""
                UPDATE people.academic_position SET computed_level = :c, final_level = 400, spillover_years = :y, spillover_state = :st,
                       classification = CASE WHEN :y > 0 THEN 'SPILLOVER' ELSE 'ACTIVE' END, issues = ARRAY['LEVEL_CONFLICT']
                 WHERE student_id = :s
                """).param("c", computed).param("y", years).param("st", state).param("s", student).update();
    }

    private static List<String> names(ResponseEntity<Map> r) {
        return ((List<Map<String, Object>>) r.getBody().get("rows")).stream().map(x -> String.valueOf(x.get("other_names"))).sorted().toList();
    }

    /** V593: found by the level they should be at and by spillover position, every one found corrected after a count, the rest
     *  left; Student Query finds them by the engine's level and whether the record is below it; the statistics take a position */
    @Test
    void everyOneFoundByTheLevelTheyShouldBeAtIsCorrectedAfterACount() {
        String tag = it.freeSurname("ZZLW");
        UUID sp1 = it.student(tag, "C00023", it.freeNumber("MOAUM/ADM/95/", 6), it.freeNumber("MOAUM/MTC/95/", 5), 100);
        UUID sp2 = it.student(tag + "B", "C00023", it.freeNumber("MOAUM/ADM/95/", 6), it.freeNumber("MOAUM/MTC/95/", 5), 100);
        UUID third = it.student(tag + "C", "C00023", it.freeNumber("MOAUM/ADM/95/", 6), it.freeNumber("MOAUM/MTC/95/", 5), 200);
        position(sp1, 400, "SPILLOVER_YEAR_1", 1);
        position(sp2, 400, "SPILLOVER_YEAR_2", 2);
        position(third, 300, "NORMAL", 0);

        // found by the level they should be at, by spillover position; the counts by level and position
        ResponseEntity<Map> at400 = it.get(academic, "/api/v1/cohorts/levels?q=" + tag + "&level=400");
        assertThat(at400.getStatusCode().value()).as(String.valueOf(at400.getBody())).isEqualTo(200);
        assertThat(((Number) at400.getBody().get("total")).intValue()).isEqualTo(2);
        assertThat(((Number) it.get(academic, "/api/v1/cohorts/levels?q=" + tag + "&spillover=SPILLOVER_YEAR_1").getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) it.get(academic, "/api/v1/cohorts/levels?q=" + tag + "&spillover=NONE").getBody().get("total")).intValue()).isEqualTo(1);
        // V598: by the level on record — the one at 200 (should be at 300), not the two at 100
        assertThat(((Number) it.get(academic, "/api/v1/cohorts/levels?q=" + tag + "&current=200").getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) it.call(academic, HttpMethod.POST, "/api/v1/cohorts/levels/apply",
                Map.of("q", tag, "fromLevel", 100, "bases", List.of("SPILLOVER", "REGISTRATION", "ARITHMETIC"))).getBody().get("selected")).intValue()).isEqualTo(2);
        Map<String, Object> all = it.get(academic, "/api/v1/cohorts/levels?q=" + tag).getBody();
        assertThat((List<Map<String, Object>>) all.get("byLevel")).extracting(x -> x.get("level") + ":" + x.get("n")).containsExactly("300:1", "400:2");
        assertThat((List<Map<String, Object>>) all.get("bySpillover")).extracting(x -> x.get("spillover") + ":" + x.get("n"))
                .containsExactlyInAnyOrder("NONE:1", "SPILLOVER_YEAR_1:1", "SPILLOVER_YEAR_2:1");

        // Student Query: by the engine's level and whether the record is below it
        ResponseEntity<Map> behind = it.get(academic, "/api/v1/stats/students/query?q=" + tag + "&expectedLevel=300&levelBehind=YES");
        assertThat(behind.getStatusCode().value()).as(String.valueOf(behind.getBody())).isEqualTo(200);
        assertThat(((Number) behind.getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) it.get(academic, "/api/v1/stats/students/query?q=" + tag + "&expectedLevel=400&levelBehind=YES").getBody().get("total")).intValue()).isEqualTo(2);
        assertThat(it.get(academic, "/api/v1/stats/students/query?q=" + tag + "&recommendation=SPILLOVER_YEAR_1&completion=OUTSTANDING_COURSES&programmeLength=4")
                .getStatusCode().value()).isEqualTo(200);

        // every one found at 400 counted, then corrected; the one who should be at 300 is left
        Map<String, Object> found = Map.of("toLevel", 400, "q", tag);
        Map<String, Object> dry = it.call(academic, HttpMethod.POST, "/api/v1/cohorts/levels/apply", found).getBody();
        assertThat(((Number) dry.get("selected")).intValue()).isEqualTo(2);
        assertThat(((Number) dry.get("corrected")).intValue()).isZero();
        Map<String, Object> run = new java.util.HashMap<>(found);
        run.put("dryRun", false);
        run.put("reason", "Every student who should be at 400 Level, found by the level");
        ResponseEntity<Map> done = it.call(academic, HttpMethod.POST, "/api/v1/cohorts/levels/apply", run);
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(((Number) done.getBody().get("corrected")).intValue()).isEqualTo(2);
        assertThat(((Number) done.getBody().get("remaining")).intValue()).isZero();
        assertThat(jdbc.sql("SELECT string_agg(current_level::text, ',' ORDER BY surname) FROM people.student WHERE id IN (:a, :b, :c)")
                .param("a", sp1).param("b", sp2).param("c", third).query(String.class).single()).isEqualTo("400,400,200");
        assertThat(((Number) it.get(academic, "/api/v1/stats/students/query?q=" + tag + "&expectedLevel=400&levelBehind=YES").getBody().get("total")).intValue()).isZero();

        // the statistics take a position (their figures are read when the University has a current session)
        ResponseEntity<Map> stats = it.get(academic, "/api/v1/stats/students/summary?position=SP1");
        assertThat(stats.getStatusCode().value()).as(String.valueOf(stats.getBody())).isEqualTo(200);
        assertThat(stats.getBody()).containsKey("byPosition");
        assertThat(it.get(academic, "/api/v1/stats/students?position=GRADUATION_CANDIDATE").getStatusCode().value()).isEqualTo(200);
    }
}
