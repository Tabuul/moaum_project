package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * V533: a refund is paid only into a full account on record, its number checked against the bank. The desk raises a refund with
 * the full account (one digit off refused), or without one — then it is approved but not paid; the account the desk records on
 * the approved refund sends it back for approval, which the officer who recorded it may not give; another officer approves and it
 * is paid — V534: with the bank transfer reference and the date the money left, never a date to come. A name on the account that
 * shares no word with the payer's is flagged. The Bursary keeps the list of banks (Internal Audit reads it). Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class RefundAccountsIT {

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

    /** a refund on the desk's list, read in its state (the list shows the newest 300) */
    private Map<String, Object> row(String token, String reference, String state) {
        ResponseEntity<List> list = it.getList(token, "/api/v1/finance/refunds?state=" + state);
        assertThat(list.getStatusCode().value()).isEqualTo(200);
        return ((List<Map<String, Object>>) list.getBody()).stream().filter(r -> reference.equals(r.get("reference"))).findFirst().orElseThrow();
    }

    @Test
    void aRefundIsPaidOnlyIntoAFullCheckedAccountAndAnAccountRecordedAfterApprovalIsApprovedAgain() {
        String tag = String.format("%05d", new Random().nextInt(100_000));
        String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String checker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String third = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String audit = ItSupport.token("audit");
        String payer = "ZZREFUNDACCT" + tag + ", Invented";

        // raised with the full account: one digit off is refused, the right number recorded with its bank
        ResponseEntity<Map> slip = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds",
                Map.of("payer", payer, "reason", "V533 IT: with the account", "amount", 1500, "bank", "GTB", "accountName", "ZZREFUNDACCT" + tag + " Invented", "accountNumber", "2222222222"));
        assertThat(slip.getStatusCode().value()).isEqualTo(422);
        assertThat(slip.getBody()).containsEntry("code", "REFUND_ACCOUNT_CHECK_DIGIT");
        ResponseEntity<Map> withAccount = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds",
                Map.of("payer", payer, "reason", "V533 IT: with the account", "amount", 1500, "bank", "GTB", "accountName", "Someone Else", "accountNumber", "2222222223"));
        assertThat(withAccount.getStatusCode().value()).as(String.valueOf(withAccount.getBody())).isEqualTo(200);
        Map<String, Object> first = row(audit, String.valueOf(withAccount.getBody().get("reference")), "PROPOSED");
        assertThat(first.get("bank_name") + ":" + first.get("account_number") + ":" + first.get("account_source") + ":" + first.get("bank_code") + ":" + first.get("account_name_matches"))
                .as("the name differs from the payer's: flagged").isEqualTo("Guaranty Trust Bank:2222222223:DESK:058:false");

        // raised with no account: approved, never paid until one is recorded
        ResponseEntity<Map> bare = it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("payer", payer, "reason", "V533 IT: no account yet", "amount", 2500));
        assertThat(bare.getStatusCode().value()).as(String.valueOf(bare.getBody())).isEqualTo(200);
        String ref = String.valueOf(bare.getBody().get("reference"));
        UUID id = UUID.fromString(String.valueOf(row(audit, ref, "PROPOSED").get("id")));
        String base = "/api/v1/finance/refunds/" + id;
        assertThat(it.call(checker, HttpMethod.POST, base + "/approve", Map.of()).getStatusCode().value()).isEqualTo(200);
        String today = java.time.LocalDate.now(java.time.ZoneId.of("Africa/Lagos")).toString();
        Map<String, Object> evidence = Map.of("reference", "FT-IT-" + tag, "paidOn", today);
        ResponseEntity<Map> unpaid = it.call(checker, HttpMethod.POST, base + "/pay", evidence);
        assertThat(unpaid.getStatusCode().value()).isEqualTo(422);
        assertThat(unpaid.getBody()).containsEntry("code", "REFUND_NO_ACCOUNT");

        // the account recorded by an officer on the approved refund: back for approval, not by that officer
        assertThat(it.call(audit, HttpMethod.POST, base + "/account", Map.of("bank", "011", "accountName", "ZZREFUNDACCT" + tag + " Invented", "accountNumber", "0000014579"))
                .getStatusCode().value()).as("the Bursary's desk").isEqualTo(403);
        ResponseEntity<Map> recorded = it.call(checker, HttpMethod.POST, base + "/account",
                Map.of("bank", "011", "accountName", "ZZREFUNDACCT" + tag + " Invented", "accountNumber", "0000 0145 79"));
        assertThat(recorded.getStatusCode().value()).as(String.valueOf(recorded.getBody())).isEqualTo(200);
        assertThat(recorded.getBody()).containsEntry("state", "PROPOSED");
        ResponseEntity<Map> same = it.call(checker, HttpMethod.POST, base + "/approve", Map.of());
        assertThat(same.getStatusCode().value()).isEqualTo(422);
        assertThat(same.getBody()).containsEntry("code", "REFUND_ACCOUNT_SAME_OFFICER");
        assertThat(it.call(third, HttpMethod.POST, base + "/approve", Map.of()).getStatusCode().value()).isEqualTo(200);
        // V534: paid only with the transfer reference and the date the money left, not a date to come
        assertThat(it.call(third, HttpMethod.POST, base + "/pay", Map.of("paidOn", today)).getStatusCode().value()).isEqualTo(400);
        ResponseEntity<Map> later = it.call(third, HttpMethod.POST, base + "/pay",
                Map.of("reference", "FT-IT-" + tag, "paidOn", java.time.LocalDate.parse(today).plusDays(3).toString()));
        assertThat(later.getBody()).containsEntry("code", "REFUND_PAID_DATE");
        ResponseEntity<Map> paid = it.call(third, HttpMethod.POST, base + "/pay", evidence);
        assertThat(paid.getStatusCode().value()).as(String.valueOf(paid.getBody())).isEqualTo(200);
        Map<String, Object> done = row(audit, ref, "PAID");
        assertThat(done.get("state") + ":" + done.get("bank_name") + ":" + done.get("account_number") + ":" + done.get("account_name_matches"))
                .isEqualTo("PAID:First Bank of Nigeria:0000014579:true");
        assertThat(done.get("paid_reference") + ":" + done.get("paid_on") + ":" + done.get("paid_reference_others")).isEqualTo("FT-IT-" + tag + ":" + today + ":0");

        // the banks: read by Internal Audit, kept by the Bursary
        ResponseEntity<List> banks = it.getList(audit, "/api/v1/finance/refunds/banks");
        assertThat((List<Map>) banks.getBody()).filteredOn(b -> "999992".equals(b.get("code")))
                .extracting(b -> b.get("name") + ":" + b.get("nuban_check") + ":" + b.get("kind")).containsExactly("OPay:false:PAYMENT_SERVICE");
        assertThat(it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds/banks", Map.of("code", "565", "name", "Carbon", "nubanCheck", true)).getStatusCode().value())
                .as("a microfinance bank's numbers are never checked by the banks' check digit").isEqualTo(422);
        String code = "ZZ" + tag;
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/refunds/banks", Map.of("code", code, "name", "ZZ Bank " + tag)).getStatusCode().value()).isEqualTo(403);
        try {
            ResponseEntity<List> added = it.callList(maker, HttpMethod.POST, "/api/v1/finance/refunds/banks",
                    Map.of("code", code, "name", "ZZ Bank " + tag, "kind", "MICROFINANCE", "aliases", List.of("ZZ Alias " + tag)));
            assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
            assertThat((List<Map>) added.getBody()).filteredOn(b -> code.equals(b.get("code")))
                    .extracting(b -> b.get("name") + ":" + b.get("aliases") + ":" + b.get("nuban_check") + ":" + b.get("active"))
                    .containsExactly("ZZ Bank " + tag + ":zz alias " + tag + ":false:true");
            ResponseEntity<List> aside = it.callList(maker, HttpMethod.POST, "/api/v1/finance/refunds/banks", Map.of("code", code, "name", "ZZ Bank " + tag, "active", false));
            assertThat((List<Map>) aside.getBody()).filteredOn(b -> code.equals(b.get("code"))).extracting(b -> b.get("active") + ":" + b.get("aliases"))
                    .as("set aside, its other names kept").containsExactly("false:zz alias " + tag);
            assertThat((List<Map>) it.getList(TestTokens.token(UUID.randomUUID(), List.of("student")), "/api/v1/me/banks").getBody())
                    .as("a bank set aside is not offered to students").noneMatch(b -> code.equals(b.get("code")));
        } finally {
            it.db(() -> jdbc.sql("DELETE FROM finance.bank WHERE code = :c").param("c", code).update());
        }
    }
}
