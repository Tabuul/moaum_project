package ng.edu.moaum.portal.deferments;

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

/** Each morning the deferment clock runs (V259): approved periods that have begun come into force and the
 *  student's status reads DEFERRED; returns approaching are reminded once. The database does the work. */
@Component
public class DefermentClock {

    private static final Logger LOG = LoggerFactory.getLogger(DefermentClock.class);
    private static final UUID NOBODY = new UUID(0L, 0L);

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    public DefermentClock(JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.deferments.cron:0 20 6 * * *}", zone = "Africa/Lagos")
    public void tick() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "deferment clock", null, null),
                    () -> tx.execute(st -> jdbc.sql("SELECT people.deferments_tick()").query(Integer.class).single()));
            if (n != null && n > 0) LOG.info("deferments: {} period(s) came into force or return(s) reminded", n);
        } catch (RuntimeException e) {
            LOG.warn("deferments: the clock did not run: {}", e.getMessage());
        }
    }
}
