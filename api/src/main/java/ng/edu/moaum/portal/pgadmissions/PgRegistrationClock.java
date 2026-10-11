package ng.edu.moaum.portal.pgadmissions;

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

/** Every hour (V389): the School of Postgraduate Studies' students are told by email and SMS when PG course registration
 *  opens on the School's calendar, and those not yet registered three days before it closes — once each. The database
 *  decides who and when (admissions.pg_tell_registration). */
@Component
public class PgRegistrationClock {

    private static final Logger LOG = LoggerFactory.getLogger(PgRegistrationClock.class);
    private static final UUID NOBODY = new UUID(0L, 0L);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    public PgRegistrationClock(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.pg-registration.cron:0 15 * * * *}", zone = "Africa/Lagos")
    public void tick() {
        lock.runExclusively("pg-registration-clock", this::tickNow);
    }

    void tickNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "pgschool", "postgraduate registration notices", null, null),
                    () -> tx.execute(st -> jdbc.sql("SELECT admissions.pg_tell_registration()").query(Integer.class).single()));
            if (n != null && n > 0) LOG.info("pg registration: {} student(s) told", n);
        } catch (RuntimeException e) {
            LOG.warn("pg registration: the clock did not run: {}", e.getMessage());
        }
    }
}
