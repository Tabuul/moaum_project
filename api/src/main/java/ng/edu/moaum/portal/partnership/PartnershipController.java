package ng.edu.moaum.portal.partnership;

import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.XlsxStream;

/**
 * Collaboration & Partnerships (V658): the University's side of the one central record — the Linkages & Partnerships office screens,
 * routes, assigns, reviews, asks, checks and closes; the Vice-Chancellor approves; the Legal Officer reviews agreements; the offices
 * asked review what they are asked to (a Dean only for the faculty, a Head only for the department, named on the request); Internal
 * Audit reads. Every list, figure and record is held by the database to what the acting office sees (partnership.visible), and every
 * act is checked there against the office's grants and the status (partnership.act and its siblings); this controller only shapes it.
 */
@RestController
@RequestMapping("/api/v1/partnerships")
class PartnershipController {

    static final String OFFICES = "hasAnyAuthority('OFFICE_linkages','OFFICE_legal','OFFICE_vc','OFFICE_dvc','OFFICE_dean','OFFICE_hod','OFFICE_registrar',"
            + "'OFFICE_bursar','OFFICE_pgschool','OFFICE_ict','OFFICE_dsa','OFFICE_academic','OFFICE_dregistrar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";

    /** the actions a status may move by, before the office's grants are read */
    static final Map<String, List<String>> NEXT = Map.ofEntries(
            Map.entry("RECEIVED", List.of("START_SCREENING", "ASSIGN", "ACCEPT", "ROUTE", "REQUEST_INFORMATION", "DECLINE", "CLOSE", "CANCEL")),
            Map.entry("INITIAL_SCREENING", List.of("ASSIGN", "ACCEPT", "ROUTE", "REQUEST_INFORMATION", "DECLINE", "CLOSE", "CANCEL")),
            Map.entry("ROUTED", List.of("START_SCREENING", "ASSIGN", "ACCEPT", "ROUTE", "REQUEST_INFORMATION", "DECLINE", "CLOSE", "CANCEL")),
            Map.entry("ASSIGNED", List.of("START_SCREENING", "ASSIGN", "ACCEPT", "ROUTE", "REQUEST_INFORMATION", "DECLINE", "CLOSE", "CANCEL")),
            Map.entry("AWAITING_INFORMATION", List.of("ASSIGN", "WITHDRAW_REQUEST", "DECLINE", "CLOSE", "CANCEL")),
            Map.entry("UNDER_REVIEW", List.of("ASSIGN", "ROUTE", "REQUEST_INFORMATION", "START_DUE_DILIGENCE", "MEETING", "DEVELOP", "SUBMIT_FOR_APPROVAL", "DECLINE", "CLOSE", "CANCEL")),
            Map.entry("DUE_DILIGENCE", List.of("ASSIGN", "REQUEST_INFORMATION", "MEETING", "DEVELOP", "SUBMIT_FOR_APPROVAL", "DECLINE", "CLOSE", "CANCEL")),
            Map.entry("MEETING_PROPOSED", List.of("ASSIGN", "REQUEST_INFORMATION", "START_DUE_DILIGENCE", "DEVELOP", "SUBMIT_FOR_APPROVAL", "DECLINE", "CLOSE", "CANCEL")),
            Map.entry("UNDER_DEVELOPMENT", List.of("ASSIGN", "REQUEST_INFORMATION", "START_DUE_DILIGENCE", "MEETING", "SUBMIT_FOR_APPROVAL", "DECLINE", "CLOSE", "CANCEL")),
            Map.entry("PENDING_APPROVAL", List.of("APPROVE", "DECLINE", "CLOSE")),
            Map.entry("APPROVED_FOR_DEVELOPMENT", List.of("ASSIGN", "IMPLEMENT", "ACTIVATE", "CLOSE")),
            Map.entry("AGREEMENT_REVIEW", List.of("ASSIGN", "CLOSE")),
            Map.entry("AGREEMENT_EXECUTED", List.of("ASSIGN", "IMPLEMENT", "ACTIVATE", "CLOSE")),
            Map.entry("IMPLEMENTATION", List.of("ASSIGN", "ACTIVATE", "CLOSE")),
            Map.entry("ACTIVE", List.of("ASSIGN", "CLOSE")));
    static final Map<String, String> NEEDS = Map.ofEntries(
            Map.entry("START_SCREENING", "SCREEN_PARTNERSHIP"), Map.entry("ACCEPT", "SCREEN_PARTNERSHIP"), Map.entry("MEETING", "SCREEN_PARTNERSHIP"),
            Map.entry("DEVELOP", "SCREEN_PARTNERSHIP"), Map.entry("SUBMIT_FOR_APPROVAL", "SCREEN_PARTNERSHIP"), Map.entry("IMPLEMENT", "SCREEN_PARTNERSHIP"),
            Map.entry("ACTIVATE", "SCREEN_PARTNERSHIP"), Map.entry("ROUTE", "ROUTE_PARTNERSHIP"), Map.entry("ASSIGN", "ASSIGN_PARTNERSHIP"),
            Map.entry("REQUEST_INFORMATION", "REQUEST_INFORMATION"), Map.entry("WITHDRAW_REQUEST", "REQUEST_INFORMATION"),
            Map.entry("START_DUE_DILIGENCE", "DUE_DILIGENCE"), Map.entry("APPROVE", "APPROVE_PARTNERSHIP"), Map.entry("DECLINE", "DECLINE_PARTNERSHIP"),
            Map.entry("CLOSE", "CLOSE_PARTNERSHIP"), Map.entry("CANCEL", "CLOSE_PARTNERSHIP"));
    static final Set<String> STATUSES = Set.of("RECEIVED", "INITIAL_SCREENING", "AWAITING_INFORMATION", "ROUTED", "ASSIGNED", "UNDER_REVIEW", "DUE_DILIGENCE",
            "MEETING_PROPOSED", "UNDER_DEVELOPMENT", "PENDING_APPROVAL", "APPROVED_FOR_DEVELOPMENT", "AGREEMENT_REVIEW", "AGREEMENT_EXECUTED", "IMPLEMENTATION",
            "ACTIVE", "DECLINED", "CLOSED", "CANCELLED");

    private final JdbcClient jdbc;
    private final PartnershipFiles files;
    private final tools.jackson.databind.ObjectMapper mapper;
    private final FileObjects objects;

    PartnershipController(JdbcClient jdbc, PartnershipFiles files, tools.jackson.databind.ObjectMapper mapper, FileObjects objects) {
        this.jdbc = jdbc;
        this.files = files;
        this.mapper = mapper;
        this.objects = objects;
    }

