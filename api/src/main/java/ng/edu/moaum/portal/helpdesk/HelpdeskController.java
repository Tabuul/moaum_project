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

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
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
 * The ICT support desk (V251) under /api/v1/helpdesk.
 *   /my/…       the requester — any student or member of staff signed in — raises, reads, answers, confirms, reopens, withdraws
 *   /tickets/…  the desk — ICT Support Agents, the Director of ICT, the administrators — the queue, the ticket, the acts on it
 *   /admin/…    the Director — categories, SLAs, the quiet spell
 *   /track      the public page — a ticket number and the email it was raised with
 * A requester sees only their own tickets and never an internal note; the desk sees everything.
 */
@RestController
@RequestMapping("/api/v1/helpdesk")
class HelpdeskController {

    private static final String AGENTS = "hasAnyAuthority('OFFICE_ictagent','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String DIRECTOR = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String REQUESTER = "isAuthenticated() and !hasAnyAuthority('OFFICE_applicant','OFFICE_pgapplicant')";
    private static final long MAX_BYTES = 5L * 1024 * 1024;
    private static final Set<String> TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    private static final Set<String> PRIORITIES = Set.of("LOW", "NORMAL", "HIGH", "URGENT");
    private static final Set<String> FIELD_TYPES = Set.of("text", "date", "number", "select", "session", "semester", "level");
    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    /** a ticket as the lists show it */
    private static final String ROW = """
            SELECT t.id, t.number, t.subject, t.status, t.priority, t.created_at, t.updated_at, t.resolved_at, t.closed_at, t.reopen_count,
                   c.code AS category_code, c.name AS category, t.requester_kind, t.requester_name, t.requester_number, t.requester_email,
                   t.department_code, d.name AS department, t.faculty_code, f.name AS faculty,
                   t.assigned_to, helpdesk.person_name(t.assigned_to) AS agent, t.escalated_to IS NOT NULL AS escalated,
                   helpdesk.due_at(t.created_at, t.priority) AS due_at,
                   (t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.due_at(t.created_at, t.priority) < now()) AS overdue,
                   (t.first_response_at IS NULL AND t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.response_due_at(t.created_at, t.priority) < now()) AS response_overdue,
                   (SELECT count(*) FROM helpdesk.ticket_attachment a WHERE a.ticket_id = t.id AND NOT a.internal) AS attachments
              FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
              LEFT JOIN ref.department d ON d.code = t.department_code LEFT JOIN ref.faculty f ON f.code = t.faculty_code
            """;

    private final JdbcClient jdbc;
    private final TicketNotifier notifier;

