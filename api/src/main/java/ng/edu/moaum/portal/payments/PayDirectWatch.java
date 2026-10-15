package ng.edu.moaum.portal.payments;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import ng.edu.moaum.portal.shared.JobLock;

/**
 * V433: the PAYDirect door watched. Every quarter of an hour the database judges the door's silence against its own rhythm
 * (finance.watch_paydirect) and, once per silence, tells the Directorate of ICT and the Bursary through the notification
 * engine. One instance runs it at a time (JobLock); the office may run it now from the Gateways screen.
 */
@Component
public class PayDirectWatch {

    private static final Logger LOG = LoggerFactory.getLogger(PayDirectWatch.class);

    private final JobLock lock;
    private final PaymentsService payments;

    PayDirectWatch(JobLock lock, PaymentsService payments) {
        this.lock = lock;
        this.payments = payments;
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
    }
}