    private String json(Object o) {
        return mapper.writeValueAsString(o == null ? Map.of() : o);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private List<String> permissions() {
        return jdbc.sql("SELECT unnest(partnership.permissions(partnership.actor_office()))").query(String.class).list();
    }

    private void need(String permission) {
        jdbc.sql("SELECT partnership.require(:p)").param("p", permission).query().listOfRows();
    }

    private void see(UUID id) {
        jdbc.sql("SELECT partnership.require_see(:id)").param("id", id).query().listOfRows();
    }

    /* ── the desk ── */

    @GetMapping("/desk")
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    Map<String, Object> desk() {
        need("VIEW_PARTNERSHIP");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", jdbc.sql("SELECT partnership.actor_office()").query(String.class).single());
        out.put("permissions", permissions());
        out.put("figures", parse(jdbc.sql("SELECT partnership.figures(partnership.actor(), partnership.actor_office())::text").query(String.class).single()));
        out.put("desks", jdbc.sql("SELECT d.code, d.label, d.active, d.lead_person, helpdesk.person_name(d.lead_person) AS lead_name FROM partnership.desk d ORDER BY d.sort, d.label")
                .query().listOfRows());
        out.put("groups", jdbc.sql("SELECT code, label FROM partnership.category_group WHERE active ORDER BY sort").query().listOfRows());
        out.put("categories", jdbc.sql("SELECT code, grp, label FROM partnership.category WHERE active ORDER BY sort, label").query().listOfRows());
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        out.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("reviewerOffices", jdbc.sql("""
                SELECT o.code, o.label FROM ref.office o WHERE EXISTS (SELECT 1 FROM partnership.grant g WHERE g.office_code = o.code AND g.permission = 'REVIEW_PARTNERSHIP')
                   AND o.code NOT IN ('super') ORDER BY o.label
                """).query().listOfRows());
        out.put("owners", jdbc.sql("""
                SELECT DISTINCT x.person_id AS id, helpdesk.person_name(x.person_id) AS name
                  FROM (SELECT a.person_id FROM iam.office_assignment a WHERE a.office_code = 'linkages' AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                        UNION SELECT o.person_id FROM partnership.desk_officer o WHERE o.active) x
                 ORDER BY 2
                """).query().listOfRows());
        out.put("ddItems", jdbc.sql("SELECT code, label FROM partnership.dd_item WHERE active ORDER BY sort").query().listOfRows());
        out.put("outcomeKinds", jdbc.sql("SELECT code, label FROM partnership.outcome_kind WHERE active ORDER BY sort").query().listOfRows());
        out.put("settings", jdbc.sql("SELECT * FROM partnership.setting WHERE id = 1").query().singleRow());
        return out;
    }

    private Object parse(String text) {
        return text == null ? null : mapper.readValue(text, Object.class);
    }

    /* ── the list, filtered on the server, a page at a time ── */

    private record Filter(String where, Map<String, Object> params) {
    }

    private Filter filter(String view, String q, String status, String group, String category, String faculty, String dept, String country,
                          String funding, String scope, String compliance, String owner, String desk, LocalDate from, LocalDate to) {
        List<String> w = new ArrayList<>();
        Map<String, Object> ps = new LinkedHashMap<>();
        w.add("p.id IN (SELECT partnership.visible(partnership.actor(), partnership.actor_office()))");
        String v = view == null ? "ALL" : view.toUpperCase();
        switch (v) {
            case "MINE" -> w.add("p.owner_person = partnership.actor() AND NOT partnership.terminal(p.status)");
            case "REVIEWS" -> w.add("""
                    EXISTS (SELECT 1 FROM partnership.reviewer r WHERE r.proposal_id = p.id AND r.withdrawn_at IS NULL AND r.completed_at IS NULL
                              AND (r.person_id = partnership.actor() OR (r.person_id IS NULL AND r.office_code = partnership.actor_office()
                                   AND (r.scope_code IS NULL OR r.scope_code = ANY (partnership.office_scopes(partnership.actor(), partnership.actor_office()))))))""");
            case "PENDING" -> w.add("p.status IN ('RECEIVED', 'INITIAL_SCREENING', 'ROUTED', 'ASSIGNED', 'UNDER_REVIEW', 'MEETING_PROPOSED', 'UNDER_DEVELOPMENT', 'PENDING_APPROVAL')");
            case "AWAITING" -> w.add("p.status = 'AWAITING_INFORMATION'");
            case "DUE_DILIGENCE" -> w.add("p.status = 'DUE_DILIGENCE'");
            case "APPROVAL" -> w.add("p.status = 'PENDING_APPROVAL'");
            case "AGREEMENTS" -> w.add("p.status IN ('AGREEMENT_REVIEW', 'AGREEMENT_EXECUTED') OR EXISTS (SELECT 1 FROM partnership.agreement g WHERE g.proposal_id = p.id AND g.status IN ('DRAFT', 'LEGAL_REVIEW', 'APPROVAL', 'SIGNING'))");
            case "ACTIVE" -> w.add("p.status IN ('APPROVED_FOR_DEVELOPMENT', 'AGREEMENT_EXECUTED', 'IMPLEMENTATION', 'ACTIVE')");
            case "EXPIRING" -> w.add("EXISTS (SELECT 1 FROM partnership.agreement g WHERE g.proposal_id = p.id AND g.status = 'EXECUTED' AND g.expires_on <= partnership.today() + (SELECT expiry_alert_days FROM partnership.setting WHERE id = 1))");
            case "OVERDUE" -> w.add("NOT partnership.terminal(p.status) AND p.status <> 'ACTIVE' AND p.due_on < partnership.today()");
            case "UNASSIGNED" -> w.add("p.owner_person IS NULL AND NOT partnership.terminal(p.status)");
            case "COMPLIANCE" -> w.add("p.compliance_review AND NOT partnership.terminal(p.status)");
            default -> { }
        }
        if (blank(q) != null) {
            w.add("(p.reference ILIKE '%' || :q || '%' OR p.org_name ILIKE '%' || :q || '%' OR p.title ILIKE '%' || :q || '%' OR p.email ILIKE '%' || :q || '%')");
            ps.put("q", q.trim());
        }
        if (blank(status) != null && STATUSES.contains(status.toUpperCase())) { w.add("p.status = :status"); ps.put("status", status.toUpperCase()); }
        if (blank(group) != null) { w.add("(SELECT c.grp FROM partnership.category c WHERE c.code = p.category) = :grp"); ps.put("grp", group.trim()); }
        if (blank(category) != null) { w.add("p.category = :cat"); ps.put("cat", category.trim()); }
        if (blank(faculty) != null) { w.add("p.faculty_code = :fac"); ps.put("fac", faculty.trim()); }
        if (blank(dept) != null) { w.add("p.dept_code = :dept"); ps.put("dept", dept.trim()); }
        if (blank(country) != null) { w.add("(p.country ILIKE :country OR :country = ANY (p.countries))"); ps.put("country", country.trim()); }
        if (blank(funding) != null) { w.add("p.funding_status = :fund"); ps.put("fund", funding.trim()); }
        if ("INTERNATIONAL".equalsIgnoreCase(scope)) w.add("coalesce(p.international, false)");
        if ("LOCAL".equalsIgnoreCase(scope)) w.add("NOT coalesce(p.international, false)");
        if ("REQUIRED".equalsIgnoreCase(compliance)) w.add("p.compliance_review");
        else if (blank(compliance) != null) { w.add(":flag = ANY (p.flags)"); ps.put("flag", compliance.trim().toUpperCase()); }
        if ("NONE".equalsIgnoreCase(owner)) w.add("p.owner_person IS NULL");
        else if ("ME".equalsIgnoreCase(owner)) w.add("p.owner_person = partnership.actor()");
        else if (blank(owner) != null) { w.add("p.owner_person = CAST(:owner AS uuid)"); ps.put("owner", owner.trim()); }
        if (blank(desk) != null) { w.add("p.desk_code = :desk"); ps.put("desk", desk.trim()); }
        if (from != null) { w.add("p.received_at >= CAST(:from AS date)"); ps.put("from", from.toString()); }
        if (to != null) { w.add("p.received_at < CAST(:to AS date) + 1"); ps.put("to", to.toString()); }
        return new Filter(String.join(" AND ", w), ps);
    }

    private static final String ROW = """
            SELECT p.id, p.reference, p.org_name, p.org_type, p.country, p.international, p.category, c.label AS category_label, g.label AS group_label,
                   p.title, p.faculty_code, f.name AS faculty, p.dept_code, d.name AS department, p.status, p.desk_code, k.label AS desk,
                   p.owner_person, helpdesk.person_name(p.owner_person) AS owner_name, p.received_at, p.updated_at, p.next_action, p.due_on,
                   (NOT partnership.terminal(p.status) AND p.status <> 'ACTIVE' AND p.due_on < partnership.today()) AS overdue,
                   p.funding_status, p.budget, p.currency, p.compliance_review, p.risk_level, p.flags, p.email
              FROM partnership.proposal p
              LEFT JOIN partnership.category c ON c.code = p.category
              LEFT JOIN partnership.category_group g ON g.code = c.grp
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN partnership.desk k ON k.code = p.desk_code
            """;

    @GetMapping
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String view, @RequestParam(required = false) String q, @RequestParam(required = false) String status,
                             @RequestParam(required = false) String group, @RequestParam(required = false) String category,
                             @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept,
                             @RequestParam(required = false) String country, @RequestParam(required = false) String funding,
                             @RequestParam(required = false) String scope, @RequestParam(required = false) String compliance,
                             @RequestParam(required = false) String owner, @RequestParam(required = false) String desk,
                             @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from, @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "25") int size) {
        need("VIEW_PARTNERSHIP");
        Filter f = filter(view, q, status, group, category, faculty, dept, country, funding, scope, compliance, owner, desk, from, to);
        int sz = Math.max(5, Math.min(size, 100));
        int pg = Math.max(0, page);
        var countSpec = jdbc.sql("SELECT count(*) FROM partnership.proposal p WHERE " + f.where());
        var rowsSpec = jdbc.sql(ROW + " WHERE " + f.where() + " ORDER BY p.received_at DESC NULLS LAST LIMIT :lim OFFSET :off");
        for (var e : f.params().entrySet()) {
            countSpec = countSpec.param(e.getKey(), e.getValue());
            rowsSpec = rowsSpec.param(e.getKey(), e.getValue());
        }
        long total = countSpec.query(Long.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rowsSpec.param("lim", sz).param("off", pg * sz).query().listOfRows());
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    /* ── one proposal ── */

    @GetMapping("/{id}")
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    Map<String, Object> detail(@PathVariable UUID id) {
        need("VIEW_PARTNERSHIP");
        see(id);
        boolean conf = Boolean.TRUE.equals(jdbc.sql("SELECT partnership.may_confidential(:id)").param("id", id).query(Boolean.class).single());
        List<String> perms = permissions();
        Map<String, Object> p = new LinkedHashMap<>(jdbc.sql("""
                SELECT p.*, p.high_risk::text AS high_risk_text, c.label AS category_label, g.label AS group_label, c2.label AS secondary_label,
                       f.name AS faculty, d.name AS department, k.label AS desk, helpdesk.person_name(p.owner_person) AS owner_name,
                       helpdesk.person_name(p.decided_by) AS decided_by_name, partnership.public_status(p.status) AS public_status,
                       (NOT partnership.terminal(p.status) AND p.status <> 'ACTIVE' AND p.due_on < partnership.today()) AS overdue,
                       (SELECT rr.note FROM partnership.routing_rule rr WHERE rr.id = p.routing_rule) AS routing_note
                  FROM partnership.proposal p
                  LEFT JOIN partnership.category c ON c.code = p.category LEFT JOIN partnership.category_group g ON g.code = c.grp
                  LEFT JOIN partnership.category c2 ON c2.code = p.secondary_category
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN partnership.desk k ON k.code = p.desk_code
                 WHERE p.id = :id
                """).param("id", id).query().singleRow());
        p.remove("token_hash");
        p.remove("high_risk");
        if (!conf) {
            p.put("coi_detail", p.get("coi_detail") == null ? null : "(confidential — read by the Linkages office and the Vice-Chancellor)");
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("proposal", p);
        out.put("mayConfidential", conf);
        out.put("permissions", perms);
        String status = String.valueOf(p.get("status"));
        List<String> actions = new ArrayList<>();
        for (String a : NEXT.getOrDefault(status, List.of())) {
            if (perms.contains(NEEDS.get(a)) && (!"DECLINE".equals(a) || !"PENDING_APPROVAL".equals(status) || perms.contains("APPROVE_PARTNERSHIP"))) actions.add(a);
        }
        out.put("actions", actions);
        out.put("attachments", perms.contains("VIEW_ATTACHMENTS") ? files.list(id, false) : List.of());
        out.put("events", jdbc.sql("""
                SELECT e.at, e.action, e.from_status, e.to_status, e.detail, e.applicant_visible, e.actor_office,
                       CASE WHEN e.actor IS NULL OR e.actor = '00000000-0000-0000-0000-000000000000' THEN NULL ELSE helpdesk.person_name(e.actor) END AS actor_name
                  FROM partnership.event e WHERE e.proposal_id = :id ORDER BY e.at
                """).param("id", id).query().listOfRows());
        out.put("messages", jdbc.sql("""
                SELECT m.id, m.kind, m.body, m.confidential, m.at, m.author_office, helpdesk.person_name(m.author_person) AS author_name
                  FROM partnership.message m WHERE m.proposal_id = :id AND (NOT m.confidential OR :conf) ORDER BY m.at
                """).param("id", id).param("conf", conf).query().listOfRows());
        out.put("requests", jdbc.sql("""
                SELECT r.id, r.question, r.documents, r.deadline, CASE WHEN :internal THEN r.reason END AS reason, r.requested_at, r.answer, r.answered_at,
                       r.withdrawn_at, helpdesk.person_name(r.requested_by) AS requested_by_name
                  FROM partnership.info_request r WHERE r.proposal_id = :id ORDER BY r.requested_at
                """).param("id", id).param("internal", perms.contains("REQUEST_INFORMATION")).query().listOfRows());
        out.put("reviewers", jdbc.sql("""
                SELECT r.id, r.office_code, o.label AS office, r.scope_code,
                       coalesce((SELECT f.name FROM ref.faculty f WHERE f.code = r.scope_code), (SELECT d.name FROM ref.department d WHERE d.code = r.scope_code)) AS scope_name,
                       r.person_id, helpdesk.person_name(r.person_id) AS person_name, r.role_label, r.due_on, r.see_confidential, r.assigned_at,
                       r.recommendation, r.comment, r.completed_at, helpdesk.person_name(r.completed_by) AS completed_by_name, r.withdrawn_at,
                       (r.withdrawn_at IS NULL AND (r.person_id = partnership.actor() OR (r.person_id IS NULL AND r.office_code = partnership.actor_office()
                        AND (r.scope_code IS NULL OR r.scope_code = ANY (partnership.office_scopes(partnership.actor(), partnership.actor_office())))))) AS mine
                  FROM partnership.reviewer r JOIN ref.office o ON o.code = r.office_code WHERE r.proposal_id = :id ORDER BY r.assigned_at
                """).param("id", id).query().listOfRows());
        out.put("dueDiligence", jdbc.sql("""
                SELECT i.code, i.label, x.status, x.note, x.checked_at, helpdesk.person_name(x.checked_by) AS checked_by_name
                  FROM partnership.due_diligence x JOIN partnership.dd_item i ON i.code = x.item_code WHERE x.proposal_id = :id ORDER BY i.sort
                """).param("id", id).query().listOfRows());
        out.put("agreements", jdbc.sql("""
                SELECT a.id, a.reference, a.agreement_type, a.type_other, a.title, a.parties, a.status, a.effective_on, a.expires_on, a.renewal_on, a.signed_on,
                       a.legal_note, helpdesk.person_name(a.legal_by) AS legal_by_name, a.legal_at, helpdesk.person_name(a.approved_by) AS approved_by_name,
                       a.approved_office, a.approved_at, a.executed_at, a.ended_note, a.created_at,
                       (a.status = 'EXECUTED' AND a.expires_on <= partnership.today() + (SELECT expiry_alert_days FROM partnership.setting WHERE id = 1)) AS expiring
                  FROM partnership.agreement a WHERE a.proposal_id = :id ORDER BY a.created_at
                """).param("id", id).query().listOfRows());
        out.put("activities", jdbc.sql("SELECT * FROM partnership.activity WHERE proposal_id = :id ORDER BY coalesce(due_on, created_at::date), created_at")
                .param("id", id).query().listOfRows());
        out.put("outcomes", jdbc.sql("""
                SELECT o.id, o.kind, k.label AS kind_label, o.description, o.occurred_on, o.quantity, o.amount, o.currency, o.recorded_at,
                       helpdesk.person_name(o.recorded_by) AS recorded_by_name
                  FROM partnership.outcome o JOIN partnership.outcome_kind k ON k.code = o.kind WHERE o.proposal_id = :id ORDER BY o.recorded_at
                """).param("id", id).query().listOfRows());
        return out;
    }

    public record ActIn(@NotBlank @Size(max = 40) String action, Map<String, Object> data) {
    }

    @PostMapping("/{id}/act")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> act(@PathVariable UUID id, @Valid @RequestBody ActIn body) {
        String to = jdbc.sql("SELECT partnership.act(:id, :a, CAST(:d AS jsonb))").param("id", id).param("a", body.action()).param("d", json(body.data()))
                .query(String.class).single();
        return Map.of("status", to);
    }

    public record ReviewerIn(@NotBlank @Size(max = 40) String office, @Size(max = 40) String scope, UUID person, @Size(max = 120) String role, LocalDate due,
                             Boolean confidential) {
    }

    @PostMapping("/{id}/reviewers")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> addReviewer(@PathVariable UUID id, @Valid @RequestBody ReviewerIn body) {
        UUID r = jdbc.sql("SELECT partnership.add_reviewer(:id, :o, :s, :p, :r, :d, :c)").param("id", id).param("o", body.office().trim())
                .param("s", blank(body.scope()), Types.VARCHAR).param("p", body.person(), Types.OTHER).param("r", blank(body.role()), Types.VARCHAR)
                .param("d", body.due(), Types.DATE).param("c", Boolean.TRUE.equals(body.confidential())).query(UUID.class).single();
        return Map.of("reviewer", r);
    }

    @DeleteMapping("/reviewers/{reviewer}")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> withdrawReviewer(@PathVariable UUID reviewer) {
        jdbc.sql("SELECT partnership.withdraw_reviewer(:r)").param("r", reviewer).query().listOfRows();
        return Map.of("withdrawn", true);
    }

    public record ReviewIn(@NotBlank @Size(max = 40) String recommendation, @NotBlank @Size(max = 4000) String comment) {
    }

    @PostMapping("/{id}/review")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @Valid @RequestBody ReviewIn body) {
        UUID r = jdbc.sql("SELECT partnership.review(:id, :r, :c)").param("id", id).param("r", body.recommendation().trim().toUpperCase()).param("c", body.comment())
                .query(UUID.class).single();
        return Map.of("reviewer", r);
    }

    public record NoteIn(@NotBlank @Size(max = 30) String kind, @NotBlank @Size(max = 8000) String body, Boolean confidential) {
    }

    @PostMapping("/{id}/notes")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> note(@PathVariable UUID id, @Valid @RequestBody NoteIn body) {
        UUID m = jdbc.sql("SELECT partnership.note(:id, :k, :b, :c)").param("id", id).param("k", body.kind()).param("b", body.body())
                .param("c", Boolean.TRUE.equals(body.confidential())).query(UUID.class).single();
        return Map.of("message", m);
    }

    public record CheckIn(@NotBlank @Size(max = 20) String status, @Size(max = 2000) String note) {
    }

    @PutMapping("/{id}/due-diligence/{item}")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> dueDiligence(@PathVariable UUID id, @PathVariable String item, @Valid @RequestBody CheckIn body) {
        jdbc.sql("SELECT partnership.dd_set(:id, :i, :s, :n)").param("id", id).param("i", item.trim().toUpperCase()).param("s", body.status().trim().toUpperCase())
                .param("n", blank(body.note()), Types.VARCHAR).query().listOfRows();
        return Map.of("saved", true);
    }

    /* ── agreements ── */

    public record AgreementIn(@NotBlank @Size(max = 30) String type, @Size(max = 120) String typeOther, @NotBlank @Size(max = 300) String title,
                              @NotBlank @Size(max = 1000) String parties) {
    }

    @PostMapping("/{id}/agreements")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> agreement(@PathVariable UUID id, @Valid @RequestBody AgreementIn body) {
        UUID a = jdbc.sql("SELECT partnership.agreement_create(:id, :t, :o, :ti, :pa)").param("id", id).param("t", body.type().trim().toUpperCase())
                .param("o", blank(body.typeOther()), Types.VARCHAR).param("ti", body.title()).param("pa", body.parties()).query(UUID.class).single();
        return Map.of("agreement", a);
    }

    @PostMapping("/agreements/{agreement}/act")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> agreementAct(@PathVariable UUID agreement, @Valid @RequestBody ActIn body) {
        String to = jdbc.sql("SELECT partnership.agreement_act(:a, :x, CAST(:d AS jsonb))").param("a", agreement).param("x", body.action())
                .param("d", json(body.data())).query(String.class).single();
        return Map.of("status", to);
    }

    /* ── documents ── */

    public record FileIn(@NotBlank @Size(max = 40) String kind, @NotBlank @Size(max = 200) String filename, @NotBlank String dataUrl, UUID agreement) {
    }

    @PostMapping("/{id}/attachments")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> attach(@PathVariable UUID id, @Valid @RequestBody FileIn body) {
        need("UPLOAD_DOCUMENTS");
        see(id);
        if (body.agreement() != null && !Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM partnership.agreement WHERE id = :a AND proposal_id = :p)")
                .param("a", body.agreement()).param("p", id).query(Boolean.class).single())) {
            throw new NotFound("agreement", body.agreement());
        }
        String kind = body.agreement() != null ? "AGREEMENT" : body.kind();
        PartnershipFiles.Decoded f = files.decode(body.filename(), body.dataUrl());
        UUID att = files.keep(id, kind, f, false, body.agreement(), null);
        jdbc.sql("SELECT partnership.log(:p, 'DOCUMENT_ADDED', NULL, NULL, :d, false)").param("p", id).param("d", f.filename() + " (" + kind.toLowerCase().replace('_', ' ') + ")")
                .query().listOfRows();
        return Map.of("attachment", att, "attachments", files.list(id, false));
    }

    /** a document opened: only where the office reads documents and sees the proposal; every look on the timeline */
    @GetMapping("/{id}/attachments/{attachment}")
    @PreAuthorize(OFFICES)
    @Transactional
    ResponseEntity<byte[]> open(@PathVariable UUID id, @PathVariable UUID attachment) {
        need("VIEW_ATTACHMENTS");
        see(id);
        PartnershipFiles.Loaded f = files.load(id, attachment);
        jdbc.sql("SELECT partnership.log(:p, 'DOCUMENT_OPENED', NULL, NULL, :d, false)").param("p", id).param("d", f.filename()).query().listOfRows();
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(f.contentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment().filename(f.filename()).build().toString())
                .header("X-Content-Type-Options", "nosniff").header(HttpHeaders.CACHE_CONTROL, "no-store").body(f.bytes());
    }

    /* ── the partnership under way ── */

    public record ActivityIn(@NotBlank @Size(max = 20) String kind, @NotBlank @Size(max = 300) String title, @Size(max = 200) String lead, LocalDate due,
                             @Size(max = 20) String status, @Size(max = 2000) String note) {
    }

    @PostMapping("/{id}/activities")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> addActivity(@PathVariable UUID id, @Valid @RequestBody ActivityIn body) {
        return Map.of("activity", saveActivity(id, null, body));
    }

    @PutMapping("/{id}/activities/{activity}")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> editActivity(@PathVariable UUID id, @PathVariable UUID activity, @Valid @RequestBody ActivityIn body) {
        return Map.of("activity", saveActivity(id, activity, body));
    }

    private UUID saveActivity(UUID id, UUID activity, ActivityIn b) {
        return jdbc.sql("SELECT partnership.activity_save(:id, :a, :k, :t, :l, :d, :s, :n)").param("id", id).param("a", activity, Types.OTHER)
                .param("k", b.kind().trim().toUpperCase()).param("t", b.title()).param("l", blank(b.lead()), Types.VARCHAR).param("d", b.due(), Types.DATE)
                .param("s", b.status() == null ? null : b.status().trim().toUpperCase(), Types.VARCHAR).param("n", blank(b.note()), Types.VARCHAR)
                .query(UUID.class).single();
    }

    public record OutcomeIn(@NotBlank @Size(max = 40) String kind, @NotBlank @Size(max = 2000) String description, LocalDate occurredOn, Integer quantity,
                            java.math.BigDecimal amount, @Size(max = 3) String currency) {
    }

    @PostMapping("/{id}/outcomes")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> outcome(@PathVariable UUID id, @Valid @RequestBody OutcomeIn body) {
        UUID o = jdbc.sql("SELECT partnership.outcome_add(:id, :k, :d, :on, :q, :a, :c)").param("id", id).param("k", body.kind().trim().toUpperCase())
                .param("d", body.description()).param("on", body.occurredOn(), Types.DATE).param("q", body.quantity(), Types.INTEGER)
                .param("a", body.amount(), Types.NUMERIC).param("c", blank(body.currency()), Types.VARCHAR).query(UUID.class).single();
        return Map.of("outcome", o);
    }

    /* ── a proposal recorded by the office, and a correction ── */

    public record RecordIn(Map<String, Object> answers, @NotBlank @Size(max = 1000) String reason) {
    }

    @PostMapping("/record")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> record(@Valid @RequestBody RecordIn body) {
        UUID id = jdbc.sql("SELECT partnership.create_internal(CAST(:a AS jsonb), :r)").param("a", json(body.answers())).param("r", body.reason())
                .query(UUID.class).single();
        return Map.of("id", id, "reference", jdbc.sql("SELECT reference FROM partnership.proposal WHERE id = :id").param("id", id).query(String.class).single());
    }

    @PutMapping("/{id}")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> edit(@PathVariable UUID id, @Valid @RequestBody RecordIn body) {
        jdbc.sql("SELECT partnership.edit(:id, CAST(:a AS jsonb), :r)").param("id", id).param("a", json(body.answers())).param("r", body.reason()).query().listOfRows();
        return Map.of("saved", true);
    }

    /* ── the settings and the configurable lists ── */

    @GetMapping("/settings")
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    Map<String, Object> settings() {
        need("MANAGE_PARTNERSHIP_SETTINGS");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("settings", jdbc.sql("SELECT s.*, helpdesk.person_name(s.set_by) AS set_by_name FROM partnership.setting s WHERE s.id = 1").query().singleRow());
        out.put("groups", jdbc.sql("SELECT * FROM partnership.category_group ORDER BY sort").query().listOfRows());
        out.put("categories", jdbc.sql("SELECT * FROM partnership.category ORDER BY grp, sort, label").query().listOfRows());
        out.put("desks", jdbc.sql("SELECT d.*, helpdesk.person_name(d.lead_person) AS lead_name FROM partnership.desk d ORDER BY d.sort").query().listOfRows());
        out.put("officers", jdbc.sql("SELECT o.desk_code, o.person_id, helpdesk.person_name(o.person_id) AS name, o.active FROM partnership.desk_officer o ORDER BY o.desk_code, 3")
                .query().listOfRows());
        out.put("rules", jdbc.sql("SELECT * FROM partnership.routing_rule ORDER BY priority").query().listOfRows());
        out.put("linkagesStaff", jdbc.sql("""
                SELECT DISTINCT a.person_id AS id, helpdesk.person_name(a.person_id) AS name FROM iam.office_assignment a
                 WHERE a.office_code = 'linkages' AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) ORDER BY 2
                """).query().listOfRows());
        return out;
    }

    public record SettingsIn(Map<String, Object> settings, @NotBlank @Size(max = 1000) String reason) {
    }

    @PutMapping("/settings")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> saveSettings(@Valid @RequestBody SettingsIn body) {
        jdbc.sql("SELECT partnership.set_settings(CAST(:s AS jsonb), :r)").param("s", json(body.settings())).param("r", body.reason()).query().listOfRows();
        return settings();
    }

    public record CategoryIn(@NotBlank @Size(max = 40) String group, @NotBlank @Size(max = 120) String label, Integer sort, Boolean active) {
    }

    @PutMapping("/categories/{code}")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> category(@PathVariable String code, @Valid @RequestBody CategoryIn body) {
        jdbc.sql("SELECT partnership.set_category(:c, :g, :l, :s, :a)").param("c", code).param("g", body.group()).param("l", body.label())
                .param("s", body.sort(), Types.INTEGER).param("a", body.active(), Types.BOOLEAN).query().listOfRows();
        return settings();
    }

    public record DeskIn(@NotBlank @Size(max = 120) String label, UUID lead, Boolean active) {
    }

    @PutMapping("/desks/{code}")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> desk(@PathVariable String code, @Valid @RequestBody DeskIn body) {
        jdbc.sql("SELECT partnership.set_desk(:c, :l, :p, :a)").param("c", code).param("l", body.label()).param("p", body.lead(), Types.OTHER)
                .param("a", body.active(), Types.BOOLEAN).query().listOfRows();
        return settings();
    }

    public record OfficerIn(Boolean active) {
    }

    @PutMapping("/desks/{code}/officers/{person}")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> officer(@PathVariable String code, @PathVariable UUID person, @RequestBody OfficerIn body) {
        jdbc.sql("SELECT partnership.set_desk_officer(:c, :p, :a)").param("c", code.toUpperCase()).param("p", person)
                .param("a", body == null || body.active() == null || body.active()).query().listOfRows();
        return settings();
    }

    public record RuleIn(UUID id, int priority, @Size(max = 40) String group, @Size(max = 60) String category, Boolean international,
                         @Size(max = 40) String orgType, @Size(max = 40) String funding, @NotBlank @Size(max = 40) String desk, Boolean active,
                         @Size(max = 300) String note) {
    }

    @PostMapping("/rules")
    @PreAuthorize(OFFICES)
    @Transactional
    Map<String, Object> rule(@Valid @RequestBody RuleIn b) {
        jdbc.sql("SELECT partnership.set_rule(:id, :p, :g, :c, :i, :o, :f, :d, :a, :n)").param("id", b.id(), Types.OTHER).param("p", b.priority())
                .param("g", blank(b.group()), Types.VARCHAR).param("c", blank(b.category()), Types.VARCHAR).param("i", b.international(), Types.BOOLEAN)
                .param("o", blank(b.orgType()), Types.VARCHAR).param("f", blank(b.funding()), Types.VARCHAR).param("d", b.desk())
                .param("a", b.active(), Types.BOOLEAN).param("n", blank(b.note()), Types.VARCHAR).query().listOfRows();
        return settings();
    }

    /* ── the report: one reading of what the office sees, for the screen, the workbook and the PDF ── */

    @GetMapping("/report")
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    Map<String, Object> report(@RequestParam(required = false) String q, @RequestParam(required = false) String status, @RequestParam(required = false) String group,
                               @RequestParam(required = false) String category, @RequestParam(required = false) String faculty,
                               @RequestParam(required = false) String dept, @RequestParam(required = false) String country,
                               @RequestParam(required = false) String funding, @RequestParam(required = false) String scope,
                               @RequestParam(required = false) String compliance, @RequestParam(required = false) String owner,
                               @RequestParam(required = false) String orgType, @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                               @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        need("VIEW_REPORTS");
        Filter f = filter("ALL", q, status, group, category, faculty, dept, country, funding, scope, compliance, owner, null, from, to);
        String where = f.where() + (blank(orgType) != null ? " AND p.org_type = :otype" : "");
        Map<String, Object> ps = new LinkedHashMap<>(f.params());
        if (blank(orgType) != null) ps.put("otype", orgType.trim());
        java.util.function.Function<String, List<Map<String, Object>>> run = sql -> {
            var spec = jdbc.sql(sql);
            for (var e : ps.entrySet()) spec = spec.param(e.getKey(), e.getValue());
            return spec.query().listOfRows();
        };
        String base = "FROM partnership.proposal p LEFT JOIN partnership.category c ON c.code = p.category LEFT JOIN partnership.category_group g ON g.code = c.grp "
                + "LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE " + where;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("totals", run.apply("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE p.status IN ('APPROVED_FOR_DEVELOPMENT', 'AGREEMENT_REVIEW', 'AGREEMENT_EXECUTED', 'IMPLEMENTATION', 'ACTIVE')) AS approved,
                       count(*) FILTER (WHERE p.status = 'DECLINED') AS declined,
                       count(*) FILTER (WHERE p.status = 'ACTIVE') AS active,
                       count(*) FILTER (WHERE p.status IN ('CLOSED', 'CANCELLED')) AS closed,
                       count(*) FILTER (WHERE p.status IN ('RECEIVED', 'INITIAL_SCREENING', 'ROUTED', 'ASSIGNED', 'AWAITING_INFORMATION')) AS pending,
                       count(*) FILTER (WHERE p.status IN ('UNDER_REVIEW', 'DUE_DILIGENCE', 'MEETING_PROPOSED', 'UNDER_DEVELOPMENT', 'PENDING_APPROVAL')) AS under_review,
                       count(*) FILTER (WHERE coalesce(p.international, false)) AS international,
                       count(*) FILTER (WHERE p.compliance_review) AS compliance_review
                """ + base).get(0));
        out.put("byStatus", run.apply("SELECT p.status AS key, count(*) AS n " + base + " GROUP BY 1 ORDER BY 2 DESC"));
        out.put("byGroup", run.apply("SELECT coalesce(g.label, 'None') AS key, count(*) AS n " + base + " GROUP BY 1 ORDER BY 2 DESC, 1"));
        out.put("byCategory", run.apply("SELECT coalesce(c.label, 'None') AS key, coalesce(g.label, '') AS grp, count(*) AS n " + base + " GROUP BY 1, 2 ORDER BY 3 DESC, 1"));
        out.put("byCountry", run.apply("SELECT coalesce(p.country, 'Not stated') AS key, count(*) AS n, count(*) FILTER (WHERE p.status = 'ACTIVE') AS active " + base + " GROUP BY 1 ORDER BY 2 DESC, 1"));
        out.put("byFaculty", run.apply("SELECT coalesce(f.name, 'No faculty named') AS key, count(*) AS n, count(*) FILTER (WHERE p.status = 'ACTIVE') AS active " + base + " GROUP BY 1 ORDER BY 2 DESC, 1"));
        out.put("byDepartment", run.apply("SELECT coalesce(d.name, 'No department named') AS key, coalesce(f.name, '') AS faculty, count(*) AS n, count(*) FILTER (WHERE p.status = 'ACTIVE') AS active " + base + " GROUP BY 1, 2 ORDER BY 3 DESC, 1"));
        out.put("byOrgType", run.apply("SELECT coalesce(p.org_type, 'OTHER') AS key, count(*) AS n " + base + " GROUP BY 1 ORDER BY 2 DESC"));
        out.put("byFunding", run.apply("SELECT coalesce(p.funding_status, 'NOT_STATED') AS key, count(*) AS n " + base + " GROUP BY 1 ORDER BY 2 DESC"));
        out.put("fundingTotals", run.apply("SELECT p.currency AS key, count(*) AS n, sum(p.budget) AS total " + base + " AND p.budget IS NOT NULL AND p.currency IS NOT NULL GROUP BY 1 ORDER BY 3 DESC"));
        out.put("byFlag", run.apply("SELECT x.flag AS key, count(*) AS n FROM partnership.proposal p CROSS JOIN LATERAL unnest(p.flags) x(flag) WHERE " + where + " GROUP BY 1 ORDER BY 2 DESC"));
        var rowsSpec = jdbc.sql(ROW + " WHERE " + where + " ORDER BY p.received_at DESC NULLS LAST LIMIT 5000");
        for (var e : ps.entrySet()) rowsSpec = rowsSpec.param(e.getKey(), e.getValue());
        out.put("rows", rowsSpec.query().listOfRows());
        out.put("agreements", run.apply("""
                SELECT a.reference, p.reference AS partnership, p.org_name, a.agreement_type, a.title, a.status, a.signed_on, a.effective_on, a.expires_on, a.renewal_on
                  FROM partnership.agreement a JOIN partnership.proposal p ON p.id = a.proposal_id""" + " WHERE " + where + " ORDER BY a.expires_on NULLS LAST"));
        out.put("outcomes", run.apply("""
                SELECT k.label AS key, count(*) AS n, sum(o.quantity) AS quantity
                  FROM partnership.outcome o JOIN partnership.outcome_kind k ON k.code = o.kind JOIN partnership.proposal p ON p.id = o.proposal_id
                """ + " WHERE " + where + " GROUP BY 1 ORDER BY 2 DESC"));
        return out;
    }

    /* ── the Excel workbook: the report's ten sheets, S/N first, references as text, money and dates typed ── */

    private static String words(Object status) {
        String t = status == null ? "" : String.valueOf(status).replace('_', ' ').toLowerCase();
        return t.isEmpty() ? "" : Character.toUpperCase(t.charAt(0)) + t.substring(1);
    }

    @SuppressWarnings("unchecked")
    @GetMapping("/report/workbook")
    @PreAuthorize(OFFICES)
    @Transactional(readOnly = true)
    void workbook(@RequestParam Map<String, String> q, jakarta.servlet.http.HttpServletResponse response) throws java.io.IOException {
        need("EXPORT_PARTNERSHIP");
        java.util.function.Function<String, LocalDate> date = k -> blank(q.get(k)) == null ? null : LocalDate.parse(q.get(k).trim());
        Map<String, Object> r = report(q.get("q"), q.get("status"), q.get("group"), q.get("category"), q.get("faculty"), q.get("dept"), q.get("country"),
                q.get("funding"), q.get("scope"), q.get("compliance"), q.get("owner"), q.get("orgType"), date.apply("from"), date.apply("to"));
        String who = jdbc.sql("SELECT helpdesk.person_name(partnership.actor())").query(String.class).optional().orElse("");
        String school = ng.edu.moaum.portal.platform.Branding.name().toUpperCase();
        String title = "Collaboration & Partnership Report";
        StringBuilder filters = new StringBuilder();
        for (String k : List.of("q", "status", "group", "category", "faculty", "dept", "country", "funding", "scope", "compliance", "owner", "orgType", "from", "to")) {
            if (blank(q.get(k)) != null) filters.append(filters.length() == 0 ? "" : " · ").append(k).append(": ").append(q.get(k).trim());
        }
        String facts = (filters.length() == 0 ? "All partnerships the office sees" : filters) + " · Generated "
                + java.time.ZonedDateTime.now(java.time.ZoneId.of("Africa/Lagos")).format(java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy HH:mm"))
                + (who.isBlank() ? "" : " by " + who);
        response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        response.setHeader("Content-Disposition", "attachment; filename=\"partnership-report-" + LocalDate.now(java.time.ZoneId.of("Africa/Lagos")) + ".xlsx\"");
        List<Map<String, Object>> rows = (List<Map<String, Object>>) r.get("rows");
        try (XlsxStream x = new XlsxStream(response.getOutputStream(), crest())) {
            Map<String, Object> t = (Map<String, Object>) r.get("totals");
            XlsxStream.Sheet sum = x.sheet("Summary", school, title.toUpperCase(), facts, List.of(XlsxStream.Col.text("Item", 34), XlsxStream.Col.num("Count")));
            for (String[] k : new String[][] {{"total", "Total proposals"}, {"approved", "Approved"}, {"declined", "Declined"}, {"active", "Active"}, {"closed", "Closed"},
                    {"pending", "Pending (received, screening, awaiting information)"}, {"under_review", "Under review"}, {"international", "International"},
                    {"compliance_review", "Compliance review required"}}) {
                sum.row(k[1], t.get(k[0]));
            }
            List<XlsxStream.Col> listCols = List.of(XlsxStream.Col.text("Reference", 18), XlsxStream.Col.text("Organisation", 34), XlsxStream.Col.text("Organisation type", 18),
                    XlsxStream.Col.text("Country", 16), XlsxStream.Col.text("Category", 26), XlsxStream.Col.text("Group", 18), XlsxStream.Col.text("Title", 44),
                    XlsxStream.Col.text("Faculty", 26), XlsxStream.Col.text("Department", 28), XlsxStream.Col.text("Status", 22), XlsxStream.Col.text("Owner", 24),
                    XlsxStream.Col.date("Received"), XlsxStream.Col.moment("Last updated"), XlsxStream.Col.text("Next action", 30), XlsxStream.Col.date("Due"),
                    XlsxStream.Col.text("Overdue", 9), XlsxStream.Col.text("Funding status", 18), XlsxStream.Col.money("Budget"), XlsxStream.Col.text("Currency", 9),
                    XlsxStream.Col.text("Compliance review", 10), XlsxStream.Col.text("Risk", 8), XlsxStream.Col.text("Flags", 40));
            XlsxStream.Sheet list = x.sheet("Partnership List", school, "Partnership list — " + title, facts, listCols);
            List<Object[]> activeRows = new ArrayList<>();
            for (Map<String, Object> p : rows) {
                Object[] v = {p.get("reference"), p.get("org_name"), words(p.get("org_type")), p.get("country"), p.get("category_label"), p.get("group_label"),
                        p.get("title"), p.get("faculty"), p.get("department"), words(p.get("status")), p.get("owner_name"), p.get("received_at"), p.get("updated_at"),
                        p.get("next_action"), p.get("due_on"), Boolean.TRUE.equals(p.get("overdue")) ? "Yes" : "No", words(p.get("funding_status")), p.get("budget"),
                        p.get("currency"), Boolean.TRUE.equals(p.get("compliance_review")) ? "Yes" : "No", words(p.get("risk_level")), flags(p.get("flags"))};
                list.row(v);
                if (List.of("APPROVED_FOR_DEVELOPMENT", "AGREEMENT_EXECUTED", "IMPLEMENTATION", "ACTIVE").contains(String.valueOf(p.get("status")))) activeRows.add(v);
            }
            XlsxStream.Sheet fac = x.sheet("Faculty Summary", school, "Faculty summary — " + title, facts,
                    List.of(XlsxStream.Col.text("Faculty", 40), XlsxStream.Col.num("Proposals"), XlsxStream.Col.num("Active")));
            for (Map<String, Object> a : (List<Map<String, Object>>) r.get("byFaculty")) fac.row(a.get("key"), a.get("n"), a.get("active"));
            XlsxStream.Sheet dep = x.sheet("Department Summary", school, "Department summary — " + title, facts,
                    List.of(XlsxStream.Col.text("Department", 40), XlsxStream.Col.text("Faculty", 34), XlsxStream.Col.num("Proposals"), XlsxStream.Col.num("Active")));
            for (Map<String, Object> a : (List<Map<String, Object>>) r.get("byDepartment")) dep.row(a.get("key"), a.get("faculty"), a.get("n"), a.get("active"));
            XlsxStream.Sheet cty = x.sheet("Country Summary", school, "Country summary — " + title, facts,
                    List.of(XlsxStream.Col.text("Country", 30), XlsxStream.Col.num("Proposals"), XlsxStream.Col.num("Active")));
            for (Map<String, Object> a : (List<Map<String, Object>>) r.get("byCountry")) cty.row(a.get("key"), a.get("n"), a.get("active"));
            XlsxStream.Sheet cat = x.sheet("Category Summary", school, "Category summary — " + title, facts,
                    List.of(XlsxStream.Col.text("Category", 36), XlsxStream.Col.text("Group", 22), XlsxStream.Col.num("Proposals")));
            for (Map<String, Object> a : (List<Map<String, Object>>) r.get("byCategory")) cat.row(a.get("key"), a.get("grp"), a.get("n"));
            XlsxStream.Sheet fund = x.sheet("Funding Summary", school, "Funding summary — " + title, facts,
                    List.of(XlsxStream.Col.text("Funding", 36), XlsxStream.Col.num("Proposals"), XlsxStream.Col.money("Estimated budget")));
            for (Map<String, Object> a : (List<Map<String, Object>>) r.get("byFunding")) fund.row(words(a.get("key")), a.get("n"), null);
            for (Map<String, Object> a : (List<Map<String, Object>>) r.get("fundingTotals")) fund.row("Budget stated in " + a.get("key"), a.get("n"), a.get("total"));
            XlsxStream.Sheet comp = x.sheet("Compliance Summary", school, "Compliance summary (flags for review) — " + title, facts,
                    List.of(XlsxStream.Col.text("Flag", 30), XlsxStream.Col.num("Proposals")));
            for (Map<String, Object> a : (List<Map<String, Object>>) r.get("byFlag")) comp.row(words(a.get("key")), a.get("n"));
            XlsxStream.Sheet active = x.sheet("Active Partnerships", school, "Active partnerships — " + title, facts, listCols);
            for (Object[] v : activeRows) active.row(v);
            XlsxStream.Sheet agr = x.sheet("Agreements", school, "Agreements — " + title, facts,
                    List.of(XlsxStream.Col.text("Agreement reference", 22), XlsxStream.Col.text("Partnership", 18), XlsxStream.Col.text("Organisation", 34),
                            XlsxStream.Col.text("Type", 20), XlsxStream.Col.text("Title", 40), XlsxStream.Col.text("Status", 14), XlsxStream.Col.date("Signed"),
                            XlsxStream.Col.date("Effective"), XlsxStream.Col.date("Expires"), XlsxStream.Col.date("Renewal")));
            for (Map<String, Object> a : (List<Map<String, Object>>) r.get("agreements")) {
                agr.row(a.get("reference"), a.get("partnership"), a.get("org_name"), words(a.get("agreement_type")), a.get("title"), words(a.get("status")),
                        a.get("signed_on"), a.get("effective_on"), a.get("expires_on"), a.get("renewal_on"));
            }
        }
    }

    private static String flags(Object v) {
        try {
            if (v instanceof java.sql.Array a) return String.join(", ", (String[]) a.getArray());
        } catch (java.sql.SQLException | ClassCastException e) {
            return "";
        }
        return v == null ? "" : String.valueOf(v);
    }

    /** the crest every sheet carries: the Institution Profile's logo where it is a PNG, else the portal's own */
    private byte[] crest() {
        try {
            UUID id = jdbc.sql("SELECT logo_object_id FROM platform.institution_profile WHERE id").query(UUID.class).optional().orElse(null);
            if (id != null) {
                FileObjects.Typed t = objects.typed(id);
                if (t != null && t.bytes() != null && "image/png".equalsIgnoreCase(t.contentType())) return t.bytes();
            }
        } catch (RuntimeException unreadable) {
            // the portal's own crest below
        }
        try (java.io.InputStream in = PartnershipController.class.getResourceAsStream("/branding/crest.png")) {
            return in == null ? null : in.readAllBytes();
        } catch (java.io.IOException e) {
            return null;
        }
    }
}
