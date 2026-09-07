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

    public AttributedTransactionManager(DataSource dataSource) {
        super(dataSource);
    }

    @Override
    protected void doBegin(Object transaction, TransactionDefinition definition) {
        super.doBegin(transaction, definition);
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
