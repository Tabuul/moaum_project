package ng.edu.moaum.portal.platform;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;

import javax.sql.DataSource;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.jdbc.datasource.DataSourceUtils;
import org.springframework.jdbc.support.JdbcTransactionManager;
import org.springframework.transaction.TransactionDefinition;

/**
 * Every transaction begins by placing the audit context on the connection.
 *
 * <p>V002 makes attribution a property of the database: the audit trigger
 * reads {@code moaum.actor_id} and {@code moaum.actor_office} from the
 * transaction and refuses the write when they are absent. This is the other
 * half: {@code SET LOCAL} (via {@code set_config(..., true)}) immediately
 * after the transaction opens, so the settings live exactly as long as the
 * transaction and can never leak into a pooled connection's next borrower.
 *
 * <p>When no context is present the transaction still opens — reads need no
 * attribution — and any write to an attached table is refused by the
 * database, which is the design working, not failing.
 */
public class AttributedTransactionManager extends JdbcTransactionManager {

    /** Oct 2026: how long a screen's read-only transaction may run (0: as long as it likes) */
    private final long requestReadTimeoutMs;

    /** 11 Nov 2026: the kind of the request's latest transaction, READ or WRITE — so a statement the database stops is told apart */
    public static final String TRANSACTION_ATTRIBUTE = AttributedTransactionManager.class.getName() + ".transaction";
    /** 11 Nov 2026: the read limit placed on the request's latest transaction, in milliseconds; absent where none was placed */
    public static final String READ_LIMIT_ATTRIBUTE = AttributedTransactionManager.class.getName() + ".readLimitMs";

    public AttributedTransactionManager(DataSource dataSource) {
        this(dataSource, 0);
    }

    public AttributedTransactionManager(DataSource dataSource, long requestReadTimeoutMs) {
        super(dataSource);
        this.requestReadTimeoutMs = Math.max(0, requestReadTimeoutMs);
    }

    /** a transaction begun for a request of a screen, not for a scheduled job */
    private static boolean inRequest() {
        return org.springframework.web.context.request.RequestContextHolder.getRequestAttributes() != null;
    }

    @Override
    protected void doBegin(Object transaction, TransactionDefinition definition) {
        super.doBegin(transaction, definition);
        // 11 Nov 2026: the request notes which transaction it began and whether the portal limited it, so a statement the database
        // stops (SQLSTATE 57014) is told as the portal's read limit or as a limit set outside the portal (ProblemHandler)
        org.springframework.web.context.request.RequestAttributes attributes =
                org.springframework.web.context.request.RequestContextHolder.getRequestAttributes();
        if (attributes != null) {
            boolean limited = requestReadTimeoutMs > 0 && definition.isReadOnly();
            attributes.setAttribute(TRANSACTION_ATTRIBUTE, definition.isReadOnly() ? "READ" : "WRITE",
                    org.springframework.web.context.request.RequestAttributes.SCOPE_REQUEST);
            if (limited) {
                attributes.setAttribute(READ_LIMIT_ATTRIBUTE, requestReadTimeoutMs, org.springframework.web.context.request.RequestAttributes.SCOPE_REQUEST);
            } else {
                attributes.removeAttribute(READ_LIMIT_ATTRIBUTE, org.springframework.web.context.request.RequestAttributes.SCOPE_REQUEST);
            }
        }
        // Oct 2026: a screen's read is cut short past the limit rather than holding one of the portal's few connections for
        // minutes while other requests (Interswitch's among them) wait for one; a scheduled job's reads are not limited
        if (requestReadTimeoutMs > 0 && definition.isReadOnly() && inRequest()) {
            Connection connection = DataSourceUtils.getConnection(obtainDataSource());
            try (PreparedStatement statement = connection.prepareStatement("SELECT set_config('statement_timeout', ?, true)")) {
                statement.setString(1, requestReadTimeoutMs + "ms");
                statement.execute();
            } catch (SQLException e) {
                throw new DataAccessResourceFailureException("could not limit the read", e);
            } finally {
                DataSourceUtils.releaseConnection(connection, obtainDataSource());
            }
        }
        AuditContextHolder.current().ifPresent(context -> {
            Connection connection = DataSourceUtils.getConnection(obtainDataSource());
            try {
                place(connection, context);
            } catch (SQLException e) {
                throw new DataAccessResourceFailureException("could not place the audit context on the transaction", e);
            } finally {
                DataSourceUtils.releaseConnection(connection, obtainDataSource());
            }
        });
        // V521: ICT Support viewing a student's portal — the database refuses any write the request attempts, even from a read
        if (SupportView.active()) {
            Connection connection = DataSourceUtils.getConnection(obtainDataSource());
            try (PreparedStatement statement = connection.prepareStatement("SET TRANSACTION READ ONLY")) {
                statement.execute();
            } catch (SQLException e) {
                throw new DataAccessResourceFailureException("could not make the support view read-only", e);
            } finally {
                DataSourceUtils.releaseConnection(connection, obtainDataSource());
            }
        }
    }

    private static void place(Connection connection, AuditContext context) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT set_config('moaum.actor_id', ?, true), set_config('moaum.actor_office', ?, true), "
                        + "set_config('moaum.reason', ?, true), set_config('moaum.correlation_id', ?, true), "
                        + "set_config('moaum.source_ip', ?, true)")) {
            statement.setString(1, context.actorId().toString());
            statement.setString(2, context.actorOffice());
            statement.setString(3, context.reason() == null ? "" : context.reason());
            statement.setString(4, context.correlationId().toString());
            statement.setString(5, context.sourceIp() == null ? "" : context.sourceIp());
            statement.execute();
        }
    }
}
