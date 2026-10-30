package ng.edu.moaum.portal.hostel;

import java.util.List;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/** Every five minutes the hostel clock runs (V261; hourly until V705): a hold that has expired unpaid lapses and the bed
 *  passes to the next name on the waiting list, whether anybody is watching (V030 wrote the rule; nothing used to call it);
 *  the reminders go before the deadline (V290); a student who asked to be told of a free room is told (V705). The room
 *  lists already treat a hold past its deadline as free, and a reservation lapses it first, so the clock is for the record
 *  and the notices, not the 48 hours themselves. */
@Component
public class HostelClock {

    private static final Logger LOG = LoggerFactory.getLogger(HostelClock.class);
    private static final UUID NOBODY = new UUID(0L, 0L);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    public HostelClock(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.hostel.cron:0 */5 * * * *}", zone = "Africa/Lagos")
    public void tick() {
        lock.runExclusively("hostel-clock", this::tickNow);
    }

    void tickNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "housing", "hostel hold clock", null, null), () -> tx.execute(st -> {
                List<String> sessions = jdbc.sql("SELECT DISTINCT session FROM hostel.allocation WHERE state = 'HELD' AND held_until < now()").query(String.class).list();
                int total = 0;
                for (String s : sessions) total += jdbc.sql("SELECT hostel.lapse_holds(:s)").param("s", s).query(Integer.class).single();
                // V290: the student is reminded at 24, 6 and 1 hours before a reservation expires, once each
                Integer reminded = jdbc.sql("SELECT hostel.remind_holds()").query(Integer.class).single();
                if (reminded != null && reminded > 0) LOG.info("hostel: {} payment reminder(s) sent", reminded);
                // V705: "notify me when a suitable room becomes available", once each
                Integer told = jdbc.sql("SELECT hostel.tell_watchers()").query(Integer.class).single();
                if (told != null && told > 0) LOG.info("hostel: {} student(s) told of a free room", told);
                return total;
            }));
            if (n != null && n > 0) LOG.info("hostel: {} hold(s) lapsed and passed on", n);
        } catch (RuntimeException e) {
            LOG.warn("hostel: the hold clock did not run: {}", e.getMessage());
        }
    }
}
