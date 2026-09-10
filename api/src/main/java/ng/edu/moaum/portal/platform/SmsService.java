package ng.edu.moaum.portal.platform;

import java.util.Map;

import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The SMS gateway settings (V065): an eBulkSMS account — username, sender ID and
 * API key — supplied on the dashboard, the key encrypted at rest and never read
 * back, the way the mail password and gateway keys are. When enabled and set,
 * SMS notices go out through eBulkSMS instead of the generic relay.
 */
@Service
public class SmsService {

    private final JdbcClient jdbc;
    private final String configKey;

    SmsService(JdbcClient jdbc, @Value("${moaum.config.key:${moaum.auth.hmac-secret:}}") String configKey) {
        this.jdbc = jdbc;
        this.configKey = configKey == null ? "" : configKey.trim();
    }

    /** what a screen may see: the account, sender, whether a key is set and whether it is enabled — never the key */
    @Transactional(readOnly = true)
    public Map<String, Object> config() {
        Map<String, Object> m = jdbc.sql("SELECT * FROM platform.sms_config()").query().singleRow();
        m.put("configKeyPresent", !configKey.isEmpty());
        return m;
    }

    public record Settings(@Size(max = 20) String provider, @Size(max = 120) String username,
                           @Size(max = 11) String sender, boolean enabled, @Size(max = 200) String apiKey) {
    }

    @Transactional
    public Map<String, Object> save(Settings s) {
        if (s.apiKey() != null && !s.apiKey().isBlank() && configKey.isEmpty()) {
            throw new DomainRuleViolation("SMS_NO_CONFIG_KEY", "The portal has no passphrase to encrypt the SMS API key with.",
                    new DomainRuleViolation.Remedy("Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service; the key is never stored in the clear.", "Directorate of ICT"));
        }
        jdbc.sql("SELECT platform.set_sms_settings(:pr, :u, :sn, :en, :ak, :k)")
                .param("pr", blank(s.provider())).param("u", blank(s.username())).param("sn", blank(s.sender()))
                .param("en", s.enabled()).param("ak", blank(s.apiKey()), java.sql.Types.VARCHAR).param("k", configKey)
                .query().singleRow();
        return config();
    }

    @Transactional
    public Map<String, Object> clearKey() {
        jdbc.sql("SELECT platform.clear_sms_api_key()").query().singleRow();
        return config();
    }

    /** the eBulkSMS credentials for the sender's own use — present only when enabled and fully set */
    public record Creds(String provider, String username, String sender, String apiKey) {
    }

    @Transactional(readOnly = true)
    public java.util.Optional<Creds> creds() {
        Map<String, Object> m = jdbc.sql("SELECT provider, username, sender, enabled FROM platform.sms_settings WHERE id = true")
                .query().listOfRows().stream().findFirst().orElse(null);
        if (m == null || configKey.isEmpty() || !Boolean.TRUE.equals(m.get("enabled"))) {
            return java.util.Optional.empty();
        }
        String username = str(m.get("username"));
        String sender = str(m.get("sender"));
        if (username.isEmpty() || sender.isEmpty()) {
            return java.util.Optional.empty();
        }
        String apiKey = jdbc.sql("SELECT platform.sms_api_key(:k)").param("k", configKey).query(String.class).optional().orElse(null);
        if (apiKey == null || apiKey.isBlank()) {
            return java.util.Optional.empty();
        }
        return java.util.Optional.of(new Creds(str(m.get("provider")), username, sender, apiKey));
    }

    private static String str(Object o) {
        return o == null ? "" : String.valueOf(o).trim();
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
