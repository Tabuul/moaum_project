package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
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
 * V727 — the inter-departmental transfer fee read against every verified payment, through the API. The Bursary states a fee of the
 * test's own; two programmes of the test's own in two departments of a faculty. A student who paid half of it on the old portal (an
 * imported FORM payment, in scope) holds a credit until they apply; applied, the payment counts toward the application (PART_PAID,
 * the balance owed); the current HOD, the new HOD and the Registry act on the part payment; the Academic Office's final approval is
 * refused while the balance is owed (TRANSFER_FEE_OUTSTANDING) and while the reference for it awaits the bank
 * (TRANSFER_PAYMENT_PENDING); the reference drawn is for the balance alone, the same one twice, and renewed when it expires;
 * confirmed, the final approval effects the transfer against the fee as stated. A student who paid nothing waits for the current
 * HOD; the reference they draw for the whole fee is closed when an officer links an old-portal payment that changes the balance —
 * never taken to a gateway (TRANSFER_REFERENCE_STALE), renewed as a new one for the balance — and their application, declined,
 * owes nothing more (band CLOSED). An old-portal payment filed under
 * another matriculation number is unmatched and rejected by the Bursary with a reason. The old portal's export loads an application
 * at the stage it reached and counts the payment its payment number names. The monitor bands and bounds the applications; the
 * report reads the list; ₦0 is never a fee. The fee is put back as found. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class TransferFeeBalanceIT {

    /** the test's own fee, and half of it — the old portal's form payment */
    static final BigDecimal FEE = new BigDecimal("24000");
    static final BigDecimal HALF = new BigDecimal("12000");

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final UUID bursarId = UUID.randomUUID();
    final String bursar = TestTokens.token(bursarId, List.of("bursar"));
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String studentAccounts = ItSupport.token("studentaccounts");
    final String housing = ItSupport.token("housing");
    Object feeBefore;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        feeBefore = jdbc.sql("SELECT transfer_fee FROM finance.fee_setting WHERE id = 1").query().singleRow().get("transfer_fee");
        ResponseEntity<Map> set = it.call(bursar, HttpMethod.PUT, "/api/v1/finance/transfer-fee", Map.of("amount", FEE));
        assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
    }

    @AfterEach
    void putTheFeeBack() {
        it.db(() -> jdbc.sql("UPDATE finance.fee_setting SET transfer_fee = :f WHERE id = 1").param("f", feeBefore, Types.NUMERIC).update());
    }

    private static Object code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : r.getBody().get("code");
    }

    private static BigDecimal money(Object o) {
        return o == null ? null : new BigDecimal(String.valueOf(o));
    }

    /** an old-portal transfer payment imported onto the student's record as the old portal's import writes it — channel Legacy, the
     *  item before " (legacy)", the payment number at the end of the note — paid some days after the date the exercise counts from */
    UUID legacyPayment(UUID student, String referenceMatric, String item, BigDecimal amount, String payref, int daysIntoScope) {
        String key = referenceMatric.toUpperCase().replaceAll("[^A-Z0-9]", "");
        String reference = "MOAUM-LEG-" + key + "-IDT-" + payref;
        return it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at,
                                                       confirmed_by, channel, receipt_no, note)
                SELECT st.id, st.entry_session, :ref, :purpose, :amt, x.at, x.at, x.at, gen_random_uuid(), 'Legacy', 'LEG-' || :ref,
                       'Imported from the old portal · E-Wallet · old ref ' || :payref
                  FROM people.student st,
                       LATERAL (SELECT ((g.counts_from + CAST(:days AS int))::timestamp + interval '12 hours') AT TIME ZONE 'Africa/Lagos' AS at
                                  FROM people.legacy_transfer_setting g WHERE g.id = 1) x
                 WHERE st.id = :s
                RETURNING id
                """).param("s", student).param("ref", reference).param("purpose", item + " (legacy) · semester 1").param("amt", amount)
                .param("payref", payref).param("days", daysIntoScope).query(UUID.class).single());
    }

    String student(UUID id) {
        return TestTokens.token(id, List.of("student"));
    }

    Map<String, Object> mine(UUID student) {
        ResponseEntity<Map> r = it.get(student(student), "/api/v1/me/transfer");
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    Map<String, Object> row(String token, String application) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/transfers");
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return ((List<Map<String, Object>>) r.getBody().get("rows")).stream().filter(x -> application.equals(x.get("id"))).findFirst()
                .orElseThrow(() -> new AssertionError("no row for " + application));
    }

    ResponseEntity<Map> approve(String token, String application) {
        return it.call(token, HttpMethod.POST, "/api/v1/transfers/" + application + "/approve", Map.of());
    }

    /** the student's own reference renewed (V635's door, finance.renew_reference) */
    ResponseEntity<Map> renew(UUID student, String reference) {
        return it.call(student(student), HttpMethod.POST, "/api/v1/me/fees/references/" + reference + "/renew", Map.of());
    }

    /** the student's own reference taken to a gateway */
    ResponseEntity<Map> checkout(UUID student, String reference) {
        return it.call(student(student), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", reference));
    }

    Map<String, Object> summary(String token, String search) {
        ResponseEntity<Map> r = it.get(token, u -> u.path("/api/v1/transfers/fees/summary").queryParam("session", "ALL").queryParam("search", search).build());
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @Test
    void theTransferFeeIsReadAgainstEveryVerifiedPaymentAndTheFinalApprovalWaitsForTheWhole() {
        // ── two programmes of the test's own, in two live departments of a faculty, and a third department ──
        String hex = UUID.randomUUID().toString().replaceAll("[^a-f]", "").toUpperCase() + "ABCDEFABCDEF";
        String segA = "V" + hex.substring(0, 2), segB = "U" + hex.substring(2, 4);
        String[] place = it.db(() -> {
            String[] one = jdbc.sql("""
                    SELECT p1.dept_code || ',' || p2.dept_code || ',' || p1.faculty_code
                      FROM ref.programme p1 JOIN ref.programme p2 ON p2.faculty_code = p1.faculty_code AND p2.dept_code > p1.dept_code
                      JOIN ref.faculty f ON f.code = p1.faculty_code
                      JOIN ref.department d1 ON d1.code = p1.dept_code AND d1.ended_on IS NULL
                      JOIN ref.department d2 ON d2.code = p2.dept_code AND d2.ended_on IS NULL
                     WHERE p1.category = 'UNDER GRADUATE' AND p2.category = 'UNDER GRADUATE' AND NOT p1.archived AND NOT p2.archived
                       AND coalesce(f.college_code, '') <> 'CHS'
                     ORDER BY p1.faculty_code, p1.dept_code, p2.dept_code LIMIT 1
                    """).query(String.class).single().split(",");
            String other = jdbc.sql("SELECT d.code FROM ref.department d WHERE d.ended_on IS NULL AND d.code NOT IN (:a, :b) ORDER BY d.code LIMIT 1")
                    .param("a", one[0]).param("b", one[1]).query(String.class).single();
            List<String> codes = jdbc.sql("SELECT 'C' || x FROM generate_series(96500, 96999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 2")
                    .query(String.class).list();
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years, matric_code) VALUES
                        (:a, 'B.Sc. Transfer Fee Test A ' || :a, :da, :f, 'UNDER GRADUATE', 0, 400, 4, :sa),
                        (:b, 'B.Sc. Transfer Fee Test B ' || :b, :db, :f, 'UNDER GRADUATE', 0, 400, 4, :sb)
                    """).param("a", codes.get(0)).param("b", codes.get(1)).param("da", one[0]).param("db", one[1]).param("f", one[2])
                    .param("sa", segA).param("sb", segB).update();
            return new String[] {one[0], one[1], one[2], codes.get(0), codes.get(1), other};
        });
        String deptA = place[0], deptB = place[1], fac = place[2].toUpperCase(), pa = place[3], pb = place[4], deptC = place[5];
        String hodA = it.officer("hod", "department", deptA), hodB = it.officer("hod", "department", deptB), hodC = it.officer("hod", "department", deptC);
        // four students no earlier run made: their numbers and surnames drawn from one number, four digits each
        String series = "MOAU/" + fac + "/" + segA + "/25/";
        int n = it.freeDraw(1000, 9000, k -> List.of(series + k, series + (k + 1), series + (k + 2), series + (k + 3),
                "MOAUM/ADM/25/71" + k, "MOAUM/ADM/25/72" + k, "MOAUM/ADM/25/73" + k, "MOAUM/ADM/25/74" + k,
                "ZZIDTPART" + k, "ZZIDTNONE" + k, "ZZIDTOTHER" + k, "ZZIDTLOAD" + k));
        String m1 = series + n, m2 = series + (n + 1), m3 = series + (n + 2), m4 = series + (n + 3);
        UUID s1 = it.student("ZZIDTPART" + n, pa, "MOAUM/ADM/25/71" + n, m1, 200);
        UUID s2 = it.student("ZZIDTNONE" + n, pa, "MOAUM/ADM/25/72" + n, m2, 200);
        UUID s3 = it.student("ZZIDTOTHER" + n, pa, "MOAUM/ADM/25/73" + n, m3, 200);
        UUID s4 = it.student("ZZIDTLOAD" + n, pa, "MOAUM/ADM/25/74" + n, m4, 200);
        String tag = Integer.toHexString(new Random().nextInt(0x100000, 0xFFFFFF)).toUpperCase();
        String pr1 = "PR" + tag + "01", pr2 = "PR" + tag + "02", pr3 = "PR" + tag + "03", pr4 = "PR" + tag + "04";

        // ── the fee as stated: ₦0 is never one; the statement kept, newest first ──
        ResponseEntity<Map> zero = it.call(bursar, HttpMethod.PUT, "/api/v1/finance/transfer-fee", Map.of("amount", 0));
        assertThat(zero.getStatusCode().value()).as(String.valueOf(zero.getBody())).isEqualTo(400);
        assertThat(money(it.get(bursar, "/api/v1/finance/transfer-fee").getBody().get("amount"))).isEqualByComparingTo(FEE);
        ResponseEntity<List> revisions = it.getList(bursar, "/api/v1/finance/transfer-fee/revisions");
        assertThat(revisions.getStatusCode().value()).isEqualTo(200);
        assertThat(money(((Map<String, Object>) revisions.getBody().get(0)).get("fee"))).isEqualByComparingTo(FEE);

        // ── half the fee paid on the old portal: a credit until the student applies ──
        UUID p1 = legacyPayment(s1, m1, "INTER DEPARTMENTAL TRANFER FORM", HALF, pr1, 30);
        ResponseEntity<Map> rebuilt = it.call(bursar, HttpMethod.POST, "/api/v1/transfers/legacy/reconcile", Map.of());
        assertThat(rebuilt.getStatusCode().value()).as(String.valueOf(rebuilt.getBody())).isEqualTo(200);
        assertThat(((List<Map<String, Object>>) it.get(bursar, u -> u.path("/api/v1/transfers/legacy").queryParam("search", pr1).build()).getBody().get("rows")))
                .extracting(x -> x.get("payment_id"), x -> x.get("status"), x -> x.get("item_kind"))
                .containsExactly(org.assertj.core.groups.Tuple.tuple(p1.toString(), "AWAITING_APPLICATION", "FORM"));
        Map<String, Object> before = mine(s1);
        assertThat(before.get("payment")).isNull();
        Map<String, Object> credit = (Map<String, Object>) before.get("credit");
        assertThat(money(credit.get("total"))).isEqualByComparingTo(HALF);
        assertThat((List<Map<String, Object>>) credit.get("payments")).extracting(x -> x.get("payref")).containsExactly(pr1);

        // ── applied: the old-portal payment counts toward the application — part paid, the balance owed ──
        ResponseEntity<Map> applied = it.call(student(s1), HttpMethod.POST, "/api/v1/me/transfer", Map.of("toProgramme", pb, "reason", "A stronger interest in the field"));
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        String a1 = String.valueOf(applied.getBody().get("id"));
        Map<String, Object> view = mine(s1);
        Map<String, Object> pay = (Map<String, Object>) view.get("payment");
        assertThat(pay).containsEntry("applicationId", a1).containsEntry("state", "APPLIED").containsEntry("band", "PART_PAID")
                .containsEntry("nextAction", "PAY_BALANCE").containsEntry("stageLabel", "With current department").containsEntry("pending", false);
        assertThat(money(pay.get("feeDue"))).isEqualByComparingTo(FEE);
        assertThat(money(pay.get("oldPortalPaid"))).isEqualByComparingTo(HALF);
        assertThat(money(pay.get("portalPaid"))).isEqualByComparingTo("0");
        assertThat(money(pay.get("balance"))).isEqualByComparingTo(HALF);
        assertThat(view.get("credit")).isNull();
        List<Map<String, Object>> made = (List<Map<String, Object>>) view.get("paymentsMade");
        assertThat(made).hasSize(1);
        assertThat(made.get(0)).containsEntry("source", "OLD_PORTAL").containsEntry("payref", pr1).containsEntry("status", "LINKED")
                .containsEntry("item", "INTER DEPARTMENTAL TRANFER FORM");

        // ── the desks act on the part payment: the current HOD, the new HOD, the Registry ──
        assertThat(row(hodA, a1)).containsEntry("canApprove", true).containsEntry("band", "PART_PAID");
        assertThat(row(hodC, a1)).containsEntry("canApprove", false);
        ResponseEntity<Map> fromOk = approve(hodA, a1);
        assertThat(fromOk.getStatusCode().value()).as(String.valueOf(fromOk.getBody())).isEqualTo(200);
        assertThat(fromOk.getBody()).containsEntry("state", "FROM_OK");
        assertThat(approve(hodB, a1).getBody()).containsEntry("state", "TO_OK");
        assertThat(approve(registrar, a1).getBody()).containsEntry("state", "REG_OK");

        // ── at the Academic Office the balance is named, and the final approval waits for it ──
        Map<String, Object> atAcademic = row(academic, a1);
        assertThat(atAcademic).containsEntry("canApprove", false).containsEntry("canDecline", true)
                .containsEntry("stageLabel", "With Academic office — ₦12,000 outstanding");
        assertThat(money(atAcademic.get("balance"))).isEqualByComparingTo(HALF);
        assertThat(row(bursar, a1)).containsEntry("canApprove", false);
        ResponseEntity<Map> owing = approve(academic, a1);
        assertThat(owing.getStatusCode().value()).as(String.valueOf(owing.getBody())).isEqualTo(422);
        assertThat(code(owing)).isEqualTo("TRANSFER_FEE_OUTSTANDING");

        // ── the monitor: the Bursary reads it, the departments either side read their own, another department nothing ──
        assertThat(it.get(housing, "/api/v1/transfers/fees/summary").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> monitor = it.get(bursar, u -> u.path("/api/v1/transfers/fees").queryParam("session", "ALL").queryParam("search", m1).build());
        assertThat(monitor.getStatusCode().value()).as(String.valueOf(monitor.getBody())).isEqualTo(200);
        List<Map<String, Object>> monitored = (List<Map<String, Object>>) monitor.getBody().get("rows");
        assertThat(monitored).hasSize(1);
        assertThat(monitored.get(0)).containsEntry("application_id", a1).containsEntry("band", "PART_PAID").containsEntry("awaiting", "PAYMENT")
                .containsEntry("state", "REG_OK");
        assertThat(money(monitored.get(0).get("old_portal_paid"))).isEqualByComparingTo(HALF);
        ResponseEntity<Map> summary = it.get(bursar, u -> u.path("/api/v1/transfers/fees/summary").queryParam("session", "ALL").queryParam("search", m1).build());
        assertThat(summary.getStatusCode().value()).as(String.valueOf(summary.getBody())).isEqualTo(200);
        assertThat(money(summary.getBody().get("fee"))).isEqualByComparingTo(FEE);
        assertThat(((Number) summary.getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) ((Map<String, Object>) summary.getBody().get("bands")).get("PART_PAID")).intValue()).isEqualTo(1);
        assertThat(((Number) ((Map<String, Object>) summary.getBody().get("awaiting")).get("PAYMENT")).intValue()).isEqualTo(1);
        assertThat(money(summary.getBody().get("outstanding"))).isEqualByComparingTo(HALF);
        assertThat(money(summary.getBody().get("collectedOldPortal"))).isEqualByComparingTo(HALF);
        assertThat(((Number) summary.getBody().get("readyForFinalApproval")).intValue()).isZero();
        assertThat(((Number) summary.getBody().get("stillOwing")).intValue()).isEqualTo(1);
        assertThat(((Number) summary.getBody().get("notPaid")).intValue()).isZero();
        assertThat(((Number) it.get(hodA, u -> u.path("/api/v1/transfers/fees").queryParam("session", "ALL").queryParam("search", m1).build()).getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) it.get(hodB, u -> u.path("/api/v1/transfers/fees").queryParam("session", "ALL").queryParam("search", m1).build()).getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) it.get(hodC, u -> u.path("/api/v1/transfers/fees").queryParam("session", "ALL").queryParam("search", m1).build()).getBody().get("total")).intValue()).isZero();
        ResponseEntity<Map> exported = it.call(bursar, HttpMethod.POST, "/api/v1/transfers/fees/export", Map.of("format", "XLSX", "session", "ALL", "search", m1));
        assertThat(exported.getStatusCode().value()).as(String.valueOf(exported.getBody())).isEqualTo(200);
        assertThat(((Number) exported.getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.report_export WHERE report = 'TRANSFER_FEES' AND exported_by = :b AND row_count = 1")
                .param("b", bursarId).query(Long.class).single()).isEqualTo(1L);

        // ── the reference is for the balance alone, the same one twice; while it awaits the bank the final approval waits too ──
        ResponseEntity<Map> drawn = it.call(student(s1), HttpMethod.POST, "/api/v1/me/transfer/" + a1 + "/fee", Map.of());
        assertThat(drawn.getStatusCode().value()).as(String.valueOf(drawn.getBody())).isEqualTo(200);
        String reference = String.valueOf(drawn.getBody().get("reference"));
        assertThat(money(drawn.getBody().get("amount"))).isEqualByComparingTo(HALF);
        assertThat(it.call(student(s1), HttpMethod.POST, "/api/v1/me/transfer/" + a1 + "/fee", Map.of()).getBody()).containsEntry("reference", reference);
        // expired, it awaits the bank no more; renewed, it is payable again — the same reference, for the balance
        it.db(() -> jdbc.sql("UPDATE finance.payment_reference SET expires_at = now() - interval '1 hour' WHERE reference = :r").param("r", reference).update());
        assertThat((Map<String, Object>) mine(s1).get("payment")).containsEntry("pending", false).containsEntry("nextAction", "PAY_BALANCE");
        ResponseEntity<Map> renewed = renew(s1, reference);
        assertThat(renewed.getStatusCode().value()).as(String.valueOf(renewed.getBody())).isEqualTo(200);
        assertThat(renewed.getBody()).containsEntry("reference", reference).containsEntry("outcome", "REOPENED");
        assertThat(money(renewed.getBody().get("amount"))).isEqualByComparingTo(HALF);
        assertThat(OffsetDateTime.parse(String.valueOf(renewed.getBody().get("expiresAt")))).isAfter(OffsetDateTime.now());
        pay = (Map<String, Object>) mine(s1).get("payment");
        assertThat(pay).containsEntry("pending", true).containsEntry("nextAction", "COMPLETE_PAYMENT").containsEntry("openReference", reference);
        ResponseEntity<Map> pending = approve(academic, a1);
        assertThat(pending.getStatusCode().value()).as(String.valueOf(pending.getBody())).isEqualTo(422);
        assertThat(code(pending)).isEqualTo("TRANSFER_PAYMENT_PENDING");

        // ── confirmed: settled in parts, nothing more drawn, the final approval effects the transfer against the fee as stated ──
        ResponseEntity<Map> confirmed = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + reference + "/confirm", Map.of("channel", "Bank transfer", "note", "transfer fee balance test"));
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
        view = mine(s1);
        pay = (Map<String, Object>) view.get("payment");
        assertThat(pay).containsEntry("band", "SETTLED_IN_PARTS").containsEntry("settled", true).containsEntry("nextAction", "AWAIT_APPROVAL");
        assertThat(money(pay.get("balance"))).isEqualByComparingTo("0");
        assertThat(money(pay.get("paidTotal"))).isEqualByComparingTo(FEE);
        assertThat((List<Map<String, Object>>) view.get("paymentsMade")).extracting(x -> x.get("status")).containsExactlyInAnyOrder("LINKED", "CONFIRMED");
        ResponseEntity<Map> again = it.call(student(s1), HttpMethod.POST, "/api/v1/me/transfer/" + a1 + "/fee", Map.of());
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(code(again)).isEqualTo("TRANSFER_FEE_SETTLED");
        assertThat(row(academic, a1)).containsEntry("canApprove", true).containsEntry("stageLabel", "With Academic office");
        Map<String, Object> ready = summary(bursar, m1);
        assertThat(((Number) ready.get("readyForFinalApproval")).intValue()).isEqualTo(1);
        assertThat(((Number) ready.get("stillOwing")).intValue()).isZero();
        assertThat(money(ready.get("outstanding"))).isEqualByComparingTo("0");
        ResponseEntity<Map> effected = approve(academic, a1);
        assertThat(effected.getStatusCode().value()).as(String.valueOf(effected.getBody())).isEqualTo(200);
        assertThat(effected.getBody()).containsEntry("state", "EFFECTED");
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", s1).query(String.class).single()).isEqualTo(pb);
        Map<String, Object> settlement = jdbc.sql("SELECT fee, paid_total, payments FROM people.transfer_fee_settlement WHERE application_id = CAST(:a AS uuid)")
                .param("a", a1).query().singleRow();
        assertThat((BigDecimal) settlement.get("fee")).isEqualByComparingTo(FEE);
        assertThat((BigDecimal) settlement.get("paid_total")).isEqualByComparingTo(FEE);
        assertThat(((Number) settlement.get("payments")).intValue()).isEqualTo(2);
        assertThat((Map<String, Object>) mine(s1).get("payment")).containsEntry("state", "EFFECTED").containsEntry("nextAction", "NONE");

        // ── nothing paid: the current HOD may not act ──
        ResponseEntity<Map> unpaid = it.call(student(s2), HttpMethod.POST, "/api/v1/me/transfer", Map.of("toProgramme", pb, "reason", "Wishes to move departments"));
        assertThat(unpaid.getStatusCode().value()).as(String.valueOf(unpaid.getBody())).isEqualTo(200);
        String a2 = String.valueOf(unpaid.getBody().get("id"));
        assertThat((Map<String, Object>) mine(s2).get("payment")).containsEntry("band", "NOT_PAID").containsEntry("nextAction", "PAY_NOW");
        assertThat(row(hodA, a2)).containsEntry("canApprove", false).containsEntry("stageLabel", "Awaiting payment");
        ResponseEntity<Map> notYet = approve(hodA, a2);
        assertThat(notYet.getStatusCode().value()).as(String.valueOf(notYet.getBody())).isEqualTo(422);
        assertThat(code(notYet)).isEqualTo("TR_NOT_YOUR_STAGE");

        // ── the reference drawn for the whole fee, then an officer links an old-portal payment that changes the balance: the reference
        //    is closed and never taken to a gateway; renewed, it is a new one for the balance ──
        ResponseEntity<Map> whole = it.call(student(s2), HttpMethod.POST, "/api/v1/me/transfer/" + a2 + "/fee", Map.of());
        assertThat(whole.getStatusCode().value()).as(String.valueOf(whole.getBody())).isEqualTo(200);
        String wholeRef = String.valueOf(whole.getBody().get("reference"));
        assertThat(money(whole.getBody().get("amount"))).isEqualByComparingTo(FEE);
        assertThat((Map<String, Object>) mine(s2).get("payment")).containsEntry("band", "PENDING").containsEntry("pending", true)
                .containsEntry("nextAction", "COMPLETE_PAYMENT").containsEntry("openReference", wholeRef);
        UUID p2 = legacyPayment(s2, "ZZFILED/" + n, "INTER DEPT. TRANSFER", HALF, pr2, 35);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/transfers/legacy/reconcile", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(((List<Map<String, Object>>) it.get(bursar, u -> u.path("/api/v1/transfers/legacy").queryParam("search", pr2).build()).getBody().get("rows")))
                .extracting(x -> x.get("payment_id"), x -> x.get("status")).containsExactly(org.assertj.core.groups.Tuple.tuple(p2.toString(), "UNMATCHED"));
        ResponseEntity<Map> linked = it.call(bursar, HttpMethod.POST, "/api/v1/transfers/legacy/" + p2 + "/decision",
                Map.of("decision", "LINK", "application", a2, "note", "Paid by this student under a mistyped number; counted toward the application"));
        assertThat(linked.getStatusCode().value()).as(String.valueOf(linked.getBody())).isEqualTo(200);
        assertThat(linked.getBody()).containsEntry("status", "LINKED");
        Map<String, Object> pay2 = (Map<String, Object>) mine(s2).get("payment");
        assertThat(pay2).containsEntry("band", "PART_PAID").containsEntry("pending", false).containsEntry("nextAction", "PAY_BALANCE");
        assertThat(pay2.get("openReference")).isNull();
        assertThat(money(pay2.get("balance"))).isEqualByComparingTo(HALF);
        assertThat(jdbc.sql("SELECT expires_at <= now() FROM finance.payment_reference WHERE reference = :r").param("r", wholeRef).query(Boolean.class).single()).isTrue();
        ResponseEntity<Map> closedRef = checkout(s2, wholeRef);
        assertThat(closedRef.getStatusCode().value()).as(String.valueOf(closedRef.getBody())).isEqualTo(422);
        assertThat(code(closedRef)).isIn("PAY_REFERENCE_EXPIRED", "TRANSFER_REFERENCE_STALE");
        ResponseEntity<Map> replaced = renew(s2, wholeRef);
        assertThat(replaced.getStatusCode().value()).as(String.valueOf(replaced.getBody())).isEqualTo(200);
        assertThat(replaced.getBody()).containsEntry("outcome", "NEW");
        String balanceRef = String.valueOf(replaced.getBody().get("reference"));
        assertThat(balanceRef).isNotEqualTo(wholeRef);
        assertThat(money(replaced.getBody().get("amount"))).isEqualByComparingTo(HALF);
        assertThat((Map<String, Object>) mine(s2).get("payment")).containsEntry("pending", true).containsEntry("openReference", balanceRef)
                .containsEntry("nextAction", "COMPLETE_PAYMENT");
        // a stale reference left open (no rule leaves one now) is still not taken to a gateway: it is not for what is owed
        it.db(() -> jdbc.sql("UPDATE finance.payment_reference SET expires_at = now() + interval '1 hour' WHERE reference = :r").param("r", wholeRef).update());
        ResponseEntity<Map> stale = checkout(s2, wholeRef);
        assertThat(stale.getStatusCode().value()).as(String.valueOf(stale.getBody())).isEqualTo(422);
        assertThat(code(stale)).isEqualTo("TRANSFER_REFERENCE_STALE");

        // ── declined: nothing more is owed (CLOSED), no reference left payable ──
        ResponseEntity<Map> declined = it.call(hodA, HttpMethod.POST, "/api/v1/transfers/" + a2 + "/decline", Map.of("why", "The receiving department has no place this session"));
        assertThat(declined.getStatusCode().value()).as(String.valueOf(declined.getBody())).isEqualTo(200);
        Map<String, Object> closed = (Map<String, Object>) mine(s2).get("payment");
        assertThat(closed).containsEntry("applicationId", a2).containsEntry("state", "DECLINED").containsEntry("band", "CLOSED")
                .containsEntry("nextAction", "NONE").containsEntry("stageLabel", "Declined").containsEntry("pending", false);
        assertThat(money(closed.get("balance"))).isEqualByComparingTo("0");
        assertThat(row(academic, a2)).containsEntry("band", "CLOSED").containsEntry("canApprove", false).containsEntry("canDecline", false);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE reference IN (:a, :b) AND expires_at > now()")
                .param("a", wholeRef).param("b", balanceRef).query(Long.class).single()).isZero();
        ResponseEntity<Map> afterDecline = checkout(s2, balanceRef);
        assertThat(afterDecline.getStatusCode().value()).as(String.valueOf(afterDecline.getBody())).isEqualTo(422);
        assertThat(code(afterDecline)).isIn("PAY_REFERENCE_EXPIRED", "TRANSFER_REFERENCE_STALE");
        Map<String, Object> closedSummary = summary(bursar, m2);
        assertThat(((Number) ((Map<String, Object>) closedSummary.get("bands")).get("CLOSED")).intValue()).isEqualTo(1);
        assertThat(((Number) closedSummary.get("stillOwing")).intValue()).isZero();
        assertThat(money(closedSummary.get("outstanding"))).isEqualByComparingTo("0");

        // ── an old-portal payment filed under another matriculation number: unmatched, rejected by the Bursary with a reason ──
        UUID p3 = legacyPayment(s3, "ZZOTHER/" + n, "INTER DEPT. TRANSFER", HALF, pr3, 40);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/transfers/legacy/reconcile", Map.of()).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> listed = it.get(bursar, u -> u.path("/api/v1/transfers/legacy").queryParam("status", "UNMATCHED").queryParam("search", m3).build());
        assertThat(listed.getStatusCode().value()).as(String.valueOf(listed.getBody())).isEqualTo(200);
        List<Map<String, Object>> unmatched = (List<Map<String, Object>>) listed.getBody().get("rows");
        assertThat(unmatched).extracting(x -> x.get("payment_id")).containsExactly(p3.toString());
        assertThat(String.valueOf(unmatched.get(0).get("reason"))).contains("another matriculation number");
        assertThat(((Number) ((Map<String, Object>) listed.getBody().get("counts")).get("UNMATCHED")).intValue()).isEqualTo(1);
        ResponseEntity<Map> short_ = it.call(bursar, HttpMethod.POST, "/api/v1/transfers/legacy/" + p3 + "/decision", Map.of("decision", "REJECT", "note", "no"));
        assertThat(short_.getStatusCode().value()).isEqualTo(422);
        assertThat(code(short_)).isEqualTo("LEGACY_TRANSFER_REASON");
        assertThat(it.call(studentAccounts, HttpMethod.POST, "/api/v1/transfers/legacy/" + p3 + "/decision",
                Map.of("decision", "REJECT", "note", "Paid under another student's number")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/transfers/legacy/" + UUID.randomUUID() + "/decision",
                Map.of("decision", "REJECT", "note", "Paid under another student's number")).getStatusCode().value()).isEqualTo(404);
        ResponseEntity<Map> rejected = it.call(bursar, HttpMethod.POST, "/api/v1/transfers/legacy/" + p3 + "/decision",
                Map.of("decision", "REJECT", "note", "Paid under another student's number; the Bursary returns it"));
        assertThat(rejected.getStatusCode().value()).as(String.valueOf(rejected.getBody())).isEqualTo(200);
        assertThat(rejected.getBody()).containsEntry("status", "REJECTED");
        Map<String, Object> decided = ((List<Map<String, Object>>) it.get(studentAccounts, u -> u.path("/api/v1/transfers/legacy").queryParam("search", m3).build())
                .getBody().get("rows")).get(0);
        assertThat(decided).containsEntry("status", "REJECTED").containsEntry("decided_office", "bursar")
                .containsEntry("decided_note", "Paid under another student's number; the Bursary returns it");
        // the payment the student paid toward the effected transfer stays linked, by the rule
        assertThat(((List<Map<String, Object>>) it.get(bursar, u -> u.path("/api/v1/transfers/legacy").queryParam("search", pr1).build()).getBody().get("rows")))
                .extracting(x -> x.get("payment_id"), x -> x.get("status"), x -> x.get("application_id")).containsExactly(org.assertj.core.groups.Tuple.tuple(p1.toString(), "LINKED", a1));

        // ── the scope: the date the exercise counts from and the items that count; a change without a reason is refused ──
        ResponseEntity<Map> scope = it.get(bursar, "/api/v1/transfers/legacy/scope");
        assertThat(scope.getStatusCode().value()).isEqualTo(200);
        String countsFrom = String.valueOf(scope.getBody().get("countsFrom"));
        assertThat(countsFrom).matches("\\d{4}-\\d{2}-\\d{2}");
        assertThat((List<Map<String, Object>>) scope.getBody().get("items")).filteredOn(i -> "CHANGE OF COURSE".equals(i.get("item")))
                .extracting(i -> i.get("counts")).containsExactly(false);
        ResponseEntity<Map> noReason = it.call(bursar, HttpMethod.PUT, "/api/v1/transfers/legacy/scope", Map.of("countsFrom", countsFrom, "reason", "why"));
        assertThat(noReason.getStatusCode().value()).isEqualTo(422);
        assertThat(code(noReason)).isEqualTo("LEGACY_TRANSFER_REASON");

        // ── the old portal's export: checked, then loaded at the stage it reached, the payment its number names counted ──
        UUID p4 = legacyPayment(s4, m4, "INTER DEPT. TRANSFER  PROVISIONAL LETTER", HALF, pr4, 20);
        String current = jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
        String legacyRef = "IDT/IT/" + tag + "/" + n;
        Map<String, Object> exportRow = new HashMap<>(Map.of("legacy_ref", legacyRef, "matric_no", m4, "to_programme", pb, "stage", "HOD Approved",
                "session", current, "applied_on", LocalDate.parse(countsFrom).plusDays(15).format(DateTimeFormatter.ofPattern("dd/MM/yyyy")),
                "payrefs", pr4, "approvals", "HOD (current) approved", "documents", "letter.pdf"));
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/transfers/legacy/upload/check", Map.of("rows", List.of(exportRow))).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> checked = it.call(academic, HttpMethod.POST, "/api/v1/transfers/legacy/upload/check", Map.of("rows", List.of(exportRow)));
        assertThat(checked.getStatusCode().value()).as(String.valueOf(checked.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) checked.getBody().get("rows")).extracting(x -> x.get("status"), x -> x.get("stage"))
                .containsExactly(org.assertj.core.groups.Tuple.tuple("NEW", "FROM_OK"));
        assertThat(((Number) ((Map<String, Object>) checked.getBody().get("counts")).get("NEW")).intValue()).isEqualTo(1);
        ResponseEntity<Map> loaded = it.call(academic, HttpMethod.POST, "/api/v1/transfers/legacy/upload", Map.of("rows", List.of(exportRow), "filename", "idt-export.xlsx", "partial", false));
        assertThat(loaded.getStatusCode().value()).as(String.valueOf(loaded.getBody())).isEqualTo(200);
        assertThat(((Number) loaded.getBody().get("loaded")).intValue()).isEqualTo(1);
        Map<String, Object> made4 = ((List<Map<String, Object>>) loaded.getBody().get("rows")).get(0);
        assertThat(made4).containsEntry("status", "NEW").containsEntry("legacy_ref", legacyRef);
        assertThat(((Number) made4.get("linked_payments")).intValue()).isEqualTo(1);
        String a4 = String.valueOf(made4.get("application_id"));
        String loadId = String.valueOf(loaded.getBody().get("loadId"));
        assertThat(it.getList(bursar, "/api/v1/transfers/legacy/loads").getBody()).extracting(x -> ((Map<String, Object>) x).get("id")).contains(loadId);
        Map<String, Object> view4 = mine(s4);
        assertThat((Map<String, Object>) view4.get("payment")).containsEntry("applicationId", a4).containsEntry("state", "FROM_OK").containsEntry("band", "PART_PAID");
        assertThat((Map<String, Object>) view4.get("legacy")).containsEntry("legacyRef", legacyRef).containsEntry("stage", "HOD Approved");
        assertThat((List<Map<String, Object>>) view4.get("paymentsMade")).extracting(x -> x.get("payref")).containsExactly(pr4);
        assertThat(jdbc.sql("SELECT match_method FROM people.legacy_transfer_payment WHERE payment_id = :p").param("p", p4).query(String.class).single())
                .isEqualTo("OLD_PORTAL_EXPORT");
        ResponseEntity<Map> twice = it.call(academic, HttpMethod.POST, "/api/v1/transfers/legacy/upload/check", Map.of("rows", List.of(exportRow)));
        assertThat((List<Map<String, Object>>) twice.getBody().get("rows")).extracting(x -> x.get("status")).containsExactly("EXISTS");

        // ── the reconciliation report, read from the records as they stand ──
        ResponseEntity<Map> report = it.get(bursar, "/api/v1/transfers/legacy/report");
        assertThat(report.getStatusCode().value()).as(String.valueOf(report.getBody())).isEqualTo(200);
        assertThat(money(report.getBody().get("fee"))).isEqualByComparingTo(FEE);
        assertThat(String.valueOf(report.getBody().get("countsFrom"))).isEqualTo(countsFrom);
        assertThat(((Number) report.getBody().get("paymentsRejected")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) report.getBody().get("paymentsLinked")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) report.getBody().get("legacyApplicationsMatched")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(it.get(housing, "/api/v1/transfers/legacy/report").getStatusCode().value()).isEqualTo(403);
    }
}
