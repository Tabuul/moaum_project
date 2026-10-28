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
 * V690: a GST/EPS course added as a carry-over waits for the GST fee, through the student's own door. An invented 400 Level student
 * owes no GST fee; their programme binds an EPS course at 200 Level they have no record of. The GST page offers the fee for it
 * (carryPayable); added through ADD CARRY-OVER it is refused GST_PAYMENT_REQUIRED and nothing is registered; the fee paid and confirmed,
 * it is added as a carry-over they declared. The run files everything under a session of its own. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class GstDeclaredCarryOverIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String bursar = ItSupport.token("bursar");
    String session;
    UUID s;
    String student;
    String epsCode;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        int year = it.freeYear(2300, 2900, 0, 0);
        session = year + "/" + (year + 1);
        it.session(session, year);
        int n = it.freeDraw(1000, 10000, k -> List.of("MOAUM/ADM/13/" + String.format("%06d", k), "MOAUM/GDC/13/" + k, "ZZGSTDC" + k));
        s = it.student("ZZGSTDC" + n, "C00023", "MOAUM/ADM/13/" + String.format("%06d", n), "MOAUM/GDC/13/" + n, 400);
        student = TestTokens.token(s, List.of("student"));
        // an EPS code no earlier test or run holds
        int c = 700 + n % 199;
        for (int tries = 0; tries < 199; tries++, c = 700 + (c - 700 + 1) % 199) {
            if (jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :g").param("g", "EPS " + c).query(Long.class).single() == 0) break;
        }
        epsCode = "EPS " + c;
        it.db(() -> {
            jdbc.sql("UPDATE finance.gst_setting SET required_for_gst_eps = true, required_for_all = false, covers_eps = true WHERE id = 1").update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, general_office) VALUES (:g, 'Declared Entrepreneurship Studies', 2, 1, 200, :d, 'GST', 'LIVE', 'EPS')")
                    .param("g", epsCode).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:g, 'C00023', 200, 'GST')").param("g", epsCode).update();
            return jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :g, :s, 1)").param("g", epsCode).param("s", session).update();
        });
        ResponseEntity<Map> fee = it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", session, "amount", 5000));
        assertThat(fee.getStatusCode().value()).as(String.valueOf(fee.getBody())).isEqualTo(200);
    }

    private List<String> entries() {
        return jdbc.sql("""
                SELECT o.course_code || ':' || e.entry_type FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                  JOIN catalogue.offering o ON o.id = e.offering_id WHERE r.student_id = :s AND r.session = :ses AND r.semester = 1 ORDER BY o.course_code
                """).param("s", s).param("ses", session).query(String.class).list();
    }

    private Map<String, Object> add(String courseId) {
        ResponseEntity<Map> r = it.call(student, HttpMethod.POST, "/api/v1/me/registration/carry-overs", Map.of("session", session, "semester", 1, "courses", List.of(courseId)));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return ((List<Map<String, Object>>) r.getBody().get("results")).get(0);
    }

    @Test
    void anEpsCourseAddedAsACarryOverWaitsForTheGstFee() {
        // owes nothing, yet the GST page offers the fee for the EPS course they may add as a carry-over
        Map<String, Object> gst = it.get(student, "/api/v1/me/gst?session=" + session).getBody();
        assertThat((Map<String, Object>) gst.get("entitlement")).containsEntry("required", false);
        assertThat((List<Map<String, Object>>) gst.get("carryPayable")).extracting(x -> x.get("course_code")).contains(epsCode);

        // added through ADD CARRY-OVER: refused until the fee is paid, nothing registered
        Map<String, Object> listed = it.get(student, u -> u.path("/api/v1/me/registration/carry-overs").queryParam("session", session).queryParam("semester", 1).build()).getBody();
        String courseId = String.valueOf(((List<Map<String, Object>>) listed.get("rows")).stream().filter(r -> epsCode.equals(r.get("course_code"))).findFirst().orElseThrow().get("course_id"));
        Map<String, Object> refused = add(courseId);
        assertThat(refused).containsEntry("added", false).containsEntry("code", "GST_PAYMENT_REQUIRED");
        assertThat(String.valueOf(refused.get("message"))).contains("GST fee").contains("EPS courses");
        assertThat(entries()).doesNotContain(epsCode + ":CARRYOVER");

        // the fee paid and confirmed: added as a carry-over
        ResponseEntity<Map> ref = it.call(student, HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", session));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        String reference = String.valueOf(ref.getBody().get("reference"));
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", reference).query(String.class).single());
        assertThat(add(courseId)).containsEntry("added", true);
        assertThat(entries()).contains(epsCode + ":CARRYOVER");
    }
}
