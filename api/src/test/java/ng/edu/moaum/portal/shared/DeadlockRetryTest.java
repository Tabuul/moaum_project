package ng.edu.moaum.portal.shared;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.sql.SQLException;
import java.util.concurrent.atomic.AtomicInteger;

import ng.edu.moaum.portal.platform.StoppedStatement;

import org.junit.jupiter.api.Test;
import org.springframework.dao.CannotAcquireLockException;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.PessimisticLockingFailureException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.UncategorizedSQLException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

/** V762's review (d62-1, d62b-3): a passing clash run again in a fresh transaction, a few times; a refusal never */
class DeadlockRetryTest {

    @Test
    void aDeadlockIsRunAgainUntilItGoesThrough() {
        AtomicInteger tries = new AtomicInteger();
        String answer = DeadlockRetry.run(() -> {
            if (tries.incrementAndGet() < 3) {
                throw new PessimisticLockingFailureException("ERROR: deadlock detected");
            }
            return "approved";
        });
        assertThat(answer).isEqualTo("approved");
        assertThat(tries).hasValue(3);
    }

    @Test
    void itGivesUpAfterTheLimitWithTheLastClash() {
        AtomicInteger tries = new AtomicInteger();
        assertThatThrownBy(() -> DeadlockRetry.run(() -> {
            throw new CannotAcquireLockException("could not serialize access, try " + tries.incrementAndGet());
        })).isInstanceOf(CannotAcquireLockException.class).hasMessage("could not serialize access, try 4");
        assertThat(tries).hasValue(DeadlockRetry.ATTEMPTS);
    }

    @Test
    void aLockNotHadInTimeIsRunAgainByItsSqlState() {
        AtomicInteger tries = new AtomicInteger();
        String answer = DeadlockRetry.run(() -> {
            if (tries.incrementAndGet() < 2) {
                throw new UncategorizedSQLException("approve", "SELECT 1", new SQLException("ERROR: canceling statement due to lock timeout", "55P03"));
            }
            return "approved";
        });
        assertThat(answer).isEqualTo("approved");
        assertThat(tries).hasValue(2);
        // any other uncategorized failure is not run again
        assertThatThrownBy(() -> DeadlockRetry.run(() -> {
            tries.incrementAndGet();
            throw new UncategorizedSQLException("approve", "SELECT 1", new SQLException("ERROR: no data found", "P0002"));
        })).isInstanceOf(UncategorizedSQLException.class);
        assertThat(tries).hasValue(3);
    }

