package ng.edu.moaum.portal.auditlog;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.Test;

/** V627: the audit tiles are worked out at most once a minute and kept in between; with no minute set, every time. */
class AuditTilesCacheTest {

    /** a clock the test moves by hand */
    static final class Hand extends Clock {
        Instant now = Instant.parse("2026-10-21T21:00:00Z");

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    @Test
    void theTilesAreKeptForAMinuteThenWorkedOutAgain() {
        Hand clock = new Hand();
        AuditTilesCache cache = new AuditTilesCache(Duration.ofSeconds(60), clock);
        AtomicInteger worked = new AtomicInteger();
        java.util.function.Supplier<Map<String, Object>> work = () -> Map.of("total", (long) worked.incrementAndGet());

        assertThat(cache.get(work)).containsEntry("total", 1L);
        clock.now = clock.now.plusSeconds(59);
        assertThat(cache.get(work)).containsEntry("total", 1L);
        assertThat(worked).hasValue(1);
        clock.now = clock.now.plusSeconds(1);
        assertThat(cache.get(work)).containsEntry("total", 2L);
        assertThat(worked).hasValue(2);
    }

    @Test
    void withNoMinuteTheTilesAreWorkedOutEveryTime() {
        AuditTilesCache cache = new AuditTilesCache(Duration.ZERO, new Hand());
        AtomicInteger worked = new AtomicInteger();
        cache.get(() -> Map.of("total", (long) worked.incrementAndGet()));
        cache.get(() -> Map.of("total", (long) worked.incrementAndGet()));
        assertThat(worked).hasValue(2);
    }
}
