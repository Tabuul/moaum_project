package ng.edu.moaum.portal.platform;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.postgresql.util.PSQLException;
import org.postgresql.util.ServerErrorMessage;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.http.ProblemDetail;
import org.springframework.jdbc.support.SQLExceptionTranslator;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import org.springframework.web.servlet.HandlerMapping;

/**
 * 11 November 2026: a statement the database stops (SQLSTATE 57014) is answered with what stopped it — the portal's read limit, the
 * PAYDirect door's, a statement timeout set outside the portal, or a cancel request — noted where the statement failed, and kept
 * for ICT; the read-out says where each limit was set. The Admissions dashboard's intake (a write) was stopped on the live portal
 * and answered as the portal's read limit.
 */
class StatementStoppedTest {

    @AfterEach
    void clearThreadState() {
        TransactionSynchronizationManager.setActualTransactionActive(false);
        TransactionSynchronizationManager.setCurrentTransactionReadOnly(false);
        RequestContextHolder.resetRequestAttributes();
        AuditContextHolder.clear();
    }

    private static PSQLException said(String words) {
        return new PSQLException(new ServerErrorMessage("SERROR\0C57014\0M" + words + "\0"));
    }

    private static MockHttpServletRequest request(String method, String route) {
        MockHttpServletRequest r = new MockHttpServletRequest(method, route.replace("{session}/{year}", "2026/2027"));
        r.setAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE, route);
        r.setAttribute(CorrelationIdFilter.STARTED_ATTRIBUTE, System.nanoTime() - 61_000_000_000L);
        return r;
    }

    @Test
    void theCauseIsReadFromTheDatabasesWordsAndThePortalsLimitOnTheStatement() {
        assertThat(QueryCancellations.cause("canceling statement due to statement timeout", StoppedStatement.Limit.SCREEN_READ)).isEqualTo(QueryCancellations.Cause.PORTAL_READ_LIMIT);
        assertThat(QueryCancellations.cause("canceling statement due to statement timeout", StoppedStatement.Limit.PAYDIRECT_DOOR)).isEqualTo(QueryCancellations.Cause.PAYDIRECT_DOOR_LIMIT);
        assertThat(QueryCancellations.cause("canceling statement due to statement timeout", null)).isEqualTo(QueryCancellations.Cause.DATABASE_STATEMENT_TIMEOUT);
        assertThat(QueryCancellations.cause("canceling statement due to user request", StoppedStatement.Limit.SCREEN_READ)).isEqualTo(QueryCancellations.Cause.CANCEL_REQUEST);
        assertThat(QueryCancellations.cause(null, null)).isEqualTo(QueryCancellations.Cause.OTHER);
    }

    /** the translator notes the portal's limit only where it was on the failing statement: a read-only transaction on a request's thread */
    @Test
    void theTranslatorNotesTheLimitWhereTheStatementFailed() {
        SQLExceptionTranslator fallback = (task, sql, ex) -> new QueryTimeoutException("fallback", ex);
        StoppedStatement.Translator portal = new StoppedStatement.Translator(fallback, 90_000L, null);

        // a screen's read on the request's thread
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(new MockHttpServletRequest()));
        TransactionSynchronizationManager.setActualTransactionActive(true);
        TransactionSynchronizationManager.setCurrentTransactionReadOnly(true);
        StoppedStatement read = (StoppedStatement) portal.translate("read", "SELECT 1", said("canceling statement due to statement timeout"));
        assertThat(read.transaction()).isEqualTo("READ");
        assertThat(read.portalLimitMs()).isEqualTo(90_000L);
        assertThat(read.portalLimit()).isEqualTo(StoppedStatement.Limit.SCREEN_READ);

        // the same read on a pool thread (FigureCache, FinanceSummaryCache): no request, so no portal limit was on its connection
        RequestContextHolder.resetRequestAttributes();
        StoppedStatement pooled = (StoppedStatement) portal.translate("read", "SELECT 1", said("canceling statement due to statement timeout"));
        assertThat(pooled.transaction()).isEqualTo("READ");
        assertThat(pooled.portalLimitMs()).isNull();
        assertThat(pooled.portalLimit()).isNull();

        // a write on the request's thread: the portal places no limit on a write
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(new MockHttpServletRequest()));
        TransactionSynchronizationManager.setCurrentTransactionReadOnly(false);
        StoppedStatement write = (StoppedStatement) portal.translate("write", "SELECT 1", said("canceling statement due to statement timeout"));
        assertThat(write.transaction()).isEqualTo("WRITE");
        assertThat(write.portalLimit()).isNull();

        // outside any transaction
        TransactionSynchronizationManager.setActualTransactionActive(false);
        assertThat(((StoppedStatement) portal.translate("x", "SELECT 1", said("canceling statement due to user request"))).transaction()).isNull();

        // the PAYDirect door's connections carry its own limit, whatever the transaction
        StoppedStatement door = (StoppedStatement) new StoppedStatement.Translator(fallback, 0, 8_000L)
                .translate("door", "SELECT 1", said("canceling statement due to statement timeout"));
        assertThat(door.portalLimit()).isEqualTo(StoppedStatement.Limit.PAYDIRECT_DOOR);
        assertThat(door.portalLimitMs()).isEqualTo(8_000L);

        // every other state goes to the translator it wraps
        DataAccessException other = portal.translate("x", "SELECT 1", new SQLException("unique", "23505"));
        assertThat(other).isNotInstanceOf(StoppedStatement.class).hasMessage("fallback");
    }

    @Test
    void eachStoppedStatementIsAnsweredWithItsCauseAndKeptNewestFirst() {
        QueryCancellations kept = new QueryCancellations();
        ProblemHandler handler = new ProblemHandler(kept);
        UUID officer = UUID.randomUUID();

        // a screen's read cut at the portal's limit: the words of Oct 2026, with the limit and how long it ran
        ProblemDetail read = handler.database(new StoppedStatement("x", said("canceling statement due to statement timeout"), "READ", 90_000L,
                StoppedStatement.Limit.SCREEN_READ), request("GET", "/api/v1/admissions/sessions/{session}/{year}/cycle"));
        assertThat(read.getStatus()).isEqualTo(503);
        assertThat(read.getTitle()).isEqualTo("This screen took too long to read");
        assertThat(read.getDetail()).contains("than the portal allows a screen to read (90 s)").contains("after 61 s");
        assertThat(read.getProperties()).containsEntry("code", "QUERY_TOO_LONG").containsEntry("cause", "PORTAL_READ_LIMIT");

        // the intake of 11 November 2026: a write stopped by a statement timeout the portal never set — the office the request acted as
        ProblemDetail write = AuditContextHolder.with(new AuditContext(officer, "academic", "StatementStoppedTest", null, null),
                () -> handler.database(new StoppedStatement("x", said("canceling statement due to statement timeout"), "WRITE", null, null),
                        request("POST", "/api/v1/student/intake/{session}/{year}")));
        assertThat(write.getTitle()).isEqualTo("The database stopped this: it ran too long");
        assertThat(write.getDetail()).startsWith("The database stopped this after 61 s: it ran longer than the database allows one statement to run.")
                .doesNotContain("portal allows a screen");
        assertThat(write.getProperties()).containsEntry("code", "QUERY_TOO_LONG").containsEntry("cause", "DATABASE_STATEMENT_TIMEOUT");
        @SuppressWarnings("unchecked") Map<String, Object> remedy = (Map<String, Object>) write.getProperties().get("remedy");
        assertThat(remedy).containsEntry("office", "Directorate of ICT");
        assertThat((String) remedy.get("message")).contains("Slow statements page");

        // a cancel request on a write
        ProblemDetail cancelled = handler.database(new StoppedStatement("x", said("canceling statement due to user request"), "WRITE", null, null),
                request("POST", "/api/v1/admissions/merit/record-many"));
        assertThat(cancelled.getTitle()).isEqualTo("This was stopped before it finished");
        assertThat(cancelled.getDetail()).startsWith("A cancel request stopped this 61 s in, before it finished.");
        assertThat(cancelled.getProperties()).containsEntry("code", "QUERY_CANCELLED").containsEntry("cause", "CANCEL_REQUEST");

        // a read that failed on a pool thread under the request's read-only transaction: the request's note does not decide it
        MockHttpServletRequest pooledRequest = request("GET", "/api/v1/analytics/finance/summary");
        pooledRequest.setAttribute(AttributedTransactionManager.TRANSACTION_ATTRIBUTE, "READ");
        pooledRequest.setAttribute(AttributedTransactionManager.READ_LIMIT_ATTRIBUTE, 90_000L);
        ProblemDetail pooled = handler.database(new StoppedStatement("x", said("canceling statement due to statement timeout"), "READ", null, null), pooledRequest);
        assertThat(pooled.getProperties()).containsEntry("cause", "DATABASE_STATEMENT_TIMEOUT");

        // a statement that did not pass the portal's JdbcTemplate: the request's note of its transaction is the fallback
        MockHttpServletRequest raw = request("GET", "/api/v1/dbops/master-report");
        raw.setAttribute(AttributedTransactionManager.TRANSACTION_ATTRIBUTE, "READ");
        raw.setAttribute(AttributedTransactionManager.READ_LIMIT_ATTRIBUTE, 90_000L);
        assertThat(handler.database(new QueryTimeoutException("x", said("canceling statement due to statement timeout")), raw).getProperties())
                .containsEntry("cause", "PORTAL_READ_LIMIT");

        // the PAYDirect door's own limit
        ProblemDetail door = handler.database(new StoppedStatement("x", said("canceling statement due to statement timeout"), "WRITE", 8_000L,
                StoppedStatement.Limit.PAYDIRECT_DOOR), request("POST", "/api/v1/payments/paydirect"));
        assertThat(door.getProperties()).containsEntry("code", "QUERY_TOO_LONG").containsEntry("cause", "PAYDIRECT_DOOR_LIMIT");
        assertThat(door.getDetail()).contains("(8 s)");

        List<QueryCancellations.Cancellation> latest = kept.latest();
        assertThat(latest).extracting(QueryCancellations.Cancellation::cause).containsExactly(
                QueryCancellations.Cause.PAYDIRECT_DOOR_LIMIT, QueryCancellations.Cause.PORTAL_READ_LIMIT, QueryCancellations.Cause.DATABASE_STATEMENT_TIMEOUT,
                QueryCancellations.Cause.CANCEL_REQUEST, QueryCancellations.Cause.DATABASE_STATEMENT_TIMEOUT, QueryCancellations.Cause.PORTAL_READ_LIMIT);
        QueryCancellations.Cancellation intake = latest.get(4);
        assertThat(intake.route()).isEqualTo("/api/v1/student/intake/{session}/{year}");   // the route, never the address
        assertThat(intake.transaction()).isEqualTo("WRITE");
        assertThat(intake.office()).isEqualTo("academic");
        assertThat(intake.portalLimitMs()).isNull();
        assertThat(intake.ranForMs()).isBetween(60_000L, 70_000L);
        assertThat(latest.get(2).portalLimitMs()).as("a limit that did not stop the statement is not kept as its cause").isNull();
        assertThat(latest.get(5).portalLimitMs()).isEqualTo(90_000L);
        assertThat(latest.get(5).office()).as("no audit context: no office").isNull();
        assertThat(latest.get(3).databaseSaid()).isEqualTo("canceling statement due to user request");
        assertThat(kept.total()).isEqualTo(6);
    }

    @Test
    void fiftyAreKeptAndEveryOneIsCounted() {
        QueryCancellations kept = new QueryCancellations();
        for (int i = 0; i < 60; i++) {
            kept.record(new QueryCancellations.Cancellation(java.time.Instant.now(), QueryCancellations.Cause.OTHER, "READ", null, (long) i,
                    "GET", "/r" + i, null, "ref" + i, "x"));
        }
        assertThat(kept.latest()).hasSize(QueryCancellations.KEPT);
        assertThat(kept.latest().get(0).route()).isEqualTo("/r59");
        assertThat(kept.latest().get(QueryCancellations.KEPT - 1).route()).isEqualTo("/r10");
        assertThat(kept.total()).isEqualTo(60);
    }

    @Test
    void theReadOutSaysWhereEachLimitWasSet() {
        assertThat(ProblemHandler.seconds(90_000L)).isEqualTo("90 s");
        assertThat(ProblemHandler.seconds(1_500L)).isEqualTo("1.5 s");
        assertThat(ProblemHandler.seconds(60_000L)).isEqualTo("60 s");
        assertThat(ProblemHandler.seconds(120_000L)).isEqualTo("2 min");
        assertThat(ProblemHandler.seconds(252_000L)).isEqualTo("4 min 12 s");
        assertThat(DatabaseLimitsController.millis("60", "s")).isEqualTo(60_000L);
        assertThat(DatabaseLimitsController.millis("30000", "ms")).isEqualTo(30_000L);
        assertThat(DatabaseLimitsController.millis("2", "min")).isEqualTo(120_000L);
        assertThat(DatabaseLimitsController.millis("off", "ms")).isZero();

        List<Map<String, Object>> none = List.of(Map.of("name", "statement_timeout", "setting", "0", "unit", "ms", "source", "default"),
                Map.of("name", "lock_timeout", "setting", "0", "unit", "ms", "source", "default"));
        assertThat(DatabaseLimitsController.reading(none, 90_000L, null, null, 8_000L)).isEqualTo(
                "The database places no time limit on one statement of the portal's connections. "
                        + "A screen's read runs under the portal's own limit of 90 s. "
                        + "The portal places no limit of its own on a write. "
                        + "The PAYDirect door's own connections stop a statement after 8 s and a wait for a lock after 4 s.");

        // a limit on the role: it stops writes; a screen's read runs under the portal's instead; other limits named
        List<Map<String, Object>> onRole = List.of(Map.of("name", "statement_timeout", "setting", "60000", "unit", "ms", "source", "user"),
                Map.of("name", "transaction_timeout", "setting", "120000", "unit", "ms", "source", "global"),
                Map.of("name", "lock_timeout", "setting", "5", "unit", "s", "source", "database"));
        String reading = DatabaseLimitsController.reading(onRole, 90_000L, null, null, 8_000L);
        assertThat(reading).startsWith("The database stops the portal's statements after 60 s — set by a setting on the portal's database role")
                .contains("A screen's read runs under the portal's own limit of 90 s, which takes the place of the database's for that read.")
                .contains("The portal places no limit of its own on a write: the database's applies.")
                .contains("The database also ends any transaction of the portal's, read or write, and closes its connection, after 2 min — set by a setting on every role")
                .contains("The database also stops a statement that waits for a lock after 5 s — set by a setting on the database");
        // the portal's own query timeout limits writes too
        assertThat(DatabaseLimitsController.reading(none, 90_000L, 30, null, 8_000L))
                .contains("The portal also limits every statement, read or write, to 30 s (its query timeout).")
                .doesNotContain("no limit of its own on a write");
        assertThat(DatabaseLimitsController.source("client")).contains("DATABASE_URL").doesNotContain("PGOPTIONS");
        assertThat(DatabaseLimitsController.source("configuration file")).contains("postgresql.conf");

        // the connection's options alone, never the rest of the address
        assertThat(DatabaseLimitsController.options("jdbc:postgresql://db:5432/railway?sslmode=require&options=-c%20statement_timeout%3D60000", new Properties()))
                .isEqualTo("-c statement_timeout=60000");
        assertThat(DatabaseLimitsController.options("jdbc:postgresql://db:5432/railway?sslmode=require", new Properties())).isNull();
        Properties p = new Properties();
        p.setProperty("options", "-c statement_timeout=5000");
        assertThat(DatabaseLimitsController.options("jdbc:postgresql://db/x", p)).isEqualTo("-c statement_timeout=5000");
    }
}
