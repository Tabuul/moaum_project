package ng.edu.moaum.portal.platform;

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
 * V555: once a day, every statement of the database as pg_stat_statements holds it (calls, time, rows) kept for Slow Statements'
 * last day, week and month (platform.take_statement_snapshot), and ICT told of the statements whose average over the last day is at
 * least twice the week before's. Where the statistics are not kept, the snapshot says so and nothing is written.
 */
@Component
class StatementSnapshots {

    private static final Logger LOG = LoggerFactory.getLogger(StatementSnapshots.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    StatementSnapshots(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.statements.snapshot-cron:0 5 0 * * *}", zone = "Africa/Lagos")
    void snapshot() {
        lock.runExclusively("statement-snapshot", this::snapshotNow);
    }

    String snapshotNow() {
        try {
            String r = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "statement snapshot", null, null), () -> tx.execute(status ->
                    jdbc.sql("SELECT platform.take_statement_snapshot()::text").query(String.class).single()));
            LOG.info("statement snapshot: {}", r);
            return r;
        } catch (RuntimeException e) {
            LOG.warn("statement snapshot did not run: {}", e.getMessage());
            return null;
        }
    }
}
