package ng.edu.moaum.portal.payments;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.Map;

import org.junit.jupiter.api.Test;

/**
 * WebPAY's requery answer names the card payment it confirms three ways: its payment reference, its Retrieval Reference Number and the
 * transaction reference the portal asked about. Interswitch's settlement report may list the payment by any one of them, so a
 * transfer applicant's reference keeps them all (V766, round 6: v5v-2). Round 5 kept the payment reference alone, and a settlement
 * row naming the transaction reference or the RRN was refused as another payment. What the requery is recorded under, for every kind
 * of reference, stays the rule it always was (round 7: v6v-4).
 */
class WebpayIdentifiersTest {

    private static final String TXN = "MOAUM-IUTAPP-2026-000001-A2";

    @Test
    void theRequeryKeepsThePaymentReferenceTheRrnAndTheTransactionReferenceAsked() {
        Map<String, Object> answer = Map.of("ResponseCode", "00", "Amount", "500000", "PaymentReference", "FBN|WEB|MX6072|16-11-2026|601",
                "RetrievalReferenceNumber", "631602000601");
        assertThat(PaymentsService.webpayIdentifiers(answer, TXN)).containsExactly("FBN|WEB|MX6072|16-11-2026|601", "631602000601", TXN);
    }

    @Test
    void anAnswerWithoutAPaymentReferenceKeepsTheRrnFirst() {
        Map<String, Object> answer = new HashMap<>(Map.of("ResponseCode", "00", "RetrievalReferenceNumber", "631602000602"));
        answer.put("PaymentReference", null);
        assertThat(PaymentsService.webpayIdentifiers(answer, TXN)).containsExactly("631602000602", TXN);
    }

    @Test
    void anAnswerNamingNeitherKeepsTheTransactionReferenceAsked() {
        assertThat(PaymentsService.webpayIdentifiers(Map.of("ResponseCode", "00"), TXN)).containsExactly(TXN);
    }

    /* round 7 (v6v-4): the identifier an answer is recorded under — the gateway event, the receipt's note, the ICT payment support
     * desk — is the rule as it always stood, for every kind: the payment reference whenever the answer carries one, blank included,
     * else the RRN, else the transaction reference asked. Round 6 took the first non-blank identifier instead, so an answer with a
     * blank payment reference recorded its RRN for a student's, a Post-UTME, a postgraduate, a JUPEB or a SIWES reference */
    @Test
    void theRequeryRecordsThePaymentReferenceEvenBlankThenTheRrnThenTheTransactionReference() {
        Map<String, Object> blank = new HashMap<>(Map.of("ResponseCode", "00", "PaymentReference", "", "RetrievalReferenceNumber", "631602000603"));
        assertThat(PaymentsService.webpayProviderRef(blank, TXN)).isEqualTo("");
        Map<String, Object> spaces = new HashMap<>(Map.of("ResponseCode", "00", "PaymentReference", "  ", "RetrievalReferenceNumber", "631602000604"));
        assertThat(PaymentsService.webpayProviderRef(spaces, TXN)).isEqualTo("  ");
        Map<String, Object> none = new HashMap<>(Map.of("ResponseCode", "00", "RetrievalReferenceNumber", "631602000605"));
        none.put("PaymentReference", null);
        assertThat(PaymentsService.webpayProviderRef(none, TXN)).isEqualTo("631602000605");
        Map<String, Object> blankRrn = new HashMap<>(Map.of("ResponseCode", "00", "RetrievalReferenceNumber", ""));
        assertThat(PaymentsService.webpayProviderRef(blankRrn, TXN)).isEqualTo("");
        assertThat(PaymentsService.webpayProviderRef(Map.of("ResponseCode", "00"), TXN)).isEqualTo(TXN);
        assertThat(PaymentsService.webpayProviderRef(Map.of("PaymentReference", "FBN|WEB|MX6072|16-11-2026|606", "RetrievalReferenceNumber", "631602000606"), TXN))
                .isEqualTo("FBN|WEB|MX6072|16-11-2026|606");
        // the identifiers a transfer applicant's reference keeps drop the blank one: never what the requery is recorded under
        assertThat(PaymentsService.webpayIdentifiers(blank, TXN).get(0)).isEqualTo("631602000603");
    }

    /* round 7 (v6v-4): only a transfer applicant's reference is given the list; every other kind's confirmation is called as before */
    @Test
    void onlyATransferApplicantsReferenceIsGivenEveryIdentifier() {
        Map<String, Object> answer = Map.of("ResponseCode", "00", "PaymentReference", "FBN|WEB|MX6072|16-11-2026|607", "RetrievalReferenceNumber", "631602000607");
        for (String kind : java.util.List.of("FEES", "APPLICATION", "CHECKING", "ACCEPTANCE", "PG_APPLICATION", "PG_CHECKING", "PG_ACCEPTANCE",
                "JUPEB_APPLICATION", "JUPEB_STATUS_CHECKING", "JUPEB_ACCEPTANCE", "JUPEB_SCHOOL_FIRST", "JUPEB_SCHOOL_SECOND", "JUPEB_SCHOOL_FULL")) {
            assertThat(PaymentsService.webpayGatewayRefs(kind, answer, TXN)).as(kind).isNull();
        }
        assertThat(PaymentsService.webpayGatewayRefs("IUT_APPLICATION", answer, TXN))
                .containsExactly("FBN|WEB|MX6072|16-11-2026|607", "631602000607", TXN);
    }

    @Test
    void eachIdentifierIsKeptOnceInOrderAndBlankOnesAreDropped() {
        assertThat(PaymentsService.identifiers(" 7661104 ", "", null, "7661104", "QT|WEB|7661104")).containsExactly("7661104", "QT|WEB|7661104");
        assertThat(PaymentsService.identifiers((Object) null)).isEmpty();
    }
}
