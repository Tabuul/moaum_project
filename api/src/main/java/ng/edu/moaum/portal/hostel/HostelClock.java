package ng.edu.moaum.portal.hostel;

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

/** Every hour the hostel clock runs (V261): a hold that has expired unpaid lapses and the bed passes to the next
 *  name on the waiting list, whether anybody is watching (V030 wrote the rule; nothing used to call it). */
@Component
public class HostelClock {

    private static final Logger LOG = LoggerFactory.getLogger(HostelClock.class);
    private static final UUID NOBODY = new UUID(0L, 0L);

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    public HostelClock(JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.hostel.cron:0 5 * * * *}", zone = "Africa/Lagos")
    public void tick() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "housing", "hostel hold clock", null, null), () -> tx.execute(st -> {
                List<String> sessions = jdbc.sql("SELECT DISTINCT session FROM hostel.allocation WHERE state = 'HELD' AND held_until < now()").query(String.class).list();
                int total = 0;
                for (String s : sessions) total += jdbc.sql("SELECT hostel.lapse_holds(:s)").param("s", s).query(Integer.class).single();
                return total;
            }));
            if (n != null && n > 0) LOG.info("hostel: {} hold(s) lapsed and passed on", n);
        } catch (RuntimeException e) {
            LOG.warn("hostel: the hold clock did not run: {}", e.getMessage());
        }
    }
}
