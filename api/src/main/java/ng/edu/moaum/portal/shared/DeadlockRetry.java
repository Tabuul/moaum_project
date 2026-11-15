package ng.edu.moaum.portal.shared;

import java.sql.SQLException;
import java.util.function.Supplier;

import org.springframework.dao.DataAccessException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.dao.TransientDataAccessException;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * A write the database ended for a passing clash with another write is rolled back whole, so it is run again, a few times with a short
 * pause, each time in a fresh transaction. The officer sees the answer, not the clash.
 *
 * <p>What is run again, exactly, as the portal's JdbcTemplate reports PostgreSQL's errors (Spring Framework 7.0.9's default translation,
 * no {@code sql-error-codes.xml}: PgJDBC's errors fall to {@code SQLStateSQLExceptionTranslator}; the portal's own
 * {@code StoppedStatement.Translator} changes 57014 alone):
 * <ul>
 *   <li>a deadlock (SQLSTATE 40P01) and a serialization failure (40001): Spring makes every class 40 error a
 *       {@code PessimisticLockingFailureException} (40001 a {@code CannotAcquireLockException}), a {@link TransientDataAccessException};</li>
 *   <li>a lock not had in time (55P03: a lock_timeout, or NOWAIT), which Spring leaves an {@code UncategorizedSQLException}: run again here
 *       by its SQLSTATE.</li>
 * </ul>
 * Nothing else: not a statement stopped for running too long or cancelled (57014, a {@link QueryTimeoutException}: run again, it would only
 * take as long again), not a refusal (a 422 problem, a database refusal {@code CODE: words} under 23514 or 42501, a domain rule), nor any
 * other failure.
 *
 * <p>The house pattern (a course registration approved while a bulk import writes the audit spine), in one place since V762's review
 * (d62-1). The SIWES desks — the refund desk, the Bursar's hand refund and reopening of a SIWES credit, the withdrawal of a payment never
 * received (raised, decided or cancelled), the bank check, the Bursary's bank list and the decision of its withdrawals, the archive desk
 * and the payment correction desk — take the student's SIWES lock before a payment's row, while the old fees reset, an old fees upload and
 * a gateway confirmation lock the row first and take the lock in the payment's trigger, after it. (A withdrawal decided or cancelled locks
 * the withdrawal's row before the student's SIWES lock, and the decision of a bank list's withdrawals, whichever it is, locks all their rows
 * first, in their numbers' order, and then their students' SIWES locks, by student, then session, the order the list itself takes them in
 * when it is recorded — V762's third and fourth reviews, d62c-1 and d62d-1. An old fees upload takes several students' SIWES locks in its
 * file's order, so it can still meet a list in a circle.) Meeting on one payment at one instant, PostgreSQL ends one of the two with a
 * deadlock error and keeps nothing of it. The desks, the student's SIWES registration and the portal's old fees writers (the upload, its
 * check and approval, the reset, the fee-history reconciliation, the withdrawal of doubles and the put-right) are run again here, up to
 * {@link #ATTEMPTS} tries in all. A confirmation of a payment (a gateway's, or the Bursary's by hand) is not: one that loses keeps nothing,
 * and the payment waits unconfirmed until it is confirmed again.
 *
 * <p>The retry wraps the transaction, never runs inside one: a transaction PostgreSQL has ended is aborted, and nothing more can be done in
 * it. A door that was {@code @Transactional} hands its work to {@link #inTransaction} instead; called inside a transaction already,
 * {@link #run} runs its work once. A database function that catches errors to record a refusal (the bank list's groups and the decision of
 * its withdrawals) lets these three through, so the whole call fails and is run again here.
 */
public final class DeadlockRetry {

    /** the tries in all, the first among them */
    public static final int ATTEMPTS = 4;
    /** the pause before the next try grows by this much each time: 60, 120, 180 ms */
    static final long PAUSE_MS = 60;
    /** a lock not had in time (lock_timeout, NOWAIT): PostgreSQL's SQLSTATE, which Spring leaves uncategorized */
    static final String LOCK_NOT_AVAILABLE = "55P03";

    private DeadlockRetry() {
    }

    /** {@code work} run, and run again on a passing clash, up to {@link #ATTEMPTS} times in all; {@code work} begins and ends its own
     *  transaction (a {@code @Transactional} service method, or {@link #inTransaction}). Inside a transaction already, it runs once. */
    public static <T> T run(Supplier<T> work) {
        if (TransactionSynchronizationManager.isActualTransactionActive()) {
            return work.get();   // the transaction it would run in again is the one the clash ended
        }
        DataAccessException last = null;
        for (int attempt = 1; attempt <= ATTEMPTS; attempt++) {
            try {
                return work.get();
            } catch (DataAccessException e) {
                if (!passing(e)) {
                    throw e;
                }
                last = e;
                if (attempt == ATTEMPTS) {
                    break;
                }
                try {
                    Thread.sleep(PAUSE_MS * attempt);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        throw last;
    }

    /** {@code work} in a transaction of its own, run again in a fresh one on a passing clash: for a door that was {@code @Transactional} */
    public static <T> T inTransaction(TransactionTemplate tx, Supplier<T> work) {
        return run(() -> tx.execute(status -> work.get()));
    }

    /** a clash that passes: a deadlock or a serialization failure (Spring's transient errors, 40P01 and 40001 from PostgreSQL), or a lock
     *  not had in time (55P03, by its SQLSTATE) — never a statement stopped for its time (57014) */
    static boolean passing(DataAccessException e) {
        if (e instanceof QueryTimeoutException) {
            return false;
        }
        return e instanceof TransientDataAccessException || LOCK_NOT_AVAILABLE.equals(sqlState(e));
    }

    /** the SQLSTATE of the first SQLException in a failure's causes, or null */
    static String sqlState(Throwable e) {
        for (Throwable c = e; c != null; c = c.getCause() == c ? null : c.getCause()) {
            if (c instanceof SQLException s) {
                return s.getSQLState();
            }
        }
        return null;
    }
}
