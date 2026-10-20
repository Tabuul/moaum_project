package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V582: password resets from support tickets. The agent ticks login and password tickets on the desk's queue; the server takes
 * only TICKETS — never a student, a username or a number — and works out from each ticket its student and whether it may be reset
 * (helpdesk.ticket_reset_check: the category flagged for password resets, a student's ticket, open, not in another operation, its
 * reset not done, the student within BULK_RESET_FROM_TICKETS's scope, the student's own checks). The students are reset once
 * each, however many tickets they raised, by the bulk reset's worker and the one reset service (PWR-TKT/…), and every ticket of
 * theirs is resolved with the reset; a student not reset leaves their tickets open with the reason. No password is ever sent,
 * shown, returned or recorded. The student bulk reset (V559) stays apart: its capability is not this one, and it takes students.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/tickets/password-reset")
class TicketPasswordResetController {

    static final String CAPABILITY = "BULK_RESET_FROM_TICKETS";
    static final int MAX = 10_000;
    static final String DEFAULT_RESOLUTION = "Student portal password was reset successfully. Sign in with your matriculation number as the username and as the "
            + "temporary password; you must choose a new password at once.";

    private final JdbcClient jdbc;
    private final SupportAccess support;
    private final BulkPasswordResets work;
    private final tools.jackson.databind.ObjectMapper json;

    TicketPasswordResetController(JdbcClient jdbc, SupportAccess support, BulkPasswordResets work, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.support = support;
        this.work = work;
        this.json = json;
    }

    /** the words for a ticket's reason, and the student's (V559) */
    static String words(String code, String status) {
        return switch (code == null ? "" : code) {
            case "ELIGIBLE" -> "ELIGIBLE FOR PASSWORD RESET";
            case "TICKET_NOT_FOUND" -> "TICKET NOT FOUND — or outside your support scope";
            case "TICKET_NOT_LOGIN" -> "NOT ELIGIBLE — not a login or password ticket";
            case "TICKET_NOT_STUDENT" -> "NOT ELIGIBLE — not a student's ticket";
            case "TICKET_SETTLED" -> "NOT ELIGIBLE — the ticket is resolved or closed";
            case "TICKET_IN_OPERATION" -> "ALREADY IN A PASSWORD RESET that has not finished";
            case "TICKET_RESET_DONE" -> "PASSWORD RESET COMPLETED on this ticket already";
            default -> BulkPasswordResetController.words(code, status);
        };
    }

    private SupportAccess.Access capable(Authentication auth) {
        SupportAccess.Access a = support.access(auth);
        if (!a.has(CAPABILITY)) {
            throw new DomainRuleViolation("SUPPORT_CAPABILITY", "Your posting does not carry password resets from tickets.",
                    new DomainRuleViolation.Remedy("Ask the Head of the ICT Support Desk to grant BULK_RESET_FROM_TICKETS on your posting.", "Head of ICT Support Desk"));
        }
        return a;
    }

    private Object read(String text) {
        return text == null ? null : json.readValue(text, Object.class);
    }

