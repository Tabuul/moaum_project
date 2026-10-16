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
 * V451 through the API: the Bursary names a faculty charged as another; while it has no line of its own in a session its
 * students are charged the other's, the student's fees say which open semester is not yet stated, and the Bursary's list
 * names their group; its own lines end the rule; a chain, the faculty itself and an unknown faculty are refused; only the
 * Bursary sets a rule; Go-live readiness counts the students with no fee stated.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class FeeWatchIT {

    static final String SES = "2079/2080";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String tag;
    String bursar;
    String registrar;
    String fa;
    String fb;
    String programme;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(900_000) + 100_000);
        bursar = TestTokens.token(it.person("ZZFW-BUR-" + tag, "ZZFWBUR"), List.of("bursar"));
        registrar = TestTokens.token(it.person("ZZFW-REG-" + tag, "ZZFWREG"), List.of("registrar"));
        it.session(SES, 2079);
        it.db(() -> jdbc.sql("""
                INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), :s, 1, 'CLOSED'), (gen_random_uuid(), :s, 2, 'OPEN')
                ON CONFLICT (session, number) DO UPDATE SET state = excluded.state
                """).param("s", SES).update());
        // two faculties no rule names; A with an undergraduate programme
        Map<String, Object> a = it.db(() -> jdbc.sql("""
                SELECT p.faculty_code, p.code FROM ref.programme p
                 WHERE NOT coalesce(p.archived, false) AND coalesce(p.category, '') <> 'POST GRADUATE'
                   AND p.faculty_code NOT IN (SELECT faculty_code FROM finance.faculty_fee_source UNION SELECT source_faculty_code FROM finance.faculty_fee_source)
                 ORDER BY p.faculty_code DESC, p.code LIMIT 1
                """).query().singleRow());
        fa = (String) a.get("faculty_code");
        programme = (String) a.get("code");
        fb = it.db(() -> jdbc.sql("""
                SELECT code FROM ref.faculty
                 WHERE code <> :a AND code NOT IN (SELECT faculty_code FROM finance.faculty_fee_source UNION SELECT source_faculty_code FROM finance.faculty_fee_source)
                 ORDER BY code DESC LIMIT 1
                """).param("a", fa).query(String.class).single());
        // the session's lines start empty for both
        it.db(() -> jdbc.sql("UPDATE finance.fee_schedule SET ended_at = now() WHERE session = :s AND ended_at IS NULL AND faculty_code IN (:a, :b)")
                .param("s", SES).param("a", fa).param("b", fb).update());
    }

    @AfterEach
    void tearDown() {
        it.db(() -> jdbc.sql("DELETE FROM finance.faculty_fee_source WHERE faculty_code IN (:a, :b)").param("a", fa).param("b", fb).update());
        // the session's fee lines too: a planned session with fees stated is the session a later test's student reads by default
        it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SES).update());
    }

    private void line(String faculty, int semester, int amount) {
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.fee_schedule (id, session, item, amount, level, entry_mode, faculty_code, programme_code, ord, semester, indigene, spillover, kind)
                VALUES (gen_random_uuid(), :s, :i, :amt, 100, 'UTME', :f, NULL, :sem, :sem, NULL, false, 'FEE')
                """).param("s", SES).param("i", "School fees (semester " + semester + ")").param("amt", amount).param("f", faculty).param("sem", semester).update());
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        return String.valueOf(r.getBody().get("code"));
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    private List<Map<String, Object>> rules(String token) {
        ResponseEntity<List> r = it.getList(token, "/api/v1/finance/fee-sources?session=" + SES);
        assertThat(r.getStatusCode().value()).isEqualTo(200);
        return (List<Map<String, Object>>) (List) r.getBody();
    }

    @SuppressWarnings("unchecked")
    @Test
    void aFacultyChargedAsAnotherIsChargedItsLinesUntilItStatesItsOwn() {
        UUID st = it.student("ZZFW" + tag, programme, "MOAUM/ADM/79/" + tag, "MOAUM/FW/79/" + tag, 100);
        String student = TestTokens.token(st, List.of("student"));
        // only the Bursary names a rule; a chain, the faculty itself and an unknown faculty are refused
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/finance/fee-sources/" + fa, Map.of("source", fb)).getStatusCode().value()).isEqualTo(403);
        body(it.call(bursar, HttpMethod.PUT, "/api/v1/finance/fee-sources/" + fa, Map.of("source", fb, "fromSession", SES, "note", "IT " + tag)));
        assertThat(code(it.call(bursar, HttpMethod.PUT, "/api/v1/finance/fee-sources/" + fb, Map.of("source", fa)))).isEqualTo("FEE_SOURCE_CHAIN");
        assertThat(code(it.call(bursar, HttpMethod.PUT, "/api/v1/finance/fee-sources/" + fa, Map.of("source", fa)))).isEqualTo("FEE_SOURCE_SELF");
        assertThat(code(it.call(bursar, HttpMethod.PUT, "/api/v1/finance/fee-sources/ZZNOFAC", Map.of("source", fb)))).isEqualTo("FEE_SOURCE_FACULTY");
        Map<String, Object> rule = rules(registrar).stream().filter(r -> fa.equals(r.get("faculty_code"))).findFirst().orElseThrow();
        assertThat(rule.get("source_faculty_code")).isEqualTo(fb);
        assertThat(rule.get("from_session")).isEqualTo(SES);
        assertThat(rule.get("in_force")).isEqualTo(true);

        // B states the first semester: A's student is charged it; the open second semester is not yet stated — for the
        // student, and on the Bursary's list, charged as B
        line(fb, 1, 100_000);
        Map<String, Object> fees = body(it.get(student, "/api/v1/me/fees?session=" + SES));
        assertThat((List<Map<String, Object>>) fees.get("charges")).hasSize(1);
        assertThat(fees.get("stated")).isEqualTo(true);
        assertThat((List<Integer>) fees.get("unstatedSemesters")).containsExactly(2);
        Map<String, Object> gaps = body(it.get(bursar, "/api/v1/finance/sessions/" + SES + "/fee-gaps"));
        assertThat((List<Integer>) gaps.get("openSemesters")).containsExactly(2);
        Map<String, Object> group = ((List<Map<String, Object>>) gaps.get("rows")).stream()
                .filter(g -> programme.equals(g.get("programme_code")) && Integer.valueOf(100).equals(g.get("level")) && "UTME".equals(g.get("entry_mode")))
                .findFirst().orElseThrow();
        assertThat(group.get("stated")).isEqualTo(true);
        assertThat(group.get("missing")).isEqualTo("2");
        assertThat(group.get("charged_as")).isEqualTo(fb);
        assertThat(((Number) group.get("students")).longValue()).isGreaterThanOrEqualTo(1);
        // the list is read by the offices that read the schedule, never a student
        body(it.get(registrar, "/api/v1/finance/sessions/" + SES + "/fee-gaps"));
        assertThat(it.get(student, "/api/v1/finance/sessions/" + SES + "/fee-gaps").getStatusCode().value()).isEqualTo(403);

        // B states the second: nothing is missing for A's student
        line(fb, 2, 50_000);
        fees = body(it.get(student, "/api/v1/me/fees?session=" + SES));
        assertThat((List<Map<String, Object>>) fees.get("charges")).hasSize(2);
        assertThat((List<Integer>) fees.get("unstatedSemesters")).isEmpty();

        // A states its own: the rule waits, A's lines alone apply
        line(fa, 1, 90_000);
        line(fa, 2, 40_000);
        assertThat(rules(bursar).stream().filter(r -> fa.equals(r.get("faculty_code"))).findFirst().orElseThrow().get("in_force")).isEqualTo(false);
        fees = body(it.get(student, "/api/v1/me/fees?session=" + SES));
        assertThat((List<Map<String, Object>>) fees.get("charges")).extracting(c -> ((Number) c.get("amount")).intValue()).containsExactlyInAnyOrder(90_000, 40_000);

        // the rule ended
        body(it.call(bursar, HttpMethod.DELETE, "/api/v1/finance/fee-sources/" + fa, null));
        assertThat(rules(bursar)).noneMatch(r -> fa.equals(r.get("faculty_code")));
    }

    @SuppressWarnings("unchecked")
    @Test
    void goLiveReadinessCountsTheStudentsWithNoFeeStated() {
        line(fb, 1, 100_000);
        String ict = TestTokens.token(it.person("ZZFW-ICT-" + tag, "ZZFWICT"), List.of("ict"));
        Map<String, Object> readiness = body(it.get(ict, "/api/v1/platform/readiness?session=" + SES));
        Map<String, Object> check = ((List<Map<String, Object>>) readiness.get("checks")).stream()
                .filter(c -> "fee_gaps".equals(c.get("key"))).findFirst().orElseThrow();
        long gaps = it.db(() -> jdbc.sql("SELECT coalesce(sum(students), 0) FROM finance.fee_gaps(:s)").param("s", SES).query(Long.class).single());
        assertThat(check.get("status")).isEqualTo(gaps == 0 ? "ok" : "bad");   // the second semester is open
    }
}
