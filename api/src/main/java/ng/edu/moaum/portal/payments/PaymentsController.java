package ng.edu.moaum.portal.payments;

import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
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
    @PreAuthorize("hasAuthority('OFFICE_applicant')")
    Map<String, Object> checkout(Authentication authentication, @Valid @RequestBody Checkout body) {
        return payments.checkout(UUID.fromString(authentication.getName()), body.reference(), body.gateway());
    }

    @PostMapping("/webhook/paystack")
    ResponseEntity<Map<String, Object>> paystack(@RequestBody String body, @RequestHeader(value = "x-paystack-signature", required = false) String signature) {
        if (!payments.paystackSignatureValid(body, signature)) {
            return ResponseEntity.status(401).body(Map.of("outcome", "signature does not verify"));
        }
        return ResponseEntity.ok(payments.paystackEvent(body));
    }

    @PostMapping("/webhook/flutterwave")
    ResponseEntity<Map<String, Object>> flutterwave(@RequestBody String body, @RequestHeader(value = "verif-hash", required = false) String hash) {
        if (!payments.flutterwaveHashValid(hash)) {
            return ResponseEntity.status(401).body(Map.of("outcome", "hash does not verify"));
        }
        return ResponseEntity.ok(payments.flutterwaveEvent(body));
    }
}
