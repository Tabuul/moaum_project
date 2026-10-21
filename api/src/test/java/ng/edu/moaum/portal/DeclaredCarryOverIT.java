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
 * V611, on the student's own door: a course the student registered in an earlier session whose result is not on the portal (no
 * score sheet of it here: the old portal's) is listed among the student's carry-overs, marked as one the student declares; one whose
 * sheet is still being entered waits for its result. The student adds the declared carry-over, saving without it lets it go, added
 * again it is saved with the list's course and the registration is approved automatically with it, a carry-over marked declared.
 * The run files everything under its own two sessions. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class DeclaredCarryOverIT {

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
    final String instrument = "BUR/IT/CARRY611";
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
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
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 6110")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 6110")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 6110", "next", "Own-Password-6110")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    private Map<String, Object> courses(String token, String category, String q) {
        ResponseEntity<Map> r = it.get(token, u -> {
            u.path("/api/v1/me/registration/courses").queryParam("session", session).queryParam("semester", 1);
            if (category != null) u.queryParam("category", category);
            if (q != null) u.queryParam("q", q);
            return u.build();
        });
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static Map<String, Object> row(Map<String, Object> found, String code) {
        return ((List<Map<String, Object>>) found.get("results")).stream().filter(x -> code.equals(x.get("course_code"))).findFirst().orElseThrow();
    }

    @Test
    void aStudentDeclaresACarryOverWhoseResultIsNotOnThePortal() {
        // two sessions no test has opened: the earlier one the course was registered in, and this one
        int y = it.freeYear(2300, 2900, 1, 0);
        String earlier = (y - 1) + "/" + y;
        session = y + "/" + (y + 1);
        it.session(earlier, y - 1);
        it.session(session, y);
        int n = 1000 + new Random().nextInt(8999);
        String yy = String.format("%02d", y % 100);
        String matric = "MOAUM/ITD/" + yy + "/" + n;
        UUID student = it.student("ZZDECLARE" + n, "C00061", "MOAUM/ADM/" + yy + "/61" + n, matric, 200);
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
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
                        ('ITD 201', 'Declared Current', 12, 1, 200, :d, 'Core', 'LIVE'), ('ITD 101', 'Declared Carry-over', 6, 1, 100, :d, 'Core', 'LIVE'),
                        ('ITD 103', 'Declared Result Awaited', 3, 1, 100, :d, 'Core', 'LIVE')
                    ON CONFLICT (code) DO UPDATE SET units = EXCLUDED.units, title = EXCLUDED.title
                    """).param("d", dept).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES
                        ('ITD 201', 'C00061', 200, 'Core'), ('ITD 101', 'C00061', 100, 'Core'), ('ITD 103', 'C00061', 100, 'Core')
                    ON CONFLICT DO NOTHING
                    """).update();
            jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester)
                    SELECT gen_random_uuid(), c, s, 1 FROM unnest(ARRAY['ITD 101', 'ITD 103']) c, unnest(ARRAY[:e, :s]) s
                    UNION ALL SELECT gen_random_uuid(), 'ITD 201', :s, 1
                    ON CONFLICT (course_code, session, semester, stream) DO NOTHING
                    """).param("e", earlier).param("s", session).update();
            // registered and approved in the earlier session: ITD 101 with no score sheet here, ITD 103 with its sheet still at entry
            UUID reg = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                    VALUES (:r, :st, :e, 1, 100, 'APPROVED', now(), now())
                    """).param("r", reg).param("st", student).param("e", earlier).update();
            jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                    SELECT :r, o.id, 3, 'CURRENT', 'APPROVED' FROM catalogue.offering o WHERE o.session = :e AND o.course_code IN ('ITD 101', 'ITD 103')
                    """).param("r", reg).param("e", earlier).update();
            return jdbc.sql("""
                    INSERT INTO assessment.score_sheet (id, offering_id, stage)
                    SELECT gen_random_uuid(), o.id, 'ENTRY' FROM catalogue.offering o WHERE o.session = :e AND o.course_code = 'ITD 103'
                    ON CONFLICT DO NOTHING
                    """).param("e", earlier).update();
        });
        Map<String, Object> ref = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 100000)).getBody();
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "declared carry-over test"))
                .getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/registration/approval/rules", Map.of("session", session, "mode", "AUTO_APPROVAL", "allowStudentReset", true,
                "cardOnApproval", true, "reason", "Integration test: automatic approval")).getStatusCode().value()).isEqualTo(200);

        // the carry-overs: ITD 101 declared (no result on the portal); ITD 103 waits for the result its sheet will bring
        Map<String, Object> carry = courses(token, "CARRY_OVER", null);
        assertThat(((Number) carry.get("total")).intValue()).isEqualTo(1);
        assertThat(row(carry, "ITD 101")).doesNotContainKey("refusal").containsEntry("category", "CARRY_OVER").containsEntry("added_as", "CARRY_OVER_DECLARED");
        assertThat(String.valueOf(row(carry, "ITD 101").get("why"))).startsWith("Carry-over you declare");
        assertThat(String.valueOf(row(courses(token, null, "ITD 103"), "ITD 103").get("refusal"))).startsWith("REG_RESULT_AWAITED:");
        String o101 = String.valueOf(row(carry, "ITD 101").get("offering_id"));
        String o201 = String.valueOf(row(courses(token, null, "ITD 201"), "ITD 201").get("offering_id"));

        // added, then saved without it: let go
        ResponseEntity<Map> added = it.call(token, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "offering", o101));
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) added.getBody().get("added")).containsEntry("courseCode", "ITD 101").containsEntry("category", "CARRY_OVER")
                .containsEntry("addedAs", "CARRY_OVER_DECLARED");
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of(o201))).getStatusCode().value()).isEqualTo(200);
        assertThat(String.valueOf(row(courses(token, "CARRY_OVER", null), "ITD 101").get("on_registration"))).isEqualTo("false");

        // added again, saved with the list's course, approved automatically with it: a carry-over, marked declared
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "offering", o101)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of(o201, o101))).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> submitted = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("result")).isEqualTo("approved");
        List<Map<String, Object>> entries = (List<Map<String, Object>>) ((Map<String, Object>) submitted.getBody().get("registration")).get("entries");
        assertThat(entries).extracting(e -> e.get("courseCode")).containsExactly("ITD 101", "ITD 201");
        assertThat(entries.get(0)).containsEntry("category", "CARRY_OVER").containsEntry("addedAs", "CARRY_OVER_DECLARED").containsEntry("studentAdded", true);
    }
}
