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
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * How busy the portal's database connections are (Oct 2026). Interswitch once waited fifty seconds for an answer the portal
 * gives in half a second: every connection was in use, and a request waits up to thirty seconds for one. This samples the
 * pool every few seconds — in use, idle, the requests waiting — keeps the last hour, says on the public status what the pool
 * is doing and the busiest it has been, and warns in the log (at most once a minute) while requests wait. Hikari's own leak
 * detection (spring.datasource.hikari.leak-detection-threshold) names the code holding a connection longest.
 */
@Component
public class PoolWatch {

    private static final Logger LOG = LoggerFactory.getLogger(PoolWatch.class);

    /** one sample: when, in use, idle, waiting */
    record Sample(Instant at, int active, int idle, int waiting) {
    }

    private final HikariDataSource hikari;
    private final long keepMs;
    private final Deque<Sample> samples = new ArrayDeque<>();
    private volatile Instant lastWarned = Instant.EPOCH;

    PoolWatch(DataSource dataSource, @Value("${moaum.db.pool-history-minutes:60}") int minutes) {
        this.hikari = hikari(dataSource);
        this.keepMs = Math.max(1, minutes) * 60_000L;
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
