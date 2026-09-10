package ng.edu.moaum.portal.platform;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Takes what the outbox holds to a provider, once a minute. The provider is
 * whatever answers an HTTP POST of {@code {to, subject, body}} with a bearer
 * token — an SMS gateway, a mail relay, a function in front of either — named
 * by {@code MOAUM_NOTICES_EMAIL_URL} and {@code MOAUM_NOTICES_SMS_URL}. While
 * neither is set, nothing is sent and nothing is pretended: the notices stay
 * QUEUED, and the platform dashboard says so.
 */
@Component
public class NoticeDispatcher {

    private static final Logger LOG = LoggerFactory.getLogger(NoticeDispatcher.class);
    static final UUID NOBODY = new UUID(0, 0);

    private final NoticeRepository notices;
    private final TransactionTemplate tx;
    private final String emailUrl;
    private final String smsUrl;
    private final String token;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private boolean saidNoProvider;

    private final String smsFormat;
    private final String smsFrom;
    private final String emailFormat;
    private final String emailFrom;

    private final MailService mailService;
    private final SmtpMailer smtpMailer;
    private final SmsService smsService;
    private final EbulkSmsSender ebulkSms;

    public NoticeDispatcher(NoticeRepository notices, PlatformTransactionManager transactions,
                            MailService mailService, SmtpMailer smtpMailer,
                            SmsService smsService, EbulkSmsSender ebulkSms,
                            @Value("${moaum.notices.email-url:}") String emailUrl,
                            @Value("${moaum.notices.sms-url:}") String smsUrl,
                            @Value("${moaum.notices.token:}") String token,
                            @Value("${moaum.notices.sms-format:generic}") String smsFormat,
                            @Value("${moaum.notices.sms-from:MOAUM}") String smsFrom,
                            @Value("${moaum.notices.email-format:generic}") String emailFormat,
                            @Value("${moaum.notices.email-from:MOAUM Portal <portal@moaum.edu.ng>}") String emailFrom) {
        this.notices = notices;
        this.tx = new TransactionTemplate(transactions);
        this.mailService = mailService;
        this.smtpMailer = smtpMailer;
        this.smsService = smsService;
        this.ebulkSms = ebulkSms;
        this.emailUrl = emailUrl == null ? "" : emailUrl.trim();
        this.smsUrl = smsUrl == null ? "" : smsUrl.trim();
        this.token = token == null ? "" : token.trim();
        this.smsFormat = smsFormat == null ? "generic" : smsFormat.trim().toLowerCase();
        this.smsFrom = smsFrom == null ? "MOAUM" : smsFrom.trim();
        this.emailFormat = emailFormat == null ? "generic" : emailFormat.trim().toLowerCase();
        this.emailFrom = emailFrom == null ? "" : emailFrom.trim();
    }

    /** a Nigerian number in the international form Termii and its kind expect: 0803… → 234803… */
    static String international(String phone) {
        String d = phone == null ? "" : phone.replaceAll("[^0-9]", "");
        return d.length() == 11 && d.startsWith("0") ? "234" + d.substring(1) : d;
    }

    /** the body the provider expects, by format */
    String payload(NoticeRepository.Queued n) {
        boolean sms = "SMS".equals(n.channel());
        String format = sms ? smsFormat : emailFormat;
        return switch (format) {
            case "termii" -> "{\"api_key\":" + quote(token) + ",\"to\":" + quote(international(n.recipient())) + ",\"from\":" + quote(smsFrom)
                    + ",\"sms\":" + quote(n.body()) + ",\"type\":\"plain\",\"channel\":\"generic\"}";
            case "resend" -> "{\"from\":" + quote(emailFrom) + ",\"to\":[" + quote(n.recipient()) + "],\"subject\":" + quote(n.subject())
                    + ",\"text\":" + quote(n.body()) + "}";
            default -> json(n);
        };
    }

    public boolean emailConfigured() {
        return !emailUrl.isEmpty();
    }

    public boolean smsConfigured() {
        return !smsUrl.isEmpty();
    }

