package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
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
 * V561 over the API. Two students each have two old-portal first-semester records of ₦85,294 on one day under two payment
 * numbers — the case seen on AWS — against ₦121,849.80 due: both are listed as possible double charges and shown overpaid but held
 * from carrying or refunding until the Bursary checks with the bank. For one the bank received both: the check says so and the
 * excess is carried. For the other it received one: the check names the other, which is raised for withdrawal; the officer who
 * raised it cannot approve it, another rejects only with a note and approves; the record is withdrawn (kept on the withdrawn
 * list, its payment number remembered), the student is told and is no longer overpaid, and loading the export again does not
 * bring it back. Readers read and cannot act; a portal payment, or one whose excess was already carried, is refused; a withdrawal
 * is cancelled only by the officer who raised it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class DoubleChargeIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
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

    /** two old-portal records of ₦85,294 for the first semester, one day, two payment numbers */
    private List<String> charged(UUID student, String number, String payrefA, String payrefB) {
        String key = "MOAUM-LEG-" + number.replaceAll("[^0-9A-Z]", "") + "-" + a.replace("/", "-") + "-S1";
        String first = key;
        String second = key + "-" + payrefB;
        String day = a.substring(0, 4) + "-11-23 09:00:00+01";
        it.db(() -> {
            for (String[] r : new String[][] {{first, payrefA}, {second, payrefB}}) {
                jdbc.sql("""
                        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                        VALUES (:s, :ses, :r, 'School fees (legacy) · semester 1', 85294, CAST(:d AS timestamptz), CAST(:d AS timestamptz), :by, 'Legacy', 'LEG-' || :r,
                                'Imported from the old portal · old ref ' || :p)
                        """).param("s", student).param("ses", a).param("r", r[0]).param("d", day).param("p", r[1]).param("by", UUID.randomUUID()).update();
                jdbc.sql("INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (:p, :r, 85294)").param("p", r[1]).param("r", r[0]).update();
            }
            return null;
        });
        return List.of(first, second);
    }

    private static Map<String, Object> group(Map body, UUID student) {
        return ((List<Map<String, Object>>) body.get("rows")).stream().filter(r -> student.toString().equals(r.get("student_id"))).findFirst().orElse(null);
    }

    @Test
    void aPossibleDoubleChargeIsCheckedWithTheBankBeforeTheExcessIsDecidedAndAPaymentNeverReceivedIsWithdrawn() {
        Random random = new Random();
        int year = it.freeYear(3100, 3180, 0, 1);
        a = year + "/" + (year + 1);
        b = (year + 1) + "/" + (year + 2);
        it.session(a, year);
        it.session(b, year + 1);
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 121849.80, NULL, 'C00023')")
                .param("s", a).update());
        String numR = it.freeNumber("MOAUM/DCR/86/", 6);
        String numN = it.freeNumber("MOAUM/DCN/86/", 6);
        UUID received = it.student(it.freeSurname("ZZDBLR"), "C00023", null, numR, 200);
        UUID notReceived = it.student(it.freeSurname("ZZDBLN"), "C00023", null, numN, 200);
        it.db(() -> jdbc.sql("INSERT INTO people.student_contact (student_id, email, updated_at) VALUES (:s, :e, now()) ON CONFLICT (student_id) DO NOTHING")
                .param("s", notReceived).param("e", "zzdbl" + numN.replaceAll("[^0-9]", "") + "@example.com").update());
        String tag = String.format("%07d", random.nextInt(10_000_000));
        List<String> recR = charged(received, numR, "PR" + year + "1123R" + tag + "1", "PR" + year + "1123R" + tag + "2");
        List<String> recN = charged(notReceived, numN, "PR" + year + "1123N" + tag + "1", "PR" + year + "1123N" + tag + "2");
        String bursar = ItSupport.token("bursar");
        String deputy = ItSupport.token("bursar");
        String audit = ItSupport.token("audit");

        // listed for the session, not yet checked; both overpaid, both waiting for the bank
        ResponseEntity<Map> list = it.get(audit, "/api/v1/finance/legacy-fees/double-charges?session=" + a);
        assertThat(list.getStatusCode().value()).as(String.valueOf(list.getBody())).isEqualTo(200);
        Map<String, Object> gR = group(list.getBody(), received);
        assertThat(gR).isNotNull();
        assertThat(gR).containsEntry("payments", 2).containsEntry("purpose", "School fees (legacy) · semester 1");
        assertThat(gR.get("verdict")).as("not checked with the bank").isNull();
        assertThat(((Number) gR.get("amount")).intValue()).isEqualTo(85294);
        assertThat((List<String>) gR.get("refs")).containsExactlyElementsOf(recR);
        Map<String, Object> over = it.get(audit, "/api/v1/finance/legacy-fees/overpaid?session=" + a).getBody();
        assertThat((List<Map>) over.get("rows")).filteredOn(r -> received.toString().equals(r.get("student_id")) || notReceived.toString().equals(r.get("student_id")))
                .extracting(r -> ((Number) r.get("excess")).doubleValue() + ":" + r.get("double_charge")).containsExactly("48738.2:CHECK_WITH_BANK", "48738.2:CHECK_WITH_BANK");

        // nothing is carried or refunded while the bank has not answered
        Map<String, Object> carryBoth = Map.of("session", a, "decision", "CARRY", "students", List.of(received, notReceived), "reason", "overpaid fees counted towards the next session");
        Map<String, Object> held = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/overpaid/decide", carryBoth).getBody();
        assertThat(held).as(String.valueOf(held)).containsEntry("carried", 0).containsEntry("held", 2).containsEntry("remaining", 0);

        // reading is not checking; a check is the Bursary's, on evidence, and names nothing the bank received
        Map<String, Object> checkR = new LinkedHashMap<>(Map.of("studentId", received, "session", a, "purpose", "School fees (legacy) · semester 1",
                "paidOn", a.substring(0, 4) + "-11-23", "amount", 85294, "verdict", "RECEIVED", "evidence", "Zenith statement, two credits of 85,294 on 23 Nov"));
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", checkR).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> wrong = new LinkedHashMap<>(checkR);
        wrong.put("notReceived", List.of(recR.get(1)));
        ResponseEntity<Map> refusedList = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", wrong);
        assertThat(refusedList.getStatusCode().value()).isEqualTo(422);
        assertThat(refusedList.getBody()).containsEntry("code", "PAY_CHECK_NOT_RECEIVED_LIST");

        // the bank received both: the check says so and the excess is decided
        ResponseEntity<Map> okR = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", checkR);
        assertThat(okR.getStatusCode().value()).as(String.valueOf(okR.getBody())).isEqualTo(200);
        assertThat((List) okR.getBody().get("raised")).isEmpty();
        Map<String, Object> carried = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/overpaid/decide",
                Map.of("session", a, "decision", "CARRY", "students", List.of(received), "reason", "overpaid fees counted towards the next session")).getBody();
        assertThat(carried).as(String.valueOf(carried)).containsEntry("carried", 1).containsEntry("held", 0);
        // a payment whose session's excess was carried is not withdrawn afterwards
        ResponseEntity<Map> decidedAlready = it.call(bursar, HttpMethod.POST, "/api/v1/finance/payments-not-received",
                Map.of("reference", recR.get(1), "evidence", "Zenith statement", "reason", "checking the refusal of a decided excess"));
        assertThat(decidedAlready.getStatusCode().value()).isEqualTo(422);
        assertThat(decidedAlready.getBody()).containsEntry("code", "PAY_NOT_RECEIVED_DECIDED");

        // the bank received one: the other is raised for withdrawal by the check, and the student stays held while it waits
        Map<String, Object> checkN = new LinkedHashMap<>(checkR);
        checkN.put("studentId", notReceived);
        checkN.put("verdict", "NOT_RECEIVED");
        checkN.put("evidence", "Zenith statement 23 Nov: one credit of 85,294 only");
        checkN.put("notReceived", List.of(recN.get(1)));
        ResponseEntity<Map> okN = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/check", checkN);
        assertThat(okN.getStatusCode().value()).as(String.valueOf(okN.getBody())).isEqualTo(200);
        List<String> raised = (List<String>) okN.getBody().get("raised");
        assertThat(raised).hasSize(1);
        String pnr = raised.get(0);
        assertThat(pnr).matches("PNR/[0-9]{4}/[0-9]{6}");
        String path = "/api/v1/finance/payments-not-received/" + pnr.substring("PNR/".length());
        Map<String, Object> mineRow = ((List<Map<String, Object>>) it.get(bursar, "/api/v1/finance/payments-not-received?state=PROPOSED").getBody().get("rows"))
                .stream().filter(r -> pnr.equals(r.get("request_ref"))).findFirst().orElseThrow();
        assertThat(mineRow).containsEntry("mine", true).containsEntry("reference", recN.get(1)).containsEntry("kept_reference", recN.get(0)).containsEntry("from_check", true);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/overpaid/decide",
                Map.of("session", a, "decision", "REFUND", "students", List.of(notReceived), "reason", "overpaid fees returned to the student")).getBody())
                .containsEntry("refunds", 0).containsEntry("held", 1);

        // two people: the one who raised it does not approve it; another rejects only with a note, and approves
        ResponseEntity<Map> self = it.call(bursar, HttpMethod.POST, path + "/decide", Map.of("approve", true));
        assertThat(self.getStatusCode().value()).isEqualTo(403);
        assertThat(self.getBody()).containsEntry("code", "PAY_NOT_RECEIVED_SAME_OFFICER");
        assertThat(it.call(audit, HttpMethod.POST, path + "/decide", Map.of("approve", true)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> bare = it.call(deputy, HttpMethod.POST, path + "/decide", Map.of("approve", false));
        assertThat(bare.getStatusCode().value()).isEqualTo(422);
        assertThat(bare.getBody()).containsEntry("code", "PAY_NOT_RECEIVED_NOTE");
        ResponseEntity<Map> approved = it.call(deputy, HttpMethod.POST, path + "/decide", Map.of("approve", true, "note", "Statement seen"));
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat(approved.getBody()).containsEntry("state", "APPROVED");

        // withdrawn: gone from the record, kept on the withdrawn list, its number remembered, the student told and no longer overpaid
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE reference = :r").param("r", recN.get(1)).query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT double_kind || ':' || kept_reference FROM finance.old_payment_withdrawn WHERE reference = :r").param("r", recN.get(1)).query(String.class).single())
                .isEqualTo("NOT_RECEIVED:" + recN.get(0));
        assertThat(jdbc.sql("SELECT count(*) FROM finance.legacy_payref_withdrawn WHERE reference = :r").param("r", recN.get(1)).query(Long.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE template_key = 'PAYMENT_NOT_RECEIVED_REMOVED' AND about_id = :s AND channel = 'EMAIL'")
                .param("s", notReceived).query(Long.class).single()).isEqualTo(1);
        assertThat((List<Map>) it.get(audit, "/api/v1/finance/legacy-fees/overpaid?session=" + a).getBody().get("rows"))
                .noneMatch(r -> notReceived.toString().equals(r.get("student_id")));
        assertThat(group(it.get(audit, "/api/v1/finance/legacy-fees/double-charges?session=" + a).getBody(), notReceived)).isNull();

        // the export loaded again does not bring it back
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("matric", numN);
        row.put("session", a);
        row.put("semester", "First");
        row.put("level", "200");
        row.put("amount", "85294");
        row.put("purpose", "SCHOOL FEES");
        row.put("paidOn", a.substring(0, 4) + "-11-23");
        row.put("receiptNo", "PR" + year + "1123N" + tag + "2");
        row.put("channel", "Interswitch");
        row.put("note", "");
        ResponseEntity<Map> again = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", List.of(row)));
        assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(200);
        assertThat(again.getBody()).containsEntry("duplicates", 1);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND session = :a").param("s", notReceived).param("a", a)
                .query(Long.class).single()).isEqualTo(1);

        // a portal payment is not withdrawn here; a withdrawal is cancelled only by the one who raised it
        String portalRef = "MOAUM-ITDC-" + tag;
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:s, :a, :r, 'School fees ' || :a, 1000, now(), now(), :by, 'INTERSWITCH', 'RCT-' || :r, 'portal')
                """).param("s", notReceived).param("a", a).param("r", portalRef).param("by", UUID.randomUUID()).update());
        ResponseEntity<Map> portal = it.call(bursar, HttpMethod.POST, "/api/v1/finance/payments-not-received",
                Map.of("reference", portalRef, "evidence", "Zenith statement", "reason", "a portal payment is settled with the gateway"));
        assertThat(portal.getStatusCode().value()).isEqualTo(422);
        assertThat(portal.getBody()).containsEntry("code", "PAY_NOT_RECEIVED_NOT_OLD_PORTAL");
        ResponseEntity<Map> raisedOne = it.call(bursar, HttpMethod.POST, "/api/v1/finance/payments-not-received",
                Map.of("reference", recN.get(0), "evidence", "Zenith statement", "reason", "raised to show who may cancel it"));
        assertThat(raisedOne.getStatusCode().value()).as(String.valueOf(raisedOne.getBody())).isEqualTo(200);
        String other = "/api/v1/finance/payments-not-received/" + ((String) raisedOne.getBody().get("requestRef")).substring("PNR/".length());
        ResponseEntity<Map> notYours = it.call(deputy, HttpMethod.POST, other + "/cancel", Map.of());
        assertThat(notYours.getStatusCode().value()).isEqualTo(403);
        assertThat(notYours.getBody()).containsEntry("code", "PAY_NOT_RECEIVED_NOT_YOURS");
        assertThat(it.call(bursar, HttpMethod.POST, other + "/cancel", Map.of()).getBody()).containsEntry("state", "CANCELLED");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE reference = :r").param("r", recN.get(0)).query(Long.class).single()).isEqualTo(1);
    }
}
