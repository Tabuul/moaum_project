package ng.edu.moaum.portal.analytics;

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
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Supplier;

import jakarta.annotation.PreDestroy;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Oct 2026: the financial summary reads the whole ledger — on a live-shaped copy about five seconds for one session and
 * nearly twenty for every session — so an answer is kept for a few minutes and shared by every office that reads the same
 * scope with the same filters. Within five minutes the kept answer is given. Within the hour it is given at once while a
 * new one is worked out behind it. Anything older, or nothing kept, is worked out while the request waits. One computation
 * per question at a time: a second person asking the same thing waits for the first one's answer instead of reading the
 * ledger again. Every answer says when it was worked out, and Refresh asks for a new one. Only the figures of a scope are
 * kept — nothing about the person or the office that asked.
 */
@Component
class FinanceSummaryCache {

    private static final Logger log = LoggerFactory.getLogger(FinanceSummaryCache.class);
    /** the questions kept: every scope and filter set a working day asks fits, the oldest unread one goes first */
    static final int MAX_ENTRIES = 64;

    /** the figures, when the computation began (the ledger as of then) and how long it took */
    record Entry(Map<String, Object> data, Instant at, long millis) {
    }

    /** what a request is given: the figures, and whether a newer answer is being worked out behind them */
    record Answer(Map<String, Object> data, Instant at, long millis, boolean refreshing) {
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
    /** raised when the catalogue the figures are classified by changes: an answer begun before it is not kept */
    private final AtomicLong generation = new AtomicLong();
    private final ExecutorService pool;

    FinanceSummaryCache(PlatformTransactionManager transactions,
                        @Value("${moaum.analytics.summary-fresh-seconds:300}") long freshSeconds,
                        @Value("${moaum.analytics.summary-usable-seconds:3600}") long usableSeconds) {
        this.fresh = Duration.ofSeconds(Math.max(0, freshSeconds));
        this.usable = Duration.ofSeconds(Math.max(freshSeconds, usableSeconds));
        this.readOnly = new TransactionTemplate(transactions);
        this.readOnly.setReadOnly(true);
        AtomicInteger n = new AtomicInteger();
        // two at a time: the ledger is read by at most two summaries at once, whatever the number of people asking
        this.pool = Executors.newFixedThreadPool(2, r -> {
            Thread t = new Thread(r, "finance-summary-" + n.incrementAndGet());
            t.setDaemon(true);
            return t;
        });
    }

    /**
     * The answer to a question: kept, kept while a newer one is worked out, or worked out now. {@code refresh} asks for a new
     * one; asked by many at once, it is still worked out once.
     */
    Answer get(Object key, boolean refresh, Supplier<Map<String, Object>> compute) {
        Entry kept = refresh ? null : entries.get(key);
        if (kept != null) {
            Duration age = Duration.between(kept.at(), Instant.now());
            if (age.compareTo(fresh) < 0) return new Answer(kept.data(), kept.at(), kept.millis(), running.containsKey(key));
            if (age.compareTo(usable) < 0) {
                warm(key, compute);
                return new Answer(kept.data(), kept.at(), kept.millis(), true);
            }
        }
        Entry e = await(start(key, compute));
        return new Answer(e.data(), e.at(), e.millis(), false);
    }

    /** a computation begun without anyone waiting on it (behind a kept answer, or ahead of the first request); its failure is only logged */
    void warm(Object key, Supplier<Map<String, Object>> compute) {
        start(key, compute).exceptionally(x -> {
            log.warn("the financial summary could not be prepared ahead: {}", x.toString());
            return null;
        });
    }

    /** every kept answer dropped: the categories, programme types, purposes or rules the figures are classified by changed */
    void clear() {
        generation.incrementAndGet();
        entries.clear();
    }

    /** the computation of a question — the one already running, or a new one */
    private CompletableFuture<Entry> start(Object key, Supplier<Map<String, Object>> compute) {
        CompletableFuture<Entry> mine = new CompletableFuture<>();
        CompletableFuture<Entry> prior = running.putIfAbsent(key, mine);
        if (prior != null) return prior;
        long gen = generation.get();
        try {
            pool.execute(() -> {
                try {
                    Instant at = Instant.now();
                    long t0 = System.nanoTime();
                    Map<String, Object> data = readOnly.execute(s -> compute.get());
                    Entry e = new Entry(data, at, (System.nanoTime() - t0) / 1_000_000);
                    if (generation.get() == gen) entries.put(key, e);
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
