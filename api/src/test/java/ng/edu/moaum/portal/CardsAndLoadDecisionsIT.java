package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * V505, through the offices' doors: Exams & Records reads the examination cards withheld and why (an unpaid student's, not a
 * paid one's) and reminds those students, a lecturer cannot; the Academic Office opens the registrations below the minimum and
 * accepts one as it stands (it leaves the list) or returns one to the student, the Director of ICT cannot decide; the Director
 * reads how many registrations a raised minimum would leave short before saving it, and the students are told after. Each run files
 * everything under its own session. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CardsAndLoadDecisionsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String instrument = "BUR/IT/CARDS505";
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @AfterEach
    void clean() {
        it.db(() -> {
            if (session != null) {
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
                jdbc.sql("DELETE FROM registration.unit_minimum WHERE session = :s").param("s", session).update();
            }
            jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            return jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
        });
    }

    private UUID registered(UUID student, String status) {
        return it.db(() -> {
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                    VALUES (gen_random_uuid(), :st, :s, 1, 100, :status, CASE WHEN :status = 'DRAFT' THEN NULL ELSE now() END, CASE WHEN :status = 'APPROVED' THEN now() END) RETURNING id
                    """).param("st", student).param("s", session).param("status", status).query(UUID.class).single();
            jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                    SELECT :r, o.id, 6, 'CURRENT', CASE WHEN :status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END
                      FROM catalogue.offering o WHERE o.course_code = 'IXD 505' AND o.session = :s AND o.semester = 1 AND o.stream = 'REGULAR'
                    """).param("r", reg).param("s", session).param("status", status).update();
            return reg;
        });
    }

    @Test
    void cardsWithheldAreListedAndToldAndRegistrationsBelowTheMinimumAreDecidedAndANewMinimumIsCountedAndTold() {
        int y = it.freeYear(5000, 5400);
        session = y + "/" + (y + 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        int n = 1000 + new Random().nextInt(8999);
        UUID unpaid = it.student("ZZCWU" + n, "C00061", "MOAUM/ADM/" + yy + "/81" + n, "MOAUM/CWU/" + yy + "/" + n, 100);
        UUID paid = it.student("ZZCWP" + n, "C00061", "MOAUM/ADM/" + yy + "/82" + n, "MOAUM/CWP/" + yy + "/" + n, 100);
        UUID returned = it.student("ZZCWR" + n, "C00061", "MOAUM/ADM/" + yy + "/83" + n, "MOAUM/CWR/" + yy + "/" + n, 100);
        UUID drafting = it.student("ZZCWD" + n, "C00061", "MOAUM/ADM/" + yy + "/84" + n, "MOAUM/CWD/" + yy + "/" + n, 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET curriculum_version = 'CCMAS' WHERE id IN (:a, :b, :c, :d)").param("a", unpaid).param("b", paid).param("c", returned).param("d", drafting).update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES ('IXD 505', 'Cards Test Course', 6, 1, 100, :d, 'Core', 'LIVE') ON CONFLICT (code) DO NOTHING").param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'IXD 505', :s, 1) ON CONFLICT (course_code, session, semester, stream) DO NOTHING").param("s", session).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, 100, 'C00061')").param("s", session).update();
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
            for (UUID s : List.of(paid, returned)) {
                String ref = jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, 100000, 'School fees ' || :ses)").param("s", s).param("ses", session).query(String.class).single();
                jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the cards test')").param("r", ref).query(String.class).single();
            }
            return 0;
        });
        UUID regUnpaid = registered(unpaid, "APPROVED");
        UUID regPaid = registered(paid, "APPROVED");
        UUID regReturned = registered(returned, "APPROVED");
        UUID regDraft = registered(drafting, "DRAFT");

        // 1 · the cards withheld: the unpaid student's (not cleared), not the paid one's; Exams & Records reminds them, a lecturer cannot read it
        String records = ItSupport.token("records");
        String q = "/api/v1/registration/exam-cards/withheld?session=" + session + "&semester=1&refresh=true";
        assertThat(it.get(ItSupport.token("lecturer"), q).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> withheld = it.get(records, q).getBody();
        List<Map<String, Object>> rows = (List<Map<String, Object>>) withheld.get("rows");
        assertThat(rows).anySatisfy(r -> { assertThat(r.get("student_id")).isEqualTo(unpaid.toString()); assertThat(r.get("code")).isEqualTo("EXAM_CARD_NOT_PAID"); });
        assertThat(rows).noneSatisfy(r -> assertThat(r.get("student_id")).isEqualTo(paid.toString()));
        assertThat(((Number) ((Map<String, Object>) withheld.get("counts")).get("EXAM_CARD_NOT_PAID")).intValue()).isGreaterThanOrEqualTo(1);
        ResponseEntity<Map> reminded = it.call(records, HttpMethod.POST, "/api/v1/registration/exam-cards/withheld/remind", Map.of("session", session, "semester", 1, "code", "EXAM_CARD_NOT_PAID"));
        assertThat(reminded.getStatusCode().value()).as(String.valueOf(reminded.getBody())).isEqualTo(200);
        assertThat(((Number) reminded.getBody().get("told")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND template_key = 'EXAM_CARD_WITHHELD'").param("s", unpaid).query(Long.class).single()).isPositive();

        // 2 · below the minimum (6 of CCMAS 15): the figure, accepted as it stands (it leaves the list), returned to the student;
        // the Director of ICT does not decide
        String academic = ItSupport.token("academic");
        String base = "/api/v1/registration/approval";
        assertThat(((Number) it.get(academic, base + "/overview/below-minimum?session=" + session + "&semester=1").getBody().get("below_minimum")).intValue()).isEqualTo(3);
        List<Map<String, Object>> belowRows = (List<Map<String, Object>>) it.get(academic, base + "/overview/list?session=" + session + "&semester=1&kind=BELOW_MINIMUM").getBody().get("rows");
        assertThat(belowRows).extracting(r -> r.get("registration_id")).contains(regPaid.toString(), regReturned.toString()).doesNotContain(regDraft.toString());
        assertThat(it.call(ItSupport.token("ict"), HttpMethod.POST, base + "/registrations/" + regPaid + "/load-decision", Map.of("decision", "ACCEPTED", "reason", "Integration test: ICT tries")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> accepted = it.call(academic, HttpMethod.POST, base + "/registrations/" + regPaid + "/load-decision", Map.of("decision", "ACCEPTED", "reason", "Integration test: final-year load"));
        assertThat(accepted.getStatusCode().value()).as(String.valueOf(accepted.getBody())).isEqualTo(200);
        ResponseEntity<Map> back = it.call(academic, HttpMethod.POST, base + "/registrations/" + regReturned + "/load-decision", Map.of("decision", "RETURNED", "reason", "Integration test: add the core courses"));
        assertThat(back.getStatusCode().value()).as(String.valueOf(back.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT status FROM registration.course_registration WHERE id = :r").param("r", regReturned).query(String.class).single()).isEqualTo("RETURNED");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND template_key = 'REG_LOAD_RETURNED'").param("s", returned).query(Long.class).single()).isPositive();
        // the figure and its list hold only what can still be decided: the returned one is with the student
        assertThat(((Number) it.get(academic, base + "/overview/below-minimum?session=" + session + "&semester=1").getBody().get("below_minimum")).intValue()).isEqualTo(1);
        List<Map<String, Object>> after = (List<Map<String, Object>>) it.get(academic, base + "/overview/list?session=" + session + "&semester=1&kind=BELOW_MINIMUM").getBody().get("rows");
        assertThat(after).extracting(r -> r.get("registration_id")).containsExactly(regUnpaid.toString());

        // 3 · a raised minimum: counted before (the draft and the returned registration), told after
        String ict = ItSupport.token("ict");
        Map<String, Object> impact = it.get(ict, "/api/v1/registration/load/impact?curriculum=CCMAS&session=" + session + "&minUnits=16").getBody();
        assertThat(impact).as(String.valueOf(impact)).containsEntry("toTell", 2);
        Map<String, Object> body = new HashMap<>(Map.of("curriculum", "CCMAS", "session", session, "minUnits", 16, "reason", "Integration test: CCMAS sixteen for the session"));
        ResponseEntity<Map> raised = it.call(ict, HttpMethod.PUT, "/api/v1/registration/load/rules", body);
        assertThat(raised.getStatusCode().value()).as(String.valueOf(raised.getBody())).isEqualTo(200);
        assertThat(raised.getBody()).containsEntry("told", 2);
        assertThat(jdbc.sql("SELECT count(DISTINCT about_id) FROM platform.notice WHERE about_id IN (:a, :b) AND template_key = 'REG_MIN_UNITS_RAISED'")
                .param("a", drafting).param("b", returned).query(Long.class).single()).isEqualTo(2L);
    }
}
