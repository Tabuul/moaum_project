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
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Student cohorts (V331) over the API: the position of a migrated student is computed, not typed — a student whose entry
 * session was cancelled and merged is carried by the merged-into cohort with their matriculation number untouched; the
 * summary and the lists answer the Registry within scope; a student cannot read the desk; a decision needs a reason and
 * never graduates anyone without the Senate; a Head of Department reads only their own department. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CohortIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;
    String registrar = ItSupport.token("registrar");
    String academic = ItSupport.token("academic");
    UUID student;
    String entry;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        // a student whose entry session is an old one on the calendar; the calendar's shape is the database's own
        entry = jdbc.sql("SELECT name FROM policy.academic_session WHERE state IN ('CLOSED','ARCHIVED') ORDER BY starts_on LIMIT 1").query(String.class).optional().orElse(null);
        student = it.student("ZZCOHORT", "C00023", null, "MOAUM/MTC/95/9821", 300);
        it.db(() -> {
            if (entry != null) jdbc.sql("UPDATE people.student SET entry_session = :e WHERE id = :s").param("e", entry).param("s", student).update();
            return null;
        });
    }

    private static Object path(Map body, String key) {
        return body == null ? null : body.get(key);
    }

    /** V612: the Registry pins the student's expected completion and spillover is counted from it; the pin removed, the count returns;
     *  a reason, a session on the calendar; the readers refused the act. The test makes the calendar's latest session CURRENT (an IT
     *  database has none) and puts it back. */
    @Test
    @SuppressWarnings("unchecked")
    void theRegistryPinsTheExpectedCompletionAndSpilloverIsCountedFromIt() {
        List<String> last = jdbc.sql("SELECT name FROM policy.academic_session WHERE state <> 'CANCELLED' ORDER BY starts_on DESC LIMIT 2").query(String.class).list();
        assertThat(last).hasSize(2);
        String latest = last.get(0), before = last.get(1);
        String latestState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", latest).query(String.class).single();
        String previousCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1").query(String.class).optional().orElse(null);
        String door = "/api/v1/cohorts/students/" + student + "/completion";
        try {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT'").update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/IT/612') WHERE name = :n").param("n", latest).update();
                jdbc.sql("UPDATE people.student SET status = 'ACTIVE' WHERE id = :s").param("s", student).update();
                return null;
            });
            jdbc.sql("SELECT people.refresh_academic_position(:s)").param("s", student).query().listOfRows();
            String counted = jdbc.sql("SELECT expected_completion FROM people.academic_position WHERE student_id = :s").param("s", student).query(String.class).optional().orElse(null);

            // pinned to the session before the current one: SP1, from the pin
            ResponseEntity<Map> pinned = it.call(registrar, HttpMethod.POST, door, Map.of("session", before, "reason", "Senate's directive of 1 March: the final year was " + before));
            assertThat(pinned.getStatusCode().value()).as(String.valueOf(pinned.getBody())).isEqualTo(200);
            Map<String, Object> pos = jdbc.sql("SELECT expected_completion, spillover_years, spillover_state FROM people.academic_position WHERE student_id = :s").param("s", student).query().singleRow();
            assertThat(pos.get("expected_completion")).isEqualTo(before);
            assertThat(((Number) pos.get("spillover_years")).intValue()).isEqualTo(1);
            assertThat(pos.get("spillover_state")).isEqualTo("SPILLOVER_YEAR_1");
            Map<String, Object> detail = it.get(registrar, "/api/v1/cohorts/students/" + student).getBody();
            assertThat(((Map<String, Object>) detail.get("completionOverride")).get("expected_completion")).isEqualTo(before);
            assertThat(((List<Map<String, Object>>) detail.get("decisions")).stream().map(x -> x.get("rule"))).contains("COMPLETION");
            assertThat(String.valueOf(detail.get("expected_completion"))).isEqualTo(before);

            // pinned to the current session: not in spillover
            assertThat(it.call(registrar, HttpMethod.POST, door, Map.of("session", latest, "reason", "The Registrar's letter: in the final year this session")).getStatusCode().value()).isEqualTo(200);
            pos = jdbc.sql("SELECT expected_completion, spillover_years, spillover_state FROM people.academic_position WHERE student_id = :s").param("s", student).query().singleRow();
            assertThat(pos.get("expected_completion")).isEqualTo(latest);
            assertThat(pos.get("spillover_state")).isEqualTo("NORMAL");

            // the refusals: no reason; a session off the calendar; a reader at the Registry's door
            assertThat(it.call(registrar, HttpMethod.POST, door, Map.of("session", before, "reason", "")).getStatusCode().value()).isIn(400, 422);
            ResponseEntity<Map> off = it.call(registrar, HttpMethod.POST, door, Map.of("session", "1900/1901", "reason", "No such session on the calendar"));
            assertThat(off.getStatusCode().value()).isEqualTo(422);
            assertThat(String.valueOf(off.getBody())).contains("COMPLETION_SESSION");
            assertThat(it.call(ItSupport.token("ict"), HttpMethod.POST, door, Map.of("session", before, "reason", "Not the Registry's")).getStatusCode().value()).isEqualTo(403);

            // the pin removed: the count returns; nothing to remove is refused
            assertThat(it.call(registrar, HttpMethod.POST, door, Map.of("reason", "Pinned in error")).getStatusCode().value()).isEqualTo(200);
            assertThat(it.get(registrar, "/api/v1/cohorts/students/" + student).getBody().get("completionOverride")).isNull();
            assertThat(jdbc.sql("SELECT expected_completion FROM people.academic_position WHERE student_id = :s").param("s", student).query(String.class).optional().orElse(null)).isEqualTo(counted);
            ResponseEntity<Map> none = it.call(registrar, HttpMethod.POST, door, Map.of("reason", "Nothing stands"));
            assertThat(none.getStatusCode().value()).isEqualTo(422);
            assertThat(String.valueOf(none.getBody())).contains("COMPLETION_NOT_PINNED");
            assertThat(jdbc.sql("SELECT count(*) FROM people.cohort_decision WHERE student_id = :s AND rule = 'COMPLETION'").param("s", student).query(Long.class).single()).isEqualTo(3L);
        } finally {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", latestState).param("n", latest).update();
                if (previousCurrent != null && !previousCurrent.equals(latest)) jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :n").param("n", previousCurrent).update();
                return null;
            });
        }
    }

    @Test
    void thePositionIsComputedFromTheRegisterAndTheRegistryReadsAndDecidesIt() {
        // computed on the student's own events, so it is there before anyone asks
        Map<String, Object> pos = jdbc.sql("SELECT entry_session, effective_cohort, classification, rule, confidence, final_level FROM people.academic_position WHERE student_id = :s").param("s", student).query().singleRow();
        assertThat(pos.get("classification")).isNotNull();
        assertThat(pos.get("final_level")).isEqualTo(jdbc.sql("SELECT final_level FROM ref.programme WHERE code = 'C00023'").query(Integer.class).single());
        if (entry != null) assertThat(pos.get("entry_session")).isEqualTo(entry);
        // the summary and the lists answer the Registry
        ResponseEntity<Map> summary = it.get(registrar, "/api/v1/cohorts/summary");
        assertThat(summary.getStatusCode().value()).as(String.valueOf(summary.getBody())).isEqualTo(200);
        assertThat(((Number) ((Map) path(summary.getBody(), "totals")).get("students")).longValue()).isGreaterThanOrEqualTo(1L);
        ResponseEntity<Map> list = it.get(registrar, "/api/v1/cohorts/students?q=ZZCOHORT&size=10");
        assertThat(list.getStatusCode().value()).as(String.valueOf(list.getBody())).isEqualTo(200);
        List<Map> rows = (List<Map>) path(list.getBody(), "rows");
        assertThat(rows).extracting(r -> String.valueOf(r.get("id"))).contains(student.toString());
        Map row = rows.stream().filter(r -> student.toString().equals(String.valueOf(r.get("id")))).findFirst().orElseThrow();
        assertThat(row.get("matric_no")).isEqualTo("MOAUM/MTC/95/9821");
        assertThat(row.get("matric_year")).isEqualTo(2095);
        // one student's lifecycle
        ResponseEntity<Map> one = it.get(academic, "/api/v1/cohorts/students/" + student);
        assertThat(one.getStatusCode().value()).as(String.valueOf(one.getBody())).isEqualTo(200);
        assertThat(one.getBody()).containsKeys("statusHistory", "registrations", "graduands", "decisions", "outstanding");
        // a student cannot read the desk; a decision needs a reason; nobody is graduated by hand
        assertThat(it.get(TestTokens.token(student, List.of("student")), "/api/v1/cohorts/summary").getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/cohorts/students/" + student + "/decision", Map.of("finalStatus", "ACTIVE", "reason", "")).getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> byHand = it.call(registrar, HttpMethod.POST, "/api/v1/cohorts/students/" + student + "/decision", Map.of("finalStatus", "GRADUATED", "reason", "Looks finished to me"));
        assertThat(byHand.getStatusCode().value()).isEqualTo(422);
        assertThat(path(byHand.getBody(), "code")).isEqualTo("COHORT_GRADUATION_SENATE");
        // a decision on evidence is recorded, the status unchanged where it is the same
        ResponseEntity<Map> decided = it.call(registrar, HttpMethod.POST, "/api/v1/cohorts/students/" + student + "/decision", Map.of("finalStatus", "ACTIVE", "reason", "Registered this session; carried on the register", "batch", "IT-331"));
        assertThat(decided.getStatusCode().value()).as(String.valueOf(decided.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT count(*) FROM people.cohort_decision WHERE student_id = :s AND batch_ref = 'IT-331'").param("s", student).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        // the matriculation number and the entry session are what they were
        Map<String, Object> after = jdbc.sql("SELECT matric_no, entry_session FROM people.student WHERE id = :s").param("s", student).query().singleRow();
        assertThat(after.get("matric_no")).isEqualTo("MOAUM/MTC/95/9821");
        if (entry != null) assertThat(after.get("entry_session")).isEqualTo(entry);
        // the policy is read by the Registry and set only with a reason-bearing office; the settings carry the programmes' lengths
        ResponseEntity<Map> settings = it.get(registrar, "/api/v1/cohorts/settings");
        assertThat(settings.getStatusCode().value()).isEqualTo(200);
        assertThat(((List<Map>) path(settings.getBody(), "programmes"))).anySatisfy(p -> { assertThat(p.get("code")).isEqualTo("C00023"); assertThat(p.get("final_level")).isNotNull(); });
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/cohorts/settings", Map.of("maxSpilloverYears", 2)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(ItSupport.token("hod"), HttpMethod.PUT, "/api/v1/cohorts/settings", Map.of("maxSpilloverYears", 1)).getStatusCode().value()).isEqualTo(403);
        // the bulk act counts before it applies, and takes only the Senate's rule
        ResponseEntity<Map> dry = it.call(registrar, HttpMethod.POST, "/api/v1/cohorts/apply", Map.of("rule", "R1", "dryRun", true));
        assertThat(dry.getStatusCode().value()).as(String.valueOf(dry.getBody())).isEqualTo(200);
        assertThat(path(dry.getBody(), "dryRun")).isEqualTo(true);
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/cohorts/apply", Map.of("rule", "R4", "dryRun", false)).getStatusCode().value()).isEqualTo(422);
    }
}
