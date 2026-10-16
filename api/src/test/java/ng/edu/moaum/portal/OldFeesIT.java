package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
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
 * V498: old-portal payments come in one way — Old Fees History, the old portal's payment number telling one payment from
 * another (a make-up beside the first), never twice; the retired Payment History Upload refuses, what it wrote twice is listed
 * and withdrawn by the Bursary; and the payments are reconciled against the fee setup.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class OldFeesIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private static Map<String, Object> row(String number, String session, String semester, String amount, String item, String paidOn, String payref) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("matric", number);
        r.put("session", session);
        r.put("semester", semester);
        r.put("level", "100");
        r.put("amount", amount);
        r.put("purpose", item);
        r.put("paidOn", paidOn);
        r.put("receiptNo", payref);
        r.put("channel", "Interswitch");
        r.put("note", "");
        return r;
    }

    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void oldPaymentsComeInOneWayKeyedByTheirNumberNeverTwiceAndReconciled() {
        Random random = new Random();
        String tag = String.format("%04d", random.nextInt(10_000));
        int year = 2140 + random.nextInt(60);
        String ses = year + "/" + (year + 1);
        it.session(ses, year);
        UUID student = it.student("ZZOLDFEES" + tag, "C00023", "MOAUM/ADM/88/88" + tag, "MOAUM/OFH/88/" + tag, 100);
        // the numbers the student carries (one an earlier run made is found again by name, with that run's numbers)
        String number = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 150000, NULL, 'C00023')")
                .param("s", ses).update());
        String bursar = ItSupport.token("bursar");
        String audit = ItSupport.token("audit");
        String pay1 = "PRIT" + year + tag + "01";
        String pay2 = "PRIT" + year + tag + "02";

        // the retired door refuses
        ResponseEntity<Map> retired = it.call(bursar, HttpMethod.POST, "/api/v1/finance/payments/import",
                Map.of("rows", List.of(Map.of("matric", number, "session", ses, "amount", "1000"))));
        assertThat(retired.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(retired.getBody())).contains("PAYMENT_HISTORY_RETIRED");

        // the export: school fees, a make-up in the same semester, and the make-up listed twice
        List<Map<String, Object>> rows = List.of(
                row(number, ses, "First", "100000", "SCHOOL FEES", year + "-11-02", pay1),
                row(number, ses, "First", "20000", "SCHOOL FEES MAKE UP", (year + 1) + "-01-15", pay2),
                row(number, ses, "First", "20000", "SCHOOL FEES MAKE UP", (year + 1) + "-01-15", pay2));
        ResponseEntity<Map> imp = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", rows));
        assertThat(imp.getStatusCode().value()).as(String.valueOf(imp.getBody())).isEqualTo(200);
        assertThat(imp.getBody()).containsEntry("cleared", 2).containsEntry("separate", 1).containsEntry("duplicates", 1);
        ResponseEntity<Map> again = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", rows));
        assertThat(again.getBody()).as("loaded again, nothing changes").containsEntry("cleared", 0).containsEntry("duplicates", 3);
        String makeUp = jdbc.sql("SELECT reference FROM finance.legacy_payref WHERE payref = :p").param("p", pay2).query(String.class).single();
        assertThat(makeUp).endsWith("-S1-" + pay2);

        // reconciled against the fee setup: under by the second semester's share
        ResponseEntity<Map> rec = it.get(audit, "/api/v1/finance/legacy-fees/reconciliation?session=" + ses + "&q=" + number);
        assertThat(rec.getStatusCode().value()).as(String.valueOf(rec.getBody())).isEqualTo(200);
        assertThat(rec.getBody()).containsEntry("session", ses).containsEntry("total", 1);
        Map<String, Object> mine = ((List<Map<String, Object>>) rec.getBody().get("rows")).get(0);
        assertThat(mine).containsEntry("number", number).containsEntry("state", "UNDER");
        assertThat(((Number) mine.get("due")).intValue()).isEqualTo(150000);
        assertThat(((Number) mine.get("paid")).intValue()).isEqualTo(120000);
        assertThat(((Number) mine.get("paid_old_s1")).intValue()).isEqualTo(120000);
        assertThat(((Number) mine.get("difference")).intValue()).isEqualTo(-30000);
        assertThat((List<Map>) rec.getBody().get("summary")).extracting(s -> s.get("state")).contains("UNDER");

        // what the retired door wrote before it was retired, the make-up again: listed, then withdrawn by the Bursary alone
        String double1 = "MIGR-IT" + year + tag;
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, note, receipt_no)
                VALUES (:s, :ses, :r, 'School fees ' || :ses, 20000, :d::timestamptz, :d::timestamptz + interval '1 day', :d::timestamptz, :by, 'MIGRATION', 'Migrated payment history', 'RCT-' || :r)
                """).param("s", student).param("ses", ses).param("r", double1).param("d", (year + 1) + "-01-15").param("by", UUID.randomUUID()).update());
        ResponseEntity<Map> listed = it.get(audit, "/api/v1/finance/legacy-fees/doubles?limit=100000");
        assertThat(listed.getStatusCode().value()).as(String.valueOf(listed.getBody())).isEqualTo(200);
        assertThat((List<Map>) listed.getBody().get("rows")).filteredOn(d -> double1.equals(d.get("double_reference")))
                .extracting(d -> d.get("double_kind") + ">" + d.get("kept_reference")).containsExactly("PAYMENT_HISTORY>" + makeUp);
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/legacy-fees/doubles/withdraw", Map.of("reason", "recorded by both upload screens"))
                .getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/doubles/withdraw", Map.of("reason", "short"))
                .getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> withdrawn = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/doubles/withdraw",
                Map.of("reason", "recorded by both upload screens", "limit", 20000));
        assertThat(withdrawn.getStatusCode().value()).as(String.valueOf(withdrawn.getBody())).isEqualTo(200);
        assertThat(((Number) withdrawn.getBody().get("withdrawn")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE reference = :r").param("r", double1).query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT kept_reference FROM finance.old_payment_withdrawn WHERE reference = :r").param("r", double1).query(String.class).single())
                .isEqualTo(makeUp);
        assertThat(jdbc.sql("SELECT sum(amount) FROM finance.payment_reference WHERE student_id = :s AND session = :ses AND confirmed_at IS NOT NULL")
                .param("s", student).param("ses", ses).query(java.math.BigDecimal.class).single().intValue()).as("each payment once").isEqualTo(120000);

        // an earlier upload recorded the second semester under the old portal's item code: not counted until put right
        String slug = number.replaceAll("[^0-9A-Z]", "");
        String coded = "MOAUM-LEG-" + slug + "-" + year + "-" + (year + 1) + "-S2-10048";
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:s, :ses, :r, '10048 (legacy) · semester 2', 30000, :d::timestamptz, :d::timestamptz, :by, 'Legacy', 'LEG-' || :r, 'Imported from the old portal')
                """).param("s", student).param("ses", ses).param("r", coded).param("d", (year + 1) + "-03-01").param("by", UUID.randomUUID()).update());
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/legacy-fees/item-codes", Map.of("rows", List.of(Map.of("code", "10048", "description", "SCHOOL FEES"))))
                .getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> codes = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/item-codes",
                Map.of("rows", List.of(Map.of("code", "10048", "description", "SCHOOL FEES", "school", "S001"))));
        assertThat(codes.getStatusCode().value()).as(String.valueOf(codes.getBody())).isEqualTo(200);
        ResponseEntity<Map> mislabelled = it.get(audit, "/api/v1/finance/legacy-fees/mislabelled?limit=100000");
        assertThat(mislabelled.getStatusCode().value()).as(String.valueOf(mislabelled.getBody())).isEqualTo(200);
        assertThat((List<Map>) mislabelled.getBody().get("rows")).filteredOn(m -> coded.equals(m.get("reference")))
                .extracting(m -> m.get("action") + ">" + m.get("target_purpose")).containsExactly("RENAME>School fees (legacy) · semester 2");
        ResponseEntity<Map> right = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/mislabelled/put-right",
                Map.of("reason", "recorded under the old portal's payment-item codes", "limit", 20000));
        assertThat(right.getStatusCode().value()).as(String.valueOf(right.getBody())).isEqualTo(200);
        assertThat(((Number) right.getBody().get("renamed")).intValue()).isGreaterThanOrEqualTo(1);
        Map<String, Object> after = ((List<Map<String, Object>>) it.get(audit, "/api/v1/finance/legacy-fees/reconciliation?session=" + ses + "&q=" + number)
                .getBody().get("rows")).get(0);
        assertThat(after).as("the second semester counts now").containsEntry("state", "MATCHED");
        assertThat(((Number) after.get("paid_old_s2")).intValue()).isEqualTo(30000);
    }
}
