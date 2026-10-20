package ng.edu.moaum.portal.student;

import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.JobLock;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V580: each Monday morning, the person who uploaded students' contacts is told of an upload at least a month old whose contacts
 * still wait for the students to confirm them (people.chase_unconfirmed_contacts, once a week an upload; the template
 * CONTACT_UPLOAD_WAITING, which ICT can switch off). A contact a student says is not theirs is told at once (people.contact_refuse).
 */
@Component
class ContactUploadChase {

    private static final Logger LOG = LoggerFactory.getLogger(ContactUploadChase.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JdbcClient jdbc;
    private final JobLock lock;
    private final TransactionTemplate tx;
    private final int days;

    ContactUploadChase(JdbcClient jdbc, JobLock lock, PlatformTransactionManager transactions, @Value("${moaum.contacts.chase-after-days:30}") int days) {
        this.jdbc = jdbc;
        this.lock = lock;
        this.tx = new TransactionTemplate(transactions);
        this.days = days;
    }

    @Scheduled(cron = "${moaum.contacts.chase-cron:0 45 8 * * MON}", zone = "Africa/Lagos")
    public void chase() {
        lock.runExclusively("contact-upload-chase", this::chaseNow);
    }

    void chaseNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "uploaded contacts still waiting for the students, told weekly", null, null),
                    () -> tx.execute(status -> jdbc.sql("SELECT people.chase_unconfirmed_contacts(:d)").param("d", days).query(Integer.class).single()));
            LOG.info("uploaded contacts waiting: {} notice(s) queued", n);
        } catch (RuntimeException e) {
            LOG.warn("uploaded contacts chase did not run: {}", e.getMessage());
        }
    }
}
