package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
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
 * V664 through the API: a spillover student (at 500 Level on a four-year programme, by the level basis) with first- and second-semester
 * spillover lines (₦70,000, ₦60,000) registers and pays the first semester; the second semester is held to its own fee — a registration
 * with no course is not submitted (REG_NO_COURSES); one approved empty, as the hole left it, takes no course in add and drop until the
 * second semester is paid (REG_SEMESTER_FEES_DUE with the figures); a draft with its courses is refused with the figures, part paid it
 * reads PART_PAID with exactly what is left, paid it is submitted and a further course goes on in add and drop; a second press adds and
 * submits nothing twice; the Fees page reads each semester's own fee, paid, outstanding and state. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class SpilloverSemesterRegistrationIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String session;
    String tag;
    String bursar;
    String prog4;
    String basisBefore;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(2300, 2900);
        session = y + "/" + (y + 1);
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("MOAUM/ADM/16/" + k + "64", "MOAUM/SPR/16/" + k + "4", "ZZSPR" + k)));
        bursar = TestTokens.token(it.person("ZZSPR-BUR-" + tag, "ZZSPRBUR"), List.of("bursar"));
        it.session(session, y);
        prog4 = jdbc.sql("""
                SELECT p.code FROM ref.programme p
                 WHERE NOT coalesce(p.archived, false) AND coalesce(p.category, '') <> 'POST GRADUATE' AND finance.final_level(p.code) = 400
                   AND p.faculty_code NOT IN (SELECT faculty_code FROM finance.faculty_fee_source UNION SELECT source_faculty_code FROM finance.faculty_fee_source)
                 ORDER BY p.code DESC LIMIT 1
                """).query(String.class).single();
        basisBefore = jdbc.sql("SELECT spillover_basis FROM finance.fee_setting WHERE id = 1").query(String.class).optional().orElse("LEVEL");
        it.db(() -> {
            jdbc.sql("UPDATE finance.fee_setting SET spillover_basis = 'LEVEL' WHERE id = 1").update();
            jdbc.sql("""
                    INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), :s, 1, 'OPEN'), (gen_random_uuid(), :s, 2, 'OPEN')
                    ON CONFLICT (session, number) DO UPDATE SET state = excluded.state
                    """).param("s", session).update();
            // a clearance scheme in force where none is (as SpilloverSemesterFeesIT)
            String instrument = "Integration test: SpilloverSemesterRegistrationIT " + tag;
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
            // 500-Level courses of the programme: two in the first semester, three in the second (12 + 6 units meet the minimum load)
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", prog4).query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    SELECT x.code, x.title, x.units, x.sem, 500, :d, 'Core', 'LIVE'
                      FROM (VALUES ('ZQS 511', 'Spillover Registration One', 12, 1), ('ZQS 512', 'Spillover Registration Two', 6, 1),
                                   ('ZQS 521', 'Spillover Registration Three', 12, 2), ('ZQS 522', 'Spillover Registration Four', 6, 2),
                                   ('ZQS 523', 'Spillover Registration Five', 2, 2)) x(code, title, units, sem)
                     WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = x.code)
                    """).param("d", dept).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis)
                    SELECT c, :p, 500, 'Core' FROM unnest(ARRAY['ZQS 511', 'ZQS 512', 'ZQS 521', 'ZQS 522', 'ZQS 523']) c ON CONFLICT DO NOTHING
                    """).param("p", prog4).update();
            jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester)
                    VALUES (gen_random_uuid(), 'ZQS 511', :s, 1), (gen_random_uuid(), 'ZQS 512', :s, 1),
                           (gen_random_uuid(), 'ZQS 521', :s, 2), (gen_random_uuid(), 'ZQS 522', :s, 2), (gen_random_uuid(), 'ZQS 523', :s, 2)
                    ON CONFLICT DO NOTHING
                    """).param("s", session).update();
            return null;
        });
    }

    @AfterEach
    void putBack() {
        if (it != null) it.db(() -> {
            jdbc.sql("UPDATE finance.fee_setting SET spillover_basis = :b WHERE id = 1").param("b", basisBefore).update();
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
            return null;
        });
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private UUID offering(String code, int semester) {
        return jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = :sem AND stream = 'REGULAR'")
                .param("c", code).param("s", session).param("sem", semester).query(UUID.class).single();
    }

    /** a school-fees reference for the amount, confirmed by the Bursary */
    private void pay(String token, int amount) {
        Map<String, Object> ref = ok(it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", amount)));
        ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "spillover registration test")));
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> semester(String token, int n) {
        Map<String, Object> fees = ok(it.get(token, "/api/v1/me/fees?session=" + session));
        Map<String, Object> panel = (Map<String, Object>) fees.get("spillover");
        assertThat(panel).as("the spillover panel").isNotNull();
        return ((List<Map<String, Object>>) panel.get("semesters")).stream().filter(s -> ((Number) s.get("semester")).intValue() == n).findFirst().orElseThrow();
    }

    private static int num(Object v) {
        return ((Number) v).intValue();
    }

    private UUID registration(UUID student, int semester) {
        return jdbc.sql("SELECT id FROM registration.course_registration WHERE student_id = :s AND session = :ses AND semester = :sem")
                .param("s", student).param("ses", session).param("sem", semester).query(UUID.class).single();
    }

    @Test
    void aSpilloverStudentsSecondSemesterWaitsForItsOwnFee() {
        UUID sp = it.student("ZZSPR" + tag, prog4, "MOAUM/ADM/16/" + tag + "64", "MOAUM/SPR/16/" + tag + "4", 500);
        String token = TestTokens.token(sp, List.of("student"));
        List<Map<String, Object>> rows = List.of(
                Map.of("programmeCode", prog4, "level", "400", "spillover", "SP1", "semester", "1", "amount", "70000"),
                Map.of("programmeCode", prog4, "level", "400", "spillover", "SP1", "semester", "2", "amount", "60000"));
        assertThat(num(ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/fee-lines", Map.of("rows", rows))).get("added"))).isEqualTo(2);

        // the first semester: chosen, paid (₦70,000), submitted
        ok(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", List.of(offering("ZQS 511", 1), offering("ZQS 512", 1)))));
        pay(token, 70000);
        ok(it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1)));
        assertThat(semester(token, 1)).containsEntry("status", "PAID");
        Map<String, Object> second = semester(token, 2);
        assertThat(second).containsEntry("status", "NOTHING_OWED").containsEntry("registered", false);
        assertThat(num(second.get("fee"))).isEqualTo(60000);

        // a second-semester registration with no course on it is not submitted
        UUID reg2 = UUID.randomUUID();
        it.db(() -> jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status) VALUES (:id, :s, :ses, 2, 500, 'DRAFT')")
                .param("id", reg2).param("s", sp).param("ses", session).update());
        ResponseEntity<Map> empty = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 2));
        assertThat(empty.getStatusCode().value()).as(String.valueOf(empty.getBody())).isEqualTo(422);
        assertThat(empty.getBody()).containsEntry("code", "REG_NO_COURSES");

        // one approved empty, as the hole left it: a course added in add and drop waits for the second semester's own fee
        it.db(() -> jdbc.sql("UPDATE registration.course_registration SET status = 'APPROVED', submitted_at = now(), approved_at = now() WHERE id = :id").param("id", reg2).update());
        ResponseEntity<Map> held = it.call(token, HttpMethod.POST, "/api/v1/me/registration/add", Map.of("session", session, "semester", 2, "offering", offering("ZQS 521", 2)));
        assertThat(held.getStatusCode().value()).as(String.valueOf(held.getBody())).isEqualTo(422);
        assertThat(held.getBody()).containsEntry("code", "REG_SEMESTER_FEES_DUE");
        assertThat(String.valueOf(held.getBody())).contains("₦60,000.00 outstanding (₦130,000.00 due up to the second semester, ₦70,000.00 paid)")
                .contains("A payment for another semester does not cover it");
        assertThat(jdbc.sql("SELECT count(*) FROM registration.entry WHERE registration_id = :r").param("r", reg2).query(Long.class).single()).isZero();

        // as a draft its courses go on; the submission is refused with the figures
        it.db(() -> jdbc.sql("UPDATE registration.course_registration SET status = 'DRAFT', submitted_at = NULL, approved_at = NULL WHERE id = :id").param("id", reg2).update());
        ok(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 2, "offerings", List.of(offering("ZQS 521", 2), offering("ZQS 522", 2)))));
        second = semester(token, 2);
        assertThat(second).containsEntry("status", "PAYMENT_REQUIRED").containsEntry("registered", true).containsEntry("cleared", false);
        assertThat(num(second.get("owed"))).isEqualTo(60000);
        assertThat(num(second.get("paid"))).isZero();
        assertThat(num(second.get("outstanding"))).isEqualTo(60000);
        assertThat(num(second.get("toClear"))).isEqualTo(60000);
        assertThat(semester(token, 1)).containsEntry("status", "PAID");
        ResponseEntity<Map> refused = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 2));
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);
        assertThat(refused.getBody()).containsEntry("code", "REG_SEMESTER_FEES_DUE");
        assertThat(String.valueOf(refused.getBody())).containsIgnoringCase("second semester school fees").contains("₦60,000.00 outstanding")
                .contains("Second semester registration requires payment of the second semester spillover fee");

        // part paid: exactly what is left
        pay(token, 30000);
        second = semester(token, 2);
        assertThat(second).containsEntry("status", "PART_PAID");
        assertThat(num(second.get("paid"))).isEqualTo(30000);
        assertThat(num(second.get("outstanding"))).isEqualTo(30000);
        ResponseEntity<Map> part = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 2));
        assertThat(part.getStatusCode().value()).as(String.valueOf(part.getBody())).isEqualTo(422);
        assertThat(String.valueOf(part.getBody())).contains("₦30,000.00 outstanding (₦130,000.00 due up to the second semester, ₦100,000.00 paid)");

        // paid: submitted; in add and drop a further course goes on at once; a second press adds and submits nothing twice
        pay(token, 30000);
        assertThat(semester(token, 2)).containsEntry("status", "PAID").containsEntry("cleared", true);
        ok(it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 2)));
        String status = jdbc.sql("SELECT status FROM registration.course_registration WHERE id = :id").param("id", reg2).query(String.class).single();
        assertThat(status).isIn("SUBMITTED", "APPROVED");
        it.db(() -> jdbc.sql("UPDATE registration.course_registration SET status = 'APPROVED', approved_at = now() WHERE id = :id").param("id", reg2).update());
        ok(it.call(token, HttpMethod.POST, "/api/v1/me/registration/add", Map.of("session", session, "semester", 2, "offering", offering("ZQS 523", 2))));
        ResponseEntity<Map> again = it.call(token, HttpMethod.POST, "/api/v1/me/registration/add", Map.of("session", session, "semester", 2, "offering", offering("ZQS 523", 2)));
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(again.getBody())).contains("REG_ALREADY_ADDED");
        ok(it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 2)));
        assertThat(jdbc.sql("SELECT count(*) FROM registration.entry WHERE registration_id = :r AND status NOT IN ('DROPPED', 'WITHDRAWN')").param("r", reg2).query(Long.class).single()).isEqualTo(3);
        assertThat(registration(sp, 2)).isEqualTo(reg2);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.registrations_without_fees(:ses) WHERE student_id = :s").param("ses", session).param("s", sp).query(Long.class).single()).isZero();
    }
}
