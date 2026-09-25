package ng.edu.moaum.portal.examiners;

import java.util.List;
import java.util.Map;
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

/**
 * Each morning: an examiner whose deadline is three days off or nearer is reminded once; one whose deadline
 * has passed with nothing submitted is told once, and so is the desk. Both are marked on the assignment, so
 * nobody is nagged twice for the same deadline; a deadline moved later clears the marks.
 */
@Component
class ExaminerReminders {

    private static final Logger LOG = LoggerFactory.getLogger(ExaminerReminders.class);
    private static final UUID NOBODY = new UUID(0, 0);

    private final JdbcClient jdbc;
    private final ExaminerNotifier notifier;
    private final TransactionTemplate tx;

    ExaminerReminders(JdbcClient jdbc, ExaminerNotifier notifier, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.notifier = notifier;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "0 15 7 * * *", zone = "Africa/Lagos")
    void run() {
        try {
            int[] n = AuditContextHolder.with(new AuditContext(NOBODY, "academic", "examiner deadline reminders", null, null), () -> tx.execute(status -> {
                int reminded = 0, overdue = 0;
                List<Map<String, Object>> due = jdbc.sql("""
                        SELECT a.id, (a.deadline - current_date) AS days_left FROM extexam.assignment a JOIN extexam.examiner e ON e.id = a.examiner_id
                         WHERE a.ended_at IS NULL AND a.status IN ('ASSIGNED','IN_REVIEW','REOPENED') AND e.status = 'ACTIVE'
                           AND a.deadline BETWEEN current_date AND current_date + 3 AND a.reminded_at IS NULL
                         ORDER BY a.deadline LIMIT 200 FOR UPDATE OF a SKIP LOCKED
                        """).query().listOfRows();
                for (Map<String, Object> r : due) {
                    UUID id = (UUID) r.get("id");
                    notifier.reminder(id, ((Number) r.get("days_left")).longValue());
                    jdbc.sql("UPDATE extexam.assignment SET reminded_at = now() WHERE id = :id").param("id", id).update();
                    reminded++;
                }
                List<Map<String, Object>> late = jdbc.sql("""
                        SELECT a.id FROM extexam.assignment a JOIN extexam.examiner e ON e.id = a.examiner_id
                         WHERE a.ended_at IS NULL AND a.status IN ('ASSIGNED','IN_REVIEW','REOPENED') AND e.status = 'ACTIVE'
                           AND a.deadline < current_date AND a.overdue_told_at IS NULL
                         ORDER BY a.deadline LIMIT 200 FOR UPDATE OF a SKIP LOCKED
                        """).query().listOfRows();
                for (Map<String, Object> r : late) {
                    UUID id = (UUID) r.get("id");
                    notifier.overdue(id);
                    jdbc.sql("UPDATE extexam.assignment SET overdue_told_at = now() WHERE id = :id").param("id", id).update();
                    overdue++;
                }
                return new int[] {reminded, overdue};
            }));
            if (n != null && (n[0] > 0 || n[1] > 0)) LOG.info("examiners: {} reminded, {} told overdue", n[0], n[1]);
        } catch (RuntimeException e) {
            LOG.warn("examiner reminders did not run: {}", e.getMessage());
        }
    }
}
