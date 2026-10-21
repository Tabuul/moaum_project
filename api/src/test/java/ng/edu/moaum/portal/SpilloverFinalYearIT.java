package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V595: spillover counted from the final year as the register shows it. Two students admitted five sessions ago to a four-year
 * programme (the count of sessions completes it two sessions ago): the one whose first registration at 400 Level was last session
 * is SP1, not SP2, and the Registry reads SP1 on the cohort desk; the one with no registration at the final level is SP2 as before.
 * The run's session is made current for the engine and the previous one given back. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SpilloverFinalYearIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String previousCurrent;
    String current;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        previousCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1").query(String.class).optional().orElse(null);
    }

    /** the calendar as it was: the run's session planned again, the previous current session current again */
    @AfterEach
    void clean() {
        it.db(() -> {
            if (current != null) jdbc.sql("UPDATE policy.academic_session SET state = 'PLANNED', made_current_at = NULL WHERE name = :n AND state = 'CURRENT'").param("n", current).update();
            if (previousCurrent != null) jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :n").param("n", previousCurrent).update();
            return null;
        });
    }

    @Test
    void spilloverIsCountedFromTheFinalYearTheRegisterShows() {
        int y = it.freeYear(3400, 3800, 5, 0);
        for (int x = y - 5; x <= y; x++) it.session(x + "/" + (x + 1), x);
        current = y + "/" + (y + 1);
        String entry = (y - 5) + "/" + (y - 4);
        String lastSession = (y - 1) + "/" + y;
        it.db(() -> {
            jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED', completed_at = now() WHERE state = 'CURRENT'").update();
            return jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', made_current_at = now(), senate_minute = 'SEN/IT/595' WHERE name = :n").param("n", current).update();
        });
        String yy = String.format("%02d", y % 100);
        int n = 1000 + new Random().nextInt(8999);
        UUID late = it.student("ZZSPILLLATE" + n, "C00023", "MOAUM/ADM/" + yy + "/71" + n, "MOAUM/ITS/" + yy + "/" + n, 400);
        UUID none = it.student("ZZSPILLNONE" + n, "C00023", "MOAUM/ADM/" + yy + "/72" + n, "MOAUM/ITT/" + yy + "/" + n, 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :e, entry_level = 100 WHERE id IN (:a, :b)").param("e", entry).param("a", late).param("b", none).update();
            // the late one: 300 Level two sessions ago, 400 Level for the first time last session
            jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES
                        (gen_random_uuid(), :s, :s3, 1, 300, 'APPROVED', now(), now()), (gen_random_uuid(), :s, :s4, 1, 400, 'APPROVED', now(), now())
                    """).param("s", late).param("s3", (y - 2) + "/" + (y - 1)).param("s4", lastSession).update();
            return jdbc.sql("SELECT people.refresh_academic_positions(ARRAY[:a, :b]::uuid[])").param("a", late).param("b", none).query(Integer.class).single();
        });
        Map<String, Object> lateRow = jdbc.sql("SELECT expected_completion, spillover_years, spillover_state, computed_level FROM people.academic_position WHERE student_id = :s").param("s", late).query().singleRow();
        Map<String, Object> noneRow = jdbc.sql("SELECT expected_completion, spillover_years, spillover_state FROM people.academic_position WHERE student_id = :s").param("s", none).query().singleRow();
        assertThat(lateRow).as(String.valueOf(lateRow)).containsEntry("expected_completion", lastSession).containsEntry("spillover_years", 1).containsEntry("spillover_state", "SPILLOVER_YEAR_1").containsEntry("computed_level", 400);
        assertThat(noneRow).as(String.valueOf(noneRow)).containsEntry("expected_completion", (y - 2) + "/" + (y - 1)).containsEntry("spillover_years", 2).containsEntry("spillover_state", "SPILLOVER_YEAR_2");

        // the Registry reads the same on the cohort desk
        ResponseEntity<Map> one = it.get(ItSupport.token("registrar"), "/api/v1/cohorts/students/" + late);
        assertThat(one.getStatusCode().value()).as(String.valueOf(one.getBody())).isEqualTo(200);
        assertThat(String.valueOf(one.getBody())).contains("SPILLOVER_YEAR_1").doesNotContain("SPILLOVER_YEAR_2");
        assertThat(it.get(TestTokens.token(late, List.of("student")), "/api/v1/cohorts/students/" + late).getStatusCode().value()).isEqualTo(403);
    }
}
