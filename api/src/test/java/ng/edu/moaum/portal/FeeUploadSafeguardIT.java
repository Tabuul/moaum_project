package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
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
 * V535 through the API: a structure file naming one faculty is refused as the whole session while another faculty has lines in
 * force, and replaces only that faculty's lines when uploaded for what it names; a faculty name the portal does not hold refuses
 * the upload with nothing changed; the preview of either upload says what it would change and keeps nothing; all of it the
 * Bursary's.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class FeeUploadSafeguardIT {

    static final String SES = "2083/2084";
    static final String BASE = "/api/v1/finance/sessions/" + SES;

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String tag;
    String bursar;
    String facA;
    String facB;
    String progA;

    /** the session's fee lines, taken away after the test (a planned session with fees is the one later tests' students read) */
    @AfterEach
    void takeAwayFeeLines() {
        if (it != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SES).update());
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("ZZFU-BUR-" + k, "ZZFU-REG-" + k)));
        bursar = TestTokens.token(it.person("ZZFU-BUR-" + tag, "ZZFUBUR"), List.of("bursar"));
        it.session(SES, 2083);
        // two faculties with undergraduate programmes, neither in a "charged as" rule
        List<String> facs = it.db(() -> jdbc.sql("""
                SELECT f.code FROM ref.faculty f
                 WHERE EXISTS (SELECT 1 FROM ref.programme p WHERE p.faculty_code = f.code AND NOT coalesce(p.archived, false) AND coalesce(p.category, '') <> 'POST GRADUATE')
                   AND f.code NOT IN (SELECT faculty_code FROM finance.faculty_fee_source UNION SELECT source_faculty_code FROM finance.faculty_fee_source)
                 ORDER BY f.code LIMIT 2
                """).query(String.class).list());
        facA = facs.get(0);
        facB = facs.get(1);
        progA = it.db(() -> jdbc.sql("SELECT code FROM ref.programme WHERE faculty_code = :f AND NOT coalesce(archived, false) AND coalesce(category, '') <> 'POST GRADUATE' ORDER BY code LIMIT 1")
                .param("f", facA).query(String.class).single());
        it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SES).update());
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.fee_schedule (id, session, item, amount, level, entry_mode, faculty_code, ord, semester, spillover, kind) VALUES
                  (gen_random_uuid(), :s, 'School fees (semester 1)', 50000, 100, 'UTME', :a, 1, 1, false, 'FEE'),
                  (gen_random_uuid(), :s, 'School fees (semester 1)', 60000, 100, 'UTME', :b, 1, 1, false, 'FEE')
                """).param("s", SES).param("a", facA).param("b", facB).update());
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private Map<String, Object> row(String fac, String amount) {
        return Map.of("faculty", fac, "level", "100", "entryMode", "UTME", "semester", "1", "amount", amount);
    }

    private List<String> inForce() {
        return it.db(() -> jdbc.sql("SELECT faculty_code || '=' || amount::int FROM finance.fee_schedule WHERE session = :s AND ended_at IS NULL ORDER BY 1")
                .param("s", SES).query(String.class).list());
    }

    @SuppressWarnings("unchecked")
    @Test
    void theStructureReplacesOnlyWhatItNamesUnlessTheWholeSessionIsMeant() {
        // the Bursary's alone
        String registrar = TestTokens.token(it.person("ZZFU-REG-" + tag, "ZZFUREG"), List.of("registrar"));
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/fee-structure/preview", Map.of("rows", List.of(row(facA, "55000")))).getStatusCode().value()).isEqualTo(403);

        // the preview: only faculty A's line changes; nothing is kept
        Map<String, Object> listed = ok(it.call(bursar, HttpMethod.POST, BASE + "/fee-structure/preview", Map.of("rows", List.of(row(facA, "55000")), "scope", "LISTED")));
        Map<String, Object> totals = (Map<String, Object>) listed.get("totals");
        assertThat(((Number) totals.get("changed")).intValue()).isEqualTo(1);
        assertThat(((Number) totals.get("ended")).intValue()).isZero();
        assertThat((List<Map<String, Object>>) listed.get("changes")).singleElement()
                .satisfies(c -> { assertThat(((Number) c.get("old")).intValue()).isEqualTo(50000); assertThat(((Number) c.get("new")).intValue()).isEqualTo(55000); });
        assertThat(inForce()).containsExactlyInAnyOrder(facA + "=50000", facB + "=60000");

        // the whole session: the preview says faculty B is left with no fee; the upload is refused unless that is meant
        Map<String, Object> whole = ok(it.call(bursar, HttpMethod.POST, BASE + "/fee-structure/preview", Map.of("rows", List.of(row(facA, "55000")), "scope", "SESSION")));
        assertThat((List<Map<String, Object>>) whole.get("groups")).anySatisfy(g -> {
            assertThat(g.get("facultyCode")).isEqualTo(facB);
            assertThat(g.get("losesAll")).isEqualTo(true);
        });
        ResponseEntity<Map> partial = it.call(bursar, HttpMethod.POST, BASE + "/fee-structure", Map.of("rows", List.of(row(facA, "55000")), "scope", "SESSION"));
        assertThat(partial.getStatusCode().value()).isEqualTo(422);
        assertThat(partial.getBody().get("code")).isEqualTo("FEE_STRUCTURE_PARTIAL");
        // as every caller before V535 sent it (no scope): the whole session, refused the same way
        assertThat(it.call(bursar, HttpMethod.POST, BASE + "/fee-structure", Map.of("rows", List.of(row(facA, "55000")))).getBody().get("code"))
                .isEqualTo("FEE_STRUCTURE_PARTIAL");
        assertThat(inForce()).containsExactlyInAnyOrder(facA + "=50000", facB + "=60000");

        // a name the portal does not hold: refused, nothing changed
        ResponseEntity<Map> unknown = it.call(bursar, HttpMethod.POST, BASE + "/fee-structure",
                Map.of("rows", List.of(row(facA, "55000"), row("Faculty of Nowhere Studies", "1000")), "scope", "LISTED"));
        assertThat(unknown.getBody().get("code")).isEqualTo("FEE_STRUCTURE_UNKNOWN");
        assertThat(String.valueOf(unknown.getBody().get("detail"))).contains("Faculty of Nowhere Studies");
        assertThat(inForce()).containsExactlyInAnyOrder(facA + "=50000", facB + "=60000");

        // for what it names: faculty A replaced, faculty B stands
        Map<String, Object> done = ok(it.call(bursar, HttpMethod.POST, BASE + "/fee-structure", Map.of("rows", List.of(row(facA, "55000")), "scope", "LISTED")));
        assertThat(((Number) done.get("lines")).intValue()).isEqualTo(1);
        assertThat(inForce()).containsExactlyInAnyOrder(facA + "=55000", facB + "=60000");

        // the whole session, meant: faculty B's line ends
        ok(it.call(bursar, HttpMethod.POST, BASE + "/fee-structure", Map.of("rows", List.of(row(facA, "56000")), "scope", "SESSION", "confirmWhole", true)));
        assertThat(inForce()).containsExactly(facA + "=56000");
    }

    @SuppressWarnings("unchecked")
    @Test
    void theFeesToStatePreviewSaysWhatItAddsAndKeepsNothing() {
        Map<String, Object> line = Map.of("programmeCode", progA, "level", "300", "entryMode", "UTME", "semester", "1", "amount", "81000");
        Map<String, Object> effect = ok(it.call(bursar, HttpMethod.POST, BASE + "/fee-lines/preview", Map.of("rows", List.of(line))));
        assertThat(((Number) ((Map<String, Object>) effect.get("totals")).get("new")).intValue()).isEqualTo(1);
        assertThat(((Number) ((Map<String, Object>) effect.get("result")).get("added")).intValue()).isEqualTo(1);
        assertThat(effect.get("gaps")).isInstanceOf(Map.class);
        assertThat(inForce()).containsExactlyInAnyOrder(facA + "=50000", facB + "=60000");
    }
}
