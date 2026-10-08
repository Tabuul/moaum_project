package ng.edu.moaum.portal.gst;

import java.util.Map;
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
 * V370: each morning, a request between the GST and EPS offices that nobody has answered is chased — the office that holds
 * the course reminded once after the reminder days, the request put to the Academic Office once after the escalation days
 * (catalogue.chase_general_transfers; the days are the Academic Office's to set). Marked only when somebody was reached, so a
 * request nobody could be told of is tried again the next morning.
 */
@Component
class GeneralTransferReminders {

    private static final Logger LOG = LoggerFactory.getLogger(GeneralTransferReminders.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    GeneralTransferReminders(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.gst.transfer-chase-cron:0 40 7 * * *}", zone = "Africa/Lagos")
    void run() {
        lock.runExclusively("general-transfer-reminders", this::runNow);
    }

    void runNow() {
        try {
            Map<String, Object> n = AuditContextHolder.with(new AuditContext(NOBODY, "academic", "requests between the GST and EPS offices chased", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT reminded, escalated FROM catalogue.chase_general_transfers()").query().singleRow()));
            if (n != null && (((Number) n.get("reminded")).intValue() > 0 || ((Number) n.get("escalated")).intValue() > 0)) {
                LOG.info("GST/EPS requests: {} reminded, {} put to the Academic Office", n.get("reminded"), n.get("escalated"));
            }
        } catch (RuntimeException e) {
            LOG.warn("GST/EPS request reminders did not run: {}", e.getMessage());
        }
    }
}
