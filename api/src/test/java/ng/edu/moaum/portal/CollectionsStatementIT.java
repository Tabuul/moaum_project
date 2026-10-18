package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
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
 * V552: the collections account's statement matched to what the portal received. Internal Audit uploads it: a credit with a
 * confirmed reference and its amount is matched, one with another amount differs, one for a reference never confirmed is
 * received-not-confirmed, a gateway's one sum is unmatched until marked the settlement of the gateway's day; a payment confirmed
 * and on no line is listed as not seen in the bank. The Bursary sends the unconfirmed credit to the bank credits, proposed against
 * its reference, and another officer's approval confirms it. A student may do none of it. The wallet's opening balance is read by
 * Internal Audit and reclassified by the Bursary only, never more than remains in suspense. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CollectionsStatementIT {

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

    /** six digits no portal reference of this shape uses yet, so a reference the test invents is new on any database */
    private String freeTag() {
        for (int i = 0; i < 500; i++) {
            String tag = String.valueOf(java.util.concurrent.ThreadLocalRandom.current().nextInt(100_000, 1_000_000));
            if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference LIKE 'MOAUM-FEE-' || :t || '-%')")
                    .param("t", tag).query(Boolean.class).single()) {
                return tag;
            }
        }
        throw new IllegalStateException("no free reference tag");
    }

    @Test
    void theCollectionsStatementIsMatchedToWhatWasReceivedAndTheUnconfirmedCreditGoesToTheBankCredits() {
        String tag = freeTag();
        String audit = ItSupport.token("audit");
        String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String checker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String student = TestTokens.token(UUID.randomUUID(), List.of("student"));
        String session = "9961/9962";
        it.session(session, 9961);
        UUID s = it.student(it.freeSurname("ZZCOLLECT"), "C00023", null, it.freeNumber("MOAUM/MTC/61/", 4), 100);
        String gateway = "IT Gateway " + tag;
        // the statement's day and its payments' are the session's own, far ahead, so its period holds no other test's payments
        String today = "9961-10-15";
        String ok = "MOAUM-FEE-" + tag + "-0001", diff = "MOAUM-FEE-" + tag + "-0002", open = "MOAUM-FEE-" + tag + "-0003",
               gw1 = "MOAUM-FEE-" + tag + "-0004", gw2 = "MOAUM-FEE-" + tag + "-0005", miss = "MOAUM-FEE-" + tag + "-0006";
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                SELECT :s, :ses, x.ref, 'School fees ' || :ses, x.amount, :day::timestamp AT TIME ZONE 'Africa/Lagos', now() + interval '7 days',
                       CASE WHEN x.channel IS NULL THEN NULL ELSE (:day::timestamp + interval '10 hours') AT TIME ZONE 'Africa/Lagos' END,
                       CASE WHEN x.channel IS NULL THEN NULL ELSE gen_random_uuid() END, x.channel, CASE WHEN x.channel IS NULL THEN NULL ELSE 'RCT-IT-' || x.ref END, 'V552 IT'
                  FROM (VALUES (:ok, 5000, 'Bank transfer'), (:diff, 3000, 'Card · Paystack'), (:open, 2500, NULL), (:gw1, 1000, :gw), (:gw2, 1000, :gw),
                               (:miss, 700, 'Bank transfer')) x (ref, amount, channel)
                """).param("s", s).param("ses", session).param("ok", ok).param("diff", diff).param("open", open).param("gw1", gw1).param("gw2", gw2)
                .param("miss", miss).param("gw", gateway).param("day", today).update());
        List<Map<String, Object>> rows = List.of(
                Map.of("date", today, "reference", ok, "description", "Transfer", "credit", "5,000.00"),
                Map.of("date", today, "description", "NIP TRF/" + diff.replace("-", "") + "/ZZCOLLECT", "credit", "3100"),
                Map.of("date", today, "description", "Transfer " + open, "credit", "2500"),
                Map.of("date", today, "description", "SETTLEMENT " + tag, "credit", "1950"),
                Map.of("date", today, "description", "charges", "debit", "100"));

        // a student may not upload one; Internal Audit uploads it and the credits are matched
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/finance/collections/statements", Map.of("label", "x", "rows", rows)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> st = it.call(audit, HttpMethod.POST, "/api/v1/finance/collections/statements", Map.of("label", "IT V552 " + tag, "fileName", "collections.csv", "rows", rows));
        assertThat(st.getStatusCode().value()).as(String.valueOf(st.getBody())).isEqualTo(200);
        List<Map> lines = (List<Map>) st.getBody().get("lines");
        assertThat(lines).extracting(l -> l.get("line_no") + ":" + l.get("status") + ":" + l.get("matched_reference"))
                .containsExactly("1:MATCHED:" + ok, "2:AMOUNT_DIFFERS:" + diff, "3:RECEIVED_NOT_CONFIRMED:" + open, "4:UNMATCHED:null", "5:DEBIT:null");
        assertThat(String.valueOf(lines.get(0).get("payer"))).startsWith("ZZCOLLECT");
        assertThat((List<Map>) st.getBody().get("notReceived")).filteredOn(n -> String.valueOf(n.get("reference")).startsWith("MOAUM-FEE-" + tag))
                .extracting(n -> n.get("reference")).containsExactlyInAnyOrder(gw1, gw2, miss);
        assertThat((List<Map>) st.getBody().get("unmatchedDays")).filteredOn(d -> gateway.equals(d.get("channel")))
                .extracting(d -> d.get("payments") + ":" + new BigDecimal(String.valueOf(d.get("total"))).intValue()).containsExactly("2:2000");
        String id = String.valueOf(st.getBody().get("id"));
        assertThat((List<Map>) it.getList(audit, "/api/v1/finance/collections/statements").getBody()).anyMatch(x -> id.equals(x.get("id")));
        assertThat((List<Map>) it.getList(audit, "/api/v1/finance/refunds/bank-statements").getBody()).as("not a disbursement statement").noneMatch(x -> id.equals(x.get("id")));

        // the gateway's sum marked the settlement of its day: the day's payments no longer listed
        ResponseEntity<Map> settled = it.call(audit, HttpMethod.POST, "/api/v1/finance/collections/lines/" + lines.get(3).get("id") + "/settle", Map.of("channel", gateway, "day", today));
        assertThat(settled.getStatusCode().value()).as(String.valueOf(settled.getBody())).isEqualTo(200);
        assertThat(new BigDecimal(String.valueOf(((Map) settled.getBody().get("settled")).get("difference")))).isEqualByComparingTo("50");
        assertThat((List<Map>) settled.getBody().get("notReceived")).filteredOn(n -> String.valueOf(n.get("reference")).startsWith("MOAUM-FEE-" + tag))
                .extracting(n -> n.get("reference")).containsExactly(miss);
        ResponseEntity<Map> again = it.call(audit, HttpMethod.POST, "/api/v1/finance/collections/lines/" + lines.get(3).get("id") + "/settle", Map.of("channel", gateway, "day", today));
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody()).containsEntry("code", "SETTLEMENT_LINE");

        // the credit never confirmed: to the bank credits by the Bursary (not Internal Audit), once; another officer approves it
        String line3 = "/api/v1/finance/collections/lines/" + lines.get(2).get("id") + "/bank-credit";
        assertThat(it.call(audit, HttpMethod.POST, line3, Map.of()).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> sent = it.call(maker, HttpMethod.POST, line3, Map.of());
        assertThat(sent.getStatusCode().value()).as(String.valueOf(sent.getBody())).isEqualTo(200);
        assertThat((List<Map>) sent.getBody().get("lines")).filteredOn(l -> open.equals(l.get("matched_reference")))
                .extracting(l -> l.get("bank_credit_state") + ":" + l.get("confirmed_now")).containsExactly("PROPOSED:false");
        ResponseEntity<Map> twice = it.call(maker, HttpMethod.POST, line3, Map.of());
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody()).containsEntry("code", "STATEMENT_LINE_SENT");
        String credit = String.valueOf(sent.getBody().get("bankCredit"));
        assertThat(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit + "/approve", Map.of()).getStatusCode().value())
                .as("the officer who proposed it does not approve it").isEqualTo(422);
        ResponseEntity<Map> approved = it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit + "/approve", Map.of());
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat((List<Map>) it.get(audit, "/api/v1/finance/collections/statements/" + id).getBody().get("lines")).filteredOn(l -> open.equals(l.get("matched_reference")))
                .extracting(l -> l.get("bank_credit_state") + ":" + l.get("confirmed_now")).containsExactly("POSTED:true");
    }

    @Test
    void theWalletOpeningBalanceIsReadByAuditAndReclassifiedByTheBursaryNeverBeyondWhatRemains() {
        String audit = ItSupport.token("audit");
        String bursar = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        ResponseEntity<Map> read = it.get(audit, "/api/v1/finance/accounting/wallet-opening");
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        assertThat(read.getBody()).containsKeys("state", "breakdown", "journals", "accounts");
        assertThat((List<Map>) read.getBody().get("accounts")).extracting(a -> a.get("code")).contains("1010", "5240", "4090").doesNotContain("2100", "3900");
        BigDecimal remaining = new BigDecimal(String.valueOf(((Map) read.getBody().get("state")).get("remaining")));
        Map<String, Object> tooMuch = Map.of("lines", List.of(Map.of("account", "1010", "amount", remaining.add(BigDecimal.ONE))));
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/accounting/wallet-opening/reclassify", tooMuch).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> refused = it.call(bursar, HttpMethod.POST, "/api/v1/finance/accounting/wallet-opening/reclassify", tooMuch);
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);
        assertThat(String.valueOf(refused.getBody().get("code"))).isIn("WALLET_RECLASS_TOO_MUCH", "WALLET_OPENING_NOT_POSTED");
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/accounting/wallet-opening/reclassify", Map.of("lines", List.of(Map.of("account", "1010", "amount", 0))))
                .getStatusCode().value()).isEqualTo(400);
    }
}
