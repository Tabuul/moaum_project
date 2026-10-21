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
 * V461 through the API: a student whose open second semester has no fee line while the first's does is not told registration
 * is open; the Bursary's filled sheet adds the line (once — the same sheet again adds nothing), leaves out a row with no
 * amount, and is the Bursary's alone; the gap list gives the session's semesters for the sheet.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class FeeLinesIT {

    static final String SES = "2075/2076";
    /** V613: the session the spillover-year lines are copied into */
    static final String SES2 = "2076/2077";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String tag;
    String bursar;
    String programme;

    /** the session's fee lines this test states, taken away after it: a planned session with fees stated is the session a later
     *  test's student reads by default (StudentPortalIT, PortalWindowsIT) */
    @AfterEach
    void takeAwayFeeLines() {
        if (it != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session IN (:s, :t)").param("s", SES).param("t", SES2).update());
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("MOAUM/ADM/75/" + k + "61", "MOAUM/FL/75/" + k, "ZZFL" + k)));
        bursar = TestTokens.token(it.person("ZZFL-BUR-" + tag, "ZZFLBUR"), List.of("bursar"));
        it.session(SES, 2075);
        it.db(() -> jdbc.sql("""
                INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), :s, 1, 'CLOSED'), (gen_random_uuid(), :s, 2, 'OPEN')
                ON CONFLICT (session, number) DO UPDATE SET state = excluded.state
                """).param("s", SES).update());
        // an undergraduate programme of a faculty no "charged as" rule names, with only its first-semester line
        programme = it.db(() -> jdbc.sql("""
                SELECT p.code FROM ref.programme p
                 WHERE NOT coalesce(p.archived, false) AND coalesce(p.category, '') <> 'POST GRADUATE'
                   AND p.faculty_code NOT IN (SELECT faculty_code FROM finance.faculty_fee_source UNION SELECT source_faculty_code FROM finance.faculty_fee_source)
                 ORDER BY p.code DESC LIMIT 1
                """).query(String.class).single());
        it.db(() -> jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE session = :s AND programme_code = :p AND ended_at IS NULL")
                .param("s", SES).param("p", programme).update());
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.fee_schedule (id, session, item, amount, level, entry_mode, faculty_code, programme_code, ord, semester, indigene, spillover, kind)
                SELECT gen_random_uuid(), :s, 'School fees (semester 1)', 100000, 100, 'UTME', p.faculty_code, p.code, 1, 1, NULL, false, 'FEE'
                  FROM ref.programme p WHERE p.code = :p
                """).param("s", SES).param("p", programme).update());
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static int n(Map<String, Object> m, String k) {
        return ((Number) m.get(k)).intValue();
    }

    /** V613: school-fee lines by spillover year — "400 Level (SP1) first semester" and so on: stated by the sheet ("SP1" in the
     *  Spillover cell) and by the form (spillover and its year), read by the matchers for a student in that year of a programme
     *  with that final level, kept apart from the other year, carried by a copy, and named by the gap report */
    @SuppressWarnings("unchecked")
    @Test
    void feeLinesAreStatedBySpilloverYearAndChargedToTheStudentsOfThatYear() {
        String prog4 = jdbc.sql("""
                SELECT p.code FROM ref.programme p
                 WHERE NOT coalesce(p.archived, false) AND coalesce(p.category, '') <> 'POST GRADUATE' AND finance.final_level(p.code) = 400
                   AND p.faculty_code NOT IN (SELECT faculty_code FROM finance.faculty_fee_source UNION SELECT source_faculty_code FROM finance.faculty_fee_source)
                 ORDER BY p.code DESC LIMIT 1
                """).query(String.class).single();
        String basisBefore = jdbc.sql("SELECT spillover_basis FROM finance.fee_setting WHERE id = 1").query(String.class).optional().orElse("LEVEL");
        it.db(() -> {
            // the level basis (V571): a student above the programme's final level is in spillover, a level a year
            jdbc.sql("UPDATE finance.fee_setting SET spillover_basis = 'LEVEL' WHERE id = 1").update();
            jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE session = :s AND programme_code = :p AND ended_at IS NULL").param("s", SES).param("p", prog4).update();
            return null;
        });
        it.session(SES2, 2076);
        UUID sp1 = it.student("ZZFLSPA" + tag, prog4, "MOAUM/ADM/75/" + tag + "71", "MOAUM/FLS/75/" + tag + "1", 500);
        UUID sp2 = it.student("ZZFLSPB" + tag, prog4, "MOAUM/ADM/75/" + tag + "72", "MOAUM/FLS/75/" + tag + "2", 600);
        UUID fin = it.student("ZZFLSPC" + tag, prog4, "MOAUM/ADM/75/" + tag + "73", "MOAUM/FLS/75/" + tag + "3", 400);
        try {
            // the sheet: 400 Level (SP1) first semester, 400 Level (SP2) first semester, Spillover (any year) second semester, 400 Level first semester
            List<Map<String, Object>> rows = List.of(
                    Map.of("programmeCode", prog4, "level", "400", "spillover", "SP1", "semester", "1", "amount", "70000"),
                    Map.of("programmeCode", prog4, "level", "400", "spillover", "SP2", "semester", "1", "amount", "90000"),
                    Map.of("programmeCode", prog4, "level", "", "spillover", "Yes", "semester", "2", "amount", "10000"),
                    Map.of("programmeCode", prog4, "level", "400", "entryMode", "UTME", "semester", "1", "amount", "150000"));
            Map<String, Object> added = ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES + "/fee-lines", Map.of("rows", rows)));
            assertThat(n(added, "added")).isEqualTo(4);
            assertThat(n(ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES + "/fee-lines", Map.of("rows", rows))), "added")).isEqualTo(0);
            // V616: a spillover student is charged a semester's line once they register a course in it — both register both semesters here
            it.db(() -> {
                String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", prog4).query(String.class).single();
                jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) SELECT 'ZZF 516', 'Fee Lines Spillover', 6, 1, 500, :d, 'Core', 'LIVE' WHERE NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = 'ZZF 516')").param("d", dept).update();
                for (int sem : List.of(1, 2)) {
                    UUID off = jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZF 516', :s, :sem) ON CONFLICT DO NOTHING RETURNING id")
                            .param("s", SES).param("sem", sem).query(UUID.class).optional()
                            .orElseGet(() -> jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = 'ZZF 516' AND session = :s AND semester = :sem").param("s", SES).param("sem", sem).query(UUID.class).single());
                    for (UUID st : List.of(sp1, sp2)) {
                        UUID reg = UUID.randomUUID();
                        jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status) VALUES (:id, :st, :s, :sem, (SELECT current_level FROM people.student WHERE id = :st), 'DRAFT')")
                                .param("id", reg).param("st", st).param("s", SES).param("sem", sem).update();
                        jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status) VALUES (:r, :o, 6, 'CURRENT', 'REGISTERED')").param("r", reg).param("o", off).update();
                    }
                }
                return null;
            });
            // the schedule lists the year; the matchers charge each student the lines of their year and level
            List<Map<String, Object>> items = (List<Map<String, Object>>) ok(it.get(bursar, "/api/v1/finance/sessions/" + SES + "/schedule")).get("items");
            assertThat(items.stream().filter(i -> prog4.equals(i.get("programme_code"))).map(i -> String.valueOf(i.get("spillover")) + "/" + i.get("spill_year") + "/" + i.get("level")))
                    .containsExactlyInAnyOrder("true/1/400", "true/2/400", "true/null/null", "false/null/400");
            assertThat(jdbc.sql("SELECT finance.due_for_semester(:s, :ses, 1)").param("s", sp1).param("ses", SES).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("70000");
            assertThat(jdbc.sql("SELECT finance.due_for_semester(:s, :ses, 1)").param("s", sp2).param("ses", SES).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("90000");
            assertThat(jdbc.sql("SELECT finance.due_for_semester(:s, :ses, 1)").param("s", fin).param("ses", SES).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("150000");
            assertThat(jdbc.sql("SELECT finance.due_for_semester(:s, :ses, 2)").param("s", sp1).param("ses", SES).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("80000");
            assertThat(jdbc.sql("SELECT string_agg(c.item, '; ' ORDER BY c.ord) FROM finance.charges_of_as(:s, :ses, ARRAY['FEE'], NULL) c").param("s", sp2).param("ses", SES).query(String.class).single())
                    .contains("SP2").doesNotContain("SP1");
            assertThat(jdbc.sql("SELECT finance.fee_stated(:s, :ses)").param("s", sp1).param("ses", SES).query(Boolean.class).single()).isTrue();
            // the form: a spillover levy for SP1 at 400 Level; the same again is a duplicate; a year outside 1–3 is refused
            Map<String, Object> levy = new java.util.HashMap<>(Map.of("item", "Spillover levy", "amount", 5000, "level", 400, "programmeCode", prog4, "semester", 1, "spillover", true, "spillYear", 1));
            assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES + "/schedule", levy).getStatusCode().value()).isEqualTo(200);
            ResponseEntity<Map> twice = it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES + "/schedule", levy);
            assertThat(twice.getStatusCode().value()).isEqualTo(422);
            assertThat(String.valueOf(twice.getBody())).contains("FEE_LINE_DUPLICATE");
            levy.put("spillYear", 2);
            assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES + "/schedule", levy).getStatusCode().value()).as("SP2 is another scope").isEqualTo(200);
            levy.put("spillYear", 4);
            assertThat(String.valueOf(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES + "/schedule", levy).getBody())).contains("FEE_SPILL_YEAR");
            assertThat(jdbc.sql("SELECT finance.due_for_semester(:s, :ses, 1)").param("s", sp1).param("ses", SES).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("75000");
            // the copy into the next session carries the year
            ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES2 + "/schedule/copy", Map.of("from", SES)));
            assertThat(jdbc.sql("SELECT count(*) FROM finance.fee_schedule WHERE session = :t AND programme_code = :p AND spill_year = 1").param("t", SES2).param("p", prog4).query(Long.class).single()).isEqualTo(2L);
            // the gap report names the year and the final level of a spillover group with no line: the SP2 lines and the any-year line ended
            it.db(() -> jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE session = :s AND programme_code = :p AND spillover AND (spill_year = 2 OR spill_year IS NULL)").param("s", SES).param("p", prog4).update());
            List<Map<String, Object>> gaps = (List<Map<String, Object>>) ok(it.get(bursar, "/api/v1/finance/sessions/" + SES + "/fee-gaps")).get("rows");
            Map<String, Object> g2 = gaps.stream().filter(g -> prog4.equals(g.get("programme_code")) && Integer.valueOf(2).equals(g.get("spill_year"))).findFirst().orElseThrow();
            assertThat(g2.get("final_level")).isEqualTo(400);
            assertThat(g2.get("spillover")).isEqualTo(true);
            assertThat(g2.get("stated")).isEqualTo(false);
            assertThat(gaps.stream().filter(g -> prog4.equals(g.get("programme_code")) && Integer.valueOf(1).equals(g.get("spill_year"))).findFirst().orElseThrow().get("stated")).as("SP1 keeps its own line").isEqualTo(true);
        } finally {
            it.db(() -> jdbc.sql("UPDATE finance.fee_setting SET spillover_basis = :b WHERE id = 1").param("b", basisBefore).update());
        }
    }

    @SuppressWarnings("unchecked")
    @Test
    void theFilledSheetAddsTheSemestersLineOnceAndRegistrationWaitsUntilItDoes() {
        UUID st = it.student("ZZFL" + tag, programme, "MOAUM/ADM/75/" + tag + "61", "MOAUM/FL/75/" + tag, 100);
        String student = TestTokens.token(st, List.of("student"));
        Map<String, Object> fees = ok(it.get(student, "/api/v1/me/fees?session=" + SES));
        assertThat((List<Integer>) fees.get("unstatedSemesters")).containsExactly(2);
        assertThat(fees.get("clearsRegistration")).isEqualTo(false);
        // the gap list names the session's semesters, for the sheet
        assertThat((List<Integer>) ok(it.get(bursar, "/api/v1/finance/sessions/" + SES + "/fee-gaps")).get("semesters")).containsExactly(1, 2);

        Map<String, Object> second = Map.of("programmeCode", programme, "level", "100", "entryMode", "UTME", "semester", "2",
                "indigene", "", "spillover", "No", "amount", "50000");
        Map<String, Object> blank = Map.of("programmeCode", programme, "level", "200", "entryMode", "UTME", "semester", "2", "amount", "");
        // the Bursary's alone
        String registrar = TestTokens.token(it.person("ZZFL-REG-" + tag, "ZZFLREG"), List.of("registrar"));
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES + "/fee-lines", Map.of("rows", List.of(second))).getStatusCode().value())
                .isEqualTo(403);
        Map<String, Object> added = ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES + "/fee-lines", Map.of("rows", List.of(second, blank))));
        assertThat(n(added, "added")).isEqualTo(1);
        assertThat(n(added, "no_amount")).isEqualTo(1);
        // the student's second semester is stated now; the same sheet again adds nothing
        fees = ok(it.get(student, "/api/v1/me/fees?session=" + SES));
        assertThat((List<Integer>) fees.get("unstatedSemesters")).isEmpty();
        assertThat((List<Map<String, Object>>) fees.get("charges")).hasSize(2);
        Map<String, Object> again = ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + SES + "/fee-lines", Map.of("rows", List.of(second))));
        assertThat(n(again, "added")).isZero();
        assertThat(n(again, "already")).isEqualTo(1);
    }
}
