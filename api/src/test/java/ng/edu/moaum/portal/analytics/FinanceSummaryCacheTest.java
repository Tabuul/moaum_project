package ng.edu.moaum.portal.analytics;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;

import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;

/** Oct 2026: the financial summary kept per question — worked out once however many ask, kept, refreshed behind a kept answer */
class FinanceSummaryCacheTest {

    /** no database: the computation's read-only transaction is a formality here */
    private static final PlatformTransactionManager NONE = new PlatformTransactionManager() {
        @Override
        public TransactionStatus getTransaction(TransactionDefinition definition) {
            return new SimpleTransactionStatus();
        }

        @Override
        public void commit(TransactionStatus status) {
        }

        @Override
        public void rollback(TransactionStatus status) {
        }
    };

    private static Supplier<Map<String, Object>> counting(AtomicInteger calls) {
        return () -> Map.of("n", calls.incrementAndGet());
    }

    /** the computation behind a kept answer has run, and has been kept */
    private static void settle(AtomicInteger calls, int n) throws InterruptedException {
        for (int i = 0; i < 250 && calls.get() < n; i++) Thread.sleep(20);
        Thread.sleep(100);
        assertThat(calls.get()).isEqualTo(n);
    }

    @Test
    void manyAskingTheSameQuestionAtOnceWaitForOneComputation() throws Exception {
        FinanceSummaryCache cache = new FinanceSummaryCache(NONE, 300, 3600);
        AtomicInteger calls = new AtomicInteger();
        CountDownLatch inside = new CountDownLatch(1), release = new CountDownLatch(1);
        Supplier<Map<String, Object>> slow = () -> {
            inside.countDown();
            try {
                release.await(5, TimeUnit.SECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            return Map.of("n", calls.incrementAndGet());
        };
        CompletableFuture<FinanceSummaryCache.Answer> first = CompletableFuture.supplyAsync(() -> cache.get("k", false, slow));
        assertThat(inside.await(5, TimeUnit.SECONDS)).isTrue();
        CompletableFuture<FinanceSummaryCache.Answer> second = CompletableFuture.supplyAsync(() -> cache.get("k", false, slow));
        Thread.sleep(50);
        release.countDown();
        FinanceSummaryCache.Answer a = first.get(5, TimeUnit.SECONDS), b = second.get(5, TimeUnit.SECONDS);
        assertThat(calls.get()).isEqualTo(1);
        assertThat(a.data()).isEqualTo(b.data()).containsEntry("n", 1);
        assertThat(a.at()).isEqualTo(b.at());
        // kept: asked again, the same answer without a new computation; another question is its own
        assertThat(cache.get("k", false, counting(calls)).data()).containsEntry("n", 1);
        assertThat(cache.get("other", false, counting(calls)).data()).containsEntry("n", 2);
        cache.stop();
    }

    @Test
    void aKeptAnswerPastItsMinutesIsGivenAtOnceWhileANewOneIsWorkedOutAndRefreshAsksAgain() throws Exception {
        // fresh for no time at all, usable for an hour: every request after the first is given the kept answer and starts a new one
        FinanceSummaryCache cache = new FinanceSummaryCache(NONE, 0, 3600);
        AtomicInteger calls = new AtomicInteger();
        assertThat(cache.get("k", false, counting(calls)).data()).containsEntry("n", 1);
        FinanceSummaryCache.Answer stale = cache.get("k", false, counting(calls));
        assertThat(stale.data()).containsEntry("n", 1);
        assertThat(stale.refreshing()).isTrue();
        settle(calls, 2);
        assertThat(cache.get("k", false, counting(calls)).data()).containsEntry("n", 2);
        settle(calls, 3);
        // Refresh: worked out now, and the request waits for it
        FinanceSummaryCache.Answer now = cache.get("k", true, counting(calls));
        assertThat(now.data()).containsEntry("n", 4);
        assertThat(now.refreshing()).isFalse();
        cache.stop();
    }

    @Test
    void aFailureReachesTheOneWhoAskedAndNothingIsKept_andAClearDropsWhatWasKept() {
        FinanceSummaryCache cache = new FinanceSummaryCache(NONE, 300, 3600);
        assertThatThrownBy(() -> cache.get("k", false, () -> { throw new IllegalStateException("the ledger is away"); }))
                .isInstanceOf(IllegalStateException.class).hasMessage("the ledger is away");
        AtomicInteger calls = new AtomicInteger();
        assertThat(cache.get("k", false, counting(calls)).data()).containsEntry("n", 1);
        cache.clear();
        assertThat(cache.get("k", false, counting(calls)).data()).containsEntry("n", 2);
        cache.stop();
    }
}
