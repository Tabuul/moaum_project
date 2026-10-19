package ng.edu.moaum.portal.helpdesk;

import static ng.edu.moaum.portal.helpdesk.SupportAccess.AGENTS;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.blank;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.can;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
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
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V559: bulk student password reset at the ICT Support Desk. The agent finds the students (the desk's search, or the students
 * with an open Login Issues ticket), chooses many, sees which may be reset and why not, gives the reason, and the students are
 * reset to the default student credential — the matriculation number, changed at the next sign-in — by the one reset service of
 * the single reset (BulkPasswordResets). Everything is decided on the server from the students' ids: the agent's
 * BULK_RESET_PASSWORD and its scope (the Head of the Support Desk, the Director of ICT and the administrators over the
 * University), the policy, each student's record. No password is ever sent, shown or recorded. V563: the login tickets resolved
 * with the reset when asked, the reset link for the students refused for want of a matriculation number, the students not reset
 * tried again, and an operation of more students than ICT Support Settings allow waiting for a Head's approval.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/support/password-reset/bulk")
class BulkPasswordResetController {

    /** V565: students one request takes (opened as parts of 1,000 run one after another, helpdesk.start_bulk_reset) */
    private static final int MAX = 10000;

    private final JdbcClient jdbc;
    private final SupportAccess support;
    private final BulkPasswordResets work;
    private final tools.jackson.databind.ObjectMapper json;

    BulkPasswordResetController(JdbcClient jdbc, SupportAccess support, BulkPasswordResets work, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.support = support;
        this.work = work;
        this.json = json;
    }

    /** what a result means, in the desk's words */
    static String words(String code, String status) {
        return switch (code == null ? "" : code) {
            case "ELIGIBLE" -> "Will be reset to the matriculation number";
            case "NOT_FOUND" -> "STUDENT RECORD NOT FOUND";
            case "OUT_OF_SCOPE" -> "ACCESS NOT AUTHORIZED — the student is outside your support scope";
            case "RESET_NO_MATRIC" -> "MATRICULATION NUMBER NOT AVAILABLE — send a reset link or issue a temporary password instead";
            case "RESET_STATUS" -> "STUDENT NOT ELIGIBLE — the account is not active" + (status == null ? "" : " (" + status + ")");
            case "RESET_MERGED_RECORD" -> "STUDENT NOT ELIGIBLE — the record was merged into another; reset the live record";
            case "RESET_DISABLED" -> "RESET TO THE DEFAULT CREDENTIAL IS SWITCHED OFF in ICT Support Settings";
            case "CANCELLED" -> "CANCELLED before this student was reached";
            case "REJECTED" -> "NOT APPROVED — the bulk reset was declined";
            default -> "PASSWORD RESET COULD NOT BE COMPLETED";
        };
    }

    private SupportAccess.Access bulkAccess(Authentication auth) {
        SupportAccess.Access a = support.access(auth);
        can(a, "BULK_RESET_PASSWORD");
        return a;
    }

