package ng.edu.moaum.portal.platform;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.mail.MailAuthenticationException;
import org.springframework.mail.MailSendException;

/**
 * V532: an SMTP failure read as Microsoft 365 words it — the account's or the server's failure (the same for every message,
 * so e-mail stops for the batch and the messages are not charged an attempt) apart from one recipient's.
 */
class SmtpFailureTest {

    private static MailSendException refused(String serverWords) {
        return new MailSendException(Map.of(new Object(), new jakarta.mail.MessagingException(serverWords)));
    }

    @Test
    void theAccountsAndTheServersFailuresStopTheBatch() {
        // 17 Oct 2026, the live portal: Microsoft's inbound host on 587 never answers
        MailSendException timeout = new MailSendException("Mail server connection failed",
                new jakarta.mail.MessagingException("Couldn't connect to host, port: smtp.mail.outlook.com, 587; timeout 15000",
                        new SocketTimeoutException("Connect timed out")));
        assertThat(SmtpFailure.of(timeout)).isEqualTo(SmtpFailure.Kind.UNREACHABLE);
        assertThat(SmtpFailure.of(new MailSendException("x", new UnknownHostException("smtp.offce365.com")))).isEqualTo(SmtpFailure.Kind.HOST_UNKNOWN);
        assertThat(SmtpFailure.of(new MailAuthenticationException("535 5.7.139 Authentication unsuccessful, SmtpClientAuthentication is disabled for the Mailbox")))
                .isEqualTo(SmtpFailure.Kind.SIGN_IN);
        assertThat(SmtpFailure.of(refused("550 5.7.30 Basic authentication is not supported for Client Submission"))).isEqualTo(SmtpFailure.Kind.BASIC_AUTH_OFF);
        assertThat(SmtpFailure.of(refused("554 5.2.252 SendAsDenied; moaum@bsum.edu.ng not allowed to send as notifications@moaum.edu.ng; "
                + "STOREDRV.Submission.Exception:SendAsDeniedException.MapiExceptionSendAsDenied"))).isEqualTo(SmtpFailure.Kind.SEND_AS);
        assertThat(SmtpFailure.of(refused("554 5.2.0 STOREDRV.Submission.Exception:OutboundSpamException; WASCL UserAction verdict is not None"))).isEqualTo(SmtpFailure.Kind.BLOCKED);
        assertThat(SmtpFailure.of(refused("554 5.2.0 STOREDRV.Submission.Exception:SubmissionQuotaExceededException"))).isEqualTo(SmtpFailure.Kind.LIMIT);
        assertThat(SmtpFailure.of(refused("432 4.3.2 STOREDRV.ClientSubmit; sender thread limit exceeded"))).isEqualTo(SmtpFailure.Kind.LIMIT);
        assertThat(SmtpFailure.of(refused("554 5.6.0 STOREDRV.Submission.Exception:InvalidLicenseException"))).isEqualTo(SmtpFailure.Kind.SUBMISSION);
        for (SmtpFailure.Kind k : new SmtpFailure.Kind[] {SmtpFailure.Kind.UNREACHABLE, SmtpFailure.Kind.SIGN_IN, SmtpFailure.Kind.SEND_AS,
                SmtpFailure.Kind.BLOCKED, SmtpFailure.Kind.LIMIT, SmtpFailure.Kind.SUBMISSION, SmtpFailure.Kind.BASIC_AUTH_OFF}) {
            assertThat(SmtpFailure.systemic(k)).as(k.name()).isTrue();
        }
    }

    @Test
    void aRecipientsRefusalIsTheMessagesOwn() {
        assertThat(SmtpFailure.of(refused("550 5.1.1 RESOLVER.ADR.RecipNotFound; not found"))).isEqualTo(SmtpFailure.Kind.RECIPIENT);
        assertThat(SmtpFailure.systemic(SmtpFailure.Kind.RECIPIENT)).isFalse();
        assertThat(SmtpFailure.systemic(SmtpFailure.Kind.OTHER)).isFalse();
    }

    @Test
    void theWordsSayWhatToDo() {
        assertThat(SmtpFailure.words(SmtpFailure.Kind.UNREACHABLE, "smtp.mail.outlook.com", 587, "x")).contains("smtp.office365.com", "587");
        assertThat(SmtpFailure.words(SmtpFailure.Kind.SEND_AS, "smtp.office365.com", 587, "notifications@moaum.edu.ng"))
                .contains("notifications@moaum.edu.ng", "From address");
        assertThat(SmtpFailure.stage(SmtpFailure.Kind.UNREACHABLE)).isEqualTo("CONNECTION");
        assertThat(SmtpFailure.stage(SmtpFailure.Kind.SIGN_IN)).isEqualTo("SIGN_IN");
        assertThat(SmtpFailure.stage(SmtpFailure.Kind.SEND_AS)).isEqualTo("SEND");
        assertThat(SmtpFailure.detail(refused("554 5.2.252 SendAsDenied"))).contains("5.2.252 SendAsDenied").hasSizeLessThanOrEqualTo(400);
    }
}
