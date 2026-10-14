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
 * V451: the students with no school fee stated, watched. Every hour, while a semester of the current session is open, the
 * database reads the live undergraduates the stated lines do not reach (finance.fee_gaps) and tells every Bursary office
 * holder, by e-mail and on the portal, when a group appears that it had not seen at its last reading
 * (finance.watch_fee_gaps, FEE_GAPS). A gap put right is not told again; one that opens again is. One instance runs it at a time.
 */
@Component
class FeeGapWatch {

    private static final Logger LOG = LoggerFactory.getLogger(FeeGapWatch.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    FeeGapWatch(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.fees.gap-watch-cron:0 25 * * * *}", zone = "Africa/Lagos")
    public void watch() {
        lock.runExclusively("fee-gap-watch", () -> {
            try {
                Integer told = AuditContextHolder.with(new AuditContext(NOBODY, "bursar", "fee gap watch", null, null),
                        () -> tx.execute(st -> jdbc.sql("SELECT finance.watch_fee_gaps()").query(Integer.class).single()));
                if (told != null && told > 0) {
                    LOG.info("fees: students with no school fee stated; {} message(s) queued to the Bursary", told);
                }
            } catch (RuntimeException e) {
                LOG.warn("fees: the fee-gap watch did not run: {}", e.getMessage());
            }
        });
    }
}