    /** the students' ids as one uuid[] value, read by the database as a whole (never one statement a student) */
    static String idList(List<UUID> ids) {
        StringBuilder b = new StringBuilder("{");
        for (UUID id : ids) {
            if (id == null) continue;
            if (b.length() > 1) b.append(',');
            b.append(id);
        }
        return b.append('}').toString();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> read(String text) {
        return json.readValue(text, Map.class);
    }

    /** the desk's counts, within the reader's reach, and whether the reader may bulk-reset, over what */
    @GetMapping("/summary")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(Authentication auth) {
        SupportAccess.Access a = support.access(auth);
        return read(jdbc.sql("SELECT helpdesk.reset_desk_summary(:me, :h)::text").param("me", a.agent()).param("h", a.head()).query(String.class).single());
    }

    private static final String CANDIDATES = """
            WITH sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(:me, 'BULK_RESET_PASSWORD')),
            lt AS MATERIALIZED (   -- each student's newest open Login Issues ticket, of those the agent works (the reset is filed on it)
                SELECT DISTINCT ON (t.requester_id) t.requester_id AS student_id, t.id, t.number, t.status, t.created_at
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id AND c.code = 'LOGIN'
                 WHERE t.requester_kind = 'STUDENT' AND t.status NOT IN ('RESOLVED', 'CLOSED') AND (:head OR helpdesk.can_view(:me, t.id))
                 ORDER BY t.requester_id, t.created_at DESC)
            """;
    private static final String CANDIDATES_FROM = """
              FROM people.student s
              JOIN ref.programme p ON p.code = s.programme_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN iam.student_account a ON a.student_id = s.id
              LEFT JOIN lt ON lt.student_id = s.id
             WHERE (:head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY (sc.faculties) OR p.dept_code = ANY (sc.departments)))
               AND (:fac::text IS NULL OR p.faculty_code = :fac)
               AND (:dept::text IS NULL OR p.dept_code = :dept)
               AND (:prog::text IS NULL OR p.code = :prog)
               AND (:level::int IS NULL OR s.current_level = :level)
               AND (:status::text IS NULL OR s.status = :status)
               AND (NOT :login OR lt.id IS NOT NULL)
               AND (:account::text IS NULL
                    OR (:account = 'NO_ACCOUNT' AND a.id IS NULL)
                    OR (:account = 'LOCKED' AND a.locked_until > now())
                    OR (:account = 'CHANGE_REQUIRED' AND a.must_change)
                    OR (:account = 'NORMAL' AND a.id IS NOT NULL AND NOT a.must_change AND coalesce(a.locked_until <= now(), true)))
               AND (:q::text IS NULL
                    OR upper(s.surname) LIKE :qp OR upper(s.other_names) LIKE :qp OR upper(s.matric_no) LIKE :qp OR upper(s.admission_no) LIKE :qp
                    OR upper(s.jamb_reg_no) = :qu OR s.id = :uid
                    OR s.candidate_id = (SELECT x.candidate_id FROM admissions.application x WHERE x.application_no = :qu)
                    OR EXISTS (SELECT 1 FROM people.student_contact c WHERE c.student_id = s.id AND (c.phone = :q OR lower(c.email) = lower(:q)))
                    OR upper(lt.number) = :qu)
            """;

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, SupportAccess.Access a, String q, String fac, String dept, String prog, Integer level,
                                          String status, boolean login, String account) {
        String term = blank(q);
        return spec.param("me", a.agent()).param("head", a.head())
                .param("fac", blank(fac) == null ? null : fac.trim().toUpperCase(), Types.VARCHAR)
                .param("dept", blank(dept) == null ? null : dept.trim().toUpperCase(), Types.VARCHAR)
                .param("prog", blank(prog) == null ? null : prog.trim().toUpperCase(), Types.VARCHAR)
                .param("level", level, Types.INTEGER).param("status", blank(status) == null ? null : status.trim().toUpperCase(), Types.VARCHAR)
                .param("login", login).param("account", blank(account) == null ? null : account.trim().toUpperCase(), Types.VARCHAR)
                .param("q", term, Types.VARCHAR).param("qp", term == null ? null : term.toUpperCase() + "%", Types.VARCHAR)
                .param("qu", term == null ? null : term.toUpperCase(), Types.VARCHAR).param("uid", SupportAccess.uuidOrNull(term), Types.OTHER);
    }

