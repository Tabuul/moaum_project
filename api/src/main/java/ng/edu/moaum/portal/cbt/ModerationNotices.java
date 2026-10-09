package ng.edu.moaum.portal.cbt;

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
 * V375: every ten minutes, each setter is told of the moderation decisions on their questions made at least five minutes before —
 * gathered per bank, so a moderator working through a bank sends one notice, not one a question (assessment.notify_moderation). The
 * notice says how many were approved and how many returned; the questions and the notes are read in the bank, never sent.
 */
@Component
class ModerationNotices {

    private static final Logger LOG = LoggerFactory.getLogger(ModerationNotices.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    ModerationNotices(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.cbt.moderation-notice-cron:0 */10 * * * *}", zone = "Africa/Lagos")
    void run() {
        lock.runExclusively("cbt-moderation-notices", this::runNow);
    }

    void runNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "exams", "setters told of the moderation of their questions", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT assessment.notify_moderation(interval '5 minutes')").query(Integer.class).single()));
            if (n != null && n > 0) LOG.info("question moderation: {} setter notice(s) queued", n);
        } catch (RuntimeException e) {
            LOG.warn("question moderation notices did not run: {}", e.getMessage());
        }
    }
}
