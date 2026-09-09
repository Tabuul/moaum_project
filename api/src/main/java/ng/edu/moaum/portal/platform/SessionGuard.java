package ng.edu.moaum.portal.platform;

import java.time.Instant;
import java.util.HexFormat;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * ADR-017: a token issued by a sign-in names its server-side session, and
 * the session can be ended — by the person, by the Registrar, by time. A
 * token whose session has ended is refused however valid its signature. A
 * token with no session (a development token) is not the portal's concern.
 *
 * <p>A deploy is a fresh start: every session issued before this instance
 * started is refused, so a new version is met with a fresh sign-in rather
 * than a token minted against the code that was replaced. The floor is this
 * instance's start; a restart has the same effect, which is the intent.
 */
@Component
public class SessionGuard {

    private final JdbcClient jdbc;
    /** the moment this instance started; sessions older than it are from before the deploy */
    private final Instant startedAt = Instant.now();

    public SessionGuard(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    record State(boolean ended, boolean expired, boolean stale) {
    }

    /** empty when the session is unknown; otherwise whether it still stands, and touches it */
    public Optional<String> refuse(String sidHex) {
        byte[] id;
        try {
            id = HexFormat.of().parseHex(sidHex);
        } catch (IllegalArgumentException notHex) {
            return Optional.of("The token names a session that cannot exist.");
        }
        State state = jdbc.sql("SELECT ended_at IS NOT NULL AS ended, absolute_end < now() AS expired, issued_at < :floor AS stale FROM platform.session WHERE id = :id")
                .param("id", id).param("floor", java.sql.Timestamp.from(startedAt)).query(State.class).optional().orElse(null);
        if (state == null) {
            return Optional.of("The token names a session this portal does not hold. Sign in again.");
        }
        if (state.ended()) {
            return Optional.of("This session was ended. Sign in again.");
        }
        if (state.expired()) {
            return Optional.of("This session reached its end. Sign in again.");
        }
        if (state.stale()) {
            return Optional.of("The portal was updated. Sign in again.");
        }
        jdbc.sql("UPDATE platform.session SET last_seen_at = now() WHERE id = :id AND last_seen_at < now() - interval '1 minute'")
                .param("id", id).update();
        return Optional.empty();
    }
}