    /** the desk's login and password tickets in figures, and whether the reader may reset from tickets */
    @GetMapping("/summary")
    @PreAuthorize(SupportAccess.AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(Authentication auth) {
        SupportAccess.Access a = support.access(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("may", a.has(CAPABILITY));
        out.put("figures", read(jdbc.sql("SELECT helpdesk.login_ticket_summary(:me, :h)::text").param("me", a.agent()).param("h", a.head()).query(String.class).single()));
        out.put("categories", jdbc.sql("SELECT code, name FROM helpdesk.category WHERE password_reset_eligible ORDER BY ordinal, name").query().listOfRows());
        return out;
    }

    public record Tickets(@NotNull @Size(min = 1, max = MAX) List<UUID> ticketIds) {
    }

    /** each ticket ticked checked: who it is for and whether the student may be reset from it, the duplicates grouped by student */
    @PostMapping("/validate")
    @PreAuthorize(SupportAccess.AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> validate(Authentication auth, @Valid @RequestBody Tickets body) {
        SupportAccess.Access a = capable(auth);
        List<Map<String, Object>> rows = new ArrayList<>(jdbc.sql("""
                SELECT * FROM helpdesk.ticket_reset_check(:me, :h, CAST(:ids AS uuid[])) ORDER BY eligible DESC, full_name, created_at
                """).param("me", a.agent()).param("h", a.head()).param("ids", BulkPasswordResetController.idList(body.ticketIds())).query().listOfRows());
        rows.forEach(r -> r.put("words", words((String) r.get("code"), (String) r.get("student_status"))));
        List<Map<String, Object>> ok = rows.stream().filter(r -> Boolean.TRUE.equals(r.get("eligible"))).toList();
        Map<Object, List<Map<String, Object>>> byStudent = ok.stream().collect(Collectors.groupingBy(r -> r.get("student_id"), LinkedHashMap::new, Collectors.toList()));
        List<Map<String, Object>> grouped = new ArrayList<>();
        byStudent.forEach((s, ts) -> {
            if (ts.size() > 1) {
                Map<String, Object> g = new LinkedHashMap<>();
                g.put("student_id", s);
                g.put("full_name", ts.get(0).get("full_name"));
                g.put("matric_no", ts.get(0).get("matric_no"));
                g.put("tickets", ts.stream().map(t -> t.get("number")).toList());
                grouped.add(g);
            }
        });
        long already = rows.stream().filter(r -> List.of("TICKET_RESET_DONE", "TICKET_SETTLED", "TICKET_IN_OPERATION").contains(r.get("code"))).count();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("selected", rows.size());
        out.put("eligible", ok.size());
        out.put("students", byStudent.size());
        out.put("consolidated", ok.size() - byStudent.size());
        out.put("alreadyDone", already);
        out.put("notEligible", rows.size() - ok.size() - already);
        out.put("grouped", grouped);
        out.put("rows", rows);
        out.put("policy", jdbc.sql("""
                SELECT coalesce(g.student_reset_enabled, true) AS enabled, coalesce(g.student_reset_unlock, true) AS unlock_by_default,
                       g.bulk_reset_approval_over AS approval_over
                  FROM (SELECT 1) one LEFT JOIN helpdesk.setting g ON g.row_no
                """).query().singleRow());
        out.put("resolution", DEFAULT_RESOLUTION);
        return out;
    }

    public record Execute(@NotNull @Size(min = 1, max = MAX) List<UUID> ticketIds, @NotNull @Size(max = 2000) String reason, @Size(max = 2000) String resolution,
                          Boolean unlock, @Size(max = 80) String key) {
    }

    /** the students of the eligible tickets reset, once each; every one of their tickets resolved with the reset */
    @PostMapping("/execute")
    @PreAuthorize(SupportAccess.AGENTS)
    @Transactional
    Map<String, Object> execute(Authentication auth, @Valid @RequestBody Execute body) {
        SupportAccess.Access a = capable(auth);
        String reason = body.reason().trim();
        if (reason.length() < StudentSupportController.RESET_REASON_MIN) {
            throw new DomainRuleViolation("SUPPORT_REASON_SHORT", "Say why the passwords are reset, in " + StudentSupportController.RESET_REASON_MIN + " characters or more.",
                    new DomainRuleViolation.Remedy("For example: \"Students' login and password tickets; identities as on the tickets.\"", "You"));
        }
        Map<String, Object> policy = jdbc.sql("""
                SELECT coalesce(g.student_reset_enabled, true) AS enabled, coalesce(g.student_reset_unlock, true) AS unlock_by_default
                  FROM (SELECT 1) one LEFT JOIN helpdesk.setting g ON g.row_no
                """).query().singleRow();
        if (!Boolean.TRUE.equals(policy.get("enabled"))) {
            throw new DomainRuleViolation("RESET_DISABLED", "PASSWORD RESET TO THE DEFAULT CREDENTIAL IS SWITCHED OFF.",
                    new DomainRuleViolation.Remedy("The Head of the ICT Support Desk or the Director of ICT switches it on in ICT Support Settings.", "Head of ICT Support Desk"));
        }
        String resolution = body.resolution() == null || body.resolution().isBlank() ? DEFAULT_RESOLUTION : body.resolution().trim();
        Map<String, Object> started = asMap(read(jdbc.sql("SELECT helpdesk.start_ticket_reset(:me, :o, :h, CAST(:ids AS uuid[]), :r, :u, :k, :rs)::text")
                .param("me", a.agent()).param("o", AuditContextHolder.required().actorOffice()).param("h", a.head())
                .param("ids", BulkPasswordResetController.idList(body.ticketIds())).param("r", reason)
                .param("u", body.unlock() == null ? Boolean.TRUE.equals(policy.get("unlock_by_default")) : body.unlock())
                .param("k", body.key() == null || body.key().isBlank() ? null : body.key().trim(), Types.VARCHAR).param("rs", resolution)
                .query(String.class).single()));
        // started once this transaction is committed, so the worker reads the operation
        org.springframework.transaction.support.TransactionSynchronizationManager.registerSynchronization(new org.springframework.transaction.support.TransactionSynchronization() {
            @Override
            public void afterCommit() {
                work.start();
            }
        });
        Map<String, Object> out = new LinkedHashMap<>(operation(a, UUID.fromString(String.valueOf(started.get("id")))));
        out.put("started", started);
        return out;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object o) {
        return o instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
    }

    /** an operation from tickets, every part of it, and each ticket's result — for the one who made it, or a Head */
    private Map<String, Object> operation(SupportAccess.Access a, UUID id) {
        Map<String, Object> op = jdbc.sql("""
                SELECT b.id, b.reference, b.status, b.total, b.succeeded, b.failed, b.reason, b.resolution, b.created_at, b.started_at, b.completed_at,
                       helpdesk.person_name(b.initiated_by) AS performed_by, b.initiated_by, b.approval_over, b.series_id,
                       (SELECT count(*) FROM helpdesk.bulk_reset_item i JOIN helpdesk.bulk_reset p ON p.id = i.bulk_id
                         WHERE (p.id = b.id OR p.series_id = b.id) AND i.status <> 'PENDING') AS processed
                  FROM helpdesk.bulk_reset b WHERE b.id = :b AND b.source = 'TICKETS'
                """).param("b", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("password reset from tickets", id));
        if (!a.head() && !a.agent().equals(op.get("initiated_by"))) {
            throw new NotFound("password reset from tickets", id);
        }
        Map<String, Object> out = new LinkedHashMap<>(op);
        List<Map<String, Object>> tickets = jdbc.sql("""
                SELECT x.ticket_id, t.number, t.subject, c.name AS category, t.status AS ticket_status, i.student_id,
                       upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name, s.matric_no,
                       x.status, i.status AS student_result, coalesce(x.note, i.failure_words) AS reason, coalesce(x.resolved_at, i.processed_at) AS processed_at,
                       p.reference AS part
                  FROM helpdesk.bulk_reset_ticket x
                  JOIN helpdesk.bulk_reset p ON p.id = x.bulk_id
                  JOIN helpdesk.bulk_reset_item i ON i.id = x.item_id
                  JOIN helpdesk.ticket t ON t.id = x.ticket_id JOIN helpdesk.category c ON c.id = t.category_id
                  LEFT JOIN people.student s ON s.id = i.student_id
                 WHERE p.id = :b OR p.series_id = :b
                 ORDER BY x.status = 'FAILED' DESC, full_name, t.number
                """).param("b", id).query().listOfRows();
        long students = tickets.stream().map(r -> r.get("student_id")).distinct().count();
        out.put("tickets", tickets);
        out.put("ticketCount", tickets.size());
        out.put("students", students);
        out.put("consolidated", tickets.size() - students);
        out.put("resolved", tickets.stream().filter(r -> "RESOLVED".equals(r.get("status"))).count());
        out.put("failedTickets", tickets.stream().filter(r -> "FAILED".equals(r.get("status"))).count());
        out.put("pendingTickets", tickets.stream().filter(r -> "PENDING".equals(r.get("status"))).count());
        return out;
    }

    @GetMapping("/operations/{id}")
    @PreAuthorize(SupportAccess.AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> one(Authentication auth, @PathVariable UUID id) {
        return operation(support.access(auth), id);
    }

    /** the operations from tickets, the latest first: the reader's own, or every one for a Head */
    @GetMapping("/operations")
    @PreAuthorize(SupportAccess.AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> operations(Authentication auth) {
        SupportAccess.Access a = support.access(auth);
        return jdbc.sql("""
                SELECT b.id, b.reference, b.status, b.total, b.succeeded, b.failed, b.created_at, b.completed_at, helpdesk.person_name(b.initiated_by) AS performed_by,
                       (SELECT count(*) FROM helpdesk.bulk_reset_ticket x WHERE x.bulk_id = b.id) AS tickets
                  FROM helpdesk.bulk_reset b
                 WHERE b.source = 'TICKETS' AND (b.part IS NULL OR b.part = 1) AND (:h OR b.initiated_by = :me)
                 ORDER BY b.created_at DESC LIMIT 500
                """).param("h", a.head()).param("me", a.agent()).query().listOfRows();
    }

    /** a ticket's password reset history — from tickets, in bulk, single — never a password */
    @GetMapping("/history/{ticket}")
    @PreAuthorize(SupportAccess.AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history(Authentication auth, @PathVariable UUID ticket) {
        SupportAccess.Access a = support.access(auth);
        boolean sees = a.head() || Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.can_view(:me, :t)").param("me", a.agent()).param("t", ticket).query(Boolean.class).single());
        if (!sees) {
            throw new NotFound("ticket", ticket);
        }
        return jdbc.sql("SELECT * FROM helpdesk.ticket_password_resets(:t)").param("t", ticket).query().listOfRows();
    }

    /** the login issue report: every login or password ticket the reader works, raised in the period, with its reset */
    @GetMapping("/reports/login-issues")
    @PreAuthorize(SupportAccess.AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> loginIssues(Authentication auth, @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to) {
        SupportAccess.Access a = support.access(auth);
        return jdbc.sql("""
                SELECT t.number, t.requester_name, t.requester_number, s.matric_no, t.subject, c.name AS category, t.created_at, helpdesk.person_name(t.assigned_to) AS assigned,
                       t.status, r.result AS reset_status, r.at AS reset_at, r.by_name AS reset_by, r.reference AS reset_reference, t.resolved_at
                  FROM helpdesk.ticket t
                  JOIN helpdesk.category c ON c.id = t.category_id AND c.password_reset_eligible
                  LEFT JOIN people.student s ON t.requester_kind = 'STUDENT' AND s.id = t.requester_id
                  LEFT JOIN LATERAL (SELECT * FROM helpdesk.ticket_password_resets(t.id) h ORDER BY h.at DESC LIMIT 1) r ON true
                 WHERE (:h OR helpdesk.can_view(:me, t.id))
                   AND (CAST(:f AS date) IS NULL OR t.created_at >= CAST(:f AS date)) AND (CAST(:to AS date) IS NULL OR t.created_at < CAST(:to AS date) + 1)
                 ORDER BY t.created_at DESC LIMIT 20000
                """).param("h", a.head()).param("me", a.agent()).param("f", from, Types.DATE).param("to", to, Types.DATE).query().listOfRows();
    }

    /** the password reset operations report: each ticket of each operation from tickets, with its result */
    @GetMapping("/reports/operations")
    @PreAuthorize(SupportAccess.AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> operationsReport(Authentication auth, @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to) {
        SupportAccess.Access a = support.access(auth);
        return jdbc.sql("""
                SELECT b.reference, t.number, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name, s.matric_no,
                       'Default credential (matriculation number), from the ticket' AS reset_type, x.status AS result, coalesce(x.note, i.failure_words) AS reason,
                       helpdesk.person_name(b.initiated_by) AS actor, coalesce(x.resolved_at, i.processed_at, b.created_at) AS at
                  FROM helpdesk.bulk_reset_ticket x
                  JOIN helpdesk.bulk_reset b ON b.id = x.bulk_id
                  JOIN helpdesk.bulk_reset_item i ON i.id = x.item_id
                  JOIN helpdesk.ticket t ON t.id = x.ticket_id
                  LEFT JOIN people.student s ON s.id = i.student_id
                 WHERE (:h OR b.initiated_by = :me)
                   AND (CAST(:f AS date) IS NULL OR b.created_at >= CAST(:f AS date)) AND (CAST(:to AS date) IS NULL OR b.created_at < CAST(:to AS date) + 1)
                 ORDER BY b.created_at DESC, t.number LIMIT 20000
                """).param("h", a.head()).param("me", a.agent()).param("f", from, Types.DATE).param("to", to, Types.DATE).query().listOfRows();
    }

    public record Eligible(@NotNull Boolean eligible) {
    }

    /** the Director: whether a category is a login and password issue its tickets may be reset from */
    @PutMapping("/categories/{id}")
    @PreAuthorize("hasAnyAuthority('OFFICE_helpdeskhead','OFFICE_ict','OFFICE_admin','OFFICE_super')")
    @Transactional
    Map<String, Object> category(@PathVariable UUID id, @Valid @RequestBody Eligible body) {
        int n = jdbc.sql("UPDATE helpdesk.category SET password_reset_eligible = :e WHERE id = :id").param("e", body.eligible()).param("id", id).update();
        if (n == 0) throw new NotFound("category", id);
        return Map.of("id", id, "passwordResetEligible", body.eligible());
    }
}
