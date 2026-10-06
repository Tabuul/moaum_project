package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The Head of Department's dashboard answers for a Head whose office is tied to a department, whatever one figure does:
 * the fee figure reads through the clearance scheme, which refuses rather than assumes when none is in force, and that
 * refusal is named on the figure instead of taking the whole dashboard down (where the screen then said, wrongly, that
 * the office was not tied to a department). A Head with no department is told so. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class HodDashboardIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void theDashboardAnswersForATiedHeadAndNamesAFigureItCannotRead() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        ResponseEntity<Map> home = it.get(it.officer("hod", "department", "MTC"), "/api/v1/hod/dashboard");
        assertThat(home.getStatusCode().value()).as(String.valueOf(home.getBody())).isEqualTo(200);
        Map body = home.getBody();
        assertThat(body.get("resolved")).isEqualTo(true);
        assertThat(body.get("dept")).isEqualTo("MTC");
        assertThat(body).containsKeys("approvals", "deptStudents", "deptCourses", "pipeline", "unavailable");
        Map unavailable = (Map) body.get("unavailable");
        boolean scheme = jdbc.sql("SELECT policy.in_force('clearance', 'UNIVERSITY', current_date) IS NOT NULL").query(Boolean.class).single();
        if (scheme) {
            assertThat(body.get("feesCleared")).as("with a clearance scheme in force the fee figure reads").isNotNull();
        } else {
            assertThat(body.get("feesCleared")).as("with no clearance scheme in force the fee figure is not read").isNull();
            assertThat(unavailable).containsKey("feesCleared");
        }
        // every other figure stands either way
        assertThat(body.get("deptStudents")).isNotNull();
        assertThat(unavailable).doesNotContainKeys("approvals", "deptStudents", "deptCourses", "pipeline", "tracks");

        // a Head whose office names no department is told so — the one case the notice is for
        ResponseEntity<Map> none = it.get(TestTokens.token(it.person("ZZ-HOD-NONE", "ZZHODNONE"), java.util.List.of("hod")), "/api/v1/hod/dashboard");
        assertThat(none.getStatusCode().value()).isEqualTo(200);
        assertThat(none.getBody().get("resolved")).isEqualTo(false);
    }
}
