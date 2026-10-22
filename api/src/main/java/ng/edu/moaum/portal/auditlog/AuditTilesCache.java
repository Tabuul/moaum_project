package ng.edu.moaum.portal.auditlog;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Supplier;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * V627: the audit screen's four tiles (the trail's total and today's entries, actors and refusals) kept for a minute and shared
 * by everyone who opens the screen or the Internal Audit home. On a busy day today's counts read a few hundred thousand entries,
 * so they are worked out at most once a minute, by one request at a time; the others are given the kept figures. They describe
 * the whole trail, never the person asking, so one answer serves every office. moaum.audit.tiles-seconds sets the minute
 * (0 works them out every time).
 */
@Component
class AuditTilesCache {

    private record Kept(Map<String, Object> tiles, Instant at) {
    }

    private final Duration fresh;
    private final Clock clock;
    private volatile Kept kept;

    @Autowired
    AuditTilesCache(@Value("${moaum.audit.tiles-seconds:60}") long seconds) {
        this(Duration.ofSeconds(Math.max(0, seconds)), Clock.systemUTC());
    }

    AuditTilesCache(Duration fresh, Clock clock) {
        this.fresh = fresh;
        this.clock = clock;
    }

    /** the kept tiles while they are fresh; otherwise worked out now (one caller at a time) and kept */
    Map<String, Object> get(Supplier<Map<String, Object>> work) {
        Kept k = kept;
        if (k != null && isFresh(k)) {
            return k.tiles();
        }
        synchronized (this) {
            k = kept;
            if (k != null && isFresh(k)) {
                return k.tiles();
            }
            Instant at = clock.instant();
            Map<String, Object> tiles = Collections.unmodifiableMap(new LinkedHashMap<>(work.get()));
            kept = new Kept(tiles, at);
            return tiles;
        }
    }

    private boolean isFresh(Kept k) {
        return !fresh.isZero() && Duration.between(k.at(), clock.instant()).compareTo(fresh) < 0;
    }
}
