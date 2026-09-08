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
 * The faculty list is generated from approved registrations; the run refuses
 * until every list is confirmed; a queried name keeps its admission number;
 * the numbers are issued in one run. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class MatriculationIT {

    static final String SESSION = "2092/2093";
    static final String BASE = "/api/v1/matriculation/sessions/2092/2093";

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
        it.session(SESSION, 2092);
    }

    private void registered(UUID student, UUID offering) {
        it.db(() -> {
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at)
                    VALUES (gen_random_uuid(), :s, :sess, 1, 100, 'APPROVED', now())
                    ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED' RETURNING id
                    """).param("s", student).param("sess", SESSION).query(UUID.class).single();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED') ON CONFLICT DO NOTHING")
                    .param("r", reg).param("o", offering).update();
            return null;
        });
    }

    @Test
    @SuppressWarnings("unchecked")
    void numbersAreIssuedInOneRunOverTheConfirmedLists() {
        UUID med = it.student("ZZMMEDICINE", "C00061", "MOAUM/ADM/92/900001", null, 100);
        UUID sci = it.student("ZZMSCIENCE", "C00023", "MOAUM/ADM/92/900002", null, 100);
        String medMatric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :id").param("id", med).query(String.class).optional().orElse(null);
        if (medMatric != null) {
            return; // an earlier run on this database issued it
        }
        UUID offering = it.db(() -> {
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state)
                    VALUES ('ZZT 101', 'A course for the test', 3, 1, 100, 'MTC', 'LIVE') ON CONFLICT (code) DO NOTHING
                    """).update();
            return jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZT 101', :sess, 1)
                    ON CONFLICT (course_code, session, semester) DO UPDATE SET semester = EXCLUDED.semester RETURNING id
                    """).param("sess", SESSION).query(UUID.class).single();
        });
        registered(med, offering);
        registered(sci, offering);

        ResponseEntity<Map> overview = it.get(academic, BASE);
        assertThat(overview.getStatusCode().value()).as(String.valueOf(overview.getBody())).isEqualTo(200);
        List<Map<String, Object>> faculties = (List<Map<String, Object>>) overview.getBody().get("faculties");
        Map<String, Object> bams = faculties.stream().filter(f -> "BAMS".equals(f.get("code"))).findFirst().orElseThrow();
        assertThat(((Number) bams.get("registered")).intValue()).isEqualTo(1);
        assertThat(bams.get("state")).isEqualTo("NOT_RETURNED");

        // the run cannot start with a faculty outstanding
        ResponseEntity<Map> refused = it.call(academic, HttpMethod.POST, BASE + "/run", null);
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);

        // the Science student is put under query; both lists are confirmed
        String officer = ItSupport.token("facultyofficer");
        ResponseEntity<Map> query = it.call(officer, HttpMethod.PUT, BASE + "/faculties/SC/queries/" + sci,
                Map.of("reason", "Registered 3 units; the minimum at 100 level is 15", "office", "Faculty Officer"));
        assertThat(query.getStatusCode().value()).as(String.valueOf(query.getBody())).isEqualTo(200);
        for (String f : List.of("BAMS", "SC")) {
            ResponseEntity<Map> c = it.call(officer, HttpMethod.POST, BASE + "/faculties/" + f + "/confirm", null);
            assertThat(c.getStatusCode().value()).as(f + ": " + c.getBody()).isEqualTo(200);
        }
        assertThat(it.call(officer, HttpMethod.POST, BASE + "/faculties/SC/confirm", null).getBody().get("code")).isEqualTo("MAT_ALREADY_CONFIRMED");

        // any other faculty with registered students would still block: there are none in this session
        ResponseEntity<Map> run = it.call(academic, HttpMethod.POST, BASE + "/run", null);
        assertThat(run.getStatusCode().value()).as(String.valueOf(run.getBody())).isEqualTo(200);
        assertThat(((Number) run.getBody().get("issued")).intValue()).isEqualTo(1);
        assertThat(String.valueOf(run.getBody().get("run"))).matches("MAT/2092/\\d{3}");

        assertThat(jdbc.sql("SELECT matric_no FROM people.student WHERE id = :id").param("id", med).query(String.class).single())
                .matches("MOAUM/MED/92/\\d{4}");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", sci).query(String.class).single())
                .isEqualTo("ADMITTED");

        // nothing left to matriculate
        assertThat(it.call(academic, HttpMethod.POST, BASE + "/run", null).getStatusCode().value()).isIn(404, 422);

        ResponseEntity<Map> after = it.get(academic, BASE);
        assertThat((List<?>) after.getBody().get("runs")).isNotEmpty();
        assertThat((List<?>) after.getBody().get("heldBack")).hasSize(1);
    }
}
