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
 * V506: the overpaid of a session decided by the Bursary — the excess carried into the next session (a CARRIED school-fees record
 * there) or a refund raised on the Refunds & Credits desk — the reconciliation reading it settled; a session's fee lines copied
 * from another after a preview, a line it states kept; and what waits for the ledger read on its own.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class OverpaidFeesIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    /** the run's own two sessions: their fee lines apply to every student of the programme, so they are taken away after the test */
    String a;
    String b;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @AfterEach
    void clean() {
        for (String s : new String[] {a, b}) {
            if (s != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", s).update());
        }
    }

    private UUID overpaid(String tag, String suffix, String number, long... amounts) {
        UUID student = it.student("ZZOVERPAID" + suffix + tag, "C00023", "MOAUM/ADM/86/8" + ("C".equals(suffix) ? "1" : "2") + tag, number, 100);
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        String key = "MOAUM-LEG-" + matric.replaceAll("[^0-9A-Z]", "") + "-" + a.replace("/", "-");
        for (int i = 0; i < amounts.length; i++) {
            String ref = key + "-S" + (i + 1);
            long amount = amounts[i];
            int sem = i + 1;
            it.db(() -> jdbc.sql("""
                    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                    VALUES (:s, :ses, :r, :p, :a, now(), now(), :by, 'Legacy', 'LEG-' || :r, 'Imported from the old portal')
                    ON CONFLICT (reference) DO NOTHING
                    """).param("s", student).param("ses", a).param("r", ref).param("p", "School fees (legacy) · semester " + sem).param("a", amount)
                    .param("by", UUID.randomUUID()).update());
        }
        return student;
    }

    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void overpaidFeesAreCarriedOrRefundedAndASessionsFeesCopiedFromAnother() {
        Random random = new Random();
        String tag = String.format("%04d", random.nextInt(10_000));
        // years no other test uses, and two sessions next to each other on the calendar
        int year = 3000 + random.nextInt(90);
        a = year + "/" + (year + 1);
        b = (year + 1) + "/" + (year + 2);
        it.session(a, year);
        it.session(b, year + 1);
        for (String s : new String[] {a, b}) {
            it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, NULL, 'C00023')")
                    .param("s", s).update());
        }
        UUID carry = overpaid(tag, "C", "MOAUM/OPC/86/" + tag, 70000, 50000);
        UUID refund = overpaid(tag, "R", "MOAUM/OPR/86/" + tag, 130000);
        String bursar = ItSupport.token("bursar");
        String audit = ItSupport.token("audit");

        ResponseEntity<Map> list = it.get(audit, "/api/v1/finance/legacy-fees/overpaid?session=" + a);
        assertThat(list.getStatusCode().value()).as(String.valueOf(list.getBody())).isEqualTo(200);
        assertThat(list.getBody()).containsEntry("session", a).containsEntry("nextSession", b);
        assertThat((List<Map>) list.getBody().get("rows")).filteredOn(r -> carry.toString().equals(r.get("student_id")) || refund.toString().equals(r.get("student_id")))
                .extracting(r -> ((Number) r.get("excess")).intValue() + ":" + r.get("decision")).containsExactlyInAnyOrder("20000:null", "30000:null");

        // the Bursary alone, with a reason
        Map<String, Object> carryIt = Map.of("session", a, "decision", "CARRY", "students", List.of(carry), "reason", "overpaid fees counted towards the next session");
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/legacy-fees/overpaid/decide", carryIt).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/overpaid/decide",
                Map.of("session", a, "decision", "CARRY", "students", List.of(carry), "reason", "short")).getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> carried = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/overpaid/decide", carryIt);
        assertThat(carried.getStatusCode().value()).as(String.valueOf(carried.getBody())).isEqualTo(200);
        assertThat(carried.getBody()).containsEntry("carried", 1).containsEntry("refunds", 0);
        Map<String, Object> inB = jdbc.sql("SELECT purpose, amount::int AS amount, channel FROM finance.payment_reference WHERE student_id = :s AND session = :b")
                .param("s", carry).param("b", b).query().singleRow();
        assertThat(inB).containsEntry("purpose", "School fees " + b + " (carried from " + a + ")").containsEntry("amount", 20000).containsEntry("channel", "CARRIED");

        ResponseEntity<Map> refunded = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/overpaid/decide",
                Map.of("session", a, "decision", "REFUND", "students", List.of(refund), "reason", "overpaid fees returned to the student"));
        assertThat(refunded.getStatusCode().value()).as(String.valueOf(refunded.getBody())).isEqualTo(200);
        assertThat(refunded.getBody()).containsEntry("refunds", 1);
        assertThat(jdbc.sql("SELECT amount::int || ':' || state FROM finance.refund WHERE student_id = :s").param("s", refund).query(String.class).single())
                .isEqualTo("30000:PROPOSED");

        Map<String, Object> rec = it.get(audit, "/api/v1/finance/legacy-fees/reconciliation?session=" + a + "&state=OVER_SETTLED&size=100000").getBody();
        assertThat((List<Map>) rec.get("rows")).filteredOn(r -> carry.toString().equals(r.get("student_id")) || refund.toString().equals(r.get("student_id")))
                .extracting(r -> r.get("decision") + ":" + ((Number) r.get("settled")).intValue()).containsExactlyInAnyOrder("CARRY:20000", "REFUND:30000");

        // the fees copied: a preview, then the copy of what the next session lacks
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, kind) VALUES (:s, 'Late payment', 5000, NULL, 'C00023', 'LATE_PAYMENT')")
                .param("s", a).update());
        String copyPath = "/api/v1/finance/sessions/" + b + "/schedule/copy";
        ResponseEntity<Map> preview = it.get(audit, copyPath + "?from=" + a);
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        assertThat(preview.getBody()).containsEntry("copy", 1).containsEntry("kept", 1).containsEntry("applied", false);
        assertThat(it.call(audit, HttpMethod.POST, copyPath, Map.of("from", a)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> copied = it.call(bursar, HttpMethod.POST, copyPath, Map.of("from", a));
        assertThat(copied.getStatusCode().value()).as(String.valueOf(copied.getBody())).isEqualTo(200);
        assertThat(copied.getBody()).containsEntry("copy", 1).containsEntry("applied", true);
        assertThat(it.get(audit, copyPath + "?from=" + a).getBody()).as("copied once").containsEntry("copy", 0).containsEntry("kept", 2);

        ResponseEntity<Map> unposted = it.get(audit, "/api/v1/finance/accounting/unposted");
        assertThat(unposted.getStatusCode().value()).isEqualTo(200);
        assertThat(unposted.getBody()).containsKeys("payments", "refunds", "vouchers");
    }
}
