package ng.edu.moaum.portal.calendar;

import java.util.List;
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
 * The session clock (V289). Each night it asks the calendar which planned
 * session, set to transition automatically, has reached its transition date,
 * and makes it current through the one transition there is —
 * {@code policy.transition_session} — so the current session is completed and
 * the planned one made current in one transaction, or nothing changes. A
 * blocked attempt is logged with the checks that failed and is not repeated
 * until the next day; the offices are told when it is done. No student is
 * moved: the returning student progresses by the rules that exist, and the
 * entrant continues under the same account.
 */
@Component
public class SessionTransitionClock {

    private static final Logger LOG = LoggerFactory.getLogger(SessionTransitionClock.class);
    private static final UUID NOBODY = new UUID(0L, 0L);

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final CalendarService calendar;
    private final TransactionTemplate tx;

    public SessionTransitionClock(JobLock lock, JdbcClient jdbc, CalendarService calendar, PlatformTransactionManager transactions) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.calendar = calendar;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.sessions.cron:0 15 0 * * *}", zone = "Africa/Lagos")
    public void tick() {
        lock.runExclusively("session-transition-clock", this::tickNow);
    }

    void tickNow() {
        try {
            List<Map<String, Object>> outcomes = run();
            for (Map<String, Object> o : outcomes) {
                LOG.info("session clock: {} -> {} ({})", o.get("to"), o.get("outcome"), o.get("mode"));
            }
        } catch (RuntimeException e) {
            LOG.warn("session clock: did not run: {}", e.getMessage());
        }
        try {
            remindOverrun();
        } catch (RuntimeException e) {
            LOG.warn("session clock: the overrun reminder did not run: {}", e.getMessage());
        }
    }

    /** V400: once the current session's end date has passed and it is still current, the Registry, the Academic Office and the
     *  Directorate of ICT are reminded once a day (policy.remind_session_overrun says what to tell, and nothing twice in a day) */
    public int remindOverrun() {
        return AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "session clock: overrun reminder", null, null), () -> tx.execute(st -> {
            List<Map<String, Object>> due = jdbc.sql("SELECT subject, body FROM policy.remind_session_overrun()").query().listOfRows();
            int told = 0;
            for (Map<String, Object> d : due) {
                for (String office : List.of("registrar", "academic", "ict")) {
                    jdbc.sql("SELECT admissions.tell_office(:o, :s, :b, NULL)").param("o", office).param("s", d.get("subject")).param("b", d.get("body")).query().listOfRows();
                    told++;
                }
            }
            return told;
        }));
    }

    /** every planned session due today, transitioned in turn; each attempt's outcome is returned as the log holds it */
    public List<Map<String, Object>> run() {
        return AuditContextHolder.with(new AuditContext(NOBODY, "registrar", "session clock", null, null), () -> {
            List<Map<String, Object>> due = jdbc.sql("SELECT name, transitions_on, senate_minute FROM policy.sessions_due_for_transition()").query().listOfRows();
            List<Map<String, Object>> outcomes = new java.util.ArrayList<>();
            for (Map<String, Object> d : due) {
                String name = String.valueOf(d.get("name"));
                String reason = "Reached the configured transition date " + d.get("transitions_on") + " (automatic)";
                try {
                    outcomes.add(tx.execute(st -> calendar.transition(name, "AUTOMATIC", reason, null)));
                } catch (ng.edu.moaum.portal.shared.DomainRuleViolation blocked) {
                    // the BLOCKED row is already in the log; the refusal is the same one the desk would show
                    outcomes.add(Map.of("to", name, "outcome", "BLOCKED", "mode", "AUTOMATIC", "detail", blocked.getMessage()));
                }
            }
            return outcomes;
        });
    }
}