    /**
     * the students the agent may bulk-reset, searched and filtered — a page of them; with all=true, the ids of every student that
     * matches (at most 10,000), and their login tickets, for "Select all"
     */
    @GetMapping("/candidates")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> candidates(Authentication auth, @RequestParam(required = false) String q, @RequestParam(required = false) String fac,
                                   @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                   @RequestParam(required = false) Integer level, @RequestParam(required = false) String status,
                                   @RequestParam(defaultValue = "false") boolean login, @RequestParam(required = false) String account,
                                   @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size,
                                   @RequestParam(defaultValue = "false") boolean all) {
        SupportAccess.Access a = bulkAccess(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        if (all) {
            List<Map<String, Object>> ids = bind(jdbc.sql(CANDIDATES + "SELECT s.id::text AS id, lt.id::text AS ticket " + CANDIDATES_FROM
                    + " ORDER BY lt.created_at DESC NULLS LAST, s.surname, s.other_names LIMIT " + (MAX + 1)), a, q, fac, dept, prog, level, status, login, account)
                    .query().listOfRows();
            out.put("over", ids.size() > MAX);
            List<Map<String, Object>> kept = ids.subList(0, Math.min(ids.size(), MAX));
            out.put("ids", kept.stream().map(r -> r.get("id")).toList());
            Map<Object, Object> tickets = new LinkedHashMap<>();
            kept.forEach(r -> { if (r.get("ticket") != null) tickets.put(r.get("id"), r.get("ticket")); });
            out.put("tickets", tickets);
            return out;
        }
        int sz = Math.max(1, Math.min(size, 200));
        int pg = Math.max(1, page);
        long total = bind(jdbc.sql(CANDIDATES + "SELECT count(*) " + CANDIDATES_FROM), a, q, fac, dept, prog, level, status, login, account).query(Long.class).single();
        List<Map<String, Object>> rows = bind(jdbc.sql(CANDIDATES + """
                SELECT s.id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name, s.matric_no, s.jamb_reg_no, s.admission_no,
                       f.name AS faculty, d.name AS department, p.name AS programme, s.current_level AS level, s.status,
                       CASE WHEN a.id IS NULL THEN 'NO_ACCOUNT' WHEN a.locked_until > now() THEN 'LOCKED' WHEN a.must_change THEN 'CHANGE_REQUIRED' ELSE 'NORMAL' END AS account,
                       a.last_signed_in_at, lt.id AS ticket_id, lt.number AS ticket_number, lt.status AS ticket_status
                """ + CANDIDATES_FROM + " ORDER BY lt.created_at DESC NULLS LAST, s.surname, s.other_names LIMIT :n OFFSET :o"),
                a, q, fac, dept, prog, level, status, login, account).param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        out.put("scope", a.head() ? "The University" : jdbc.sql("SELECT words FROM helpdesk.agent_scope_for(:me, 'BULK_RESET_PASSWORD')").param("me", a.agent()).query(String.class).single());
        // the filters' choices, as the desk's student list gives them (every page, so a chosen filter keeps its name)
        Map<String, Object> options = new LinkedHashMap<>();
        options.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        options.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        options.put("programmes", jdbc.sql("SELECT code, name, dept_code FROM ref.programme WHERE NOT coalesce(archived, false) ORDER BY name").query().listOfRows());
        out.put("options", options);
        return out;
    }

    public record Chosen(@NotNull @Size(min = 1, max = MAX) List<UUID> studentIds) {
    }

    /** before anything is done: which of the students chosen may be reset, and why not the others — checked again as each is reset */
    @PostMapping("/preview")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> preview(Authentication auth, @Valid @RequestBody Chosen body) {
        SupportAccess.Access a = bulkAccess(auth);
        List<Map<String, Object>> rows = new ArrayList<>(jdbc.sql("SELECT * FROM helpdesk.bulk_reset_check(:me, :h, CAST(:ids AS uuid[])) ORDER BY eligible, full_name")
                .param("me", a.agent()).param("h", a.head()).param("ids", idList(body.studentIds())).query().listOfRows());
        rows.forEach(r -> r.put("words", words((String) r.get("code"), (String) r.get("status"))));
        long eligible = rows.stream().filter(r -> Boolean.TRUE.equals(r.get("eligible"))).count();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("selected", rows.size());
        out.put("eligible", eligible);
        out.put("notEligible", rows.size() - eligible);
        out.put("rows", rows);
        Map<String, Object> policy = jdbc.sql("""
                SELECT coalesce(g.student_reset_ticket, 'OPTIONAL') AS ticket, coalesce(g.student_reset_unlock, true) AS unlock_by_default,
                       g.bulk_reset_approval_over AS approval_over
                  FROM (SELECT 1) one LEFT JOIN helpdesk.setting g ON g.row_no
                """).query().singleRow();
        out.put("policy", policy);
        return out;
    }

    public record StartIn(@NotNull @Size(min = 1, max = MAX) List<UUID> studentIds, @NotNull @Size(max = 2000) String reason,
                          Map<UUID, UUID> tickets, Boolean unlock, @Size(max = 80) String key,
                          Boolean resolveTickets, @Size(max = 4000) String resolution, UUID retryOf) {
    }

    /** the operation opened and started; the same key again is the same operation, never a second reset */
    @PostMapping
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> start(Authentication auth, @Valid @RequestBody StartIn body) {
        SupportAccess.Access a = bulkAccess(auth);
        String reason = body.reason().trim();
        if (reason.length() < StudentSupportController.RESET_REASON_MIN) {
            throw new DomainRuleViolation("SUPPORT_REASON_SHORT", "Say why the passwords are reset, in " + StudentSupportController.RESET_REASON_MIN + " characters or more.",
                    new DomainRuleViolation.Remedy("For example: \"Students reported login issues at the desk; identities checked.\"", "You"));
        }
        Map<String, Object> policy = jdbc.sql("""
                SELECT coalesce(g.student_reset_enabled, true) AS enabled, coalesce(g.student_reset_unlock, true) AS unlock_by_default, g.student_reset_hourly AS hourly
                  FROM (SELECT 1) one LEFT JOIN helpdesk.setting g ON g.row_no
                """).query().singleRow();
        if (!Boolean.TRUE.equals(policy.get("enabled"))) {
            throw new DomainRuleViolation("RESET_DISABLED", "PASSWORD RESET TO THE DEFAULT CREDENTIAL IS SWITCHED OFF.",
                    new DomainRuleViolation.Remedy("The Head of the ICT Support Desk or the Director of ICT switches it on in ICT Support Settings.", "Head of ICT Support Desk"));
        }
        String key = blank(body.key());
        boolean repeat = key != null && jdbc.sql("SELECT count(*) FROM helpdesk.bulk_reset WHERE initiated_by = :me AND idempotency_key = :k")
                .param("me", a.agent()).param("k", key).query(Long.class).single() > 0;
        // the desk's hourly limit, when the Director of ICT states one (V526: none by default), counts a bulk reset's students too
        Number hourly = (Number) policy.get("hourly");
        if (hourly != null && !repeat) {
            long lastHour = jdbc.sql("""
                    SELECT count(*) FROM helpdesk.support_action
                     WHERE agent_id = :me AND action = 'PASSWORD_RESET' AND method = 'DEFAULT_CREDENTIAL' AND at >= now() - interval '1 hour'
                    """).param("me", a.agent()).query(Long.class).single();
            if (lastHour + body.studentIds().size() > hourly.intValue()) {
                throw new DomainRuleViolation("SUPPORT_RESET_RATE", "These " + body.studentIds().size() + " resets would pass the desk's limit of " + hourly
                        + " an hour (" + lastHour + " made in the last hour).",
                        new DomainRuleViolation.Remedy("Reset fewer at once, or ask the Head of the ICT Support Desk; the limit is in ICT Support Settings.", "Head of ICT Support Desk"));
            }
        }
        Map<String, String> tickets = new LinkedHashMap<>();
        if (body.tickets() != null) body.tickets().forEach((s, t) -> { if (s != null && t != null) tickets.put(s.toString(), t.toString()); });
        String office = AuditContextHolder.required().actorOffice();
        // V563: the tickets resolved with the reset (with the words the students read), a retry of another operation's students; an
        // operation above the figure in ICT Support Settings waits for a Head's approval (decided in the database)
        UUID id = jdbc.sql("SELECT helpdesk.start_bulk_reset(:me, :o, :h, CAST(:ids AS uuid[]), CAST(:t AS jsonb), :r, :u, :k, :rv, :rt, :ro)")
                .param("me", a.agent()).param("o", office).param("h", a.head()).param("ids", idList(body.studentIds()))
                .param("t", json.writeValueAsString(tickets)).param("r", reason)
                .param("u", body.unlock() == null ? Boolean.TRUE.equals(policy.get("unlock_by_default")) : body.unlock()).param("k", key, Types.VARCHAR)
                .param("rv", Boolean.TRUE.equals(body.resolveTickets())).param("rt", blank(body.resolution()), Types.VARCHAR).param("ro", body.retryOf(), Types.OTHER)
                .query(UUID.class).single();
        // started once this transaction is committed, so the worker reads the operation
        org.springframework.transaction.support.TransactionSynchronizationManager.registerSynchronization(new org.springframework.transaction.support.TransactionSynchronization() {
            @Override
            public void afterCommit() {
                work.start();
            }
        });
        Map<String, Object> out = new LinkedHashMap<>(operation(id));
        out.put("series", series(out));
        out.put("repeat", repeat);
        return out;
    }

    private Map<String, Object> operation(UUID id) {
        return jdbc.sql("""
                SELECT b.id, b.reference, b.status, b.total, b.succeeded, b.failed, b.reason, b.office, b.created_at, b.started_at, b.completed_at,
                       helpdesk.person_name(b.initiated_by) AS performed_by, b.initiated_by,
                       (SELECT count(*) FROM helpdesk.bulk_reset_item i WHERE i.bulk_id = b.id AND i.status <> 'PENDING') AS processed,
                       b.resolve_tickets, b.resolution, b.retry_of, (SELECT o.reference FROM helpdesk.bulk_reset o WHERE o.id = b.retry_of) AS retry_of_reference,
                       b.approval_over, helpdesk.person_name(b.decided_by) AS decided_by, b.decided_at, b.decision_note, b.series_id, b.part, b.parts
                  FROM helpdesk.bulk_reset b WHERE b.id = :b
                """).param("b", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("bulk password reset", id));
    }

    /** V565: the parts of a request of more than 1,000 students, in order, with their counts (none for one of 1,000 or fewer) */
    private List<Map<String, Object>> series(Map<String, Object> op) {
        if (op.get("series_id") == null) return List.of();
        return jdbc.sql("""
                SELECT b.id, b.reference, b.part, b.status, b.total, b.succeeded, b.failed, b.completed_at,
                       (SELECT count(*) FROM helpdesk.bulk_reset_item i WHERE i.bulk_id = b.id AND i.status <> 'PENDING') AS processed
                  FROM helpdesk.bulk_reset b WHERE b.series_id = :s ORDER BY b.part
                """).param("s", op.get("series_id")).query().listOfRows();
    }

    /** the one who made it, or a Head */
    private void mine(SupportAccess.Access a, Map<String, Object> op, UUID id) {
        if (!a.head() && !a.agent().equals(op.get("initiated_by"))) {
            throw new NotFound("bulk password reset", id);
        }
    }

    /** an operation and each student's result — for the one who made it, the Head and the Director, or a reader of the reset history */
    @GetMapping("/{id}")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> one(Authentication auth, @PathVariable UUID id) {
        SupportAccess.Access a = support.access(auth);
        Map<String, Object> op = new LinkedHashMap<>(operation(id));
        if (!a.head() && !a.agent().equals(op.get("initiated_by")) && !a.has("VIEW_RESET_HISTORY")) {
            throw new NotFound("bulk password reset", id);
        }
        List<Map<String, Object>> items = new ArrayList<>(jdbc.sql("""
                SELECT i.student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name,
                       coalesce(s.matric_no, s.admission_no) AS number, p.name AS programme, f.name AS faculty, s.current_level AS level,
                       i.status, i.failure_code, i.failure_words, i.processed_at, t.number AS ticket_number, i.ticket_id,
                       i.ticket_resolved_at, i.link_sent_at, i.link_to, i.link_failure
                  FROM helpdesk.bulk_reset_item i
                  JOIN people.student s ON s.id = i.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN helpdesk.ticket t ON t.id = i.ticket_id
                 WHERE i.bulk_id = :b ORDER BY i.ord
                """).param("b", id).query().listOfRows());
        op.put("items", items);
        op.put("missing", Math.max(0, ((Number) op.get("total")).intValue() - items.size()));   // chosen ids that named no student
        // V563: the operations that tried its students again, and what the reader may do with it
        op.put("retries", jdbc.sql("SELECT id, reference, status, created_at FROM helpdesk.bulk_reset WHERE retry_of = :b ORDER BY created_at")
                .param("b", id).query().listOfRows());
        op.put("series", series(op));
        boolean own = a.agent().equals(op.get("initiated_by"));
        op.put("mayDecide", a.head() && !own && "AWAITING_APPROVAL".equals(op.get("status")));
        op.put("mayAct", a.head() || own);
        return op;
    }

    /** an operation still running stops: the students not yet reached are not reset */
    @PostMapping("/{id}/cancel")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> cancel(Authentication auth, @PathVariable UUID id) {
        SupportAccess.Access a = support.access(auth);
        Map<String, Object> op = operation(id);
        mine(a, op, id);
        // the operation is marked first, so the tally keeps it CANCELLED; one that has ended is left as it is (V563: one waiting for
        // approval is withdrawn so; V565: every part of a request not yet ended with it)
        List<UUID> stopped = jdbc.sql("""
                UPDATE helpdesk.bulk_reset SET status = 'CANCELLED', completed_at = now()
                 WHERE (id = :b OR (CAST(:s AS uuid) IS NOT NULL AND series_id = CAST(:s AS uuid))) AND status IN ('AWAITING_APPROVAL', 'PENDING', 'PROCESSING')
                RETURNING id
                """).param("b", id).param("s", op.get("series_id"), Types.OTHER).query(UUID.class).list();
        for (UUID b : stopped) {
            jdbc.sql("""
                    UPDATE helpdesk.bulk_reset_item SET status = 'FAILED', failure_code = 'CANCELLED', failure_words = :w, processed_at = now()
                     WHERE bulk_id = :b AND status = 'PENDING'
                    """).param("w", words("CANCELLED", null)).param("b", b).update();
            jdbc.sql("SELECT helpdesk.bulk_reset_tally(:b)").param("b", b).query(String.class).single();
        }
        return operation(id);
    }

    public record Decision(@Size(max = 2000) String note) {
    }

    /** V563: an operation waiting for approval approved by a Head other than the one who asked — it runs at once */
    @PostMapping("/{id}/approve")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> approve(Authentication auth, @PathVariable UUID id, @Valid @RequestBody(required = false) Decision body) {
        return decide(auth, id, true, body == null ? null : body.note());
    }

    /** V563: an operation waiting for approval declined on a reason — no student is reset */
    @PostMapping("/{id}/reject")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> reject(Authentication auth, @PathVariable UUID id, @Valid @RequestBody(required = false) Decision body) {
        return decide(auth, id, false, body == null ? null : body.note());
    }

    private Map<String, Object> decide(Authentication auth, UUID id, boolean approve, String note) {
        SupportAccess.Access a = support.access(auth);
        operation(id);
        jdbc.sql("SELECT helpdesk.decide_bulk_reset(:b, :me, :h, :ok, :n)").param("b", id).param("me", a.agent()).param("h", a.head())
                .param("ok", approve).param("n", blank(note), Types.VARCHAR).query(String.class).single();
        if (approve) {
            org.springframework.transaction.support.TransactionSynchronizationManager.registerSynchronization(new org.springframework.transaction.support.TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    work.start();
                }
            });
        }
        return operation(id);
    }

    public record LinksIn(@Size(max = 2000) String reason) {
    }

    /**
     * V563: the single reset's one-hour link sent to the operation's students refused for want of a matriculation number — each
     * checked again, to the e-mail and phone on the record; where each went (masked) or why not
     */
    @PostMapping("/{id}/links")
    @PreAuthorize(AGENTS)
    Map<String, Object> links(Authentication auth, @PathVariable UUID id, @Valid @RequestBody(required = false) LinksIn body) {
        SupportAccess.Access a = bulkAccess(auth);
        Map<String, Object> op = operation(id);
        mine(a, op, id);
        String reason = blank(body == null ? null : body.reason()) != null ? body.reason().trim()
                : "Reset link after bulk reset " + op.get("reference") + " for a student without a matriculation number";
        if (reason.length() < StudentSupportController.RESET_REASON_MIN) {
            throw new DomainRuleViolation("SUPPORT_REASON_SHORT", "Say why the links are sent, in " + StudentSupportController.RESET_REASON_MIN + " characters or more.",
                    new DomainRuleViolation.Remedy("Or leave the reason empty: the operation's reference is given.", "You"));
        }
        List<Map<String, Object>> rows = work.sendLinks(id, a.agent(), a.head(), AuditContextHolder.required().actorOffice(), reason);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("sent", rows.stream().filter(r -> Boolean.TRUE.equals(r.get("sent"))).count());
        out.put("notSent", rows.stream().filter(r -> !Boolean.TRUE.equals(r.get("sent"))).count());
        out.put("rows", rows);
        return out;
    }

    /** the bulk resets, newest first — the agent's own, or every one for the Head, the Director and readers of the reset history */
    @GetMapping
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> history(Authentication auth, @RequestParam(required = false) String from, @RequestParam(required = false) String to,
                                @RequestParam(required = false) String status, @RequestParam(required = false) String q,
                                @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "25") int size) {
        SupportAccess.Access a = support.access(auth);
        boolean everyone = a.head() || a.has("VIEW_RESET_HISTORY");
        int sz = Math.max(1, Math.min(size, 200));
        int pg = Math.max(1, page);
        String where = """
                 WHERE (:all OR b.initiated_by = :me)
                   AND (:from::date IS NULL OR (b.created_at AT TIME ZONE 'Africa/Lagos')::date >= :from::date)
                   AND (:to::date IS NULL OR (b.created_at AT TIME ZONE 'Africa/Lagos')::date <= :to::date)
                   AND (:status::text IS NULL OR b.status = :status)
                   AND (:q::text IS NULL OR upper(b.reference) LIKE :qp OR upper(helpdesk.person_name(b.initiated_by)) LIKE :qa
                        OR EXISTS (SELECT 1 FROM helpdesk.bulk_reset_item i JOIN helpdesk.ticket t ON t.id = i.ticket_id WHERE i.bulk_id = b.id AND upper(t.number) = :qu))
                """;
        String term = blank(q);
        java.util.function.Function<JdbcClient.StatementSpec, JdbcClient.StatementSpec> b = spec -> spec.param("all", everyone).param("me", a.agent())
                .param("from", blank(from), Types.VARCHAR).param("to", blank(to), Types.VARCHAR)
                .param("status", blank(status) == null ? null : status.trim().toUpperCase(), Types.VARCHAR)
                .param("q", term, Types.VARCHAR).param("qp", term == null ? null : term.toUpperCase() + "%", Types.VARCHAR)
                .param("qa", term == null ? null : "%" + term.toUpperCase() + "%", Types.VARCHAR).param("qu", term == null ? null : term.toUpperCase(), Types.VARCHAR);
        long total = b.apply(jdbc.sql("SELECT count(*) FROM helpdesk.bulk_reset b " + where)).query(Long.class).single();
        List<Map<String, Object>> rows = b.apply(jdbc.sql("""
                SELECT b.id, b.reference, b.created_at, helpdesk.person_name(b.initiated_by) AS performed_by, b.office, b.reason, b.total, b.succeeded,
                       b.failed, b.status, b.completed_at, b.part, b.parts,
                       (SELECT string_agg(DISTINCT t.number, ', ') FROM helpdesk.bulk_reset_item i JOIN helpdesk.ticket t ON t.id = i.ticket_id WHERE i.bulk_id = b.id) AS tickets
                  FROM helpdesk.bulk_reset b
                """ + where + " ORDER BY b.created_at DESC LIMIT :n OFFSET :o")).param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        out.put("everyone", everyone);
        return out;
    }
}
