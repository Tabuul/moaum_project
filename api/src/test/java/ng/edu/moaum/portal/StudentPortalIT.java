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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * The student's side end to end (V026): the Registry opens the account, the
 * student signs in, the Bursar states the charge and the scheme, the student
 * pays a reference the Bursary confirms, registers against the eligible set,
 * and submits once the scheme releases it.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class StudentPortalIT {

    static final String SESSION = "2090/2091";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    String registrar = ItSupport.token("registrar");
    String bursar = ItSupport.token("bursar");
    String hod = ItSupport.token("hod");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
        it.session(SESSION, 2090);
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    @Test
    @SuppressWarnings("unchecked")
    void theRegistryOpensTheAccountAndTheStudentRegistersOnceTheBursaryClears() {
        int n = new Random().nextInt(9000) + 1000;
        String matric = "MOAUM/ITP/90/" + n;
        UUID student = it.student("ITPORTAL" + n, "C00061", "MOAUM/ADM/90/00" + n, matric, 100);

        // no account yet: the door says so
        ResponseEntity<Map> none = post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "whatever it is"));
        assertThat(none.getStatusCode().value()).isEqualTo(422);
        assertThat(none.getBody().get("code")).isEqualTo("AUTH_NO_STUDENT_ACCOUNT");

        // the Registry opens it with a first password
        ResponseEntity<Map> opened = it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 2090"));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        ResponseEntity<Map> signed = post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric.toLowerCase(), "password", "first password 2090"));
        assertThat(signed.getStatusCode().value()).as(String.valueOf(signed.getBody())).isEqualTo(200);
        assertThat(signed.getBody().get("mustChange")).isEqualTo(true);
        String token = String.valueOf(signed.getBody().get("token"));

        // the student changes it, and the old one no longer signs in
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 2090", "next", "my own password 2090")).getStatusCode().value()).isEqualTo(200);
        assertThat(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 2090")).getStatusCode().value()).isEqualTo(422);

        // me: the record as the register holds it, no charge yet
        Map<String, Object> me = it.get(token, "/api/v1/me").getBody();
        assertThat(me.get("matricNo")).isEqualTo(matric);
        Map<String, Object> fees = (Map<String, Object>) me.get("fees");
        assertThat(((Number) fees.get("due")).doubleValue()).isEqualTo(0.0);

        // the student's token reaches nothing of an office's
        assertThat(it.get(token, "/api/v1/finance/sessions/2090/2091/schedule").getStatusCode().value()).isEqualTo(403);

        // the Bursar states the charge: 100,000 to everybody at 100 level, and an item for 400 level that does not apply
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/2090/2091/schedule", Map.of("item", "School fees", "amount", 100000, "level", 100)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/2090/2091/schedule", Map.of("item", "Final year charge", "amount", 50000, "level", 400)).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> fees2 = it.get(token, "/api/v1/me/fees?session=2090/2091").getBody();
        assertThat(((Number) fees2.get("due")).doubleValue()).isEqualTo(100000.0);
        assertThat(((Number) fees2.get("balance")).doubleValue()).isEqualTo(100000.0);

        // a reference for half the charge, confirmed by the Bursary: a receipt, and a notice to the student
        Map<String, Object> withRef = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", SESSION, "amount", 50000)).getBody();
        String reference = String.valueOf(withRef.get("reference"));
        assertThat(reference).startsWith("MOAUM-FEE-");
        // more than the balance is refused
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", SESSION, "amount", 900000)).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> confirmed = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + reference + "/confirm", Map.of("channel", "Bank transfer", "note", "teller 0091"));
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
        Map<String, Object> receipt = it.get(token, "/api/v1/me/fees/receipts/" + reference).getBody();
        assertThat(String.valueOf(receipt.get("receipt_no"))).startsWith("RCT-2090-");
        Map<String, Object> fees3 = it.get(token, "/api/v1/me/fees?session=2090/2091").getBody();
        assertThat(((Number) fees3.get("paid")).doubleValue()).isEqualTo(50000.0);
        assertThat(fees3.get("instalmentsPaid")).isEqualTo(1);

        // the registration: two courses offered to the programme this semester
        it.db(() -> {
            String dept = jdbc.sql("SELECT code FROM ref.department ORDER BY code LIMIT 1").query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES ('ITP 101', 'Portal Course One', 12, 1, 100, :d, 'Compulsory', 'LIVE'), ('ITP 102', 'Portal Course Two', 6, 1, 100, :d, 'Elective', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('ITP 101', 'C00061', 100, 'Core'), ('ITP 102', 'C00061', 100, 'Elective') ON CONFLICT DO NOTHING").update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ITP 101', :s, 1), (gen_random_uuid(), 'ITP 102', :s, 1) ON CONFLICT (course_code, session, semester) DO NOTHING")
                    .param("s", SESSION).update();
            return null;
        });
        Map<String, Object> view = it.get(token, "/api/v1/me/registration?session=2090/2091&semester=1").getBody();
        List<Map<String, Object>> menu = (List<Map<String, Object>>) view.get("menu");
        assertThat(menu.stream().map(m -> String.valueOf(m.get("course_code"))).toList()).contains("ITP 101", "ITP 102");
        List<UUID> offerings = menu.stream().map(m -> UUID.fromString(String.valueOf(m.get("offering_id")))).toList();
        Map<String, Object> chosen = it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", offerings)).getBody();
        assertThat(((Map<String, Object>) chosen.get("registration")).get("units")).isEqualTo(18);

        // submitting with no clearance scheme in force is refused: the portal refuses rather than assumes (D-Q4)
        ResponseEntity<Map> refused = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", SESSION, "semester", 1));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);

        // the Bursar puts the recommended scheme in force under a minute — bounded before any scheme already in force from a later date
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           'BUR/IT/2090', 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = 'BUR/IT/2090' ON CONFLICT DO NOTHING").update();
            jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED'
                        WHEN 'REGISTRATION' THEN 'INSTALMENT_1' WHEN 'ID_CARD' THEN 'INSTALMENT_1' WHEN 'LIBRARY' THEN 'INSTALMENT_1' ELSE 'PAID_IN_FULL' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = 'BUR/IT/2090' ON CONFLICT DO NOTHING
                    """).update();
            return null;
        });
        Map<String, Object> fees4 = it.get(token, "/api/v1/me/fees?session=2090/2091").getBody();
        assertThat(fees4.get("clearsRegistration")).isEqualTo(true);
        ResponseEntity<Map> submitted = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", SESSION, "semester", 1));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        Map<String, Object> reg = (Map<String, Object>) submitted.getBody().get("registration");
        assertThat(reg.get("status")).isEqualTo("SUBMITTED");

        // the Head of Department approves through the desk that already exists; the form follows
        ResponseEntity<Map> approved = it.call(hod, HttpMethod.POST, "/api/v1/registration/course-registrations/" + reg.get("id") + "/approve", Map.of());
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        Map<String, Object> after = it.get(token, "/api/v1/me/registration?session=2090/2091&semester=1").getBody();
        assertThat(((Map<String, Object>) after.get("registration")).get("status")).isEqualTo("APPROVED");

        // results: registered, nothing published, the desk each sheet is on
        Map<String, Object> results = it.get(token, "/api/v1/me/results").getBody();
        List<Map<String, Object>> rows = (List<Map<String, Object>>) results.get("rows");
        assertThat(rows).hasSize(2);
        assertThat(rows.get(0).get("published")).isEqualTo(false);
        assertThat(results.get("cgpa")).isNull();
    }
}
