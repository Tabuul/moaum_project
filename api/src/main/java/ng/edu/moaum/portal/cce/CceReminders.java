package ng.edu.moaum.portal.cce;

import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Each morning at half past ten (V418): a CCE applicant with a step still outstanding — the application fee, the form, what
 * the Centre asked for, the CCE admission checking fee, the acceptance fee — is reminded of the earliest one, by email (and SMS
 * where the Centre's rule says), at most once a day and only as often and as many times as that rule allows. Every reminder
 * is logged; the rules, who is due and "send now" are on the Centre's Admission Processing page.
 */
@Component
class CceReminders {

    private static final Logger LOG = LoggerFactory.getLogger(CceReminders.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final String portalUrl;

    CceReminders(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions,
                 @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    @Scheduled(cron = "0 30 10 * * *", zone = "Africa/Lagos")
    void run() {
        lock.runExclusively("cce-reminders", this::runNow);
    }

    void runNow() {
        try {
            String sent = AuditContextHolder.with(new AuditContext(NOBODY, "cce", "CCE reminders", null, null), () -> tx.execute(status ->
                    jdbc.sql("SELECT admissions.cce_send_reminders(now(), :p, 500, 'SCHEDULE')::text").param("p", portalUrl).query(String.class).single()));
            LOG.info("cce reminders: {}", sent);
        } catch (RuntimeException e) {
            LOG.warn("cce reminders did not run: {}", e.getMessage());
        }
    }

    /** the portal's address the reminders link to */
    String portalUrl() {
        return portalUrl;
    }
}
