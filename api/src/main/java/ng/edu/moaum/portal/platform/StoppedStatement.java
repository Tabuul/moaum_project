package ng.edu.moaum.portal.platform;

import java.sql.SQLException;

import org.springframework.dao.DataAccessException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.jdbc.support.SQLExceptionTranslator;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.context.request.RequestContextHolder;

/**
 * 11 November 2026: a statement the database stopped (SQLSTATE 57014), with the transaction it ran in and the portal's own limit
 * on it, noted where it failed — on the thread that ran it, in its own transaction — not read afterwards from the request.
 *
 * <p>The request's note of the transaction it began last (AttributedTransactionManager) is wrong for a statement that ran on a
 * pool thread (FigureCache, FinanceSummaryCache, ReadinessSnapshot: no request there, so no portal limit on its connection),
 * in an outer transaction after an inner one ended, or on the PAYDirect door's own pool (whose connections carry the door's own
 * statement_timeout). The {@link Translator} is put on the portal's JdbcTemplate (PlatformConfig) and on the door's, and turns
 * each 57014 into this exception; ProblemHandler reads it. It stays a QueryTimeoutException, as Spring translated 57014 before.
 */
public class StoppedStatement extends QueryTimeoutException {

    /** the portal's own limit that was on the statement */
    public enum Limit {
        /** a screen's read: the read limit AttributedTransactionManager places on a request's read-only transaction */
        SCREEN_READ,
        /** the PAYDirect door's own connections (PayDirectLane: statement_timeout in the pool's options) */
        PAYDIRECT_DOOR
    }

    private final String transaction;
    private final Long portalLimitMs;
    private final Limit portalLimit;

    public StoppedStatement(String message, SQLException cause, String transaction, Long portalLimitMs, Limit portalLimit) {
        super(message, cause);
        this.transaction = transaction;
        this.portalLimitMs = portalLimitMs;
        this.portalLimit = portalLimit;
    }

    /** READ, WRITE, or null where the statement ran outside a transaction */
    public String transaction() {
        return transaction;
    }

    /** the portal's own limit on the statement, in milliseconds; null where the portal placed none */
    public Long portalLimitMs() {
        return portalLimitMs;
    }

    public Limit portalLimit() {
        return portalLimit;
    }

    /** the first StoppedStatement in a throwable's chain, or null */
    public static StoppedStatement in(Throwable t) {
        for (Throwable c = t; c != null; c = c.getCause() == c ? null : c.getCause()) {
            if (c instanceof StoppedStatement s) {
                return s;
            }
        }
        return null;
    }

    /**
     * Turns SQLSTATE 57014 into a StoppedStatement noted on the failing statement's own thread; every other SQLException goes to
     * the translator it wraps. The portal's read limit was on the statement only when it ran in a read-only transaction begun on a
     * request's thread (exactly where AttributedTransactionManager places it); a door's limit is on every statement of its pool.
     */
    public static final class Translator implements SQLExceptionTranslator {

        private final SQLExceptionTranslator delegate;
        private final long readLimitMs;
        private final Long doorLimitMs;

        public Translator(SQLExceptionTranslator delegate, long readLimitMs, Long doorLimitMs) {
            this.delegate = delegate;
            this.readLimitMs = readLimitMs;
            this.doorLimitMs = doorLimitMs;
        }

        @Override
        public DataAccessException translate(String task, String sql, SQLException ex) {
            if (!"57014".equals(ex.getSQLState())) {
                return delegate.translate(task, sql, ex);
            }
            boolean active = TransactionSynchronizationManager.isActualTransactionActive();
            String transaction = active ? (TransactionSynchronizationManager.isCurrentTransactionReadOnly() ? "READ" : "WRITE") : null;
            Long limit = null;
            Limit kind = null;
            if (doorLimitMs != null) {
                limit = doorLimitMs;
                kind = Limit.PAYDIRECT_DOOR;
            } else if ("READ".equals(transaction) && readLimitMs > 0 && RequestContextHolder.getRequestAttributes() != null) {
                limit = readLimitMs;
                kind = Limit.SCREEN_READ;
            }
            return new StoppedStatement((task == null ? "" : task + "; ") + ex.getMessage(), ex, transaction, limit, kind);
        }
    }
}
