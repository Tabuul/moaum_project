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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The school fees report over the API: three students of one programme at one level in a session of the test's own — one paid in
 * full, one part-paid, one not at all — move their faculty, department and level line and the grand total by exactly what they paid
 * and owe (the line read before and after, so other tests' students on the same line do not matter). A Head of Department reads
 * only their own department; a student cannot read it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class FeeReportIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @AfterEach
    void clean() {
        if (session != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update());
    }

    private Map<String, Object> line(Map body, String dept, int level) {
        return ((List<Map<String, Object>>) body.get("rows")).stream()
                .filter(r -> dept.equals(r.get("dept_code")) && Integer.valueOf(level).equals(r.get("level"))).findFirst()
                .orElse(Map.of("paid_students", 0, "owing_students", 0, "part_paid", 0, "amount_paid", 0, "amount_owing", 0, "students", 0));
    }

    private static long n(Object v) {
        return ((Number) v).longValue();
    }

    private static BigDecimal money(Object v) {
        return new BigDecimal(String.valueOf(v));
    }

    private void pay(UUID student, long amount) {
        String ref = "MOAUM-ITFR-" + UUID.randomUUID().toString().substring(0, 12).toUpperCase();
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:st, :s, :r, 'School fees ' || :s, :a, now(), now(), :by, 'INTERSWITCH', 'RCT-' || :r, 'fee report test')
                """).param("st", student).param("s", session).param("r", ref).param("a", amount).param("by", UUID.randomUUID()).update());
    }

    @Test
    void eachLineCountsWhoPaidAndWhoOwesAndTheGrandTotalAddsUp() {
        int year = it.freeYear(3300, 3380);
        session = year + "/" + (year + 1);
        it.session(session, year);
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, NULL, 'C00023')")
                .param("s", session).update());
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
        String bursar = ItSupport.token("bursar");
        String path = "/api/v1/finance/fee-report?session=" + session;

        ResponseEntity<Map> before = it.get(bursar, path);
        assertThat(before.getStatusCode().value()).as(String.valueOf(before.getBody())).isEqualTo(200);
        Map<String, Object> b = line(before.getBody(), dept, 100);
        Map<String, Object> bt = (Map<String, Object>) before.getBody().get("total");

        UUID full = it.student(it.freeSurname("ZZFRF"), "C00023", null, it.freeNumber("MOAUM/FRF/86/", 6), 100);
        UUID part = it.student(it.freeSurname("ZZFRP"), "C00023", null, it.freeNumber("MOAUM/FRP/86/", 6), 100);
        it.student(it.freeSurname("ZZFRN"), "C00023", null, it.freeNumber("MOAUM/FRN/86/", 6), 100);
        pay(full, 100000);
        pay(part, 40000);

        ResponseEntity<Map> after = it.get(bursar, path);
        assertThat(after.getStatusCode().value()).isEqualTo(200);
        assertThat(after.getBody()).containsEntry("session", session);
        Map<String, Object> a = line(after.getBody(), dept, 100);
        Map<String, Object> at = (Map<String, Object>) after.getBody().get("total");
        assertThat(n(a.get("paid_students")) - n(b.get("paid_students"))).isEqualTo(1);
        assertThat(n(a.get("owing_students")) - n(b.get("owing_students"))).isEqualTo(2);
        assertThat(n(a.get("part_paid")) - n(b.get("part_paid"))).isEqualTo(1);
        assertThat(money(a.get("amount_paid")).subtract(money(b.get("amount_paid")))).isEqualByComparingTo("140000");
        assertThat(money(a.get("amount_owing")).subtract(money(b.get("amount_owing")))).isEqualByComparingTo("160000");
        assertThat(money(at.get("amount_paid")).subtract(money(bt.get("amount_paid")))).isEqualByComparingTo("140000");
        assertThat(n(at.get("owing_students")) - n(bt.get("owing_students"))).isEqualTo(2);
        // the grand total is the lines added up
        List<Map<String, Object>> rows = (List<Map<String, Object>>) after.getBody().get("rows");
        assertThat(rows.stream().map(r -> money(r.get("amount_owing"))).reduce(BigDecimal.ZERO, BigDecimal::add)).isEqualByComparingTo(money(at.get("amount_owing")));
        assertThat(rows.stream().mapToLong(r -> n(r.get("paid_students"))).sum()).isEqualTo(n(at.get("paid_students")));

        // a Head of Department reads their own department alone; a student reads nothing
        String other = jdbc.sql("SELECT code FROM ref.department WHERE code <> :d ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
        String hod = it.officer("hod", "department", other);
        ResponseEntity<Map> theirs = it.get(hod, path);
        assertThat(theirs.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) theirs.getBody().get("rows")).allMatch(r -> other.equals(r.get("dept_code")));
        assertThat(it.get(hod, path + "&dept=" + dept).getStatusCode().value()).isEqualTo(422);
        assertThat(it.get(TestTokens.token(full, List.of("student")), path).getStatusCode().value()).isEqualTo(403);
    }
}