    @Test
    void aRefusalIsNeverRunAgain() {
        AtomicInteger tries = new AtomicInteger();
        // the database's refusal (CODE: words, SQLSTATE 23514), as ProblemHandler turns it into a 422 problem
        assertThatThrownBy(() -> DeadlockRetry.run(() -> {
            tries.incrementAndGet();
            throw new DataIntegrityViolationException("REFUND_SIWES_GIVEN_BACK: payment MOAUM-FEE-X is a SIWES registration fee of NGN 4000");
        })).isInstanceOf(DataIntegrityViolationException.class);
        assertThat(tries).hasValue(1);
        // a 422 problem the door raises itself
        assertThatThrownBy(() -> DeadlockRetry.run(() -> {
            tries.incrementAndGet();
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "PAR_SETTLED");
        })).isInstanceOf(ResponseStatusException.class);
        assertThat(tries).hasValue(2);
        // a statement the database stopped for running too long would only take as long again
        assertThatThrownBy(() -> DeadlockRetry.run(() -> {
            tries.incrementAndGet();
            throw new QueryTimeoutException("canceling statement due to statement timeout");
        })).isInstanceOf(QueryTimeoutException.class);
        assertThat(tries).hasValue(3);
    }

    /** the portal's JdbcTemplate as PlatformConfig leaves it: Spring's own translator (no sql-error-codes.xml), StoppedStatement's
     *  translator before it for 57014 */
    private static final class PortalTemplate extends JdbcTemplate {
        PortalTemplate() {
            setExceptionTranslator(new StoppedStatement.Translator(getExceptionTranslator(), 0, null));
        }

        DataAccessException reported(String sqlState) {
            // PgJDBC's PSQLException is a plain SQLException with the server's SQLSTATE, as here
            return translateException("DeadlockRetryTest", "SELECT 1", new SQLException("ERROR: " + sqlState, sqlState));
        }
    }

    /** each SQLSTATE as the portal's JdbcTemplate reports it, thrown once: how many tries it took (2: run again; 1: not) */
    private static int tries(PortalTemplate template, String sqlState) {
        AtomicInteger tries = new AtomicInteger();
        try {
            DeadlockRetry.run(() -> {
                if (tries.incrementAndGet() == 1) {
                    throw template.reported(sqlState);
                }
                return "done";
            });
        } catch (DataAccessException refused) {
            // not run again: the first failure itself
        }
        return tries.get();
    }

    @Test
    void whatIsRunAgainIsExactlyADeadlockASerializationFailureOrALockNotHadInTimeAsTheJdbcTemplateReportsThem() {
        PortalTemplate template = new PortalTemplate();
        // Spring Framework's translation, as the doors meet it
        assertThat(template.reported("40P01")).isInstanceOf(PessimisticLockingFailureException.class);
        assertThat(template.reported("40001")).isInstanceOf(CannotAcquireLockException.class);
        assertThat(template.reported("55P03")).isInstanceOf(UncategorizedSQLException.class);
        assertThat(template.reported("57014")).isInstanceOf(StoppedStatement.class);
        assertThat(template.reported("23514")).isInstanceOf(DataIntegrityViolationException.class);
        // run again: a deadlock, a serialization failure, a lock not had in time
        assertThat(tries(template, "40P01")).isEqualTo(2);
        assertThat(tries(template, "40001")).isEqualTo(2);
        assertThat(tries(template, "55P03")).isEqualTo(2);
        // never: a statement stopped (57014), a refusal (23514 check, 42501 office, P0001 raised, 23505 duplicate), a function's own error
        for (String never : new String[] {"57014", "23514", "42501", "P0001", "P0002", "23505", "22023"}) {
            assertThat(tries(template, never)).as(never).isEqualTo(1);
        }
    }

    @Test
    void insideATransactionItRunsOnce() {
        AtomicInteger tries = new AtomicInteger();
        TransactionSynchronizationManager.setActualTransactionActive(true);
        try {
            assertThatThrownBy(() -> DeadlockRetry.run(() -> {
                tries.incrementAndGet();
                throw new PessimisticLockingFailureException("ERROR: deadlock detected");
            })).isInstanceOf(PessimisticLockingFailureException.class);
        } finally {
            TransactionSynchronizationManager.setActualTransactionActive(false);
        }
        assertThat(tries).hasValue(1);
    }

    @Test
    void eachTryIsAFreshTransactionAndTheFailedOnesAreRolledBack() {
        Counting manager = new Counting();
        AtomicInteger tries = new AtomicInteger();
        String answer = DeadlockRetry.inTransaction(new TransactionTemplate(manager), () -> {
            if (tries.incrementAndGet() < 3) {
                throw new PessimisticLockingFailureException("ERROR: deadlock detected");
            }
            return "archived";
        });
        assertThat(answer).isEqualTo("archived");
        assertThat(manager.begun).hasValue(3);
        assertThat(manager.rolledBack).hasValue(2);
        assertThat(manager.committed).hasValue(1);
    }

    /** a transaction manager that counts what it is asked to do */
    private static final class Counting implements PlatformTransactionManager {
        final AtomicInteger begun = new AtomicInteger();
        final AtomicInteger committed = new AtomicInteger();
        final AtomicInteger rolledBack = new AtomicInteger();

        @Override
        public TransactionStatus getTransaction(TransactionDefinition definition) {
            begun.incrementAndGet();
            return new SimpleTransactionStatus(true);
        }

        @Override
        public void commit(TransactionStatus status) {
            committed.incrementAndGet();
        }

        @Override
        public void rollback(TransactionStatus status) {
            rolledBack.incrementAndGet();
        }
    }
}
