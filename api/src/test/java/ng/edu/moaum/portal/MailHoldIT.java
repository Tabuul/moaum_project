package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import ng.edu.moaum.portal.platform.NoticeRepository;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V556: e-mail held after the mail server refused the portal — 5 minutes, then 10 — so the mailbox is not signed into every half
 * minute; ICT reads it on the Mail server screen and as the e-mail provider's FAILING state, in words; saving the settings tries
 * again at once. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class MailHoldIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    NoticeRepository notices;

    @Test
    void eMailIsHeldAfterTheServerRefusesTheSignInAndTriedAgainWhenTheSettingsAreSaved() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String ict = TestTokens.token(it.person(it.freeNumber("ZZ-HOLD-", 6), "ZZHOLDICT"), List.of("ict"));
        String words = "The server refused the sign-in: the username or password is wrong, or Authenticated SMTP is turned off for this mailbox in Microsoft 365.";
        try {
            OffsetDateTime first = it.db(() -> notices.smtpHold("SIGN_IN", words, "MailAuthenticationException: 535 5.7.139 Authentication unsuccessful"));
            OffsetDateTime second = it.db(() -> notices.smtpHold("SIGN_IN", words, "MailAuthenticationException: 535 5.7.139 Authentication unsuccessful"));
            assertThat(first).isAfter(OffsetDateTime.now().plusMinutes(4)).isBefore(OffsetDateTime.now().plusMinutes(6));
            assertThat(second).isAfter(OffsetDateTime.now().plusMinutes(9)).isBefore(OffsetDateTime.now().plusMinutes(11));
            assertThat(notices.smtpHeldUntil()).isEqualTo(second);

            // ICT reads it: the Mail server screen, and the e-mail provider failing, in words
            assertThat(it.get(ItSupport.token("bursar"), "/api/v1/platform/mail").getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> config = it.get(ict, "/api/v1/platform/mail");
            Map hold = (Map) config.getBody().get("hold");
            assertThat(hold).containsEntry("held", true).containsEntry("paused", true).containsEntry("failures", 2).containsEntry("kind", "SIGN_IN");
            assertThat((String) hold.get("words")).startsWith("The server refused the sign-in");
            Map email = it.db(() -> jdbc.sql("SELECT state, last_error FROM platform.provider_status() WHERE channel = 'EMAIL'").query().singleRow());
            if (!"OFF".equals(email.get("state"))) {
                assertThat(email).containsEntry("state", "FAILING");
                assertThat((String) email.get("last_error")).startsWith("The server refused the sign-in").contains("535 5.7.139");
            }

            // saving the settings tries again at once
            Map<String, Object> same = new HashMap<>();
            Map c = config.getBody();
            same.put("smtpHost", c.get("smtp_host"));
            same.put("smtpPort", c.get("smtp_port"));
            same.put("smtpEncryption", c.get("smtp_encryption"));
            same.put("username", c.get("username"));
            same.put("fromAddress", c.get("from_address"));
            ResponseEntity<Map> saved = it.call(ict, HttpMethod.PUT, "/api/v1/platform/mail", same);
            assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
            assertThat(notices.smtpHeldUntil()).isNull();
            assertThat((Map) it.get(ict, "/api/v1/platform/mail").getBody().get("hold")).containsEntry("held", false);
        } finally {
            it.db(notices::smtpResume);
        }
    }
}
