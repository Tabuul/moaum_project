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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V501: the examination card — the University's full examination permit — has its own rule beside the GST & EPS permit's: a
 * student whose registration is approved and who has paid has the card, with every course registered, departmental, GST and EPS
 * alike; an unpaid student's card is withheld and its code is not signed; a registration not yet approved has no card. Each run
 * files everything under its own session. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ExamCardIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String instrument = "BUR/IT/CARD501";
    /** the run's own session: its fee line applies to every student at the level, so it is taken away after the test */
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @AfterEach
    void clean() {
        it.db(() -> {
            if (session != null) jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
            jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            return jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
        });
    }

    private void registered(UUID student, String status, String... courses) {
        it.db(() -> {
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                    VALUES (gen_random_uuid(), :st, :s, 1, 100, :status, now(), CASE WHEN :status = 'APPROVED' THEN now() END) RETURNING id
                    """).param("st", student).param("s", session).param("status", status).query(UUID.class).single();
            for (String c : courses) {
                jdbc.sql("""
                        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                        SELECT :r, o.id, c.units, 'CURRENT', CASE WHEN :status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END
                          FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
                         WHERE o.course_code = :c AND o.session = :s AND o.semester = 1 AND o.stream = 'REGULAR'
                        """).param("r", reg).param("c", c).param("s", session).param("status", status).update();
            }
            return reg;
        });
    }

    @Test
    void theExaminationCardCarriesEveryRegisteredCourseForEveryStudentWhoRegisteredAndPaid() {
        int y = it.freeYear(4000, 4500);
        session = y + "/" + (y + 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        int n = 1000 + new Random().nextInt(8999);
        it.db(() -> {
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
                        ('GST 487', 'Card Use of English', 2, 1, 100, :d, 'GST', 'LIVE'), ('EPS 487', 'Card Entrepreneurship', 2, 1, 100, :d, 'GST', 'LIVE'),
                        ('ITE 487', 'Card Departmental Course', 3, 1, 100, :d, 'Core', 'LIVE')
                    ON CONFLICT (code) DO NOTHING
                    """).param("d", dept).update();
            jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester)
                    SELECT gen_random_uuid(), c, :s, 1 FROM unnest(ARRAY['GST 487', 'EPS 487', 'ITE 487']) c
                    ON CONFLICT (course_code, session, semester, stream) DO NOTHING
                    """).param("s", session).update();
            // the session's school fees stated, and a clearance scheme in force where none is: the examination cleared on payment
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, 100, 'C00061')").param("s", session).update();
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           :i, 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).param("i", instrument).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = :i ON CONFLICT DO NOTHING").param("i", instrument).update();
            return jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED' ELSE 'INSTALMENT_1' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = :i ON CONFLICT DO NOTHING
                    """).param("i", instrument).update();
        });
        UUID a = it.student("ZZCARDA" + n, "C00061", "MOAUM/ADM/" + yy + "/61" + n, "MOAUM/ICA/" + yy + "/" + n, 100);
        UUID b = it.student("ZZCARDB" + n, "C00061", "MOAUM/ADM/" + yy + "/62" + n, "MOAUM/ICB/" + yy + "/" + n, 100);
        registered(a, "APPROVED", "ITE 487", "GST 487", "EPS 487");
        registered(b, "SUBMITTED", "ITE 487");
        String ta = TestTokens.token(a, List.of("student"));
        String tb = TestTokens.token(b, List.of("student"));
        String q = "?session=" + session + "&semester=1";

        // registered and approved but not paid: the card is withheld (V567: not paid), and its code is not signed
        Map<String, Object> unpaid = it.get(ta, "/api/v1/me/exam-card" + q).getBody();
        assertThat(unpaid).as(String.valueOf(unpaid)).containsEntry("available", false).containsEntry("code", "EXAM_CARD_NOT_PAID");
        ResponseEntity<Map> noCode = it.get(ta, "/api/v1/me/check-code?kind=EXAM&session=" + session + "&semester=1");
        assertThat(noCode.getStatusCode().value()).isEqualTo(422);
        assertThat(noCode.getBody().get("code")).isEqualTo("EXAM_CARD_NOT_PAID");

        // paid in full: the card is available, with every registered course — the departmental course, GST and EPS alike
        it.db(() -> {
            String ref = jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, 100000, 'School fees ' || :ses)").param("s", a).param("ses", session).query(String.class).single();
            return jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the exam card test')").param("r", ref).query(String.class).single();
        });
        Map<String, Object> card = it.get(ta, "/api/v1/me/exam-card" + q).getBody();
        assertThat(card).as(String.valueOf(card)).containsEntry("available", true).containsEntry("count", 3).containsEntry("units", 7).containsEntry("gstEpsCount", 2);
        assertThat(((List<Map<String, Object>>) card.get("courses")).stream().map(c -> c.get("course_code")))
                .containsExactlyInAnyOrder("ITE 487", "GST 487", "EPS 487");
        // the GST & EPS permit beside it carries only the GST and EPS courses — two documents, never one for the other
        assertThat(jdbc.sql("SELECT jsonb_array_length(registration.gst_eps_permit_state(:s, :ses, 1)->'courses')").param("s", a).param("ses", session)
                .query(Integer.class).single()).isEqualTo(2);
        ResponseEntity<Map> code = it.get(ta, "/api/v1/me/check-code?kind=EXAM&session=" + session + "&semester=1");
        assertThat(code.getStatusCode().value()).as(String.valueOf(code.getBody())).isEqualTo(200);
        assertThat(((Map<String, Object>) it.get(ta, "/api/v1/me/exam-card" + q).getBody().get("issued")).get("times")).isEqualTo(1);

        // V567: a registration submitted and not yet approved waits only for the payment — paid, the card is the student's at once
        Map<String, Object> waiting = it.get(tb, "/api/v1/me/exam-card" + q).getBody();
        assertThat(waiting).containsEntry("available", false).containsEntry("code", "EXAM_CARD_NOT_PAID");
        it.db(() -> {
            String ref = jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, 50000, 'School fees ' || :ses)").param("s", b).param("ses", session).query(String.class).single();
            return jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the exam card test')").param("r", ref).query(String.class).single();
        });
        assertThat(it.get(tb, "/api/v1/me/exam-card" + q).getBody()).containsEntry("available", true).containsEntry("count", 1);
        ResponseEntity<Map> bCode = it.get(tb, "/api/v1/me/check-code?kind=EXAM&session=" + session + "&semester=1");
        assertThat(bCode.getStatusCode().value()).isEqualTo(200);
        // V567 at the examination hall: that card verifies as valid, with its course and the school fees paid
        Map<String, Object> hall = it.anon(HttpMethod.GET, "/api/v1/verify/exam?matric=" + bCode.getBody().get("number") + "&session=" + session
                + "&semester=1&c=" + bCode.getBody().get("code"), null).getBody();
        assertThat(hall).as(String.valueOf(hall)).containsEntry("genuine", true).containsEntry("status", "VALID").containsEntry("cleared", true);
        assertThat((List<?>) hall.get("courses")).hasSize(1);
    }
}
