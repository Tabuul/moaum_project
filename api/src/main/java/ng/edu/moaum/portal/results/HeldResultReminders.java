package ng.edu.moaum.portal.results;

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
 * Each morning (V424): the results held for the Senate's decision (withheld, incomplete, malpractice) longer than the
 * University's days (policy.standing_setting.held_remind_days) are reminded to the Registrar, the Deputy Registrar and Exams
 * and Records — at most once a week, never when the days are 0. assessment.held_reminder_log keeps what was sent.
 */
@Component
class HeldResultReminders {

    private static final Logger LOG = LoggerFactory.getLogger(HeldResultReminders.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    HeldResultReminders(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "0 50 8 * * *", zone = "Africa/Lagos")
    void run() {
        lock.runExclusively("held-result-reminders", this::runNow);
    }

    int runNow() {
        try {
            Integer told = AuditContextHolder.with(new AuditContext(NOBODY, "records", "results held for the Senate", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT assessment.remind_held_results()").query(Integer.class).single()));
            if (told != null && told > 0) LOG.info("held results: {} officer(s) reminded", told);
            return told == null ? 0 : told;
        } catch (RuntimeException e) {
            LOG.warn("held result reminders failed: {}", e.getMessage());
            return 0;
        }
    }
}
