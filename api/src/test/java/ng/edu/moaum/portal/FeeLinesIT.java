package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * V461 through the API: a student whose open second semester has no fee line while the first's does is not told registration
 * is open; the Bursary's filled sheet adds the line (once — the same sheet again adds nothing), leaves out a row with no
 * amount, and is the Bursary's alone; the gap list gives the session's semesters for the sheet.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class FeeLinesIT {

    static final String SES = "2075/2076";

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

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(9_000) + 1_000);
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
