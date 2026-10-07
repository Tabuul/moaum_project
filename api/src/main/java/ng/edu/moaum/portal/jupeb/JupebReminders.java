package ng.edu.moaum.portal.jupeb;

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
 * Each morning at ten (V343): a JUPEB candidate with an unfinished step — the application fee, the submission, the passport
 * photograph, an open admission status check, the acceptance fee, the school fee — is reminded once, by email (and SMS where
 * the JUPEB Office's rule says), at most once a day and only as often and as many times as that rule allows. Every reminder
 * is logged; the rules, a preview and "send now" are on the JUPEB settings page.
 */
@Component
class JupebReminders {

    private static final Logger LOG = LoggerFactory.getLogger(JupebReminders.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final String portalUrl;

    JupebReminders(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions,
                   @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}") String portalUrl) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.portalUrl = portalUrl == null ? "" : portalUrl.replaceAll("/+$", "");
    }

    @Scheduled(cron = "0 0 10 * * *", zone = "Africa/Lagos")
    void run() {
        lock.runExclusively("jupeb-reminders", this::runNow);
    }

    void runNow() {
        try {
            String sent = AuditContextHolder.with(new AuditContext(NOBODY, "jupeb", "JUPEB reminders", null, null), () -> tx.execute(status ->
                    jdbc.sql("SELECT jupeb.send_reminders(now(), :p, 500, 'SCHEDULE')::text").param("p", portalUrl).query(String.class).single()));
            LOG.info("jupeb reminders: {}", sent);
            /* V355: the calendar's reminders — to the students, the JUPEB Office and the lecturers, each once */
            String calendar = AuditContextHolder.with(new AuditContext(NOBODY, "jupeb", "JUPEB calendar reminders", null, null), () -> tx.execute(status ->
                    jdbc.sql("SELECT jupeb.send_calendar_reminders(now(), :p)::text").param("p", portalUrl).query(String.class).single()));
            LOG.info("jupeb calendar reminders: {}", calendar);
        } catch (RuntimeException e) {
            LOG.warn("jupeb reminders did not run: {}", e.getMessage());
        }
    }
}
