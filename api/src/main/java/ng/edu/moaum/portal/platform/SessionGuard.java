package ng.edu.moaum.portal.platform;

import java.util.HexFormat;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * ADR-017: a token issued by a sign-in names its server-side session, and
 * the session can be ended — by the person, by the Registrar, by time. A
 * token whose session has ended is refused however valid its signature. A
 * token with no session (a development token) is not the portal's concern.
 */
@Component
public class SessionGuard {

    private final JdbcClient jdbc;

    public SessionGuard(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    record State(boolean ended, boolean expired) {
    }

    /** empty when the session is unknown; otherwise whether it still stands, and touches it */
    public Optional<String> refuse(String sidHex) {
        byte[] id;
        try {
            id = HexFormat.of().parseHex(sidHex);
        } catch (IllegalArgumentException notHex) {
            return Optional.of("The token names a session that cannot exist.");
        }
        State state = jdbc.sql("SELECT ended_at IS NOT NULL AS ended, absolute_end < now() AS expired FROM platform.session WHERE id = :id")
                .param("id", id).query(State.class).optional().orElse(null);
        if (state == null) {
            return Optional.of("The token names a session this portal does not hold. Sign in again.");
        }
        if (state.ended()) {
            return Optional.of("This session was ended. Sign in again.");
        }
        if (state.expired()) {
            return Optional.of("This session reached its end. Sign in again.");
        }
        jdbc.sql("UPDATE platform.session SET last_seen_at = now() WHERE id = :id AND last_seen_at < now() - interval '1 minute'")
                .param("id", id).update();
        return Optional.empty();
    }
}
