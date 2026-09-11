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
    private final String envQuickteller;
    private final String configKey;
    private final String portalUrl;
    private final String apiUrl;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    PaymentsService(PaymentsRepository repo, PlatformTransactionManager transactions,
                    @Value("${moaum.payments.paystack-secret:}") String paystackSecret,
                    @Value("${moaum.payments.flutterwave-secret:}") String flutterwaveSecret,
                    @Value("${moaum.payments.flutterwave-hash:}") String flutterwaveHash,
                    @Value("${moaum.payments.quickteller-config:}") String quicktellerConfig,
                    @Value("${moaum.config.key:${moaum.auth.hmac-secret:}}") String configKey,
                    @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl,
                    @Value("${moaum.api-url:}") String apiUrl) {
        this.repo = repo;
        this.tx = new TransactionTemplate(transactions);
        this.envPaystack = blank(paystackSecret) ? "" : paystackSecret.trim();
        this.envFlutterwave = blank(flutterwaveSecret) ? "" : flutterwaveSecret.trim();
        this.envFlutterwaveHash = blank(flutterwaveHash) ? "" : flutterwaveHash.trim();
        this.envQuickteller = blank(quicktellerConfig) ? "" : quicktellerConfig.trim();
        this.configKey = configKey == null ? "" : configKey.trim();
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
        this.apiUrl = apiUrl == null ? "" : apiUrl.replaceAll("/+$", "");
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

    /* ── Quickteller Business (Interswitch): a set of credentials, not one string ── */

    /**
     * The Quickteller merchant's four things: a client id and secret for the
     * requery API, and a merchant code and pay-item id for the hosted page,
     * with a sandbox flag. Kept as one JSON document in the encrypted secret
     * slot (V052), so it is stored and read exactly as any other gateway key.
     */
    record Quickteller(String clientId, String clientSecret, String merchantCode, String payItemId, boolean sandbox) {
    }

    private String quicktellerConfigJson() {
        if (!configKey.isEmpty()) {
            String db = repo.gatewaySecret("quickteller", configKey);
            if (db != null && !db.isBlank()) {
                return db.trim();
            }
        }
        return envQuickteller;
    }

    Quickteller quickteller() {
        String json = quicktellerConfigJson();
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            Map<String, Object> m = mapper.readValue(json, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
            String clientId = str(m.get("clientId"));
            String clientSecret = str(m.get("clientSecret"));
            String merchantCode = str(m.get("merchantCode"));
            String payItemId = str(m.get("payItemId"));
            boolean sandbox = Boolean.parseBoolean(str(m.getOrDefault("sandbox", "false")));
            if (clientId.isEmpty() || clientSecret.isEmpty() || merchantCode.isEmpty() || payItemId.isEmpty()) {
                return null;
            }
            return new Quickteller(clientId, clientSecret, merchantCode, payItemId, sandbox);
        } catch (RuntimeException notJson) {
            LOG.warn("payments: the Quickteller configuration is not the JSON it should be: {}", notJson.getMessage());
            return null;
        }
    }

    private static String str(Object o) {
        return o == null ? "" : String.valueOf(o).trim();
    }

    public boolean quicktellerOn() {
        return quickteller() != null;
    }

    /** PayDirect is on when a main biller is configured (the billers are a setting, seeded by V080) */
    public boolean paydirectOn() {
        return repo.paydirectActive();
    }

    /** the PayDirect query-API credentials (V080): the client id and secret Interswitch issues for the
     *  Transaction Query; kept in the same encrypted secret slot as the other gateways, read only here. */
    record PayDirect(String clientId, String clientSecret, boolean sandbox) {
    }

    private String paydirectConfigJson() {
        if (!configKey.isBlank()) {
            String db = repo.gatewaySecret("paydirect", configKey);
            if (db != null && !db.isBlank()) return db;
        }
        return "";
    }

    PayDirect paydirectQuery() {
        String json = paydirectConfigJson();
        if (json.isBlank()) return null;
        try {
            Map<String, Object> m = mapper.readValue(json, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
            String clientId = str(m.get("clientId"));
            String clientSecret = str(m.get("clientSecret"));
            boolean sandbox = m.get("sandbox") == null || Boolean.parseBoolean(String.valueOf(m.get("sandbox")));
            if (clientId.isEmpty() || clientSecret.isEmpty()) return null;
            return new PayDirect(clientId, clientSecret, sandbox);
        } catch (RuntimeException notJson) {
            LOG.warn("payments: the PayDirect configuration is not the JSON it should be: {}", notJson.getMessage());
            return null;
        }
    }

    public boolean paydirectQueryOn() {
        return paydirectQuery() != null;
    }

    private static String paydirectQueryEndpoint(boolean sandbox) {
        // Interswitch PayDirect transaction query; confirm the exact host/path on merchant onboarding
        return sandbox ? "https://qa.interswitchng.com/paydirect/api/v1/gettransaction.json"
                : "https://webpay.interswitchng.com/paydirect/api/v1/gettransaction.json";
    }

    /** which gateways are wired, for the button to say so */
    public Map<String, Object> gateways() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("paystack", paystackOn());
        m.put("flutterwave", flutterwaveOn());
        m.put("quickteller", quicktellerOn());
        m.put("paydirect", paydirectOn());
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
        String g = gateway == null ? (paystackOn() ? "paystack" : flutterwaveOn() ? "flutterwave" : quicktellerOn() ? "quickteller" : "") : gateway.trim().toLowerCase();
        String back = portalUrl + ("FEES".equals(r.kind()) ? "/student/fees" : "ACCEPTANCE".equals(r.kind()) ? "/applicant/accept" : "/applicant/fee") + "?paid=" + r.reference();
        String url;
        if ("paystack".equals(g) && paystackOn()) {
            url = paystackInitialize(r, back);
        } else if ("flutterwave".equals(g) && flutterwaveOn()) {
            url = flutterwaveInitialize(r, back);
        } else if ("quickteller".equals(g) && quicktellerOn()) {
            // Quickteller's page is reached by a form POST, so the browser is sent to
            // this portal's own /quickteller/start, which renders the self-posting form.
            url = quicktellerStartUrl(r.reference());
        } else if ("paydirect".equals(g) && paydirectOn()) {
            // PayDirect is not a redirect checkout: the student pays the reference (the PRN)
            // on the Quickteller biller for their College, or by ATM/USSD/bank. Return the
            // instruction, and record the attempt so the sweep re-checks it.
            return paydirectInstruction(r, account);
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

    /* ── Quickteller PayDirect (V080): billers routed by College; the PRN is the reference ── */

    private Map<String, Object> paydirectInstruction(PaymentsRepository.Reference r, UUID account) {
        Map<String, Object> b = "FEES".equals(r.kind()) ? repo.paydirectBillerFor(account) : repo.paydirectMain();
        final String chosen = "paydirect";
        AuditContextHolder.with(new AuditContext(account, "bursar", "PayDirect PRN issued for " + r.reference(), null, null),
                () -> tx.execute(st -> { repo.attempt(r.reference(), chosen, r.kind(), account); return null; }));
        String code = str(b.get("biller_code"));
        String amt = r.amount().stripTrailingZeros().toPlainString();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("gateway", "paydirect");
        out.put("reference", r.reference());
        out.put("prn", r.reference());
        out.put("billerCode", code);
        out.put("billerName", str(b.get("name")));
        out.put("payLink", b.get("pay_link"));
        out.put("ussd", "*723*" + code + "*" + amt + "#");
        out.put("amount", r.amount());
        return out;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> paydirect() {
        Map<String, Object> m = new java.util.LinkedHashMap<>();
        m.put("billers", repo.paydirectBillers());
        m.put("collections", repo.paydirectCollections(200));
        return m;
    }

    /** the Quickteller/PayDirect collections report, matched by PRN and confirmed — the report route to the details */
    public Map<String, Object> importPaydirect(java.util.List<Map<String, Object>> rows) {
        if (rows == null || rows.isEmpty()) {
            throw new DomainRuleViolation("PAY_PD_ROWS", "The report is rows: PRN, amount, and a settlement reference.",
                    new DomainRuleViolation.Remedy("Export the Quickteller collections report and send its rows.", "Bursary"));
        }
        String json = mapper.writeValueAsString(rows);
        return AuditContextHolder.with(AuditContextHolder.required(), () -> tx.execute(st -> repo.importPaydirect(json)));
    }

    public Map<String, Object> setPaydirectBiller(String scope, String code, String name, String link, Boolean active) {
        return AuditContextHolder.with(AuditContextHolder.required(),
                () -> tx.execute(st -> repo.setPaydirectBiller(scope, code, name, link, active == null || active)));
    }

    /* ── Quickteller Business (Interswitch): hosted page reached by a self-posting form ── */

    private String quicktellerStartUrl(String reference) {
        // the browser navigates here on this portal's origin; the API's own public
        // URL if it is set, else the portal's BFF, which forwards /api to the API
        String base = apiUrl.isEmpty() ? portalUrl + "/api/bff" : apiUrl;
        return base + "/api/v1/payments/quickteller/start?reference=" + reference;
    }

    private static String quicktellerPayEndpoint(boolean sandbox) {
        return sandbox ? "https://newwebpay.qa.interswitchng.com/collections/w/pay"
                : "https://newwebpay.interswitchng.com/collections/w/pay";
    }

    private static String quicktellerRequeryEndpoint(boolean sandbox) {
        return sandbox ? "https://qa.interswitchng.com/collections/api/v1/gettransaction.json"
                : "https://webpay.interswitchng.com/collections/api/v1/gettransaction.json";
    }

    private String backUrl(String kind, String reference) {
        return portalUrl + ("FEES".equals(kind) ? "/student/fees" : "ACCEPTANCE".equals(kind) ? "/applicant/accept" : "/applicant/fee") + "?paid=" + reference;
    }

    /** the self-submitting form that carries the payment to Interswitch's hosted page */
    public String quicktellerStartPage(String referenceIn) {
        String reference = referenceIn == null ? "" : referenceIn.trim().toUpperCase();
        Quickteller q = quickteller();
        PaymentsRepository.Reference r = repo.byReference(reference).or(() -> repo.studentReference(reference)).orElse(null);
        if (q == null || r == null) {
            return notice("This payment could not be started", "The reference is not one this portal is waiting on, or Quickteller is not configured.");
        }
        if (r.confirmedAt() != null) {
            return notice("Already paid", "This reference is already confirmed as paid; nothing more is owed against it.");
        }
        long kobo = r.amount().movePointRight(2).longValueExact();
        String action = quicktellerPayEndpoint(q.sandbox());
        String back = backUrl(r.kind(), r.reference());
        StringBuilder f = new StringBuilder();
        f.append("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">")
                .append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
                .append("<title>Opening Quickteller…</title></head>")
                .append("<body style=\"font:15px/1.5 system-ui,Segoe UI,Arial,sans-serif;color:#1c1c1c;margin:0;padding:48px 20px;text-align:center\">")
                .append("<p>Opening the secure Quickteller payment page for <strong>").append(esc(r.reference())).append("</strong>…</p>")
                .append("<p style=\"color:#666\">If it does not open in a moment, press the button.</p>")
                .append("<form id=\"qt\" method=\"POST\" action=\"").append(esc(action)).append("\">");
        field(f, "merchant_code", q.merchantCode());
        field(f, "pay_item_id", q.payItemId());
        field(f, "pay_item_name", "MOAUM " + ("ACCEPTANCE".equals(r.kind()) ? "acceptance fee" : "FEES".equals(r.kind()) ? "school fees" : "application fee"));
        field(f, "txn_ref", r.reference());
        field(f, "site_redirect_url", back);
        field(f, "amount", Long.toString(kobo));
        field(f, "currency", "566");
        field(f, "cust_id", r.email() == null ? r.applicationNo() : r.email());
        field(f, "cust_name", r.applicationNo());
        field(f, "cust_email", r.email() == null ? "" : r.email());
        field(f, "mode", q.sandbox() ? "TEST" : "LIVE");
        f.append("<button type=\"submit\" style=\"font:inherit;padding:10px 18px;border:0;border-radius:8px;background:#0a7d3f;color:#fff;cursor:pointer\">Pay with Quickteller</button>")
                .append("</form><script>document.getElementById('qt').submit();</script></body></html>");
        return f.toString();
    }

    private static void field(StringBuilder f, String name, String value) {
        f.append("<input type=\"hidden\" name=\"").append(esc(name)).append("\" value=\"").append(esc(value == null ? "" : value)).append("\">");
    }

    private static String notice(String title, String body) {
        return "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>"
                + esc(title) + "</title></head><body style=\"font:15px/1.5 system-ui,Segoe UI,Arial,sans-serif;color:#1c1c1c;margin:0;padding:48px 20px;text-align:center\"><h1 style=\"font-size:18px\">"
                + esc(title) + "</h1><p style=\"color:#555\">" + esc(body) + "</p></body></html>";
    }

    private static String esc(String s) {
        return s == null ? "" : s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;");
    }

    static String sha512Hex(String s) {
        try {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance("SHA-512");
            return HexFormat.of().formatHex(md.digest(s.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    /** Quickteller's notification is a hint only: find the reference in it and requery Interswitch. */
    public Map<String, Object> quicktellerNotified(String body) {
        String reference = null;
        try {
            Map<String, Object> m = mapper.readValue(body == null || body.isBlank() ? "{}" : body, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
            for (String k : new String[] { "merchantreference", "transactionreference", "txnref", "txn_ref", "paymentReference", "MerchantReference", "TransactionReference" }) {
                if (m.get(k) != null && !String.valueOf(m.get(k)).isBlank()) {
                    reference = String.valueOf(m.get(k));
                    break;
                }
            }
        } catch (RuntimeException notJson) {
            LOG.warn("payments: the Quickteller notification was not JSON: {}", notJson.getMessage());
        }
        if (reference == null || reference.isBlank()) {
            log("quickteller", "WEBHOOK", null, null, null, null, null, true, "NO_REFERENCE", body != null && body.length() < 20000 ? body : null);
            return Map.of("outcome", "ignored");
        }
        try {
            return verify(reference, "WEBHOOK");
        } catch (RuntimeException e) {
            LOG.warn("payments: the Quickteller notification for {} could not be verified: {}", reference, e.getMessage());
            return Map.of("outcome", "could not verify", "reference", reference);
        }
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
            String channel = gateway.equals("paydirect") ? "Quickteller PayDirect"
                    : "Card · " + (gateway.equals("paystack") ? "Paystack" : gateway.equals("quickteller") ? "Quickteller" : "Flutterwave");
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

    private Map<String, Object> getWith(String url, Map<String, String> headers) {
        try {
            HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(20)).GET();
            headers.forEach(b::header);
            HttpResponse<String> res = http.send(b.build(), HttpResponse.BodyHandlers.ofString());
            return mapper.readValue(res.body() == null ? "{}" : res.body(), new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
        } catch (Exception e) {
            throw new DomainRuleViolation("PAY_GATEWAY_UNREACHABLE", "The payment gateway could not be reached: " + e.getMessage(),
                    new DomainRuleViolation.Remedy("Try again in a moment.", "Bursary"));
        }
    }

    private static String enc(String s) {
        return java.net.URLEncoder.encode(s == null ? "" : s, StandardCharsets.UTF_8);
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
                    AuditContextHolder.with(new AuditContext(NOBODY, "bursar", "reconciler checked " + reference, null, null), () -> tx.execute(st -> { repo.checked(reference); return null; }));
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
        Quickteller q = quickteller();
        if (q != null) {
            long kobo = r.amount().movePointRight(2).longValueExact();
            // Interswitch requery: the Hash header is SHA-512 of (clientId + reference + clientSecret).
            // The exact inputs are per the merchant's Quickteller Business profile — confirm on onboarding.
            String hash = sha512Hex(q.clientId() + reference + q.clientSecret());
            String url = quicktellerRequeryEndpoint(q.sandbox()) + "?merchantcode=" + enc(q.merchantCode())
                    + "&transactionreference=" + enc(reference) + "&amount=" + kobo;
            Map<String, Object> a = getWith(url, Map.of("Hash", hash, "Accept", "application/json"));
            Object rc = a.get("ResponseCode");
            if (rc != null) {
                boolean success = "00".equals(String.valueOf(rc));
                BigDecimal paid = a.get("Amount") == null ? BigDecimal.ZERO : new BigDecimal(String.valueOf(a.get("Amount"))).movePointLeft(2);
                String providerRef = a.get("PaymentReference") != null ? String.valueOf(a.get("PaymentReference"))
                        : a.get("RetrievalReferenceNumber") != null ? String.valueOf(a.get("RetrievalReferenceNumber")) : reference;
                out = settle("quickteller", source, "verify", reference, paid, String.valueOf(rc), success, providerRef, mapper.writeValueAsString(a));
                if (success) {
                    AuditContextHolder.with(new AuditContext(NOBODY, "bursar", "reconciler checked " + reference, null, null), () -> tx.execute(st -> { repo.checked(reference); return null; }));
                    return out;
                }
            } else {
                log("quickteller", source, "verify", reference, null, null, String.valueOf(a.getOrDefault("ResponseDescription", "no answer")), true, "GATEWAY_ERROR", mapper.writeValueAsString(a));
                if ("no gateway".equals(out.get("outcome"))) {
                    out = Map.of("outcome", "not found at the gateway", "reference", reference, "gateway", "quickteller", "said", String.valueOf(a.getOrDefault("ResponseDescription", "")));
                }
            }
        }
        PayDirect pd = paydirectQuery();
        if (pd != null) {
            // the biller a reference belongs to: routed by College for a student's fees, else the main biller
            String biller = "FEES".equals(r.kind())
                    ? String.valueOf(repo.paydirectBillerFor(r.accountId()).get("biller_code"))
                    : String.valueOf(repo.paydirectMain().get("biller_code"));
            long kobo = r.amount().movePointRight(2).longValueExact();
            // Interswitch transaction query: the Hash header is SHA-512 of (clientId + reference + clientSecret);
            // the biller code is the merchantcode. The exact inputs are per the merchant's profile — confirm on onboarding.
            String hash = sha512Hex(pd.clientId() + reference + pd.clientSecret());
            String url = paydirectQueryEndpoint(pd.sandbox()) + "?merchantcode=" + enc(biller)
                    + "&transactionreference=" + enc(reference) + "&amount=" + kobo;
            Map<String, Object> a = getWith(url, Map.of("Hash", hash, "Accept", "application/json"));
            Object rc = a.get("ResponseCode");
            if (rc != null) {
                boolean success = "00".equals(String.valueOf(rc));
                BigDecimal paid = a.get("Amount") == null ? BigDecimal.ZERO : new BigDecimal(String.valueOf(a.get("Amount"))).movePointLeft(2);
                String providerRef = a.get("PaymentReference") != null ? String.valueOf(a.get("PaymentReference"))
                        : a.get("RetrievalReferenceNumber") != null ? String.valueOf(a.get("RetrievalReferenceNumber")) : reference;
                out = settle("paydirect", source, "verify", reference, paid, String.valueOf(rc), success, providerRef, mapper.writeValueAsString(a));
                if (success) {
                    AuditContextHolder.with(new AuditContext(NOBODY, "bursar", "reconciler checked " + reference, null, null), () -> tx.execute(st -> { repo.checked(reference); return null; }));
                    return out;
                }
            } else {
                log("paydirect", source, "verify", reference, null, null, String.valueOf(a.getOrDefault("ResponseDescription", "no answer")), true, "GATEWAY_ERROR", mapper.writeValueAsString(a));
                if ("no gateway".equals(out.get("outcome"))) {
                    out = Map.of("outcome", "not found at the gateway", "reference", reference, "gateway", "paydirect", "said", String.valueOf(a.getOrDefault("ResponseDescription", "")));
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

    /**
     * Every ten minutes, and whether or not anybody is watching: the hanging
     * payments are asked about, each on the channel of the gateway it was opened
     * on — Paystack's verify, Flutterwave's verify-by-reference, Quickteller's
     * requery. A reference the gateway now says is paid is settled exactly as a
     * webhook would settle it, so a dropped callback resolves itself.
     */
    @org.springframework.scheduling.annotation.Scheduled(fixedDelayString = "${moaum.payments.sweep-every-ms:600000}", initialDelayString = "120000")
    public void sweep() {
        if (!paystackOn() && !flutterwaveOn() && !quicktellerOn() && !paydirectQueryOn()) {
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
                        "webhook", "/api/v1/payments/webhook/flutterwave", "hash", !flutterwaveHash().isEmpty(), "channels", "Card · bank transfer · USSD"),
                Map.of("gateway", "quickteller", "on", quicktellerOn(), "mode", quicktellerOn() ? (quickteller().sandbox() ? "TEST" : "LIVE") : "OFF",
                        "webhook", "/api/v1/payments/webhook/quickteller", "channels", "Card · bank transfer · USSD · Quickteller")));
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
        // resolving stamps gateway_event (on the spine) with resolved_by; it must run
        // inside an attributed transaction, or the write is refused as unattributed.
        AuditContextHolder.with(AuditContextHolder.required(),
                () -> tx.execute(st -> { repo.resolve(id, resolution); return null; }));
        return Map.of("id", id, "resolved", true);
    }


    /* ── the dashboard's key management (V039): set encrypted, shown never ── */

    public java.util.List<java.util.Map<String, Object>> gatewayConfig() {
        return repo.gatewayConfig();
    }

    public java.util.Map<String, Object> setKey(String gatewayIn, String secret, String hash) {
        String gateway = gatewayIn == null ? "" : gatewayIn.trim().toLowerCase();
        if (!gateway.equals("paystack") && !gateway.equals("flutterwave") && !gateway.equals("quickteller")) {
            throw new DomainRuleViolation("PAY_GATEWAY", "The gateway is Paystack, Flutterwave or Quickteller.", new DomainRuleViolation.Remedy("One of the three.", "Directorate of ICT"));
        }
        if (configKey.isEmpty()) {
            throw new DomainRuleViolation("PAY_NO_CONFIG_KEY", "The portal has no passphrase to encrypt a gateway key with.",
                    new DomainRuleViolation.Remedy("Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service; a key is never stored in the clear.", "Directorate of ICT"));
        }
        if (secret == null || secret.isBlank()) {
            throw new DomainRuleViolation("PAY_SECRET_BLANK", "The secret key is blank.", new DomainRuleViolation.Remedy("Paste the key from the gateway's dashboard.", "Bursary"));
        }
        String s = secret.trim();
        String mode;
        String last4;
        if (gateway.equals("quickteller")) {
            // Quickteller's "secret" is the whole JSON credential document; validate it and
            // derive the mode from its sandbox flag and the last four from the merchant code
            try {
                Map<String, Object> m = mapper.readValue(s, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
                String mc = str(m.get("merchantCode"));
                if (str(m.get("clientId")).isEmpty() || str(m.get("clientSecret")).isEmpty() || mc.isEmpty() || str(m.get("payItemId")).isEmpty()) {
                    throw new DomainRuleViolation("PAY_QT_INCOMPLETE", "The Quickteller configuration needs clientId, clientSecret, merchantCode and payItemId.",
                            new DomainRuleViolation.Remedy("Paste all four from your Quickteller Business profile, with sandbox true for test.", "Directorate of ICT"));
                }
                mode = Boolean.parseBoolean(str(m.getOrDefault("sandbox", "false"))) ? "TEST" : "LIVE";
                last4 = mc.length() > 4 ? mc.substring(mc.length() - 4) : mc;
            } catch (DomainRuleViolation d) {
                throw d;
            } catch (RuntimeException notJson) {
                throw new DomainRuleViolation("PAY_QT_JSON", "The Quickteller configuration must be a JSON object with clientId, clientSecret, merchantCode, payItemId and sandbox.",
                        new DomainRuleViolation.Remedy("The Gateways screen builds it for you from the four fields; paste them there.", "Directorate of ICT"));
            }
        } else {
            mode = gateway.equals("paystack") ? (s.startsWith("sk_test") ? "TEST" : "LIVE") : (s.toUpperCase().contains("_TEST") ? "TEST" : "LIVE");
            last4 = s.length() > 4 ? s.substring(s.length() - 4) : "****";
        }
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
