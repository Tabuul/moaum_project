package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.sql.Connection;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.sql.DataSource;

import ng.edu.moaum.portal.finance.OverpaidWatch;

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
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V781 through the API: the Overpaid school fees desk. The students of a session who paid above their charge, by cause, with every hold
 * on them, read from the kept list; the wallet credit requested for many at once by one Bursary officer (or the Students Account
 * Officer) and approved by another, a call at a time, the approval loop ending; the refund raised for the exact repeats; the further
 * decision after a student pays again; a hand refund lowering what remains; a request returned, withdrawn and made again; what the
 * student's own pages say; the wallet credit applied to the next session's fees by the student (nothing is applied by an approval);
 * a wallet refund of the overpaid money by source, and what a charge that rose after a decision keeps back from it.
 * The job that works the kept list out is off under every integration test (src/test/resources/config), and refreshes only when the
 * test calls it.
 *
 * <p>Every student, number and amount is invented; each test draws sessions no other test has opened. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class OverpaidReconciliationIT {

    /** the screenshot's charge: ₦66,745 and ₦28,605 */
    private static final long FEE = 95350;
    private static final long REPEAT = 28605;
    private static final String BASE = "/api/v1/finance/overpaid";

    @Value("${local.server.port}")
    int port;
    @Value("${moaum.overpaid.enabled}")
    boolean jobEnabled;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    DataSource dataSource;
    @Autowired
    OverpaidWatch watch;

    ItSupport it;
    String tag;
    String a;
    String b;
    String prog = "C00023";
    UUID saoId;
    UUID bursar1Id;
    UUID bursar2Id;
    UUID bursar3Id;
    String sao;
    String bursar1;
    String bursar2;
    String bursar3;
    String registrar = ItSupport.token("registrar");
    String audit = ItSupport.token("audit");
    /** the invented students' keys for their payment references */
    final Map<UUID, String> keys = new HashMap<>();

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> {
            List<String> ids = new ArrayList<>(List.of("ZZOVR-SAO-" + k, "ZZOVR-BU1-" + k, "ZZOVR-BU2-" + k, "ZZOVR-BU3-" + k));
            for (int n = 1; n <= 14; n++) {
                ids.add("MOAUM/ADM/63/" + k + String.format("%02d", n));
                ids.add("MOAUM/OVR/63/" + k + String.format("%02d", n));
                ids.add("ZZOVR" + k + "N" + n);
            }
            return ids;
        }));
        int year = it.freeYear(3200, 3290, 0, 1);
        a = year + "/" + (year + 1);
        b = (year + 1) + "/" + (year + 2);
        it.session(a, year);
        it.session(b, year + 1);
        saoId = it.person("ZZOVR-SAO-" + tag, "ZZOVRSAO");
        bursar1Id = it.person("ZZOVR-BU1-" + tag, "ZZOVRBU1");
        bursar2Id = it.person("ZZOVR-BU2-" + tag, "ZZOVRBU2");
        bursar3Id = it.person("ZZOVR-BU3-" + tag, "ZZOVRBU3");
        sao = TestTokens.token(saoId, List.of("studentaccounts"));
        bursar1 = TestTokens.token(bursar1Id, List.of("bursar"));
        bursar2 = TestTokens.token(bursar2Id, List.of("bursar"));
        bursar3 = TestTokens.token(bursar3Id, List.of("bursar"));
        it.db(() -> {
            for (String s : new String[] {a, b}) {
                jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', :f, NULL, :p)")
                        .param("s", s).param("f", FEE).param("p", prog).update();
            }
            // the Bursar's office holders, so the desk's notices reach someone
            for (UUID p : new UUID[] {bursar1Id, bursar2Id, bursar3Id}) {
                jdbc.sql("""
                        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from, valid_to)
                        VALUES (gen_random_uuid(), :p, 'bursar', 'institution', NULL, 'OverpaidReconciliationIT', gen_random_uuid(), current_date - 1, NULL)
                        """).param("p", p).update();
            }
            return null;
        });
    }

    @AfterEach
    void putBack() {
        if (it != null) {
            it.db(() -> {
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session IN (:a, :b)").param("a", a).param("b", b).update();
                jdbc.sql("DELETE FROM iam.office_assignment WHERE instrument = 'OverpaidReconciliationIT'").update();
                return null;
            });
        }
    }

    /* ── the invented students and their payments ── */

    /** an invented student of the programme who entered in session a at 100 Level (so the level on record is the level by entry year) */
    private UUID student(int n, String status) {
        UUID s = it.student("ZZOVR" + tag + "N" + n, prog, "MOAUM/ADM/63/" + tag + String.format("%02d", n), "MOAUM/OVR/63/" + tag + String.format("%02d", n), 100);
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :a, status = :st WHERE id = :s").param("a", a).param("st", status).param("s", s).update());
        keys.put(s, "N" + n);
        return s;
    }

    /** a confirmed school-fees payment of session a: the old portal's own record, or a portal payment the gateway reported */
    private String paid(UUID s, String kind, long amount, int seq, int daysAgo) {
        return paid(s, kind, amount, seq, daysAgo, true);
    }

    /** evidenced false: a portal payment confirmed with no report of the bank on record (a hand confirmation) */
    private String paid(UUID s, String kind, long amount, int seq, int daysAgo, boolean evidenced) {
        String key = keys.get(s);
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", s).query(String.class).single();
        boolean old = "OLD".equals(kind);
        String ref = old ? "MOAUM-LEG-" + matric.replaceAll("[^0-9A-Z]", "") + "-" + a.replace("/", "-") + "-S" + seq : "MOAUM-OVR-" + tag + "-" + key + "-" + seq;
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                    VALUES (:s, :ses, :r, :p, :a, now() - make_interval(days => :d) - interval '1 hour', now() - make_interval(days => :d) + interval '1 day',
                            now() - make_interval(days => :d), :by, :ch, :rc, 'OverpaidReconciliationIT')
                    """).param("s", s).param("ses", a).param("r", ref).param("p", old ? "School fees (legacy) · semester 1" : "School fees " + a)
                    .param("a", amount).param("d", daysAgo).param("by", UUID.randomUUID()).param("ch", old ? "Legacy" : "Quickteller WEB")
                    .param("rc", (old ? "LEG-" : "RCT-") + ref).update();
            if (!old && evidenced) {
                // the bank's own report of the payment: a gateway event with its reference
                jdbc.sql("""
                        INSERT INTO finance.gateway_event (gateway, source, event, reference, gateway_ref, amount, status, signature_ok, outcome, received_at)
                        VALUES ('interswitch', 'WEBHOOK', 'payment', :r, :g, :a, 'SUCCESS', true, 'SETTLED', now() - make_interval(days => :d))
                        """).param("r", ref).param("g", "GW-" + ref).param("a", amount).param("d", daysAgo).update();
            }
            return null;
        });
        return ref;
    }

    /** the screenshot's student: ₦66,745 on the old portal and ₦28,605 twice on the portal against a charge of ₦95,350 */
    private UUID twice(int n, String status) {
        return twice(n, status, false);
    }

    /** the same, the payments confirmed just now (a payment of the session since the kept list was last worked out) when `now` */
    private UUID twice(int n, String status, boolean now) {
        UUID s = student(n, status);
        paid(s, "OLD", 66745, 1, now ? 0 : 30);
        paid(s, "PORTAL", REPEAT, 2, now ? 0 : 20);
        paid(s, "PORTAL", REPEAT, 3, now ? 0 : 14);
        return s;
    }

    /* ── reads ── */

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static void refused(ResponseEntity<Map> r, int status, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(status);
        assertThat(r.getBody()).containsEntry("code", code);
    }

    private static BigDecimal bd(Object o) {
        return new BigDecimal(String.valueOf(o));
    }

    private static int num(Object o) {
        return ((Number) o).intValue();
    }

    private Map<String, Object> refresh(String token) {
        return ok(it.call(token, HttpMethod.POST, BASE + "/refresh", Map.of("session", a)));
    }

    private Map<String, Object> row(String token, UUID student) {
        Map<String, Object> rows = ok(it.get(token, BASE + "/rows?session=" + a + "&size=500"));
        return ((List<Map<String, Object>>) rows.get("rows")).stream().filter(r -> student.toString().equals(r.get("student_id"))).findFirst().orElse(null);
    }

    private Map<String, Object> figures(String token) {
        return ok(it.get(token, BASE + "/figures?session=" + a));
    }

    private Map<String, Object> request(String token, Map<String, Object> body) {
        return ok(it.call(token, HttpMethod.POST, BASE + "/credits/request", body));
    }

    private Map<String, Object> decide(String token, Map<String, Object> body) {
        return ok(it.call(token, HttpMethod.POST, BASE + "/credits/decide", body));
    }

    private static Map<String, Object> act(String session, Object students, String cause, String reason, boolean fee) {
        Map<String, Object> m = new HashMap<>();
        m.put("session", session);
        if (students != null) m.put("students", students);
        if (cause != null) m.put("cause", cause);
        m.put("reason", reason);
        m.put("confirmed", true);
        if (fee) m.put("feeSetupChecked", true);
        return m;
    }

    private static List<String> codes(Map<String, Object> answer) {
        return ((List<Map<String, Object>>) answer.get("skippedWhy")).stream().map(x -> String.valueOf(x.get("code"))).sorted().toList();
    }

    private BigDecimal wallet(UUID s) {
        return jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", s).query(BigDecimal.class).single();
    }

    /** a count; the statement names its parameters (:x) in the order of the values given */
    private long count(String sql, Object... params) {
        JdbcClient.StatementSpec spec = jdbc.sql(sql.replaceAll("(?<!:):[a-z]+", "?"));
        for (Object p : params) spec = spec.param(p);
        return spec.query(Long.class).single();
    }

    /* ═══ the list, the request by one officer, the approval by another, and what the student does with the credit ═══ */

    @Test
    void theListIsRequestedByOneOfficerApprovedByAnotherAndTheStudentAppliesTheCreditToTheNextSession() {
        UUID tw1 = twice(1, "ACTIVE");
        UUID tw2 = twice(2, "ACTIVE");
        UUID tw3 = twice(3, "ACTIVE");
        UUID tw4 = twice(4, "ACTIVE");
        UUID tw5 = twice(5, "ACTIVE");
        UUID wd = twice(6, "WITHDRAWN");
        UUID gr = twice(7, "GRADUATED");
        UUID ln = student(8, "ACTIVE");   // one payment of ₦110,000 against ₦95,350: above the fee line, not a repeated payment
        paid(ln, "PORTAL", 110000, 1, 12);

        // nothing is worked out until it is asked for: a session never worked out answers computed false with zeros
        Map<String, Object> before = figures(registrar);
        assertThat(before).containsEntry("computed", false);
        assertThat(num(before.get("students"))).isZero();
        assertThat(ok(it.get(registrar, BASE + "/rows?session=" + a))).containsEntry("computed", false).containsEntry("total", 0);
        assertThat(it.get(audit, BASE + "/figures?session=" + a).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(TestTokens.token(tw1, List.of("student")), BASE + "/figures?session=" + a).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(registrar, BASE + "/figures?session=2025-2026").getStatusCode().value()).isEqualTo(422);
        // the offices: a registrar reads, and neither refreshes nor requests; the Students Account Officer requests but neither approves nor refunds
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/refresh", Map.of("session", a)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/credits/request", act(a, List.of(tw1), null, "a registrar cannot request this", false)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(sao, HttpMethod.POST, BASE + "/credits/decide", Map.of("batch", "OCR/2026/000001", "action", "APPROVE")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(sao, HttpMethod.POST, BASE + "/refund", act(a, List.of(tw1), null, "the officer cannot refund this", false)).getStatusCode().value()).isEqualTo(403);

        // the Students Account Officer works the list out: eight students, the screenshot's among them
        Map<String, Object> fig = refresh(sao);
        assertThat(fig).containsEntry("computed", true);
        assertThat(num(fig.get("students"))).isEqualTo(8);
        assertThat(bd(fig.get("excess"))).isEqualByComparingTo(String.valueOf(7 * REPEAT + 14650));
        List<Map<String, Object>> causes = (List<Map<String, Object>>) fig.get("causes");
        assertThat(causes).extracting(c -> c.get("cause")).containsExactly("PORTAL_TWICE", "OLD_AND_PORTAL", "OLD_TWICE", "PART_PAYMENTS", "ABOVE_FEE_LINE");
        assertThat(causes.get(0)).containsEntry("students", 7).containsEntry("held", 1).containsEntry("ready", 6);
        assertThat(causes.get(4)).containsEntry("students", 1).containsEntry("ready", 0);
        Map<String, Object> twiceFig = (Map<String, Object>) fig.get("paidTwice");
        assertThat(twiceFig).containsEntry("students", 7).containsEntry("ready", 6).containsEntry("walletReady", 5).containsEntry("refundOnly", 1);
        assertThat(bd(twiceFig.get("walletReadyAmount"))).isEqualByComparingTo(String.valueOf(5 * REPEAT));
        assertThat((Map<String, Object>) fig.get("apart")).containsEntry("students", 1);
        Map<String, Object> heldFig = (Map<String, Object>) fig.get("held");
        assertThat(heldFig).containsEntry("students", 1);
        assertThat((Map<String, Object>) heldFig.get("reasons")).containsEntry("CLOSED_FOR_FEES", 1);
        assertThat((Map<String, Object>) fig.get("overDecided")).containsEntry("students", 0);
        // another refresh running leaves its answer standing
        try (Connection other = dataSource.getConnection()) {
            other.createStatement().execute("SELECT pg_advisory_lock(hashtext('overpaid-snapshot:" + a + "'))");
            Map<String, Object> standing = refresh(sao);
            assertThat(standing).containsEntry("computed", true);
            assertThat(num(standing.get("students"))).isEqualTo(8);
            other.createStatement().execute("SELECT pg_advisory_unlock(hashtext('overpaid-snapshot:" + a + "'))");
        } catch (java.sql.SQLException e) {
            throw new IllegalStateException(e);
        }

        // the rows: the screenshot's student is paid twice on the portal, in bulk, with nothing held and the wallet suggested
        Map<String, Object> rows = ok(it.get(registrar, BASE + "/rows?session=" + a + "&size=500"));
        assertThat(rows).containsEntry("computed", true).containsEntry("total", 8).containsEntry("page", 0);
        assertThat((List<Map<String, Object>>) rows.get("faculties")).isNotEmpty();
        List<Map<String, Object>> list = (List<Map<String, Object>>) rows.get("rows");
        assertThat(list.get(list.size() - 1)).as("the held row is last").containsEntry("student_id", gr.toString());
        Map<String, Object> r1 = row(registrar, tw1);
        assertThat(r1).containsEntry("cause", "PORTAL_TWICE").containsEntry("bulk", true).containsEntry("suggested", "WALLET").containsEntry("state", "UNDECIDED")
                .containsEntry("n_payments", 3).containsEntry("level", 100);
        assertThat(bd(r1.get("excess"))).isEqualByComparingTo("28605");
        assertThat(bd(r1.get("repeat_amount"))).isEqualByComparingTo("28605");
        assertThat(bd(r1.get("remaining"))).isEqualByComparingTo("28605");
        assertThat((List<?>) r1.get("holds")).isEmpty();
        assertThat((List<Map<String, Object>>) r1.get("payments")).extracting(p -> p.get("kind") + ":" + bd(p.get("amount")).intValue())
                .containsExactly("OLD:66745", "PORTAL:28605", "PORTAL:28605");
        assertThat(row(registrar, ln)).containsEntry("cause", "ABOVE_FEE_LINE").containsEntry("bulk", false).containsEntry("suggested", "CHECK_FEE_SETUP");
        assertThat(row(registrar, wd)).containsEntry("refund_only", "WITHDRAWN").containsEntry("suggested", "REFUND");
        Map<String, Object> rg = row(registrar, gr);
        assertThat((List<String>) rg.get("holds")).containsExactly("CLOSED_FOR_FEES");
        assertThat(rg).containsEntry("suggested", "WAIT").containsEntry("refund_only", "GRADUATED");
        // filtered in the statement, paged, and the filters named
        assertThat(ok(it.get(registrar, BASE + "/rows?session=" + a + "&cause=ABOVE_FEE_LINE"))).containsEntry("total", 1);
        assertThat(ok(it.get(registrar, BASE + "/rows?session=" + a + "&held=true"))).containsEntry("total", 1);
        assertThat(ok(it.get(registrar, BASE + "/rows?session=" + a + "&bulk=false"))).containsEntry("total", 1);
        assertThat(ok(it.get(registrar, BASE + "/rows?session=" + a + "&q=ZZOVR" + tag))).containsEntry("total", 8);
        assertThat(ok(it.get(registrar, BASE + "/rows?session=" + a + "&state=UNDECIDED"))).containsEntry("total", 8);
        Map<String, Object> page = ok(it.get(registrar, BASE + "/rows?session=" + a + "&size=3&page=2"));
        assertThat((List<?>) page.get("rows")).hasSize(2);
        assertThat(page).containsEntry("total", 8).containsEntry("size", 3).containsEntry("page", 2);
        refused(it.get(registrar, BASE + "/rows?session=" + a + "&cause=NOT_A_CAUSE"), 422, "OVERPAID_FILTER");
        refused(it.get(registrar, BASE + "/rows?session=" + a + "&state=NOT_A_STATE"), 422, "OVERPAID_FILTER");
        // the student's own fees page says what the Bursary will do, before any decision
        String tw1Token = TestTokens.token(tw1, List.of("student"));
        Map<String, Object> mine = ok(it.get(tw1Token, "/api/v1/me/fees?session=" + a));
        assertThat(bd(mine.get("excess"))).isEqualByComparingTo("28605");
        assertThat(bd(mine.get("excessDecided"))).isEqualByComparingTo("0");
        assertThat(bd(mine.get("excessRemaining"))).isEqualByComparingTo("28605");
        assertThat(bd(mine.get("excessRequested"))).isEqualByComparingTo("0");
        assertThat(mine).containsEntry("excessCause", "PORTAL_TWICE").doesNotContainKey("walletOverpaid");
        assertThat((List<?>) mine.get("excessHolds")).isEmpty();

        // the requests: the confirmation first, who and which cause, at most 2,000 named
        Map<String, Object> noTick = act(a, List.of(tw5), null, "the payments were looked at", false);
        noTick.put("confirmed", false);
        refused(it.call(bursar1, HttpMethod.POST, BASE + "/credits/request", noTick), 422, "OVERPAID_CONFIRM");
        refused(it.call(bursar1, HttpMethod.POST, BASE + "/credits/request", act(a, null, "ABOVE_FEE_LINE", "the payments were looked at", true)), 422, "OVERPAID_BULK_CAUSE");
        refused(it.call(bursar1, HttpMethod.POST, BASE + "/credits/request", act(a, null, null, "the payments were looked at", true)), 422, "OVERPAID_BULK_WHO");
        List<UUID> many = new ArrayList<>();
        for (int i = 0; i < 2001; i++) many.add(UUID.randomUUID());
        refused(it.call(bursar1, HttpMethod.POST, BASE + "/credits/request", act(a, many, null, "the payments were looked at", true)), 422, "OVERPAID_TOO_MANY");
        refused(it.call(bursar1, HttpMethod.POST, BASE + "/credits/request", act(a, List.of(tw5), null, "short", false)), 400, "VALIDATION_FAILED");

        // a Bursary officer requests one student; the Bursar's office holders are told, a notice each
        Map<String, Object> rb = request(bursar1, act(a, List.of(tw5), null, "the screenshot's student paid 28,605 twice", false));
        assertThat(rb).containsEntry("requested", 1).containsEntry("skipped", 0);
        assertThat((String) rb.get("batch")).matches("OCR/[0-9]{4}/[0-9]{6}");
        assertThat(bd(rb.get("amount"))).isEqualByComparingTo("28605");
        assertThat(count("SELECT count(*) FROM platform.notice WHERE about_kind = 'person' AND about_id = :p AND template_key = 'OVERPAID_CREDITS_WAITING'", bursar2Id)).isGreaterThanOrEqualTo(1);

        // the Students Account Officer: a fee-line student is never in a request of many (ONE_AT_A_TIME), alone it needs the fee setup checked
        Map<String, Object> r1q = request(sao, act(a, List.of(tw1, ln), null, "the payments were looked at", false));
        assertThat(r1q).containsEntry("requested", 1).containsEntry("skipped", 1);
        assertThat(codes(r1q)).containsExactly("ONE_AT_A_TIME");
        Map<String, Object> unchecked = request(sao, act(a, List.of(ln), null, "the payments were looked at", false));
        assertThat(unchecked).containsEntry("requested", 0);
        assertThat(codes(unchecked)).containsExactly("FEE_SETUP_UNCHECKED");
        Map<String, Object> lnq = request(sao, act(a, List.of(ln), null, "paid above the fee line; the fee setup and the payments were checked", true));
        assertThat(lnq).containsEntry("requested", 1).containsEntry("skipped", 0);
        assertThat(bd(lnq.get("amount"))).isEqualByComparingTo("14650");
        // a paid-twice cause as a whole, in two calls of one act (the first with a limit): the students already requested, the withdrawn one
        // and the graduated one are left, each with its reason
        Map<String, Object> cause1 = act(a, null, "PORTAL_TWICE", "paid twice on the portal; the payments were looked at", false);
        cause1.put("limit", 2);
        Map<String, Object> c1 = request(sao, cause1);
        assertThat(c1).containsEntry("requested", 2);
        String batchC = (String) c1.get("batch");
        Map<String, Object> cause2 = act(a, null, "PORTAL_TWICE", "paid twice on the portal; the payments were looked at", false);
        cause2.put("batch", batchC);
        Map<String, Object> c2 = request(sao, cause2);
        assertThat(c2).containsEntry("requested", 1).containsEntry("remaining", 0).containsEntry("batch", batchC);
        assertThat(codes(c2)).containsExactly("HELD", "REFUND_ONLY", "REQUEST_OPEN", "REQUEST_OPEN");
        Map<String, Object> alien = act(a, List.of(tw1), null, "a batch that is not the caller's own", false);
        alien.put("batch", rb.get("batch"));
        refused(it.call(sao, HttpMethod.POST, BASE + "/credits/request", alien), 422, "OVERPAID_BATCH");

        // the requests, a page at a time, each with whether it is the caller's own
        List<Map<String, Object>> inBatch = (List<Map<String, Object>>) it.getList(sao, BASE + "/credits?session=" + a + "&batch=" + batchC).getBody();
        assertThat(inBatch).hasSize(3);
        assertThat(inBatch).allSatisfy(r -> assertThat(r).containsEntry("bulk", true).containsEntry("cause", "PORTAL_TWICE").containsEntry("status", "PENDING_BURSAR_APPROVAL")
                .containsEntry("request_batch", batchC).containsEntry("mine", true));
        assertThat(inBatch).extracting(r -> r.get("student_id")).containsExactlyInAnyOrder(tw2.toString(), tw3.toString(), tw4.toString());
        assertThat((String) inBatch.get(0).get("ref")).matches("LOR/[0-9]{4}/[0-9]{6}");
        assertThat(bd(inBatch.get(0).get("confirmed_amount"))).isEqualByComparingTo("28605");
        List<Map<String, Object>> asOther = (List<Map<String, Object>>) it.getList(bursar2, BASE + "/credits?session=" + a + "&batch=" + batchC).getBody();
        assertThat(asOther).allSatisfy(r -> assertThat(r).containsEntry("mine", false));
        List<Map<String, Object>> page0 = (List<Map<String, Object>>) it.getList(bursar2, BASE + "/credits?session=" + a + "&batch=" + batchC + "&size=2&page=0").getBody();
        List<Map<String, Object>> page1 = (List<Map<String, Object>>) it.getList(bursar2, BASE + "/credits?session=" + a + "&batch=" + batchC + "&size=2&page=1").getBody();
        assertThat(page0).hasSize(2);
        assertThat(page1).hasSize(1);
        assertThat(page1.get(0).get("id")).isNotIn(page0.get(0).get("id"), page0.get(1).get("id"));
        assertThat(it.getList(bursar2, BASE + "/credits?session=" + a + "&status=ALL&size=500").getBody()).hasSize(6);
        refused(it.get(bursar2, BASE + "/credits?session=" + a + "&status=NOT_A_STATUS"), 422, "OVERPAID_FILTER");
        // the figures say what waits for this officer's approval, and what is the officer's own
        Map<String, Object> askedOfB2 = (Map<String, Object>) figures(bursar2).get("requests");
        assertThat(askedOfB2).containsEntry("pending", 6).containsEntry("forYou", 6).containsEntry("mine", 0).containsEntry("single", 0);
        Map<String, Object> askedOfSao = (Map<String, Object>) figures(sao).get("requests");
        assertThat(askedOfSao).containsEntry("pending", 6).containsEntry("forYou", 1).containsEntry("mine", 5);
        assertThat((List<Map<String, Object>>) askedOfSao.get("batches")).anySatisfy(x -> assertThat(x).containsEntry("batch", batchC).containsEntry("count", 3)
                .containsEntry("cause", "PORTAL_TWICE").containsEntry("mine", true));
        // the desk's row and the student's own page both say a credit is asked for; the Legacy desk's queue does not list what is decided here
        assertThat(row(sao, tw1)).containsEntry("state", "CREDIT_REQUESTED");
        assertThat((Map<String, Object>) row(sao, tw1).get("request")).containsEntry("status", "PENDING_BURSAR_APPROVAL").containsEntry("mine", true);
        assertThat((Map<String, Object>) row(bursar2, tw1).get("request")).containsEntry("mine", false);
        assertThat(bd(ok(it.get(tw1Token, "/api/v1/me/fees?session=" + a)).get("excessRequested"))).isEqualByComparingTo("28605");
        assertThat((List<?>) it.getList(sao, "/api/v1/finance/legacy-reconciliation/requests?status=PENDING_BURSAR_APPROVAL&q=ZZOVR" + tag).getBody()).isEmpty();
        assertThat(num(((Map) ok(it.get(sao, "/api/v1/finance/legacy-reconciliation/figures?session=" + a)).get("requests")).get("onOverpaidDesk"))).isGreaterThanOrEqualTo(6);
        Map<String, Object> picture = ok(it.get(sao, "/api/v1/finance/legacy-reconciliation/students/" + tw1));
        Map<String, Object> pictureSession = ((List<Map<String, Object>>) picture.get("sessions")).stream().filter(x -> a.equals(x.get("session"))).findFirst().orElseThrow();
        assertThat(pictureSession).containsEntry("cause", "PORTAL_TWICE").containsEntry("bulk", true);
        assertThat(bd(pictureSession.get("remaining"))).isEqualByComparingTo("28605");
        assertThat((List<?>) picture.get("requests")).hasSize(1);

        // the approval: a Bursary officer other than the requester, never the Students Account Officer
        // the requester's own request is left with its reason and not tried again in the pass (`since`): the loop ends
        Map<String, Object> own = decide(bursar1, Map.of("batch", rb.get("batch"), "action", "APPROVE"));
        assertThat(own).containsEntry("credited", 0).containsEntry("skipped", 1).containsEntry("remaining", 0);
        assertThat(codes(own)).containsExactly("LEGACY_CREDIT_SAME_OFFICER");
        Map<String, Object> ownAgain = decide(bursar1, Map.of("batch", rb.get("batch"), "action", "APPROVE", "since", own.get("since")));
        assertThat(ownAgain).containsEntry("credited", 0).containsEntry("skipped", 0).containsEntry("remaining", 0);
        assertThat(String.valueOf(((Map<String, Object>) row(bursar1, tw5).get("request")).get("skip"))).contains("you initiated");
        assertThat(wallet(tw5)).isEqualByComparingTo("0");
        // a pass in calls of one: each call hands back `since`, the number left falls to 0, and the call that follows finds nothing
        Map<String, Object> p1 = decide(bursar2, Map.of("batch", batchC, "action", "APPROVE", "limit", 1));
        assertThat(p1).containsEntry("credited", 1).containsEntry("remaining", 2).containsEntry("batch", batchC);
        assertThat(bd(p1.get("amount"))).isEqualByComparingTo("28605");
        Map<String, Object> p2 = decide(bursar2, Map.of("batch", batchC, "action", "APPROVE", "limit", 1, "since", p1.get("since")));
        assertThat(p2).containsEntry("credited", 1).containsEntry("remaining", 1);
        Map<String, Object> p3 = decide(bursar2, Map.of("batch", batchC, "action", "APPROVE", "limit", 1, "since", p1.get("since")));
        assertThat(p3).containsEntry("credited", 1).containsEntry("remaining", 0);
        Map<String, Object> p4 = decide(bursar2, Map.of("batch", batchC, "action", "APPROVE", "limit", 1, "since", p1.get("since")));
        assertThat(p4).containsEntry("credited", 0).containsEntry("skipped", 0).containsEntry("remaining", 0);
        refused(it.call(bursar2, HttpMethod.POST, BASE + "/credits/decide", Map.of("batch", batchC, "action", "APPROVE", "since", "yesterday")), 422, "OVERPAID_SINCE");
        // the requests of the others, approved by other Bursary officers: all of them credited
        assertThat(decide(bursar2, Map.of("batch", rb.get("batch"), "action", "APPROVE"))).containsEntry("credited", 1);
        assertThat(decide(bursar2, Map.of("batch", r1q.get("batch"), "action", "APPROVE"))).containsEntry("credited", 1);
        Map<String, Object> lnApproved = decide(bursar3, Map.of("batch", lnq.get("batch"), "action", "APPROVE"));
        assertThat(lnApproved).containsEntry("credited", 1);
        assertThat(bd(lnApproved.get("amount"))).isEqualByComparingTo("14650");

        // what an approval does: one wallet entry of the source OVERPAID with a plain note, one WALLET decision, the request closed, the student told
        // — and nothing is applied to fees
        for (UUID s : List.of(tw1, tw2, tw3, tw4, tw5)) {
            assertThat(wallet(s)).as(keys.get(s)).isEqualByComparingTo("28605");
            assertThat(count("SELECT count(*) FROM finance.wallet_entry WHERE student_id = :s AND kind = 'CREDIT' AND source_code = 'OVERPAID'", s)).isEqualTo(1);
            assertThat(jdbc.sql("SELECT note FROM finance.wallet_entry WHERE student_id = :s AND source_code = 'OVERPAID'").param("s", s).query(String.class).single())
                    .startsWith("Overpaid school fees of " + a + " credited to your wallet (LOR/").doesNotContain("officer", "evidence", "paid twice");
            assertThat(jdbc.sql("SELECT decision || ':' || amount::int FROM finance.overpayment_decision WHERE student_id = :s AND session = :a AND superseded_at IS NULL")
                    .param("s", s).param("a", a).query(String.class).list()).containsExactly("WALLET:28605");
            assertThat(count("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND channel = 'NELFUND wallet'", s)).as("no fees are paid by an approval").isZero();
            List<String> told = jdbc.sql("SELECT body FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND template_key = 'LEGACY_CREDIT_POSTED'")
                    .param("s", s).query(String.class).list();
            assertThat(told).isNotEmpty();
            assertThat(told).allSatisfy(body -> assertThat(body).contains("Wallet page").doesNotContain("automatically"));
        }
        assertThat(wallet(ln)).isEqualByComparingTo("14650");
        assertThat(wallet(wd)).isEqualByComparingTo("0");
        assertThat(wallet(gr)).isEqualByComparingTo("0");
        assertThat(count("SELECT count(*) FROM finance.legacy_credit_request WHERE session = :a AND status = 'CREDITED' AND credit_batch ~ '^OCA/[0-9]{4}/[0-9]{6}$' AND bulk", a)).isEqualTo(6);
        assertThat(count("SELECT count(*) FROM platform.notice WHERE about_kind = 'person' AND about_id = :p AND template_key = 'OVERPAID_CREDITS_DECIDED'", saoId)).isGreaterThanOrEqualTo(1);
        assertThat(count("SELECT count(*) FROM platform.notice WHERE about_kind = 'person' AND about_id = :p AND template_key = 'OVERPAID_CREDITS_DECIDED'", bursar1Id)).isGreaterThanOrEqualTo(1);
        // the ledger: the credit moves the overpaid session's school-fees income to the wallet's account; no cash moves
        Map<String, Object> synced = null;
        for (int i = 0; i < 5; i++) {
            synced = ok(it.call(bursar1, HttpMethod.POST, "/api/v1/finance/accounting/sync?limit=10000", null));
            if (num(synced.get("remaining")) == 0) break;
        }
        assertThat(num(synced.get("remaining"))).isZero();
        UUID entry = jdbc.sql("SELECT id FROM finance.wallet_entry WHERE student_id = :s AND source_code = 'OVERPAID'").param("s", tw2).query(UUID.class).single();
        assertThat(jdbc.sql("""
                SELECT p.account || ':' || p.debit::int || ':' || p.credit::int || ':' || p.session
                  FROM finance.gl_journal j JOIN finance.gl_posting p ON p.journal_id = j.id
                 WHERE j.source_type = 'WALLET' AND j.source_ref = 'WALLET-' || :e ORDER BY p.line
                """).param("e", entry).query(String.class).list())
                .containsExactly(jdbc.sql("SELECT finance.gl_income_account('School fees')").query(String.class).single() + ":28605:0:" + a, "2100:0:28605:" + a);

        // the figures and the desk read the credits; the student sees them on both pages
        Map<String, Object> afterFig = figures(registrar);
        assertThat((Map<String, Object>) afterFig.get("requests")).containsEntry("pending", 0);
        Map<String, Object> credited = (Map<String, Object>) afterFig.get("credited");
        assertThat(credited).containsEntry("students", 6);
        assertThat(bd(credited.get("amount"))).isEqualByComparingTo(String.valueOf(5 * REPEAT + 14650));
        assertThat(bd(credited.get("inWallets"))).isEqualByComparingTo(String.valueOf(5 * REPEAT + 14650));
        assertThat(bd(credited.get("applied"))).isEqualByComparingTo("0");
        assertThat(row(registrar, tw3)).containsEntry("state", "CREDITED");
        Map<String, Object> feesA = ok(it.get(TestTokens.token(tw2, List.of("student")), "/api/v1/me/fees?session=" + a));
        assertThat(bd(feesA.get("excessDecided"))).isEqualByComparingTo("28605");
        assertThat(bd(feesA.get("excessRemaining"))).isEqualByComparingTo("0");
        assertThat(bd(feesA.get("excessRequested"))).isEqualByComparingTo("0");
        assertThat(bd(feesA.get("walletOverpaid"))).isEqualByComparingTo("28605");
        assertThat((List<Map<String, Object>>) feesA.get("overpayments")).extracting(o -> o.get("decision")).containsExactly("WALLET");
        Map<String, Object> walletB = ok(it.get(tw1Token, "/api/v1/me/wallet?session=" + b));
        assertThat(bd(walletB.get("overpaid"))).isEqualByComparingTo("28605");
        assertThat(walletB).doesNotContainKey("overpaidKeptBack");
        assertThat((List<?>) ((Map<String, Object>) walletB.get("eligibility")).get("sources")).as("the next session's fees are not paid yet").isEmpty();

        // the student applies it to the next session's fees on the Wallet page and pays only the rest
        Map<String, Object> applied = ok(it.call(tw1Token, HttpMethod.POST, "/api/v1/me/wallet/apply", Map.of("session", b)));
        assertThat(String.valueOf(applied)).contains("reference");
        assertThat(jdbc.sql("SELECT paid FROM finance.position(:s, :b)").param("s", tw1).param("b", b).query(BigDecimal.class).single()).isEqualByComparingTo("28605");
        assertThat(wallet(tw1)).isEqualByComparingTo("0");
        assertThat(jdbc.sql("SELECT amount::int FROM finance.payment_reference WHERE student_id = :s AND session = :b AND channel = 'NELFUND wallet'")
                .param("s", tw1).param("b", b).query(Integer.class).single()).isEqualTo(28605);
        Map<String, Object> feesAfter = ok(it.get(tw1Token, "/api/v1/me/fees?session=" + b));
        assertThat(feesAfter).doesNotContainKey("walletOverpaid");
        assertThat(ok(it.get(tw1Token, "/api/v1/me/wallet?session=" + b))).doesNotContainKey("overpaid");
        assertThat(bd(((Map<String, Object>) figures(registrar).get("credited")).get("applied"))).isEqualByComparingTo("28605");

        // the refund route for the students the wallet is refused to: withdrawn, deceased, graduated, left; and only the exact repeats in bulk
        refused(it.call(bursar1, HttpMethod.POST, BASE + "/refund", act(a, null, null, "refund everyone is never offered", false)), 422, "OVERPAID_BULK_WHO");
        refused(it.call(bursar1, HttpMethod.POST, BASE + "/refund", act(a, null, "ABOVE_FEE_LINE", "an above-the-fee-line cause is not refunded whole", false)), 422, "OVERPAID_BULK_WHO");
        Map<String, Object> noConfirm = act(a, List.of(wd), null, "the withdrawn student's repeat is refunded", false);
        noConfirm.put("confirmed", false);
        refused(it.call(bursar1, HttpMethod.POST, BASE + "/refund", noConfirm), 422, "OVERPAID_CONFIRM");
        UUID ap = student(9, "ACTIVE");   // paid twice, but the bank reported only one of the repeats: not an exact repeat on the records
        paid(ap, "OLD", 66745, 1, 30, true);
        paid(ap, "PORTAL", REPEAT, 2, 20, true);
        paid(ap, "PORTAL", REPEAT, 3, 14, false);
        Map<String, Object> byCause = ok(it.call(bursar1, HttpMethod.POST, BASE + "/refund", act(a, null, "PORTAL_TWICE", "refunded: the student has withdrawn; the repeat was looked at", false)));
        assertThat(byCause).containsEntry("refunds", 1).containsEntry("held", 1).containsEntry("apart", 1).containsEntry("requested", 0).containsEntry("unchecked", 0).containsEntry("remaining", 0);
        // named, the student who is not an exact repeat needs the fee setup confirmed, and is decided on his own
        assertThat(ok(it.call(bursar1, HttpMethod.POST, BASE + "/refund", act(a, List.of(ap), null, "the second payment is refunded; the bank's report was looked at", false))))
                .containsEntry("refunds", 0).containsEntry("unchecked", 1);
        assertThat(ok(it.call(bursar1, HttpMethod.POST, BASE + "/refund", act(a, List.of(ap, wd), null, "the second payment is refunded; the bank's report was looked at", true))))
                .containsEntry("refunds", 0).containsEntry("apart", 1);
        assertThat(ok(it.call(bursar1, HttpMethod.POST, BASE + "/refund", act(a, List.of(ap), null, "the second payment is refunded; the bank's report was looked at", true))))
                .containsEntry("refunds", 1);
        // the refund is raised on the Refunds & Credits desk, approved by another officer and paid with its transfer reference and date
        Map<String, Object> raised = jdbc.sql("SELECT id, reference, state, amount::int AS amount FROM finance.refund WHERE student_id = :s").param("s", wd).query().singleRow();
        assertThat(raised).containsEntry("state", "PROPOSED").containsEntry("amount", 28605);
        refresh(sao);
        assertThat(row(registrar, wd)).containsEntry("state", "REFUND_RAISED");
        UUID refundId = (UUID) raised.get("id");
        assertThat(it.call(bursar1, HttpMethod.POST, "/api/v1/finance/refunds/" + refundId + "/account",
                Map.of("bank", "011", "accountName", "Invented Student", "accountNumber", "0123 456 784")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(bursar1, HttpMethod.POST, "/api/v1/finance/refunds/" + refundId + "/approve", Map.of()).getStatusCode().value()).as("the officer who raised it does not approve it").isGreaterThanOrEqualTo(400);
        ok(it.call(bursar2, HttpMethod.POST, "/api/v1/finance/refunds/" + refundId + "/approve", Map.of()));
        assertThat(row(registrar, wd)).containsEntry("state", "REFUND_APPROVED");
        String today = java.time.LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).toString();
        ok(it.call(bursar2, HttpMethod.POST, "/api/v1/finance/refunds/" + refundId + "/pay", Map.of("reference", "TRF-IT-774", "paidOn", today)));
        assertThat(row(registrar, wd)).containsEntry("state", "REFUND_PAID");
        Map<String, Object> refundFig = (Map<String, Object>) figures(registrar).get("refunds");
        assertThat(refundFig).containsEntry("paid", 1);
        assertThat(refundFig).containsEntry("raised", 1);   // the second student's, raised and waiting

        // a refund raised by hand on Refunds & Credits against the graduated student's payment settles it: nothing remains to decide
        String portalRef = "MOAUM-OVR-" + tag + "-N7-3";
        Map<String, Object> hand = ok(it.call(bursar1, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", gr, "payer", "Invented Graduate",
                "reason", "the graduated student's repeat is refunded by hand", "amount", 28605, "source", portalRef)));
        assertThat(hand).containsEntry("state", "PROPOSED");
        refresh(sao);
        Map<String, Object> grRow = row(registrar, gr);
        assertThat(grRow).containsEntry("state", "REFUND_BY_HAND");
        assertThat(bd(grRow.get("remaining"))).isEqualByComparingTo("0");
        assertThat(bd(grRow.get("refunded_by_hand"))).isEqualByComparingTo("28605");
        assertThat(bd(grRow.get("decided"))).isEqualByComparingTo("28605");
        assertThat(((Map<String, Object>) figures(registrar).get("refunds"))).containsEntry("byHand", 1);
        // and the same payment is not refunded twice
        assertThat(it.call(bursar1, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("student", gr, "payer", "Invented Graduate",
                "reason", "the graduated student's repeat refunded a second time", "amount", 28605, "source", portalRef)).getStatusCode().value()).isEqualTo(422);
    }

    /* ═══ a student who pays again is decided again for what is above what is decided; a request is returned, withdrawn and made again ═══ */

    @Test
    void aStudentWhoPaysAgainIsDecidedAgainAndARequestIsReturnedWithdrawnAndMadeAgain() {
        UUID fd = twice(1, "ACTIVE");
        refresh(sao);
        Map<String, Object> first = request(sao, act(a, List.of(fd), null, "paid twice on the portal; the payments were looked at", false));
        assertThat(first).containsEntry("requested", 1);
        assertThat(decide(bursar2, Map.of("batch", first.get("batch"), "action", "APPROVE"))).containsEntry("credited", 1);
        assertThat(wallet(fd)).isEqualByComparingTo("28605");

        // the student pays a third time: a further decision for the amount above what is decided, never for what is decided already
        paid(fd, "PORTAL", REPEAT, 4, 1, true);
        Map<String, Object> stale = row(sao, fd);
        assertThat(stale).as("the kept list still reads the excess it was worked out with").containsEntry("state", "CREDITED");
        refresh(sao);
        Map<String, Object> again = row(sao, fd);
        assertThat(again).containsEntry("state", "UNDECIDED").containsEntry("cause", "PORTAL_TWICE").containsEntry("bulk", true);
        assertThat(bd(again.get("excess"))).isEqualByComparingTo("57210");
        assertThat(bd(again.get("decided"))).isEqualByComparingTo("28605");
        assertThat(bd(again.get("remaining"))).isEqualByComparingTo("28605");
        assertThat((List<?>) again.get("decisions")).hasSize(1);
        assertThat(num(((Map<String, Object>) figures(sao).get("paidTwice")).get("students"))).isEqualTo(1);
        Map<String, Object> second = request(sao, act(a, List.of(fd), null, "paid a third time; the payments were looked at", false));
        assertThat(second).containsEntry("requested", 1);
        assertThat(bd(second.get("amount"))).isEqualByComparingTo("28605");
        assertThat(decide(bursar3, Map.of("batch", second.get("batch"), "action", "APPROVE"))).containsEntry("credited", 1);
        assertThat(wallet(fd)).isEqualByComparingTo("57210");
        assertThat(jdbc.sql("SELECT decision || ':' || amount::int FROM finance.overpayment_decision WHERE student_id = :s AND session = :a AND superseded_at IS NULL")
                .param("s", fd).param("a", a).query(String.class).list()).containsExactly("WALLET:28605", "WALLET:28605");
        refresh(sao);
        Map<String, Object> done = row(sao, fd);
        assertThat(done).containsEntry("state", "CREDITED");
        assertThat((List<?>) done.get("decisions")).hasSize(2);
        assertThat(bd(done.get("remaining"))).isEqualByComparingTo("0");
        Map<String, Object> mine = ok(it.get(TestTokens.token(fd, List.of("student")), "/api/v1/me/fees?session=" + a));
        assertThat(bd(mine.get("excessDecided"))).isEqualByComparingTo("57210");
        assertThat(bd(mine.get("walletOverpaid"))).isEqualByComparingTo("57210");
        assertThat((List<?>) mine.get("overpayments")).hasSize(2);
        // nothing is left to refund: the refund route decides nothing for a student with nothing left
        assertThat(it.call(bursar1, HttpMethod.POST, BASE + "/refund", act(a, List.of(fd), null, "nothing is left of the second payment to refund", false)).getBody())
                .containsEntry("refunds", 0);

        // a request returned for correction, withdrawn and made again
        UUID rt = twice(2, "ACTIVE");
        refresh(sao);
        Map<String, Object> rq = request(sao, act(a, List.of(rt), null, "paid twice on the portal; the payments were looked at", false));
        assertThat(rq).containsEntry("requested", 1);
        Map<String, Object> shortNote = new HashMap<>(Map.of("batch", rq.get("batch"), "action", "RETURN", "note", "short"));
        refused(it.call(bursar2, HttpMethod.POST, BASE + "/credits/decide", shortNote), 422, "LEGACY_CREDIT_NOTE");
        Map<String, Object> returned = decide(bursar2, Map.of("batch", rq.get("batch"), "action", "RETURN", "note", "the second payment's receipt is not attached"));
        assertThat(returned).containsEntry("returned", 1).containsEntry("credited", 0);
        assertThat(wallet(rt)).isEqualByComparingTo("0");
        assertThat(count("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND template_key = 'LEGACY_CREDIT_POSTED'", rt)).as("the student is not told of a return").isZero();
        assertThat(count("SELECT count(*) FROM platform.notice WHERE about_kind = 'person' AND about_id = :p AND template_key = 'OVERPAID_CREDITS_DECIDED'", saoId)).isGreaterThanOrEqualTo(2);
        assertThat(row(sao, rt)).containsEntry("state", "CREDIT_RETURNED");
        assertThat(((List<Map<String, Object>>) it.getList(sao, BASE + "/credits?session=" + a + "&status=RETURNED_FOR_CORRECTION").getBody())).hasSize(1);
        // a returned request stands in the way of another until it is withdrawn
        Map<String, Object> blocked = request(sao, act(a, List.of(rt), null, "paid twice on the portal; the payments were looked at", false));
        assertThat(blocked).containsEntry("requested", 0);
        assertThat(codes(blocked)).containsExactly("REQUEST_OPEN");
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/credits/withdraw", Map.of("batch", rq.get("batch"), "reason", "withdrawn by someone with no office on it")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(sao, HttpMethod.POST, BASE + "/credits/withdraw", Map.of("batch", rq.get("batch"), "reason", "short")).getStatusCode().value()).isIn(400, 422);
        assertThat(ok(it.call(sao, HttpMethod.POST, BASE + "/credits/withdraw", Map.of("batch", rq.get("batch"), "reason", "returned, and made again on a corrected request")))).containsEntry("withdrawn", 1);
        assertThat(ok(it.call(sao, HttpMethod.POST, BASE + "/credits/withdraw", Map.of("batch", rq.get("batch"), "reason", "returned, and made again on a corrected request")))).containsEntry("withdrawn", 0);
        assertThat(row(sao, rt)).containsEntry("state", "UNDECIDED");
        Map<String, Object> third = request(sao, act(a, List.of(rt), null, "paid twice on the portal; the payments were looked at again", false));
        assertThat(third).containsEntry("requested", 1);
        // rejected: the student stays undecided; a request made again is withdrawn by a Bursary officer who did not make it
        assertThat(decide(bursar2, Map.of("batch", third.get("batch"), "action", "REJECT", "note", "the second payment is a part payment of the next session"))).containsEntry("rejected", 1);
        assertThat(row(sao, rt)).containsEntry("state", "UNDECIDED");
        Map<String, Object> fourth = request(sao, act(a, List.of(rt), null, "paid twice on the portal; the payments were looked at once more", false));
        assertThat(fourth).containsEntry("requested", 1);
        assertThat(ok(it.call(bursar3, HttpMethod.POST, BASE + "/credits/withdraw", Map.of("batch", fourth.get("batch"), "reason", "the Bursary withdraws a mistaken request")))).containsEntry("withdrawn", 1);
        assertThat(count("SELECT count(*) FROM finance.legacy_credit_request WHERE student_id = :s AND status = 'WITHDRAWN'", rt)).isEqualTo(2);
        assertThat(count("SELECT count(*) FROM finance.legacy_credit_request WHERE student_id = :s AND status = 'REJECTED'", rt)).isEqualTo(1);
        assertThat(wallet(rt)).isEqualByComparingTo("0");
    }

    /* ═══ the wallet's overpaid money is refunded by its source; a charge that rose after a decision keeps part of it back ═══ */

    @Test
    void aWalletRefundOfOverpaidFeesNamesItsSourceAndAChargeThatRoseKeepsWhatIsOwedBack() {
        UUID g1 = twice(1, "ACTIVE");
        // the student's current session is session a (as an MBBS student's own session is), so a charge that rises in it is read against the credit
        it.db(() -> jdbc.sql("INSERT INTO people.study_session (student_id, session, level, set_by, set_office, approval) VALUES (:s, :a, 100, :by, 'ict', 'NOT_REQUIRED')")
                .param("s", g1).param("a", a).param("by", UUID.randomUUID()).update());
        refresh(sao);
        Map<String, Object> rq = request(sao, act(a, List.of(g1), null, "paid twice on the portal; the payments were looked at", false));
        assertThat(decide(bursar2, Map.of("batch", rq.get("batch"), "action", "APPROVE"))).containsEntry("credited", 1);
        String student = TestTokens.token(g1, List.of("student"));
        assertThat(wallet(g1)).isEqualByComparingTo("28605");

        // overpaid school fees are refundable from the session they were overpaid in (its fees are paid in full), by their own source
        Map<String, Object> w = ok(it.get(student, "/api/v1/me/wallet?session=" + a));
        assertThat(bd(w.get("overpaid"))).isEqualByComparingTo("28605");
        assertThat(w).doesNotContainKey("overpaidKeptBack");
        assertThat((List<Map<String, Object>>) ((Map<String, Object>) w.get("eligibility")).get("sources"))
                .extracting(x -> x.get("code") + ":" + bd(x.get("refundable")).intValue() + ":" + x.get("nature")).containsExactly("OVERPAID:28605:SELF");

        // the charge rises after the credit: the session's fees are short of what the decision gave; the desk lists the student as decided above
        // the excess, and what the wallet still holds of it is kept back from a refund — the page says so and the figure the server never exceeds falls
        levy(true);
        refresh(sao);
        Map<String, Object> over = row(sao, g1);
        assertThat(over).containsEntry("state", "OVER_DECIDED").containsEntry("suggested", "RECOVER");
        assertThat(bd(over.get("over_decided"))).isEqualByComparingTo("20000");
        assertThat(bd(over.get("excess"))).isEqualByComparingTo("8605");
        Map<String, Object> overFig = (Map<String, Object>) figures(sao).get("overDecided");
        assertThat(overFig).containsEntry("students", 1);
        assertThat(bd(overFig.get("amount"))).isEqualByComparingTo("20000");
        Map<String, Object> wKept = ok(it.get(student, "/api/v1/me/wallet?session=" + a));
        assertThat(bd(wKept.get("overpaid"))).isEqualByComparingTo("28605");
        assertThat(bd(wKept.get("overpaidKeptBack"))).isEqualByComparingTo("20000");
        assertThat((List<Map<String, Object>>) ((Map<String, Object>) wKept.get("eligibility")).get("sources"))
                .extracting(x -> x.get("code") + ":" + bd(x.get("refundable")).intValue()).containsExactly("OVERPAID:8605");
        ResponseEntity<Map> tooMuch = it.call(student, HttpMethod.POST, "/api/v1/me/wallet/withdrawal",
                Map.of("session", a, "amount", 28605, "bank", "Zenith", "accountNo", "0123 456 788", "accountName", "ZZOVR", "source", "OVERPAID"));
        assertThat(tooMuch.getStatusCode().value()).as(String.valueOf(tooMuch.getBody())).isEqualTo(422);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.wallet_withdrawal WHERE student_id = :s").param("s", g1).query(Long.class).single()).isZero();

        // the charge put back, all of it is refundable again; the student asks for it by its source
        levy(false);
        Map<String, Object> wBack = ok(it.get(student, "/api/v1/me/wallet?session=" + a));
        assertThat(wBack).doesNotContainKey("overpaidKeptBack");
        assertThat((List<Map<String, Object>>) ((Map<String, Object>) wBack.get("eligibility")).get("sources"))
                .extracting(x -> x.get("code") + ":" + bd(x.get("refundable")).intValue()).containsExactly("OVERPAID:28605");
        Map<String, Object> request = ok(it.call(student, HttpMethod.POST, "/api/v1/me/wallet/withdrawal",
                Map.of("session", a, "amount", 28605, "bank", "Zenith", "accountNo", "0123 456 788", "accountName", "ZZOVR", "source", "OVERPAID")));
        assertThat(request).containsEntry("source_code", "OVERPAID");
        String withdrawal = String.valueOf(request.get("id"));
        assertThat(ok(it.get(student, "/api/v1/me/wallet?session=" + a))).as("the money asked for is held").doesNotContainKey("overpaid");

        // a charge that rises after the refund was asked for: refused at approval, with the figure it may have
        levy(true);
        ResponseEntity<Map> kept = it.call(bursar2, HttpMethod.POST, "/api/v1/funding/withdrawals/" + withdrawal + "/approve", Map.of());
        assertThat(kept.getStatusCode().value()).as(String.valueOf(kept.getBody())).isEqualTo(422);
        assertThat(kept.getBody()).containsEntry("code", "WALLET_REFUND_KEPT_BACK");
        // the charge put back, the refund is approved by another officer and paid with its reference and date
        levy(false);
        ok(it.call(bursar2, HttpMethod.POST, "/api/v1/funding/withdrawals/" + withdrawal + "/approve", Map.of()));
        String today = java.time.LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).toString();
        ok(it.call(bursar3, HttpMethod.POST, "/api/v1/funding/withdrawals/" + withdrawal + "/pay", Map.of("ref", "TRF-IT-774", "paidOn", today)));
        assertThat(wallet(g1)).isEqualByComparingTo("0");
        assertThat(ok(it.get(student, "/api/v1/me/wallet?session=" + a))).doesNotContainKey("overpaid");
        refresh(sao);
        assertThat(row(sao, g1)).containsEntry("state", "CREDITED");
    }

    /** a charge of ₦20,000 added to the session's fees for the programme (the levy), or taken away again */
    private void levy(boolean on) {
        it.db(() -> {
            if (on) {
                jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'Development levy', 20000, NULL, :p)")
                        .param("s", a).param("p", prog).update();
            } else {
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s AND item = 'Development levy'").param("s", a).update();
            }
            return null;
        });
    }

    /* ═══ the job ═══ */

    @Test
    void theJobIsOffUnderTheTestsAndTheKeptListIsWorkedOutOnlyWhenAskedFor() {
        // the switch reads false from src/test/resources/config/application.properties (merged over the main file), and the schedules do nothing
        assertThat(jobEnabled).isFalse();
        assertThat((Boolean) ReflectionTestUtils.getField(watch, "enabled")).isFalse();
        String current = jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
        it.db(() -> jdbc.sql("DELETE FROM finance.overpaid_snapshot_run WHERE session = :s").param("s", current).update());
        ReflectionTestUtils.invokeMethod(watch, "scheduledRefreshDue");
        ReflectionTestUtils.invokeMethod(watch, "scheduledRefreshAll");
        assertThat(count("SELECT count(*) FROM finance.overpaid_snapshot_run WHERE session = :s", current)).as("no scheduled refresh ran").isZero();
        // the methods the tests call themselves do their work: due once (never worked out), not due again
        assertThat(watch.refreshDue()).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM finance.overpaid_snapshot_run WHERE session = :s", current)).isEqualTo(1);
        assertThat(watch.refreshDue()).isZero();

        // a session of the test's own: due until it is worked out, not after, due again when a school-fees payment of it is confirmed
        UUID s1 = twice(1, "ACTIVE");
        assertThat(jdbc.sql("SELECT finance.overpaid_refresh_due(:s)").param("s", a).query(Boolean.class).single()).isTrue();
        assertThat(figures(registrar)).containsEntry("computed", false);
        Map<String, Object> fig = refresh(sao);
        assertThat(fig).containsEntry("computed", true);
        assertThat(num(fig.get("students"))).isEqualTo(1);
        assertThat(jdbc.sql("SELECT finance.overpaid_refresh_due(:s)").param("s", a).query(Boolean.class).single()).isFalse();
        UUID s2 = twice(2, "ACTIVE", true);
        assertThat(jdbc.sql("SELECT finance.overpaid_refresh_due(:s)").param("s", a).query(Boolean.class).single()).as("a payment of the session was confirmed since").isTrue();
        assertThat(num(figures(registrar).get("students"))).as("the kept list is not read live").isEqualTo(1);
        assertThat(watch.refreshAll()).isGreaterThanOrEqualTo(1);
        assertThat(jdbc.sql("SELECT finance.overpaid_refresh_due(:s)").param("s", a).query(Boolean.class).single()).isFalse();
        assertThat(num(figures(registrar).get("students"))).isEqualTo(2);
        assertThat(row(registrar, s2)).containsEntry("cause", "PORTAL_TWICE");
        // the money never reads the kept list: a student paid since the last refresh is requested from the live read
        UUID s3 = twice(3, "ACTIVE");
        Map<String, Object> live = request(sao, act(a, List.of(s3), null, "paid twice on the portal; the payments were looked at", false));
        assertThat(live).containsEntry("requested", 1);
        assertThat(row(registrar, s3)).as("not on the kept list until it is worked out again").isNull();
        // a session not on the calendar is refused
        refused(it.call(sao, HttpMethod.POST, BASE + "/refresh", Map.of("session", "2999/3000")), 422, "OVERPAID_SESSION");
        assertThat(s1).isNotEqualTo(s2);
    }
}
