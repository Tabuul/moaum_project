package ng.edu.moaum.portal.finance;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

/**
 * V781: the Overpaid school fees list, kept. The list of students paid above their charge — by cause, with every hold on it — costs
 * seconds a session to work out (finance.overpaid_read), so the dashboard's panel and the desk read a kept copy
 * (finance.overpaid_snapshot) that this job keeps fresh: every ten minutes for the current session when a school-fees payment of it was
 * confirmed, uploaded by the old fees desk or archived since the last time, or the list is over an hour old
 * (finance.overpaid_refresh_due), and once a night for every session kept. Money never reads the kept list: every request, approval,
 * refund and carry reads the session live in the database. One instance runs it at a time.
 *
 * <p>The two schedules call {@link #refreshDue()} and {@link #refreshAll()} only while {@code moaum.overpaid.enabled} is true; the
 * integration tests turn it off (src/test/resources/config) so no refresh runs under a test that asserts a session was never worked
 * out, and call the two methods themselves where they need the job — they do their work whenever they are called.
 */
@Component
public class OverpaidWatch {

    private static final Logger LOG = LoggerFactory.getLogger(OverpaidWatch.class);
    private static final UUID NOBODY = new UUID(0, 0);
    private static final String LOCK = "overpaid-snapshot";

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final boolean enabled;

    OverpaidWatch(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions,
                  @Value("${moaum.overpaid.enabled:true}") boolean enabled) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.enabled = enabled;
    }

    @Scheduled(cron = "${moaum.overpaid.refresh-cron:0 */10 * * * *}", zone = "Africa/Lagos")
    void scheduledRefreshDue() {
        if (enabled) {
            refreshDue();
        }
    }

    @Scheduled(cron = "${moaum.overpaid.refresh-all-cron:0 20 2 * * *}", zone = "Africa/Lagos")
    void scheduledRefreshAll() {
        if (enabled) {
            refreshAll();
        }
    }

    /** the current session's kept list worked out again when it is due (never worked out, over an hour old, or a school-fees payment
     *  of the session confirmed, uploaded or archived since); the number of sessions worked out (0 or 1) */
    public int refreshDue() {
        AtomicInteger done = new AtomicInteger();
        lock.runExclusively(LOCK, () -> {
            try {
                String session = jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
                if (session != null && refresh(session, true)) {
                    done.incrementAndGet();
                }
            } catch (RuntimeException e) {
                LOG.warn("overpaid: the list could not be worked out: {}", e.getMessage());
            }
        });
        return done.get();
    }

    /** every session the kept list holds worked out again, whether or not it is due: the night's pass; the number worked out */
    public int refreshAll() {
        AtomicInteger done = new AtomicInteger();
        lock.runExclusively(LOCK, () -> {
            try {
                List<String> sessions = jdbc.sql("SELECT session FROM finance.overpaid_snapshot_run ORDER BY session DESC").query(String.class).list();
                for (String session : sessions) {
                    try {
                        if (refresh(session, false)) {
                            done.incrementAndGet();
                        }
                    } catch (RuntimeException e) {
                        LOG.warn("overpaid: the list of {} could not be worked out: {}", session, e.getMessage());
                    }
                }
            } catch (RuntimeException e) {
                LOG.warn("overpaid: the sessions kept could not be read: {}", e.getMessage());
            }
        });
        return done.get();
    }

    /** one session in a transaction of its own; whether it was worked out (another refresh running leaves its answer standing) */
    private boolean refresh(String session, boolean onlyWhenDue) {
        Boolean worked = AuditContextHolder.with(new AuditContext(NOBODY, "bursar", "overpaid list refresh", null, null), () -> tx.execute(st -> {
            if (onlyWhenDue && !Boolean.TRUE.equals(jdbc.sql("SELECT finance.overpaid_refresh_due(:s)").param("s", session).query(Boolean.class).single())) {
                return false;
            }
            var r = jdbc.sql("SELECT students, took_ms, refreshed FROM finance.overpaid_refresh(:s)").param("s", session).query().singleRow();
            if (Boolean.TRUE.equals(r.get("refreshed"))) {
                LOG.info("overpaid: {} worked out: {} student(s) paid above their charge, {} ms", session, r.get("students"), r.get("took_ms"));
                return true;
            }
            return false;
        }));
        return Boolean.TRUE.equals(worked);
    }
}
