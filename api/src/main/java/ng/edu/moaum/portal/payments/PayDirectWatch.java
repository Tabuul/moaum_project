package ng.edu.moaum.portal.payments;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V433: the PAYDirect door watched. Every quarter of an hour the database judges the door's silence against its own rhythm
 * (finance.watch_paydirect) and, once per silence, tells the Directorate of ICT and the Bursary through the notification
 * engine. One instance runs it at a time (JobLock); the office may run it now from the Gateways screen. V477: with it, the
 * Pay on Quickteller payments Interswitch has not reported after a day are told to the Bursary once a day. V481: after each
 * minute's sweep, payments Interswitch reported and still not settled past ten minutes are told to the Bursary and the
 * Directorate of ICT, at most once an hour (finance.watch_paydirect_inbox).
 */
@Component
public class PayDirectWatch {

    private static final Logger LOG = LoggerFactory.getLogger(PayDirectWatch.class);

    private final JobLock lock;
    private final PaymentsService payments;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    PayDirectWatch(JobLock lock, PaymentsService payments, JdbcClient jdbc, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.payments = payments;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(fixedDelayString = "${moaum.paydirect.watch-every-ms:900000}", initialDelayString = "${moaum.paydirect.watch-initial-ms:90000}")
    public void watch() {
        lock.runExclusively("paydirect-watch", this::watchNow);
    }

    /** V474: a notified payment recorded and not settled — the portal was busy past the answer's budget, or the settling
     *  failed — is settled here, every minute, by one instance at a time */
    @Scheduled(fixedDelayString = "${moaum.paydirect.sweep-every-ms:60000}", initialDelayString = "${moaum.paydirect.sweep-initial-ms:120000}")
    public void sweep() {
        lock.runExclusively("paydirect-sweep", () -> {
            try {
                int settled = payments.paydirectSweep();
                if (settled > 0) {
                    LOG.info("payments: {} recorded PAYDirect payment(s) settled after the answer", settled);
                }
            } catch (RuntimeException e) {
                LOG.warn("payments: the PAYDirect sweep did not run: {}", e.getMessage());
            }
            // V481: what the sweep could not settle, told (the event key keeps it to once an hour)
            try {
                Integer told = AuditContextHolder.with(new AuditContext(PaymentsService.NOBODY, "ict", "Pay on Quickteller payments not settled", null, null),
                        () -> tx.execute(st -> jdbc.sql("SELECT finance.watch_paydirect_inbox()").query(Integer.class).single()));
                if (told != null && told > 0) {
                    LOG.warn("payments: Pay on Quickteller payments reported and not settled; {} message(s) queued to the Bursary and the Directorate of ICT", told);
                }
            } catch (RuntimeException e) {
                LOG.warn("payments: the unsettled Pay on Quickteller watch did not run: {}", e.getMessage());
            }
        });
    }

    void watchNow() {
        try {
            int told = payments.watchPaydirectUnattended();
            if (told > 0) {
                LOG.warn("payments: the PAYDirect door has gone quiet; {} message(s) queued to the Directorate of ICT and the Bursary", told);
            }
        } catch (RuntimeException e) {
            LOG.warn("payments: the PAYDirect door watch did not run: {}", e.getMessage());
        }
        // V477: the Pay on Quickteller payments Interswitch has not reported after a day, told to the Bursary once a day
        try {
            int told = payments.watchPaydirectUnreported();
            if (told > 0) {
                LOG.info("payments: Pay on Quickteller payments unreported after a day; {} message(s) queued to the Bursary", told);
            }
        } catch (RuntimeException e) {
            LOG.warn("payments: the unreported Pay on Quickteller watch did not run: {}", e.getMessage());
        }
    }
}
