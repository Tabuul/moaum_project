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
 * V499, end to end as the Bursary does it: the old-portal fees history is uploaded and posted to the ledger; the reset (the word
 * RESET, the Bursary only) deletes it in batches, each record's ledger journal reversed and the record kept on file, while the
 * student's payment made on the portal stays as it was; the same file uploaded again is posted once, never refused by the
 * journal of the payment it replaced. Each run files everything under its own session. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class LegacyFeesResetIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String bursar = ItSupport.token("bursar");
    /** the run's own session: its fee line applies to every student of the programme, so it is taken away after the test (a
     *  planned session with fees stated is the session a later test's student reads by default) */
    String ses;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @AfterEach
    void clean() {
        if (ses != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", ses).update());
    }

    private static Map<String, Object> row(String matric, String session, String semester, String amount, String paidOn) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("matric", matric);
        r.put("session", session);
        r.put("semester", semester);
        r.put("level", "100");
        r.put("amount", amount);
        r.put("purpose", "SCHOOL FEES");
        r.put("paidOn", paidOn);
        r.put("note", "");
        return r;
    }

    /** the ledger posts everything waiting, a batch at a time, as the Accounting screen does */
    private void syncLedger() {
        for (int i = 0; i < 200; i++) {
            ResponseEntity<Map> s = it.call(bursar, HttpMethod.POST, "/api/v1/finance/accounting/sync?limit=10000", null);
            assertThat(s.getStatusCode().value()).as(String.valueOf(s.getBody())).isEqualTo(200);
            if (((Number) s.getBody().get("remaining")).longValue() == 0) return;
        }
        throw new AssertionError("the ledger sync did not finish");
    }

    private long count(String sql, Map<String, Object> params) {
        var q = jdbc.sql(sql);
        for (var e : params.entrySet()) q = q.param(e.getKey(), e.getValue());
        return q.query(Long.class).single();
    }

    @Test
    void theResetReversesTheLedgerKeepsWhatItDeletedNeverTouchesAPortalPaymentAndAReloadPostsOnce() {
        Random random = new Random();
        String tag = String.format("%04d", random.nextInt(10_000));
        int year = 2600 + random.nextInt(300);
        ses = year + "/" + (year + 1);
        String yy = String.format("%02d", year % 100);
        it.session(ses, year);
        UUID student = it.student("ZZLEGRESET" + tag, "C00023", "MOAUM/ADM/" + yy + "/77" + tag, "MOAUM/LGR/" + yy + "/" + tag, 100);
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, NULL, 'C00023')")
                .param("s", ses).update());

        // the old portal's payments uploaded, and one payment made on the portal itself
        List<Map<String, Object>> rows = List.of(row(matric, ses, "First", "60000", year + "-11-02"), row(matric, ses, "Second", "40000", (year + 1) + "-03-10"));
        ResponseEntity<Map> imp = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", rows));
        assertThat(imp.getStatusCode().value()).as(String.valueOf(imp.getBody())).isEqualTo(200);
        assertThat(((Number) imp.getBody().get("cleared")).intValue()).isEqualTo(2);
        String portalRef = "MOAUM-LGRIT-" + year + "-" + tag;
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                VALUES (:s, :ses, :r, 'School fees ' || :ses, 25000, now() + interval '1 day', now(), :s, 'Card · Paystack', :r)
                """).param("s", student).param("ses", ses).param("r", portalRef).update());
        syncLedger();
        Map<String, Object> p = Map.of("s", student, "ses", ses);
        assertThat(count("SELECT count(*) FROM finance.gl_journal j JOIN finance.payment_reference r ON r.reference = j.source_ref AND j.source_type = 'PAYMENT' WHERE r.student_id = :s AND r.session = :ses AND r.channel = 'Legacy'", p))
                .as("both old-portal payments are on the books").isEqualTo(2);

        // only the Bursary resets, and only on the word
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/finance/legacy-fees/reset", Map.of("session", ses, "confirm", "RESET")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/reset", Map.of("session", ses, "confirm", "yes")).getStatusCode().value()).isEqualTo(422);

        // the reset, asked until none is left
        long deleted = 0, reversed = 0;
        for (int i = 0; i < 50; i++) {
            ResponseEntity<Map> r = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/reset", Map.of("session", ses, "confirm", "RESET"));
            assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
            deleted += ((Number) r.getBody().get("deleted")).longValue();
            reversed += ((Number) r.getBody().get("ledger_reversed")).longValue();
            if (((Number) r.getBody().get("remaining")).longValue() == 0) break;
        }
        assertThat(deleted).isEqualTo(2);
        assertThat(reversed).isEqualTo(2);
        assertThat(count("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND session = :ses AND channel = 'Legacy'", p)).isZero();
        assertThat(count("SELECT count(*) FROM finance.legacy_payment_reset WHERE student_id = :s AND session = :ses AND ledger_journal IS NOT NULL AND reversal_journal IS NOT NULL", p))
                .as("what was deleted is kept, with its journal and the reversal").isEqualTo(2);
        // the books: each old journal reversed, so the bank account nets to the portal payment alone
        assertThat(count("""
                SELECT count(*) FROM finance.legacy_payment_reset x JOIN finance.gl_journal j ON j.id = x.ledger_journal
                 WHERE x.student_id = :s AND x.session = :ses AND j.status = 'REVERSED' AND j.source_type = 'PAYMENT_RESET'
                   AND EXISTS (SELECT 1 FROM finance.gl_journal v WHERE v.reverses = j.id)
                """, p)).isEqualTo(2);
        // the payment made on the portal is untouched, and still on the books
        assertThat(count("SELECT count(*) FROM finance.payment_reference WHERE reference = :r AND amount = 25000 AND confirmed_at IS NOT NULL", Map.of("r", portalRef))).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM finance.gl_journal WHERE source_type = 'PAYMENT' AND source_ref = :r AND status = 'POSTED'", Map.of("r", portalRef))).isEqualTo(1);

        // the same file again: recorded, and posted once
        ResponseEntity<Map> again = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", rows));
        assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(200);
        assertThat(((Number) again.getBody().get("cleared")).intValue()).isEqualTo(2);
        syncLedger();
        assertThat(count("""
                SELECT count(*) FROM finance.payment_reference r
                  JOIN finance.gl_journal j ON j.source_type = 'PAYMENT' AND j.source_ref = r.reference AND j.status = 'POSTED'
                 WHERE r.student_id = :s AND r.session = :ses AND r.channel = 'Legacy'
                """, p)).as("each reloaded payment is posted once").isEqualTo(2);
        assertThat(count("""
                SELECT coalesce(sum(pg.debit - pg.credit), 0)::bigint FROM finance.gl_posting pg JOIN finance.gl_journal j ON j.id = pg.journal_id
                 WHERE pg.account = '1010' AND (j.source_ref IN (SELECT reference FROM finance.payment_reference WHERE student_id = :s AND session = :ses)
                    OR j.source_ref IN (SELECT x.reference || '#' || x.id FROM finance.legacy_payment_reset x WHERE x.student_id = :s AND x.session = :ses)
                    OR j.reverses IN (SELECT x.ledger_journal FROM finance.legacy_payment_reset x WHERE x.student_id = :s AND x.session = :ses))
                """, p)).as("the bank account holds each payment once: 60,000 + 40,000 + 25,000").isEqualTo(125_000L);
    }
}
