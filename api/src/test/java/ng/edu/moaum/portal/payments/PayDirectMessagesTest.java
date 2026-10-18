package ng.edu.moaum.portal.payments;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * Interswitch asks a biller that takes both customer validation and payment notification for one address that accepts both
 * messages, posted raw as text/xml: the message itself says which it is. Told apart here by the root element, whatever its
 * case or namespace (through a SOAP envelope too), or by the one key of a JSON body; failing a name, a message carrying
 * payments is a notification and one carrying only a customer reference a validation. Anything else is neither.
 */
class PayDirectMessagesTest {

    private static PayDirectMessages.Kind kind(String body) {
        return PayDirectMessages.read(body).kind();
    }

    @Test
    void theRootElementSaysWhichMessageItIs() {
        assertThat(kind("<CustomerInformationRequest><ServiceUsername/><ServicePassword/><MerchantReference>6405</MerchantReference>"
                + "<CustReference>MOAUM-FEE-1</CustReference><PaymentItemCode>01</PaymentItemCode></CustomerInformationRequest>"))
                .isEqualTo(PayDirectMessages.Kind.CUSTOMER_VALIDATION);
        assertThat(kind("<?xml version=\"1.0\" encoding=\"utf-8\"?><PaymentNotificationRequest xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">"
                + "<ServiceUsername>u</ServiceUsername><ServicePassword>p</ServicePassword><Payments><Payment><PaymentLogId>1</PaymentLogId>"
                + "<CustReference>MOAUM-FEE-1</CustReference><Amount>100.00</Amount></Payment></Payments></PaymentNotificationRequest>"))
                .isEqualTo(PayDirectMessages.Kind.PAYMENT_NOTIFICATION);
        assertThat(kind("<customerinformationrequest><custreference>x</custreference></customerinformationrequest>"))
                .isEqualTo(PayDirectMessages.Kind.CUSTOMER_VALIDATION);
        assertThat(kind("<p:PaymentNotificationRequest xmlns:p=\"urn:x\"><p:Payments/></p:PaymentNotificationRequest>"))
                .isEqualTo(PayDirectMessages.Kind.PAYMENT_NOTIFICATION);
    }

    @Test
    void throughAnEnvelopeOrAsJson() {
        assertThat(kind("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><CustomerInformationRequest>"
                + "<CustReference>A</CustReference></CustomerInformationRequest></s:Body></s:Envelope>"))
                .isEqualTo(PayDirectMessages.Kind.CUSTOMER_VALIDATION);
        assertThat(kind("{\"PaymentNotificationRequest\": {\"ServiceUsername\": \"u\", \"Payments\": {\"Payment\": [{\"PaymentLogId\": \"1\"}]}}}"))
                .isEqualTo(PayDirectMessages.Kind.PAYMENT_NOTIFICATION);
        assertThat(kind("{\"CustomerInformationRequest\": {\"CustReference\": \"A\"}}")).isEqualTo(PayDirectMessages.Kind.CUSTOMER_VALIDATION);
    }

    @Test
    void withoutAName_whatItCarriesDecides() {
        assertThat(kind("<Request><Payments><Payment><PaymentLogId>9</PaymentLogId></Payment></Payments></Request>"))
                .isEqualTo(PayDirectMessages.Kind.PAYMENT_NOTIFICATION);
        assertThat(kind("<Request><CustReference>A</CustReference></Request>")).isEqualTo(PayDirectMessages.Kind.CUSTOMER_VALIDATION);
        assertThat(kind("<Hello><World/></Hello>")).isEqualTo(PayDirectMessages.Kind.UNKNOWN);
        assertThatThrownBy(() -> PayDirectMessages.read("not xml at all")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> PayDirectMessages.read("<!DOCTYPE x [<!ENTITY e SYSTEM \"file:///etc/passwd\">]><CustomerInformationRequest>&e;</CustomerInformationRequest>"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    /** Oct 2026: Interswitch's HTTP generic route sends the request in a SOAP envelope and reads the answer from one — a bare
     *  answer is logged on their side as E19; the answer goes back in the request's own envelope, prefix and namespace kept */
    @Test
    void anEnvelopedRequestIsAnsweredInItsEnvelope() {
        PayDirectMessages.Message m = PayDirectMessages.read("<ns3:Envelope xmlns:ns2=\"http://techquest.interswitchng.com/\" xmlns:ns3=\"http://schemas.xmlsoap.org/soap/envelope/\">"
                + "<ns3:Body><CustomerInformationRequest><ServiceUrl>https://portal.moaum.edu.ng/api/v1/payments/paydirect/interswitch</ServiceUrl>"
                + "<MerchantReference>6316</MerchantReference><CustReference>MOAUM-FEE-513120-5203</CustReference><Amount>0</Amount></CustomerInformationRequest></ns3:Body></ns3:Envelope>");
        assertThat(m.kind()).isEqualTo(PayDirectMessages.Kind.CUSTOMER_VALIDATION);
        assertThat(m.enveloped()).isTrue();
        assertThat(m.field("CustReference")).isEqualTo("MOAUM-FEE-513120-5203");
        String answer = PayDirectMessages.wrap(m, PayDirectMessages.customerAnswer(false, "6316", "", "MOAUM-FEE-513120-5203", true, "Ada", "OKAFOR", "MOAUM/SC/23/1234", new java.math.BigDecimal("100000")));
        assertThat(answer).startsWith("<?xml version=\"1.0\" encoding=\"utf-8\"?><ns3:Envelope xmlns:ns3=\"http://schemas.xmlsoap.org/soap/envelope/\"><ns3:Body><CustomerInformationResponse>");
        assertThat(answer).endsWith("</CustomerInformationResponse></ns3:Body></ns3:Envelope>");
        assertThat(answer).contains("<CustReference>MOAUM-FEE-513120-5203</CustReference>").contains("<MerchantReference>6316</MerchantReference>");
        assertThat(answer.indexOf("<?xml")).isEqualTo(0);
        assertThat(answer.indexOf("<?xml", 1)).isEqualTo(-1);
        // a bare request is answered bare, as before
        PayDirectMessages.Message bare = PayDirectMessages.read("<CustomerInformationRequest><CustReference>A</CustReference></CustomerInformationRequest>");
        assertThat(bare.enveloped()).isFalse();
        assertThat(PayDirectMessages.wrap(bare, "<x/>")).isEqualTo("<x/>");
    }

    /** Oct 2026: the first name Quickteller is told carries the payer's number at its end, so Interswitch's collections report (surname,
     *  then first name) reads "DAVID Terfa (MOAU/CS/BRO/24/72981)" */
    @Test
    void theFirstNameCarriesThePayersNumber() {
        assertThat(PaymentsService.withNumber("Terfa", "MOAU/CS/BRO/24/72981")).isEqualTo("Terfa (MOAU/CS/BRO/24/72981)");
        assertThat(PaymentsService.withNumber(" Terfa ", null)).isEqualTo("Terfa");
        assertThat(PaymentsService.withNumber("Terfa", "  ")).isEqualTo("Terfa");
        assertThat(PaymentsService.withNumber("", "MOAUM/ADM/25/1234")).isEqualTo("(MOAUM/ADM/25/1234)");
        assertThat(PaymentsService.withNumber("Terfa (MOAU/CS/BRO/24/72981)", "moau/cs/bro/24/72981")).isEqualTo("Terfa (MOAU/CS/BRO/24/72981)");
    }
}
