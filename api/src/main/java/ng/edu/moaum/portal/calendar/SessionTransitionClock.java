package ng.edu.moaum.portal.calendar;

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

    private final JdbcClient jdbc;
    private final CalendarService calendar;
    private final TransactionTemplate tx;

    public SessionTransitionClock(JdbcClient jdbc, CalendarService calendar, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.calendar = calendar;
        this.tx = new TransactionTemplate(transactions);
    }

    @Scheduled(cron = "${moaum.sessions.cron:0 15 0 * * *}", zone = "Africa/Lagos")
    public void tick() {
        try {
            List<Map<String, Object>> outcomes = run();
            for (Map<String, Object> o : outcomes) {
                LOG.info("session clock: {} -> {} ({})", o.get("to"), o.get("outcome"), o.get("mode"));
            }
        } catch (RuntimeException e) {
            LOG.warn("session clock: did not run: {}", e.getMessage());
        }
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
