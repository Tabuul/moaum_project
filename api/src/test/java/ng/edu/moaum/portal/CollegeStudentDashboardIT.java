package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
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
 * V603: the College's own student area (/college/student) is for the programmes the College runs on its own machinery
 * (college.programme_rule: MBBS), not for every College of Health Sciences student. The dashboard the student lands on is the
 * API's (GET /api/v1/me, dashboard), from the programme and level on the record: COLLEGE for MBBS from 200 Level, UNIVERSITY for
 * MBBS at 100 Level and for Nursing, Medical Laboratory Science and every other programme. The College's student doors refuse a
 * student of another programme on the server (COLLEGE_NOT_MBBS), and a programme change changes the dashboard with the record.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CollegeStudentDashboardIT {

    static final String MBBS = "C00061";
    static final String NURSING = "C35147";
    static final String MLS = "C49412";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private String dashboard(ItSupport it, String token) {
        ResponseEntity<Map> me = it.get(token, "/api/v1/me");
        assertThat(me.getStatusCode().value()).as(String.valueOf(me.getBody())).isEqualTo(200);
        return String.valueOf(me.getBody().get("dashboard"));
    }

    @Test
    void onlyMbbsStudentsUseTheCollegesOwnStudentAreaAndAProgrammeChangeMovesTheDashboard() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        UUID mbbs = it.student(it.freeSurname("ZZCSDMBBS"), MBBS, null, it.freeNumber("MOAUM/CSD/26/1", 5), 300);
        UUID first = it.student(it.freeSurname("ZZCSDMBBSONE"), MBBS, null, it.freeNumber("MOAUM/CSD/26/2", 5), 100);
        UUID nursing = it.student(it.freeSurname("ZZCSDNURSE"), NURSING, null, it.freeNumber("MOAUM/CSD/26/3", 5), 200);
        UUID mls = it.student(it.freeSurname("ZZCSDMLS"), MLS, null, it.freeNumber("MOAUM/CSD/26/4", 5), 300);
        String tMbbs = TestTokens.token(mbbs, List.of("student"));
        String tFirst = TestTokens.token(first, List.of("student"));
        String tNursing = TestTokens.token(nursing, List.of("student"));
        String tMls = TestTokens.token(mls, List.of("student"));

        // MBBS from 200 Level lands in the College's area; MBBS at 100 Level, Nursing and MLS on the University's portal
        assertThat(dashboard(it, tMbbs)).isEqualTo("COLLEGE");
        assertThat(dashboard(it, tFirst)).isEqualTo("UNIVERSITY");
        assertThat(dashboard(it, tNursing)).isEqualTo("UNIVERSITY");
        assertThat(dashboard(it, tMls)).isEqualTo("UNIVERSITY");
        // V606: the College's area is an MBBS student's at every level (the menu's link), never a Nursing student's
        assertThat(it.get(tFirst, "/api/v1/me").getBody()).containsEntry("collegeArea", true);
        assertThat(it.get(tMbbs, "/api/v1/me").getBody()).containsEntry("collegeArea", true);
        assertThat(it.get(tNursing, "/api/v1/me").getBody()).containsEntry("collegeArea", false);

        // the College's student doors: open to MBBS (100 Level reads its record too), refused to anyone else on the server
        ResponseEntity<Map> record = it.get(tMbbs, "/api/v1/college/my-record");
        assertThat(record.getStatusCode().value()).as(String.valueOf(record.getBody())).isEqualTo(200);
        assertThat(it.get(tFirst, "/api/v1/college/my-record").getStatusCode().value()).isEqualTo(200);
        for (String door : List.of("/api/v1/college/my-record", "/api/v1/college/my-logbooks", "/api/v1/college/my-assessments", "/api/v1/college/my-postings")) {
            ResponseEntity<Map> refused = it.get(tNursing, door);
            assertThat(refused.getStatusCode().value()).as(door + " " + refused.getBody()).isEqualTo(422);
            assertThat(refused.getBody()).as(door).containsEntry("code", "COLLEGE_NOT_MBBS");
        }
        assertThat(it.get(tMls, "/api/v1/college/my-record").getBody()).containsEntry("code", "COLLEGE_NOT_MBBS");
        ResponseEntity<Map> register = it.call(tNursing, HttpMethod.POST, "/api/v1/college/register", Map.of());
        assertThat(register.getStatusCode().value()).as(String.valueOf(register.getBody())).isEqualTo(422);
        assertThat(register.getBody()).containsEntry("code", "COLLEGE_NOT_MBBS");
        // the database refuses it too, whoever calls it
        String refusedInDb;
        try {
            refusedInDb = jdbc.sql("SELECT college.register_level(:s, NULL)").param("s", nursing).query(String.class).single();
        } catch (RuntimeException e) {
            refusedInDb = String.valueOf(e.getMessage());
        }
        assertThat(refusedInDb).contains("COLLEGE_NOT_MBBS");

        // a programme change moves the dashboard with the record: MBBS to Nursing, and Nursing to MBBS
        it.db(() -> jdbc.sql("UPDATE people.student SET programme_code = :p WHERE id = :s").param("p", NURSING).param("s", mbbs).update());
        assertThat(dashboard(it, tMbbs)).isEqualTo("UNIVERSITY");
        assertThat(it.get(tMbbs, "/api/v1/college/my-record").getBody()).containsEntry("code", "COLLEGE_NOT_MBBS");
        it.db(() -> jdbc.sql("UPDATE people.student SET programme_code = :p WHERE id = :s").param("p", MBBS).param("s", nursing).update());
        assertThat(dashboard(it, tNursing)).isEqualTo("COLLEGE");
        assertThat(it.get(tNursing, "/api/v1/college/my-record").getStatusCode().value()).isEqualTo(200);
    }
}