    @Scheduled(fixedDelayString = "${moaum.notices.every-ms:60000}", initialDelayString = "${moaum.notices.initial-ms:15000}")
    public void dispatch() {
        // the mail account set on the Mail server screen (V057) sends email over SMTP; an HTTP
        // relay (MOAUM_NOTICES_EMAIL_URL) is the fallback, and SMS still goes by the relay
        java.util.Optional<MailService.Smtp> smtp = mailService.smtp();
        java.util.Optional<SmsService.Creds> smsCreds = smsService.creds();
        boolean emailReady = smtp.isPresent() || emailConfigured();
        boolean smsReady = smsConfigured() || smsCreds.isPresent();
        if (!emailReady && !smsReady) {
            if (!saidNoProvider) {
                LOG.info("notices: no email account (Mail server screen), SMS account (SMS settings screen) or relay configured; the outbox holds them");
                saidNoProvider = true;
            }
            return;
        }
        saidNoProvider = false;
        List<NoticeRepository.Queued> batch = notices.queued(50);
        for (NoticeRepository.Queued n : batch) {
            boolean email = "EMAIL".equals(n.channel());
            String outcome = null;
            String error = null;
            if (email && smtp.isPresent()) {
                try {
                    smtpMailer.send(smtp.get(), n.recipient(), n.subject(), n.body());
                    outcome = "smtp " + smtp.get().host();
                } catch (Exception e) {
                    error = e.getClass().getSimpleName() + ": " + e.getMessage();
                }
            } else if (!email && smsCreds.isPresent()) {
                try {
                    outcome = ebulkSms.send(smsCreds.get(), n.recipient(), n.body());
                } catch (Exception e) {
                    error = e.getClass().getSimpleName() + ": " + e.getMessage();
                }
            } else {
                String url = email ? emailUrl : smsUrl;
                if (url.isEmpty()) {
                    continue;
                }
                try {
                    HttpRequest.Builder req = HttpRequest.newBuilder(URI.create(url))
                            .timeout(Duration.ofSeconds(20))
                            .header("Content-Type", "application/json")
                            .POST(HttpRequest.BodyPublishers.ofString(payload(n)));
                    if (!token.isEmpty()) {
                        req.header("Authorization", "Bearer " + token);
                    }
                    HttpResponse<String> r = http.send(req.build(), HttpResponse.BodyHandlers.ofString());
                    if (r.statusCode() >= 200 && r.statusCode() < 300) {
                        outcome = r.body() == null ? "" : r.body().substring(0, Math.min(r.body().length(), 200));
                    } else {
                        error = "provider answered " + r.statusCode() + ": " + (r.body() == null ? "" : r.body().substring(0, Math.min(r.body().length(), 300)));
                    }
                } catch (Exception e) {
                    error = e.getClass().getSimpleName() + ": " + e.getMessage();
                }
            }
            final String ref = outcome;
            final String err = error;
            AuditContextHolder.with(new AuditContext(NOBODY, "ict", "notice dispatch", null, null), () -> tx.execute(status -> {
                if (ref != null) {
                    notices.sent(n.id(), ref);
                } else {
                    notices.failed(n.id(), err, n.attempts() + 1 >= 5);
                }
                return null;
            }));
        }
    }

    static String json(NoticeRepository.Queued n) {
        return "{\"to\":" + quote(n.recipient()) + ",\"subject\":" + quote(n.subject()) + ",\"body\":" + quote(n.body())
                + ",\"channel\":" + quote(n.channel()) + ",\"id\":" + quote(n.id().toString()) + "}";
    }

    private static String quote(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (char c : (s == null ? "" : s).toCharArray()) {
            switch (c) {
                case '"' -> b.append("\\\"");
                case '\\' -> b.append("\\\\");
                case '\n' -> b.append("\\n");
                case '\r' -> b.append("\\r");
                case '\t' -> b.append("\\t");
                default -> {
                    if (c < 0x20) {
                        b.append(String.format("\\u%04x", (int) c));
                    } else {
                        b.append(c);
                    }
                }
            }
        }
        return b.append('"').toString();
    }
}
