package ng.edu.moaum.portal.helpdesk;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import ng.edu.moaum.portal.auth.PasswordResetService;
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
 * spine's correlation, and every act on the support ledger names the operation (V563: helpdesk.support_action.bulk_id, from the
 * transaction's moaum.bulk_reset). V563: a student's login ticket is resolved with the reset when the operation says so, and a
 * student refused for want of a matriculation number may be sent the single reset's one-hour link (sendLinks). V582: an operation
 * from tickets (source TICKETS) is checked again on the student's tickets — still open, still the agent's, the student within
 * BULK_RESET_FROM_TICKETS's scope — and every ticket of the student it holds is resolved with the one reset.
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
    private final TicketNotifier notifier;
    private final PasswordResetService resets;
    private final ExecutorService now = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "bulk-password-reset");
        t.setDaemon(true);
        return t;
    });

    BulkPasswordResets(JobLock lock, JdbcClient jdbc, PlatformTransactionManager transactions, StudentAuthService studentAuth, SupportAccess support,
                       TicketNotifier notifier, PasswordResetService resets) {
        this.lock = lock;
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactions);
        this.studentAuth = studentAuth;
        this.support = support;
        this.notifier = notifier;
        this.resets = resets;
    }

    /** the operation every support act of this transaction is made in (V563: helpdesk.support_action.bulk_id) */
    private void tag(UUID bulk) {
        jdbc.sql("SELECT set_config('moaum.bulk_reset', :b, true)").param("b", bulk.toString()).query().singleRow();
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
                    SELECT id, reference, initiated_by, office, head, reason, unlock, resolve_tickets, resolution, source FROM helpdesk.bulk_reset
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
        String resolution = Boolean.TRUE.equals(op.get("resolve_tickets")) ? (String) op.get("resolution") : null;
        boolean fromTickets = "TICKETS".equals(op.get("source"));
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
                        tag(id);
                        List<UUID> resolved = resetOne(id, itemId, student, ticket, agent, head, unlock, reference, reason, sealed, access, resolution, fromTickets);
                        // the requester told of each resolution, queued with the student's reset (all of it, or none)
                        resolved.forEach(notifier::resolved);
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

    /**
     * one student: checked again, reset, on the ledger and the ticket, the ticket resolved when the operation says so (V582: every
     * ticket of the student an operation from tickets holds), the ids resolved returned for the requesters' notices, told — or
     * refused with the reason the screen shows
     */
    private List<UUID> resetOne(UUID bulk, UUID itemId, UUID student, UUID ticket, UUID agent, boolean head, boolean unlock, String reference, String reason,
                                String sealed, SupportAccess.Access access, String resolution, boolean fromTickets) {
        // held while the student is reset: a cancel that reached the student first leaves them as they are
        if (!"PENDING".equals(jdbc.sql("SELECT status FROM helpdesk.bulk_reset_item WHERE id = :i FOR UPDATE").param("i", itemId).query(String.class).single())) {
            return List.of();
        }
        Map<String, Object> check = fromTickets
                // V582: the student's tickets still open and the agent's, the student within BULK_RESET_FROM_TICKETS's scope, the student's own checks
                ? jdbc.sql("""
                        SELECT bool_or(c.eligible) AS eligible, (array_agg(c.code ORDER BY c.eligible DESC))[1] AS code,
                               (array_agg(c.student_status ORDER BY c.eligible DESC))[1] AS status
                          FROM helpdesk.ticket_reset_check(:a, :h, ARRAY(SELECT x.ticket_id FROM helpdesk.bulk_reset_ticket x WHERE x.item_id = :i AND x.status = 'PENDING'), :b) c
                        """).param("a", agent).param("h", head).param("i", itemId).param("b", bulk).query().singleRow()
                : jdbc.sql("SELECT eligible, code, status FROM helpdesk.bulk_reset_check(:a, :h, ARRAY[CAST(:s AS uuid)])")
                        .param("a", agent).param("h", head).param("s", student).query().singleRow();
        if (!Boolean.TRUE.equals(check.get("eligible"))) {
            String code = check.get("code") == null ? "TICKET_SETTLED" : (String) check.get("code");
            throw new DomainRuleViolation(code, TicketPasswordResetController.words(code, (String) check.get("status")),
                    new DomainRuleViolation.Remedy("See the reason; the student was not reset.", "ICT Support"));
        }
        boolean ticketRequired = "REQUIRED".equals(jdbc.sql("SELECT coalesce(g.student_reset_ticket, 'OPTIONAL') FROM (SELECT 1) one LEFT JOIN helpdesk.setting g ON g.row_no")
                .query(String.class).single());
        UUID onTicket = support.ticketFor(access, ticket, student, ticketRequired);
        StudentAuthService.DefaultReset r = studentAuth.resetToDefault(student, unlock, sealed);
        if (r.alreadyDone()) {
            jdbc.sql("UPDATE helpdesk.bulk_reset_item SET status = 'ALREADY_RESET', processed_at = now() WHERE id = :i").param("i", itemId).update();
            return fromTickets ? resolveTickets(itemId, agent, reference, resolution) : single(resolve(itemId, onTicket, agent, reference, resolution));
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
        jdbc.sql("UPDATE helpdesk.bulk_reset_item SET status = 'RESET', action_id = :a, processed_at = now() WHERE id = :i")
                .param("a", action).param("i", itemId).update();
        List<UUID> resolved = fromTickets ? resolveTickets(itemId, agent, reference, resolution) : single(resolve(itemId, onTicket, agent, reference, resolution));
        // a student whose ticket is resolved reads it there (and is e-mailed the resolution); the others are told as a single reset tells them
        if (resolved.isEmpty()) {
            support.tell(student, "Your portal password was reset by ICT Support",
                    "ICT Support reset your portal password. Sign in with the details ICT Support gave you; you will be asked to choose your own "
                            + "password at once. If you did not ask for this, contact ICT Support.");
        }
        return resolved;
    }

    private static List<UUID> single(UUID resolved) {
        return resolved == null ? List.of() : List.of(resolved);
    }

    /** V582: every ticket of the student the operation holds, resolved with the one reset — one settled meanwhile is left as it is */
    private List<UUID> resolveTickets(UUID itemId, UUID agent, String reference, String resolution) {
        List<UUID> out = new ArrayList<>();
        for (Map<String, Object> x : jdbc.sql("SELECT id, ticket_id FROM helpdesk.bulk_reset_ticket WHERE item_id = :i AND status = 'PENDING' ORDER BY id")
                .param("i", itemId).query().listOfRows()) {
            UUID t = (UUID) x.get("ticket_id");
            boolean done = Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.resolve_for_reset(:t, :a, :s, :d)")
                    .param("t", t).param("a", agent).param("s", "Password reset by ICT Support (" + reference + ")").param("d", resolution)
                    .query(Boolean.class).single());
            jdbc.sql("UPDATE helpdesk.bulk_reset_ticket SET status = :st, resolved_at = CASE WHEN :ok THEN now() END WHERE id = :x")
                    .param("st", done ? "RESOLVED" : "UNRESOLVED").param("ok", done).param("x", x.get("id")).update();
            if (done) out.add(t);
        }
        if (!out.isEmpty()) {
            jdbc.sql("UPDATE helpdesk.bulk_reset_item SET ticket_resolved_at = now() WHERE id = :i").param("i", itemId).update();
        }
        return out;
    }

    /** V563: the student's login ticket resolved with the reset, through opened and in progress as the desk takes it */
    private UUID resolve(UUID itemId, UUID ticket, UUID agent, String reference, String resolution) {
        if (resolution == null || ticket == null) {
            return null;
        }
        boolean done = Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.resolve_for_reset(:t, :a, :s, :d)")
                .param("t", ticket).param("a", agent).param("s", "Password reset by ICT Support (" + reference + ")").param("d", resolution)
                .query(Boolean.class).single());
        if (!done) {
            return null;
        }
        jdbc.sql("UPDATE helpdesk.bulk_reset_item SET ticket_resolved_at = now() WHERE id = :i").param("i", itemId).update();
        return ticket;
    }

    /**
     * V563: the single reset's one-hour link sent to each student of the operation refused for want of a matriculation number (who
     * signs in with the admission or JAMB number), each in a transaction of its own and checked again — within the agent's scope,
     * still without a number — to the e-mail and phone on the record (the login ticket's e-mail where the record has none). Each
     * student's result: where the link went, masked, or why it was not sent.
     */
    List<Map<String, Object>> sendLinks(UUID bulk, UUID agent, boolean head, String office, String reason) {
        String reference = jdbc.sql("SELECT reference FROM helpdesk.bulk_reset WHERE id = :b").param("b", bulk).query(String.class).single();
        AuditContext ctx = new AuditContext(agent, office, reason, bulk, null);
        SupportAccess.Access access = new SupportAccess.Access(agent, head, Set.of(), "");
        List<Map<String, Object>> out = new ArrayList<>();
        List<Map<String, Object>> items = jdbc.sql("""
                SELECT i.id, i.student_id, i.ticket_id, t.requester_email FROM helpdesk.bulk_reset_item i LEFT JOIN helpdesk.ticket t ON t.id = i.ticket_id
                 WHERE i.bulk_id = :b AND i.status = 'FAILED' AND i.failure_code = 'RESET_NO_MATRIC' AND i.link_sent_at IS NULL ORDER BY i.ord
                """).param("b", bulk).query().listOfRows();
        for (Map<String, Object> item : items) {
            UUID itemId = (UUID) item.get("id");
            UUID student = (UUID) item.get("student_id");
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("student_id", student);
            try {
                String to = AuditContextHolder.with(ctx, () -> tx.execute(st -> {
                    tag(bulk);
                    Map<String, Object> check = jdbc.sql("SELECT code, status FROM helpdesk.bulk_reset_check(:a, :h, ARRAY[CAST(:s AS uuid)])")
                            .param("a", agent).param("h", head).param("s", student).query().singleRow();
                    String code = (String) check.get("code");
                    if ("ELIGIBLE".equals(code)) {
                        throw new DomainRuleViolation("BULK_LINK_HAS_NUMBER", "NOW HAS A MATRICULATION NUMBER — try the failed students again instead",
                                new DomainRuleViolation.Remedy("Retry the failed students.", "ICT Support"));
                    }
                    if (!"RESET_NO_MATRIC".equals(code)) {
                        throw new DomainRuleViolation(code, BulkPasswordResetController.words(code, (String) check.get("status")),
                                new DomainRuleViolation.Remedy("See the reason; no link was sent.", "ICT Support"));
                    }
                    UUID ticket = (UUID) item.get("ticket_id");
                    UUID onTicket = null;
                    if (ticket != null) {
                        try {
                            onTicket = support.ticketFor(access, ticket, student, false);
                        } catch (DomainRuleViolation notWorked) {
                            onTicket = null;   // the link goes all the same; the act is not filed on a ticket the agent does not work
                        }
                    }
                    PasswordResetService.StudentReset sent = resets.forStudent(student, (String) item.get("requester_email"));
                    String where = String.join(" and ", java.util.stream.Stream.of(sent.email(), sent.phone()).filter(java.util.Objects::nonNull).toList());
                    support.act(student, onTicket, "PASSWORD_RESET", null, null, null, reason, null, null,
                            Map.of("method", "RESET_LINK", "authEventId", sent.resetId().toString(), "bulkReference", reference,
                                   "summary", "Password reset initiated after bulk reset " + reference + " (no matriculation number): a one-hour link sent to " + where));
                    if (onTicket != null) {
                        jdbc.sql("SELECT helpdesk.comment(:t, 'AGENT', :a, helpdesk.person_name(:a), false, :b)").param("t", onTicket).param("a", agent)
                                .param("b", "A password reset link has been sent to the email address (and phone, where one is held) on your record. It is valid for one hour. "
                                        + "Open it to choose a new password, then sign in with your admission or JAMB number; the desk never sees or sets your password.")
                                .query(UUID.class).single();
                    }
                    jdbc.sql("UPDATE helpdesk.bulk_reset_item SET link_sent_at = now(), link_to = :w, link_failure = NULL WHERE id = :i")
                            .param("w", where).param("i", itemId).update();
                    return where;
                }));
                result.put("sent", true);
                result.put("to", to);
            } catch (DomainRuleViolation refused) {
                String words = "AUTH_NO_ADDRESS".equals(refused.code())
                        ? "NO E-MAIL OR PHONE ON RECORD — correct the student's contact, or the Registry issues the matriculation number"
                        : refused.getMessage();
                AuditContextHolder.with(ctx, () -> tx.execute(st -> jdbc.sql("UPDATE helpdesk.bulk_reset_item SET link_failure = :w WHERE id = :i")
                        .param("w", words).param("i", itemId).update()));
                result.put("sent", false);
                result.put("why", words);
            }
            out.add(result);
        }
        return out;
    }

    private void fail(AuditContext ctx, UUID itemId, String code, String words) {
        AuditContextHolder.with(ctx, () -> tx.execute(st -> jdbc.sql("""
                UPDATE helpdesk.bulk_reset_item SET status = 'FAILED', failure_code = :c, failure_words = :w, processed_at = now()
                 WHERE id = :i AND status = 'PENDING'
                """).param("c", code == null ? "RESET_REFUSED" : code).param("w", words).param("i", itemId).update()));
    }
}
