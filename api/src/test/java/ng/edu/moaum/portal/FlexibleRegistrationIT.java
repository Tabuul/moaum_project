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
 * Flexible course registration (V504), on the student's own door: the student searches for a course beside the recommended list
 * and the engine judges each one found — a course of the programme at a lower level is available, one of a higher level, one not
 * offered in the semester and one of another programme are not, each with the reason; the recommended course is marked; the
 * student adds the lower-level course (a second time is refused), saves it with the list's course, and the registration is
 * approved automatically with both, in the University's order; the Academic Office closes adding other courses and the search
 * says so, a student may not change the rule. The run files everything under its own session. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class FlexibleRegistrationIT {

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
    final String instrument = "BUR/IT/FLEX504";
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    /** the rule back to its default, the fee lines and the clearance scheme the test stated taken away */
    @AfterEach
    void clean() {
        it.call(academic, HttpMethod.PUT, "/api/v1/registration/flex", Map.of("allowOtherCourses", true, "otherScope", "PROGRAMME", "allowHigherLevels", false,
                "reason", "Integration test: the default rule restored"));
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
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 5040")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 5040")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 5040", "next", "Own-Password-5040")).getStatusCode().value()).isEqualTo(200);
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

    @Test
    void aStudentAddsAValidCourseBesideTheListAndIsApprovedWithItInOrder() {
        // a session no test has opened: seven other tests draw theirs from 2300–2899 as well, and a session one of them opened first
        // carries that test's fees, rules and windows
        int y = it.freeYear(2300, 2900);
        session = y + "/" + (y + 1);
        it.session(session, y);
        int n = 1000 + new Random().nextInt(8999);
        String yy = String.format("%02d", y % 100);
        String matric = "MOAUM/ITF/" + yy + "/" + n;
        UUID student = it.student("ZZFLEX" + n, "C00061", "MOAUM/ADM/" + yy + "/47" + n, matric, 200);
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
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
                        ('ITF 201', 'Flex Current', 12, 1, 200, :d, 'Core', 'LIVE'), ('ITF 101', 'Flex Lower Level', 6, 1, 100, :d, 'Core', 'LIVE'),
                        ('ITF 102', 'Flex Second Semester', 3, 2, 100, :d, 'Core', 'LIVE'), ('ITF 301', 'Flex Higher Level', 3, 1, 300, :d, 'Core', 'LIVE'),
                        ('ITX 201', 'Flex Elsewhere', 3, 1, 200, :o, 'Core', 'LIVE')
                    ON CONFLICT (code) DO NOTHING
                    """).param("d", dept).param("o", other).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES
                        ('ITF 201', 'C00061', 200, 'Core'), ('ITF 101', 'C00061', 100, 'Core'), ('ITF 102', 'C00061', 100, 'Core'), ('ITF 301', 'C00061', 300, 'Core')
                    ON CONFLICT DO NOTHING
                    """).update();
            return jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester)
                    SELECT gen_random_uuid(), c, :s, CASE c WHEN 'ITF 102' THEN 2 ELSE 1 END FROM unnest(ARRAY['ITF 201', 'ITF 101', 'ITF 102', 'ITF 301', 'ITX 201']) c
                    ON CONFLICT (course_code, session, semester, stream) DO NOTHING
                    """).param("s", session).update();
        });
        Map<String, Object> ref = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 100000)).getBody();
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "flexible registration test"))
                .getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/registration/approval/rules", Map.of("session", session, "mode", "AUTO_APPROVAL", "allowStudentReset", true,
                "cardOnApproval", true, "reason", "Integration test: automatic approval")).getStatusCode().value()).isEqualTo(200);

        // the view carries the rule and the outstanding courses (none: no published failure)
        Map<String, Object> view = it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1").getBody();
        assertThat((Map<String, Object>) view.get("flex")).containsEntry("allow_other_courses", true).containsEntry("other_scope", "PROGRAMME");
        assertThat((List<?>) view.get("outstanding")).isEmpty();

        // the search: each course judged by the engine, the ones the student may add first
        Map<String, Object> found = search(token, "ITF");
        // a null field is left out of the answer: no refusal is an available course
        assertThat(row(found, "ITF 101")).doesNotContainKey("refusal").containsEntry("category", "CORE").containsEntry("added_as", "PROGRAMME_OTHER_LEVEL");
        assertThat(row(found, "ITF 201")).doesNotContainKey("refusal").containsEntry("recommended", true);
        assertThat(String.valueOf(row(found, "ITF 301").get("refusal"))).startsWith("REG_HIGHER_LEVEL:");
        assertThat(String.valueOf(row(found, "ITF 102").get("refusal"))).startsWith("REG_NOT_OFFERED_SEMESTER:").contains("second semester");
        assertThat(String.valueOf(row(search(token, "ITX 201"), "ITX 201").get("refusal"))).startsWith("REG_NOT_AVAILABLE:");
        List<Map<String, Object>> rows = (List<Map<String, Object>>) found.get("results");
        assertThat(rows.get(0).get("refusal")).isNull();
        assertThat(rows.get(rows.size() - 1).get("refusal")).isNotNull();
        assertThat(it.get(token, u -> u.path("/api/v1/me/registration/courses").queryParam("session", session).queryParam("category", "ANY").build()).getBody())
                .containsEntry("code", "REG_SEARCH_CATEGORY");
        // V507: nothing typed, the student's own courses are listed; a category alone narrows them
        Map<String, Object> own = it.get(token, u -> u.path("/api/v1/me/registration/courses").queryParam("session", session).queryParam("semester", 1).build()).getBody();
        assertThat(own).containsEntry("listed", "YOUR_COURSES");
        assertThat((List<Map<String, Object>>) own.get("results")).extracting(x -> x.get("course_code")).contains("ITF 201", "ITF 101", "ITF 301").doesNotContain("ITX 201");
        Map<String, Object> core = it.get(token, u -> u.path("/api/v1/me/registration/courses").queryParam("session", session).queryParam("semester", 1)
                .queryParam("category", "CORE").build()).getBody();
        assertThat((List<Map<String, Object>>) core.get("results")).isNotEmpty().allSatisfy(x -> assertThat(x.get("category")).isEqualTo("CORE"));
        assertThat((List<Map<String, Object>>) core.get("results")).extracting(x -> x.get("course_code")).contains("ITF 201", "ITF 101");
        assertThat(((Number) it.get(token, u -> u.path("/api/v1/me/registration/courses").queryParam("session", session).queryParam("semester", 1)
                .queryParam("category", "CARRY_OVER").build()).getBody().get("total")).intValue()).isZero();

        // a higher-level course is refused with its reason; the lower-level one is added, once
        String o101 = String.valueOf(row(found, "ITF 101").get("offering_id"));
        String o301 = String.valueOf(row(found, "ITF 301").get("offering_id"));
        String o201 = String.valueOf(row(found, "ITF 201").get("offering_id"));
        ResponseEntity<Map> higher = it.call(token, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "offering", o301));
        assertThat(higher.getBody()).as(higher.getStatusCode().value() + " " + higher.getBody()).containsEntry("code", "REG_HIGHER_LEVEL");
        ResponseEntity<Map> added = it.call(token, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "offering", o101));
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) added.getBody().get("added")).containsEntry("courseCode", "ITF 101").containsEntry("addedAs", "PROGRAMME_OTHER_LEVEL");
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "offering", o101)).getBody())
                .containsEntry("code", "REG_ALREADY_ADDED");

        // saved with the list's course, submitted, approved automatically: both on it, in the University's order
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of(o201, o101))).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> submitted = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("result")).isEqualTo("approved");
        Map<String, Object> reg = (Map<String, Object>) submitted.getBody().get("registration");
        List<Map<String, Object>> entries = (List<Map<String, Object>>) reg.get("entries");
        assertThat(entries).extracting(e -> e.get("courseCode")).containsExactly("ITF 101", "ITF 201");
        assertThat(entries.get(0)).containsEntry("studentAdded", true).containsEntry("category", "CORE").containsEntry("addedAs", "PROGRAMME_OTHER_LEVEL");
        assertThat(entries.get(1)).containsEntry("studentAdded", false);
        assertThat(String.valueOf(row(search(token, "ITF 101"), "ITF 101").get("on_registration"))).isEqualTo("true");

        // the rule is the Academic Office's, not the student's; closed, the search says so
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/registration/flex", Map.of("allowOtherCourses", false, "otherScope", "PROGRAMME", "allowHigherLevels", false,
                "reason", "a student trying to change it")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> off = it.call(academic, HttpMethod.PUT, "/api/v1/registration/flex", Map.of("allowOtherCourses", false, "otherScope", "PROGRAMME", "allowHigherLevels", false,
                "reason", "Integration test: other courses closed"));
        assertThat(off.getStatusCode().value()).as(String.valueOf(off.getBody())).isEqualTo(200);
        assertThat(off.getBody()).containsEntry("allow_other_courses", false).containsEntry("set_office", "academic");
        assertThat(String.valueOf(row(search(token, "ITF 101"), "ITF 101").get("refusal"))).startsWith("REG_OTHER_COURSES_OFF:");
    }
}
