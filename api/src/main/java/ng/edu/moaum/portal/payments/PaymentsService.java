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
    private final String envPaystack;
    private final String envFlutterwave;
    private final String envFlutterwaveHash;
    private final String configKey;
    private final String portalUrl;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    PaymentsService(PaymentsRepository repo, PlatformTransactionManager transactions,
                    @Value("${moaum.payments.paystack-secret:}") String paystackSecret,
                    @Value("${moaum.payments.flutterwave-secret:}") String flutterwaveSecret,
                    @Value("${moaum.payments.flutterwave-hash:}") String flutterwaveHash,
                    @Value("${moaum.config.key:${moaum.auth.hmac-secret:}}") String configKey,
                    @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.repo = repo;
        this.tx = new TransactionTemplate(transactions);
        this.envPaystack = blank(paystackSecret) ? "" : paystackSecret.trim();
        this.envFlutterwave = blank(flutterwaveSecret) ? "" : flutterwaveSecret.trim();
        this.envFlutterwaveHash = blank(flutterwaveHash) ? "" : flutterwaveHash.trim();
        this.configKey = configKey == null ? "" : configKey.trim();
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    private static boolean blank(String s) {
        return s == null || s.isBlank();
    }

    /* ── the secret in force: the dashboard value (V039, encrypted at rest) if set, else the service variable ── */
    private String paystackSecret() {
        if (!configKey.isEmpty()) {
            String db = repo.gatewaySecret("paystack", configKey);
            if (db != null && !db.isBlank()) {
                return db.trim();
            }
        }
        return envPaystack;
    }

    private String flutterwaveSecret() {
        if (!configKey.isEmpty()) {
            String db = repo.gatewaySecret("flutterwave", configKey);
            if (db != null && !db.isBlank()) {
                return db.trim();
            }
        }
        return envFlutterwave;
    }

    private String flutterwaveHash() {
        if (!configKey.isEmpty()) {
            String db = repo.gatewayHash("flutterwave", configKey);
            if (db != null && !db.isBlank()) {
                return db.trim();
            }
        }
        return envFlutterwaveHash;
    }

    public boolean paystackOn() {
        return !paystackSecret().isEmpty();
    }

    public boolean flutterwaveOn() {
        return !flutterwaveSecret().isEmpty();
    }

    /** which gateways are wired, for the button to say so */
    public Map<String, Object> gateways() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("paystack", paystackOn());
        m.put("flutterwave", flutterwaveOn());
        return m;
    }

    /* ── checkout ── */

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
        final String chosen = g;
        AuditContextHolder.with(new AuditContext(account, "bursar", "checkout opened for " + r.reference(), null, null),
                () -> tx.execute(st -> { repo.attempt(r.reference(), chosen, r.kind(), account); return null; }));
        return Map.of("url", url, "gateway", g, "reference", r.reference());
    }

    private String paystackInitialize(PaymentsRepository.Reference r, String back) {
        long kobo = r.amount().movePointRight(2).longValueExact();
        String body = mapper.writeValueAsString(Map.of("email", r.email(), "amount", kobo, "reference", r.reference(), "callback_url", back,
                "metadata", Map.of("application", r.applicationNo(), "kind", r.kind())));
        Map<String, Object> answer = post("https://api.paystack.co/transaction/initialize", body, "Bearer " + paystackSecret());
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
        Map<String, Object> answer = post("https://api.flutterwave.com/v3/payments", body, "Bearer " + flutterwaveSecret());
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
                hmacSha512Hex(paystackSecret(), body).getBytes(StandardCharsets.UTF_8), signature.trim().toLowerCase().getBytes(StandardCharsets.UTF_8));
    }

    /** Flutterwave: the verif-hash header equals the secret hash set on the dashboard */
    public boolean flutterwaveHashValid(String header) {
        String hash = flutterwaveHash();
        return !hash.isEmpty() && header != null && java.security.MessageDigest.isEqual(
                hash.getBytes(StandardCharsets.UTF_8), header.trim().getBytes(StandardCharsets.UTF_8));
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
        return settle(gateway, "WEBHOOK", null, reference, paid, success ? "success" : "failed", success, providerRef, null);
    }

    /** the one settlement, whichever path reached it, with the gateway's own words kept beside what the portal did (V037) */
    Map<String, Object> settle(String gateway, String source, String event, String reference, BigDecimal paid, String status, boolean success,
                               String providerRef, String payload) {
        PaymentsRepository.Reference r = repo.byReference(reference).or(() -> repo.studentReference(reference)).orElse(null);
        String outcome;
        Map<String, Object> answer;
        if (r == null) {
            LOG.warn("payments: {} names a reference this portal did not generate: {}", gateway, reference);
            outcome = "UNKNOWN_REFERENCE";
            answer = Map.of("outcome", "unknown reference");
        } else if (!success) {
            outcome = "NOT_SUCCESSFUL";
            answer = Map.of("outcome", "not successful");
        } else if (paid.compareTo(r.amount()) < 0) {
            LOG.warn("payments: {} paid {} against {} owing {}", gateway, paid, reference, r.amount());
            outcome = "SHORT_PAID";
            answer = Map.of("outcome", "short paid", "paid", paid, "owed", r.amount());
        } else {
            final boolean student = "FEES".equals(r.kind());
            String channel = "Card · " + (gateway.equals("paystack") ? "Paystack" : "Flutterwave");
            String settled = AuditContextHolder.with(new AuditContext(NOBODY, "bursar", gateway + " " + source.toLowerCase() + " " + providerRef, null, null),
                    () -> tx.execute(st -> student
                            ? repo.confirmStudent(reference, channel, gateway + " " + providerRef + " · " + paid.toPlainString())
                            : repo.confirm(reference, channel, gateway + " " + providerRef + " · " + paid.toPlainString())));
            outcome = "already confirmed".equals(settled) ? "ALREADY_SETTLED" : "SETTLED";
            answer = Map.of("outcome", settled, "reference", reference);
        }
        log(gateway, source, event, reference, providerRef, paid, status, true, outcome, payload);
        return answer;
    }

    /** every event is written, signature good or bad, as an act at the Bursary's door */
    void log(String gateway, String source, String event, String reference, String providerRef, BigDecimal amount, String status, boolean signatureOk,
             String outcome, String payload) {
        try {
            AuditContextHolder.with(new AuditContext(NOBODY, "bursar", gateway + " " + source.toLowerCase() + " event", null, null),
                    () -> tx.execute(st -> repo.logEvent(gateway, source, event, reference, providerRef, amount, status, signatureOk, outcome, payload)));
        } catch (RuntimeException notLogged) {
            LOG.warn("payments: the {} event was not written to the log: {}", gateway, notLogged.getMessage());
        }
    }

    /** a webhook whose signature does not verify is discarded and logged; nothing in it is read as a fact */
    public void refused(String gateway, String body) {
        log(gateway, "WEBHOOK", null, null, null, null, null, false, "BAD_SIGNATURE", body != null && body.length() < 20000 ? body : null);
    }

    /* ── a callback is a hint: the gateway is asked what a reference actually settled for ── */

    private Map<String, Object> get(String url, String authorization) {
        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(20)).header("Authorization", authorization).GET().build();
            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            return mapper.readValue(res.body() == null ? "{}" : res.body(), new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
        } catch (Exception e) {
            throw new DomainRuleViolation("PAY_GATEWAY_UNREACHABLE", "The payment gateway could not be reached: " + e.getMessage(),
                    new DomainRuleViolation.Remedy("Try again in a moment.", "Bursary"));
        }
    }

    /**
     * Asks the gateway about a reference and settles what it answers — the
     * reconciler's act, and the student's "check again". Nothing is credited
     * on the callback's word alone.
     */
    public Map<String, Object> verify(String referenceIn, String source) {
        String reference = referenceIn == null ? "" : referenceIn.trim().toUpperCase();
        PaymentsRepository.Reference r = repo.byReference(reference).or(() -> repo.studentReference(reference))
                .orElseThrow(() -> new NotFound("fee reference", reference));
        if (r.confirmedAt() != null) {
            return Map.of("outcome", "already confirmed", "reference", reference);
        }
        Map<String, Object> out = Map.of("outcome", "no gateway", "reference", reference);
        if (paystackOn()) {
            Map<String, Object> a = get("https://api.paystack.co/transaction/verify/" + reference, "Bearer " + paystackSecret());
            if (a.get("data") instanceof Map<?, ?> d && d.get("status") != null) {
                BigDecimal paid = d.get("amount") == null ? BigDecimal.ZERO : new BigDecimal(String.valueOf(d.get("amount"))).movePointLeft(2);
                String status = String.valueOf(d.get("status"));
                out = settle("paystack", source, "verify", reference, paid, status, "success".equals(status),
                        d.get("id") == null ? reference : String.valueOf(d.get("id")), mapper.writeValueAsString(a));
                if ("success".equals(status)) {
                    repo.checked(reference);
                    return out;
                }
            } else {
                log("paystack", source, "verify", reference, null, null, String.valueOf(a.getOrDefault("message", "no answer")), true, "GATEWAY_ERROR", mapper.writeValueAsString(a));
                out = Map.of("outcome", "not found at the gateway", "reference", reference, "gateway", "paystack", "said", String.valueOf(a.getOrDefault("message", "")));
            }
        }
        if (flutterwaveOn()) {
            Map<String, Object> a = get("https://api.flutterwave.com/v3/transactions/verify_by_reference?tx_ref=" + reference, "Bearer " + flutterwaveSecret());
            if (a.get("data") instanceof Map<?, ?> d && d.get("status") != null) {
                BigDecimal paid = d.get("amount") == null ? BigDecimal.ZERO : new BigDecimal(String.valueOf(d.get("amount")));
                String status = String.valueOf(d.get("status"));
                out = settle("flutterwave", source, "verify", reference, paid, status, "successful".equals(status),
                        d.get("flw_ref") == null ? String.valueOf(d.get("id")) : String.valueOf(d.get("flw_ref")), mapper.writeValueAsString(a));
            } else {
                log("flutterwave", source, "verify", reference, null, null, String.valueOf(a.getOrDefault("message", "no answer")), true, "GATEWAY_ERROR", mapper.writeValueAsString(a));
                if ("no gateway".equals(out.get("outcome"))) {
                    out = Map.of("outcome", "not found at the gateway", "reference", reference, "gateway", "flutterwave", "said", String.valueOf(a.getOrDefault("message", "")));
                }
            }
        }
        AuditContextHolder.with(new AuditContext(NOBODY, "bursar", "reconciler checked " + reference, null, null), () -> tx.execute(st -> { repo.checked(reference); return null; }));
        return out;
    }

    /** the student's own reference, or an office's: who may ask */
    public Map<String, Object> verifyFor(UUID account, boolean office, String reference) {
        if (!office) {
            PaymentsRepository.Reference r = repo.byReference(reference).or(() -> repo.studentReference(reference)).orElseThrow(() -> new NotFound("fee reference", reference));
            if (!r.accountId().equals(account)) {
                throw new NotFound("fee reference", reference);
            }
        }
        return verify(reference, "VERIFY");
    }

    /** every ten minutes, and whether or not anybody is watching: the hanging payments are asked about */
    @org.springframework.scheduling.annotation.Scheduled(fixedDelayString = "${moaum.payments.sweep-every-ms:600000}", initialDelayString = "120000")
    public void sweep() {
        if (!paystackOn() && !flutterwaveOn()) {
            return;
        }
        for (Map<String, Object> h : repo.hanging()) {
            Number minutes = (Number) h.get("minutes");
            Number checks = (Number) h.get("checks");
            if (minutes.intValue() < 5 || checks.intValue() >= 12) {
                continue;
            }
            try {
                verify(String.valueOf(h.get("reference")), "SWEEP");
            } catch (RuntimeException e) {
                LOG.warn("payments: sweep could not verify {}: {}", h.get("reference"), e.getMessage());
            }
        }
    }

    /* ── the Bursary's desk ── */

    public Map<String, Object> bursary() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("gateways", java.util.List.of(
                Map.of("gateway", "paystack", "on", paystackOn(), "mode", paystackOn() ? (paystackSecret().startsWith("sk_test") ? "TEST" : "LIVE") : "OFF",
                        "webhook", "/api/v1/payments/webhook/paystack", "channels", "Card · bank transfer · USSD"),
                Map.of("gateway", "flutterwave", "on", flutterwaveOn(), "mode", flutterwaveOn() ? (flutterwaveSecret().toUpperCase().contains("_TEST") ? "TEST" : "LIVE") : "OFF",
                        "webhook", "/api/v1/payments/webhook/flutterwave", "hash", !flutterwaveHash().isEmpty(), "channels", "Card · bank transfer · USSD")));
        out.put("tiles", repo.eventTiles());
        out.put("events", repo.events(200));
        out.put("hanging", repo.hanging());
        out.put("portalUrl", portalUrl);
        return out;
    }

    /** a test checkout: a small reference for a named student, opened on the gateway so the webhook can be watched arriving */
    public Map<String, Object> testCheckout(String number, BigDecimal amount, String gateway) {
        UUID student = repo.studentByNumber(number == null ? "" : number.trim()).orElseThrow(() -> new DomainRuleViolation("PAY_NO_STUDENT",
                "No student carries the number " + number + ".", new DomainRuleViolation.Remedy("A demo student's matriculation number does.", "Bursary")));
        BigDecimal amt = amount == null || amount.signum() <= 0 ? new BigDecimal("100") : amount;
        String reference = AuditContextHolder.with(AuditContextHolder.required(), () -> tx.execute(st -> repo.testReference(student, repo.currentSession(), amt)));
        PaymentsRepository.Reference r = repo.studentReference(reference).orElseThrow();
        String g = gateway == null || gateway.isBlank() ? (paystackOn() ? "paystack" : "flutterwave") : gateway.trim().toLowerCase();
        String back = portalUrl + "/finance/gateways?paid=" + reference;
        String url = "paystack".equals(g) && paystackOn() ? paystackInitialize(r, back) : "flutterwave".equals(g) && flutterwaveOn() ? flutterwaveInitialize(r, back) : null;
        if (url == null) {
            throw new DomainRuleViolation("PAY_GATEWAY_NOT_WIRED", "That gateway is not wired.", new DomainRuleViolation.Remedy("Set its secret on the API service.", "Directorate of ICT"));
        }
        AuditContextHolder.with(AuditContextHolder.required(), () -> tx.execute(st -> { repo.attempt(reference, g, "TEST", student); return null; }));
        return Map.of("url", url, "gateway", g, "reference", reference, "amount", amt);
    }

    public Map<String, Object> resolveEvent(UUID id, String resolution) {
        repo.resolve(id, resolution);
        return Map.of("id", id, "resolved", true);
    }


    /* ── the dashboard's key management (V039): set encrypted, shown never ── */

    public java.util.List<java.util.Map<String, Object>> gatewayConfig() {
        return repo.gatewayConfig();
    }

    public java.util.Map<String, Object> setKey(String gatewayIn, String secret, String hash) {
        String gateway = gatewayIn == null ? "" : gatewayIn.trim().toLowerCase();
        if (!gateway.equals("paystack") && !gateway.equals("flutterwave")) {
            throw new DomainRuleViolation("PAY_GATEWAY", "The gateway is Paystack or Flutterwave.", new DomainRuleViolation.Remedy("One of the two.", "Bursary"));
        }
        if (configKey.isEmpty()) {
            throw new DomainRuleViolation("PAY_NO_CONFIG_KEY", "The portal has no passphrase to encrypt a gateway key with.",
                    new DomainRuleViolation.Remedy("Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service; a key is never stored in the clear.", "Directorate of ICT"));
        }
        if (secret == null || secret.isBlank()) {
            throw new DomainRuleViolation("PAY_SECRET_BLANK", "The secret key is blank.", new DomainRuleViolation.Remedy("Paste the key from the gateway's dashboard.", "Bursary"));
        }
        String s = secret.trim();
        String mode = gateway.equals("paystack") ? (s.startsWith("sk_test") ? "TEST" : "LIVE") : (s.toUpperCase().contains("_TEST") ? "TEST" : "LIVE");
        String last4 = s.length() > 4 ? s.substring(s.length() - 4) : "****";
        String hashArg = hash == null || hash.isBlank() ? null : hash.trim();
        // the write must run inside an attributed transaction, or the V039 function
        // refuses ("a gateway key is set by a person") because moaum.actor_id is unset.
        AuditContextHolder.with(AuditContextHolder.required(),
                () -> tx.execute(st -> { repo.setGatewaySecret(gateway, s, hashArg, mode, last4, configKey); return null; }));
        return java.util.Map.of("gateway", gateway, "configured", true, "mode", mode, "last4", last4);
    }

    public java.util.Map<String, Object> clearKey(String gatewayIn) {
        String gateway = gatewayIn == null ? "" : gatewayIn.trim().toLowerCase();
        AuditContextHolder.with(AuditContextHolder.required(),
                () -> tx.execute(st -> { repo.clearGatewaySecret(gateway); return null; }));
        return java.util.Map.of("gateway", gateway, "configured", false);
    }
}
