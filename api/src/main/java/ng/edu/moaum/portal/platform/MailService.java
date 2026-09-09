package ng.edu.moaum.portal.platform;

import java.util.Map;
import java.util.Set;

import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The mail server settings (V057): the IMAP, POP and SMTP parameters of a mail
 * account — Microsoft 365 by default — set from a screen, the account password
 * encrypted at rest and never read back, the way a payment gateway key is.
 */
@Service
public class MailService {

    private static final Set<String> ENC = Set.of("STARTTLS", "SSL", "NONE");

    private final JdbcClient jdbc;
    private final String configKey;

    MailService(JdbcClient jdbc, @Value("${moaum.config.key:${moaum.auth.hmac-secret:}}") String configKey) {
        this.jdbc = jdbc;
        this.configKey = configKey == null ? "" : configKey.trim();
    }

    /** what a screen may see: the servers, the account, whether a password is set — never the password */
    @Transactional(readOnly = true)
    public Map<String, Object> config() {
        Map<String, Object> m = jdbc.sql("SELECT * FROM platform.mail_config()").query().singleRow();
        m.put("configKeyPresent", !configKey.isEmpty());
        return m;
    }

    public record Settings(@Size(max = 200) String smtpHost, Integer smtpPort, @Size(max = 12) String smtpEncryption,
                           @Size(max = 200) String imapHost, Integer imapPort, @Size(max = 12) String imapEncryption,
                           @Size(max = 200) String popHost, Integer popPort, @Size(max = 12) String popEncryption,
                           @Size(max = 320) String username, @Size(max = 320) String fromAddress, @Size(max = 400) String password) {
    }

    @Transactional
    public Map<String, Object> save(Settings s) {
        enc("SMTP", s.smtpEncryption());
        enc("IMAP", s.imapEncryption());
        enc("POP", s.popEncryption());
        if (s.password() != null && !s.password().isBlank() && configKey.isEmpty()) {
            throw new DomainRuleViolation("MAIL_NO_CONFIG_KEY", "The portal has no passphrase to encrypt the mail password with.",
                    new DomainRuleViolation.Remedy("Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service; the password is never stored in the clear.", "Directorate of ICT"));
        }
        jdbc.sql("SELECT platform.set_mail_settings(:sh, :sp, :se, :ih, :ip, :ie, :ph, :pp, :pe, :u, :f, :pw, :k)")
                .param("sh", blank(s.smtpHost())).param("sp", s.smtpPort(), java.sql.Types.INTEGER).param("se", up(s.smtpEncryption()))
                .param("ih", blank(s.imapHost())).param("ip", s.imapPort(), java.sql.Types.INTEGER).param("ie", up(s.imapEncryption()))
                .param("ph", blank(s.popHost())).param("pp", s.popPort(), java.sql.Types.INTEGER).param("pe", up(s.popEncryption()))
                .param("u", blank(s.username())).param("f", blank(s.fromAddress())).param("pw", blank(s.password()), java.sql.Types.VARCHAR)
                .param("k", configKey)
                .query().singleRow();
        return config();
    }

    @Transactional
    public Map<String, Object> clearPassword() {
        jdbc.sql("SELECT platform.clear_mail_password()").query().singleRow();
        return config();
    }

    private static void enc(String which, String value) {
        if (value != null && !value.isBlank() && !ENC.contains(value.trim().toUpperCase())) {
            throw new DomainRuleViolation("MAIL_ENCRYPTION", which + " encryption is STARTTLS, SSL or NONE.",
                    new DomainRuleViolation.Remedy("Microsoft 365 is STARTTLS for SMTP and SSL for IMAP/POP.", "Directorate of ICT"));
        }
    }

    private static String up(String s) {
        return s == null || s.isBlank() ? null : s.trim().toUpperCase();
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
