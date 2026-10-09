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
        assertThat(listing.get("paydirect")).as("Pay on Quickteller (V299) is off until the Bursary switches a biller on").isEqualTo(false);
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

    /** an applicant registered on the CAPS list into a programme, with an application-fee reference */
    String[] applicantWithReference(String programme, String surname, String tag) {
        String jamb = "2026" + String.format("%08d", new Random().nextInt(100_000_000)) + tag;
        it.call(academic, HttpMethod.POST, "/api/v1/admissions/caps-batches", Map.of(
                "session", SESSION, "source", "CAPS_DOWNLOAD", "filename", "CAPS-DE-" + tag + ".xlsx",
                "fileSha256", String.format("%064x", new Random().nextLong() & Long.MAX_VALUE), "listKind", "DIRECT_ENTRY", "downloadedOn", "2026-09-01",
                "rows", List.of(Map.of("jambRegNo", jamb, "surname", surname, "otherNames", "Invented Payer", "jambCode", programme,
                        "entryMode", "DIRECT_ENTRY", "sex", "F", "raw", Map.of()))));
        @SuppressWarnings("rawtypes")
        ResponseEntity<Map> registered = post("/api/v1/applicant/register", Map.of("session", SESSION, "jambKey", jamb,
                "email", jamb.toLowerCase() + "@example.com", "phone", "0803411" + String.format("%04d", new Random().nextInt(10_000)), "password", "a long enough password"));
        assertThat(registered.getStatusCode().value()).as(String.valueOf(registered.getBody())).isEqualTo(200);
        String token = String.valueOf(registered.getBody().get("token"));
        String reference = String.valueOf(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")).getBody().get("reference"));
        return new String[] { token, reference };
    }

    static String notification(String user, String pass, String reference, String logId, String amount, boolean repeated, boolean reversal) {
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?><PaymentNotificationRequest xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">"
                + "<ServiceUrl>https://example.invalid/notify</ServiceUrl><ServiceUsername>" + user + "</ServiceUsername><ServicePassword>" + pass + "</ServicePassword>"
                + "<Payments><Payment><IsRepeated>" + (repeated ? "True" : "False") + "</IsRepeated><ProductGroupCode>HTTPGENERICv31</ProductGroupCode>"
                + "<PaymentLogId>" + logId + "</PaymentLogId><CustReference>" + reference + "</CustReference><AlternateCustReference>--N/A--</AlternateCustReference>"
                + "<Amount>" + amount + "</Amount><PaymentStatus>0</PaymentStatus><PaymentMethod>Debit Card</PaymentMethod><PaymentReference>QT|WEB|" + logId + "</PaymentReference>"
                + "<TerminalId></TerminalId><ChannelName>WEB</ChannelName><Location></Location><IsReversal>" + (reversal ? "True" : "False") + "</IsReversal>"
                + "<PaymentDate>09/30/2026 15:00:00</PaymentDate><SettlementDate>10/01/2026 00:00:01</SettlementDate><CustomerName>Invented Payer</CustomerName>"
                + "<ReceiptNo>" + logId + "</ReceiptNo><PaymentItems><PaymentItem><ItemName>Application fee</ItemName><ItemCode>01</ItemCode><ItemAmount>" + amount
                + "</ItemAmount><ItemQuantity>1</ItemQuantity></PaymentItem></PaymentItems><PaymentCurrency>566</PaymentCurrency></Payment></Payments></PaymentNotificationRequest>";
    }

    String postXml(String path, String xml) {
        return open.post().uri(path).contentType(MediaType.TEXT_XML).body(xml).retrieve().body(String.class);
    }

    /**
     * Pay on Quickteller (V299), as Interswitch described it: the payer is sent to
     * https://quickteller.com/bsum?cid=<reference>&amount=<amount>, the reference
     * being the portal's own, unchanged. The redirect is off until the Bursary
     * switches the biller on, and a link to anywhere but Interswitch is refused.
     * Quickteller's question about a reference is answered from the reference; a
     * payment notification is believed only with the credentials agreed for it,
     * settles the fee once and only for the amount owed, and a reversal is kept for
     * the Bursary. A payer in the College of Health Sciences is not sent to the
     * University's biller while the College's own is in use.
     */
    @Test
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void payOnQuicktellerCarriesThePortalReferenceAndBelievesOnlyAnAuthenticNotification() {
        String bursar = ItSupport.token("bursar");
        String ict = ItSupport.token("ict");
        Map<String, Object> desk = it.get(bursar, "/api/v1/payments/paydirect").getBody();
        List<Map<String, Object>> billers = (List<Map<String, Object>>) desk.get("billers");
        Map<String, Object> main = billers.stream().filter(b -> "MAIN".equals(b.get("scope"))).findFirst().orElseThrow();
        Map<String, Object> chs = billers.stream().filter(b -> "CHS".equals(b.get("scope"))).findFirst().orElseThrow();
        assertThat(main.get("redirect")).as("off until the Bursary switches it on").isEqualTo(false);
        assertThat(main.get("pay_link")).isEqualTo("https://quickteller.com/bsum");
        assertThat(it.get(academic, "/api/v1/payments/gateways").getBody().get("paydirect")).isEqualTo(false);
        try {
            String[] app = applicantWithReference("C00023", "ITQUICKTELLER", "QR");
            String token = app[0];
            String reference = app[1];
            BigDecimal amount = jdbc.sql("SELECT amount FROM admissions.fee_reference WHERE reference = :r").param("r", reference).query(BigDecimal.class).single();
            String amountInLink = amount.stripTrailingZeros().scale() <= 0 ? amount.toBigInteger().toString() : amount.setScale(2).toPlainString();

            // off: the payer is not sent anywhere
            ResponseEntity<Map> off = it.call(token, HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", reference, "gateway", "paydirect"));
            assertThat(off.getStatusCode().value()).isEqualTo(422);

            // a link to anywhere but Interswitch is refused; the University's Quickteller page is accepted and switched on
            ResponseEntity<Map> elsewhere = it.call(bursar, HttpMethod.PUT, "/api/v1/payments/paydirect/billers/MAIN", Map.of("code", "04255101",
                    "name", "Benue State University, Makurdi", "link", "https://pay.example.com/bsum", "active", true, "redirect", true, "withAmount", true));
            assertThat(elsewhere.getStatusCode().value()).isEqualTo(422);
            assertThat(String.valueOf(elsewhere.getBody())).contains("QUICKTELLER_LINK");
            ResponseEntity<Map> on = it.call(bursar, HttpMethod.PUT, "/api/v1/payments/paydirect/billers/MAIN", Map.of("code", "04255101",
                    "name", "Benue State University, Makurdi", "link", "https://quickteller.com/bsum", "active", true, "redirect", true, "withAmount", true));
            assertThat(on.getStatusCode().value()).as(String.valueOf(on.getBody())).isEqualTo(200);
            assertThat(it.get(token, "/api/v1/payments/gateways?reference=" + reference).getBody().get("paydirect")).isEqualTo(true);

            // the link: the portal's own reference in cid, and the amount
            Map<String, Object> checkout = it.call(token, HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", reference, "gateway", "paydirect")).getBody();
            assertThat(checkout.get("url")).isEqualTo("https://quickteller.com/bsum?cid=" + reference + "&amount=" + amountInLink);
            assertThat(checkout.get("gateway")).isEqualTo("paydirect");
            assertThat(jdbc.sql("SELECT count(*) FROM finance.gateway_attempt WHERE reference = :r AND gateway = 'paydirect'").param("r", reference).query(Long.class).single())
                    .as("the Bursary sees who went to pay").isEqualTo(1L);

            // the one address Interswitch asks for takes both messages; opened in a browser it says it is reachable
            assertThat(open.get().uri("/api/v1/payments/paydirect/interswitch").retrieve().body(String.class)).contains("This address is reachable");
            // Quickteller's question about the reference, at the one address: the payer's name and the amount; an unknown reference is refused
            String asked = postXml("/api/v1/payments/paydirect/interswitch", "<CustomerInformationRequest><ServiceUsername></ServiceUsername><ServicePassword></ServicePassword>"
                    + "<MerchantReference>6405</MerchantReference><CustReference>" + reference.toLowerCase() + "</CustReference><PaymentItemCode>01</PaymentItemCode>"
                    + "<ThirdPartyCode></ThirdPartyCode></CustomerInformationRequest>");
            assertThat(asked).contains("<Status>0</Status>").contains("<CustReference>" + reference + "</CustReference>")
                    .containsIgnoringCase("<LastName>ITQUICKTELLER</LastName>").containsIgnoringCase("<FirstName>Invented</FirstName>")
                    .contains("<Amount>" + amount.setScale(2).toPlainString() + "</Amount>");
            assertThat(postXml("/api/v1/payments/paydirect/validate", "<CustomerInformationRequest><CustReference>MOAUM-APP-000000-0000</CustReference></CustomerInformationRequest>"))
                    .contains("<Status>1</Status>").contains("<FirstName></FirstName>");

            // a notification without the credentials agreed for it is kept and not believed
            String logId = String.valueOf(1_000_000 + new Random().nextInt(8_000_000));
            assertThat(postXml("/api/v1/payments/paydirect/notify", notification("", "", reference, logId, amount.toPlainString(), false, false)))
                    .contains("<PaymentLogId>" + logId + "</PaymentLogId><Status>1</Status>");
            assertThat(jdbc.sql("SELECT confirmed_at IS NULL FROM admissions.fee_reference WHERE reference = :r").param("r", reference).query(Boolean.class).single()).isTrue();
            assertThat(it.get(token, "/api/v1/payments/state?reference=" + reference).getBody().get("confirmed")).as("the payer's check reads the record").isEqualTo(false);

            // the credentials, set once by the Directorate of ICT
            ResponseEntity<Map> creds = it.call(ict, HttpMethod.PUT, "/api/v1/payments/gateways/paydirect/key",
                    Map.of("secret", "{\"serviceUsername\":\"moaum-it-notify\",\"servicePassword\":\"an-invented-password\"}"));
            assertThat(creds.getStatusCode().value()).as(String.valueOf(creds.getBody())).isEqualTo(200);
            assertThat(creds.getBody().get("last4")).isEqualTo("tify");
            assertThat(postXml("/api/v1/payments/paydirect/notify", notification("moaum-it-notify", "a-wrong-password", reference, logId, amount.toPlainString(), false, false)))
                    .contains("<Status>1</Status>");

            // short of the amount: received, kept open for the Bursary
            String shortId = String.valueOf(Long.parseLong(logId) + 1);
            assertThat(postXml("/api/v1/payments/paydirect/notify", notification("moaum-it-notify", "an-invented-password", reference, shortId, "100.00", false, false)))
                    .contains("<PaymentLogId>" + shortId + "</PaymentLogId><Status>0</Status>");
            assertThat(jdbc.sql("SELECT confirmed_at IS NULL FROM admissions.fee_reference WHERE reference = :r").param("r", reference).query(Boolean.class).single()).isTrue();

            // the amount owed, authentic, reported at the one address: confirmed once, on Quickteller's channel
            assertThat(postXml("/api/v1/payments/paydirect/interswitch", notification("moaum-it-notify", "an-invented-password", reference, logId, amount.toPlainString(), true, false)))
                    .contains("<PaymentLogId>" + logId + "</PaymentLogId><Status>0</Status>");
            assertThat(it.get(token, "/api/v1/applicant/me").getBody().get("feeConfirmedAt")).isNotNull();
            assertThat(it.get(token, "/api/v1/payments/state?reference=" + reference).getBody().get("confirmed")).isEqualTo(true);
            assertThat(jdbc.sql("SELECT channel FROM admissions.fee_reference WHERE reference = :r").param("r", reference).query(String.class).single()).isEqualTo("Quickteller · WEB");
            // the same payment again is received, not paid twice
            assertThat(postXml("/api/v1/payments/paydirect/notify", notification("moaum-it-notify", "an-invented-password", reference, logId, amount.toPlainString(), true, false)))
                    .contains("<Status>0</Status>");
            List<String> outcomes = jdbc.sql("SELECT outcome FROM finance.gateway_event WHERE gateway = 'paydirect' AND reference = :r AND source = 'WEBHOOK' ORDER BY received_at")
                    .param("r", reference).query(String.class).list();
            assertThat(outcomes).containsExactly("BAD_SIGNATURE", "BAD_SIGNATURE", "SHORT_PAID", "SETTLED", "ALREADY_SETTLED");

            // a paid reference is refused when Quickteller asks again, so it is not paid twice — at either address
            assertThat(postXml("/api/v1/payments/paydirect/validate", "<CustomerInformationRequest><CustReference>" + reference + "</CustReference></CustomerInformationRequest>"))
                    .contains("<Status>1</Status>");
            assertThat(postXml("/api/v1/payments/paydirect/interswitch", "<CustomerInformationRequest><CustReference>" + reference + "</CustReference></CustomerInformationRequest>"))
                    .contains("<CustomerInformationResponse>").contains("<Status>1</Status>");
            // a message that is neither is answered as a reference not found, and nothing moves
            assertThat(postXml("/api/v1/payments/paydirect/interswitch", "<Hello><World/></Hello>")).contains("<CustomerInformationResponse>").contains("<Status>1</Status>");
            // a reversal is kept for the Bursary; the confirmation stands until the Bursary acts
            String reversalId = String.valueOf(Long.parseLong(logId) + 2);
            assertThat(postXml("/api/v1/payments/paydirect/notify", notification("moaum-it-notify", "an-invented-password", reference, reversalId, "-" + amount.toPlainString(), false, true)))
                    .contains("<Status>0</Status>");
            assertThat(jdbc.sql("SELECT outcome FROM finance.gateway_event WHERE gateway = 'paydirect' AND gateway_ref = :g").param("g", reversalId).query(String.class).single())
                    .isEqualTo("REVERSED");
            assertThat(jdbc.sql("SELECT confirmed_at IS NOT NULL FROM admissions.fee_reference WHERE reference = :r").param("r", reference).query(Boolean.class).single()).isTrue();
            // no secret is kept on the log
            assertThat(jdbc.sql("SELECT count(*) FROM finance.gateway_event WHERE gateway = 'paydirect' AND payload::text LIKE '%an-invented-password%'").query(Long.class).single())
                    .isEqualTo(0L);

            // the Bursary's desk: the reference checks listed apart from the money, the settlement among the events
            Map<String, Object> after = it.get(bursar, "/api/v1/payments/paydirect").getBody();
            assertThat(after.get("credentials")).isEqualTo(true);
            assertThat(((List<Map<String, Object>>) after.get("validations")).stream().map(v -> String.valueOf(v.get("reference")))).contains(reference);
            List<Map<String, Object>> events = (List<Map<String, Object>>) it.get(bursar, "/api/v1/payments/bursary").getBody().get("events");
            assertThat(events.stream().filter(e -> reference.equals(e.get("reference"))).map(e -> String.valueOf(e.get("source")))).doesNotContain("VALIDATE");

            // a payer in the College of Health Sciences: the College's biller is in use but not switched on — not sent to the University's
            String[] chsApp = applicantWithReference("C00061", "ITQUICKTELLERCHS", "QH");
            assertThat(it.get(chsApp[0], "/api/v1/payments/state?reference=" + reference).getStatusCode().value()).as("another payer's reference is not theirs to read").isEqualTo(404);
            assertThat(it.get(chsApp[0], "/api/v1/payments/gateways?reference=" + chsApp[1]).getBody().get("paydirect")).isEqualTo(false);
            assertThat(it.call(chsApp[0], HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", chsApp[1], "gateway", "paydirect")).getStatusCode().value())
                    .isEqualTo(422);
            // without the amount in the link when the biller says so
            it.call(bursar, HttpMethod.PUT, "/api/v1/payments/paydirect/billers/CHS", Map.of("code", String.valueOf(chs.get("biller_code")),
                    "name", String.valueOf(chs.get("name")), "link", "https://quickteller.com/chsbsu", "active", true, "redirect", true, "withAmount", false));
            Map<String, Object> chsCheckout = it.call(chsApp[0], HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", chsApp[1], "gateway", "paydirect")).getBody();
            assertThat(chsCheckout.get("url")).isEqualTo("https://quickteller.com/chsbsu?cid=" + chsApp[1]);
        } finally {
            // the billers as they were, switched off again, and the credentials cleared
            for (Map<String, Object> b : List.of(main, chs)) {
                ResponseEntity<Map> back = it.call(bursar, HttpMethod.PUT, "/api/v1/payments/paydirect/billers/" + b.get("scope"), Map.of(
                        "code", String.valueOf(b.get("biller_code")), "name", String.valueOf(b.get("name")),
                        "link", b.get("pay_link") == null ? "" : String.valueOf(b.get("pay_link")),
                        "active", Boolean.TRUE.equals(b.get("active")), "redirect", false, "withAmount", true));
                assertThat(back.getStatusCode().value()).as("biller " + b.get("scope") + " restored: " + back.getBody()).isEqualTo(200);
            }
            it.call(ict, HttpMethod.POST, "/api/v1/payments/gateways/paydirect/clear-key", Map.of());
        }
    }

    /**
     * V383: an Interswitch test reference — a small reference against a named student, issued by the Bursary and payable for
     * the days the Bursar chooses, so Interswitch's testers can check one reference over several days. Quickteller is answered
     * Status 0 with the student's name and the amount while it is unpaid and unexpired, and Status 1 once its days have run out,
     * once it is withdrawn, and once it is paid. Only the Bursary's desk issues one.
     */
    @Test
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void anInterswitchTestReferenceIsAnsweredZeroUntilItIsPaidOrExpires() {
        String bursar = ItSupport.token("bursar");
        String ict = ItSupport.token("ict");
        it.student("ZZINTERSWITCH", "C00023", "MOAUM/ADM/99/990383", "MOAUM/ITR/99/0383", 100);
        String validate = "<CustomerInformationRequest><ServiceUsername></ServiceUsername><ServicePassword></ServicePassword><MerchantReference>6405</MerchantReference>"
                + "<CustReference>%s</CustReference><PaymentItemCode>01</PaymentItemCode><ThirdPartyCode></ThirdPartyCode></CustomerInformationRequest>";

        // only the Bursary's desk issues one; the days are 1 to 14
        ResponseEntity<Map> refused = it.call(academic, HttpMethod.POST, "/api/v1/payments/paydirect/test-references", Map.of("number", "MOAUM/ITR/99/0383", "amount", 150));
        assertThat(refused.getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> tooLong = it.call(bursar, HttpMethod.POST, "/api/v1/payments/paydirect/test-references", Map.of("number", "MOAUM/ITR/99/0383", "amount", 150, "days", 15));
        assertThat(tooLong.getStatusCode().value()).isEqualTo(422);
        assertThat(tooLong.getBody().get("code")).isEqualTo("GATEWAY_TEST_DAYS");

        // issued for five days, by the matriculation number in any case
        ResponseEntity<Map> issued = it.call(bursar, HttpMethod.POST, "/api/v1/payments/paydirect/test-references", Map.of("number", "moaum/itr/99/0383", "amount", 150, "days", 5));
        assertThat(issued.getStatusCode().value()).as(String.valueOf(issued.getBody())).isEqualTo(200);
        String reference = String.valueOf(issued.getBody().get("reference"));
        assertThat(issued.getBody().get("state")).isEqualTo("OPEN");
        assertThat(((Number) issued.getBody().get("days")).intValue()).isEqualTo(5);
        assertThat(jdbc.sql("SELECT extract(epoch FROM expires_at - generated_at)::int FROM finance.payment_reference WHERE reference = :r").param("r", reference)
                .query(Integer.class).single()).as("payable for the five days chosen, not 24 hours").isEqualTo(5 * 24 * 3600);
        assertThat(jdbc.sql("SELECT purpose FROM finance.payment_reference WHERE reference = :r").param("r", reference).query(String.class).single())
                .isEqualTo("Gateway test by the Bursary");

        // open: Status 0 with the student's name and the amount
        assertThat(postXml("/api/v1/payments/paydirect/interswitch", validate.formatted(reference.toLowerCase())))
                .contains("<Status>0</Status>").contains("<CustReference>" + reference + "</CustReference>")
                .containsIgnoringCase("<LastName>ZZINTERSWITCH</LastName>").containsIgnoringCase("<FirstName>Invented</FirstName>").contains("<Amount>150.00</Amount>");
        Map<String, Object> listed = ((List<Map<String, Object>>) it.get(bursar, "/api/v1/payments/paydirect").getBody().get("testReferences")).stream()
                .filter(r -> reference.equals(r.get("reference"))).findFirst().orElseThrow();
        assertThat(listed.get("state")).isEqualTo("OPEN");
        assertThat(((Number) listed.get("checks")).intValue()).as("Quickteller's check is counted against it").isEqualTo(1);

        // its days run out: Status 1
        it.db(() -> jdbc.sql("UPDATE finance.payment_reference SET expires_at = now() - interval '1 minute' WHERE reference = :r").param("r", reference).update());
        assertThat(postXml("/api/v1/payments/paydirect/validate", validate.formatted(reference))).contains("<Status>1</Status>");
        assertThat(jdbc.sql("SELECT payload->>'why' FROM finance.gateway_event WHERE gateway = 'paydirect' AND source = 'VALIDATE' AND reference = :r ORDER BY received_at DESC LIMIT 1")
                .param("r", reference).query(String.class).single()).startsWith("Expired");

        // withdrawn by the Bursary: it expires now, Status 1 from then on
        String withdrawn = String.valueOf(it.call(bursar, HttpMethod.POST, "/api/v1/payments/paydirect/test-references", Map.of("number", "MOAUM/ADM/99/990383", "amount", 100, "days", 1))
                .getBody().get("reference"));
        assertThat(postXml("/api/v1/payments/paydirect/interswitch", validate.formatted(withdrawn))).contains("<Status>0</Status>");
        ResponseEntity<Map> wd = it.call(bursar, HttpMethod.POST, "/api/v1/payments/paydirect/test-references/" + withdrawn + "/withdraw", Map.of());
        assertThat(wd.getStatusCode().value()).as(String.valueOf(wd.getBody())).isEqualTo(200);
        assertThat(wd.getBody().get("state")).isEqualTo("WITHDRAWN");
        assertThat(postXml("/api/v1/payments/paydirect/interswitch", validate.formatted(withdrawn))).contains("<Status>1</Status>");

        // paid through Quickteller's notification: settled once, then Status 1, and a paid one is not withdrawn
        String paid = String.valueOf(it.call(bursar, HttpMethod.POST, "/api/v1/payments/paydirect/test-references", Map.of("number", "MOAUM/ITR/99/0383", "amount", 100))
                .getBody().get("reference"));
        assertThat(jdbc.sql("SELECT extract(epoch FROM expires_at - generated_at)::int FROM finance.payment_reference WHERE reference = :r").param("r", paid)
                .query(Integer.class).single()).as("seven days unless said").isEqualTo(7 * 24 * 3600);
        assertThat(postXml("/api/v1/payments/paydirect/interswitch", validate.formatted(paid))).contains("<Status>0</Status>").contains("<Amount>100.00</Amount>");
        try {
            ResponseEntity<Map> creds = it.call(ict, HttpMethod.PUT, "/api/v1/payments/gateways/paydirect/key",
                    Map.of("secret", "{\"serviceUsername\":\"moaum-it-notify\",\"servicePassword\":\"an-invented-password\"}"));
            assertThat(creds.getStatusCode().value()).as(String.valueOf(creds.getBody())).isEqualTo(200);
            String logId = String.valueOf(1_000_000 + new Random().nextInt(8_000_000));
            assertThat(postXml("/api/v1/payments/paydirect/interswitch", notification("moaum-it-notify", "an-invented-password", paid, logId, "100.00", false, false)))
                    .contains("<PaymentLogId>" + logId + "</PaymentLogId><Status>0</Status>");
            assertThat(jdbc.sql("SELECT confirmed_at IS NOT NULL FROM finance.payment_reference WHERE reference = :r").param("r", paid).query(Boolean.class).single()).isTrue();
            assertThat(postXml("/api/v1/payments/paydirect/interswitch", validate.formatted(paid))).contains("<Status>1</Status>");
            assertThat(jdbc.sql("SELECT payload->>'why' FROM finance.gateway_event WHERE gateway = 'paydirect' AND source = 'VALIDATE' AND reference = :r ORDER BY received_at DESC LIMIT 1")
                    .param("r", paid).query(String.class).single()).isEqualTo("Already paid");
            ResponseEntity<Map> notWithdrawn = it.call(bursar, HttpMethod.POST, "/api/v1/payments/paydirect/test-references/" + paid + "/withdraw", Map.of());
            assertThat(notWithdrawn.getStatusCode().value()).isEqualTo(422);
            assertThat(notWithdrawn.getBody().get("code")).isEqualTo("GATEWAY_TEST_PAID");
        } finally {
            it.call(ict, HttpMethod.POST, "/api/v1/payments/gateways/paydirect/clear-key", Map.of());
        }
    }
}