    HelpdeskController(JdbcClient jdbc, TicketNotifier notifier) {
        this.jdbc = jdbc;
        this.notifier = notifier;
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
        return jdbc.sql("SELECT id, code, name, description, suggested_priority, fields::text AS fields, attachment_hint FROM helpdesk.category WHERE active ORDER BY ordinal, name")
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

    /** the queue: searched, filtered, sorted, paged on the server */
    @GetMapping("/tickets")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> queue(Authentication auth,
                              @RequestParam(required = false) String q, @RequestParam(required = false) String status, @RequestParam(required = false) String category,
                              @RequestParam(required = false) String priority, @RequestParam(required = false) String agent,
                              @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                              @RequestParam(required = false) String faculty, @RequestParam(required = false) String department,
                              @RequestParam(defaultValue = "updated") String sort, @RequestParam(defaultValue = "desc") String dir,
                              @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "20") int size) {
        int sz = Math.max(1, Math.min(size, 100));
        int pg = Math.max(1, page);
        String order = switch (sort) {
            case "created" -> "t.created_at";
            case "priority" -> "CASE t.priority WHEN 'URGENT' THEN 4 WHEN 'HIGH' THEN 3 WHEN 'NORMAL' THEN 2 ELSE 1 END";
            case "status" -> "t.status";
            case "number" -> "t.number";
            case "due" -> "helpdesk.due_at(t.created_at, t.priority)";
            default -> "t.updated_at";
        };
        String direction = "asc".equalsIgnoreCase(dir) ? "ASC" : "DESC";
        List<String> statuses = status == null || status.isBlank() || "all".equalsIgnoreCase(status) ? List.of()
                : "open".equalsIgnoreCase(status) ? List.of("SUBMITTED", "OPENED", "IN_PROGRESS", "REOPENED")
                : List.of(status.toUpperCase().split(","));
        UUID agentId = null;
        boolean unassigned = "none".equalsIgnoreCase(agent);
        if (agent != null && !agent.isBlank() && !unassigned) agentId = "me".equalsIgnoreCase(agent) ? me(auth) : uuid(agent, "agent");
        String like = q == null || q.isBlank() ? null : "%" + q.trim() + "%";
        List<Map<String, Object>> rows = jdbc.sql(ROW.replace("SELECT t.id,", "SELECT count(*) OVER() AS total, t.id,") + """
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
                 ORDER BY %s %s, t.created_at DESC
                 LIMIT :n OFFSET :o
                """.formatted(order, direction))
                .param("like", like, Types.VARCHAR).param("nst", statuses.size()).param("st", String.join(",", statuses))
                .param("cat", category == null || category.isBlank() ? null : category.toUpperCase(), Types.VARCHAR)
                .param("pri", priority == null || priority.isBlank() ? null : priority.toUpperCase(), Types.VARCHAR)
                .param("unassigned", unassigned).param("agent", agentId, Types.OTHER)
                .param("from", from, Types.DATE).param("to", to, Types.DATE)
                .param("fac", faculty == null || faculty.isBlank() ? null : faculty, Types.VARCHAR).param("dep", department == null || department.isBlank() ? null : department, Types.VARCHAR)
                .param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        if (rows.isEmpty() && pg > 1) {
            total = jdbc.sql("""
                    SELECT count(*) FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id
                     WHERE (:like::text IS NULL OR t.number ILIKE :like OR t.subject ILIKE :like OR t.requester_name ILIKE :like OR t.requester_number ILIKE :like
                            OR t.requester_email ILIKE :like OR t.details->>'payment_reference' ILIKE :like OR t.details->>'username' ILIKE :like)
                       AND (:nst = 0 OR t.status = ANY(string_to_array(:st, ',')))
                       AND (:cat::text IS NULL OR c.code = :cat) AND (:pri::text IS NULL OR t.priority = :pri)
                       AND (NOT :unassigned OR t.assigned_to IS NULL) AND (:agent::uuid IS NULL OR t.assigned_to = :agent)
                       AND (:from::date IS NULL OR t.created_at >= :from) AND (:to::date IS NULL OR t.created_at < :to + 1)
                       AND (:fac::text IS NULL OR t.faculty_code = :fac) AND (:dep::text IS NULL OR t.department_code = :dep)
                    """).param("like", like, Types.VARCHAR).param("nst", statuses.size()).param("st", String.join(",", statuses))
                    .param("cat", category == null || category.isBlank() ? null : category.toUpperCase(), Types.VARCHAR)
                    .param("pri", priority == null || priority.isBlank() ? null : priority.toUpperCase(), Types.VARCHAR)
                    .param("unassigned", unassigned).param("agent", agentId, Types.OTHER).param("from", from, Types.DATE).param("to", to, Types.DATE)
                    .param("fac", faculty == null || faculty.isBlank() ? null : faculty, Types.VARCHAR).param("dep", department == null || department.isBlank() ? null : department, Types.VARCHAR)
                    .query(Long.class).single();
        }
        rows.forEach(r -> r.remove("total"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows); out.put("total", total); out.put("page", pg); out.put("size", sz);
        return out;
    }

    /** the desk's figures and the Director's analytics, from the same filters as the queue */
    @GetMapping("/stats")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    Map<String, Object> stats(Authentication auth, @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                              @RequestParam(required = false) String category, @RequestParam(required = false) String priority,
                              @RequestParam(required = false) String agent, @RequestParam(required = false) String faculty, @RequestParam(required = false) String department) {
        String where = """
                 WHERE (:from::date IS NULL OR t.created_at >= :from) AND (:to::date IS NULL OR t.created_at < :to + 1)
                   AND (:cat::text IS NULL OR c.code = :cat) AND (:pri::text IS NULL OR t.priority = :pri)
                   AND (:agent::uuid IS NULL OR t.assigned_to = :agent) AND (NOT :none OR t.assigned_to IS NULL)
                   AND (:fac::text IS NULL OR t.faculty_code = :fac) AND (:dep::text IS NULL OR t.department_code = :dep)
                """;
        String base = "FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id LEFT JOIN ref.faculty f ON f.code = t.faculty_code LEFT JOIN ref.department d ON d.code = t.department_code" + where;
        boolean unassignedOnly = "none".equalsIgnoreCase(agent);
        UUID agentId = agent == null || agent.isBlank() || unassignedOnly ? null : "me".equalsIgnoreCase(agent) ? me(auth) : uuid(agent, "agent");
        java.util.function.Function<String, JdbcClient.StatementSpec> with = sql -> jdbc.sql(sql)
                .param("from", from, Types.DATE).param("to", to, Types.DATE)
                .param("cat", category == null || category.isBlank() ? null : category.toUpperCase(), Types.VARCHAR)
                .param("pri", priority == null || priority.isBlank() ? null : priority.toUpperCase(), Types.VARCHAR)
                .param("agent", agentId, Types.OTHER).param("none", unassignedOnly)
                .param("fac", faculty == null || faculty.isBlank() ? null : faculty, Types.VARCHAR)
                .param("dep", department == null || department.isBlank() ? null : department, Types.VARCHAR);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("totals", with.apply("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE t.status = 'SUBMITTED') AS submitted,
                       count(*) FILTER (WHERE t.status = 'OPENED') AS opened,
                       count(*) FILTER (WHERE t.status = 'IN_PROGRESS') AS in_progress,
                       count(*) FILTER (WHERE t.status = 'REOPENED') AS reopened,
                       count(*) FILTER (WHERE t.status = 'RESOLVED') AS resolved,
                       count(*) FILTER (WHERE t.status = 'CLOSED') AS closed,
                       count(*) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED')) AS open,
                       count(*) FILTER (WHERE t.assigned_to IS NULL AND t.status NOT IN ('RESOLVED','CLOSED')) AS unassigned,
                       count(*) FILTER (WHERE t.priority IN ('HIGH','URGENT') AND t.status NOT IN ('RESOLVED','CLOSED')) AS high,
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
        out.put("sla", jdbc.sql("SELECT priority, first_response_hours, resolution_hours FROM helpdesk.sla ORDER BY CASE priority WHEN 'URGENT' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'NORMAL' THEN 3 ELSE 4 END").query().listOfRows());
        return out;
    }

    /** what happened on the desk lately, across every ticket: the last acts, newest first */
    @GetMapping("/activity")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> activity(@RequestParam(defaultValue = "25") int limit) {
        return jdbc.sql("""
                SELECT e.id, e.at, e.actor_kind, e.actor_name, e.action, e.from_value, e.to_value, e.detail, e.internal,
                       t.id AS ticket_id, t.number, t.subject, t.status, t.priority
                  FROM helpdesk.ticket_event e JOIN helpdesk.ticket t ON t.id = e.ticket_id
                 ORDER BY e.at DESC LIMIT :n
                """).param("n", Math.max(1, Math.min(limit, 100))).query().listOfRows();
    }

    /** the people the desk can give a ticket to: agents and the Director, with their open load */
    @GetMapping("/agents")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> agents() {
        return jdbc.sql("""
                SELECT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number, p.email IS NOT NULL AS reachable,
                       string_agg(DISTINCT o.label, ', ' ORDER BY o.label) AS offices,
                       bool_or(a.office_code = 'ict') AS director,
                       (SELECT count(*) FROM helpdesk.ticket t WHERE t.assigned_to = p.id AND t.status NOT IN ('RESOLVED','CLOSED')) AS open
                  FROM iam.person p JOIN iam.office_assignment a ON a.person_id = p.id JOIN ref.office o ON o.code = a.office_code
                 WHERE a.office_code IN ('ictagent','ict') AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND p.ended_on IS NULL
                 GROUP BY p.id, p.surname, p.given_names, p.staff_number, p.email ORDER BY director, p.surname, p.given_names
                """).query().listOfRows();
    }

    /** the ticket in full; the first agent to read a submitted ticket opens it (§8), and that is recorded */
    @GetMapping("/tickets/{id}")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> ticket(Authentication auth, @PathVariable UUID id) {
        requireTicket(id);
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
        requireTicket(id);
        UUID before = jdbc.sql("SELECT assigned_to FROM helpdesk.ticket WHERE id = :id").param("id", id).query(UUID.class).optional().orElse(null);
        jdbc.sql("SELECT helpdesk.assign(:t, :a, :by, :r)").param("t", id).param("a", body.agentId()).param("by", me(auth)).param("r", body.reason(), Types.VARCHAR).query().singleRow();
        notifier.assigned(id, body.agentId(), before != null);
        return Map.of("id", id, "assignedTo", body.agentId());
    }

    public record Status(@NotBlank String status, @Size(max = 2000) String reason) {
    }

    /** start work, close on a reason, reopen on a reason — the desk's transitions */
    @PostMapping("/tickets/{id}/status")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> status(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Status body) {
        requireTicket(id);
        String to = body.status().trim().toUpperCase();
        if (!Set.of("OPENED", "IN_PROGRESS", "CLOSED", "REOPENED").contains(to)) {
            throw new DomainRuleViolation("HELPDESK_STATUS", "The desk moves a ticket to opened, in progress, closed or reopened; a resolution is recorded through Resolve.",
                    new DomainRuleViolation.Remedy("Choose one of those.", "Directorate of ICT"));
        }
        jdbc.sql("SELECT helpdesk.transition(:t, :to, 'AGENT', :a, :n, :r)").param("t", id).param("to", to).param("a", me(auth)).param("n", myName(auth))
                .param("r", body.reason(), Types.VARCHAR).query().singleRow();
        switch (to) {
            case "CLOSED" -> notifier.closed(id);
            case "REOPENED" -> { notifier.reopened(id, body.reason() == null ? "" : body.reason().trim(), true); notifier.statusChanged(id); }
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
        requireTicket(id);
        String p = body.priority().trim().toUpperCase();
        if (!PRIORITIES.contains(p)) throw new DomainRuleViolation("HELPDESK_PRIORITY", "A priority is low, normal, high or urgent.", new DomainRuleViolation.Remedy("Choose one of the four.", "Directorate of ICT"));
        jdbc.sql("SELECT helpdesk.set_priority(:t, :p, :by)").param("t", id).param("p", p).param("by", me(auth)).query().singleRow();
        return Map.of("id", id, "priority", p);
    }

    public record Escalate(@NotNull UUID toPersonId, @NotBlank @Size(max = 2000) String reason) {
    }

    @PostMapping("/tickets/{id}/escalate")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> escalate(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Escalate body) {
        requireTicket(id);
        jdbc.sql("SELECT helpdesk.escalate(:t, :to, :by, :r)").param("t", id).param("to", body.toPersonId()).param("by", me(auth)).param("r", body.reason().trim()).query().singleRow();
        notifier.escalated(id, body.toPersonId(), body.reason().trim());
        return Map.of("id", id, "escalatedTo", body.toPersonId());
    }

    public record Resolve(@NotBlank @Size(max = 300) String summary, @NotBlank @Size(max = 8000) String details) {
    }

    @PostMapping("/tickets/{id}/resolve")
    @PreAuthorize(AGENTS)
    @Transactional
    Map<String, Object> resolve(Authentication auth, @PathVariable UUID id, @Valid @RequestBody Resolve body) {
        requireTicket(id);
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
        requireTicket(id);
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
        requireTicket(id);
        return store(id, "AGENT", me(auth), myName(auth), body, Boolean.TRUE.equals(body.internal()));
    }

    @GetMapping("/tickets/{id}/attachments/{att}/content")
    @PreAuthorize(AGENTS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> deskContent(@PathVariable UUID id, @PathVariable UUID att) {
        requireTicket(id);
        return content(id, att, true);
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
        out.put("sla", jdbc.sql("SELECT priority, first_response_hours, resolution_hours FROM helpdesk.sla ORDER BY CASE priority WHEN 'URGENT' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'NORMAL' THEN 3 ELSE 4 END").query().listOfRows());
        return out;
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
                  FROM helpdesk.ticket_event e WHERE e.ticket_id = :t AND NOT e.internal AND e.action NOT IN ('INTERNAL_NOTE','ATTACHMENT','ASSIGNED','REASSIGNED','ESCALATED','PRIORITY_CHANGED')
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
                 WHERE ticket_id = :t AND (:desk OR (NOT internal AND action NOT IN ('INTERNAL_NOTE','ESCALATED','PRIORITY_CHANGED')))
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
        UUID id = jdbc.sql("SELECT helpdesk.attach(:t, NULL, :k, :by, :n, :f, :ty, :b, :c, :i)")
                .param("t", ticket).param("k", kind).param("by", by).param("n", name).param("f", filename).param("ty", type).param("b", (long) bytes.length).param("c", bytes).param("i", internal)
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
                SELECT a.filename, a.content_type, b.content FROM helpdesk.ticket_attachment a JOIN helpdesk.ticket_attachment_blob b ON b.attachment_id = a.id
                 WHERE a.id = :a AND a.ticket_id = :t AND (:desk OR NOT a.internal)
                """).param("a", att).param("t", ticket).param("desk", desk).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("attachment", att));
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType((String) r.get("content_type")))
                .cacheControl(CacheControl.noStore())
                .header("Content-Disposition", ContentDisposition.inline().filename(String.valueOf(r.get("filename")), java.nio.charset.StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Type-Options", "nosniff")
                .header("Content-Security-Policy", "sandbox")
                .body((byte[]) r.get("content"));
    }
}
