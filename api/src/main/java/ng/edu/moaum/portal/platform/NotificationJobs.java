package ng.edu.moaum.portal.platform;

import java.util.List;
import java.util.Map;
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
 * V425: the notification engine's clock. Every half-minute it drains the open notification jobs (a window's message to a
 * session's students, later a campaign) by a few batches, each in its own transaction so a long send never holds one open;
 * on Monday mornings it runs the weekly biodata reminder (which itself sends at most once a week per student and nothing
 * while neither the gate nor the reminder switch is on). At start it writes the portal's own address into the engine's
 * setting when ICT has not stated one, so [PORTAL_URL] is never empty in a message.
 */
@Component
public class NotificationJobs {

    private static final Logger LOG = LoggerFactory.getLogger(NotificationJobs.class);
    static final UUID NOBODY = new UUID(0, 0);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final String portalUrl;
    private final int batchesPerTick;

    NotificationJobs(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions,
                     @Value("${moaum.portal-url:}") String portalUrl,
                     @Value("${moaum.notices.job-batches-per-tick:4}") int batchesPerTick) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.portalUrl = portalUrl == null ? "" : portalUrl.trim().replaceAll("/+$", "");
        this.batchesPerTick = Math.max(1, batchesPerTick);
    }

    @jakarta.annotation.PostConstruct
    void statePortalUrl() {
        if (portalUrl.isEmpty()) {
            return;
        }
        try {
            AuditContextHolder.with(new AuditContext(NOBODY, "ict", "the portal's own address", null, null), () -> tx.execute(status ->
                    jdbc.sql("UPDATE platform.notice_setting SET portal_url = :u WHERE id AND portal_url IS NULL").param("u", portalUrl).update()));
        } catch (RuntimeException e) {
            LOG.warn("notices: the portal address was not written to the engine's setting: {}", e.getMessage());
        }
    }

    @Scheduled(fixedDelayString = "${moaum.notices.jobs-every-ms:30000}", initialDelayString = "${moaum.notices.jobs-initial-ms:25000}")
    public void drain() {
        lock.runExclusively("notice-jobs", this::drainNow);
    }

    /** a few batches a tick, each its own transaction; stops early when nothing is open or the job just finished */
    void drainNow() {
        for (int i = 0; i < batchesPerTick; i++) {
            List<Map<String, Object>> ran;
            try {
                ran = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "notification job", null, null), () -> tx.execute(status ->
                        jdbc.sql("SELECT job_id, kind, reached, queued, done FROM platform.run_notice_job(NULL)").query().listOfRows()));
            } catch (RuntimeException e) {
                LOG.warn("notification job did not run: {}", e.getMessage());
                return;
            }
            if (ran == null || ran.isEmpty()) {
                return;
            }
            Map<String, Object> r = ran.get(0);
            LOG.info("notification job {} ({}): {} reached, {} queued{}", r.get("job_id"), r.get("kind"), r.get("reached"), r.get("queued"),
                    Boolean.TRUE.equals(r.get("done")) ? ", done" : "");
            if (Boolean.TRUE.equals(r.get("done"))) {
                return;
            }
        }
    }

    @Scheduled(cron = "${moaum.biodata.remind-cron:0 0 9 * * MON}", zone = "Africa/Lagos")
    public void remindBiodata() {
        lock.runExclusively("biodata-reminders", this::remindBiodataNow);
    }

    void remindBiodataNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "weekly biodata reminder", null, null), () -> tx.execute(status ->
                    jdbc.sql("SELECT people.remind_biodata(3000)").query(Integer.class).single()));
            LOG.info("biodata reminders: {} student(s) reminded", n);
            snapshotNow();
        } catch (RuntimeException e) {
            LOG.warn("biodata reminders did not run: {}", e.getMessage());
        }
    }

    /** V430: the weekly reminder to staff whose e-mail or phone is missing or not usable (on ICT's switch), and the HR office's
     *  weekly word on how many cannot be reached at all; Tuesday mornings */
    /** V438: every morning, the fees and registration windows closing in three days or tomorrow are queued as reminder jobs */
    @Scheduled(cron = "${moaum.windows.remind-cron:0 0 8 * * *}", zone = "Africa/Lagos")
    public void remindClosingWindows() {
        lock.runExclusively("closing-reminders", this::remindClosingWindowsNow);
    }

    void remindClosingWindowsNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "window closing reminders", null, null), () -> tx.execute(status ->
                    jdbc.sql("SELECT platform.queue_closing_reminders()").query(Integer.class).single()));
            if (n != null && n > 0) {
                LOG.info("window closing reminders: {} job(s) queued", n);
            }
        } catch (RuntimeException e) {
            LOG.warn("window closing reminders did not run: {}", e.getMessage());
        }
    }

    @Scheduled(cron = "${moaum.staff.remind-cron:0 0 9 * * TUE}", zone = "Africa/Lagos")
    public void remindStaffContact() {
        lock.runExclusively("staff-contact-reminders", this::remindStaffContactNow);
    }

    void remindStaffContactNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "weekly staff contact reminder", null, null), () -> tx.execute(status ->
                    jdbc.sql("SELECT iam.remind_staff_contact(2000)").query(Integer.class).single()));
            LOG.info("staff contact reminders: {} person(s) reminded", n);
        } catch (RuntimeException e) {
            LOG.warn("staff contact reminders did not run: {}", e.getMessage());
        }
    }

    /** V426: the reading of every student's biodata status the offices' counts and lists read — every quarter of an hour,
     *  and after the weekly reminder; some ten seconds on a register of 54,000 */
    @Scheduled(fixedDelayString = "${moaum.biodata.snapshot-every-ms:900000}", initialDelayString = "${moaum.biodata.snapshot-initial-ms:120000}")
    public void snapshot() {
        lock.runExclusively("biodata-snapshot", this::snapshotNow);
    }

    void snapshotNow() {
        try {
            Integer n = AuditContextHolder.with(new AuditContext(NOBODY, "ict", "biodata status reading", null, null), () -> tx.execute(status ->
                    jdbc.sql("SELECT people.refresh_biodata_snapshot(NULL)").query(Integer.class).single()));
            LOG.info("biodata status reading: {} student(s)", n);
        } catch (RuntimeException e) {
            LOG.warn("biodata status reading did not run: {}", e.getMessage());
        }
    }
}
