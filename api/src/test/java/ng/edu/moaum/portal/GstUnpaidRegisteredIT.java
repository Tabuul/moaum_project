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
 * V691: the students with a GST/EPS course registered while the GST fee is unpaid, listed for the GST office and the Bursary with the
 * amount, and reminded. An invented 400 Level student has an EPS course on an approved registration and has not paid; another has none.
 * The GST office's list (the GST fee covers EPS) and the EPS office's hold the first with the fee owed, the dashboard counts them; the
 * Registry may not remind them and the EPS office may not send from the GST office's list; the Bursary's reminder tells the first and
 * passes over the second, and the same day again it is "reminded already today"; each sending is written down. The run files everything
 * under a session of its own. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class GstUnpaidRegisteredIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String bursar = ItSupport.token("bursar");
    String session;
    String surname;
    UUID unpaid;
    UUID none;
    String epsCode;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        int year = it.freeYear(2300, 2900, 0, 0);
        session = year + "/" + (year + 1);
        it.session(session, year);
        int n = it.freeDraw(1000, 10000, k -> List.of("MOAUM/ADM/14/" + String.format("%06d", k), "MOAUM/GUR/14/" + k, "MOAUM/ADM/14/" + String.format("%06d", k + 1),
                "MOAUM/GUR/14/" + (k + 1), "ZZGSTUR" + k + "U", "ZZGSTUR" + k + "N"));
        surname = "ZZGSTUR" + n;
        // two surnames: an invented student is found again by surname
        unpaid = it.student(surname + "U", "C00023", "MOAUM/ADM/14/" + String.format("%06d", n), "MOAUM/GUR/14/" + n, 400);
        none = it.student(surname + "N", "C00023", "MOAUM/ADM/14/" + String.format("%06d", n + 1), "MOAUM/GUR/14/" + (n + 1), 400);
        // an EPS code no earlier test or run holds
        int c = 700 + n % 199;
        for (int tries = 0; tries < 199; tries++, c = 700 + (c - 700 + 1) % 199) {
            if (jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :g").param("g", "EPS " + c).query(Long.class).single() == 0) break;
        }
        epsCode = "EPS " + c;
        it.db(() -> {
            jdbc.sql("UPDATE finance.gst_setting SET required_for_gst_eps = true, required_for_all = false, covers_eps = true WHERE id = 1").update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, general_office) VALUES (:g, 'Unpaid Entrepreneurship Studies', 2, 1, 200, :d, 'GST', 'LIVE', 'EPS')")
                    .param("g", epsCode).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:g, 'C00023', 200, 'GST')").param("g", epsCode).update();
            UUID offering = UUID.randomUUID();
            UUID reg = UUID.randomUUID();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:o, :g, :s, 1)").param("o", offering).param("g", epsCode).param("s", session).update();
            // registered before the fee was asked of a carry-over, approved, unpaid
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :st, :s, 1, 400, 'APPROVED', now(), now())")
                    .param("r", reg).param("st", unpaid).param("s", session).update();
            return jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, added_as) VALUES (:r, :o, 2, 'CARRYOVER', 'APPROVED', 'CARRY_OVER_DECLARED')")
                    .param("r", reg).param("o", offering).update();
        });
        ResponseEntity<Map> fee = it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", session, "amount", 5000));
        assertThat(fee.getStatusCode().value()).as(String.valueOf(fee.getBody())).isEqualTo(200);
    }

    private Map<String, Object> list(String token, String office) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/gst/" + office + "/students?session=" + session + "&eligibility=UNPAID_REGISTERED&refresh=true&q=" + surname);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private ResponseEntity<Map> remind(String token, String office) {
        return it.call(token, HttpMethod.POST, "/api/v1/gst/" + office + "/students/remind", Map.of("session", session, "students", List.of(unpaid.toString(), none.toString())));
    }

    @Test
    void theStudentsRegisteredWithoutPayingAreListedWithTheAmountAndReminded() {
        // the GST office's list (the fee covers EPS), the EPS office's, and the Bursary reading the GST office's: the one unpaid, ₦5,000 owed
        for (String[] who : List.of(new String[] {ItSupport.token("gst"), "GST"}, new String[] {ItSupport.token("eps"), "EPS"}, new String[] {bursar, "GST"})) {
            Map<String, Object> page = list(who[0], who[1]);
            assertThat(page).containsEntry("eligibility", "UNPAID_REGISTERED");
            List<Map<String, Object>> rows = (List<Map<String, Object>>) page.get("rows");
            assertThat(rows).extracting(r -> r.get("student_id")).containsExactly(unpaid.toString());
            assertThat(((Number) rows.get(0).get("owed")).intValue()).isEqualTo(5000);
            assertThat(((Number) page.get("owedTotal")).intValue()).isEqualTo(5000);
        }
        // the dashboard counts them, with what they owe
        Map<String, Object> totals = (Map<String, Object>) it.get(bursar, "/api/v1/gst/GST/dashboard?session=" + session).getBody().get("totals");
        assertThat(((Number) totals.get("registered_unpaid")).intValue()).isEqualTo(1);
        assertThat(((Number) totals.get("registered_unpaid_owed")).intValue()).isEqualTo(5000);

        // the Registry reads the list but does not remind; the EPS office does not send from the GST office's list
        assertThat(remind(ItSupport.token("registrar"), "GST").getStatusCode().value()).isEqualTo(403);
        assertThat(remind(ItSupport.token("eps"), "GST").getStatusCode().value()).isEqualTo(403);

        // the Bursary reminds: the unpaid student told, the other passed over
        ResponseEntity<Map> first = remind(bursar, "GST");
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) first.getBody().get("counts")).containsEntry("SENT", 1).containsEntry("NOT_UNPAID", 1);
        assertThat((List<Map<String, Object>>) first.getBody().get("rows")).filteredOn(r -> unpaid.toString().equals(String.valueOf(r.get("student"))))
                .singleElement().satisfies(r -> assertThat(r).containsEntry("outcome", "SENT").containsEntry("courses", epsCode));
        String body = jdbc.sql("SELECT body FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND template_key = 'GST_FEE_UNPAID_REGISTERED' AND channel = 'PORTAL'")
                .param("s", unpaid).query(String.class).single();
        assertThat(body).contains(epsCode).contains("NGN 5,000.00").contains(session);

        // the same day again: reminded already today, nothing sent twice
        ResponseEntity<Map> again = remind(ItSupport.token("gst"), "GST");
        assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) again.getBody().get("counts")).containsEntry("SENT", 0).containsEntry("ALREADY_TODAY", 1);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND template_key = 'GST_FEE_UNPAID_REGISTERED' AND channel = 'PORTAL'")
                .param("s", unpaid).query(Long.class).single()).isEqualTo(1L);

        // each sending written down
        assertThat(jdbc.sql("SELECT string_agg(sent_office || ':' || sent || '/' || already || '/' || skipped, ',' ORDER BY sent_at) FROM finance.gst_unpaid_reminder WHERE session = :s")
                .param("s", session).query(String.class).single()).isEqualTo("bursar:1/0/1,gst:0/1/1");
    }
}
