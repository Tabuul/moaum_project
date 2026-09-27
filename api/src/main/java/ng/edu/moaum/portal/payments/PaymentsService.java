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
    private final String envQuicktellerParts;
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
                    @Value("${moaum.payments.quickteller.product-id:6498}") String qtProductId,
                    @Value("${moaum.payments.quickteller.pay-item-id:101}") String qtPayItemId,
                    @Value("${moaum.payments.quickteller.mac-key:}") String qtMacKey,
                    @Value("${moaum.payments.quickteller.chs-product-id:6207}") String qtChsProductId,
                    @Value("${moaum.payments.quickteller.chs-pay-item-id:101}") String qtChsPayItemId,
                    @Value("${moaum.payments.quickteller.chs-mac-key:}") String qtChsMacKey,
                    @Value("${moaum.payments.quickteller.sandbox:false}") boolean qtSandbox,
                    @Value("${moaum.config.key:${moaum.auth.hmac-secret:}}") String configKey,
                    @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl,
                    @Value("${moaum.api-url:}") String apiUrl) {
        this.repo = repo;
        this.tx = new TransactionTemplate(transactions);
        this.envPaystack = blank(paystackSecret) ? "" : paystackSecret.trim();
        this.envFlutterwave = blank(flutterwaveSecret) ? "" : flutterwaveSecret.trim();
        this.envFlutterwaveHash = blank(flutterwaveHash) ? "" : flutterwaveHash.trim();
        this.envQuickteller = blank(quicktellerConfig) ? "" : quicktellerConfig.trim();
        // the service variables, one per thing, assembled into the same JSON the dashboard stores
        if (!blank(qtMacKey)) {
            Map<String, Object> parts = new LinkedHashMap<>();
            parts.put("productId", qtProductId.trim());
            parts.put("payItemId", qtPayItemId.trim());
            parts.put("macKey", qtMacKey.trim());
            parts.put("sandbox", qtSandbox);
            if (!blank(qtChsMacKey)) {
                parts.put("chs", Map.of("productId", qtChsProductId.trim(), "payItemId", qtChsPayItemId.trim(), "macKey", qtChsMacKey.trim()));
            }
            this.envQuicktellerParts = mapper.writeValueAsString(parts);
        } else {
            this.envQuicktellerParts = "";
        }
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

    /* ── Quickteller on Interswitch WebPAY: two merchants, routed by the payer's College ── */

    /**
     * One WebPAY merchant: the product id Interswitch gave the University, the
     * pay item on it, and the MAC key that signs the payment form and the
     * requery. The key is a secret and lives in the encrypted slot (V052) or a
     * service variable — never in this repository.
     */
    record WebpayMerchant(String productId, String merchantCode, String payItemId, String macKey, String name) {
        /** the legacy WebPAY identity: product_id and a MAC-signed form; otherwise the current one, merchant_code */
        boolean legacy() {
            return merchantCode == null || merchantCode.isEmpty();
        }
    }

    /**
     * The University's set-up: the main merchant (product 6498, pay item 101),
     * the College of Health Sciences merchant when it has its own (product 6207),
     * and the mode. A payer whose programme's faculty is in College CHS pays the
     * College merchant; everyone else pays the University's.
     */
    record Quickteller(WebpayMerchant main, WebpayMerchant chs, boolean sandbox) {
        WebpayMerchant merchantFor(String college) {
            return "CHS".equals(college) && chs != null ? chs : main;
        }
    }

    static final String SCHOOL_NAME = "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI";
    static final String CHS_NAME = "College of Health Sciences, MOAU Makurdi";
    static final String SCHOOL_ABBR = "MOAUM";
    static final String NAIRA = "566";

    private String quicktellerConfigJson() {
        if (!configKey.isEmpty()) {
            String db = repo.gatewaySecret("quickteller", configKey);
            if (db != null && !db.isBlank()) {
                return db.trim();
            }
        }
        return envQuickteller.isEmpty() ? envQuicktellerParts : envQuickteller;
    }

    /** the merchant described by a JSON object — productId, payItemId, macKey — or null when any is missing */
    private static WebpayMerchant merchant(Object o, String name) {
        if (!(o instanceof Map<?, ?> m)) {
            return null;
        }
        String productId = str(m.get("productId"));
        String merchantCode = str(m.get("merchantCode"));
        String payItemId = str(m.get("payItemId"));
        String macKey = str(m.get("macKey"));
        // a merchant is known by its merchant code (current WebPAY), or by its product id with the MAC key that signs the form (legacy WebPAY)
        if (payItemId.isEmpty() || (merchantCode.isEmpty() && (productId.isEmpty() || macKey.isEmpty()))) {
            return null;
        }
        return new WebpayMerchant(productId, merchantCode, payItemId, macKey, name);
    }

    Quickteller quickteller() {
        String json = quicktellerConfigJson();
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            Map<String, Object> m = mapper.readValue(json, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
            WebpayMerchant main = merchant(m, SCHOOL_NAME);
            if (main == null) {
                return null;
            }
            boolean sandbox = Boolean.parseBoolean(str(m.getOrDefault("sandbox", "false")));
            return new Quickteller(main, merchant(m.get("chs"), CHS_NAME), sandbox);
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

    /** which gateways are wired, for the button to say so */
    public Map<String, Object> gateways() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("paystack", paystackOn());
        m.put("flutterwave", flutterwaveOn());
        m.put("quickteller", quicktellerOn());
        return m;
    }

    /* ── checkout ── */

    public Map<String, Object> checkout(UUID account, String reference, String gateway) {
        /* an applicant's fee reference, or a student's (V026): the account is the applicant's account or the student's own id */
        PaymentsRepository.Reference r = repo.byReference(reference)
                .or(() -> repo.studentReference(reference))
                .or(() -> repo.pgReference(reference))
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
        String back = portalUrl + backPath(r.kind()) + "?paid=" + r.reference();
        /* the card gateways open a checkout on an email address; a record without one (a migrated student
           who never gave a contact) cannot be sent to them — say so, rather than fail inside the request */
        if (("paystack".equals(g) || "flutterwave".equals(g)) && (r.email() == null || r.email().isBlank())) {
            throw new DomainRuleViolation("PAY_NO_EMAIL", "A card checkout needs an email address on your record, and none is recorded.",
                    new DomainRuleViolation.Remedy("Add your email under Contact and try again, or pay by Quickteller, by bank transfer, or at a branch against the reference.", "You"));
        }
        String url;
        if ("paystack".equals(g) && paystackOn()) {
            url = paystackInitialize(r, back);
        } else if ("flutterwave".equals(g) && flutterwaveOn()) {
            url = flutterwaveInitialize(r, back);
        } else if ("quickteller".equals(g) && quicktellerOn()) {
            // Quickteller's page is reached by a form POST, so the browser is sent to
            // this portal's own /quickteller/start, which renders the self-posting form.
            url = quicktellerStartUrl(r.reference());
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
                "metadata", Map.of("application", r.applicationNo() == null ? "" : r.applicationNo(), "kind", r.kind() == null ? "" : r.kind())));
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
                "customizations", Map.of("title", "MOAUM " + feeName(r.kind()))));
        Map<String, Object> answer = post("https://api.flutterwave.com/v3/payments", body, "Bearer " + flutterwaveSecret());
        Object data = answer.get("data");
        if (!(data instanceof Map<?, ?> d) || d.get("link") == null) {
            throw new DomainRuleViolation("PAY_GATEWAY_REFUSED", "The payment gateway did not open a checkout: " + answer.getOrDefault("message", "no answer"),
                    new DomainRuleViolation.Remedy("Try again in a moment, or pay by transfer against the reference.", "Bursary"));
        }
        return String.valueOf(d.get("link"));
    }

    /* ── Quickteller WebPAY: the hosted page is reached by a self-posting form; the payer returns by a POST ── */

    private String apiBase() {
        // the browser (and Interswitch) reach the API on its own public URL if it is
        // set, else through the portal's BFF, which forwards /api to the API
        return apiUrl.isEmpty() ? portalUrl + "/api/bff" : apiUrl;
    }

    private String quicktellerStartUrl(String reference) {
        return apiBase() + "/api/v1/payments/quickteller/start?reference=" + reference;
    }

    /** where WebPAY sends the payer back: this portal's own return door, the reference named so nothing depends on what the gateway posts */
    private String quicktellerReturnUrl(String reference) {
        return apiBase() + "/api/v1/payments/quickteller/return?reference=" + reference;
    }

    private static String quicktellerPayEndpoint(boolean sandbox) {
        return sandbox ? "https://sandbox.interswitchng.com/collections/w/pay"
                : "https://webpay.interswitchng.com/collections/w/pay";
    }

    private static String quicktellerRequeryEndpoint(boolean sandbox) {
        return sandbox ? "https://sandbox.interswitchng.com/collections/api/v1/gettransaction.json"
                : "https://webpay.interswitchng.com/collections/api/v1/gettransaction.json";
    }

    /** the fee named as the gateway shows it to the payer, by the reference's kind */
    static String feeName(String kind) {
        return switch (kind == null ? "" : kind) {
            case "FEES" -> "school fees";
            case "ACCEPTANCE", "PG_ACCEPTANCE" -> "acceptance fee";
            case "CHECKING" -> "admission checking fee";
            case "PG_CHECKING" -> "postgraduate checking fee";
            case "PG_APPLICATION" -> "postgraduate application fee";
            default -> "application fee";
        };
    }

    /** where the gateway returns the payer after this kind of fee: the page that shows it paid */
    private static String backPath(String kind) {
        return switch (kind) {
            case "FEES" -> "/student/fees";
            case "ACCEPTANCE" -> "/applicant/accept";
            case "CHECKING" -> "/applicant/admission";
            case "PG_APPLICATION", "PG_CHECKING", "PG_ACCEPTANCE" -> "/pg/portal";
            default -> "/applicant/fee";
        };
    }

    private String backUrl(String kind, String reference) {
        return portalUrl + backPath(kind) + "?paid=" + reference;
    }

    /** a reference wherever it lives: an applicant's fee, a student's fee, a postgraduate applicant's fee */
    private PaymentsRepository.Reference anyReference(String reference) {
        return repo.byReference(reference).or(() -> repo.studentReference(reference)).or(() -> repo.pgReference(reference)).orElse(null);
    }

    /** the merchant a reference is paid to: the College of Health Sciences' own when the payer's programme is in that College */
    WebpayMerchant merchantFor(Quickteller q, String reference) {
        return q.merchantFor(repo.collegeOfReference(reference));
    }

    /** WebPAY's form hash: SHA-512 of txn_ref + product_id + pay_item_id + amount + site_redirect_url + MAC key, upper-case hex */
    public static String webpayHash(String txnRef, String productId, String payItemId, long kobo, String redirect, String macKey) {
        return sha512Hex(txnRef + productId + payItemId + kobo + redirect + macKey).toUpperCase();
    }

    /**
     * The self-submitting form that carries the payment to Interswitch's hosted
     * page. WebPAY refuses a transaction reference it has already seen, so each
     * visit is its own attempt with its own txn_ref — the fee reference the first
     * time, then the reference with -A2, -A3 … — remembered on the attempt row so
     * the requery and the return find the payment whichever attempt paid.
     */
    public String quicktellerStartPage(String referenceIn) {
        String reference = referenceIn == null ? "" : referenceIn.trim().toUpperCase();
        Quickteller q = quickteller();
        PaymentsRepository.Reference r = anyReference(reference);
        if (q == null || r == null) {
            return notice("This payment could not be started", "The reference is not one this portal is waiting on, or Quickteller is not configured.");
        }
        if (r.confirmedAt() != null) {
            return notice("Already paid", "This reference is already confirmed as paid; nothing more is owed against it.");
        }
        if (r.expiresAt() != null && r.expiresAt().isBefore(OffsetDateTime.now())) {
            return notice("This reference has expired", "Generate a new one on the portal; it is free of charge.");
        }
        WebpayMerchant m = merchantFor(q, r.reference());
        long kobo = r.amount().movePointRight(2).longValueExact();
        int attempts = repo.quicktellerAttempts(r.reference()).size();
        String txnRef = attempts == 0 ? r.reference() : r.reference() + "-A" + (attempts + 1);
        String action = quicktellerPayEndpoint(q.sandbox());
        String back = quicktellerReturnUrl(r.reference());
        String hash = m.legacy() ? webpayHash(txnRef, m.productId(), m.payItemId(), kobo, back, m.macKey()) : null;
        AuditContextHolder.with(new AuditContext(r.accountId(), "bursar", "Quickteller attempt " + txnRef, null, null),
                () -> tx.execute(st -> { repo.quicktellerAttempt(r.reference(), txnRef, r.kind(), r.accountId()); return null; }));
        StringBuilder f = new StringBuilder();
        f.append("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">")
                .append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
                .append("<title>Opening Quickteller…</title></head>")
                .append("<body style=\"font:15px/1.5 system-ui,Segoe UI,Arial,sans-serif;color:#1c1c1c;margin:0;padding:48px 20px;text-align:center\">")
                .append("<p>Opening the secure Interswitch payment page for <strong>").append(esc(r.reference())).append("</strong> — ")
                .append(esc(m.name())).append("…</p>")
                .append("<p style=\"color:#666\">If it does not open in a moment, press the button.</p>")
                .append("<form id=\"qt\" method=\"POST\" action=\"").append(esc(action)).append("\">");
        if (m.legacy()) {
            field(f, "product_id", m.productId());
        } else {
            field(f, "merchant_code", m.merchantCode());
        }
        field(f, "pay_item_id", m.payItemId());
        field(f, "pay_item_name", SCHOOL_ABBR + " " + feeName(r.kind()));
        field(f, "amount", Long.toString(kobo));
        field(f, "currency", NAIRA);
        field(f, "site_redirect_url", back);
        field(f, "site_name", portalUrl.replaceFirst("^https?://", ""));
        field(f, "txn_ref", txnRef);
        field(f, "cust_id", r.applicationNo() == null ? r.reference() : r.applicationNo());
        field(f, "cust_id_desc", "FEES".equals(r.kind()) ? "Matriculation number" : "Application number");
        field(f, "cust_name", r.applicationNo() == null ? r.reference() : r.applicationNo());
        if (hash != null) {
            field(f, "hash", hash);
        }
        f.append("<button type=\"submit\" style=\"font:inherit;padding:10px 18px;border:0;border-radius:8px;background:#0a7d3f;color:#fff;cursor:pointer\">Pay with Quickteller</button>")
                .append("</form><script>document.getElementById('qt').submit();</script></body></html>");
        return f.toString();
    }

    /**
     * WebPAY sends the payer back here by a POST (txnref, resp, desc, payRef,
     * apprAmt …). None of it is believed: the reference is requeried and settled
     * on Interswitch's answer, then the payer is returned to the page that shows
     * the fee — by a page that redirects itself, so the return works whether
     * Interswitch reached the API directly or through the portal's BFF.
     */
    public String quicktellerReturned(String referenceParam, Map<String, String> posted) {
        String txnRef = str(posted.getOrDefault("txnref", posted.getOrDefault("txn_ref", "")));
        String reference = str(referenceParam);
        if (reference.isEmpty() && !txnRef.isEmpty()) {
            reference = repo.referenceOfTxnRef(txnRef).orElse(txnRef.replaceFirst("-A\\d+$", ""));
        }
        reference = reference.toUpperCase();
        PaymentsRepository.Reference r = reference.isEmpty() ? null : anyReference(reference);
        if (r == null) {
            log("quickteller", "RETURN", "return", reference.isEmpty() ? null : reference, txnRef.isEmpty() ? null : txnRef, null,
                    str(posted.get("resp")), true, "UNKNOWN_REFERENCE", safeJson(posted));
            return notice("This payment could not be matched", "The gateway returned a reference this portal is not waiting on. Nothing has been charged against your record; contact the Bursary with your payment reference.");
        }
        String resp = str(posted.get("resp"));
        String desc = str(posted.get("desc"));
        log("quickteller", "RETURN", "return", r.reference(), txnRef.isEmpty() ? null : txnRef,
                posted.get("apprAmt") == null || str(posted.get("apprAmt")).isEmpty() ? null : new BigDecimal(str(posted.get("apprAmt"))).movePointLeft(2),
                resp.isEmpty() ? null : resp, true, "00".equals(resp) ? "IGNORED" : "NOT_SUCCESSFUL", safeJson(posted));
        Map<String, Object> outcome;
        try {
            outcome = verify(r.reference(), "RETURN");
        } catch (RuntimeException e) {
            LOG.warn("payments: the Quickteller return for {} could not be verified: {}", r.reference(), e.getMessage());
            outcome = Map.of("outcome", "could not verify");
        }
        String said = String.valueOf(outcome.getOrDefault("outcome", ""));
        boolean paid = r.confirmedAt() != null || "SETTLED".equals(said) || "already confirmed".equals(said) || "ALREADY_SETTLED".equals(said);
        String back = backUrl(r.kind(), r.reference()) + (paid ? "" : "&outcome=" + enc(resp.isEmpty() ? "pending" : resp + " " + desc));
        String title = paid ? "Payment received" : "Payment not confirmed";
        String body = paid ? "Your " + feeName(r.kind()) + " against " + r.reference() + " is confirmed. Returning you to the portal…"
                : "Interswitch answered " + (resp.isEmpty() ? "nothing yet" : resp + (desc.isEmpty() ? "" : " — " + desc)) + " for " + r.reference()
                + ". If you were debited, the portal re-checks the reference every ten minutes and confirms it when Interswitch does. Returning you to the portal…";
        return "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                + "<meta http-equiv=\"refresh\" content=\"2;url=" + esc(back) + "\"><title>" + esc(title) + "</title></head>"
                + "<body style=\"font:15px/1.5 system-ui,Segoe UI,Arial,sans-serif;color:#1c1c1c;margin:0;padding:48px 20px;text-align:center\"><h1 style=\"font-size:18px\">"
                + esc(title) + "</h1><p style=\"color:#555\">" + esc(body) + "</p><p><a href=\"" + esc(back) + "\">Continue</a></p>"
                + "<script>setTimeout(function(){location.replace(" + mapper.writeValueAsString(back) + ")},1200);</script></body></html>";
    }

    private String safeJson(Map<String, String> posted) {
        try {
            Map<String, String> copy = new LinkedHashMap<>();
            posted.forEach((k, v) -> { if (!"cardNum".equalsIgnoreCase(k)) copy.put(k, v != null && v.length() > 500 ? v.substring(0, 500) : v); });
            return mapper.writeValueAsString(copy);
        } catch (RuntimeException e) {
            return null;
        }
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
            log("quickteller", "WEBHOOK", null, null, null, null, null, true, "IGNORED", body != null && body.length() < 20000 ? body : null);
            return Map.of("outcome", "ignored");
        }
        // the notification may name an attempt's txn_ref rather than the fee reference
        final String named = reference.trim();
        reference = repo.referenceOfTxnRef(named).orElse(named.replaceFirst("-A\\d+$", ""));
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
        PaymentsRepository.Reference r = repo.byReference(reference).or(() -> repo.studentReference(reference)).or(() -> repo.pgReference(reference)).orElse(null);
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
            String channel = "Card · " + (gateway.equals("paystack") ? "Paystack" : gateway.equals("quickteller") ? "Quickteller" : "Flutterwave");
            String note = gateway + " " + providerRef + " · " + paid.toPlainString();
            String settled = AuditContextHolder.with(new AuditContext(NOBODY, "bursar", gateway + " " + source.toLowerCase() + " " + providerRef, null, null),
                    () -> tx.execute(st -> switch (r.kind()) {
                        case "FEES" -> repo.confirmStudent(reference, channel, note);
                        case "PG_APPLICATION", "PG_CHECKING", "PG_ACCEPTANCE" -> repo.confirmPg(reference, channel);
                        default -> repo.confirm(reference, channel, note);
                    }));
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
        PaymentsRepository.Reference r = repo.byReference(reference).or(() -> repo.studentReference(reference)).or(() -> repo.pgReference(reference))
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
            WebpayMerchant m = merchantFor(q, reference);
            // WebPAY requery: GET gettransaction.json?productid&transactionreference&amount with
            // header Hash = SHA-512(product_id + txn_ref + MAC key). Every attempt's txn_ref is
            // asked, newest first, then the bare reference; the first settled one wins.
            java.util.List<String> txnRefs = new java.util.ArrayList<>(repo.quicktellerAttempts(reference));
            java.util.Collections.reverse(txnRefs);
            if (!txnRefs.contains(reference)) {
                txnRefs.add(reference);
            }
            Map<String, Object> last = Map.of();
            for (String txnRef : txnRefs) {
                String url = quicktellerRequeryEndpoint(q.sandbox()) + (m.legacy() ? "?productid=" + enc(m.productId()) : "?merchantcode=" + enc(m.merchantCode()))
                        + "&transactionreference=" + enc(txnRef) + "&amount=" + kobo;
                Map<String, Object> a = getWith(url, m.legacy()
                        ? Map.of("Hash", sha512Hex(m.productId() + txnRef + m.macKey()).toUpperCase(), "Accept", "application/json")
                        : Map.of("Accept", "application/json"));
                last = a;
                Object rc = a.get("ResponseCode");
                if (rc == null) {
                    continue;
                }
                boolean success = "00".equals(String.valueOf(rc));
                BigDecimal paid = a.get("Amount") == null ? BigDecimal.ZERO : new BigDecimal(String.valueOf(a.get("Amount"))).movePointLeft(2);
                String providerRef = a.get("PaymentReference") != null ? String.valueOf(a.get("PaymentReference"))
                        : a.get("RetrievalReferenceNumber") != null ? String.valueOf(a.get("RetrievalReferenceNumber")) : txnRef;
                out = settle("quickteller", source, "verify", reference, paid, String.valueOf(rc), success, providerRef, mapper.writeValueAsString(a));
                if (success) {
                    AuditContextHolder.with(new AuditContext(NOBODY, "bursar", "reconciler checked " + reference, null, null), () -> tx.execute(st -> { repo.checked(reference); return null; }));
                    return out;
                }
            }
            if (last.get("ResponseCode") == null) {
                log("quickteller", source, "verify", reference, null, null, String.valueOf(last.getOrDefault("ResponseDescription", "no answer")), true, "GATEWAY_ERROR", mapper.writeValueAsString(last));
                if ("no gateway".equals(out.get("outcome"))) {
                    out = Map.of("outcome", "not found at the gateway", "reference", reference, "gateway", "quickteller", "said", String.valueOf(last.getOrDefault("ResponseDescription", "")));
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
        if (!paystackOn() && !flutterwaveOn() && !quicktellerOn()) {
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
                quicktellerListing()));
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

    private static Map<String, Object> merchantRow(String scope, WebpayMerchant m) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("scope", scope);
        row.put("productId", m.productId());
        row.put("merchantCode", m.merchantCode());
        row.put("payItemId", m.payItemId());
        row.put("identity", m.legacy() ? "product id (legacy WebPAY)" : "merchant code (WebPAY)");
        row.put("name", m.name());
        return row;
    }

    /** the Quickteller row of the Bursary's listing: on, the mode, and which merchants are wired — never a key */
    private Map<String, Object> quicktellerListing() {
        Quickteller q = quickteller();
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("gateway", "quickteller");
        row.put("on", q != null);
        row.put("mode", q == null ? "OFF" : q.sandbox() ? "TEST" : "LIVE");
        row.put("webhook", "/api/v1/payments/webhook/quickteller");
        row.put("return", "/api/v1/payments/quickteller/return");
        row.put("channels", "Card · bank transfer · USSD · Quickteller (Interswitch WebPAY)");
        row.put("merchants", q == null ? java.util.List.of() : q.chs() == null
                ? java.util.List.of(merchantRow("MAIN", q.main()))
                : java.util.List.of(merchantRow("MAIN", q.main()), merchantRow("CHS", q.chs())));
        return row;
    }

    public java.util.List<java.util.Map<String, Object>> gatewayConfig() {
        // PayDirect is no longer offered (its rows may remain from V080): the card gateways only
        return repo.gatewayConfig().stream().filter(r -> !"paydirect".equals(r.get("gateway"))).toList();
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
            // Quickteller's "secret" is the whole WebPAY configuration as one JSON document;
            // validate it, derive the mode from its sandbox flag and the last four from the
            // main merchant's MAC key — the key itself is stored encrypted and never shown
            try {
                Map<String, Object> m = mapper.readValue(s, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
                WebpayMerchant main = merchant(m, SCHOOL_NAME);
                if (main == null) {
                    throw new DomainRuleViolation("PAY_QT_INCOMPLETE", "The Quickteller configuration needs the University's WebPAY merchant: its merchant code and pay item id, or its product id, pay item id and MAC key.",
                            new DomainRuleViolation.Remedy("Paste them from the Interswitch merchant profile, with sandbox true for test; the College of Health Sciences merchant is optional.", "Directorate of ICT"));
                }
                if (m.get("chs") != null && merchant(m.get("chs"), CHS_NAME) == null) {
                    throw new DomainRuleViolation("PAY_QT_CHS_INCOMPLETE", "The College of Health Sciences merchant needs its merchant code and pay item id, or its product id, pay item id and MAC key — or leave it out.",
                            new DomainRuleViolation.Remedy("Fill the College's fields or clear them.", "Directorate of ICT"));
                }
                if (!main.macKey().isEmpty() && !main.macKey().matches("[0-9A-Fa-f]{32,256}")) {
                    throw new DomainRuleViolation("PAY_QT_MAC", "The MAC key is a hexadecimal string from Interswitch; this is not one.",
                            new DomainRuleViolation.Remedy("Copy the MAC key exactly as the merchant profile shows it.", "Directorate of ICT"));
                }
                mode = Boolean.parseBoolean(str(m.getOrDefault("sandbox", "false"))) ? "TEST" : "LIVE";
                String tail = main.macKey().isEmpty() ? main.merchantCode() : main.macKey();
                last4 = (tail.length() > 4 ? tail.substring(tail.length() - 4) : tail).toUpperCase();
            } catch (DomainRuleViolation d) {
                throw d;
            } catch (RuntimeException notJson) {
                throw new DomainRuleViolation("PAY_QT_JSON", "The Quickteller configuration must be a JSON object with productId, payItemId, macKey, sandbox and an optional chs merchant.",
                        new DomainRuleViolation.Remedy("The Gateways screen builds it for you from the fields; paste them there.", "Directorate of ICT"));
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
