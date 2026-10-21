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
 * A GST or EPS carry-over waits for the GST fee (V512), on the student's own door: a 400-level student who failed a GST course owes it
 * as a carry-over and owes the GST fee — the course is on the registration screen, held, and not put on the draft when the student
 * saves their other courses; registering it is refused with GST_PAYMENT_REQUIRED, and the attempt, the hold and the payment required
 * stay on the GST/EPS registration log though the request is refused; the GST payment confirmed, the student registers it from the
 * same screen — no ICT Support — under carry-over, the log saying so. The run files everything under sessions of its own.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class GstCarryOverIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String bursar = ItSupport.token("bursar");
    /** the run's own two sessions, which no test has opened (ItSupport.freeYear) */
    int year;
    String before;
    String session;
    UUID s;
    String student;
    String gstCode;
    UUID gstOffering;
    UUID coreOffering;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        year = it.freeYear(2300, 2900, 1, 0);
        before = (year - 1) + "/" + year;
        session = year + "/" + (year + 1);
        it.session(before, year - 1);
        it.session(session, year);
        int n = it.freeDraw(1000, 10000, k -> List.of("MOAUM/ADM/12/" + String.format("%06d", k), "MOAUM/GCO/12/" + k, "ZZGSTCO" + k));
        s = it.student("ZZGSTCO" + n, "C00023", "MOAUM/ADM/12/" + String.format("%06d", n), "MOAUM/GCO/12/" + n, 400);
        student = TestTokens.token(s, List.of("student"));
        // a GST code no earlier test or run holds
        int c = 500 + n % 199;
        for (int tries = 0; tries < 199; tries++, c = 500 + (c - 500 + 1) % 199) {
            if (jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :g").param("g", "GST " + c).query(Long.class).single() == 0) break;
        }
        gstCode = "GST " + c;
        String coreCode = "ITG " + c;
        UUID earlier = UUID.randomUUID();
        gstOffering = UUID.randomUUID();
        coreOffering = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("UPDATE finance.gst_setting SET required_for_gst_eps = true, required_for_all = false, covers_eps = true WHERE id = 1").update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, general_office) VALUES (:g, 'Carried General Studies', 2, 1, 300, :d, 'GST', 'LIVE', 'GST'), (:c, 'Final-year Core', 3, 1, 400, :d, 'Core', 'LIVE', NULL)")
                    .param("g", gstCode).param("c", coreCode).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:g, 'C00023', 300, 'GST'), (:c, 'C00023', 400, 'Core')")
                    .param("g", gstCode).param("c", coreCode).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:e, :g, :b, 1), (:o, :g, :s, 1), (:k, :c, :s, 1)")
                    .param("e", earlier).param("g", gstCode).param("b", before).param("o", gstOffering).param("k", coreOffering).param("c", coreCode).param("s", session).update();
            // last session: the GST course failed, the result published
            UUID reg = UUID.randomUUID();
            UUID sheet = UUID.randomUUID();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (:r, :s, :b, 1, 300, 'APPROVED', now())")
                    .param("r", reg).param("s", s).param("b", before).update();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 2, 'APPROVED')").param("r", reg).param("o", earlier).update();
            jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at, submitted_at) VALUES (:id, :o, 'PUBLISHED', 'SEN/IT/512', now(), now())")
                    .param("id", sheet).param("o", earlier).update();
            return jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) VALUES (:sh, :s, 10, 15, 'GRADED')").param("sh", sheet).param("s", s).update();
        });
        ResponseEntity<Map> fee = it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", session, "amount", 5000));
        assertThat(fee.getStatusCode().value()).as(String.valueOf(fee.getBody())).isEqualTo(200);
    }

    private Map<String, Object> view() {
        ResponseEntity<Map> r = it.get(student, "/api/v1/me/registration?session=" + session + "&semester=1");
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private List<String> entries() {
        return jdbc.sql("""
                SELECT o.course_code || ':' || e.entry_type FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                  JOIN catalogue.offering o ON o.id = e.offering_id WHERE r.student_id = :s AND r.session = :ses AND r.semester = 1 ORDER BY o.course_code
                """).param("s", s).param("ses", session).query(String.class).list();
    }

    private List<String> events() {
        return jdbc.sql("SELECT event FROM registration.gst_course_event WHERE student_id = :s ORDER BY event").param("s", s).query(String.class).list();
    }

    @Test
    void aGstCarryOverWaitsForTheFeeAndIsRegisteredOnceItIsPaid() {
        // the carry-over is on the screen, under carry-over, held on the GST fee
        Map<String, Object> carry = ((List<Map<String, Object>>) view().get("menu")).stream()
                .filter(m -> gstCode.equals(m.get("course_code"))).findFirst().orElseThrow();
        assertThat(carry).containsEntry("carryover", true).containsEntry("gstLocked", true);

        // the student's other course is saved; the carry-over is not put on the draft unpaid
        ResponseEntity<Map> saved = it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of(coreOffering)));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat(entries()).containsExactly("ITG " + gstCode.substring(4) + ":CURRENT");

        // registering it is refused, and the attempt, the hold and the payment required stay on the log though the request is refused
        ResponseEntity<Map> refused = it.call(student, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "offering", gstOffering));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody()).containsEntry("code", "GST_PAYMENT_REQUIRED");
        assertThat(String.valueOf(refused.getBody().get("detail"))).contains("carry-over");
        assertThat(entries()).doesNotContain(gstCode + ":CARRYOVER");
        assertThat(events()).containsExactly("GST_CARRY_OVER_REGISTRATION_ATTEMPTED", "GST_CARRY_OVER_REGISTRATION_BLOCKED", "GST_PAYMENT_REQUIRED_FOR_REGISTRATION");

        // the GST fee paid on the one ledger and confirmed: the student registers the carry-over from the same screen
        ResponseEntity<Map> ref = it.call(student, HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", session));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        String reference = String.valueOf(ref.getBody().get("reference"));
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", reference).query(String.class).single());
        Map<String, Object> paid = ((List<Map<String, Object>>) view().get("menu")).stream()
                .filter(m -> gstCode.equals(m.get("course_code"))).findFirst().orElseThrow();
        assertThat(paid.get("gstLocked")).isEqualTo(false);
        ResponseEntity<Map> added = it.call(student, HttpMethod.POST, "/api/v1/me/registration/courses", Map.of("session", session, "semester", 1, "offering", gstOffering));
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
        assertThat(entries()).contains(gstCode + ":CARRYOVER");
        Map<String, Object> entry = ((List<Map<String, Object>>) ((Map<String, Object>) added.getBody().get("registration")).get("entries")).stream()
                .filter(e -> gstCode.equals(e.get("courseCode"))).findFirst().orElseThrow();
        assertThat(entry).containsEntry("category", "CARRY_OVER").containsEntry("kind", "GST");
        assertThat(events()).contains("GST_CARRY_OVER_REGISTERED", "GST_PAYMENT_VERIFIED");
    }
}
