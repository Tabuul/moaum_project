package ng.edu.moaum.portal.platform;

import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import org.springframework.stereotype.Component;

/**
 * 11 November 2026: the statements the database stopped before they finished (SQLSTATE 57014) on a request this API instance
 * answered — the last fifty since the instance started, newest first — so the Directorate of ICT reads on its Slow statements page
 * what stopped a screen, for how long it ran and on which request, without reading the server's logs. Each instance keeps its own
 * list and a redeploy empties it; a scheduled job's or background work's stopped statements are in the server's logs alone.
 *
 * <p>SQLSTATE 57014 is the same for a statement timeout and for a cancel request, and the API's own read limit
 * ({@link AttributedTransactionManager}) is itself a statement timeout; the database's message tells them apart
 * ("canceling statement due to statement timeout" / "… due to user request", in the server's English messages), and the portal's
 * own limit on the failing statement is noted where it failed ({@link StoppedStatement}). Nothing personal is kept: the request's
 * route pattern (never its address, which can carry a student's id), the acting office and the request's reference.
 */
@Component
public class QueryCancellations {

    /** what stopped the statement */
    public enum Cause {
        /** a screen's read, cut at the portal's own read limit (moaum.db.request-read-timeout-ms) */
        PORTAL_READ_LIMIT,
        /** the PAYDirect door's own limit: the statement_timeout its pool's connections carry (PayDirectLane) */
        PAYDIRECT_DOOR_LIMIT,
        /** a statement timeout other than the portal's own: set on the server, the database, the role or the connection's options */
        DATABASE_STATEMENT_TIMEOUT,
        /** a cancel request: pg_cancel_backend, or a client's query timeout */
        CANCEL_REQUEST,
        /** a reason the database worded otherwise */
        OTHER
    }

    /** one statement stopped: when, why, under which transaction and limit, how long the request had run, on which route */
    public record Cancellation(Instant at, Cause cause, String transaction, Long portalLimitMs, Long ranForMs, String method,
                               String route, String office, String reference, String databaseSaid) {
    }

    static final int KEPT = 50;

    private final Deque<Cancellation> kept = new ArrayDeque<>();
    private final AtomicLong total = new AtomicLong();
    private final Instant since = Instant.now();

    /**
     * The cause, read from the database's own words and the portal's limit that was on the failing statement (noted where it
     * failed): a statement timeout under a screen's read limit or the PAYDirect door's is the portal's own; any other was set
     * outside the portal.
     */
    public static Cause cause(String databaseSaid, StoppedStatement.Limit portalLimit) {
        String said = databaseSaid == null ? "" : databaseSaid.toLowerCase(java.util.Locale.ROOT);
        if (said.contains("statement timeout")) {
            return portalLimit == StoppedStatement.Limit.SCREEN_READ ? Cause.PORTAL_READ_LIMIT
                    : portalLimit == StoppedStatement.Limit.PAYDIRECT_DOOR ? Cause.PAYDIRECT_DOOR_LIMIT : Cause.DATABASE_STATEMENT_TIMEOUT;
        }
        if (said.contains("user request")) {
            return Cause.CANCEL_REQUEST;
        }
        return Cause.OTHER;
    }

    public void record(Cancellation c) {
        total.incrementAndGet();
        synchronized (kept) {
            kept.addFirst(c);
            while (kept.size() > KEPT) {
                kept.removeLast();
            }
        }
    }

    /** the kept statements, newest first */
    public List<Cancellation> latest() {
        synchronized (kept) {
            return new ArrayList<>(kept);
        }
    }

    /** every statement stopped since the API started, kept or not */
    public long total() {
        return total.get();
    }

    public Instant since() {
        return since;
    }
}
