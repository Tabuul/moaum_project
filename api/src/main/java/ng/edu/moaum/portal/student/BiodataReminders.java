package ng.edu.moaum.portal.student;

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
 * Each morning (V423), while mandatory biodata completion is ON: a student on the register whose required biodata is
 * still incomplete is told by e-mail and SMS (and on the portal's notifications) — at most once in seven days, so a
 * student is never told twice in a week and never on every sign-in; once complete, nothing more is sent. While the
 * gate is OFF nobody is reminded (people.remind_biodata).
 */
@Component
class BiodataReminders {

    private static final Logger LOG = LoggerFactory.getLogger(BiodataReminders.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    BiodataReminders(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "0 20 9 * * *", zone = "Africa/Lagos")
    void run() {
        lock.runExclusively("biodata-reminders", this::runNow);
    }

    int runNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "biodata completion reminders", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT people.remind_biodata(3000)").query(Integer.class).single()));
            if (n != null && n > 0) LOG.info("biodata reminders: {} student(s) reminded", n);
            return n == null ? 0 : n;
        } catch (RuntimeException e) {
            LOG.warn("biodata reminders failed: {}", e.getMessage());
            return 0;
        }
    }
}
