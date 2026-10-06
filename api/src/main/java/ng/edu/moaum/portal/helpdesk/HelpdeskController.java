package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.auth.PasswordResetService;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
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
 * The ICT support desk (V251, across the University V328) under /api/v1/helpdesk.
 *   /my/…       the requester — any student or member of staff signed in — raises, reads, answers, confirms, reopens, withdraws
 *   /tickets/…  the desk — ICT Support Agents, the Head of ICT Support Desk, the Director of ICT, the administrators — the queue,
 *               the ticket, the acts on it; an agent within the scope of their postings (helpdesk.can_view), a head everywhere
 *   /queues, /workload   the queues and the agents' load
 *   /office/…   a University office a ticket was escalated to — it reads the ticket and answers it
 *   /admin/…    the Head and the Director — categories, SLAs, the quiet spell, the queues, the routing rules, the agents' postings
 *   /track      the public page — a ticket number and the email it was raised with
 * A requester sees only their own tickets and never an internal note; support access is never administrative authority.
 */
@RestController
@RequestMapping("/api/v1/helpdesk")
class HelpdeskController {

    private static final String AGENTS = "hasAnyAuthority('OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String DIRECTOR = "hasAnyAuthority('OFFICE_helpdeskhead','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String REQUESTER = "isAuthenticated() and !hasAnyAuthority('OFFICE_applicant','OFFICE_pgapplicant')";
    private static final String OFFICER = "isAuthenticated() and !hasAnyAuthority('OFFICE_student','OFFICE_applicant','OFFICE_pgapplicant')";
    private static final Set<String> HEADS = Set.of("OFFICE_helpdeskhead", "OFFICE_ict", "OFFICE_admin", "OFFICE_super");
    private static final long MAX_BYTES = 5L * 1024 * 1024;
    private static final Set<String> TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    private static final Set<String> PRIORITIES = Set.of("LOW", "NORMAL", "HIGH", "URGENT", "CRITICAL");
    private static final Set<String> SCOPES = Set.of("GLOBAL", "FACULTY", "COLLEGE", "DEPARTMENT", "OFFICE");
    private static final Set<String> AVAILABILITY = Set.of("AVAILABLE", "BUSY", "AWAY", "OFFLINE", "ON_LEAVE");
    private static final Set<String> STRATEGIES = Set.of("ROUND_ROBIN", "LEAST_LOADED", "MANUAL", "QUEUE_ONLY", "FACULTY_AGENT_FIRST", "OFFICE_AGENT_FIRST");
    private static final String PRIORITY_RANK = "CASE t.priority WHEN 'CRITICAL' THEN 5 WHEN 'URGENT' THEN 4 WHEN 'HIGH' THEN 3 WHEN 'NORMAL' THEN 2 ELSE 1 END";
    private static final String SLA_ORDER = "ORDER BY CASE priority WHEN 'CRITICAL' THEN 0 WHEN 'URGENT' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'NORMAL' THEN 3 ELSE 4 END";
    /** what the requester and the public never see of the desk's own business */
    private static final String DESK_ACTIONS = "'INTERNAL_NOTE','ESCALATED','PRIORITY_CHANGED','ROUTED','QUEUED','RETURNED','ESCALATED_TO_OFFICE','OFFICE_ANSWERED'";
    private static final Set<String> FIELD_TYPES = Set.of("text", "date", "number", "select", "session", "semester", "level");
    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    /** a ticket as the lists show it */
    private static final String ROW = """
            SELECT t.id, t.number, t.subject, t.status, t.priority, t.created_at, t.updated_at, t.resolved_at, t.closed_at, t.reopen_count,
                   c.code AS category_code, c.name AS category, t.requester_kind, t.requester_name, t.requester_number, t.requester_email,
                   t.department_code, d.name AS department, t.faculty_code, f.name AS faculty,
                   t.assigned_to, helpdesk.person_name(t.assigned_to) AS agent, t.escalated_to IS NOT NULL AS escalated,
                   t.queue_code, qu.name AS queue, t.escalated_office, oo.label AS office, t.waiting_since,
                   helpdesk.due_at(t.created_at, t.priority) AS due_at,
                   (t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.due_at(t.created_at, t.priority) < now()) AS overdue,
                   (t.first_response_at IS NULL AND t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.response_due_at(t.created_at, t.priority) < now()) AS response_overdue,
                   (SELECT count(*) FROM helpdesk.ticket_attachment a WHERE a.ticket_id = t.id AND NOT a.internal) AS attachments
              FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
              LEFT JOIN ref.department d ON d.code = t.department_code LEFT JOIN ref.faculty f ON f.code = t.faculty_code
              LEFT JOIN helpdesk.queue qu ON qu.code = t.queue_code LEFT JOIN ref.office oo ON oo.code = t.escalated_office
            """;

    private final FileObjects files;
    private final JdbcClient jdbc;
    private final TicketNotifier notifier;
    private final PasswordResetService resets;

    HelpdeskController(FileObjects files, JdbcClient jdbc, TicketNotifier notifier, PasswordResetService resets) {
        this.jdbc = jdbc;
        this.files = files;
        this.notifier = notifier;
        this.resets = resets;
    }

    /* ── who is asking ── */

    record Who(String kind, UUID id, String name, String number, String email, String phone, String departmentCode, String department,
               String facultyCode, String faculty, String programme) {
    }

    private static boolean has(Authentication auth, String authority) {
        for (GrantedAuthority a : auth.getAuthorities()) if (authority.equals(a.getAuthority())) return true;
        return false;
    }

    /** the requester as the account knows them: a student from the register and their contact, staff from the person and their office */
    private Who who(Authentication auth) {
        UUID id = UUID.fromString(auth.getName());
        if (has(auth, "OFFICE_student")) {
            Map<String, Object> s = jdbc.sql("""
                    SELECT st.id, st.surname || ', ' || st.other_names AS name, coalesce(st.matric_no, st.admission_no) AS number,
                           r.email, r.phone, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty, p.name AS programme
                      FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
                      JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = p.faculty_code
                      LEFT JOIN LATERAL people.student_reach(st.id) r ON true
                     WHERE st.id = :id
                    """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", id));
            return new Who("STUDENT", id, (String) s.get("name"), (String) s.get("number"), (String) s.get("email"), (String) s.get("phone"),
                    (String) s.get("dept_code"), (String) s.get("department"), (String) s.get("faculty_code"), (String) s.get("faculty"), (String) s.get("programme"));
        }
        Map<String, Object> p = jdbc.sql("""
                SELECT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number, p.email, p.phone,
                       dep.code AS dept_code, dep.name AS department, fac.code AS faculty_code, fac.name AS faculty
                  FROM iam.person p
                  LEFT JOIN LATERAL (SELECT a.scope_id FROM iam.office_assignment a
                                      WHERE a.person_id = p.id AND a.scope_kind = 'department' AND nullif(btrim(a.scope_id), '') IS NOT NULL
                                        AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                                      ORDER BY a.valid_from DESC LIMIT 1) sc ON true
                  LEFT JOIN ref.department dep ON dep.code = sc.scope_id
                  LEFT JOIN ref.faculty fac ON fac.code = coalesce(dep.faculty_code,
                        (SELECT a.scope_id FROM iam.office_assignment a WHERE a.person_id = p.id AND a.scope_kind = 'faculty' AND nullif(btrim(a.scope_id), '') IS NOT NULL
                           AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) ORDER BY a.valid_from DESC LIMIT 1))
                 WHERE p.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new DomainRuleViolation("HELPDESK_NOT_A_MEMBER",
                "Tickets are raised by students and members of staff signed in to the portal.",
                new DomainRuleViolation.Remedy("Sign in with your student or staff account.", "Directorate of ICT")));
        return new Who("STAFF", id, (String) p.get("name"), (String) p.get("staff_number"), (String) p.get("email"), (String) p.get("phone"),
                (String) p.get("dept_code"), (String) p.get("department"), (String) p.get("faculty_code"), (String) p.get("faculty"), null);
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private String myName(Authentication auth) {
        return jdbc.sql("SELECT helpdesk.person_name(:id)").param("id", me(auth)).query(String.class).optional().orElse("The ICT desk");
    }

    /* ── the requester's side ── */

    @GetMapping("/my/profile")
    @PreAuthorize(REQUESTER)
    @Transactional(readOnly = true)
    Map<String, Object> profile(Authentication auth) {
        Who w = who(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", w.kind()); out.put("name", w.name()); out.put("number", w.number()); out.put("email", w.email()); out.put("phone", w.phone());
        out.put("department", w.department()); out.put("departmentCode", w.departmentCode()); out.put("faculty", w.faculty()); out.put("facultyCode", w.facultyCode());
        out.put("programme", w.programme());
        out.put("openTickets", jdbc.sql("SELECT count(*) FROM helpdesk.ticket WHERE requester_kind = :k AND requester_id = :id AND status <> 'CLOSED'")
                .param("k", w.kind()).param("id", w.id()).query(Long.class).single());
        return out;
    }

    /** the categories open for a new ticket, each with the fields it asks for */
    @GetMapping("/categories")
    @PreAuthorize(REQUESTER)
    @Transactional(readOnly = true)
    List<Map<String, Object>> categories() {
        return jdbc.sql("SELECT id, code, name, description, suggested_priority, fields::text AS fields, attachment_hint FROM helpdesk.category WHERE active AND code <> 'JUPEB' ORDER BY ordinal, name")
                .query().listOfRows();
    }

    @GetMapping("/my/tickets")
    @PreAuthorize(REQUESTER)
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine(Authentication auth) {
        Who w = who(auth);
        return jdbc.sql(ROW + " WHERE t.requester_kind = :k AND t.requester_id = :id ORDER BY (t.status = 'CLOSED'), t.updated_at DESC LIMIT 200")
                .param("k", w.kind()).param("id", w.id()).query().listOfRows();
    }

    public record Submit(@NotBlank @Size(max = 40) String category, @NotBlank @Size(max = 200) String subject, @NotBlank @Size(max = 8000) String description,
                         @Size(max = 200) String email, @Size(max = 30) String phone, Map<String, String> details) {
    }

    @PostMapping("/my/tickets")
    @PreAuthorize(REQUESTER)
    @Transactional
    Map<String, Object> submit(Authentication auth, @Valid @RequestBody Submit body) {
        Who w = who(auth);
        // the notices go to the address the account holds; a requester types one only where the account has none
        String email = w.email() != null && !w.email().isBlank() ? w.email().trim() : body.email() == null ? null : body.email().trim();
        String phone = body.phone() == null || body.phone().isBlank() ? w.phone() : body.phone().trim();
        Map<String, String> details = new LinkedHashMap<>();
        Set<String> declared = declaredKeys(body.category());
        if (body.details() != null) body.details().forEach((k, v) -> {
            if (k != null && declared.contains(k) && v != null && !v.isBlank() && details.size() < 30) details.put(k, v.trim().substring(0, Math.min(v.trim().length(), 500)));
        });
        UUID id = jdbc.sql("SELECT helpdesk.submit(:k, :id, :n, :num, :e, :ph, :d, :f, :c, :s, :desc, :j::jsonb)")
                .param("k", w.kind()).param("id", w.id()).param("n", w.name()).param("num", w.number(), Types.VARCHAR)
                .param("e", email, Types.VARCHAR).param("ph", phone, Types.VARCHAR).param("d", w.departmentCode(), Types.VARCHAR).param("f", w.facultyCode(), Types.VARCHAR)
                .param("c", body.category()).param("s", body.subject().trim()).param("desc", body.description().trim()).param("j", JSON.writeValueAsString(details))
                .query(UUID.class).single();
        // V328: routed to its queue by the category's rule, and to an available agent whose scope covers it — or queued for the Head
        jdbc.sql("SELECT helpdesk.route(:t)").param("t", id).query(String.class).single();
        notifier.submitted(id);
        String number = jdbc.sql("SELECT number FROM helpdesk.ticket WHERE id = :id").param("id", id).query(String.class).single();
        return Map.of("id", id, "number", number, "status", "SUBMITTED");
    }

    @GetMapping("/my/tickets/{id}")
    @PreAuthorize(REQUESTER)
    @Transactional(readOnly = true)
    Map<String, Object> myTicket(Authentication auth, @PathVariable UUID id) {
        Who w = who(auth);
        requireMine(id, w);
        return detail(id, false);
    }

    public record Say(@NotBlank @Size(max = 8000) String body) {
    }

    @PostMapping("/my/tickets/{id}/comments")
    @PreAuthorize(REQUESTER)
    @Transactional
    Map<String, Object> mySay(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Say body) {
        Who w = who(auth);
        requireMine(id, w);
        UUID c = jdbc.sql("SELECT helpdesk.comment(:t, 'REQUESTER', :a, :n, false, :b)").param("t", id).param("a", w.id()).param("n", w.name()).param("b", body.body().trim())
                .query(UUID.class).single();
        notifier.requesterUpdate(id, excerpt(body.body()));
        return Map.of("id", c);
    }

    public record Upload(@NotBlank @Size(max = 200) String filename, @NotBlank String contentType, @NotBlank @Size(max = 7_100_000) String contentBase64, Boolean internal) {
    }

    @PostMapping("/my/tickets/{id}/attachments")
    @PreAuthorize(REQUESTER)
    @Transactional
    Map<String, Object> myAttach(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Upload body) {
        Who w = who(auth);
        requireMine(id, w);
        return store(id, "REQUESTER", w.id(), w.name(), body, false);
    }

    @GetMapping("/my/tickets/{id}/attachments/{att}/content")
    @PreAuthorize(REQUESTER)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> myContent(Authentication auth, @PathVariable UUID id, @PathVariable UUID att) {
        Who w = who(auth);
        requireMine(id, w);
        return content(id, att, false);
    }

    public record Reason(@Size(max = 2000) String reason) {
    }

    /** the requester is satisfied: RESOLVED → CLOSED */
    @PostMapping("/my/tickets/{id}/confirm")
    @PreAuthorize(REQUESTER)
    @Transactional
    Map<String, Object> confirm(Authentication auth, @PathVariable UUID id) {
        Who w = who(auth);
        requireMine(id, w);
        String status = jdbc.sql("SELECT status FROM helpdesk.ticket WHERE id = :id").param("id", id).query(String.class).single();
        if (!"RESOLVED".equals(status)) {
            throw new DomainRuleViolation("HELPDESK_NOT_RESOLVED", "Only a resolved ticket is confirmed.",
                    new DomainRuleViolation.Remedy("Wait for the desk's resolution, or close the ticket if you no longer need it.", "Directorate of ICT"));
        }
        jdbc.sql("SELECT helpdesk.transition(:t, 'CLOSED', 'REQUESTER', :a, :n, NULL)").param("t", id).param("a", w.id()).param("n", w.name()).query().singleRow();
        notifier.closed(id);
        return Map.of("id", id, "status", "CLOSED");
    }

    /** the requester is not satisfied: RESOLVED → REOPENED, on a reason */
    @PostMapping("/my/tickets/{id}/reopen")
    @PreAuthorize(REQUESTER)
    @Transactional
    Map<String, Object> reopen(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Reason body) {
        Who w = who(auth);
        requireMine(id, w);
        jdbc.sql("SELECT helpdesk.transition(:t, 'REOPENED', 'REQUESTER', :a, :n, :r)").param("t", id).param("a", w.id()).param("n", w.name())
                .param("r", body.reason(), Types.VARCHAR).query().singleRow();
        notifier.reopened(id, body.reason() == null ? "" : body.reason().trim(), false);
        return Map.of("id", id, "status", "REOPENED");
    }

    /** the requester no longer needs it: any open status → CLOSED */
    @PostMapping("/my/tickets/{id}/close")
    @PreAuthorize(REQUESTER)
    @Transactional
    Map<String, Object> withdraw(Authentication auth, @PathVariable UUID id, @Valid @RequestBody(required = false) Reason body) {
        Who w = who(auth);
        requireMine(id, w);
        jdbc.sql("SELECT helpdesk.transition(:t, 'CLOSED', 'REQUESTER', :a, :n, :r)").param("t", id).param("a", w.id()).param("n", w.name())
                .param("r", body == null ? null : body.reason(), Types.VARCHAR).query().singleRow();
        notifier.closed(id);
        return Map.of("id", id, "status", "CLOSED");
    }

    /* ── the desk ── */

    /** the queue: searched, filtered, sorted, paged on the server; an agent sees only what their postings cover (V328) */
    @GetMapping("/tickets")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> queue(Authentication auth,
                              @RequestParam(required = false) String q, @RequestParam(required = false) String status, @RequestParam(required = false) String category,
                              @RequestParam(required = false) String priority, @RequestParam(required = false) String agent,
                              @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                              @RequestParam(required = false) String faculty, @RequestParam(required = false) String department,
                              @RequestParam(required = false) String queue, @RequestParam(required = false) String office,
                              @RequestParam(defaultValue = "false") boolean overdue, @RequestParam(defaultValue = "false") boolean escalated,
                              @RequestParam(defaultValue = "updated") String sort, @RequestParam(defaultValue = "desc") String dir,
                              @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "20") int size) {
        int sz = Math.max(1, Math.min(size, 100));
        int pg = Math.max(1, page);
        // the desk's order of attention: priority first, then the most recently touched; every other sort falls back to it
        String order = switch (sort) {
            case "created" -> "t.created_at";
            case "priority" -> PRIORITY_RANK;
            case "status" -> "t.status";
            case "number" -> "t.number";
            case "due" -> "helpdesk.due_at(t.created_at, t.priority)";
            case "queue" -> "t.queue_code";
            default -> "t.updated_at";
        };
        String direction = "asc".equalsIgnoreCase(dir) ? "ASC" : "DESC";
        String then = "priority".equals(sort) ? "t.updated_at DESC" : "t.created_at DESC";
        List<String> statuses = status == null || status.isBlank() || "all".equalsIgnoreCase(status) ? List.of()
                : "open".equalsIgnoreCase(status) ? List.of("SUBMITTED", "OPENED", "IN_PROGRESS", "REOPENED", "WAITING_FOR_STUDENT", "WAITING_FOR_OFFICE")
                : "waiting".equalsIgnoreCase(status) ? List.of("WAITING_FOR_STUDENT", "WAITING_FOR_OFFICE")
                : "new".equalsIgnoreCase(status) ? List.of("SUBMITTED")
                : "active".equalsIgnoreCase(status) ? List.of("OPENED", "IN_PROGRESS", "REOPENED")
                : List.of(status.toUpperCase().split(","));
        boolean unassigned = "none".equalsIgnoreCase(agent);
        UUID agentId = agent == null || agent.isBlank() || unassigned ? null : "me".equalsIgnoreCase(agent) ? me(auth) : uuid(agent, "agent");
        String like = q == null || q.isBlank() ? null : "%" + q.trim() + "%";
        String where = """
                 WHERE (:like::text IS NULL OR t.number ILIKE :like OR t.subject ILIKE :like OR t.requester_name ILIKE :like OR t.requester_number ILIKE :like
                        OR t.requester_email ILIKE :like OR t.details->>'payment_reference' ILIKE :like OR t.details->>'username' ILIKE :like)
                   AND (:nst = 0 OR t.status = ANY(string_to_array(:st, ',')))
                   AND (:cat::text IS NULL OR c.code = :cat)
                   AND (:pri::text IS NULL OR t.priority = :pri)
                   AND (NOT :unassigned OR t.assigned_to IS NULL)
                   AND (:agent::uuid IS NULL OR t.assigned_to = :agent)
                   AND (:from::date IS NULL OR t.created_at >= :from)
                   AND (:to::date IS NULL OR t.created_at < :to + 1)
                   AND (:fac::text IS NULL OR t.faculty_code = :fac)
                   AND (:dep::text IS NULL OR t.department_code = :dep)
                   AND (:queue::text IS NULL OR t.queue_code = :queue)
                   AND (:office::text IS NULL OR t.escalated_office = :office)
                   AND (NOT :overdue OR (t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.due_at(t.created_at, t.priority) < now()))
                   AND (NOT :escalated OR (t.status NOT IN ('RESOLVED','CLOSED') AND (t.escalated_to IS NOT NULL OR t.escalated_office IS NOT NULL)))
                   AND (:head OR helpdesk.can_view(:me, t.id))
                """;
        java.util.function.Function<String, JdbcClient.StatementSpec> with = sql -> jdbc.sql(sql)
                .param("like", like, Types.VARCHAR).param("nst", statuses.size()).param("st", String.join(",", statuses))
                .param("cat", category == null || category.isBlank() ? null : category.toUpperCase(), Types.VARCHAR)
                .param("pri", priority == null || priority.isBlank() ? null : priority.toUpperCase(), Types.VARCHAR)
                .param("unassigned", unassigned).param("agent", agentId, Types.OTHER)
                .param("from", from, Types.DATE).param("to", to, Types.DATE)
                .param("fac", faculty == null || faculty.isBlank() ? null : faculty, Types.VARCHAR).param("dep", department == null || department.isBlank() ? null : department, Types.VARCHAR)
                .param("queue", queue == null || queue.isBlank() ? null : queue.trim().toUpperCase(), Types.VARCHAR)
                .param("office", office == null || office.isBlank() ? null : office.trim().toLowerCase(), Types.VARCHAR)
                .param("overdue", overdue).param("escalated", escalated)
                .param("head", head(auth)).param("me", me(auth));
        List<Map<String, Object>> rows = with.apply(ROW.replace("SELECT t.id,", "SELECT count(*) OVER() AS total, t.id,") + where
                + " ORDER BY %s %s, %s LIMIT :n OFFSET :o".formatted(order, direction, then))
                .param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        if (rows.isEmpty() && pg > 1) {
            total = with.apply("SELECT count(*) FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id" + where).query(Long.class).single();
        }
        rows.forEach(r -> r.remove("total"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows); out.put("total", total); out.put("page", pg); out.put("size", sz);
        return out;
    }

    /** what needs attention now, cheaply: the open tickets within the reader's scope counted by the states the desk acts on,
     *  and the reader's own share — one pass over open tickets, no analytics, so the ticket workspace never waits for the figures */
    @GetMapping("/counts")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> counts(Authentication auth) {
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("""
                SELECT count(*) AS open,
                       count(*) FILTER (WHERE t.status = 'SUBMITTED') AS new,
                       count(*) FILTER (WHERE t.assigned_to IS NULL) AS unassigned,
                       count(*) FILTER (WHERE t.priority IN ('URGENT','CRITICAL')) AS urgent,
                       count(*) FILTER (WHERE t.priority = 'CRITICAL') AS critical,
                       count(*) FILTER (WHERE t.escalated_to IS NOT NULL OR t.escalated_office IS NOT NULL) AS escalated,
                       count(*) FILTER (WHERE helpdesk.due_at(t.created_at, t.priority) < now()) AS overdue,
                       count(*) FILTER (WHERE t.status IN ('WAITING_FOR_STUDENT','WAITING_FOR_OFFICE')) AS waiting,
                       count(*) FILTER (WHERE t.assigned_to = :me) AS mine,
                       count(*) FILTER (WHERE t.assigned_to = :me AND t.status IN ('SUBMITTED','OPENED')) AS mine_new,
                       count(*) FILTER (WHERE t.assigned_to = :me AND t.status IN ('IN_PROGRESS','REOPENED')) AS mine_in_progress,
                       count(*) FILTER (WHERE t.assigned_to = :me AND t.status IN ('WAITING_FOR_STUDENT','WAITING_FOR_OFFICE')) AS mine_waiting,
                       count(*) FILTER (WHERE t.escalated_to = :me OR (t.assigned_to = :me AND t.escalated_office IS NOT NULL)) AS mine_escalated,
                       count(*) FILTER (WHERE t.assigned_to = :me AND helpdesk.due_at(t.created_at, t.priority) < now()) AS mine_overdue,
                       max(t.created_at) FILTER (WHERE t.status = 'SUBMITTED') AS latest_new,
                       now() AS at
                  FROM helpdesk.ticket t
                 WHERE t.status NOT IN ('RESOLVED','CLOSED') AND (:head OR helpdesk.can_view(:me, t.id))
                """).param("head", head(auth)).param("me", me(auth)).query().singleRow());
        out.put("head", head(auth));
        return out;
    }

    /** the desk's figures and the Director's analytics, from the same filters as the queue */
    @GetMapping("/stats")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> stats(Authentication auth, @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                              @RequestParam(required = false) String category, @RequestParam(required = false) String priority,
                              @RequestParam(required = false) String agent, @RequestParam(required = false) String faculty, @RequestParam(required = false) String department,
                              @RequestParam(required = false) String queue) {
        String where = """
                 WHERE (:from::date IS NULL OR t.created_at >= :from) AND (:to::date IS NULL OR t.created_at < :to + 1)
                   AND (:cat::text IS NULL OR c.code = :cat) AND (:pri::text IS NULL OR t.priority = :pri)
                   AND (:agent::uuid IS NULL OR t.assigned_to = :agent) AND (NOT :none OR t.assigned_to IS NULL)
                   AND (:fac::text IS NULL OR t.faculty_code = :fac) AND (:dep::text IS NULL OR t.department_code = :dep)
                   AND (:queue::text IS NULL OR t.queue_code = :queue)
                   AND (:head OR helpdesk.can_view(:me, t.id))
                """;
        String base = "FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id LEFT JOIN ref.faculty f ON f.code = t.faculty_code LEFT JOIN ref.department d ON d.code = t.department_code LEFT JOIN helpdesk.queue qu ON qu.code = t.queue_code" + where;
        boolean unassignedOnly = "none".equalsIgnoreCase(agent);
        UUID agentId = agent == null || agent.isBlank() || unassignedOnly ? null : "me".equalsIgnoreCase(agent) ? me(auth) : uuid(agent, "agent");
        java.util.function.Function<String, JdbcClient.StatementSpec> with = sql -> jdbc.sql(sql)
                .param("from", from, Types.DATE).param("to", to, Types.DATE)
                .param("cat", category == null || category.isBlank() ? null : category.toUpperCase(), Types.VARCHAR)
                .param("pri", priority == null || priority.isBlank() ? null : priority.toUpperCase(), Types.VARCHAR)
                .param("agent", agentId, Types.OTHER).param("none", unassignedOnly)
                .param("fac", faculty == null || faculty.isBlank() ? null : faculty, Types.VARCHAR)
                .param("dep", department == null || department.isBlank() ? null : department, Types.VARCHAR)
                .param("queue", queue == null || queue.isBlank() ? null : queue.trim().toUpperCase(), Types.VARCHAR)
                .param("head", head(auth)).param("me", me(auth));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("totals", with.apply("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE t.status = 'SUBMITTED') AS submitted,
                       count(*) FILTER (WHERE t.status = 'OPENED') AS opened,
                       count(*) FILTER (WHERE t.status = 'IN_PROGRESS') AS in_progress,
                       count(*) FILTER (WHERE t.status = 'REOPENED') AS reopened,
                       count(*) FILTER (WHERE t.status = 'RESOLVED') AS resolved,
                       count(*) FILTER (WHERE t.status = 'CLOSED') AS closed,
                       count(*) FILTER (WHERE t.status = 'WAITING_FOR_STUDENT') AS waiting_student,
                       count(*) FILTER (WHERE t.status = 'WAITING_FOR_OFFICE') AS waiting_office,
                       count(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED')) AS open,
                       count(*) FILTER (WHERE t.assigned_to IS NULL AND t.status NOT IN ('RESOLVED','CLOSED')) AS unassigned,
                       count(*) FILTER (WHERE t.priority IN ('HIGH','URGENT','CRITICAL') AND t.status NOT IN ('RESOLVED','CLOSED')) AS high,
                       count(*) FILTER (WHERE t.priority = 'CRITICAL' AND t.status NOT IN ('RESOLVED','CLOSED')) AS critical,
                       count(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.due_at(t.created_at, t.priority) < now()) AS overdue,
                       count(*) FILTER (WHERE t.first_response_at IS NULL AND t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.response_due_at(t.created_at, t.priority) < now()) AS response_overdue,
                       count(*) FILTER (WHERE t.escalated_to IS NOT NULL AND t.status NOT IN ('RESOLVED','CLOSED')) AS escalated,
                       round(avg(EXTRACT(EPOCH FROM (t.first_response_at - t.created_at)) / 3600)::numeric, 1) AS avg_first_response_hours,
                       round(avg(EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 3600) FILTER (WHERE t.resolved_at IS NOT NULL)::numeric, 1) AS avg_resolution_hours,
                       round(avg(EXTRACT(EPOCH FROM (t.closed_at - t.created_at)) / 3600) FILTER (WHERE t.closed_at IS NOT NULL)::numeric, 1) AS avg_closure_hours,
                       count(*) FILTER (WHERE t.resolved_at IS NOT NULL AND t.resolved_at <= helpdesk.due_at(t.created_at, t.priority)) AS resolved_in_sla,
                       count(*) FILTER (WHERE t.resolved_at IS NOT NULL) AS ever_resolved,
                       count(*) FILTER (WHERE t.assigned_to = :me AND t.status NOT IN ('RESOLVED','CLOSED')) AS mine_open
                """ + base).param("me", me(auth)).query().singleRow());
        out.put("byStatus", with.apply("SELECT t.status AS key, count(*) AS n " + base + " GROUP BY t.status ORDER BY n DESC").query().listOfRows());
        out.put("byCategory", with.apply("SELECT c.name AS key, count(*) AS n, count(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED')) AS open " + base + " GROUP BY c.name ORDER BY n DESC").query().listOfRows());
        out.put("byPriority", with.apply("SELECT t.priority AS key, count(*) AS n " + base + " GROUP BY t.priority ORDER BY n DESC").query().listOfRows());
        out.put("byFaculty", with.apply("SELECT coalesce(f.name, 'Not stated') AS key, count(*) AS n " + base + " GROUP BY f.name ORDER BY n DESC LIMIT 20").query().listOfRows());
        out.put("byDepartment", with.apply("SELECT coalesce(d.name, 'Not stated') AS key, count(*) AS n " + base + " GROUP BY d.name ORDER BY n DESC LIMIT 20").query().listOfRows());
        out.put("byRequesterKind", with.apply("SELECT t.requester_kind AS key, count(*) AS n " + base + " GROUP BY t.requester_kind ORDER BY n DESC").query().listOfRows());
        out.put("byQueue", with.apply("""
                SELECT coalesce(qu.name, 'No queue') AS key, t.queue_code, count(*) AS n,
                       count(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED')) AS open,
                       count(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED') AND t.assigned_to IS NULL) AS unassigned,
                       count(*) FILTER (WHERE t.status IN ('WAITING_FOR_STUDENT','WAITING_FOR_OFFICE')) AS waiting,
                       count(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.due_at(t.created_at, t.priority) < now()) AS overdue,
                       round(avg(EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 3600) FILTER (WHERE t.resolved_at IS NOT NULL)::numeric, 1) AS avg_resolution_hours
                """ + base + " GROUP BY qu.name, t.queue_code, qu.ordinal ORDER BY qu.ordinal NULLS LAST, n DESC").query().listOfRows());
        out.put("byAgent", with.apply("""
                SELECT coalesce(helpdesk.person_name(t.assigned_to), 'Unassigned') AS key, t.assigned_to AS agent_id, count(*) AS n,
                       count(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED')) AS open,
                       count(*) FILTER (WHERE t.status IN ('RESOLVED','CLOSED')) AS done,
                       count(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.due_at(t.created_at, t.priority) < now()) AS overdue,
                       round(avg(EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 3600) FILTER (WHERE t.resolved_at IS NOT NULL)::numeric, 1) AS avg_resolution_hours
                """ + base + " GROUP BY t.assigned_to ORDER BY open DESC, n DESC").query().listOfRows());
        out.put("monthly", with.apply("""
                SELECT to_char(m, 'YYYY-MM') AS key,
                       (SELECT count(*) """ + base + " AND t.created_at >= m AND t.created_at < m + interval '1 month') AS created," + """
                       (SELECT count(*) """ + base + " AND t.resolved_at >= m AND t.resolved_at < m + interval '1 month') AS resolved," + """
                       (SELECT count(*) """ + base + " AND t.closed_at >= m AND t.closed_at < m + interval '1 month') AS closed" + """
                  FROM generate_series(date_trunc('month', now()) - interval '11 months', date_trunc('month', now()), interval '1 month') m ORDER BY m
                """).query().listOfRows());
        out.put("sla", jdbc.sql("SELECT priority, first_response_hours, resolution_hours FROM helpdesk.sla " + SLA_ORDER).query().listOfRows());
        return out;
    }

    /** what happened on the desk lately, across every ticket the reader may see: the last acts, newest first */
    @GetMapping("/activity")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> activity(Authentication auth, @RequestParam(defaultValue = "25") int limit) {
        return jdbc.sql("""
                SELECT e.id, e.at, e.actor_kind, e.actor_name, e.action, e.from_value, e.to_value, e.detail, e.internal,
                       t.id AS ticket_id, t.number, t.subject, t.status, t.priority, t.queue_code
                  FROM helpdesk.ticket_event e JOIN helpdesk.ticket t ON t.id = e.ticket_id
                 WHERE (:head OR helpdesk.can_view(:me, t.id))
                 ORDER BY e.at DESC LIMIT :n
                """).param("n", Math.max(1, Math.min(limit, 100))).param("head", head(auth)).param("me", me(auth)).query().listOfRows();
    }

    /** the people the desk can give a ticket to: agents, the Head and the Director, with their postings and open load; against a
     *  ticket, which of them the routing would choose — an eligible agent is posted on its queue and covers its faculty or department */
    @GetMapping("/agents")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> agents(@RequestParam(required = false) UUID ticket) {
        return jdbc.sql("""
                SELECT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number, p.email IS NOT NULL AS reachable,
                       string_agg(DISTINCT o.label, ', ' ORDER BY o.label) AS offices,
                       bool_or(a.office_code = 'ict') AS director,
                       bool_or(a.office_code IN ('helpdeskhead','ict')) AS head,
                       (SELECT count(*) FROM helpdesk.ticket t WHERE t.assigned_to = p.id AND t.status NOT IN ('RESOLVED','CLOSED')) AS open,
                       (SELECT string_agg(DISTINCT q.name, ', ' ORDER BY q.name) FROM helpdesk.agent_assignment aa JOIN helpdesk.queue q ON q.code = aa.queue_code
                         WHERE aa.person_id = p.id AND aa.active) AS queues,
                       (SELECT string_agg(DISTINCT CASE WHEN aa.scope_kind = 'GLOBAL' THEN 'The University' ELSE initcap(lower(aa.scope_kind)) || ' ' || aa.scope_ref END, ', ')
                          FROM helpdesk.agent_assignment aa WHERE aa.person_id = p.id AND aa.active) AS scopes,
                       (SELECT aa.availability FROM helpdesk.agent_assignment aa WHERE aa.person_id = p.id AND aa.active ORDER BY aa.is_primary DESC, aa.created_at LIMIT 1) AS availability,
                       (:t::uuid IS NOT NULL AND EXISTS (SELECT 1 FROM helpdesk.eligible_agents(:t) e WHERE e.person_id = p.id)) AS eligible,
                       (:t::uuid IS NOT NULL AND EXISTS (SELECT 1 FROM helpdesk.eligible_agents(:t) e WHERE e.person_id = p.id AND e.posted)) AS posted
                  FROM iam.person p JOIN iam.office_assignment a ON a.person_id = p.id JOIN ref.office o ON o.code = a.office_code
                 WHERE a.office_code IN ('ictagent','helpdeskhead','ict') AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND p.ended_on IS NULL
                 GROUP BY p.id, p.surname, p.given_names, p.staff_number, p.email ORDER BY 12 DESC, 13 DESC, director, p.surname, p.given_names
                """).param("t", ticket, Types.OTHER).query().listOfRows();
    }

    /** the queues and their load: agents posted and available, open, unassigned, waiting, overdue (V328) */
    @GetMapping("/queues")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> queues() {
        return jdbc.sql("SELECT * FROM helpdesk.queue_workload()").query().listOfRows();
    }

    /** the agents' workload: a head reads every agent's, an agent their own */
    @GetMapping("/workload")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> workload(Authentication auth, @RequestParam(required = false) String queue) {
        return jdbc.sql("SELECT * FROM helpdesk.agent_workload(:q) w WHERE :head OR w.person_id = :me")
                .param("q", queue == null || queue.isBlank() ? null : queue.trim().toUpperCase(), Types.VARCHAR).param("head", head(auth)).param("me", me(auth)).query().listOfRows();
    }

    /** the ticket in full; the first agent to read a submitted ticket opens it (§8), and that is recorded */
    @GetMapping("/tickets/{id}")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> ticket(Authentication auth, @PathVariable UUID id) {
        requireVisible(auth, id);
        Boolean opened = jdbc.sql("SELECT helpdesk.open_ticket(:t, :a)").param("t", id).param("a", me(auth)).query(Boolean.class).single();
        if (Boolean.TRUE.equals(opened)) notifier.statusChanged(id);
        return detail(id, true);
    }

    public record Assign(@NotNull UUID agentId, @Size(max = 500) String reason) {
    }

    @PostMapping("/tickets/{id}/assign")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> assign(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Assign body) {
        requireVisible(auth, id);
        UUID before = jdbc.sql("SELECT assigned_to FROM helpdesk.ticket WHERE id = :id").param("id", id).query(UUID.class).optional().orElse(null);
        jdbc.sql("SELECT helpdesk.assign(:t, :a, :by, :r)").param("t", id).param("a", body.agentId()).param("by", me(auth)).param("r", body.reason(), Types.VARCHAR).query().singleRow();
        notifier.assigned(id, body.agentId(), before != null);
        return Map.of("id", id, "assignedTo", body.agentId());
    }

    public record Status(@NotBlank String status, @Size(max = 2000) String reason) {
    }

    /** start work, wait on the requester (on a reason), resume, close on a reason, reopen on a reason — the desk's transitions */
    @PostMapping("/tickets/{id}/status")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> status(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Status body) {
        requireVisible(auth, id);
        String to = body.status().trim().toUpperCase();
        if (!Set.of("OPENED", "IN_PROGRESS", "WAITING_FOR_STUDENT", "CLOSED", "REOPENED").contains(to)) {
            throw new DomainRuleViolation("HELPDESK_STATUS", "The desk moves a ticket to opened, in progress, waiting for the requester, closed or reopened; a resolution is recorded through Resolve, an office through Escalate to Office.",
                    new DomainRuleViolation.Remedy("Choose one of those.", "Directorate of ICT"));
        }
        jdbc.sql("SELECT helpdesk.transition(:t, :to, 'AGENT', :a, :n, :r)").param("t", id).param("to", to).param("a", me(auth)).param("n", myName(auth))
                .param("r", body.reason(), Types.VARCHAR).query().singleRow();
        switch (to) {
            case "CLOSED" -> notifier.closed(id);
            case "REOPENED" -> { notifier.reopened(id, body.reason() == null ? "" : body.reason().trim(), true); notifier.statusChanged(id); }
            case "WAITING_FOR_STUDENT" -> notifier.waiting(id, body.reason() == null ? "" : body.reason().trim());
            default -> notifier.statusChanged(id);
        }
        return Map.of("id", id, "status", to);
    }

    public record Priority(@NotBlank String priority) {
    }

    @PostMapping("/tickets/{id}/priority")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> priority(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Priority body) {
        requireVisible(auth, id);
        String p = body.priority().trim().toUpperCase();
        if (!PRIORITIES.contains(p)) throw new DomainRuleViolation("HELPDESK_PRIORITY", "A priority is low, normal, high, urgent or critical.", new DomainRuleViolation.Remedy("Choose one of the five.", "Directorate of ICT"));
        jdbc.sql("SELECT helpdesk.set_priority(:t, :p, :by)").param("t", id).param("p", p).param("by", me(auth)).query().singleRow();
        if ("CRITICAL".equals(p)) notifier.critical(id, me(auth));
        return Map.of("id", id, "priority", p);
    }

    public record Escalate(@NotNull UUID toPersonId, @NotBlank @Size(max = 2000) String reason) {
    }

    /** escalation to a person of the desk: a senior agent, the Head, the Director */
    @PostMapping("/tickets/{id}/escalate")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> escalate(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Escalate body) {
        requireVisible(auth, id);
        jdbc.sql("SELECT helpdesk.escalate(:t, :to, :by, :r)").param("t", id).param("to", body.toPersonId()).param("by", me(auth)).param("r", body.reason().trim()).query().singleRow();
        notifier.escalated(id, body.toPersonId(), body.reason().trim());
        return Map.of("id", id, "escalatedTo", body.toPersonId());
    }

    public record Transfer(@NotBlank @Size(max = 40) String queue, @NotBlank @Size(max = 2000) String reason) {
    }

    /** V328: the same ticket moved to another queue on a reason — never a second ticket; routed again to an agent there, or queued */
    @PostMapping("/tickets/{id}/transfer")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> transfer(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Transfer body) {
        requireVisible(auth, id);
        Map<String, Object> before = jdbc.sql("SELECT coalesce(q.name, 'no queue') AS queue FROM helpdesk.ticket t LEFT JOIN helpdesk.queue q ON q.code = t.queue_code WHERE t.id = :id").param("id", id).query().singleRow();
        jdbc.sql("SELECT helpdesk.transfer(:t, :q, :by, :r)").param("t", id).param("q", body.queue().trim().toUpperCase()).param("by", me(auth)).param("r", body.reason().trim()).query().singleRow();
        Map<String, Object> after = jdbc.sql("SELECT t.queue_code, q.name AS queue, t.assigned_to FROM helpdesk.ticket t JOIN helpdesk.queue q ON q.code = t.queue_code WHERE t.id = :id").param("id", id).query().singleRow();
        notifier.transferred(id, (String) before.get("queue"), (String) after.get("queue"), body.reason().trim(), (UUID) after.get("assigned_to"));
        return Map.of("id", id, "queue", after.get("queue_code"), "assignedTo", after.get("assigned_to") == null ? "" : after.get("assigned_to"));
    }

    public record EscalateOffice(@NotBlank @Size(max = 40) String office, @NotBlank @Size(max = 2000) String reason) {
    }

    /** V328: a policy or administrative decision goes to the queue's office; a technical fault to the Director of ICT; the ticket waits on them */
    @PostMapping("/tickets/{id}/escalate-office")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> escalateOffice(Authentication auth, @PathVariable UUID id, @Valid @RequestBody EscalateOffice body) {
        requireVisible(auth, id);
        String office = body.office().trim().toLowerCase();
        jdbc.sql("SELECT helpdesk.escalate_to_office(:t, :o, :by, :r)").param("t", id).param("o", office).param("by", me(auth)).param("r", body.reason().trim()).query().singleRow();
        notifier.escalatedToOffice(id, office, body.reason().trim());
        return Map.of("id", id, "office", office, "status", "WAITING_FOR_OFFICE");
    }

    /** V328: the secure reset, through the portal's own door — a one-hour link to the address on the requester's account; the desk never sees a password */
    @PostMapping("/tickets/{id}/password-reset")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> passwordReset(Authentication auth, @PathVariable UUID id, jakarta.servlet.http.HttpServletRequest request) {
        requireVisible(auth, id);
        Map<String, Object> t = jdbc.sql("SELECT status, requester_kind, requester_number, requester_email, requester_name FROM helpdesk.ticket WHERE id = :id").param("id", id).query().singleRow();
        if ("CLOSED".equals(t.get("status"))) throw new DomainRuleViolation("HELPDESK_CLOSED", "A closed ticket takes no further act.", new DomainRuleViolation.Remedy("Reopen it first.", "Directorate of ICT"));
        String identifier = t.get("requester_number") != null && !String.valueOf(t.get("requester_number")).isBlank() ? String.valueOf(t.get("requester_number")) : (String) t.get("requester_email");
        if (identifier == null || identifier.isBlank()) throw new DomainRuleViolation("HELPDESK_NO_IDENTIFIER", "The ticket names no account to reset.", new DomainRuleViolation.Remedy("Ask the requester for their matriculation or staff number.", "Directorate of ICT"));
        resets.forgot(identifier, request.getRemoteAddr());
        String said = "A password reset link has been sent to the email address (and phone, where one is held) on your account. It is valid for one hour. "
                + "Open it to choose a new password; the desk never sees or sets your password.";
        jdbc.sql("SELECT helpdesk.comment(:t, 'AGENT', :a, :n, false, :b)").param("t", id).param("a", me(auth)).param("n", myName(auth)).param("b", said).query(UUID.class).single();
        notifier.agentUpdate(id, said);
        return Map.of("id", id, "sent", true);
    }

    public record Resolve(@NotBlank @Size(max = 300) String summary, @NotBlank @Size(max = 8000) String details) {
    }

    @PostMapping("/tickets/{id}/resolve")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> resolve(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Resolve body) {
        requireVisible(auth, id);
        jdbc.sql("SELECT helpdesk.resolve(:t, :a, :s, :d)").param("t", id).param("a", me(auth)).param("s", body.summary().trim()).param("d", body.details().trim()).query().singleRow();
        notifier.resolved(id);
        return Map.of("id", id, "status", "RESOLVED");
    }

    public record Note(@NotBlank @Size(max = 8000) String body, Boolean internal) {
    }

    /** an internal note the requester never sees, or an update they do */
    @PostMapping("/tickets/{id}/comments")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> note(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Note body) {
        requireVisible(auth, id);
        boolean internal = Boolean.TRUE.equals(body.internal());
        UUID c = jdbc.sql("SELECT helpdesk.comment(:t, 'AGENT', :a, :n, :i, :b)").param("t", id).param("a", me(auth)).param("n", myName(auth)).param("i", internal)
                .param("b", body.body().trim()).query(UUID.class).single();
        if (!internal) notifier.agentUpdate(id, excerpt(body.body()));
        return Map.of("id", c, "internal", internal);
    }

    @PostMapping("/tickets/{id}/attachments")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> deskAttach(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Upload body) {
        requireVisible(auth, id);
        return store(id, "AGENT", me(auth), myName(auth), body, Boolean.TRUE.equals(body.internal()));
    }

    @GetMapping("/tickets/{id}/attachments/{att}/content")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> deskContent(Authentication auth, @PathVariable UUID id, @PathVariable UUID att) {
        requireVisible(auth, id);
        return content(id, att, true);
    }

    /* ── a University office the ticket waits on (V328) ── */

    /** the tickets escalated to an office the reader holds, and those they answered before */
    @GetMapping("/office/tickets")
    @PreAuthorize(OFFICER)
    @Transactional(readOnly = true)
    Map<String, Object> officeTickets(Authentication auth) {
        List<String> offices = offices(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("offices", jdbc.sql("SELECT code, label FROM ref.office WHERE code = ANY(string_to_array(:o, ',')) ORDER BY label").param("o", String.join(",", offices)).query().listOfRows());
        out.put("waiting", jdbc.sql(ROW + " WHERE t.escalated_office = ANY(string_to_array(:o, ',')) AND t.status NOT IN ('CLOSED') ORDER BY t.escalated_at").param("o", String.join(",", offices)).query().listOfRows());
        out.put("answered", jdbc.sql(ROW + """
                 WHERE t.escalated_office IS NULL AND EXISTS (SELECT 1 FROM helpdesk.ticket_event e WHERE e.ticket_id = t.id AND e.action = 'OFFICE_ANSWERED' AND e.actor_id = :me)
                 ORDER BY t.updated_at DESC LIMIT 50
                """).param("me", me(auth)).query().listOfRows());
        return out;
    }

    @GetMapping("/office/tickets/{id}")
    @PreAuthorize(OFFICER)
    @Transactional(readOnly = true)
    Map<String, Object> officeTicket(Authentication auth, @PathVariable UUID id) {
        requireOffice(auth, id);
        return detail(id, true);
    }

    @GetMapping("/office/tickets/{id}/attachments/{att}/content")
    @PreAuthorize(OFFICER)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> officeContent(Authentication auth, @PathVariable UUID id, @PathVariable UUID att) {
        requireOffice(auth, id);
        return content(id, att, true);
    }

    public record Answer(@NotBlank @Size(max = 8000) String body, Boolean internal) {
    }

    /** the office's decision: an instruction to the agent (internal unless the office says otherwise); the ticket returns to the agent */
    @PostMapping("/office/tickets/{id}/answer")
    @PreAuthorize(OFFICER)
    @Transactional
    Map<String, Object> officeAnswer(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Answer body) {
        requireOffice(auth, id);
        boolean internal = body.internal() == null || body.internal();
        UUID c = jdbc.sql("SELECT helpdesk.office_answer(:t, :by, :b, :i)").param("t", id).param("by", me(auth)).param("b", body.body().trim()).param("i", internal).query(UUID.class).single();
        notifier.officeAnswered(id, me(auth));
        if (!internal) notifier.agentUpdate(id, excerpt(body.body()));
        return Map.of("id", c, "ticket", id, "internal", internal);
    }

    /* ── the Director: categories, SLAs, the quiet spell ── */

    @GetMapping("/admin/categories")
    @PreAuthorize(DIRECTOR)
    @Transactional(readOnly = true)
    List<Map<String, Object>> allCategories() {
        return jdbc.sql("""
                SELECT c.id, c.code, c.name, c.description, c.active, c.ordinal, c.suggested_priority, c.fields::text AS fields, c.attachment_hint,
                       (SELECT count(*) FROM helpdesk.ticket t WHERE t.category_id = c.id) AS tickets
                  FROM helpdesk.category c ORDER BY c.active DESC, c.ordinal, c.name
                """).query().listOfRows();
    }

    public record CategoryIn(@Size(max = 32) String code, @NotBlank @Size(max = 120) String name, @Size(max = 500) String description, Boolean active,
                             @Min(1) @Max(999) Integer ordinal, String suggestedPriority, @Size(max = 200) String attachmentHint, List<Map<String, Object>> fields) {
    }

    @PostMapping("/admin/categories")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> newCategory(@Valid @RequestBody CategoryIn body) {
        String code = body.code() == null || body.code().isBlank() ? body.name().trim().toUpperCase().replaceAll("[^A-Z0-9]+", "_").replaceAll("^_+|_+$", "") : body.code().trim().toUpperCase();
        if (!code.matches("[A-Z][A-Z0-9_]{1,30}")) throw new DomainRuleViolation("HELPDESK_CATEGORY_CODE", "A category code is letters, digits and underscores, starting with a letter.", new DomainRuleViolation.Remedy("Give a short code such as PRINTING.", "Directorate of ICT"));
        String pri = body.suggestedPriority() == null ? "NORMAL" : body.suggestedPriority().trim().toUpperCase();
        if (!PRIORITIES.contains(pri)) throw new DomainRuleViolation("HELPDESK_PRIORITY", "A priority is low, normal, high or urgent.", new DomainRuleViolation.Remedy("Choose one of the four.", "Directorate of ICT"));
        UUID id = jdbc.sql("""
                INSERT INTO helpdesk.category (code, name, description, active, ordinal, suggested_priority, attachment_hint, fields)
                VALUES (:c, :n, :d, :a, :o, :p, :h, :f::jsonb) RETURNING id
                """).param("c", code).param("n", body.name().trim()).param("d", body.description(), Types.VARCHAR).param("a", body.active() == null || body.active())
                .param("o", body.ordinal() == null ? 100 : body.ordinal()).param("p", pri).param("h", body.attachmentHint(), Types.VARCHAR).param("f", fieldsJson(body.fields()))
                .query(UUID.class).single();
        return Map.of("id", id, "code", code);
    }

    @PutMapping("/admin/categories/{id}")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> editCategory(@PathVariable UUID id, @Valid @RequestBody CategoryIn body) {
        String pri = body.suggestedPriority() == null ? "NORMAL" : body.suggestedPriority().trim().toUpperCase();
        if (!PRIORITIES.contains(pri)) throw new DomainRuleViolation("HELPDESK_PRIORITY", "A priority is low, normal, high or urgent.", new DomainRuleViolation.Remedy("Choose one of the four.", "Directorate of ICT"));
        int n = jdbc.sql("""
                UPDATE helpdesk.category SET name = :n, description = :d, active = :a, ordinal = :o, suggested_priority = :p, attachment_hint = :h, fields = :f::jsonb
                 WHERE id = :id
                """).param("id", id).param("n", body.name().trim()).param("d", body.description(), Types.VARCHAR).param("a", body.active() == null || body.active())
                .param("o", body.ordinal() == null ? 100 : body.ordinal()).param("p", pri).param("h", body.attachmentHint(), Types.VARCHAR).param("f", fieldsJson(body.fields())).update();
        if (n == 0) throw new NotFound("category", id);
        return Map.of("id", id, "updated", n);
    }

    /** the field definitions, checked: a key, a label, a known type, options for a choice */
    private static String fieldsJson(List<Map<String, Object>> fields) {
        List<Map<String, Object>> out = new ArrayList<>();
        Set<String> seen = new java.util.HashSet<>();
        if (fields != null) {
            for (Map<String, Object> f : fields) {
                if (f == null) continue;
                String key = f.get("key") == null ? "" : String.valueOf(f.get("key")).trim().toLowerCase();
                String label = f.get("label") == null ? "" : String.valueOf(f.get("label")).trim();
                String type = f.get("type") == null ? "text" : String.valueOf(f.get("type")).trim().toLowerCase();
                if (!key.matches("[a-z][a-z0-9_]{0,30}") || label.isBlank() || !FIELD_TYPES.contains(type) || !seen.add(key)) {
                    throw new DomainRuleViolation("HELPDESK_FIELD", "A field has a key (letters, digits, underscores), a label and a type: text, date, number, select, session, semester or level.",
                            new DomainRuleViolation.Remedy("Correct the field and save again.", "Directorate of ICT"));
                }
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("key", key); m.put("label", label); m.put("type", type);
                m.put("required", Boolean.TRUE.equals(f.get("required")) || "true".equals(String.valueOf(f.get("required"))));
                if (f.get("hint") != null && !String.valueOf(f.get("hint")).isBlank()) m.put("hint", String.valueOf(f.get("hint")).trim());
                if ("select".equals(type)) {
                    List<String> options = new ArrayList<>();
                    Object o = f.get("options");
                    if (o instanceof List<?> l) for (Object x : l) { String s = String.valueOf(x).trim(); if (!s.isBlank()) options.add(s); }
                    else if (o != null) for (String s : String.valueOf(o).split("[,;\\n]")) { if (!s.isBlank()) options.add(s.trim()); }
                    if (options.isEmpty()) throw new DomainRuleViolation("HELPDESK_FIELD", "A choice field lists its options.", new DomainRuleViolation.Remedy("Give the options, one per line.", "Directorate of ICT"));
                    m.put("options", options);
                }
                out.add(m);
            }
        }
        return JSON.writeValueAsString(out);
    }

    @GetMapping("/admin/settings")
    @PreAuthorize(DIRECTOR)
    @Transactional(readOnly = true)
    Map<String, Object> settings() {
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT auto_close_days, notify_agents_on_new FROM helpdesk.setting WHERE row_no").query().singleRow());
        out.put("sla", jdbc.sql("SELECT priority, first_response_hours, resolution_hours FROM helpdesk.sla " + SLA_ORDER).query().listOfRows());
        return out;
    }

    /* ── the Head and the Director: the queues, the routing rules, the agents' postings (V328) ── */

    @GetMapping("/admin/queues")
    @PreAuthorize(DIRECTOR)
    @Transactional(readOnly = true)
    Map<String, Object> adminQueues() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("queues", jdbc.sql("""
                SELECT w.*, q.description, q.ordinal, helpdesk.person_name(q.supervisor) AS supervisor FROM helpdesk.queue_workload() w JOIN helpdesk.queue q ON q.code = w.code
                """).query().listOfRows());
        out.put("offices", jdbc.sql("SELECT code, label FROM ref.office WHERE code NOT IN ('student','applicant','pgapplicant','extexaminer','lecturer') ORDER BY label").query().listOfRows());
        return out;
    }

    public record QueueIn(@Size(max = 40) String code, @NotBlank @Size(max = 120) String name, @Size(max = 500) String description, @Size(max = 40) String officeCode,
                          @Min(1) @Max(999) Integer ordinal, Boolean active) {
    }

    private void checkOffice(String office) {
        if (office == null) return;
        Boolean ok = jdbc.sql("SELECT true FROM ref.office WHERE code = :c").param("c", office).query(Boolean.class).optional().orElse(false);
        if (!ok) throw new DomainRuleViolation("HELPDESK_OFFICE_UNKNOWN", "No office is coded " + office + ".", new DomainRuleViolation.Remedy("Choose the office from the list.", "Directorate of ICT"));
    }

    @PostMapping("/admin/queues")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> newQueue(@Valid @RequestBody QueueIn body) {
        String code = body.code() == null || body.code().isBlank() ? body.name().trim().toUpperCase().replaceAll("[^A-Z0-9]+", "_").replaceAll("^_+|_+$", "") : body.code().trim().toUpperCase();
        if (!code.matches("[A-Z][A-Z0-9_]{1,40}")) throw new DomainRuleViolation("HELPDESK_QUEUE_CODE", "A queue code is letters, digits and underscores, starting with a letter.", new DomainRuleViolation.Remedy("Give a short code such as HOSTEL_SUPPORT.", "Directorate of ICT"));
        String office = body.officeCode() == null || body.officeCode().isBlank() ? null : body.officeCode().trim().toLowerCase();
        checkOffice(office);
        if (jdbc.sql("SELECT true FROM helpdesk.queue WHERE code = :c").param("c", code).query(Boolean.class).optional().orElse(false)) {
            throw new DomainRuleViolation("HELPDESK_QUEUE_EXISTS", "A queue is coded " + code + " already.", new DomainRuleViolation.Remedy("Edit that queue, or choose another code.", "Directorate of ICT"));
        }
        jdbc.sql("INSERT INTO helpdesk.queue (code, name, description, office_code, ordinal, active) VALUES (:c, :n, :d, :o, :ord, :a)")
                .param("c", code).param("n", body.name().trim()).param("d", body.description(), Types.VARCHAR).param("o", office, Types.VARCHAR)
                .param("ord", body.ordinal() == null ? 100 : body.ordinal()).param("a", body.active() == null || body.active()).update();
        return Map.of("code", code);
    }

    @PutMapping("/admin/queues/{code}")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> editQueue(@PathVariable String code, @Valid @RequestBody QueueIn body) {
        String office = body.officeCode() == null || body.officeCode().isBlank() ? null : body.officeCode().trim().toLowerCase();
        checkOffice(office);
        int n = jdbc.sql("UPDATE helpdesk.queue SET name = :n, description = :d, office_code = :o, ordinal = :ord, active = :a WHERE code = :c")
                .param("c", code.trim().toUpperCase()).param("n", body.name().trim()).param("d", body.description(), Types.VARCHAR).param("o", office, Types.VARCHAR)
                .param("ord", body.ordinal() == null ? 100 : body.ordinal()).param("a", body.active() == null || body.active()).update();
        if (n == 0) throw new NotFound("queue", code);
        return Map.of("code", code.trim().toUpperCase(), "updated", n);
    }

    @GetMapping("/admin/routing")
    @PreAuthorize(DIRECTOR)
    @Transactional(readOnly = true)
    Map<String, Object> routing() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rules", jdbc.sql("""
                SELECT r.id, r.category_code, c.name AS category, r.faculty_code, f.name AS faculty, r.department_code, d.name AS department,
                       r.queue_code, q.name AS queue, r.strategy, r.priority_floor, r.active, r.created_at
                  FROM helpdesk.routing_rule r JOIN helpdesk.category c ON c.code = r.category_code JOIN helpdesk.queue q ON q.code = r.queue_code
                  LEFT JOIN ref.faculty f ON f.code = r.faculty_code LEFT JOIN ref.department d ON d.code = r.department_code
                 ORDER BY r.active DESC, c.ordinal, c.name, (r.department_code IS NOT NULL) DESC, (r.faculty_code IS NOT NULL) DESC, r.created_at
                """).query().listOfRows());
        out.put("categories", jdbc.sql("SELECT code, name, active FROM helpdesk.category ORDER BY active DESC, ordinal, name").query().listOfRows());
        out.put("queues", jdbc.sql("SELECT code, name, active FROM helpdesk.queue ORDER BY active DESC, ordinal, name").query().listOfRows());
        out.put("unrouted", jdbc.sql("""
                SELECT c.code, c.name FROM helpdesk.category c WHERE c.active
                   AND NOT EXISTS (SELECT 1 FROM helpdesk.routing_rule r WHERE r.category_code = c.code AND r.active AND r.faculty_code IS NULL AND r.department_code IS NULL)
                 ORDER BY c.ordinal, c.name
                """).query().listOfRows());
        return out;
    }

    public record RuleIn(@NotBlank @Size(max = 40) String categoryCode, @Size(max = 20) String facultyCode, @Size(max = 20) String departmentCode,
                         @NotBlank @Size(max = 40) String queueCode, @NotBlank String strategy, String priorityFloor, Boolean active) {
    }

    private RuleIn checkRule(RuleIn body) {
        String strategy = body.strategy().trim().toUpperCase();
        if (!STRATEGIES.contains(strategy)) throw new DomainRuleViolation("HELPDESK_STRATEGY", "A strategy is faculty agent first, office agent first, least loaded, round robin, manual or queue only.", new DomainRuleViolation.Remedy("Choose one of those.", "Directorate of ICT"));
        String floor = body.priorityFloor() == null || body.priorityFloor().isBlank() ? null : body.priorityFloor().trim().toUpperCase();
        if (floor != null && !PRIORITIES.contains(floor)) throw new DomainRuleViolation("HELPDESK_PRIORITY", "A priority is low, normal, high, urgent or critical.", new DomainRuleViolation.Remedy("Choose one of the five.", "Directorate of ICT"));
        if (!jdbc.sql("SELECT true FROM helpdesk.category WHERE code = :c").param("c", body.categoryCode().trim().toUpperCase()).query(Boolean.class).optional().orElse(false)) {
            throw new DomainRuleViolation("HELPDESK_CATEGORY_UNKNOWN", "No category is coded " + body.categoryCode() + ".", new DomainRuleViolation.Remedy("Choose the category from the list.", "Directorate of ICT"));
        }
        if (!jdbc.sql("SELECT true FROM helpdesk.queue WHERE code = :c").param("c", body.queueCode().trim().toUpperCase()).query(Boolean.class).optional().orElse(false)) {
            throw new DomainRuleViolation("HELPDESK_QUEUE_UNKNOWN", "No queue is coded " + body.queueCode() + ".", new DomainRuleViolation.Remedy("Choose the queue from the list.", "Directorate of ICT"));
        }
        String fac = body.facultyCode() == null || body.facultyCode().isBlank() ? null : body.facultyCode().trim().toUpperCase();
        String dep = body.departmentCode() == null || body.departmentCode().isBlank() ? null : body.departmentCode().trim().toUpperCase();
        if (fac != null && !jdbc.sql("SELECT true FROM ref.faculty WHERE code = :c").param("c", fac).query(Boolean.class).optional().orElse(false)) throw new DomainRuleViolation("HELPDESK_SCOPE_UNKNOWN", "No faculty is coded " + fac + ".", new DomainRuleViolation.Remedy("Choose the faculty from the list.", "Directorate of ICT"));
        if (dep != null && !jdbc.sql("SELECT true FROM ref.department WHERE code = :c").param("c", dep).query(Boolean.class).optional().orElse(false)) throw new DomainRuleViolation("HELPDESK_SCOPE_UNKNOWN", "No department is coded " + dep + ".", new DomainRuleViolation.Remedy("Choose the department from the list.", "Directorate of ICT"));
        return new RuleIn(body.categoryCode().trim().toUpperCase(), fac, dep, body.queueCode().trim().toUpperCase(), strategy, floor, body.active() == null || body.active());
    }

    @PostMapping("/admin/routing")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> newRule(@Valid @RequestBody RuleIn in) {
        RuleIn r = checkRule(in);
        UUID id = jdbc.sql("""
                INSERT INTO helpdesk.routing_rule (category_code, faculty_code, department_code, queue_code, strategy, priority_floor, active)
                VALUES (:c, :f, :d, :q, :s, :p, :a) RETURNING id
                """).param("c", r.categoryCode()).param("f", r.facultyCode(), Types.VARCHAR).param("d", r.departmentCode(), Types.VARCHAR).param("q", r.queueCode())
                .param("s", r.strategy()).param("p", r.priorityFloor(), Types.VARCHAR).param("a", r.active()).query(UUID.class).single();
        return Map.of("id", id);
    }

    @PutMapping("/admin/routing/{id}")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> editRule(@PathVariable UUID id, @Valid @RequestBody RuleIn in) {
        RuleIn r = checkRule(in);
        int n = jdbc.sql("""
                UPDATE helpdesk.routing_rule SET category_code = :c, faculty_code = :f, department_code = :d, queue_code = :q, strategy = :s, priority_floor = :p, active = :a WHERE id = :id
                """).param("id", id).param("c", r.categoryCode()).param("f", r.facultyCode(), Types.VARCHAR).param("d", r.departmentCode(), Types.VARCHAR).param("q", r.queueCode())
                .param("s", r.strategy()).param("p", r.priorityFloor(), Types.VARCHAR).param("a", r.active()).update();
        if (n == 0) throw new NotFound("routing rule", id);
        return Map.of("id", id, "updated", n);
    }

    /** every posting, live and ended, with the person, the queue, the scope, the availability and the load */
    @GetMapping("/admin/agents")
    @PreAuthorize(DIRECTOR)
    @Transactional(readOnly = true)
    Map<String, Object> adminAgents() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("postings", jdbc.sql("""
                SELECT a.id, a.person_id, helpdesk.person_name(a.person_id) AS name, p.staff_number, p.email, p.ended_on IS NOT NULL AS left_the_university,
                       helpdesk.is_agent(a.person_id) AS holds_office,
                       a.queue_code, q.name AS queue, a.scope_kind, a.scope_ref,
                       CASE a.scope_kind WHEN 'FACULTY' THEN (SELECT name FROM ref.faculty WHERE code = a.scope_ref) WHEN 'DEPARTMENT' THEN (SELECT name FROM ref.department WHERE code = a.scope_ref)
                            WHEN 'COLLEGE' THEN (SELECT name FROM ref.college WHERE code = a.scope_ref) WHEN 'OFFICE' THEN (SELECT label FROM ref.office WHERE code = a.scope_ref) ELSE 'The University' END AS scope_name,
                       a.is_primary, a.active, a.availability, a.effective_from, a.effective_to, helpdesk.person_name(a.assigned_by) AS assigned_by, a.reason, a.created_at, a.updated_at,
                       array_to_string(a.capabilities, ',') AS capabilities,
                       (SELECT count(*) FROM helpdesk.ticket t WHERE t.assigned_to = a.person_id AND t.status NOT IN ('RESOLVED','CLOSED')) AS open
                  FROM helpdesk.agent_assignment a JOIN iam.person p ON p.id = a.person_id JOIN helpdesk.queue q ON q.code = a.queue_code
                 ORDER BY a.active DESC, p.surname, p.given_names, q.ordinal
                """).query().listOfRows());
        out.put("candidates", jdbc.sql("""
                SELECT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number, p.email,
                       string_agg(DISTINCT o.label, ', ' ORDER BY o.label) AS offices,
                       (SELECT count(*) FROM helpdesk.agent_assignment aa WHERE aa.person_id = p.id AND aa.active) AS postings
                  FROM iam.person p JOIN iam.office_assignment a ON a.person_id = p.id JOIN ref.office o ON o.code = a.office_code
                 WHERE a.office_code IN ('ictagent','helpdeskhead','ict') AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND p.ended_on IS NULL
                 GROUP BY p.id, p.surname, p.given_names, p.staff_number, p.email ORDER BY p.surname, p.given_names
                """).query().listOfRows());
        out.put("queues", jdbc.sql("SELECT code, name, active FROM helpdesk.queue ORDER BY active DESC, ordinal, name").query().listOfRows());
        out.put("workload", jdbc.sql("SELECT * FROM helpdesk.agent_workload(NULL)").query().listOfRows());
        return out;
    }

    public record PostingIn(@NotNull UUID personId, @NotBlank @Size(max = 40) String queueCode, String scopeKind, @Size(max = 40) String scopeRef, Boolean isPrimary,
                            String availability, LocalDate effectiveFrom, LocalDate effectiveTo, @Size(max = 500) String reason, List<String> capabilities) {
    }

    /** V334: the student-record capabilities a posting may carry; anything else is refused here and by the database */
    private static final Set<String> CAPABILITIES = Set.of("VIEW_STUDENT", "EDIT_CONTACT", "EDIT_PERSONAL", "EDIT_FAMILY", "EDIT_PHOTO", "REQUEST_CHANGE",
            "VIEW_PAYMENTS", "VIEW_DOCUMENTS", "MANAGE_REGISTRATION", "EXPORT_STUDENTS");

    private static String capabilities(List<String> in) {
        if (in == null) return null;
        List<String> out = new java.util.ArrayList<>();
        for (String c : in) {
            String k = c == null ? "" : c.trim().toUpperCase();
            if (!CAPABILITIES.contains(k)) {
                throw new DomainRuleViolation("HELPDESK_CAPABILITY", "A posting carries only the student-record capabilities the desk defines; " + k + " is not one.",
                        new DomainRuleViolation.Remedy("Tick the capabilities from the list.", "Head of ICT Support Desk"));
            }
            if (!out.contains(k)) out.add(k);
        }
        return String.join(",", out);
    }

    /** a person who holds the ICT Support Agent office (or the Head's, or the Director's) placed on a queue within a scope; never anyone else */
    @PostMapping("/admin/agents")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> post(Authentication auth, @Valid @RequestBody PostingIn body) {
        boolean agent = jdbc.sql("SELECT helpdesk.is_agent(:p) AND EXISTS (SELECT 1 FROM iam.person WHERE id = :p AND ended_on IS NULL)").param("p", body.personId()).query(Boolean.class).single();
        if (!agent) {
            throw new DomainRuleViolation("HELPDESK_NOT_AN_AGENT", "Only a person who holds the ICT Support Agent office is posted to a queue; support access comes from that office, never from a posting.",
                    new DomainRuleViolation.Remedy("Grant the person the ICT Support Agent office under Users & Roles first.", "Directorate of ICT"));
        }
        String queue = body.queueCode().trim().toUpperCase();
        if (!jdbc.sql("SELECT true FROM helpdesk.queue WHERE code = :c AND active").param("c", queue).query(Boolean.class).optional().orElse(false)) {
            throw new DomainRuleViolation("HELPDESK_QUEUE_UNKNOWN", "No active queue is coded " + queue + ".", new DomainRuleViolation.Remedy("Choose the queue from the list.", "Directorate of ICT"));
        }
        String kind = body.scopeKind() == null || body.scopeKind().isBlank() ? "GLOBAL" : body.scopeKind().trim().toUpperCase();
        if (!SCOPES.contains(kind)) throw new DomainRuleViolation("HELPDESK_SCOPE", "A scope is the University, a faculty, a college, a department or an office.", new DomainRuleViolation.Remedy("Choose one of those.", "Directorate of ICT"));
        String ref = "GLOBAL".equals(kind) ? null : body.scopeRef() == null ? "" : body.scopeRef().trim();
        if (ref != null) {
            if ("OFFICE".equals(kind)) ref = ref.toLowerCase(); else ref = ref.toUpperCase();
            String table = switch (kind) { case "FACULTY" -> "ref.faculty"; case "DEPARTMENT" -> "ref.department"; case "COLLEGE" -> "ref.college"; default -> "ref.office"; };
            if (ref.isBlank() || !jdbc.sql("SELECT true FROM " + table + " WHERE code = :c").param("c", ref).query(Boolean.class).optional().orElse(false)) {
                throw new DomainRuleViolation("HELPDESK_SCOPE_UNKNOWN", "The " + kind.toLowerCase() + " " + ref + " is not on the register.", new DomainRuleViolation.Remedy("Choose it from the list.", "Directorate of ICT"));
            }
        }
        String availability = body.availability() == null || body.availability().isBlank() ? "AVAILABLE" : body.availability().trim().toUpperCase();
        if (!AVAILABILITY.contains(availability)) throw new DomainRuleViolation("HELPDESK_AVAILABILITY", "Availability is available, busy, away, offline or on leave.", new DomainRuleViolation.Remedy("Choose one of those.", "Directorate of ICT"));
        if (jdbc.sql("SELECT true FROM helpdesk.agent_assignment WHERE person_id = :p AND queue_code = :q AND scope_kind = :k AND coalesce(scope_ref, '') = coalesce(:r, '') AND active")
                .param("p", body.personId()).param("q", queue).param("k", kind).param("r", ref, Types.VARCHAR).query(Boolean.class).optional().orElse(false)) {
            throw new DomainRuleViolation("HELPDESK_POSTED_ALREADY", "The person is posted on that queue in that scope already.", new DomainRuleViolation.Remedy("Edit the posting instead.", "Directorate of ICT"));
        }
        String caps = capabilities(body.capabilities());
        UUID id = jdbc.sql("""
                INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, is_primary, availability, effective_from, effective_to, assigned_by, reason, capabilities)
                VALUES (:p, :q, :k, :r, :prim, :av, coalesce(:from, current_date), :to, :by, :why, string_to_array(coalesce(:caps, ''), ',')) RETURNING id
                """).param("p", body.personId()).param("q", queue).param("k", kind).param("r", ref, Types.VARCHAR).param("prim", Boolean.TRUE.equals(body.isPrimary()))
                .param("av", availability).param("from", body.effectiveFrom(), Types.DATE).param("to", body.effectiveTo(), Types.DATE).param("by", me(auth)).param("caps", caps, Types.VARCHAR).param("why", body.reason(), Types.VARCHAR)
                .query(UUID.class).single();
        return Map.of("id", id);
    }

    public record PostingEdit(String availability, Boolean active, Boolean isPrimary, LocalDate effectiveTo, @Size(max = 500) String reason, List<String> capabilities) {
    }

    /** availability, dates, primacy, or the end of a posting; an agent made unavailable holds nothing — their open tickets return to the queue */
    @PutMapping("/admin/agents/{id}")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> editPosting(Authentication auth, @PathVariable UUID id, @Valid @RequestBody PostingEdit body) {
        String availability = body.availability() == null || body.availability().isBlank() ? null : body.availability().trim().toUpperCase();
        if (availability != null && !AVAILABILITY.contains(availability)) throw new DomainRuleViolation("HELPDESK_AVAILABILITY", "Availability is available, busy, away, offline or on leave.", new DomainRuleViolation.Remedy("Choose one of those.", "Directorate of ICT"));
        String caps = capabilities(body.capabilities());
        int n = jdbc.sql("""
                UPDATE helpdesk.agent_assignment SET availability = coalesce(:av, availability), active = coalesce(:a, active), is_primary = coalesce(:prim, is_primary),
                       effective_to = CASE WHEN :a = false THEN least(coalesce(effective_to, current_date), current_date) ELSE coalesce(:to, effective_to) END,
                       reason = CASE WHEN :why::text IS NULL THEN reason ELSE :why END,
                       capabilities = CASE WHEN :caps::text IS NULL THEN capabilities ELSE string_to_array(:caps, ',') END, updated_at = now()
                 WHERE id = :id
                """).param("id", id).param("av", availability, Types.VARCHAR).param("a", body.active(), Types.BOOLEAN).param("prim", body.isPrimary(), Types.BOOLEAN)
                .param("to", body.effectiveTo(), Types.DATE).param("why", body.reason(), Types.VARCHAR).param("caps", caps, Types.VARCHAR).update();
        if (n == 0) throw new NotFound("posting", id);
        List<UUID> returned = jdbc.sql("SELECT * FROM helpdesk.sweep_inactive_agents()").query(UUID.class).list();
        if (!returned.isEmpty()) notifier.returned(returned);
        return Map.of("id", id, "updated", n, "returned", returned.size());
    }

    public record Why(@NotBlank @Size(max = 500) String reason) {
    }

    /** the Head takes an agent off the desk: every posting ended, every open ticket back on its queue, the Head told */
    @PostMapping("/admin/agents/{person}/deactivate")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> deactivate(Authentication auth, @PathVariable UUID person, @Valid @RequestBody Why body) {
        List<UUID> held = jdbc.sql("SELECT id FROM helpdesk.ticket WHERE assigned_to = :p AND status NOT IN ('RESOLVED','CLOSED')").param("p", person).query(UUID.class).list();
        Integer n = jdbc.sql("SELECT helpdesk.deactivate_agent(:p, :by, :r)").param("p", person).param("by", me(auth)).param("r", body.reason().trim()).query(Integer.class).single();
        if (!held.isEmpty()) notifier.returned(held);
        return Map.of("personId", person, "returned", n);
    }

    public record Reassign(@NotNull UUID toPersonId, @NotBlank @Size(max = 500) String reason) {
    }

    /** every open ticket with one agent moved to another, on a reason */
    @PostMapping("/admin/agents/{person}/reassign")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> reassign(Authentication auth, @PathVariable UUID person, @Valid @RequestBody Reassign body) {
        Integer n = jdbc.sql("SELECT helpdesk.reassign_open(:from, :to, :by, :r)").param("from", person).param("to", body.toPersonId()).param("by", me(auth)).param("r", body.reason().trim()).query(Integer.class).single();
        if (n > 0) notifier.bulkAssigned(body.toPersonId(), n, body.reason().trim());
        return Map.of("from", person, "to", body.toPersonId(), "moved", n);
    }

    public record SlaIn(@NotBlank String priority, @Min(1) @Max(720) int firstResponseHours, @Min(1) @Max(2160) int resolutionHours) {
    }

    public record SettingsIn(@Min(1) @Max(90) Integer autoCloseDays, Boolean notifyAgentsOnNew, List<@Valid SlaIn> sla) {
    }

    @PutMapping("/admin/settings")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> saveSettings(@Valid @RequestBody SettingsIn body) {
        jdbc.sql("UPDATE helpdesk.setting SET auto_close_days = :d, notify_agents_on_new = :n WHERE row_no")
                .param("d", body.autoCloseDays(), Types.INTEGER).param("n", body.notifyAgentsOnNew() == null || body.notifyAgentsOnNew()).update();
        if (body.sla() != null) {
            for (SlaIn s : body.sla()) {
                String p = s.priority().trim().toUpperCase();
                if (!PRIORITIES.contains(p)) continue;
                if (s.resolutionHours() < s.firstResponseHours()) {
                    throw new DomainRuleViolation("HELPDESK_SLA", "The resolution time is at least the first-response time.", new DomainRuleViolation.Remedy("Correct the hours for " + p.toLowerCase() + ".", "Directorate of ICT"));
                }
                jdbc.sql("UPDATE helpdesk.sla SET first_response_hours = :f, resolution_hours = :r WHERE priority = :p").param("f", s.firstResponseHours()).param("r", s.resolutionHours()).param("p", p).update();
            }
        }
        return settings();
    }

    /* ── the public page ── */

    public record Track(@NotBlank @Size(max = 20) String number, @NotBlank @Size(max = 200) String email) {
    }

    /** the public page is answered at most this many times a quarter-hour for one address or one email, so the number space cannot be walked */
    private static final int TRACK_LIMIT = 12;
    private final ConcurrentHashMap<String, long[]> trackAttempts = new ConcurrentHashMap<>();

    private void throttle(String key) {
        long now = System.currentTimeMillis();
        long[] slot = trackAttempts.compute(key, (k, v) -> v == null || now - v[0] > 15 * 60_000L ? new long[] {now, 1} : new long[] {v[0], v[1] + 1});
        if (trackAttempts.size() > 50_000) trackAttempts.clear();
        if (slot[1] > TRACK_LIMIT) {
            throw new DomainRuleViolation("HELPDESK_TRACK_SLOW_DOWN", "Too many lookups in a short time.",
                    new DomainRuleViolation.Remedy("Wait a quarter of an hour and try again, or sign in to the portal to see your tickets.", "Directorate of ICT"));
        }
    }

    /** a ticket number and the email it was raised with; nothing internal, no attachments, no names at all */
    @PostMapping("/track")
    @Transactional(readOnly = true)
    Map<String, Object> track(@Valid @RequestBody Track body, jakarta.servlet.http.HttpServletRequest request) {
        String number = body.number().trim().toUpperCase();
        String ip = request.getHeader("X-Forwarded-For");
        ip = ip == null || ip.isBlank() ? request.getRemoteAddr() : ip.split(",")[0].trim();
        throttle("ip:" + ip);
        throttle("email:" + body.email().trim().toLowerCase());
        Map<String, Object> t = jdbc.sql("""
                SELECT t.id, t.number, t.subject, c.name AS category, t.status, t.priority, t.created_at, t.updated_at, t.resolved_at, t.closed_at,
                       t.resolution_summary, t.reopen_count
                  FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
                 WHERE t.number = :n AND lower(t.requester_email) = lower(:e)
                """).param("n", number).param("e", body.email().trim()).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("ticket", number));
        UUID id = (UUID) t.get("id");
        Map<String, Object> out = new LinkedHashMap<>(t);
        out.remove("id");
        out.put("timeline", jdbc.sql("""
                SELECT e.at, e.action, e.from_value, e.to_value,
                       CASE WHEN e.actor_kind = 'REQUESTER' THEN 'You' WHEN e.actor_kind = 'SYSTEM' THEN 'The portal' ELSE 'ICT Support' END AS actor,
                       CASE WHEN e.action IN ('SUBMITTED','OPENED','STATUS_CHANGED','RESOLUTION','REOPENED','CLOSED') THEN e.detail ELSE NULL END AS detail
                  FROM helpdesk.ticket_event e WHERE e.ticket_id = :t AND NOT e.internal AND e.action NOT IN ('ATTACHMENT','ASSIGNED','REASSIGNED',""" + DESK_ACTIONS + """
                )
                 ORDER BY e.at
                """).param("t", id).query().listOfRows());
        return out;
    }

    /* ── helpers ── */

    /** the keys a category asks for, so a ticket carries nothing the form did not show */
    private Set<String> declaredKeys(String category) {
        String fields = jdbc.sql("SELECT fields::text FROM helpdesk.category WHERE code = upper(btrim(:c))").param("c", category).query(String.class).optional().orElse("[]");
        Set<String> keys = new java.util.HashSet<>();
        try {
            for (var node : JSON.readTree(fields)) if (node.get("key") != null) keys.add(node.get("key").asText());
        } catch (RuntimeException unreadable) {
            // an unreadable definition asks for nothing beyond the subject and description
        }
        return keys;
    }

    private static UUID uuid(String s, String what) {
        try {
            return UUID.fromString(s.trim());
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("HELPDESK_BAD_ID", "That is not a valid " + what + " id.", new DomainRuleViolation.Remedy("Choose the " + what + " from the list.", "Directorate of ICT"));
        }
    }

    private void requireMine(UUID ticket, Who w) {
        Boolean ok = jdbc.sql("SELECT true FROM helpdesk.ticket WHERE id = :id AND requester_kind = :k AND requester_id = :r")
                .param("id", ticket).param("k", w.kind()).param("r", w.id()).query(Boolean.class).optional().orElse(false);
        if (!ok) throw new NotFound("ticket", ticket);
    }

    private void requireTicket(UUID ticket) {
        Boolean ok = jdbc.sql("SELECT true FROM helpdesk.ticket WHERE id = :id").param("id", ticket).query(Boolean.class).optional().orElse(false);
        if (!ok) throw new NotFound("ticket", ticket);
    }

    /** the Head of ICT Support Desk, the Director of ICT and the administrators see and act everywhere */
    private static boolean head(Authentication auth) {
        for (GrantedAuthority a : auth.getAuthorities()) if (HEADS.contains(a.getAuthority())) return true;
        return false;
    }

    /** scope, enforced where it counts (V328): an agent reaches a ticket only when helpdesk.can_view says their postings cover it, or it is with them */
    private void requireVisible(Authentication auth, UUID ticket) {
        requireTicket(ticket);
        if (head(auth)) return;
        Boolean ok = jdbc.sql("SELECT helpdesk.can_view(:me, :t)").param("me", me(auth)).param("t", ticket).query(Boolean.class).single();
        if (!Boolean.TRUE.equals(ok)) {
            throw new AccessDeniedException("That ticket is outside your support scope: it is on a queue you are not posted to, or in a faculty or department your posting does not cover.");
        }
    }

    /** the offices the token carries, as office codes */
    private static List<String> offices(Authentication auth) {
        List<String> out = new ArrayList<>();
        for (GrantedAuthority a : auth.getAuthorities()) if (a.getAuthority().startsWith("OFFICE_")) out.add(a.getAuthority().substring(7));
        return out;
    }

    /** an office reaches a ticket that waits on it, or one it answered before; the Head and the Director reach any */
    private void requireOffice(Authentication auth, UUID ticket) {
        requireTicket(ticket);
        if (head(auth)) return;
        Boolean ok = jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM helpdesk.ticket t WHERE t.id = :t AND t.escalated_office = ANY(string_to_array(:o, ',')))
                    OR EXISTS (SELECT 1 FROM helpdesk.ticket_event e WHERE e.ticket_id = :t AND e.action = 'OFFICE_ANSWERED' AND e.actor_id = :me)
                """).param("t", ticket).param("o", String.join(",", offices(auth))).param("me", me(auth)).query(Boolean.class).single();
        if (!Boolean.TRUE.equals(ok)) throw new AccessDeniedException("The ticket does not wait on an office you hold.");
    }

    /** the ticket, its category's fields, what was said, the evidence and the history; the desk sees the internal parts */
    private Map<String, Object> detail(UUID id, boolean desk) {
        Map<String, Object> t = jdbc.sql(ROW.replace("SELECT t.id,", """
                SELECT t.description, t.details::text AS details, c.fields::text AS fields, c.attachment_hint,
                       t.requester_id, t.requester_phone, t.assigned_by, helpdesk.person_name(t.assigned_by) AS assigned_by_name, t.assigned_at,
                       t.escalated_to, helpdesk.person_name(t.escalated_to) AS escalated_to_name, helpdesk.person_name(t.escalated_by) AS escalated_by_name, t.escalated_at, t.escalation_reason,
                       t.opened_at, helpdesk.person_name(t.opened_by) AS opened_by_name, t.first_response_at, t.in_progress_at,
                       helpdesk.person_name(t.resolved_by) AS resolved_by_name, t.resolution_summary, t.resolution_details,
                       t.closed_by_kind, CASE WHEN t.closed_by_kind = 'AGENT' THEN helpdesk.person_name(t.closed_by) WHEN t.closed_by_kind = 'REQUESTER' THEN t.requester_name WHEN t.closed_by_kind = 'SYSTEM' THEN 'The portal' END AS closed_by_name, t.closure_reason,
                       helpdesk.response_due_at(t.created_at, t.priority) AS response_due_at, t.id,""") + " WHERE t.id = :id").param("id", id).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(t);
        if (!desk) {
            for (String k : List.of("requester_id", "assigned_by", "assigned_by_name", "escalated_to", "escalated_to_name", "escalated_by_name", "escalated_at", "escalation_reason", "escalated")) out.remove(k);
        } else {
            // V328: what the ticket may be escalated to — the queue's office for a decision, the Director of ICT for a technical fault
            out.put("escalation_offices", jdbc.sql("""
                    SELECT o.code, o.label, o.code = 'ict' AS technical FROM ref.office o
                     WHERE o.code = 'ict' OR o.code = (SELECT q.office_code FROM helpdesk.ticket t JOIN helpdesk.queue q ON q.code = t.queue_code WHERE t.id = :t)
                     ORDER BY technical, o.label
                    """).param("t", id).query().listOfRows());
        }
        out.put("comments", jdbc.sql("""
                SELECT id, author_kind, author_name, internal, body, created_at FROM helpdesk.ticket_comment WHERE ticket_id = :t AND (:desk OR NOT internal) ORDER BY created_at
                """).param("t", id).param("desk", desk).query().listOfRows());
        out.put("attachments", jdbc.sql("""
                SELECT id, comment_id, uploaded_kind, uploader_name, filename, content_type, bytes, internal, uploaded_at
                  FROM helpdesk.ticket_attachment WHERE ticket_id = :t AND (:desk OR NOT internal) ORDER BY uploaded_at
                """).param("t", id).param("desk", desk).query().listOfRows());
        out.put("timeline", jdbc.sql("""
                SELECT id, at, actor_kind, actor_name, action, from_value, to_value,
                       CASE WHEN :desk OR action NOT IN ('ASSIGNED','REASSIGNED') THEN detail END AS detail, internal
                  FROM helpdesk.ticket_event
                 WHERE ticket_id = :t AND (:desk OR (NOT internal AND action NOT IN (""" + DESK_ACTIONS + """
                )))
                 ORDER BY at
                """).param("t", id).param("desk", desk).query().listOfRows());
        return out;
    }

    private static String excerpt(String body) {
        String s = body.trim();
        return s.length() <= 600 ? s : s.substring(0, 600) + "…";
    }

    /** the bytes decoded, sized, and sniffed — the declared type must match what the file begins with */
    private Map<String, Object> store(UUID ticket, String kind, UUID by, String name, Upload body, boolean internal) {
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(body.contentBase64());
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("HELPDESK_FILE_BAD", "The file could not be read.", new DomainRuleViolation.Remedy("Attach it again.", "Directorate of ICT"));
        }
        if (bytes.length == 0 || bytes.length > MAX_BYTES) {
            throw new DomainRuleViolation("HELPDESK_FILE_SIZE", "An attachment is between 1 byte and 5 MB.", new DomainRuleViolation.Remedy("Attach a smaller file.", "Directorate of ICT"));
        }
        String type = body.contentType().trim().toLowerCase();
        if ("image/jpg".equals(type)) type = "image/jpeg";
        if (!TYPES.contains(type) || !sniffed(bytes).equals(type)) {
            throw new DomainRuleViolation("HELPDESK_FILE_TYPE", "An attachment is a PDF, a JPEG or a PNG, and its contents must be what its name says.",
                    new DomainRuleViolation.Remedy("Save it as one of those and attach it again.", "Directorate of ICT"));
        }
        String filename = body.filename().trim().replaceAll("[\\\\/\\r\\n\\t]", "_");
        UUID oid = files.store("helpdesk.ticket_attachment", ticket, filename, type, bytes);
        UUID id = jdbc.sql("SELECT helpdesk.attach(:t, NULL, :k, :by, :n, :f, :ty, :b, :c, :i, :o)")
                .param("t", ticket).param("k", kind).param("by", by).param("n", name).param("f", filename).param("ty", type).param("b", (long) bytes.length).param("c", bytes).param("o", oid, java.sql.Types.OTHER).param("i", internal)
                .query(UUID.class).single();
        return Map.of("id", id, "filename", filename, "bytes", bytes.length, "contentType", type);
    }

    private static String sniffed(byte[] b) {
        if (b.length >= 5 && b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F' && b[4] == '-') return "application/pdf";
        if (b.length >= 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G' && b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A) return "image/png";
        if (b.length >= 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF) return "image/jpeg";
        return "unknown";
    }

    private ResponseEntity<byte[]> content(UUID ticket, UUID att, boolean desk) {
        Map<String, Object> r = jdbc.sql("""
                SELECT a.filename, a.content_type, b.content, b.object_id FROM helpdesk.ticket_attachment a JOIN helpdesk.ticket_attachment_blob b ON b.attachment_id = a.id
                 WHERE a.id = :a AND a.ticket_id = :t AND (:desk OR NOT a.internal)
                """).param("a", att).param("t", ticket).param("desk", desk).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("attachment", att));
        r.put("content", files.resolve((byte[]) r.get("content"), (UUID) r.get("object_id")));
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType((String) r.get("content_type")))
                .cacheControl(CacheControl.noStore())
                .header("Content-Disposition", ContentDisposition.inline().filename(String.valueOf(r.get("filename")), java.nio.charset.StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Type-Options", "nosniff")
                .header("Content-Security-Policy", "sandbox")
                .body((byte[]) r.get("content"));
    }
}
