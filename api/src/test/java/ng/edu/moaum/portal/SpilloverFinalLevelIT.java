package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
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
 * V637 through the API: an SP1 student at a four-year programme's final level (400, as the level desk sets SP1), under the Bursary's
 * LEVEL basis, is billed as spillover — nothing owed before a course is registered; a course registered in the first semester alone
 * makes the first semester's spillover fee due (70,000), never the 400 Level session (270,000) nor the second semester's; the Fees view
 * shows the SP year, each semester's fee and which is registered; the reference names the spillover and the semester; the Bursary's list
 * names the student as owing; the School Fees Report counts the student apart as spillover; a student at 400 in a normal year owes the
 * full session as before. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class SpilloverFinalLevelIT {

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
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("MOAUM/ADM/17/" + k + "71", "MOAUM/ADM/17/" + k + "72", "MOAUM/SFL/17/" + k + "1", "MOAUM/SFL/17/" + k + "2", "ZZSFL" + k, "ZZSFLN" + k)));
        bursar = TestTokens.token(it.person("ZZSFL-BUR-" + tag, "ZZSFLBUR"), List.of("bursar"));
        it.session(session, y);
        prog4 = jdbc.sql("""
                SELECT p.code FROM ref.programme p
                 WHERE NOT coalesce(p.archived, false) AND coalesce(p.category, '') <> 'POST GRADUATE' AND finance.final_level(p.code) = 400
                   AND p.faculty_code NOT IN (SELECT faculty_code FROM finance.faculty_fee_source UNION SELECT source_faculty_code FROM finance.faculty_fee_source)
                 ORDER BY p.code DESC LIMIT 1
                """).query(String.class).single();
        basisBefore = jdbc.sql("SELECT spillover_basis FROM finance.fee_setting WHERE id = 1").query(String.class).optional().orElse("LEVEL");
        it.db(() -> {
            // the level basis (V571), as the Bursary has it
            jdbc.sql("UPDATE finance.fee_setting SET spillover_basis = 'LEVEL' WHERE id = 1").update();
            jdbc.sql("""
                    INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), :s, 1, 'OPEN'), (gen_random_uuid(), :s, 2, 'OPEN')
                    ON CONFLICT (session, number) DO UPDATE SET state = excluded.state
                    """).param("s", session).update();
            String instrument = "Integration test: SpilloverFinalLevelIT " + tag;
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
            // two 400-Level courses of the programme offered in the session's first semester
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", prog4).query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    SELECT x.code, x.title, x.units, 1, 400, :d, 'Core', 'LIVE'
                      FROM (VALUES ('ZZF 431', 'Spillover Final Level One', 12), ('ZZF 432', 'Spillover Final Level Two', 6)) x(code, title, units)
                     WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = x.code)
                    """).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('ZZF 431', :p, 400, 'Core'), ('ZZF 432', :p, 400, 'Core') ON CONFLICT DO NOTHING").param("p", prog4).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZF 431', :s, 1), (gen_random_uuid(), 'ZZF 432', :s, 1) ON CONFLICT DO NOTHING").param("s", session).update();
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

    private BigDecimal due(UUID student) {
        return jdbc.sql("SELECT due FROM finance.position(:s, :ses)").param("s", student).param("ses", session).query(BigDecimal.class).single();
    }

    /** the cohort engine's reading as the level desk leaves an SP1 student: at the final level, one year past the programme's length */
    private void sp1(UUID student) {
        it.db(() -> jdbc.sql("UPDATE people.academic_position SET spillover_state = 'SPILLOVER_YEAR_1', spillover_years = 1 WHERE student_id = :s").param("s", student).update());
    }

    @SuppressWarnings("unchecked")
    @Test
    void anSp1StudentAtTheFinalLevelPaysTheFirstSemestersSpilloverFeeAloneWhenRegisteredInItAlone() {
        UUID sp = it.student("ZZSFL" + tag, prog4, "MOAUM/ADM/17/" + tag + "71", "MOAUM/SFL/17/" + tag + "1", 400);
        UUID normal = it.student("ZZSFLN" + tag, prog4, "MOAUM/ADM/17/" + tag + "72", "MOAUM/SFL/17/" + tag + "2", 400);
        String token = TestTokens.token(sp, List.of("student"));
        // the other student in their normal final year, whatever the engine made of a test record's dates
        it.db(() -> jdbc.sql("UPDATE people.academic_position SET spillover_state = 'NORMAL', spillover_years = 0 WHERE student_id = :s").param("s", normal).update());
        List<Map<String, Object>> rows = List.of(
                Map.of("programmeCode", prog4, "level", "400", "spillover", "SP1", "semester", "1", "amount", "70000"),
                Map.of("programmeCode", prog4, "level", "400", "spillover", "SP1", "semester", "2", "amount", "60000"),
                Map.of("programmeCode", prog4, "level", "400", "entryMode", "UTME", "semester", "1", "amount", "150000"),
                Map.of("programmeCode", prog4, "level", "400", "entryMode", "UTME", "semester", "2", "amount", "120000"));
        assertThat(((Number) ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/fee-lines", Map.of("rows", rows))).get("added")).intValue()).isEqualTo(4);

        // SP1 at 400: in spillover, nothing owed before a course is registered; the panel names SP1 and each semester's fee
        sp1(sp);
        assertThat(jdbc.sql("SELECT finance.is_spillover(:s)").param("s", sp).query(Boolean.class).single()).isTrue();
        assertThat(due(sp)).isEqualByComparingTo("0");
        Map<String, Object> fees = ok(it.get(token, "/api/v1/me/fees?session=" + session));
        Map<String, Object> panel = (Map<String, Object>) fees.get("spillover");
        assertThat(panel).as(String.valueOf(fees)).isNotNull().containsEntry("label", "SP1");
        List<Map<String, Object>> sems = (List<Map<String, Object>>) panel.get("semesters");
        assertThat(((Number) sems.get(0).get("fee")).intValue()).isEqualTo(70000);
        assertThat(((Number) sems.get(1).get("fee")).intValue()).isEqualTo(60000);
        assertThat(sems.get(0)).containsEntry("registered", false);

        // a course registered in the first semester alone: the first semester's spillover fee, never the session's 270,000
        Map<String, Object> view = ok(it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1"));
        List<Map<String, Object>> menu = (List<Map<String, Object>>) view.get("menu");
        List<UUID> offerings = menu.stream().filter(m -> String.valueOf(m.get("course_code")).startsWith("ZZF 43")).map(m -> UUID.fromString(String.valueOf(m.get("offering_id")))).toList();
        assertThat(offerings).hasSize(2);
        sp1(sp);
        ok(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", offerings)));
        sp1(sp);
        assertThat(due(sp)).isEqualByComparingTo("70000");
        fees = ok(it.get(token, "/api/v1/me/fees?session=" + session));
        assertThat(((Number) fees.get("due")).intValue()).isEqualTo(70000);
        panel = (Map<String, Object>) fees.get("spillover");
        sems = (List<Map<String, Object>>) panel.get("semesters");
        assertThat(sems.get(0)).containsEntry("registered", true);
        assertThat(sems.get(1)).containsEntry("registered", false);

        // the reference names the spillover year and the semester; it is still school fees to every reader
        Map<String, Object> ref = ok(it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 70000)));
        String purpose = jdbc.sql("SELECT purpose FROM finance.payment_reference WHERE reference = :r").param("r", ref.get("reference")).query(String.class).single();
        assertThat(purpose).isEqualTo("School fees " + session + " · spillover (SP1) · first semester");

        // the Bursary's list names the student as owing; the School Fees Report counts them apart
        Map<String, Object> list = ok(it.get(bursar, "/api/v1/finance/spillover?session=" + session + "&q=ZZSFL" + tag));
        List<Map<String, Object>> listed = (List<Map<String, Object>>) list.get("rows");
        assertThat(listed).anySatisfy(r -> {
            assertThat(r).containsEntry("student_id", sp.toString()).containsEntry("state", "OWES").containsEntry("spill_year", 1);
            assertThat(((Number) r.get("owing")).intValue()).isEqualTo(70000);
        });
        assertThat(listed).noneSatisfy(r -> assertThat(r).containsEntry("student_id", normal.toString()));
        Map<String, Object> report = ok(it.get(bursar, "/api/v1/finance/fee-report?session=" + session));
        assertThat(((Number) ((Map<String, Object>) report.get("total")).get("spill_students")).intValue()).isGreaterThanOrEqualTo(1);

        // a student at 400 in a normal year owes the whole session as before
        it.db(() -> jdbc.sql("UPDATE people.academic_position SET spillover_state = 'NORMAL', spillover_years = 0 WHERE student_id = :s").param("s", normal).update());
        assertThat(due(normal)).isEqualByComparingTo("270000");
        assertThat(ok(it.get(TestTokens.token(normal, List.of("student")), "/api/v1/me/fees?session=" + session)).get("spillover")).isNull();
    }
}
