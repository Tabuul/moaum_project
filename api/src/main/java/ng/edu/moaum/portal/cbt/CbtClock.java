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
 * The CBT clock (V322). The server's end time on an attempt is the authority: a candidate whose browser never
 * comes back — a closed laptop, a dead battery, a lost connection — still has their attempt finalised and scored
 * from the answers saved so far, a short grace after the end. Every API instance ticks; one runs at a time under
 * the job lock; the finalisation is idempotent, so a tick that overlaps a candidate's own submission changes
 * nothing. The state lives in PostgreSQL alone, so an instance restarting mid-examination loses nothing.
 */
@Component
public class CbtClock {

    private static final Logger LOG = LoggerFactory.getLogger(CbtClock.class);
    private static final UUID NOBODY = new UUID(0L, 0L);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    public CbtClock(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(fixedDelayString = "${moaum.cbt.sweep-ms:30000}", initialDelayString = "${moaum.cbt.sweep-initial-ms:45000}")
    public void tick() {
        lock.runExclusively("cbt-sweep", this::tickNow);
    }

    void tickNow() {
        try {
            int n = sweep();
            if (n > 0) LOG.info("cbt clock: {} attempt(s) finalised at time expired", n);
        } catch (RuntimeException e) {
            LOG.warn("cbt clock: did not run: {}", e.getMessage());
        }
    }

    /** every attempt past its end finalised; how many */
    public int sweep() {
        return AuditContextHolder.with(new AuditContext(NOBODY, "ict", "CBT clock: time expired", null, null),
                () -> tx.execute(st -> jdbc.sql("SELECT assessment.cbt_sweep()").query(Integer.class).single()));
    }
}
