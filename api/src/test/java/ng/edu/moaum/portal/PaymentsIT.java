package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Random;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

import ng.edu.moaum.portal.payments.PaymentsService;

/**
 * The gateway's webhook confirms exactly one fee, once, for at least the
 * amount owed, and only when its signature verifies. Paystack's signature
 * is HMAC-SHA512 of the body with the secret key; Flutterwave's is the hash
 * set on its dashboard.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET, "moaum.payments.paystack-secret=sk_test_only_for_the_it",
                "moaum.payments.flutterwave-hash=flw-hash-only-for-the-it"})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class PaymentsIT {

    static final String SESSION = "2092/2093";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    String academic = ItSupport.token("academic");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    @Test
    @SuppressWarnings("unchecked")
    void aSignedWebhookConfirmsTheFeeOnceAndAnUnsignedOneIsRefused() {
        String jamb = "2026" + String.format("%08d", new Random().nextInt(100_000_000)) + "PY";
        it.call(academic, HttpMethod.POST, "/api/v1/admissions/caps-batches", Map.of(
                "session", SESSION, "source", "CAPS_DOWNLOAD", "filename", "CAPS-DE-pay.xlsx",
                "fileSha256", String.format("%064x", new Random().nextLong() & Long.MAX_VALUE), "listKind", "DIRECT_ENTRY", "downloadedOn", "2026-09-01",
                "rows", List.of(Map.of("jambRegNo", jamb, "surname", "ITPAYER", "otherNames", "Invented", "jambCode", "C00061",
                        "entryMode", "DIRECT_ENTRY", "sex", "M", "raw", Map.of()))));
        ResponseEntity<Map> registered = post("/api/v1/applicant/register", Map.of("session", SESSION, "jambKey", jamb,
                "email", jamb.toLowerCase() + "@example.com", "phone", "08034117725", "password", "a long enough password"));
        assertThat(registered.getStatusCode().value()).as(String.valueOf(registered.getBody())).isEqualTo(200);
        String token = String.valueOf(registered.getBody().get("token"));
        String reference = String.valueOf(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")).getBody().get("reference"));

        // no gateway wired for checkout beyond the secret? Paystack is: the checkout call reaches out, and is refused or answered by the world — not asserted here

        // an unsigned Paystack webhook is refused before anything is read
        String body = "{\"event\":\"charge.success\",\"data\":{\"reference\":\"" + reference + "\",\"amount\":230000,\"status\":\"success\",\"id\":12345}}";
        ResponseEntity<Map> unsigned = open.post().uri("/api/v1/payments/webhook/paystack").contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
        assertThat(unsigned.getStatusCode().value()).isEqualTo(401);
        assertThat(it.get(token, "/api/v1/applicant/me").getBody().get("feeConfirmedAt")).isNull();

        // short-paid is not confirmed
        String shortBody = "{\"event\":\"charge.success\",\"data\":{\"reference\":\"" + reference + "\",\"amount\":100,\"status\":\"success\",\"id\":12346}}";
        ResponseEntity<Map> shortPaid = open.post().uri("/api/v1/payments/webhook/paystack").contentType(MediaType.APPLICATION_JSON)
                .header("x-paystack-signature", PaymentsService.hmacSha512Hex("sk_test_only_for_the_it", shortBody)).body(shortBody).retrieve().toEntity(Map.class);
        assertThat(shortPaid.getStatusCode().value()).isEqualTo(200);
        assertThat(shortPaid.getBody().get("outcome")).isEqualTo("short paid");

        // signed and for the amount owed: confirmed, attributed to the Bursary's door with the gateway's reference
        ResponseEntity<Map> signed = open.post().uri("/api/v1/payments/webhook/paystack").contentType(MediaType.APPLICATION_JSON)
                .header("x-paystack-signature", PaymentsService.hmacSha512Hex("sk_test_only_for_the_it", body)).body(body).retrieve().toEntity(Map.class);
        assertThat(signed.getStatusCode().value()).as(String.valueOf(signed.getBody())).isEqualTo(200);
        assertThat(signed.getBody().get("outcome")).isEqualTo("confirmed");
        Map<String, Object> me = it.get(token, "/api/v1/applicant/me").getBody();
        assertThat(me.get("feeConfirmedAt")).isNotNull();
        assertThat(me.get("stage")).isEqualTo(1);
        Map<String, Object> ref = ((List<Map<String, Object>>) me.get("feeReferences")).get(0);
        assertThat(String.valueOf(ref.get("channel"))).isEqualTo("Card · Paystack");

        // the same webhook again is a no-op, not a second payment
        ResponseEntity<Map> again = open.post().uri("/api/v1/payments/webhook/paystack").contentType(MediaType.APPLICATION_JSON)
                .header("x-paystack-signature", PaymentsService.hmacSha512Hex("sk_test_only_for_the_it", body)).body(body).retrieve().toEntity(Map.class);
        assertThat(again.getBody().get("outcome")).isEqualTo("already confirmed");

        // Flutterwave: the dashboard hash, and a reference this portal did not generate
        String flw = "{\"event\":\"charge.completed\",\"data\":{\"tx_ref\":\"MOAUM-APP-000000-0000\",\"amount\":2300,\"status\":\"successful\",\"flw_ref\":\"FLW-1\"}}";
        assertThat(open.post().uri("/api/v1/payments/webhook/flutterwave").contentType(MediaType.APPLICATION_JSON).header("verif-hash", "wrong").body(flw)
                .retrieve().toEntity(Map.class).getStatusCode().value()).isEqualTo(401);
        ResponseEntity<Map> unknown = open.post().uri("/api/v1/payments/webhook/flutterwave").contentType(MediaType.APPLICATION_JSON)
                .header("verif-hash", "flw-hash-only-for-the-it").body(flw).retrieve().toEntity(Map.class);
        assertThat(unknown.getStatusCode().value()).isEqualTo(200);
        assertThat(unknown.getBody().get("outcome")).isEqualTo("unknown reference");

        // V037: every event was kept — the unsigned one as a bad signature, the short one, the settlement, the unknown reference
        String bursar = ItSupport.token("bursar");
        ResponseEntity<Map> desk = it.get(bursar, "/api/v1/payments/bursary");
        assertThat(desk.getStatusCode().value()).as(String.valueOf(desk.getBody())).isEqualTo(200);
        List<Map<String, Object>> events = (List<Map<String, Object>>) desk.getBody().get("events");
        assertThat(events.stream().map(e -> String.valueOf(e.get("outcome"))).toList()).contains("BAD_SIGNATURE", "SHORT_PAID", "SETTLED", "ALREADY_SETTLED", "UNKNOWN_REFERENCE");
        assertThat(events.stream().filter(e -> reference.equals(e.get("reference")) && "SETTLED".equals(e.get("outcome"))).count()).isEqualTo(1);
        // the verification path names the reference the same way; with no live gateway it says so rather than guessing
        ResponseEntity<Map> verified = it.call(bursar, HttpMethod.POST, "/api/v1/payments/verify", Map.of("reference", reference));
        assertThat(verified.getStatusCode().value()).isEqualTo(200);
        assertThat(verified.getBody().get("outcome")).isEqualTo("already confirmed");
    }

    /**
     * Quickteller on Interswitch WebPAY (V276): the configuration is set from the
     * dashboard as one JSON secret and never read back; the start page posts the
     * University's merchant (product 6498, pay item 101, naira 566) with a
     * SHA-512 hash; a payer in the College of Health Sciences is sent to the
     * College's merchant (6207); a second visit is a new attempt with its own
     * txn_ref; and WebPAY's return is not believed — the fee stays unpaid until
     * Interswitch's requery says otherwise. The keys used here are invented.
     */
    @Test
    @SuppressWarnings("unchecked")
    void quicktellerWebpayPostsTheMerchantOfThePayersCollegeAndBelievesNoReturn() {
        String ict = ItSupport.token("ict");
        String mac = "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
        String chsMac = "FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
        // an incomplete configuration is refused; the whole set is accepted
        ResponseEntity<Map> bad = it.call(ict, HttpMethod.PUT, "/api/v1/payments/gateways/quickteller/key", Map.of("secret", "{\"productId\":\"6498\"}"));
        assertThat(bad.getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> set = it.call(ict, HttpMethod.PUT, "/api/v1/payments/gateways/quickteller/key", Map.of("secret",
                "{\"productId\":\"6498\",\"payItemId\":\"101\",\"macKey\":\"" + mac + "\",\"sandbox\":true,\"chs\":{\"productId\":\"6207\",\"payItemId\":\"101\",\"macKey\":\"" + chsMac + "\"}}"));
        assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
        assertThat(set.getBody().get("mode")).isEqualTo("TEST");
        assertThat(set.getBody().get("last4")).isEqualTo("CDEF");
        Map<String, Object> listing = it.get(academic, "/api/v1/payments/gateways").getBody();
        assertThat(listing.get("quickteller")).isEqualTo(true);
        assertThat(listing).as("PayDirect is no longer offered").doesNotContainKey("paydirect");
        try {
            // a Direct Entry applicant into Computer Science (the University's merchant)
            String jamb = "2026" + String.format("%08d", new Random().nextInt(100_000_000)) + "QT";
            it.call(academic, HttpMethod.POST, "/api/v1/admissions/caps-batches", Map.of(
                    "session", SESSION, "source", "CAPS_DOWNLOAD", "filename", "CAPS-DE-qt.xlsx",
                    "fileSha256", String.format("%064x", new Random().nextLong() & Long.MAX_VALUE), "listKind", "DIRECT_ENTRY", "downloadedOn", "2026-09-01",
                    "rows", List.of(Map.of("jambRegNo", jamb, "surname", "ITWEBPAY", "otherNames", "Invented", "jambCode", "C00023",
                            "entryMode", "DIRECT_ENTRY", "sex", "F", "raw", Map.of()))));
            ResponseEntity<Map> registered = post("/api/v1/applicant/register", Map.of("session", SESSION, "jambKey", jamb,
                    "email", jamb.toLowerCase() + "@example.com", "phone", "08034117726", "password", "a long enough password"));
            assertThat(registered.getStatusCode().value()).as(String.valueOf(registered.getBody())).isEqualTo(200);
            String token = String.valueOf(registered.getBody().get("token"));
            String reference = String.valueOf(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")).getBody().get("reference"));
            BigDecimal amount = jdbc.sql("SELECT amount FROM admissions.fee_reference WHERE reference = :r").param("r", reference).query(BigDecimal.class).single();

            // the checkout hands the browser the portal's own start page
            Map<String, Object> checkout = it.call(token, HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", reference, "gateway", "quickteller")).getBody();
            assertThat(String.valueOf(checkout.get("url"))).contains("/api/v1/payments/quickteller/start?reference=" + reference);

            // the start page: the University's merchant, the amount in kobo, naira, the return door, the hash
            String page = open.get().uri("/api/v1/payments/quickteller/start?reference=" + reference).retrieve().body(String.class);
            assertThat(page).contains("action=\"https://sandbox.interswitchng.com/collections/w/pay\"")
                    .contains("name=\"product_id\" value=\"6498\"").contains("name=\"pay_item_id\" value=\"101\"")
                    .contains("name=\"currency\" value=\"566\"").contains("name=\"txn_ref\" value=\"" + reference + "\"")
                    .contains("name=\"amount\" value=\"" + amount.movePointRight(2).longValueExact() + "\"")
                    .contains("/api/v1/payments/quickteller/return?reference=" + reference);
            java.util.regex.Matcher h = java.util.regex.Pattern.compile("name=\"hash\" value=\"([0-9A-F]{128})\"").matcher(page);
            assertThat(h.find()).as("a 128-hex upper-case SHA-512 hash on the form").isTrue();
            java.util.regex.Matcher redirect = java.util.regex.Pattern.compile("name=\"site_redirect_url\" value=\"([^\"]+)\"").matcher(page);
            assertThat(redirect.find()).isTrue();
            String expected = PaymentsService.webpayHash(reference, "6498", "101", amount.movePointRight(2).longValueExact(), redirect.group(1).replace("&amp;", "&"), mac);
            assertThat(h.group(1)).isEqualTo(expected);
            assertThat(page).doesNotContain(mac).doesNotContain(chsMac);

            // a second visit is a new attempt: WebPAY refuses a txn_ref it has seen
            String again = open.get().uri("/api/v1/payments/quickteller/start?reference=" + reference).retrieve().body(String.class);
            assertThat(again).contains("name=\"txn_ref\" value=\"" + reference + "-A2\"");
            assertThat(jdbc.sql("SELECT count(*) FROM finance.gateway_attempt WHERE reference = :r AND txn_ref IS NOT NULL").param("r", reference).query(Long.class).single()).isEqualTo(2L);

            // WebPAY's return says "00" — it is not believed: the requery (sandbox, invented key) settles nothing
            String returned = open.post().uri("/api/v1/payments/quickteller/return?reference=" + reference)
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body("txnref=" + reference + "-A2&resp=00&desc=Approved&payRef=FBN|WEB|MX1|01-01-2026|000001&apprAmt=" + amount.movePointRight(2).longValueExact())
                    .retrieve().body(String.class);
            assertThat(returned).contains("/applicant/fee?paid=" + reference);
            assertThat(jdbc.sql("SELECT count(*) FROM admissions.fee_reference WHERE reference = :r AND confirmed_at IS NOT NULL").param("r", reference).query(Long.class).single()).isEqualTo(0L);
            assertThat(jdbc.sql("SELECT count(*) FROM finance.gateway_event WHERE gateway = 'quickteller' AND source = 'RETURN' AND event = 'return' AND reference = :r").param("r", reference).query(Long.class).single()).isEqualTo(1L);

            // a payer in the College of Health Sciences is sent to the College's merchant
            String chsJamb = "2026" + String.format("%08d", new Random().nextInt(100_000_000)) + "QC";
            it.call(academic, HttpMethod.POST, "/api/v1/admissions/caps-batches", Map.of(
                    "session", SESSION, "source", "CAPS_DOWNLOAD", "filename", "CAPS-DE-qtc.xlsx",
                    "fileSha256", String.format("%064x", new Random().nextLong() & Long.MAX_VALUE), "listKind", "DIRECT_ENTRY", "downloadedOn", "2026-09-01",
                    "rows", List.of(Map.of("jambRegNo", chsJamb, "surname", "ITWEBPAYCHS", "otherNames", "Invented", "jambCode", "C00061",
                            "entryMode", "DIRECT_ENTRY", "sex", "M", "raw", Map.of()))));
            ResponseEntity<Map> chsRegistered = post("/api/v1/applicant/register", Map.of("session", SESSION, "jambKey", chsJamb,
                    "email", chsJamb.toLowerCase() + "@example.com", "phone", "08034117727", "password", "a long enough password"));
            assertThat(chsRegistered.getStatusCode().value()).as(String.valueOf(chsRegistered.getBody())).isEqualTo(200);
            String chsToken = String.valueOf(chsRegistered.getBody().get("token"));
            String chsReference = String.valueOf(it.call(chsToken, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")).getBody().get("reference"));
            String college = jdbc.sql("SELECT f.college_code FROM admissions.fee_reference fr JOIN admissions.application a ON a.id = fr.application_id JOIN admissions.candidate c ON c.id = a.candidate_id JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme) JOIN ref.faculty f ON f.code = p.faculty_code WHERE fr.reference = :r")
                    .param("r", chsReference).query(String.class).optional().orElse("?");
            assertThat(college).as("the CHS applicant's programme resolves to the College").isEqualTo("CHS");
            String chsPage = open.get().uri("/api/v1/payments/quickteller/start?reference=" + chsReference).retrieve().body(String.class);
            assertThat(chsPage).contains("name=\"product_id\" value=\"6207\"").contains("College of Health Sciences");

            // the current WebPAY knows a merchant by its merchant code: accepted without a MAC key, posted as merchant_code, unsigned
            ResponseEntity<Map> byCode = it.call(ict, HttpMethod.PUT, "/api/v1/payments/gateways/quickteller/key", Map.of("secret", "{\"merchantCode\":\"MX000001\",\"payItemId\":\"101\",\"sandbox\":true}"));
            assertThat(byCode.getStatusCode().value()).as(String.valueOf(byCode.getBody())).isEqualTo(200);
            assertThat(byCode.getBody().get("last4")).isEqualTo("0001");
            String codePage = open.get().uri("/api/v1/payments/quickteller/start?reference=" + reference).retrieve().body(String.class);
            assertThat(codePage).contains("name=\"merchant_code\" value=\"MX000001\"").contains("name=\"txn_ref\" value=\"" + reference + "-A3\"")
                    .doesNotContain("name=\"product_id\"").doesNotContain("name=\"hash\"");
        } finally {
            it.call(ict, HttpMethod.POST, "/api/v1/payments/gateways/quickteller/clear-key", Map.of());
        }
    }
}
