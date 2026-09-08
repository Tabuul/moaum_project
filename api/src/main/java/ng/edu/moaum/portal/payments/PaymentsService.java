package ng.edu.moaum.portal.payments;

import java.math.BigDecimal;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Hosted checkout and the signed webhook, for Paystack and Flutterwave. The
 * reference the gateway carries is the one this portal generated, so the
 * webhook confirms exactly one fee, once, for at least the amount owed, as
 * an act attributed to the Bursary's door with the gateway's reference on
 * the record. A gateway is on when its secret is set, and off — honestly —
 * when it is not.
 */
@Service
public class PaymentsService {

    private static final Logger LOG = LoggerFactory.getLogger(PaymentsService.class);
    static final UUID NOBODY = new UUID(0, 0);

    private final PaymentsRepository repo;
    private final TransactionTemplate tx;
    private final String paystackSecret;
    private final String flutterwaveSecret;
    private final String flutterwaveHash;
    private final String portalUrl;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    PaymentsService(PaymentsRepository repo, PlatformTransactionManager transactions,
                    @Value("${moaum.payments.paystack-secret:}") String paystackSecret,
                    @Value("${moaum.payments.flutterwave-secret:}") String flutterwaveSecret,
                    @Value("${moaum.payments.flutterwave-hash:}") String flutterwaveHash,
                    @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.repo = repo;
        this.tx = new TransactionTemplate(transactions);
        this.paystackSecret = blank(paystackSecret) ? "" : paystackSecret.trim();
        this.flutterwaveSecret = blank(flutterwaveSecret) ? "" : flutterwaveSecret.trim();
        this.flutterwaveHash = blank(flutterwaveHash) ? "" : flutterwaveHash.trim();
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    private static boolean blank(String s) {
        return s == null || s.isBlank();
    }

    public boolean paystackOn() {
        return !paystackSecret.isEmpty();
    }

    public boolean flutterwaveOn() {
        return !flutterwaveSecret.isEmpty();
    }

    /** which gateways are wired, for the button to say so */
    public Map<String, Object> gateways() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("paystack", paystackOn());
        m.put("flutterwave", flutterwaveOn());
        return m;
    }

    /* ── checkout ── */

    @Transactional(readOnly = true)
    public Map<String, Object> checkout(UUID account, String reference, String gateway) {
        /* an applicant's fee reference, or a student's (V026): the account is the applicant's account or the student's own id */
        PaymentsRepository.Reference r = repo.byReference(reference)
                .or(() -> repo.studentReference(reference))
                .orElseThrow(() -> new NotFound("fee reference", reference));
        if (!r.accountId().equals(account)) {
            throw new NotFound("fee reference", reference);
        }
        if (r.confirmedAt() != null) {
            throw new DomainRuleViolation("PAY_ALREADY_CONFIRMED", "This reference is already confirmed as paid.",
                    new DomainRuleViolation.Remedy("Nothing more is owed against it.", "You"));
        }
        if (r.expiresAt().isBefore(OffsetDateTime.now())) {
            throw new DomainRuleViolation("PAY_REFERENCE_EXPIRED", "This reference has expired.",
                    new DomainRuleViolation.Remedy("Generate a new one; it is free of charge.", "You"));
        }
        String g = gateway == null ? (paystackOn() ? "paystack" : flutterwaveOn() ? "flutterwave" : "") : gateway.trim().toLowerCase();
        String back = portalUrl + ("FEES".equals(r.kind()) ? "/student/fees" : "ACCEPTANCE".equals(r.kind()) ? "/applicant/accept" : "/applicant/fee") + "?paid=" + r.reference();
        String url;
        if ("paystack".equals(g) && paystackOn()) {
            url = paystackInitialize(r, back);
        } else if ("flutterwave".equals(g) && flutterwaveOn()) {
            url = flutterwaveInitialize(r, back);
        } else {
            throw new DomainRuleViolation("PAY_GATEWAY_NOT_WIRED", "Card and USSD payment arrive when a payment gateway is wired to the portal.",
                    new DomainRuleViolation.Remedy("Pay by bank transfer or at a bank branch against the reference; the Bursary confirms it against the bank's record.", "Bursary"));
        }
        return Map.of("url", url, "gateway", g, "reference", r.reference());
    }

    private String paystackInitialize(PaymentsRepository.Reference r, String back) {
        long kobo = r.amount().movePointRight(2).longValueExact();
        String body = mapper.writeValueAsString(Map.of("email", r.email(), "amount", kobo, "reference", r.reference(), "callback_url", back,
                "metadata", Map.of("application", r.applicationNo(), "kind", r.kind())));
        Map<String, Object> answer = post("https://api.paystack.co/transaction/initialize", body, "Bearer " + paystackSecret);
        Object data = answer.get("data");
        if (!(data instanceof Map<?, ?> d) || d.get("authorization_url") == null) {
            throw new DomainRuleViolation("PAY_GATEWAY_REFUSED", "The payment gateway did not open a checkout: " + answer.getOrDefault("message", "no answer"),
                    new DomainRuleViolation.Remedy("Try again in a moment, or pay by transfer against the reference.", "Bursary"));
        }
        return String.valueOf(d.get("authorization_url"));
    }

