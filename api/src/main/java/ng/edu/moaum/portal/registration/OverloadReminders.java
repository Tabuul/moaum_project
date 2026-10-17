package ng.edu.moaum.portal.registration;

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
 * Each morning (V514): an overload request waiting three days or more is reminded to the Head of the student's department (once in
 * three days a request), and the Academic Office is told, once a day, how many wait in departments with no Head on the portal, and
 * which (registration.remind_overloads). Nothing is decided for the Head.
 */
@Component
class OverloadReminders {

    private static final Logger LOG = LoggerFactory.getLogger(OverloadReminders.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    OverloadReminders(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.overloads.remind-cron:0 10 9 * * *}", zone = "Africa/Lagos")
    void run() {
        lock.runExclusively("overload-reminders", this::runNow);
    }

    String runNow() {
        try {
            String out = AuditContextHolder.with(new AuditContext(NOBODY, "academic", "overload requests waiting", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT registration.remind_overloads(3)::text").query(String.class).single()));
            LOG.info("overload reminders: {}", out);
            return out;
        } catch (RuntimeException e) {
            LOG.warn("overload reminders failed: {}", e.getMessage());
            return null;
        }
    }
}
