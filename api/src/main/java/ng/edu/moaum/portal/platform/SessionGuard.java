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
 *
 * <p>V437: a session left alone ends. The Directorate of ICT's policy
 * (platform.session_policy) says after how long without activity; the server's
 * clock decides, on every request, from the session's last activity — and ends
 * the session there and then, with the reason, so no later request revives it.
 * Activity is what the person does: a request the browser sends on its own (a
 * poll, a board refreshing) says so with {@code X-Background} and does not
 * count. The browser's own countdown is for the person's benefit only.
 */
@Component
public class SessionGuard {

    /** the code the 401 carries when the session ended for inactivity, which the portal turns into "Session expired" */
    public static final String EXPIRED_IDLE = "SESSION_EXPIRED_IDLE";

    private final JdbcClient jdbc;
    /** the moment this instance started; sessions older than it are from before the deploy */
    private final Instant startedAt = Instant.now();

    public SessionGuard(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** why a token is refused: a stable code, and the words the person reads */
    public record Refusal(String code, String detail) {
    }

    record State(boolean ended, boolean expired, boolean stale, boolean idle) {
    }

    /**
     * Empty when the session still stands; otherwise why it does not. A standing session is touched as seen — unless the
     * request is the browser's own (quiet), which is never activity. A session past the idle timeout is ended here, with
     * the reason, before it is refused.
     */
    public Optional<Refusal> refuse(String sidHex, boolean quiet) {
        byte[] id;
        try {
            id = HexFormat.of().parseHex(sidHex);
        } catch (IllegalArgumentException notHex) {
            return Optional.of(new Refusal("SESSION_INVALID", "The token names a session that cannot exist."));
        }
        State state = jdbc.sql("""
                SELECT s.ended_at IS NOT NULL AS ended, s.absolute_end < now() AS expired, s.issued_at < :floor AS stale,
                       p.idle_enabled AND s.last_seen_at < now() - make_interval(secs => p.idle_seconds) AS idle
                  FROM platform.session s
                 CROSS JOIN LATERAL platform.session_policy_for(s.active_office) AS p
                 WHERE s.id = :id
                """).param("id", id).param("floor", java.sql.Timestamp.from(startedAt)).query(State.class).optional().orElse(null);
        if (state == null) {
            return Optional.of(new Refusal("SESSION_UNKNOWN", "The token names a session this portal does not hold. Sign in again."));
        }
        if (state.ended()) {
            return Optional.of(new Refusal("SESSION_ENDED", "This session was ended. Sign in again."));
        }
        if (state.expired()) {
            return Optional.of(new Refusal("SESSION_EXPIRED", "This session reached its end. Sign in again."));
        }
        if (state.stale()) {
            return Optional.of(new Refusal("SESSION_STALE", "The portal was updated. Sign in again."));
        }
        if (state.idle()) {
            jdbc.sql("SELECT platform.session_expire_idle(:id)").param("id", id).query(Boolean.class).optional();
            return Optional.of(new Refusal(EXPIRED_IDLE, "Your session ended because you were inactive. Sign in again."));
        }
        if (!quiet) {
            touch(id);
        }
        return Optional.empty();
    }

    /** the session seen now — written at most once in fifteen seconds, so a busy person costs one small write a quarter minute */
    public void touch(String sidHex) {
        try {
            touch(HexFormat.of().parseHex(sidHex));
        } catch (IllegalArgumentException notHex) {
            // a token that names no real session was refused before any work was done
        }
    }

    private void touch(byte[] id) {
        jdbc.sql("UPDATE platform.session SET last_seen_at = now() WHERE id = :id AND ended_at IS NULL AND last_seen_at < now() - interval '15 seconds'")
                .param("id", id).update();
    }
}
