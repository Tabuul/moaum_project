package ng.edu.moaum.portal.platform;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Supplier;

import jakarta.annotation.PreDestroy;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * Oct 2026: the public {@code /api/v1/platform/status} is what probes and pipelines poll, and it carried the PG and CCE
 * readiness (V393, V412), read on every call. The PG readiness alone read about fifteen seconds on live data, and the
 * probes became almost all of the database's load. The two readings are now kept: within five minutes the kept one is
 * given, and after that the kept one is still given at once while one new reading is taken behind it. A probe waits only
 * when nothing has been read yet since this instance started, and many probes arriving together wait for the same single
 * reading. The Go-live readiness screen reads live, and what it reads replaces the kept reading.
 */
@Component
class ReadinessSnapshot {

    private static final Logger log = LoggerFactory.getLogger(ReadinessSnapshot.class);

    /** the PG and CCE readings (either may be absent when its reading failed), and when they were taken */
    record Reading(Map<String, Object> postgraduate, Map<String, Object> cce, Instant at) {
    }

    private final Supplier<Map<String, Object>> pg;
    private final Supplier<Map<String, Object>> cce;
    private final Duration fresh;
    private final Supplier<Instant> clock;
    private final ExecutorService pool;
    private volatile Reading kept;
    /** the one reading being taken, if any */
    private CompletableFuture<Reading> running;

    @Autowired
    ReadinessSnapshot(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json,
                      @Value("${moaum.platform.status-readiness-seconds:300}") long freshSeconds) {
        this(() -> read(jdbc, json, "admissions.pg_readiness()"), () -> read(jdbc, json, "admissions.cce_readiness()"),
                Duration.ofSeconds(Math.max(0, freshSeconds)), Instant::now);
    }

    ReadinessSnapshot(Supplier<Map<String, Object>> pg, Supplier<Map<String, Object>> cce, Duration fresh, Supplier<Instant> clock) {
        this.pg = pg;
        this.cce = cce;
        this.fresh = fresh;
        this.clock = clock;
        this.pool = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "status-readiness");
            t.setDaemon(true);
            return t;
        });
    }

    /** one readiness function's answer, as a map */
    static Map<String, Object> read(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json, String function) {
        String text = jdbc.sql("SELECT " + function + "::text").query(String.class).single();
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** the kept reading — taken now only when there is none yet; a stale one is given while a new one is taken behind it */
    Reading get() {
        Reading r = kept;
        if (r != null) {
            if (stale(r)) {
                refreshIfStale();
            }
            return r;
        }
        try {
            return refresh().join();
        } catch (CompletionException x) {
            return null;
        }
    }

    /** a reading the Go-live readiness took live: kept, as newer than anything kept */
    void offer(Map<String, Object> postgraduate, Map<String, Object> cceReading) {
        keep(new Reading(postgraduate, cceReading, clock.get()));
    }

    /** a reading kept unless a newer one already is (a live read can land while an older one is still being taken) */
    private synchronized void keep(Reading r) {
        if (kept == null || !kept.at().isAfter(r.at())) {
            kept = r;
        }
    }

    /** the first reading taken as soon as the instance is up, so the first probe does not wait for it */
    @EventListener(ApplicationReadyEvent.class)
    void warm() {
        refresh();
    }

    private boolean stale(Reading r) {
        return Duration.between(r.at(), clock.get()).compareTo(fresh) >= 0;
    }

    /** a new reading behind a stale one — unless one is being taken, or one has just been kept since the caller looked */
    private synchronized void refreshIfStale() {
        Reading now = kept;
        if (now == null || stale(now)) {
            refresh();
        }
    }

    /** the reading being taken, or a new one */
    synchronized CompletableFuture<Reading> refresh() {
        if (running != null && !running.isDone()) {
            return running;
        }
        CompletableFuture<Reading> mine = new CompletableFuture<>();
        running = mine;
        try {
            pool.execute(() -> {
                try {
                    Instant at = clock.get();
                    Reading before = kept;
                    // a part that cannot be read keeps what was read of it before
                    Reading r = new Reading(part(pg, before == null ? null : before.postgraduate(), "PG"),
                            part(cce, before == null ? null : before.cce(), "CCE"), at);
                    keep(r);
                    mine.complete(kept);
                } catch (Throwable x) {
                    mine.completeExceptionally(x);
                }
            });
        } catch (RuntimeException x) {
            mine.completeExceptionally(x);
        }
        return mine;
    }

    private static Map<String, Object> part(Supplier<Map<String, Object>> read, Map<String, Object> before, String what) {
        try {
            return read.get();
        } catch (RuntimeException x) {
            log.warn("the {} readiness could not be read for the status: {}", what, x.toString());
            return before;
        }
    }

    @PreDestroy
    void stop() {
        pool.shutdownNow();
    }
}
