package ng.edu.moaum.portal.shared;

import java.time.Duration;
import java.time.Instant;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;

import jakarta.annotation.PreDestroy;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Oct 2026: a figure a screen shows that takes many seconds to work out — the migrated students cleared, a department's
 * students carrying a failed course — kept for a few minutes and shared by everyone who asks the same question (the key).
 * Within five minutes the kept figure is given; within the hour it is given at once while a new one is worked out behind it;
 * anything older, or nothing kept, is worked out while the request waits (once, however many ask at the same moment). Every
 * answer says when it was worked out; an act that changes the figure forgets it. The same rules as the financial summary's
 * (analytics.FinanceSummaryCache), for any module's figure. Only figures are kept, never who asked.
 */
@Component
public class FigureCache {

    private static final Logger log = LoggerFactory.getLogger(FigureCache.class);
    static final int MAX_ENTRIES = 256;

    record Entry(Object value, Instant at, long millis) {
    }

    /** what a request is given: the figure, when it was worked out, and whether a newer one is being worked out behind it */
    public record Answer<T>(T value, Instant at, long millis, boolean refreshing) {
    }

    private final Duration fresh;
    private final Duration usable;
    private final TransactionTemplate readOnly;
    private final Map<Object, Entry> entries = Collections.synchronizedMap(new LinkedHashMap<>(16, 0.75f, true) {
        @Override
        protected boolean removeEldestEntry(Map.Entry<Object, Entry> eldest) {
            return size() > MAX_ENTRIES;
        }
    });
    private final ConcurrentHashMap<Object, CompletableFuture<Entry>> running = new ConcurrentHashMap<>();
    private final ExecutorService pool;

    FigureCache(PlatformTransactionManager transactions,
                @Value("${moaum.figures.fresh-seconds:300}") long freshSeconds,
                @Value("${moaum.figures.usable-seconds:3600}") long usableSeconds) {
        this.fresh = Duration.ofSeconds(Math.max(0, freshSeconds));
        this.usable = Duration.ofSeconds(Math.max(freshSeconds, usableSeconds));
        this.readOnly = new TransactionTemplate(transactions);
        this.readOnly.setReadOnly(true);
        AtomicInteger n = new AtomicInteger();
        // two at a time: however many people ask, at most two such figures are being worked out at once
        this.pool = Executors.newFixedThreadPool(2, r -> {
            Thread t = new Thread(r, "figure-cache-" + n.incrementAndGet());
            t.setDaemon(true);
            return t;
        });
    }

    /** the figure for a question: kept, kept while a newer one is worked out, or worked out now; {@code refresh} asks for a new one */
    @SuppressWarnings("unchecked")
    public <T> Answer<T> get(Object key, boolean refresh, Supplier<T> compute) {
        Entry kept = refresh ? null : entries.get(key);
        if (kept != null) {
            Duration age = Duration.between(kept.at(), Instant.now());
            if (age.compareTo(fresh) < 0) return new Answer<>((T) kept.value(), kept.at(), kept.millis(), running.containsKey(key));
            if (age.compareTo(usable) < 0) {
                warm(key, compute);
                return new Answer<>((T) kept.value(), kept.at(), kept.millis(), true);
            }
        }
        Entry e = await(start(key, compute));
        return new Answer<>((T) e.value(), e.at(), e.millis(), false);
    }

    /** a figure worked out ahead of anyone asking (at start-up, or behind a kept one); a failure is only logged */
    public void warm(Object key, Supplier<?> compute) {
        start(key, compute).exceptionally(x -> {
            log.warn("the figure {} could not be prepared ahead: {}", key, x.toString());
            return null;
        });
    }

    /** a figure an act has changed: forgotten, so the next request works it out again */
    public void forget(Object key) {
        entries.remove(key);
    }

    /** a figure an act has just worked out itself (after its transaction committed): kept as of now */
    public void put(Object key, Object value) {
        entries.put(key, new Entry(value, Instant.now(), 0));
    }

    private CompletableFuture<Entry> start(Object key, Supplier<?> compute) {
        CompletableFuture<Entry> mine = new CompletableFuture<>();
        CompletableFuture<Entry> prior = running.putIfAbsent(key, mine);
        if (prior != null) return prior;
        try {
            pool.execute(() -> {
                try {
                    Instant at = Instant.now();
                    long t0 = System.nanoTime();
                    Object value = readOnly.execute(s -> compute.get());
                    Entry e = new Entry(value, at, (System.nanoTime() - t0) / 1_000_000);
                    entries.put(key, e);
                    running.remove(key, mine);
                    mine.complete(e);
                } catch (Throwable x) {
                    running.remove(key, mine);
                    mine.completeExceptionally(x);
                }
            });
        } catch (RuntimeException x) {
            running.remove(key, mine);
            mine.completeExceptionally(x);
        }
        return mine;
    }

    private static Entry await(CompletableFuture<Entry> f) {
        try {
            return f.join();
        } catch (CompletionException x) {
            Throwable cause = x.getCause();
            if (cause instanceof RuntimeException r) throw r;
            if (cause instanceof Error err) throw err;
            throw x;
        }
    }

    @PreDestroy
    void stop() {
        pool.shutdownNow();
    }
}