    private String flutterwaveInitialize(PaymentsRepository.Reference r, String back) {
        String body = mapper.writeValueAsString(Map.of("tx_ref", r.reference(), "amount", r.amount().toPlainString(), "currency", "NGN",
                "redirect_url", back, "customer", Map.of("email", r.email()),
                "customizations", Map.of("title", "MOAUM " + ("ACCEPTANCE".equals(r.kind()) ? "acceptance fee" : "application fee"))));
        Map<String, Object> answer = post("https://api.flutterwave.com/v3/payments", body, "Bearer " + flutterwaveSecret);
        Object data = answer.get("data");
        if (!(data instanceof Map<?, ?> d) || d.get("link") == null) {
            throw new DomainRuleViolation("PAY_GATEWAY_REFUSED", "The payment gateway did not open a checkout: " + answer.getOrDefault("message", "no answer"),
                    new DomainRuleViolation.Remedy("Try again in a moment, or pay by transfer against the reference.", "Bursary"));
        }
        return String.valueOf(d.get("link"));
    }

    private Map<String, Object> post(String url, String body, String authorization) {
        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(20))
                    .header("Content-Type", "application/json").header("Authorization", authorization)
                    .POST(HttpRequest.BodyPublishers.ofString(body)).build();
            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            return mapper.readValue(res.body() == null ? "{}" : res.body(), new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
        } catch (Exception e) {
            throw new DomainRuleViolation("PAY_GATEWAY_UNREACHABLE", "The payment gateway could not be reached: " + e.getMessage(),
                    new DomainRuleViolation.Remedy("Try again in a moment, or pay by transfer against the reference.", "Bursary"));
        }
    }

    /* ── the webhooks ── */

    public static String hmacSha512Hex(String secret, String body) {
        try {
            Mac mac = Mac.getInstance("HmacSHA512");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA512"));
            return HexFormat.of().formatHex(mac.doFinal(body.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    /** Paystack: the body signed with the secret key, HMAC-SHA512, in x-paystack-signature */
    public boolean paystackSignatureValid(String body, String signature) {
        return paystackOn() && signature != null && java.security.MessageDigest.isEqual(
                hmacSha512Hex(paystackSecret, body).getBytes(StandardCharsets.UTF_8), signature.trim().toLowerCase().getBytes(StandardCharsets.UTF_8));
    }

    /** Flutterwave: the verif-hash header equals the secret hash set on the dashboard */
    public boolean flutterwaveHashValid(String header) {
        return !flutterwaveHash.isEmpty() && header != null && java.security.MessageDigest.isEqual(
                flutterwaveHash.getBytes(StandardCharsets.UTF_8), header.trim().getBytes(StandardCharsets.UTF_8));
    }

    public Map<String, Object> paystackEvent(String body) {
        Map<String, Object> event = mapper.readValue(body, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
        if (!"charge.success".equals(event.get("event")) || !(event.get("data") instanceof Map<?, ?> d)) {
            return Map.of("outcome", "ignored");
        }
        String reference = String.valueOf(d.get("reference"));
        BigDecimal paid = d.get("amount") == null ? BigDecimal.ZERO : new BigDecimal(String.valueOf(d.get("amount"))).movePointLeft(2);
        String status = String.valueOf(d.get("status"));
        String providerRef = d.get("id") == null ? reference : String.valueOf(d.get("id"));
        return settle("paystack", reference, paid, "success".equals(status), providerRef);
    }

    public Map<String, Object> flutterwaveEvent(String body) {
        Map<String, Object> event = mapper.readValue(body, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
        if (!(event.get("data") instanceof Map<?, ?> d)) {
            return Map.of("outcome", "ignored");
        }
        String reference = String.valueOf(d.get("tx_ref"));
        BigDecimal paid = d.get("amount") == null ? BigDecimal.ZERO : new BigDecimal(String.valueOf(d.get("amount")));
        String status = String.valueOf(d.get("status"));
        String providerRef = d.get("flw_ref") == null ? String.valueOf(d.get("id")) : String.valueOf(d.get("flw_ref"));
        return settle("flutterwave", reference, paid, "successful".equals(status), providerRef);
    }

    /** the gateway's confirmation is the Bursary's act at the door, with the gateway's reference on the record */
    Map<String, Object> settle(String gateway, String reference, BigDecimal paid, boolean success, String providerRef) {
        PaymentsRepository.Reference r = repo.byReference(reference).or(() -> repo.studentReference(reference)).orElse(null);
        if (r == null) {
            LOG.warn("payments: {} webhook names a reference this portal did not generate: {}", gateway, reference);
            return Map.of("outcome", "unknown reference");
        }
        final boolean student = "FEES".equals(r.kind());
        if (!success) {
            return Map.of("outcome", "not successful");
        }
        if (paid.compareTo(r.amount()) < 0) {
            LOG.warn("payments: {} paid {} against {} owing {}", gateway, paid, reference, r.amount());
            return Map.of("outcome", "short paid", "paid", paid, "owed", r.amount());
        }
        String channel = "Card · " + (gateway.equals("paystack") ? "Paystack" : "Flutterwave");
        String outcome = AuditContextHolder.with(new AuditContext(NOBODY, "bursar", gateway + " webhook " + providerRef, null, null),
                () -> tx.execute(status -> student
                        ? repo.confirmStudent(reference, channel, gateway + " " + providerRef + " · " + paid.toPlainString())
                        : repo.confirm(reference, channel, gateway + " " + providerRef + " · " + paid.toPlainString())));
        return Map.of("outcome", outcome, "reference", reference);
    }
}
