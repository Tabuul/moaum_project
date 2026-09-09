package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
}
