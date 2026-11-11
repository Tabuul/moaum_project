package ng.edu.moaum.portal.platform;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Properties;

import org.junit.jupiter.api.Test;
import org.postgresql.util.PSQLException;
import org.postgresql.util.ServerErrorMessage;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.http.ProblemDetail;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.servlet.HandlerMapping;

/**
 * 11 November 2026: a statement the database stops (SQLSTATE 57014) is answered with what stopped it — the portal's read limit, a
 * statement timeout set outside the portal, or a cancel request — and kept for ICT; the read-out says where the database's limit
 * was set. The Admissions dashboard's intake (a write) was stopped on the live portal and answered as the portal's read limit.
 */
class StatementStoppedTest {

    private static QueryTimeoutException stoppedBecause(String words) {
        return new QueryTimeoutException("stopped", new PSQLException(new ServerErrorMessage("SERROR\0C57014\0M" + words + "\0")));
    }

    private static MockHttpServletRequest request(String method, String route, String transaction, Long limit) {
        MockHttpServletRequest r = new MockHttpServletRequest(method, route.replace("{session}/{year}", "2026/2027"));
        r.setAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE, route);
        r.setAttribute(CorrelationIdFilter.STARTED_ATTRIBUTE, System.nanoTime() - 61_000_000_000L);
        if (transaction != null) r.setAttribute(AttributedTransactionManager.TRANSACTION_ATTRIBUTE, transaction);
        if (limit != null) r.setAttribute(AttributedTransactionManager.READ_LIMIT_ATTRIBUTE, limit);
        r.addHeader(AuditContextFilter.ACTIVE_OFFICE_HEADER, "academic");
        return r;
    }

    @Test
    void theCauseIsReadFromTheDatabasesWordsAndTheRequestsTransaction() {
        assertThat(QueryCancellations.cause("canceling statement due to statement timeout", "READ", 90_000L)).isEqualTo(QueryCancellations.Cause.PORTAL_READ_LIMIT);
        assertThat(QueryCancellations.cause("canceling statement due to statement timeout", "WRITE", null)).isEqualTo(QueryCancellations.Cause.DATABASE_STATEMENT_TIMEOUT);
        // a read the portal did not limit (the limit switched off) is the database's limit
        assertThat(QueryCancellations.cause("canceling statement due to statement timeout", "READ", null)).isEqualTo(QueryCancellations.Cause.DATABASE_STATEMENT_TIMEOUT);
        assertThat(QueryCancellations.cause("canceling statement due to statement timeout", null, null)).isEqualTo(QueryCancellations.Cause.DATABASE_STATEMENT_TIMEOUT);
        assertThat(QueryCancellations.cause("canceling statement due to user request", "WRITE", null)).isEqualTo(QueryCancellations.Cause.CANCEL_REQUEST);
        assertThat(QueryCancellations.cause("canceling statement due to conflict with recovery", "READ", 90_000L)).isEqualTo(QueryCancellations.Cause.RECOVERY_CONFLICT);
        assertThat(QueryCancellations.cause(null, "READ", 90_000L)).isEqualTo(QueryCancellations.Cause.OTHER);
    }

    @Test
    void eachStoppedStatementIsAnsweredWithItsCauseAndKeptNewestFirst() {
        QueryCancellations kept = new QueryCancellations();
        ProblemHandler handler = new ProblemHandler(kept);

        // a screen's read cut at the portal's limit: the words of Oct 2026, with the limit and how long it ran
        ProblemDetail read = handler.database(stoppedBecause("canceling statement due to statement timeout"),
                request("GET", "/api/v1/admissions/sessions/{session}/{year}/cycle", "READ", 90_000L));
        assertThat(read.getStatus()).isEqualTo(503);
        assertThat(read.getTitle()).isEqualTo("This screen took too long to read");
        assertThat(read.getDetail()).contains("than the portal allows a screen to read (90 s)").contains("after 61 s");
        assertThat(read.getProperties()).containsEntry("code", "QUERY_TOO_LONG").containsEntry("cause", "PORTAL_READ_LIMIT");

        // the intake of 11 November 2026: a write stopped by a statement timeout the portal never set
        ProblemDetail write = handler.database(stoppedBecause("canceling statement due to statement timeout"),
                request("POST", "/api/v1/student/intake/{session}/{year}", "WRITE", null));
        assertThat(write.getTitle()).isEqualTo("The database stopped this: it ran too long");
        assertThat(write.getDetail()).startsWith("The database stopped this after 61 s: it ran longer than the database allows one statement to run.")
                .doesNotContain("portal allows a screen");
        assertThat(write.getProperties()).containsEntry("code", "QUERY_TOO_LONG").containsEntry("cause", "DATABASE_STATEMENT_TIMEOUT");
        @SuppressWarnings("unchecked") Map<String, Object> remedy = (Map<String, Object>) write.getProperties().get("remedy");
        assertThat(remedy).containsEntry("office", "Directorate of ICT");
        assertThat((String) remedy.get("message")).contains("Slow statements page");

        // a cancel request on a write
        ProblemDetail cancelled = handler.database(stoppedBecause("canceling statement due to user request"),
                request("POST", "/api/v1/admissions/merit/record-many", "WRITE", null));
        assertThat(cancelled.getTitle()).isEqualTo("This was stopped before it finished");
        assertThat(cancelled.getProperties()).containsEntry("code", "QUERY_CANCELLED").containsEntry("cause", "CANCEL_REQUEST");

        List<QueryCancellations.Cancellation> latest = kept.latest();
        assertThat(latest).extracting(QueryCancellations.Cancellation::cause).containsExactly(
                QueryCancellations.Cause.CANCEL_REQUEST, QueryCancellations.Cause.DATABASE_STATEMENT_TIMEOUT, QueryCancellations.Cause.PORTAL_READ_LIMIT);
        assertThat(latest.get(1).route()).isEqualTo("/api/v1/student/intake/{session}/{year}");   // the route, never the address
        assertThat(latest.get(1).transaction()).isEqualTo("WRITE");
        assertThat(latest.get(1).office()).isEqualTo("academic");
        assertThat(latest.get(1).ranForMs()).isBetween(60_000L, 70_000L);
        assertThat(latest.get(2).portalLimitMs()).isEqualTo(90_000L);
        assertThat(latest.get(0).databaseSaid()).isEqualTo("canceling statement due to user request");
        assertThat(kept.total()).isEqualTo(3);
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
    void theReadOutSaysWhereTheDatabasesLimitWasSet() {
        assertThat(ProblemHandler.seconds(90_000L)).isEqualTo("90 s");
        assertThat(ProblemHandler.seconds(1_500L)).isEqualTo("1.5 s");
        assertThat(ProblemHandler.seconds(60_000L)).isEqualTo("60 s");
        assertThat(ProblemHandler.seconds(120_000L)).isEqualTo("2 min");
        assertThat(ProblemHandler.seconds(252_000L)).isEqualTo("4 min 12 s");
        assertThat(DatabaseLimitsController.millis("60", "s")).isEqualTo(60_000L);
        assertThat(DatabaseLimitsController.millis("30000", "ms")).isEqualTo(30_000L);
        assertThat(DatabaseLimitsController.millis("2", "min")).isEqualTo(120_000L);
        assertThat(DatabaseLimitsController.millis("off", "ms")).isZero();

        String none = DatabaseLimitsController.reading(List.of(Map.of("name", "statement_timeout", "setting", "0", "unit", "ms", "source", "default")), 90_000L);
        assertThat(none).isEqualTo("The database places no time limit on one statement of the portal's connections. "
                + "The portal limits a screen's read to 90 s; it places no limit on a write.");
        String onRole = DatabaseLimitsController.reading(List.of(Map.of("name", "statement_timeout", "setting", "60000", "unit", "ms", "source", "user")), 90_000L);
        assertThat(onRole).startsWith("The database stops any statement of the portal's, read or write, after 60 s — set by a setting on the portal's database role");
        assertThat(DatabaseLimitsController.source("client")).contains("DATABASE_URL");
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
