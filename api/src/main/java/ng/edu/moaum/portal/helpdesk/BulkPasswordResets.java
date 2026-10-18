package ng.edu.moaum.portal.helpdesk;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.JobLock;
import ng.edu.moaum.portal.studentportal.StudentAuthService;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V559: the students of a bulk password reset reset one by one, each in its own transaction — the student checked again (the
 * agent's scope, the policy, the record), the account put on its first password by the one reset service (V485's
 * StudentAuthService.resetToDefault, with one sealed hash for the whole operation), the act on the support ledger and the ticket,
 * the student told as a single reset tells them, and the result kept — so a student who fails leaves the others as they are, and
 * one who succeeds is never half reset. The request that opens the operation starts the work at once; a timer finds any that an
 * API restart left open. Every write is in the agent's name, with the operation's reason, and the operation's id as the audit
 * spine's correlation.
 */
@Component
class BulkPasswordResets {

    private static final Logger LOG = LoggerFactory.getLogger(BulkPasswordResets.class);
    /** students reset between two writes of the operation's counts (what the screen's progress reads) */
    private static final int CHUNK = 20;

    private final JobLock lock;
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;
    private final StudentAuthService studentAuth;
    private final SupportAccess support;
    private final ExecutorService now = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "bulk-password-reset");
        t.setDaemon(true);
        return t;
    });

    BulkPasswordResets(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions, StudentAuthService studentAuth, SupportAccess support) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.studentAuth = studentAuth;
        this.support = support;
    }

    /** the request that opened an operation starts it now, not at the next tick */
    void start() {
        now.submit(() -> lock.runExclusively("bulk-password-reset", this::runNow));
    }

    /** an operation an API restart left open is taken up again */
    @Scheduled(fixedDelayString = "${moaum.bulk-reset.every-ms:20000}", initialDelayString = "${moaum.bulk-reset.initial-ms:30000}")
    void tick() {
        lock.runExclusively("bulk-password-reset", this::runNow);
    }

    void runNow() {
        while (true) {
            Map<String, Object> op = jdbc.sql("""
                    SELECT id, reference, initiated_by, office, head, reason, unlock FROM helpdesk.bulk_reset
                     WHERE status IN ('PENDING', 'PROCESSING') ORDER BY created_at LIMIT 1
                    """).query().listOfRows().stream().findFirst().orElse(null);
            if (op == null) {
                return;
            }
            try {
                process(op);
            } catch (RuntimeException e) {
                LOG.warn("bulk password reset {} stopped: {}", op.get("reference"), e.getMessage());
                return;   // the next tick tries again
            }
        }
    }

    private void process(Map<String, Object> op) {
        UUID id = (UUID) op.get("id");
        UUID agent = (UUID) op.get("initiated_by");
        boolean head = Boolean.TRUE.equals(op.get("head"));
        boolean unlock = Boolean.TRUE.equals(op.get("unlock"));
        String reference = (String) op.get("reference");
        String reason = (String) op.get("reason");
        AuditContext ctx = new AuditContext(agent, (String) op.get("office"), reason, id, null);
        SupportAccess.Access access = new SupportAccess.Access(agent, head, Set.of(), "");
        String sealed = studentAuth.sealedHash();   // one secret nobody holds, for every account of the operation
        AuditContextHolder.with(ctx, () -> tx.execute(st -> jdbc.sql("SELECT helpdesk.bulk_reset_tally(:b)").param("b", id).query(String.class).single()));
        long done = 0;
        while (true) {
            List<Map<String, Object>> items = jdbc.sql("""
                    SELECT i.id, i.student_id, i.ticket_id FROM helpdesk.bulk_reset_item i
                     WHERE i.bulk_id = :b AND i.status = 'PENDING' ORDER BY i.ord LIMIT :n
                    """).param("b", id).param("n", CHUNK).query().listOfRows();
            if (items.isEmpty()) {
                break;
            }
            for (Map<String, Object> item : items) {
                UUID itemId = (UUID) item.get("id");
                UUID student = (UUID) item.get("student_id");
                UUID ticket = (UUID) item.get("ticket_id");
                try {
                    AuditContextHolder.with(ctx, () -> tx.execute(st -> {
                        resetOne(itemId, student, ticket, agent, head, unlock, reference, reason, sealed, access);
                        return null;
                    }));
                } catch (DomainRuleViolation refused) {
                    fail(ctx, itemId, refused.code(), refused.getMessage());
                } catch (RuntimeException e) {
                    LOG.warn("bulk password reset {}: student {} not reset: {}", reference, student, e.getMessage());
                    fail(ctx, itemId, "RESET_REFUSED", "PASSWORD RESET COULD NOT BE COMPLETED. Try this student again, or tell the Director of ICT.");
                }
                done++;
            }
            String status = AuditContextHolder.with(ctx, () -> tx.execute(st -> jdbc.sql("SELECT helpdesk.bulk_reset_tally(:b)").param("b", id).query(String.class).single()));
            if ("CANCELLED".equals(jdbc.sql("SELECT status FROM helpdesk.bulk_reset WHERE id = :b").param("b", id).query(String.class).single())) {
                LOG.info("bulk password reset {} cancelled after {} student(s)", reference, done);
                return;
            }
            if (status != null && !"PROCESSING".equals(status)) {
                break;
            }
        }
        LOG.info("bulk password reset {}: {} student(s) taken", reference, done);
    }

    /** one student: checked again, reset, on the ledger and the ticket, told — or refused with the reason the screen shows */
    private void resetOne(UUID itemId, UUID student, UUID ticket, UUID agent, boolean head, boolean unlock, String reference, String reason,
                          String sealed, SupportAccess.Access access) {
        // held while the student is reset: a cancel that reached the student first leaves them as they are
        if (!"PENDING".equals(jdbc.sql("SELECT status FROM helpdesk.bulk_reset_item WHERE id = :i FOR UPDATE").param("i", itemId).query(String.class).single())) {
            return;
        }
        Map<String, Object> check = jdbc.sql("SELECT eligible, code, status FROM helpdesk.bulk_reset_check(:a, :h, ARRAY[CAST(:s AS uuid)])")
                .param("a", agent).param("h", head).param("s", student).query().singleRow();
        if (!Boolean.TRUE.equals(check.get("eligible"))) {
            String code = (String) check.get("code");
            throw new DomainRuleViolation(code, BulkPasswordResetController.words(code, (String) check.get("status")),
                    new DomainRuleViolation.Remedy("See the reason; the student was not reset.", "ICT Support"));
        }
        boolean ticketRequired = "REQUIRED".equals(jdbc.sql("SELECT coalesce(g.student_reset_ticket, 'OPTIONAL') FROM (SELECT 1) one LEFT JOIN helpdesk.setting g ON g.row_no")
                .query(String.class).single());
        UUID onTicket = support.ticketFor(access, ticket, student, ticketRequired);
        StudentAuthService.DefaultReset r = studentAuth.resetToDefault(student, unlock, sealed);
        if (r.alreadyDone()) {
            jdbc.sql("UPDATE helpdesk.bulk_reset_item SET status = 'ALREADY_RESET', processed_at = now() WHERE id = :i").param("i", itemId).update();
            return;
        }
        UUID action = support.act(student, onTicket, "PASSWORD_RESET", null, null, null, reason, null, null,
                Map.of("method", "DEFAULT_CREDENTIAL", "authEventId", r.eventId().toString(), "bulkReference", reference,
                       "summary", "Password reset to the default student credential in bulk reset " + reference
                               + ": the student signs in with the matriculation number and must change the password at once"
                               + (r.opened() ? "; the portal account was opened" : "")
                               + (r.sessionsEnded() > 0 ? "; " + r.sessionsEnded() + " open session" + (r.sessionsEnded() == 1 ? "" : "s") + " ended" : "")));
        if (r.unlocked()) {
            support.act(student, onTicket, "ACCOUNT_UNLOCKED", null, null, null, reason, null, null,
                    Map.of("summary", "Account unlocked with the password reset in bulk reset " + reference + ": the failed sign-ins cleared"));
        }
        support.tell(student, "Your portal password was reset by ICT Support",
                "ICT Support reset your portal password. Sign in with the details ICT Support gave you; you will be asked to choose your own "
                        + "password at once. If you did not ask for this, contact ICT Support.");
        jdbc.sql("UPDATE helpdesk.bulk_reset_item SET status = 'RESET', action_id = :a, processed_at = now() WHERE id = :i")
                .param("a", action).param("i", itemId).update();
    }

    private void fail(AuditContext ctx, UUID itemId, String code, String words) {
        AuditContextHolder.with(ctx, () -> tx.execute(st -> jdbc.sql("""
                UPDATE helpdesk.bulk_reset_item SET status = 'FAILED', failure_code = :c, failure_words = :w, processed_at = now()
                 WHERE id = :i AND status = 'PENDING'
                """).param("c", code == null ? "RESET_REFUSED" : code).param("w", words).param("i", itemId).update()));
    }
}
