package ng.edu.moaum.portal.finance;

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
 * V569: the bank matching watched. Every morning the database reads what the statements show and no one has acted on — a month not
 * reconciled by the set day, a credit for a never-confirmed reference not sent to the bank credits, a payment confirmed on the portal
 * and not in the bank — and tells the office whose act it is, each thing once (finance.watch_bank_matching). One instance runs it at
 * a time.
 */
@Component
class BankMatchingWatch {

    private static final Logger LOG = LoggerFactory.getLogger(BankMatchingWatch.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    BankMatchingWatch(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.bank.matching-watch-cron:0 20 8 * * *}", zone = "Africa/Lagos")
    public void watch() {
        lock.runExclusively("bank-matching-watch", () -> {
            try {
                String said = AuditContextHolder.with(new AuditContext(NOBODY, "bursar", "bank matching watch", null, null),
                        () -> tx.execute(st -> jdbc.sql("SELECT finance.watch_bank_matching()::text").query(String.class).single()));
                LOG.info("bank matching: {}", said);
            } catch (RuntimeException e) {
                LOG.warn("bank matching: the morning alerts did not run: {}", e.getMessage());
            }
        });
    }
}
