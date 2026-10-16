package ng.edu.moaum.portal.platform;

import java.sql.SQLException;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.Map;

import javax.sql.DataSource;

import com.zaxxer.hikari.HikariDataSource;
import com.zaxxer.hikari.HikariPoolMXBean;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * How busy the portal's database connections are (Oct 2026). Interswitch once waited fifty seconds for an answer the portal
 * gives in half a second: every connection was in use, and a request waits up to thirty seconds for one. This samples the
 * pool every few seconds — in use, idle, the requests waiting — keeps the last hour, says on the public status what the pool
 * is doing and the busiest it has been, and warns in the log (at most once a minute) while requests wait. Hikari's own leak
 * detection (spring.datasource.hikari.leak-detection-threshold) names the code holding a connection longest. V486: when requests
 * have waited for a connection for a minute or more (moaum.db.pool-alert-after-seconds), the Directorate of ICT is told through
 * the notification engine — at most once an hour (platform.tell_pool_waiting) — on a thread of its own, so the sampler never
 * waits on the busy pool itself.
 */
@Component
public class PoolWatch {

    private static final Logger LOG = LoggerFactory.getLogger(PoolWatch.class);

    /** one sample: when, in use, idle, waiting */
    record Sample(Instant at, int active, int idle, int waiting) {
    }

    private static final java.util.UUID NOBODY = new java.util.UUID(0, 0);

    private final HikariDataSource hikari;
    private final long keepMs;
    private final Deque<Sample> samples = new ArrayDeque<>();
    private volatile Instant lastWarned = Instant.EPOCH;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final long alertAfterSeconds;
    /** V486: since when requests have waited without a break, the most waiting at once since, and whether ICT has been told */
    private volatile Instant waitingSince;
    private volatile int waitingPeak;
    private volatile boolean told;
    private final java.util.concurrent.atomic.AtomicBoolean telling = new java.util.concurrent.atomic.AtomicBoolean();

    PoolWatch(DataSource dataSource, JdbcClient jdbc, PlatformTransactionManager transactions,
              @Value("${moaum.db.pool-history-minutes:60}") int minutes,
              @Value("${moaum.db.pool-alert-after-seconds:60}") long alertAfterSeconds) {
        this.hikari = hikari(dataSource);
        this.keepMs = Math.max(1, minutes) * 60_000L;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.alertAfterSeconds = alertAfterSeconds;
    }

    private static HikariDataSource hikari(DataSource ds) {
        if (ds instanceof HikariDataSource h) return h;
        try {
            return ds.isWrapperFor(HikariDataSource.class) ? ds.unwrap(HikariDataSource.class) : null;
        } catch (SQLException notWrapped) {
            return null;
        }
    }

    private HikariPoolMXBean pool() {
        return hikari == null ? null : hikari.getHikariPoolMXBean();
    }

    @Scheduled(fixedDelayString = "${moaum.db.pool-sample-ms:5000}", initialDelayString = "${moaum.db.pool-sample-initial-ms:10000}")
    public void sample() {
        HikariPoolMXBean p = pool();
        if (p == null) return;
        Sample s = new Sample(Instant.now(), p.getActiveConnections(), p.getIdleConnections(), p.getThreadsAwaitingConnection());
        synchronized (samples) {
            samples.addLast(s);
            Instant cut = s.at().minusMillis(keepMs);
            while (!samples.isEmpty() && samples.peekFirst().at().isBefore(cut)) samples.removeFirst();
        }
        if (s.waiting() > 0 && s.at().isAfter(lastWarned.plusSeconds(60))) {
            lastWarned = s.at();
            LOG.warn("database pool busy: {} of {} connections in use, {} request(s) waiting for one", s.active(), hikari.getMaximumPoolSize(), s.waiting());
        }
        // V486: waiting without a break for a minute or more is told to ICT, once a run (and once an hour, by the event key)
        if (s.waiting() == 0) {
            waitingSince = null;
            waitingPeak = 0;
            told = false;
            return;
        }
        if (waitingSince == null) waitingSince = s.at();
        waitingPeak = Math.max(waitingPeak, s.waiting());
        long seconds = java.time.Duration.between(waitingSince, s.at()).getSeconds();
        if (alertAfterSeconds > 0 && !told && seconds >= alertAfterSeconds && telling.compareAndSet(false, true)) {
            int peak = waitingPeak, max = hikari.getMaximumPoolSize();
            Thread.ofVirtual().name("pool-watch-tell").start(() -> {
                try {
                    Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "Database connections waited for", null, null),
                            () -> tx.execute(st -> jdbc.sql("SELECT platform.tell_pool_waiting(:s, :p, :m)")
                                    .param("s", (int) seconds).param("p", peak).param("m", max).query(Integer.class).single()));
                    told = true;
                    LOG.warn("database pool busy for {} s; the Directorate of ICT told ({} message(s) queued)", seconds, n);
                } catch (RuntimeException e) {
                    LOG.warn("database pool busy for {} s; telling the Directorate of ICT did not go through yet: {}", seconds, e.getMessage());
                } finally {
                    telling.set(false);
                }
            });
        }
    }

    /** the pool now, and the busiest it has been over the kept history — counts only, nothing personal */
    public Map<String, Object> status() {
        HikariPoolMXBean p = pool();
        Map<String, Object> out = new LinkedHashMap<>();
        if (p == null) {
            out.put("available", false);
            return out;
        }
        out.put("max", hikari.getMaximumPoolSize());
        out.put("active", p.getActiveConnections());
        out.put("idle", p.getIdleConnections());
        out.put("waiting", p.getThreadsAwaitingConnection());
        int peakActive = 0, peakWaiting = 0, busy = 0, n;
        Instant lastBusy = null;
        synchronized (samples) {
            n = samples.size();
            for (Sample s : samples) {
                peakActive = Math.max(peakActive, s.active());
                peakWaiting = Math.max(peakWaiting, s.waiting());
                if (s.waiting() > 0) {
                    busy++;
                    lastBusy = s.at();
                }
            }
        }
        Map<String, Object> hour = new LinkedHashMap<>();
        hour.put("samples", n);
        hour.put("peakActive", peakActive);
        hour.put("peakWaiting", peakWaiting);
        hour.put("samplesWithWaiting", busy);
        hour.put("lastWaitingAt", lastBusy == null ? null : lastBusy.toString());
        out.put("history", hour);
        return out;
    }
}
