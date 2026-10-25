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
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * Every course registrable whatever its class (V655), on the student's own door: a course of the programme with no class in the session
 * (bound after registration opened) is found by Add Other Course as available, with no class; the student adds it by its code, its class
 * opens once and the course is on the draft; a second add is refused as already added; another department's course is refused with its
 * reason and opens no class; an add naming neither a class nor a course is refused; the registration page reads with the course on the recommended
 * list. The run files everything under its own session.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseWithNoClassIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");
    final String academic = ItSupport.token("academic");
    final String instrument = "BUR/IT/NOCLASS655";
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
        it.call(academic, HttpMethod.PUT, "/api/v1/registration/flex", Map.of("allowOtherCourses", true, "otherScope", "PROGRAMME", "allowHigherLevels", false,
                "reason", "Integration test: the default rule"));
    }

    /** the fee lines and the clearance scheme the test stated taken away */
    @AfterEach
    void clean() {
        it.db(() -> {
            if (session != null) jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
            jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            return jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
        });
    }

    private ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    private String signedIn(UUID student, String matric) {
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 6550")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 6550")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 6550", "next", "Own-Password-6550")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    private Map<String, Object> search(String token, String q) {
        ResponseEntity<Map> r = it.get(token, u -> u.path("/api/v1/me/registration/courses").queryParam("session", session).queryParam("semester", 1).queryParam("q", q).build());
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static Map<String, Object> row(Map<String, Object> found, String code) {
        return ((List<Map<String, Object>>) found.get("results")).stream().filter(x -> code.equals(x.get("course_code"))).findFirst().orElseThrow();
    }

    private int classes(String code) {
        return jdbc.sql("SELECT count(*) FROM catalogue.offering WHERE course_code = :c AND session = :s").param("c", code).param("s", session).query(Integer.class).single();
    }

    @Test
    void aCourseWithNoClassInTheSessionIsAddedAndItsClassOpensOnce() {
        int y = it.freeYear(2300, 2900);
        session = y + "/" + (y + 1);
        it.session(session, y);
        int n = 1000 + new Random().nextInt(8999);
        String yy = String.format("%02d", y % 100);
        String matric = "MOAUM/ITN/" + yy + "/" + n;
        UUID student = it.student("ZZNOCLASS" + n, "C00061", "MOAUM/ADM/" + yy + "/65" + n, matric, 200);
        String token = signedIn(student, matric);

        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/schedule", Map.of("item", "School fees", "amount", 100000, "level", 200)).getStatusCode().value()).isEqualTo(200);
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           :i, 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).param("i", instrument).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = :i ON CONFLICT DO NOTHING").param("i", instrument).update();
            jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED' ELSE 'INSTALMENT_1' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = :i ON CONFLICT DO NOTHING
                    """).param("i", instrument).update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
            String other = jdbc.sql("SELECT code FROM ref.department WHERE code <> :d ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
            // bound to the programme with no class in the session (as one bound after registration opened); another department's
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
                        ('ITN 201', 'No Class Yet', 3, 1, 200, :d, 'Core', 'LIVE'), ('ITN 299', 'No Class Elsewhere', 3, 1, 200, :o, 'Core', 'LIVE')
                    ON CONFLICT (code) DO NOTHING
                    """).param("d", dept).param("o", other).update();
            return jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('ITN 201', 'C00061', 200, 'Core') ON CONFLICT DO NOTHING").update();
        });
        Map<String, Object> ref = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 100000)).getBody();
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "no class test"))
                .getStatusCode().value()).isEqualTo(200);
        assertThat(classes("ITN 201")).isZero();

        // found as available, with no class (a null field is left out of the answer); the other department's is not
        Map<String, Object> found = search(token, "ITN");
        assertThat(row(found, "ITN 201")).doesNotContainKey("refusal").doesNotContainKey("offering_id").containsEntry("category", "CORE");
        assertThat(String.valueOf(row(found, "ITN 299").get("refusal"))).startsWith("REG_NOT_AVAILABLE:");
        // nothing typed: the student's own courses list it too
        Map<String, Object> own = it.get(token, u -> u.path("/api/v1/me/registration/courses").queryParam("session", session).queryParam("semester", 1).build()).getBody();
        assertThat((List<Map<String, Object>>) own.get("results")).extracting(x -> x.get("course_code")).contains("ITN 201");

        // refused: the reason, and no class opened; an add naming nothing is refused
        ResponseEntity<Map> elsewhere = it.call(token, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "courseCode", "ITN 299"));
        assertThat(elsewhere.getStatusCode().value()).as(String.valueOf(elsewhere.getBody())).isEqualTo(422);
        assertThat(elsewhere.getBody()).containsEntry("code", "REG_NOT_AVAILABLE");
        assertThat(classes("ITN 299")).isZero();
        ResponseEntity<Map> nothing = it.call(token, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1));
        assertThat(nothing.getStatusCode().value()).isEqualTo(422);
        assertThat(nothing.getBody()).containsEntry("code", "REG_COURSE_UNKNOWN");

        // added by its code: the class opens once, the course is on the draft; again is refused as already added
        ResponseEntity<Map> added = it.call(token, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "courseCode", "ITN 201"));
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) added.getBody().get("added")).containsEntry("courseCode", "ITN 201");
        String cls = String.valueOf(added.getBody().get("offering"));
        assertThat(classes("ITN 201")).isEqualTo(1);
        assertThat(jdbc.sql("SELECT id::text FROM catalogue.offering WHERE course_code = 'ITN 201' AND session = :s AND semester = 1").param("s", session).query(String.class).single())
                .isEqualTo(cls);
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "courseCode", "ITN 201")).getBody())
                .containsEntry("code", "REG_ALREADY_ADDED");
        assertThat(classes("ITN 201")).isEqualTo(1);
        Map<String, Object> after = row(search(token, "ITN 201"), "ITN 201");
        assertThat(after).containsEntry("offering_id", cls);
        assertThat(String.valueOf(after.get("on_registration"))).isEqualTo("true");

        // the registration page reads through its own transaction (V655: in the session the student registers in now, the classes of
        // the student's level are opened first): the course is on the recommended list; the student's own session reads too
        ResponseEntity<Map> page = it.get(token, u -> u.path("/api/v1/me/registration").queryParam("session", session).queryParam("semester", 1).build());
        assertThat(page.getStatusCode().value()).as(String.valueOf(page.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) page.getBody().get("menu")).extracting(x -> x.get("course_code")).contains("ITN 201");
        ResponseEntity<Map> own2 = it.get(token, "/api/v1/me/registration?semester=1");
        assertThat(own2.getStatusCode().value()).as(String.valueOf(own2.getBody())).isEqualTo(200);
    }
}
