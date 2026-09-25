package ng.edu.moaum.portal.helpdesk;

import java.util.List;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * The configured quiet spell: when the Director has set a number of days, a resolved ticket the requester
 * has not answered closes itself after them, on the record, and the requester is told. Nothing happens
 * while the setting is empty, which is how it ships.
 */
@Component
class AutoCloser {

    private static final Logger LOG = LoggerFactory.getLogger(AutoCloser.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JdbcClient jdbc;
    private final TicketNotifier notifier;
    private final TransactionTemplate tx;

    AutoCloser(JdbcClient jdbc, TicketNotifier notifier, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.notifier = notifier;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(initialDelayString = "PT5M", fixedDelayString = "PT1H")
    void run() {
        try {
            List<UUID> closed = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "helpdesk auto-close", null, null), () -> tx.execute(status -> {
                List<UUID> ids = jdbc.sql("SELECT * FROM helpdesk.auto_close()").query(UUID.class).list();
                for (UUID id : ids) notifier.closed(id);
                return ids;
            }));
            if (closed != null && !closed.isEmpty()) LOG.info("helpdesk: {} resolved ticket(s) closed after the configured quiet spell", closed.size());
        } catch (RuntimeException e) {
            LOG.warn("helpdesk auto-close did not run: {}", e.getMessage());
        }
    }
}
