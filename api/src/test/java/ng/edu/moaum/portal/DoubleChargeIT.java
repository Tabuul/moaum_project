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
    @Autowired
    javax.sql.DataSource dataSource;

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
                // V781: the excess (48,738.20) is not the repeated amount (85,294), so the officer confirms the fee setup and the payments were checked
                Map.of("session", a, "decision", "CARRY", "students", List.of(received), "reason", "overpaid fees counted towards the next session", "feeSetupChecked", true)).getBody();
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

        // withdrawn: kept archived for good (V670: a payment is never deleted) and counted nowhere, kept on the withdrawn list, its number
        // remembered, the student told and no longer overpaid
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE reference = :r AND archived_at IS NULL").param("r", recN.get(1)).query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT state FROM finance.payment_archive WHERE reference = :r").param("r", recN.get(1)).query(String.class).single()).isEqualTo("NOT_RECEIVED");
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
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND session = :a AND archived_at IS NULL").param("s", notReceived).param("a", a)
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

    /** V684: two old-portal records of ₦85,294 for the first semester on a day already past, under two payment numbers */
    private List<String> chargedOn(UUID student, String number, String day, String payrefA, String payrefB) {
        String first = "MOAUM-LEG-" + number.replaceAll("[^0-9A-Z]", "") + "-" + a.replace("/", "-") + "-S1";
        String second = first + "-" + payrefB;
        it.db(() -> {
            for (String[] r : new String[][] {{first, payrefA}, {second, payrefB}}) {
                jdbc.sql("""
                        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                        VALUES (:s, :ses, :r, 'School fees (legacy) · semester 1', 85294, CAST(:d AS timestamptz), CAST(:d AS timestamptz), :by, 'Legacy', 'LEG-' || :r,
                                'Imported from the old portal · old ref ' || :p)
                        """).param("s", student).param("ses", a).param("r", r[0]).param("d", day + " 09:00:00+01").param("p", r[1]).param("by", UUID.randomUUID()).update();
                jdbc.sql("INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (:p, :r, 85294)").param("p", r[1]).param("r", r[0]).update();
            }
            return null;
        });
        return List.of(first, second);
    }

    @Test
    void theBanksListChecksThePossibleDoubleChargesOfItsDaysAtOnceAndAnotherOfficerDecidesItsWithdrawals() {
        Random random = new Random();
        int year = it.freeYear(3181, 3199, 0, 1);
        a = year + "/" + (year + 1);
        it.session(a, year);
        java.time.LocalDate day = java.time.LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).minusDays(10);
        String numR = it.freeNumber("MOAUM/BLR/86/", 6);
        String numN = it.freeNumber("MOAUM/BLN/86/", 6);
        UUID received = it.student(it.freeSurname("ZZBLCR"), "C00023", null, numR, 200);
        UUID notReceived = it.student(it.freeSurname("ZZBLCN"), "C00023", null, numN, 200);
        String tag = String.format("%07d", random.nextInt(10_000_000));
        String pR1 = "PR" + year + "R" + tag + "1", pR2 = "PR" + year + "R" + tag + "2", pN1 = "PR" + year + "N" + tag + "1", pN2 = "PR" + year + "N" + tag + "2";
        chargedOn(received, numR, day.toString(), pR1, pR2);
        List<String> recN = chargedOn(notReceived, numN, day.toString(), pN1, pN2);
        String bursar = ItSupport.token("bursar");
        String deputy = ItSupport.token("bursar");
        String audit = ItSupport.token("audit");

        // the gateway's report shows both of one student's payments and one of the other's (written as a report writes them)
        Map<String, Object> list = new LinkedHashMap<>();
        list.put("session", a);
        list.put("from", day.minusDays(3).toString());
        list.put("to", day.plusDays(3).toString());
        list.put("numbers", List.of(Map.of("n", pR1.toLowerCase()), Map.of("n", pR2, "a", "85294"), Map.of("n", pN1, "a", "85,294.00")));
        list.put("evidence", "Interswitch collections report, MOAU fees account");
        list.put("fileName", "collections.xlsx");
        list.put("rowsRead", 3);

        // reading the list is the Bursary's; the preview judges each group and writes nothing
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/bank-list/preview", list).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> preview = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/bank-list/preview", list);
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) preview.getBody().get("counts")).containsEntry("RECEIVED", 1).containsEntry("NOT_RECEIVED", 1);
        assertThat(preview.getBody()).containsEntry("toWithdraw", 1);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.double_charge_check WHERE student_id IN (:a, :b)").param("a", received).param("b", notReceived)
                .query(Long.class).single()).isZero();

        // recorded: each group checked from the list, the record not on it raised for withdrawal beside the one that is
        ResponseEntity<Map> recorded = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/bank-list", list);
        assertThat(recorded.getStatusCode().value()).as(String.valueOf(recorded.getBody())).isEqualTo(200);
        String ref = (String) recorded.getBody().get("listRef");
        assertThat(ref).matches("BLC/[0-9]{4}/[0-9]{6}");
        assertThat((Map<String, Object>) recorded.getBody().get("outcomes")).containsEntry("RECEIVED", 1).containsEntry("NOT_RECEIVED", 1).containsEntry("raised", 1);
        Map<String, Object> gR = group(it.get(audit, "/api/v1/finance/legacy-fees/double-charges?session=" + a).getBody(), received);
        assertThat(gR).containsEntry("verdict", "RECEIVED");
        String path = "/api/v1/finance/legacy-fees/bank-lists/" + ref.substring("BLC/".length());
        Map<String, Object> shown = it.get(audit, path).getBody();
        Map<String, Object> rowN = ((List<Map<String, Object>>) shown.get("rows")).stream().filter(r -> notReceived.toString().equals(r.get("student_id"))).findFirst().orElseThrow();
        assertThat(rowN).containsEntry("outcome", "NOT_RECEIVED").containsEntry("missing", List.of(recN.get(1))).containsEntry("found", List.of(recN.get(0)));
        assertThat((List<Map<String, Object>>) rowN.get("withdrawals")).extracting(w -> w.get("reference") + ":" + w.get("state")).containsExactly(recN.get(1) + ":PROPOSED");
        Map<String, Object> listed = ((List<Map<String, Object>>) it.get(bursar, "/api/v1/finance/legacy-fees/bank-lists").getBody().get("rows")).stream()
                .filter(r -> ref.equals(r.get("list_ref"))).findFirst().orElseThrow();
        assertThat(listed).containsEntry("mine", true);
        assertThat((Map<String, Object>) listed.get("withdrawals")).containsEntry("PROPOSED", 1);

        // decided together, by another officer; a rejection says why
        ResponseEntity<Map> self = it.call(bursar, HttpMethod.POST, path + "/decide", Map.of("action", "APPROVE"));
        assertThat(self.getStatusCode().value()).isEqualTo(403);
        assertThat(self.getBody()).containsEntry("code", "BANK_LIST_SAME_OFFICER");
        assertThat(it.call(audit, HttpMethod.POST, path + "/decide", Map.of("action", "APPROVE")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> bare = it.call(deputy, HttpMethod.POST, path + "/decide", Map.of("action", "REJECT"));
        assertThat(bare.getStatusCode().value()).isEqualTo(422);
        assertThat(bare.getBody()).containsEntry("code", "BANK_LIST_NOTE");
        ResponseEntity<Map> approved = it.call(deputy, HttpMethod.POST, path + "/decide", Map.of("action", "APPROVE", "note", "Report seen"));
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat(approved.getBody()).containsEntry("done", 1).containsEntry("refused", 0);

        // the record the bank never received is archived, never deleted, and the student is no longer listed
        assertThat(jdbc.sql("SELECT state FROM finance.payment_archive WHERE reference = :r").param("r", recN.get(1)).query(String.class).single()).isEqualTo("NOT_RECEIVED");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE reference = :r").param("r", recN.get(1)).query(Long.class).single()).isEqualTo(1);
        assertThat(group(it.get(audit, "/api/v1/finance/legacy-fees/double-charges?session=" + a).getBody(), notReceived)).isNull();
        ResponseEntity<Map> nothing = it.call(deputy, HttpMethod.POST, path + "/decide", Map.of("action", "APPROVE"));
        assertThat(nothing.getStatusCode().value()).isEqualTo(422);
        assertThat(nothing.getBody()).containsEntry("code", "BANK_LIST_NOTHING_WAITING");
    }

    /** V762's second review: two old-portal SIWES records of ₦4,000 for the second semester on a day already past, two payment numbers */
    private List<String> siwesOn(UUID student, String number, String day, String payrefA, String payrefB) {
        String first = "MOAUM-LEG-" + number.replaceAll("[^0-9A-Z]", "") + "-" + a.replace("/", "-") + "-S2-SIWES";
        String second = first + "-" + payrefB;
        it.db(() -> {
            for (String[] r : new String[][] {{first, payrefA}, {second, payrefB}}) {
                jdbc.sql("""
                        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                        VALUES (:s, :ses, :r, 'SIWES (legacy) · semester 2', 4000, CAST(:d AS timestamptz), CAST(:d AS timestamptz), :by, 'Legacy', 'LEG-' || :r,
                                'Imported from the old portal · old ref ' || :p)
                        """).param("s", student).param("ses", a).param("r", r[0]).param("d", day + " 09:00:00+01").param("p", r[1]).param("by", UUID.randomUUID()).update();
                jdbc.sql("INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (:p, :r, 4000)").param("p", r[1]).param("r", r[0]).update();
            }
            return null;
        });
        return List.of(first, second);
    }

    /**
     * The door called while a connection of the test's own holds {@code reference}'s row, as a write that locks a SIWES payment's row
     * first does (the old fees reset, an upload). Once the door waits on that row, the connection takes {@code student}'s SIWES lock of
     * the session, which the door holds already: a deadlock. PostgreSQL ends the door's transaction, which waited first (where the role
     * may, the holder's deadlock_timeout is set long, so it is never the one ended); the connection then has the lock — proof that the
     * door's transaction was ended under it — and lets go. Returns the door's answer.
     */
    private ResponseEntity<Map> deadlocked(java.util.function.Supplier<ResponseEntity<Map>> door, String reference, UUID student) throws Exception {
        return clash(door, holder -> {
            try (java.sql.PreparedStatement p = holder.prepareStatement("SELECT 1 FROM finance.payment_reference WHERE reference = ? FOR UPDATE")) {
                p.setString(1, reference);
                p.executeQuery().close();
            }
        }, holder -> {
            try (java.sql.PreparedStatement p = holder.prepareStatement("SELECT finance.siwes_lock(?, ?)")) {
                p.setObject(1, student);
                p.setString(2, a);
                p.executeQuery().close();
            }
        });
    }

    /** one statement of the holder's, on its own connection */
    @FunctionalInterface
    private interface Hold {
        void on(java.sql.Connection holder) throws java.sql.SQLException;
    }

    /**
     * The door called while a connection of the test's own has done {@code first}; once the door waits on what that holds, the
     * connection does {@code then}, which waits on what the door holds already: a deadlock. PostgreSQL ends the door's transaction,
     * which waited first (where the role may, the holder's deadlock_timeout is set long, so it is never the one ended); the connection's
     * {@code then} goes through only once the door's transaction is ended under it, and the connection lets go. Returns the door's answer.
     */
    private ResponseEntity<Map> clash(java.util.function.Supplier<ResponseEntity<Map>> door, Hold first, Hold then) throws Exception {
        java.util.concurrent.ExecutorService pool = java.util.concurrent.Executors.newFixedThreadPool(2);
        try (java.sql.Connection holder = dataSource.getConnection()) {
            holder.setAutoCommit(false);
            try {
                int pid;
                try (java.sql.Statement s = holder.createStatement()) {
                    s.execute("SELECT set_config('deadlock_timeout', '60s', true) FROM pg_roles WHERE rolname = current_user AND rolsuper");
                    try (java.sql.ResultSet r = s.executeQuery("SELECT pg_backend_pid()")) {
                        r.next();
                        pid = r.getInt(1);
                    }
                }
                first.on(holder);
                java.util.concurrent.Future<ResponseEntity<Map>> answer = pool.submit(door::get);
                boolean waiting = false;
                for (int i = 0; i < 1200 && !waiting; i++) {   // up to a minute
                    waiting = jdbc.sql("SELECT EXISTS (SELECT 1 FROM pg_locks l WHERE NOT l.granted AND CAST(:pid AS int) = ANY (pg_blocking_pids(l.pid)))")
                            .param("pid", pid).query(Boolean.class).single();
                    if (!waiting) Thread.sleep(50);
                }
                assertThat(waiting).as("the door waits on what the connection holds").isTrue();
                java.util.concurrent.Future<Object> closed = pool.submit(() -> {
                    then.on(holder);
                    holder.rollback();
                    return null;
                });
                closed.get(60, java.util.concurrent.TimeUnit.SECONDS);
                return answer.get(120, java.util.concurrent.TimeUnit.SECONDS);
            } finally {
                holder.rollback();
            }
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void aDeadlockInTheBankListOrInTheDecisionOfItsWithdrawalsIsRunAgainNeverRecordedAsARefusal() throws Exception {
        Random random = new Random();
        int year = it.freeYear(3181, 3199, 0, 1);
        a = year + "/" + (year + 1);
        it.session(a, year);
        java.time.LocalDate day = java.time.LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).minusDays(12);
        String numR = it.freeNumber("MOAUM/BLD/86/", 6);
        String numN = it.freeNumber("MOAUM/BLS/86/", 6);
        UUID received = it.student(it.freeSurname("ZZBLDR"), "C00023", null, numR, 300);
        UUID notReceived = it.student(it.freeSurname("ZZBLDS"), "C00023", null, numN, 300);
        String tag = String.format("%07d", random.nextInt(10_000_000));
        String pR1 = "PD" + year + "R" + tag + "1", pR2 = "PD" + year + "R" + tag + "2", pN1 = "PD" + year + "S" + tag + "1", pN2 = "PD" + year + "S" + tag + "2";
        chargedOn(received, numR, day.toString(), pR1, pR2);
        List<String> recN = siwesOn(notReceived, numN, day.toString(), pN1, pN2);
        String bursar = ItSupport.token("bursar");
        String deputy = ItSupport.token("bursar");

        Map<String, Object> list = new LinkedHashMap<>();
        list.put("session", a);
        list.put("from", day.minusDays(1).toString());
        list.put("to", day.plusDays(1).toString());
        list.put("numbers", List.of(Map.of("n", pR1), Map.of("n", pR2), Map.of("n", pN1)));
        list.put("evidence", "Bank statement of the fees account (deadlock)");
        long before = jdbc.sql("SELECT CASE WHEN is_called THEN last_value ELSE last_value - 1 END FROM finance.bank_list_check_seq").query(Long.class).single();

        // the list meets a deadlock raising the withdrawal of the SIWES record not on it: ended whole and run again by its door
        ResponseEntity<Map> recorded = deadlocked(() -> it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/bank-list", list),
                recN.get(1), notReceived);
        assertThat(recorded.getStatusCode().value()).as(String.valueOf(recorded.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) recorded.getBody().get("outcomes")).containsEntry("RECEIVED", 1).containsEntry("NOT_RECEIVED", 1).containsEntry("raised", 1)
                .doesNotContainKey("REFUSED");
        String ref = (String) recorded.getBody().get("listRef");
        assertThat(Long.parseLong(ref.substring(ref.lastIndexOf('/') + 1))).as("the first try's list number spent: the door ran it again")
                .isGreaterThanOrEqualTo(before + 2);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.bank_list_group WHERE student_id = :s AND outcome = 'REFUSED'").param("s", notReceived)
                .query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT state FROM finance.payment_not_received WHERE reference = :r").param("r", recN.get(1)).query(String.class).list())
                .containsExactly("PROPOSED");

        // its withdrawal approved by another officer meets the same deadlock: ended whole and run again, never refused
        String path = "/api/v1/finance/legacy-fees/bank-lists/" + ref.substring("BLC/".length());
        ResponseEntity<Map> approved = deadlocked(() -> it.call(deputy, HttpMethod.POST, path + "/decide", Map.of("action", "APPROVE", "note", "Statement seen")),
                recN.get(1), notReceived);
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat(approved.getBody()).containsEntry("done", 1).containsEntry("refused", 0);
        assertThat(jdbc.sql("SELECT state FROM finance.payment_not_received WHERE reference = :r").param("r", recN.get(1)).query(String.class).single())
                .isEqualTo("APPROVED");
        assertThat(jdbc.sql("SELECT state FROM finance.payment_archive WHERE reference = :r").param("r", recN.get(1)).query(String.class).single())
                .isEqualTo("NOT_RECEIVED");
    }

    /**
     * V762's third review (d62c-1): a SIWES withdrawal cancelled by the officer who raised it locks the withdrawal's row, then releases
     * the record under the student's SIWES lock (the withdrawal's trigger). Here the test's own connection holds that lock and, once the
     * cancellation waits on it, asks for the withdrawal's row: a deadlock, which ended the cancellation with an error the officer saw
     * while its door was not run again. Now the door runs it again and the withdrawal is cancelled.
     */
    @Test
    void aDeadlockCancellingAWithdrawalIsRunAgain() throws Exception {
        Random random = new Random();
        int year = it.freeYear(3181, 3199, 0, 1);
        a = year + "/" + (year + 1);
        it.session(a, year);
        java.time.LocalDate day = java.time.LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).minusDays(12);
        String numN = it.freeNumber("MOAUM/BLX/86/", 6);
        UUID notReceived = it.student(it.freeSurname("ZZBLXS"), "C00023", null, numN, 300);
        String tag = String.format("%07d", random.nextInt(10_000_000));
        String pN1 = "PD" + year + "X" + tag + "1", pN2 = "PD" + year + "X" + tag + "2";
        List<String> recN = siwesOn(notReceived, numN, day.toString(), pN1, pN2);
        String bursar = ItSupport.token("bursar");

        Map<String, Object> list = new LinkedHashMap<>();
        list.put("session", a);
        list.put("from", day.minusDays(1).toString());
        list.put("to", day.plusDays(1).toString());
        list.put("numbers", List.of(Map.of("n", pN1)));
        list.put("evidence", "Bank statement of the fees account (cancel)");
        ResponseEntity<Map> recorded = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/double-charges/bank-list", list);
        assertThat(recorded.getStatusCode().value()).as(String.valueOf(recorded.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) recorded.getBody().get("outcomes")).containsEntry("NOT_RECEIVED", 1).containsEntry("raised", 1);
        String request = jdbc.sql("SELECT request_ref FROM finance.payment_not_received WHERE reference = :r AND state = 'PROPOSED'")
                .param("r", recN.get(1)).query(String.class).single();

        // the officer who recorded the list cancels the withdrawal it raised while the student's SIWES lock is held and the holder then
        // asks for the withdrawal's row: the cancellation is ended whole and run again by its door
        ResponseEntity<Map> cancelled = clash(() -> it.call(bursar, HttpMethod.POST, "/api/v1/finance/payments-not-received/" + request.substring("PNR/".length()) + "/cancel", Map.of()),
                holder -> {
                    try (java.sql.PreparedStatement p = holder.prepareStatement("SELECT finance.siwes_lock(?, ?)")) {
                        p.setObject(1, notReceived);
                        p.setString(2, a);
                        p.executeQuery().close();
                    }
                }, holder -> {
                    try (java.sql.PreparedStatement p = holder.prepareStatement("SELECT 1 FROM finance.payment_not_received WHERE request_ref = ? FOR UPDATE")) {
                        p.setString(1, request);
                        p.executeQuery().close();
                    }
                });
        assertThat(cancelled.getStatusCode().value()).as(String.valueOf(cancelled.getBody())).isEqualTo(200);
        assertThat(cancelled.getBody()).containsEntry("requestRef", request).containsEntry("state", "CANCELLED");
        assertThat(jdbc.sql("SELECT state FROM finance.payment_not_received WHERE request_ref = :r").param("r", request).query(String.class).single())
                .isEqualTo("CANCELLED");
    }
}
