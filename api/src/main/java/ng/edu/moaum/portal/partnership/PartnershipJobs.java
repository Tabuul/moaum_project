package ng.edu.moaum.portal.partnership;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

/**
 * V658's daily round, once a day on one API task (JobLock): the executed agreements nearing or past their expiry told to their
 * owner and the Linkages office (each told once a threshold; an expired one marked so — never renewed), and the public drafts left
 * past their time removed with their files.
 */
@Component
class PartnershipJobs {

    private static final Logger LOG = LoggerFactory.getLogger(PartnershipJobs.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    PartnershipJobs(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "0 20 6 * * *", zone = "Africa/Lagos")
    void daily() {
        lock.runExclusively("partnership-daily", this::runNow);
    }

    void runNow() {
        try {
            Integer told = AuditContextHolder.with(new AuditContext(NOBODY, "linkages", "partnerships: agreement expiry alerts", null, null),
                    () -> tx.execute(st -> jdbc.sql("SELECT partnership.agreement_alerts()").query(Integer.class).single()));
            Integer purged = AuditContextHolder.with(new AuditContext(NOBODY, "linkages", "partnerships: drafts past their time removed", null, null),
                    () -> tx.execute(st -> jdbc.sql("SELECT partnership.purge_drafts()").query(Integer.class).single()));
            if ((told != null && told > 0) || (purged != null && purged > 0)) {
                LOG.info("partnerships: {} expiry notice(s), {} old draft(s) removed", told, purged);
            }
        } catch (RuntimeException e) {
            LOG.warn("partnerships daily round did not run: {}", e.getMessage());
        }
    }
}
