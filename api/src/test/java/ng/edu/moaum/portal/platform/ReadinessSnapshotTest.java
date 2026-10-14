package ng.edu.moaum.portal.platform;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Supplier;

import org.junit.jupiter.api.Test;

/** Oct 2026: the readiness the public status gives — read once however many probes ask, kept, and read again behind a kept one */
class ReadinessSnapshotTest {

    private static Supplier<Map<String, Object>> counting(AtomicInteger calls) {
        return () -> Map.of("n", calls.incrementAndGet());
    }

    /** the reading behind a kept one has run */
    private static void settle(AtomicInteger calls, int n) throws InterruptedException {
        for (int i = 0; i < 250 && calls.get() < n; i++) Thread.sleep(20);
        Thread.sleep(100);
        assertThat(calls.get()).isEqualTo(n);
    }

    @Test
    void manyProbesAtOnceOnAColdStartWaitForOneReading() throws Exception {
        AtomicInteger pg = new AtomicInteger(), cce = new AtomicInteger();
        CountDownLatch inside = new CountDownLatch(1), release = new CountDownLatch(1);
        Supplier<Map<String, Object>> slow = () -> {
            inside.countDown();
            try {
                release.await(5, TimeUnit.SECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            return Map.of("n", pg.incrementAndGet());
        };
        ReadinessSnapshot snap = new ReadinessSnapshot(slow, counting(cce), Duration.ofMinutes(5), Instant::now);
        List<CompletableFuture<ReadinessSnapshot.Reading>> probes = new ArrayList<>();
        for (int i = 0; i < 8; i++) probes.add(CompletableFuture.supplyAsync(snap::get));
        assertThat(inside.await(5, TimeUnit.SECONDS)).isTrue();
        Thread.sleep(100);
        release.countDown();
        for (CompletableFuture<ReadinessSnapshot.Reading> p : probes) {
            assertThat(p.get(5, TimeUnit.SECONDS).postgraduate()).containsEntry("n", 1);
        }
        assertThat(pg.get()).isEqualTo(1);
        assertThat(cce.get()).isEqualTo(1);
    }

    @Test
    void aFreshReadingIsGivenWithoutReadingAgain() {
        AtomicInteger pg = new AtomicInteger(), cce = new AtomicInteger();
        ReadinessSnapshot snap = new ReadinessSnapshot(counting(pg), counting(cce), Duration.ofMinutes(5), Instant::now);
        for (int i = 0; i < 50; i++) assertThat(snap.get().postgraduate()).containsEntry("n", 1);
        assertThat(pg.get()).isEqualTo(1);
    }

    @Test
    void aStaleReadingIsGivenAtOnceWhileOneNewReadingIsTakenBehindIt() throws Exception {
        AtomicInteger pg = new AtomicInteger(), cce = new AtomicInteger();
        AtomicReference<Instant> now = new AtomicReference<>(Instant.parse("2026-10-14T09:00:00Z"));
        ReadinessSnapshot snap = new ReadinessSnapshot(counting(pg), counting(cce), Duration.ofMinutes(5), now::get);
        assertThat(snap.get().postgraduate()).containsEntry("n", 1);
        now.set(now.get().plus(Duration.ofMinutes(6)));
        for (int i = 0; i < 20; i++) assertThat(snap.get()).isNotNull();   // the kept one, never a wait
        settle(pg, 2);
        assertThat(snap.get().postgraduate()).containsEntry("n", 2);
    }

    @Test
    void aPartThatCannotBeReadKeepsWhatWasReadOfItBefore() throws Exception {
        AtomicInteger pg = new AtomicInteger(), cce = new AtomicInteger();
        AtomicReference<Instant> now = new AtomicReference<>(Instant.parse("2026-10-14T09:00:00Z"));
        Supplier<Map<String, Object>> failingSecondTime = () -> {
            if (pg.incrementAndGet() > 1) throw new IllegalStateException("database gone");
            return Map.of("n", 1);
        };
        ReadinessSnapshot snap = new ReadinessSnapshot(failingSecondTime, counting(cce), Duration.ofMinutes(5), now::get);
        snap.get();
        now.set(now.get().plus(Duration.ofMinutes(6)));
        snap.refresh().get(5, TimeUnit.SECONDS);
        ReadinessSnapshot.Reading r = snap.get();
        assertThat(r.postgraduate()).containsEntry("n", 1);
        assertThat(r.cce()).containsEntry("n", 2);
    }

    @Test
    void whatTheGoLiveScreenReadLiveReplacesTheKeptReading() {
        AtomicInteger pg = new AtomicInteger(), cce = new AtomicInteger();
        ReadinessSnapshot snap = new ReadinessSnapshot(counting(pg), counting(cce), Duration.ofMinutes(5), Instant::now);
        snap.get();
        snap.offer(Map.of("n", 99), Map.of("n", 98));
        assertThat(snap.get().postgraduate()).containsEntry("n", 99);
        assertThat(snap.get().cce()).containsEntry("n", 98);
        assertThat(pg.get()).isEqualTo(1);
    }
}
