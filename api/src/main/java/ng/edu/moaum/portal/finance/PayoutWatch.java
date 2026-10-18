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
 * V545: refunds and wallet withdrawals approved and not yet paid, watched. Every morning the database reads those that have waited
 * longer than the days the Bursary set (finance.unpaid_payouts) and tells the Bursar and the Students Account Officer, once a day,
 * by e-mail and on the portal (finance.watch_unpaid_payouts, UNPAID_PAYOUTS). One instance runs it at a time.
 */
@Component
class PayoutWatch {

    private static final Logger LOG = LoggerFactory.getLogger(PayoutWatch.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    PayoutWatch(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.payouts.unpaid-watch-cron:0 10 8 * * *}", zone = "Africa/Lagos")
    public void watch() {
        lock.runExclusively("unpaid-payout-watch", () -> {
            try {
                Integer told = AuditContextHolder.with(new AuditContext(NOBODY, "bursar", "unpaid payout watch", null, null),
                        () -> tx.execute(st -> jdbc.sql("SELECT finance.watch_unpaid_payouts()").query(Integer.class).single()));
                if (told != null && told > 0) {
                    LOG.info("payouts: approved refunds and withdrawals not yet paid; {} message(s) queued to the Bursary", told);
                }
            } catch (RuntimeException e) {
                LOG.warn("payouts: the unpaid payout watch did not run: {}", e.getMessage());
            }
        });
    }
}
