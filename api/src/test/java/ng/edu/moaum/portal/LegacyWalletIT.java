package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
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
 * The old portal's e-wallet reconciled (V583), over the API: a student's old top-ups and the fees paid from the old wallet, as the
 * old-fees export brought them, leave a balance the reconciliation computes; the Students Account Officer verifies it, the officer
 * who verified it cannot post it, a Bursar officer posts it once as a LEGACY_WALLET credit on the wallet, the student applies it
 * to the session's fees through the wallet that exists (the fee position settles by it, the payment confirmed from the wallet, not
 * the bank), a second run posts nothing twice, a student who paid from the old wallet more than the top-ups on file is held for
 * review until the old portal's statement is entered, and Audit reads but changes nothing. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class LegacyWalletIT {

    static final String PATH = "/api/v1/finance/legacy-wallet";

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

    /** an old-portal payment as the old-fees export brings it: a top-up by its purpose, or a fee paid by the method on the note */
    private void legacy(UUID student, String purpose, String method, long amount, String ses) {
        String ref = "MOAUM-LEG-ITLW-" + UUID.randomUUID().toString().substring(0, 12).toUpperCase();
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:st, :s, :r, :p, :a, now(), now() - interval '30 days', gen_random_uuid(), 'Legacy', 'LEG-' || :r,
                        'Imported from the old portal ' || chr(183) || ' ' || :m || ' ' || chr(183) || ' old ref PR' || substr(:r, 16))
                """).param("st", student).param("s", ses).param("r", ref).param("p", purpose).param("a", amount).param("m", method).update());
    }

    private static BigDecimal money(Object v) {
        return new BigDecimal(String.valueOf(v));
    }

    private Map<String, Object> rowOf(String token, UUID student) {
        ResponseEntity<Map> r = it.get(token, PATH + "/students/" + student);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return (Map<String, Object>) r.getBody().get("row");
    }

    @Test
    void aBalanceIsComputedVerifiedByOneOfficerPostedByAnotherAndAppliedToFeesOnce() {
        int year = 3380 + new Random().nextInt(15);
        session = year + "/" + (year + 1);
        it.session(session, year);
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 180000, NULL, 'C00023')").param("s", session).update());
        UUID student = it.student(it.freeSurname("ZZLWA"), "C00023", null, it.freeNumber("MOAUM/LWA/86/", 6), 200);
        // topped up 150,000 on the old portal, paid 50,000 of fees from the wallet there: 100,000 left
        legacy(student, "E-WALLET TOP-UP (legacy) · semester 1", "Interswitch", 100000, "2024/2025");
        legacy(student, "E-WALLET TOP-UP (legacy) · semester 2", "Interswitch", 50000, "2024/2025");
        legacy(student, "School fees (legacy) · semester 1", "E-Wallet", 50000, "2024/2025");
        UUID over = it.student(it.freeSurname("ZZLWB"), "C00023", null, it.freeNumber("MOAUM/LWB/86/", 6), 200);
        legacy(over, "E-WALLET TOP-UP (legacy) · semester 1", "Interswitch", 20000, "2024/2025");
        legacy(over, "School fees (legacy) · semester 1", "E-Wallet", 60000, "2024/2025");

        String sao = TestTokens.token(it.person("ZZ-LW-S1", "ZZLWS1"), List.of("studentaccounts"));
        String bursar = TestTokens.token(it.person("ZZ-LW-B1", "ZZLWB1"), List.of("bursar"));
        String audit = TestTokens.token(it.person("ZZ-LW-A1", "ZZLWA1"), List.of("audit"));

        ResponseEntity<Map> run = it.call(sao, HttpMethod.POST, PATH + "/compute", Map.of());
        assertThat(run.getStatusCode().value()).as(String.valueOf(run.getBody())).isEqualTo(200);
        Map<String, Object> mine = rowOf(sao, student);
        assertThat(mine).containsEntry("status", "COMPUTED").containsEntry("topup_count", 2).containsEntry("used_count", 1);
        assertThat(money(mine.get("topups"))).isEqualByComparingTo("150000");
        assertThat(money(mine.get("used"))).isEqualByComparingTo("50000");
        assertThat(money(mine.get("available"))).isEqualByComparingTo("100000");
        Map<String, Object> theirs = rowOf(sao, over);
        assertThat(theirs).containsEntry("status", "REQUIRES_REVIEW").containsEntry("reason_code", "USED_EXCEEDS_TOPUPS");
        assertThat(money(theirs.get("available"))).isEqualByComparingTo("0");

        // Audit reads, never verifies; the Students Account Officer verifies; the same officer cannot post
        assertThat(it.getList(audit, PATH + "/rows?status=COMPUTED").getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(audit, HttpMethod.POST, PATH + "/verify", Map.of("ids", List.of(mine.get("id")))).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> verified = it.call(sao, HttpMethod.POST, PATH + "/verify", Map.of("ids", List.of(mine.get("id"), theirs.get("id")), "note", "checked against the old portal"));
        assertThat(verified.getStatusCode().value()).as(String.valueOf(verified.getBody())).isEqualTo(200);
        assertThat(verified.getBody()).containsEntry("verified", 1);
        assertThat(it.call(sao, HttpMethod.POST, PATH + "/post", Map.of("ids", List.of(mine.get("id")))).getStatusCode().value()).isEqualTo(403);
        String sao2Bursar = TestTokens.token(it.person("ZZ-LW-S1", "ZZLWS1"), List.of("bursar"));   // the verifier, now acting as Bursar: still not the one to post
        ResponseEntity<Map> self = it.call(sao2Bursar, HttpMethod.POST, PATH + "/post", Map.of("ids", List.of(mine.get("id"))));
        assertThat(self.getStatusCode().value()).as(String.valueOf(self.getBody())).isEqualTo(200);
        assertThat(self.getBody()).containsEntry("posted", 0).containsEntry("skipped", 1);
        assertThat(String.valueOf(((List<Map<String, Object>>) self.getBody().get("skipped_why")).get(0).get("why"))).contains("verified by you");

        ResponseEntity<Map> posted = it.call(bursar, HttpMethod.POST, PATH + "/post", Map.of("ids", List.of(mine.get("id"), theirs.get("id")), "note", "first posting"));
        assertThat(posted.getStatusCode().value()).as(String.valueOf(posted.getBody())).isEqualTo(200);
        assertThat(posted.getBody()).containsEntry("posted", 1).containsEntry("skipped", 1);
        assertThat(String.valueOf(posted.getBody().get("batch_ref"))).matches("LEGACY-WALLET/[0-9]{4}/[0-9]{6}");
        assertThat(money(posted.getBody().get("amount"))).isEqualByComparingTo("100000");
        Map<String, Object> after = rowOf(bursar, student);
        assertThat(after).containsEntry("status", "POSTED");
        assertThat(money(after.get("remaining"))).isEqualByComparingTo("100000");
        // one credit on the wallet, of the student's own nature, dated the old top-up, drawn from suspense on the ledger
        Map<String, Object> entry = jdbc.sql("SELECT kind, source_code, amount, (at < now() - interval '20 days') AS old FROM finance.wallet_entry WHERE student_id = :s AND source_code = 'LEGACY_WALLET'")
                .param("s", student).query().singleRow();
        assertThat(entry).containsEntry("kind", "CREDIT").containsEntry("old", true);
        assertThat(money(entry.get("amount"))).isEqualByComparingTo("100000");
        assertThat(jdbc.sql("SELECT finance.gl_wallet_credit_account('LEGACY_WALLET', false)").query(String.class).single()).isEqualTo("3900");
        // the student's wallet reads the balance by its source, from the old portal
        String me = TestTokens.token(student, List.of("student"));
        ResponseEntity<Map> wallet = it.get(me, "/api/v1/me/wallet");
        assertThat(wallet.getStatusCode().value()).as(String.valueOf(wallet.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) wallet.getBody().get("balances")).anySatisfy(b -> {
            assertThat(b.get("source_code")).isEqualTo("LEGACY_WALLET");
            assertThat(money(b.get("available"))).isEqualByComparingTo("100000");
        });
        assertThat((List<Map<String, Object>>) wallet.getBody().get("statement")).anySatisfy(e -> assertThat(e).containsEntry("origin", "OLD_PORTAL"));

        // applied to the session's fees through the wallet that exists: the fees are short by 80,000, the wallet empty, no new cash
        ResponseEntity<Map> applied = it.call(me, HttpMethod.POST, "/api/v1/me/wallet/apply", Map.of("session", session));
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        Map<String, Object> pos = jdbc.sql("SELECT paid, balance FROM finance.position(:s, :ses)").param("s", student).param("ses", session).query().singleRow();
        assertThat(money(pos.get("paid"))).isEqualByComparingTo("100000");
        assertThat(money(pos.get("balance"))).isEqualByComparingTo("80000");
        assertThat(jdbc.sql("SELECT channel FROM finance.payment_reference WHERE student_id = :s AND session = :ses AND confirmed_at IS NOT NULL AND purpose LIKE 'School fees%'")
                .param("s", student).param("ses", session).query(String.class).single()).isEqualTo("NELFUND wallet");
        assertThat(money(jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", student).query(BigDecimal.class).single())).isEqualByComparingTo("0");
        Map<String, Object> done = rowOf(bursar, student);
        assertThat(money(done.get("applied"))).isEqualByComparingTo("100000");
        assertThat(money(done.get("remaining"))).isEqualByComparingTo("0");

        // a second run and a second posting change nothing: one credit a student, ever
        assertThat(it.call(sao, HttpMethod.POST, PATH + "/compute", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(rowOf(sao, student)).containsEntry("status", "POSTED");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.wallet_entry WHERE student_id = :s AND kind = 'CREDIT' AND source_code = 'LEGACY_WALLET'").param("s", student).query(Long.class).single()).isEqualTo(1L);

        // the one under review: the old portal's statement, entered by the officer, governs and is verified afresh
        ResponseEntity<Map> stated = it.call(sao, HttpMethod.POST, PATH + "/students/" + over + "/statement",
                Map.of("topups", 80000, "used", 60000, "balance", 20000, "source", "old portal wallet page, 19 Oct 2026", "note", "earlier top-up outside the export"));
        assertThat(stated.getStatusCode().value()).as(String.valueOf(stated.getBody())).isEqualTo(200);
        Map<String, Object> judged = (Map<String, Object>) stated.getBody().get("row");
        assertThat(judged).containsEntry("status", "COMPUTED").containsEntry("reason_code", "STATEMENT_DIFFERS");
        assertThat(money(judged.get("available"))).isEqualByComparingTo("20000");
        ResponseEntity<Map> figures = it.get(audit, PATH + "/figures");
        assertThat(figures.getStatusCode().value()).isEqualTo(200);
        assertThat(((Number) figures.getBody().get("posted")).intValue()).isGreaterThanOrEqualTo(1);
        // the old top-up reads as a wallet deposit, not other income
        assertThat(jdbc.sql("SELECT finance.categorise(NULL, 'E-WALLET TOP-UP (legacy) · semester 1')").query(String.class).single()).isEqualTo("WALLET");
        // the full record shows it
        ResponseEntity<Map> full = it.get(bursar, "/api/v1/student/students/" + student + "/full/finance");
        assertThat(full.getStatusCode().value()).isEqualTo(200);
        assertThat((Map<String, Object>) full.getBody().get("legacyWallet")).containsEntry("status", "POSTED");
    }
}
