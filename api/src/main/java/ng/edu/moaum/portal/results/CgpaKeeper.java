package ng.edu.moaum.portal.results;

import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V549: each student's CGPA kept current (assessment.cgpa_kept). Every minute the CGPAs made stale since — by a score, a sheet,
 * a registration, the grading — are worked out again, a batch at a time, each batch its own transaction, for at most a set
 * time a tick; the first run after the migration holds every student. Once a night every kept CGPA is made stale, for a grading
 * version that comes into force on a date with no write. A CGPA made stale is read from the results until it is worked out
 * again (assessment.kept_cgpa), so nothing waits on this job but the speed of the register.
 */
@Component
class CgpaKeeper {

    private static final Logger LOG = LoggerFactory.getLogger(CgpaKeeper.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final int batch;
    private final long budgetMs;

    CgpaKeeper(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions,
               @Value("${moaum.cgpa.keep-batch:2000}") int batch, @Value("${moaum.cgpa.keep-budget-ms:20000}") long budgetMs) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.batch = Math.max(1, batch);
        this.budgetMs = Math.max(1000, budgetMs);
    }

    @Scheduled(fixedDelayString = "${moaum.cgpa.keep-every-ms:60000}", initialDelayString = "${moaum.cgpa.keep-initial-ms:90000}")
    void keep() {
        lock.runExclusively("cgpa-keeper", this::keepNow);
    }

    /** batches until none is stale, a batch finds nothing to do, or the tick's time is spent; the number worked out again */
    int keepNow() {
        long until = System.currentTimeMillis() + budgetMs;
        int done = 0;
        long left = 0;
        while (true) {
            Map<String, Object> r;
            try {
                r = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "CGPA kept", null, null), () -> tx.execute(status ->
                        jdbc.sql("SELECT (x->>'refreshed')::int AS refreshed, (x->>'left')::bigint AS still FROM assessment.refresh_kept_cgpa(:n) AS x")
                                .param("n", batch).query().singleRow()));
            } catch (RuntimeException e) {
                LOG.warn("CGPA keeping did not run: {}", e.getMessage());
                return done;
            }
            int refreshed = r == null ? 0 : ((Number) r.get("refreshed")).intValue();
            left = r == null ? 0 : ((Number) r.get("still")).longValue();
            done += refreshed;
            if (left == 0 || refreshed == 0 || System.currentTimeMillis() > until) {
                break;
            }
        }
        if (done > 0) {
            LOG.info("CGPA kept: {} worked out again, {} still to do", done, left);
        }
        return done;
    }

    /** every night: every kept CGPA made stale, so a grading version in force from today is read by the next ticks */
    @Scheduled(cron = "${moaum.cgpa.stale-cron:0 30 1 * * *}", zone = "Africa/Lagos")
    void nightly() {
        lock.runExclusively("cgpa-keeper", () -> {
            try {
                Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "CGPA kept: the nightly pass", null, null), () -> tx.execute(status ->
                        jdbc.sql("SELECT assessment.cgpa_stale_all()").query(Integer.class).single()));
                LOG.info("CGPA kept: {} made stale for the nightly pass", n);
            } catch (RuntimeException e) {
                LOG.warn("CGPA nightly pass did not run: {}", e.getMessage());
            }
        });
    }
}
