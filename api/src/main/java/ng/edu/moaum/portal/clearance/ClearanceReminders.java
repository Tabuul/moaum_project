package ng.edu.moaum.portal.clearance;

import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Each morning (V415): a student whose clearance still has offices outstanding is reminded — once per process in the
 * workflow's interval (clearance.workflow.reminder_days; none at 0), never in the clearance's first interval — so nobody
 * is told the same thing twice in a week. clearance.reminder keeps what was sent.
 */
@Component
class ClearanceReminders {

    private static final Logger LOG = LoggerFactory.getLogger(ClearanceReminders.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    ClearanceReminders(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "0 40 8 * * *", zone = "Africa/Lagos")
    void run() {
        lock.runExclusively("clearance-reminders", this::runNow);
    }

    int runNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "clearance reminders", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT clearance.remind(2000)").query(Integer.class).single()));
            if (n != null && n > 0) LOG.info("clearance reminders: {} student(s) reminded", n);
            return n == null ? 0 : n;
        } catch (RuntimeException e) {
            LOG.warn("clearance reminders failed: {}", e.getMessage());
            return 0;
        }
    }
}
