package ng.edu.moaum.portal.platform;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

/**
 * V442: the mail and SMS providers watched. Every ten minutes the SMS account's balance is read from eBulkSMS (when an
 * eBulkSMS account is set), and the database judges each channel — failing, stuck, low on balance — from the dispatcher's
 * counts and the outbox, telling the Directorate of ICT once per episode on the channels that still work
 * (platform.watch_providers). One instance runs it at a time; the office may run it now from the Notifications screen.
 */
@Component
public class ProviderWatch {

    private static final Logger LOG = LoggerFactory.getLogger(ProviderWatch.class);
    static final UUID NOBODY = new UUID(0, 0);
    private static final Pattern NUMBER = Pattern.compile("-?[0-9]+(?:[.][0-9]+)?");

    private final JobLock lock;
    private final NoticeRepository notices;
    private final SmsService sms;
    private final EbulkSmsSender ebulkSms;
    private final TransactionTemplate tx;

    ProviderWatch(JobLock lock, NoticeRepository notices, SmsService sms, EbulkSmsSender ebulkSms, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.notices = notices;
        this.sms = sms;
        this.ebulkSms = ebulkSms;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(fixedDelayString = "${moaum.providers.watch-every-ms:600000}", initialDelayString = "${moaum.providers.watch-initial-ms:120000}")
    public void watch() {
        lock.runExclusively("provider-watch", () -> {
            try {
                Map<String, Object> r = check(new AuditContext(NOBODY, "ict", "provider watch", null, null));
                if (((Number) r.get("told")).intValue() > 0) {
                    LOG.warn("notices: a message provider needs attention; {} message(s) queued to the Directorate of ICT", r.get("told"));
                }
            } catch (RuntimeException e) {
                LOG.warn("notices: the provider watch did not run: {}", e.getMessage());
            }
        });
    }

    /** the balance read (when an eBulkSMS account is set) and the watch run, under the context given; what it found */
    public Map<String, Object> check(AuditContext ctx) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("balance", readBalance(ctx));
        Integer told = AuditContextHolder.with(ctx, () -> tx.execute(st -> notices.watchProviders()));
        out.put("told", told == null ? 0 : told);
        out.put("providers", notices.providerStatus());
        return out;
    }

    /** eBulkSMS's answer as it came, the number read from it when it is one; nothing when no eBulkSMS account is set */
    private String readBalance(AuditContext ctx) {
        java.util.Optional<SmsService.Creds> creds = sms.creds();
        if (creds.isEmpty()) {
            return null;
        }
        String raw;
        try {
            raw = ebulkSms.balance(creds.get());
        } catch (Exception e) {
            raw = "not read: " + e.getMessage();
        }
        BigDecimal value = null;
        Matcher m = NUMBER.matcher(raw == null ? "" : raw.trim());
        if (m.matches()) {
            value = new BigDecimal(m.group());
        }
        final String said = raw;
        final BigDecimal v = value;
        AuditContextHolder.with(ctx, () -> tx.execute(st -> {
            notices.recordSmsBalance(said, v);
            return null;
        }));
        return raw;
    }
}
