package ng.edu.moaum.portal.payments;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Checkout for the applicant, and the two webhooks the gateways call. A
 * webhook whose signature does not verify is refused before anything is
 * read from it; one that verifies is answered 200 whatever it says, and what
 * it settled is in the answer and on the record.
 */
@RestController
@RequestMapping("/api/v1/payments")
class PaymentsController {

    public record Checkout(@NotBlank String reference, String gateway) {
    }

    private final PaymentsService payments;

    PaymentsController(PaymentsService payments) {
        this.payments = payments;
    }

    /** which gateways are wired: the applicant's button says so */
    @GetMapping("/gateways")
    @PreAuthorize("isAuthenticated()")
    Map<String, Object> gateways() {
        return payments.gateways();
    }

    @PostMapping("/checkout")
    @PreAuthorize("hasAnyAuthority('OFFICE_applicant','OFFICE_student')")
    Map<String, Object> checkout(Authentication authentication, @Valid @RequestBody Checkout body) {
        return payments.checkout(UUID.fromString(authentication.getName()), body.reference(), body.gateway());
    }

    @PostMapping("/webhook/paystack")
    ResponseEntity<Map<String, Object>> paystack(@RequestBody String body, @RequestHeader(value = "x-paystack-signature", required = false) String signature) {
        if (!payments.paystackSignatureValid(body, signature)) {
            payments.refused("paystack", body);
            return ResponseEntity.status(401).body(Map.of("outcome", "signature does not verify"));
        }
        return ResponseEntity.ok(payments.paystackEvent(body));
    }

    @PostMapping("/webhook/flutterwave")
    ResponseEntity<Map<String, Object>> flutterwave(@RequestBody String body, @RequestHeader(value = "verif-hash", required = false) String hash) {
        if (!payments.flutterwaveHashValid(hash)) {
            payments.refused("flutterwave", body);
            return ResponseEntity.status(401).body(Map.of("outcome", "hash does not verify"));
        }
        return ResponseEntity.ok(payments.flutterwaveEvent(body));
    }

    /**
     * Quickteller's notification is only a hint: whatever it says, the portal
     * asks Interswitch's requery API what the reference actually settled for
     * and settles on that answer alone. So the notification is answered 200
     * and the reference it names is re-verified — nothing is credited on the
     * notification's word.
     */
    @PostMapping("/webhook/quickteller")
    ResponseEntity<Map<String, Object>> quickteller(@RequestBody(required = false) String body) {
        return ResponseEntity.ok(payments.quicktellerNotified(body));
    }

    /**
     * The Quickteller hosted page is reached by a form POST, not a link, so the
     * checkout hands the browser this endpoint; it renders the self-submitting
     * form that posts the payment to Interswitch. It reveals only what a payer
     * needs to pay a reference they already hold, so it is open like a webhook.
     */
    @GetMapping(value = "/quickteller/start", produces = "text/html;charset=UTF-8")
    ResponseEntity<String> quicktellerStart(@org.springframework.web.bind.annotation.RequestParam String reference) {
        return ResponseEntity.ok().body(payments.quicktellerStartPage(reference));
    }

    /* ── V037: the Bursary's side of the gateways ── */

    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_vc','OFFICE_dvc')";

    public record Verify(@NotBlank String reference) {
    }

    public record TestCheckout(@NotBlank String number, java.math.BigDecimal amount, String gateway) {
    }

    public record Resolution(@NotBlank String resolution) {
    }

    /** the gateway is asked what the reference settled for: the student's own, or any for an office */
    @PostMapping("/verify")
    @PreAuthorize("isAuthenticated()")
    Map<String, Object> verify(Authentication authentication, @Valid @RequestBody Verify body) {
        boolean office = authentication.getAuthorities().stream().anyMatch(a -> a.getAuthority().matches("OFFICE_(bursar|ict|admin|super|audit)"));
        return payments.verifyFor(UUID.fromString(authentication.getName()), office, body.reference());
    }

    @GetMapping("/bursary")
    @PreAuthorize(READERS)
    Map<String, Object> bursary() {
        return payments.bursary();
    }

    @PostMapping("/test-checkout")
    @PreAuthorize(BURSARY)
    Map<String, Object> testCheckout(@Valid @RequestBody TestCheckout body) {
        return payments.testCheckout(body.number(), body.amount(), body.gateway());
    }

    @PostMapping("/sweep")
    @PreAuthorize(BURSARY)
    Map<String, Object> sweep() {
        payments.sweep();
        return Map.of("swept", true);
    }

    @PostMapping("/events/{id}/resolve")
    @PreAuthorize(BURSARY)
    Map<String, Object> resolve(@PathVariable UUID id, @Valid @RequestBody Resolution body) {
        return payments.resolveEvent(id, body.resolution());
    }

    /* ── V039: keys set from the dashboard, encrypted, never read back ── */

    public record Key(@NotBlank String secret, String hash) {
    }

    @GetMapping("/gateway-config")
    @PreAuthorize(READERS)
    List<Map<String, Object>> gatewayConfig() {
        return payments.gatewayConfig();
    }

    @org.springframework.web.bind.annotation.PutMapping("/gateways/{gateway}/key")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')")
    Map<String, Object> setKey(@PathVariable String gateway, @Valid @RequestBody Key body) {
        return payments.setKey(gateway, body.secret(), body.hash());
    }

    @PostMapping("/gateways/{gateway}/clear-key")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')")
    Map<String, Object> clearKey(@PathVariable String gateway) {
        return payments.clearKey(gateway);
    }

    /* ── V080: Quickteller PayDirect billers, routing and the collections import ── */

    public record ImportRows(@jakarta.validation.constraints.NotNull List<Map<String, Object>> rows) {
    }

    public record BillerIn(@NotBlank String code, @NotBlank String name, String link, Boolean active) {
    }

    /** the billers, and the imported collections — the Bursary's PayDirect desk */
    @GetMapping("/paydirect")
    @PreAuthorize(READERS)
    Map<String, Object> paydirect() {
        return payments.paydirect();
    }

    /** import the Quickteller/PayDirect collections report: each PRN matched to its reference and confirmed */
    @PostMapping("/paydirect/import")
    @PreAuthorize(BURSARY)
    Map<String, Object> importPaydirect(@Valid @RequestBody ImportRows body) {
        return payments.importPaydirect(body.rows());
    }

    @org.springframework.web.bind.annotation.PutMapping("/paydirect/billers/{scope}")
    @PreAuthorize(BURSARY)
    Map<String, Object> setBiller(@PathVariable String scope, @Valid @RequestBody BillerIn body) {
        return payments.setPaydirectBiller(scope, body.code(), body.name(), body.link(), body.active());
    }
}
