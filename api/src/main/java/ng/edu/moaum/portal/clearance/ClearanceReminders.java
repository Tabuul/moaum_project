package ng.edu.moaum.portal.clearance;

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

/**
 * Each morning (V415): a student whose clearance still has offices outstanding is reminded — once per process in the
 * workflow's interval (clearance.workflow.reminder_days; none at 0), never in the clearance's first interval — so nobody
 * is told the same thing twice in a week. clearance.reminder keeps what was sent. V416: and a stage open past its deadline is
 * chased with the people who sign it, once a week at most (clearance.chase). V671: a student whose final clearance waits only on the
 * Bursary is told once (what is owed, if anything), and the Bursar is told of the students newly ready to graduate.
 */
@Component
class ClearanceReminders {

    private static final Logger LOG = LoggerFactory.getLogger(ClearanceReminders.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    ClearanceReminders(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "0 40 8 * * *", zone = "Africa/Lagos")
    void run() {
        lock.runExclusively("clearance-reminders", this::runNow);
    }

    int runNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "clearance reminders", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT clearance.remind(2000)").query(Integer.class).single()));
            if (n != null && n > 0) LOG.info("clearance reminders: {} student(s) reminded", n);
            // V416: a stage open past its deadline, chased with the people who sign it (one e-mail each, not again within a week)
            Integer told = AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "clearance stages past their deadline", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT clearance.chase_offices(7)").query(Integer.class).single()));
            if (told != null && told > 0) LOG.info("clearance chase: {} officer(s) told of stages past their deadline", told);
            // V671: the student told once that only the Bursary remains; the Bursar told of the students newly ready to graduate
            Integer turn = AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "final clearances waiting only on the Bursary", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT clearance.tell_bursary_turn(2000)").query(Integer.class).single()));
            if (turn != null && turn > 0) LOG.info("final clearance: {} student(s) told only the Bursary remains", turn);
            Integer ready = AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "students newly ready to graduate", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT clearance.tell_bursar_ready()").query(Integer.class).single()));
            if (ready != null && ready > 0) LOG.info("final clearance: the Bursar's office told of students newly ready ({} notice(s))", ready);
            return n == null ? 0 : n;
        } catch (RuntimeException e) {
            LOG.warn("clearance reminders failed: {}", e.getMessage());
            return 0;
        }
    }
}
