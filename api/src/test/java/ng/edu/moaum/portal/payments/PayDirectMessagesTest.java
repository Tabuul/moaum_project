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
}
