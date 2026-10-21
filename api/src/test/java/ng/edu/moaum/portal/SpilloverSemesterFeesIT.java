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
 * V616 through the API: a spillover student (at 500 Level on a four-year programme, by the level basis) with 400 Level (SP1) lines
 * for both semesters and a whole-session spillover line owes nothing and is cleared until a course is on a registration; registering
 * a course in the second semester alone makes that semester's line and the whole-session line due — never the first semester's — the
 * fees page says so, the submission waits for the payment, the payment settles it and the registration is submitted; the readers
 * built on fee profiles agree; a student not in spillover is charged as before. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class SpilloverSemesterFeesIT {

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
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("MOAUM/ADM/16/" + k + "61", "MOAUM/ADM/16/" + k + "62", "MOAUM/SPS/16/" + k + "1", "MOAUM/SPS/16/" + k + "2", "ZZSPS" + k, "ZZSPSF" + k)));
        bursar = TestTokens.token(it.person("ZZSPS-BUR-" + tag, "ZZSPSBUR"), List.of("bursar"));
        it.session(session, y);
        prog4 = jdbc.sql("""
                SELECT p.code FROM ref.programme p
                 WHERE NOT coalesce(p.archived, false) AND coalesce(p.category, '') <> 'POST GRADUATE' AND finance.final_level(p.code) = 400
                   AND p.faculty_code NOT IN (SELECT faculty_code FROM finance.faculty_fee_source UNION SELECT source_faculty_code FROM finance.faculty_fee_source)
                 ORDER BY p.code DESC LIMIT 1
                """).query(String.class).single();
        basisBefore = jdbc.sql("SELECT spillover_basis FROM finance.fee_setting WHERE id = 1").query(String.class).optional().orElse("LEVEL");
        it.db(() -> {
            // the level basis (V571): a level above the programme's final one is spillover, a level a year
            jdbc.sql("UPDATE finance.fee_setting SET spillover_basis = 'LEVEL' WHERE id = 1").update();
            jdbc.sql("""
                    INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), :s, 1, 'OPEN'), (gen_random_uuid(), :s, 2, 'OPEN')
                    ON CONFLICT (session, number) DO UPDATE SET state = excluded.state
                    """).param("s", session).update();
            // a clearance scheme in force, releasing registration at the first instalment, where none is (as CourseRegistrationAutoApprovalIT)
            String instrument = "Integration test: SpilloverSemesterFeesIT " + tag;
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
            // two 500-Level courses of the programme (12 and 6 units: the minimum load met), offered in the session's second semester
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", prog4).query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    SELECT x.code, x.title, x.units, 2, 500, :d, 'Core', 'LIVE'
                      FROM (VALUES ('ZZS 516', 'Spillover Semester Fees One', 12), ('ZZS 517', 'Spillover Semester Fees Two', 6)) x(code, title, units)
                     WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = x.code)
                    """).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('ZZS 516', :p, 500, 'Core'), ('ZZS 517', :p, 500, 'Core') ON CONFLICT DO NOTHING").param("p", prog4).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZS 516', :s, 2), (gen_random_uuid(), 'ZZS 517', :s, 2) ON CONFLICT DO NOTHING").param("s", session).update();
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

    @SuppressWarnings("unchecked")
    @Test
    void aSpilloverStudentIsChargedASemestersFeesOnlyWhenTheyRegisterACourseInIt() {
        UUID sp1 = it.student("ZZSPS" + tag, prog4, "MOAUM/ADM/16/" + tag + "61", "MOAUM/SPS/16/" + tag + "1", 500);
        UUID fin = it.student("ZZSPSF" + tag, prog4, "MOAUM/ADM/16/" + tag + "62", "MOAUM/SPS/16/" + tag + "2", 400);
        String token = TestTokens.token(sp1, List.of("student"));
        // the Bursary's lines: 400 Level (SP1) first and second semester, a whole-session spillover line, the level's own lines
        List<Map<String, Object>> rows = List.of(
                Map.of("programmeCode", prog4, "level", "400", "spillover", "SP1", "semester", "1", "amount", "70000"),
                Map.of("programmeCode", prog4, "level", "400", "spillover", "SP1", "semester", "2", "amount", "60000"),
                Map.of("programmeCode", prog4, "level", "", "spillover", "Yes", "semester", "", "amount", "5000"),
                Map.of("programmeCode", prog4, "level", "400", "entryMode", "UTME", "semester", "1", "amount", "150000"),
                Map.of("programmeCode", prog4, "level", "400", "entryMode", "UTME", "semester", "2", "amount", "120000"));
        assertThat(((Number) ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/fee-lines", Map.of("rows", rows))).get("added")).intValue()).isEqualTo(5);

        // before a course is chosen: nothing due, the fee stated, nothing unstated, the student told how they are charged
        assertThat(due(sp1)).isEqualByComparingTo("0");
        Map<String, Object> fees = ok(it.get(token, "/api/v1/me/fees?session=" + session));
        assertThat(fees.get("stated")).isEqualTo(true);
        assertThat(fees.get("spilloverBySemester")).isEqualTo(true);
        assertThat((List<Integer>) fees.get("unstatedSemesters")).isEmpty();
        assertThat(((Number) fees.get("due")).intValue()).isZero();
        assertThat(jdbc.sql("SELECT finance.semester_cleared(:s, :ses, 2)").param("s", sp1).param("ses", session).query(Boolean.class).single()).isTrue();

        // a course registered in the second semester alone: that semester's line and the whole-session line become due, never the first's
        Map<String, Object> view = ok(it.get(token, "/api/v1/me/registration?session=" + session + "&semester=2"));
        List<Map<String, Object>> menu = (List<Map<String, Object>>) view.get("menu");
        List<UUID> offerings = menu.stream().filter(m -> String.valueOf(m.get("course_code")).startsWith("ZZS 51")).map(m -> UUID.fromString(String.valueOf(m.get("offering_id")))).toList();
        assertThat(offerings).hasSize(2);
        ok(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 2, "offerings", offerings)));
        assertThat(due(sp1)).isEqualByComparingTo("65000");
        assertThat(jdbc.sql("SELECT finance.due_for_semester(:s, :ses, 1)").param("s", sp1).param("ses", session).query(BigDecimal.class).single()).isEqualByComparingTo("5000");
        assertThat(jdbc.sql("SELECT string_agg(c.item, '; ' ORDER BY c.ord) FROM finance.charges_of_as(:s, :ses, ARRAY['FEE'], NULL) c").param("s", sp1).param("ses", session).query(String.class).single())
                .contains("Second Semester").doesNotContain("First Semester");
        fees = ok(it.get(token, "/api/v1/me/fees?session=" + session));
        assertThat(((Number) fees.get("due")).intValue()).isEqualTo(65000);
        assertThat((List<Integer>) fees.get("unstatedSemesters")).isEmpty();
        // the readers built on fee profiles agree with the student's own position
        assertThat(jdbc.sql("SELECT reg_sems FROM finance.fee_profiles(:ses) WHERE student_id = :s").param("ses", session).param("s", sp1).query(String.class).single()).isEqualTo("{2}");
        assertThat(jdbc.sql("SELECT due FROM finance.fee_positions_of(:ses, ARRAY[:s]::uuid[])").param("ses", session).param("s", sp1).query(BigDecimal.class).single()).isEqualByComparingTo("65000");
        assertThat(jdbc.sql("SELECT payable FROM finance.session_positions(:ses, 2) WHERE student_id = :s").param("ses", session).param("s", sp1).query(BigDecimal.class).single()).isEqualByComparingTo("60000");
        // the submission waits for the semester's fees; paid, it goes through
        ResponseEntity<Map> held = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 2));
        assertThat(held.getStatusCode().value()).as(String.valueOf(held.getBody())).isEqualTo(422);
        assertThat(String.valueOf(held.getBody())).containsIgnoringCase("second semester school fees");
        Map<String, Object> ref = ok(it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 65000)));
        ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "spillover semester fees test")));
        assertThat(jdbc.sql("SELECT paid_in_full FROM finance.position(:s, :ses)").param("s", sp1).param("ses", session).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT finance.semester_cleared(:s, :ses, 2)").param("s", sp1).param("ses", session).query(Boolean.class).single()).isTrue();
        ResponseEntity<Map> submitted = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 2));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.registrations_without_fees(:ses) WHERE student_id = :s").param("ses", session).param("s", sp1).query(Long.class).single()).isZero();
        // a student not in spillover is charged as before, registered or not
        assertThat(due(fin)).isEqualByComparingTo("270000");
        assertThat(jdbc.sql("SELECT reg_sems FROM finance.fee_profiles(:ses) WHERE student_id = :s").param("ses", session).param("s", fin).query(String.class).optional().orElse(null)).isNull();
    }
}
