package ng.edu.moaum.portal.manual;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
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
 * V387: the Quick Operational Manual. A signed-in person reads the published procedures bound to the keys they act under —
 * the acting office the token carries, the sidebar the portal names beside it (a postgraduate's, a JUPEB applicant's) and
 * everyone — and, where a procedure is bound to a capability, only when one of their support postings carries it. The
 * filter is the database's ({@code manual.procedures_for}); a page never decides what a person may read. Manual Management
 * (Super Administrator, System Administrator, Director of ICT) drafts, edits, publishes, unpublishes, archives, restores and
 * orders the procedures; every edit keeps the previous version; every act is on the audit spine.
 */
@RestController
@RequestMapping("/api/v1/manual")
class ManualController {

    private static final String ADMINS = "hasAnyAuthority('OFFICE_super','OFFICE_admin','OFFICE_ict')";
    /** the sidebars a student or an applicant may read the manual under, beside the office itself */
    private static final Set<String> STUDENT_MENUS = Set.of("student", "pgstudent", "jupebstudent");
    private static final Set<String> APPLICANT_MENUS = Set.of("applicant", "pgapplicant", "jupebapplicant", "jupebcandidate", "cceapplicant");
    private static final Set<String> ACTIONS = Set.of("PUBLISH", "UNPUBLISH", "ARCHIVE", "RESTORE");
    private static final Set<String> VIEW_KINDS = Set.of("OPEN", "SEARCH", "PROCEDURE", "PRINT", "PDF");

    public record ProcedureIn(@NotBlank @Size(max = 80) String slug, @NotBlank @Size(max = 120) String title, @NotBlank @Size(max = 300) String purpose,
                              @NotBlank String category, @NotEmpty List<@Size(max = 40) String> offices, List<@Size(max = 40) String> capabilities,
                              @Size(max = 80) String menuId, @Size(max = 80) String route, @NotEmpty List<@Size(max = 400) String> steps,
                              @NotBlank @Size(max = 300) String expected, Integer sortOrder, @Size(max = 500) String note) {
    }

    public record ViewIn(@NotBlank String kind, UUID procedureId, @Size(max = 120) String q) {
    }

    public record OrderIn(@NotEmpty List<UUID> ids) {
    }

    public record NoteIn(@Size(max = 500) String note) {
    }

    private record Keys(String office, List<String> keys, List<String> caps) {
    }

    private record Cached(List<Map<String, Object>> rows, long at) {
    }

    private final JdbcClient jdbc;
    /* the manual of a set of keys, kept a minute: a dashboard opens it often and it changes rarely */
    private final ConcurrentHashMap<String, Cached> cache = new ConcurrentHashMap<>();

    ManualController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    // ── who is reading ───────────────────────────────────────────────────────────

    private static AuditContext actor() {
        return AuditContextHolder.required();
    }

    /** the keys a person reads under: the acting office, a sidebar of the office's own family when the portal names one, and their postings' capabilities */
    private Keys keys(Authentication auth, String menu) {
        String office = AuditContextHolder.current().map(AuditContext::actorOffice).orElse(null);
        if (office == null || office.isBlank()) {
            throw new AccessDeniedException("The manual is read as an office.");
        }
        List<String> keys = new ArrayList<>();
        keys.add(office);
        String m = menu == null ? "" : menu.trim();
        if (!m.isEmpty() && !m.equals(office)
                && (("student".equals(office) && STUDENT_MENUS.contains(m)) || ("applicant".equals(office) && APPLICANT_MENUS.contains(m)))) {
            keys.add(m);
        }
        List<String> caps = List.of();
        if ("ictagent".equals(office) || "helpdeskhead".equals(office)) {
            caps = texts(jdbc.sql("SELECT helpdesk.agent_capabilities(:p)").param("p", UUID.fromString(auth.getName()), Types.OTHER).query().singleValue());
        }
        return new Keys(office, keys, caps);
    }

    private Map<String, Object> edition() {
        return jdbc.sql("""
                SELECT e.major || '.' || e.minor AS version, e.updated_at, e.note,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = e.updated_by) AS updated_by, e.updated_office
                  FROM manual.edition e
                """).query().singleRow();
    }

    // ── reading ──────────────────────────────────────────────────────────────────

    /** the person's manual: the edition, the keys it was read under, and the procedures (searched when q is given) */
    @GetMapping
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> manual(Authentication auth, @RequestParam(required = false) String menu, @RequestParam(required = false) String q) {
        Keys k = keys(auth, menu);
        Map<String, Object> edition = edition();
        boolean searching = q != null && !q.isBlank();
        List<Map<String, Object>> rows;
        if (searching) {
            rows = rows(jdbc.sql("SELECT * FROM manual.search(:k, :c, :q)").param("k", k.keys().toArray(String[]::new))
                    .param("c", k.caps().toArray(String[]::new)).param("q", q.trim()).query().listOfRows());
        } else {
            String key = String.join(",", k.keys()) + "|" + String.join(",", k.caps()) + "|" + edition.get("version") + "|" + edition.get("updated_at");
            Cached c = cache.get(key);
            if (c == null || System.currentTimeMillis() - c.at() > 60_000) {
                c = new Cached(rows(jdbc.sql("SELECT * FROM manual.procedures_for(:k, :c)").param("k", k.keys().toArray(String[]::new))
                        .param("c", k.caps().toArray(String[]::new)).query().listOfRows()), System.currentTimeMillis());
                cache.put(key, c);
                if (cache.size() > 500) cache.clear();
            }
            rows = c.rows();
        }
        jdbc.sql("SELECT manual.record_view(:p, :o, :kind, NULL, :q)").param("p", UUID.fromString(auth.getName()), Types.OTHER).param("o", k.office())
                .param("kind", searching ? "SEARCH" : "OPEN").param("q", searching ? q.trim() : null, Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("edition", edition);
        out.put("office", k.office());
        out.put("keys", k.keys());
        out.put("capabilities", k.caps());
        out.put("q", searching ? q.trim() : null);
        out.put("procedures", rows);
        return out;
    }

    /** the procedures a page offers as its own help: those bound to its route, or living on its menu item */
    @GetMapping("/context")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    List<Map<String, Object>> context(Authentication auth, @RequestParam String route, @RequestParam(required = false) String menu) {
        Keys k = keys(auth, menu);
        return rows(jdbc.sql("SELECT * FROM manual.context_for(:k, :c, :r)").param("k", k.keys().toArray(String[]::new))
                .param("c", k.caps().toArray(String[]::new)).param("r", route).query().listOfRows());
    }

    /** a reading recorded by the page: a procedure opened, the manual printed or downloaded */
    @PostMapping("/views")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> view(Authentication auth, @Valid @RequestBody ViewIn in) {
        if (!VIEW_KINDS.contains(in.kind())) {
            throw new DomainRuleViolation("MANUAL_VIEW_KIND", "A reading is OPEN, SEARCH, PROCEDURE, PRINT or PDF.");
        }
        String office = AuditContextHolder.current().map(AuditContext::actorOffice).orElse(null);
        jdbc.sql("SELECT manual.record_view(:p, :o, :kind, :proc, :q)").param("p", UUID.fromString(auth.getName()), Types.OTHER).param("o", office, Types.VARCHAR)
                .param("kind", in.kind()).param("proc", in.procedureId(), Types.OTHER).param("q", in.q(), Types.VARCHAR).query().listOfRows();
        return Map.of("recorded", true);
    }

    // ── Manual Management ────────────────────────────────────────────────────────

    /** every procedure in every state, the edition, and what a procedure may be bound to */
    @GetMapping("/admin")
    @PreAuthorize(ADMINS)
    @Transactional(readOnly = true)
    Map<String, Object> admin(@RequestParam(required = false) String q, @RequestParam(required = false) String state) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("edition", edition());
        out.put("procedures", rows(jdbc.sql("""
                SELECT p.*, (SELECT x.surname || ', ' || x.given_names FROM iam.person x WHERE x.id = p.updated_by) AS updated_by_name,
                       (SELECT count(*) FROM manual.procedure_version v WHERE v.procedure_id = p.id) AS versions,
                       (SELECT count(*) FROM manual.view w WHERE w.procedure_id = p.id) AS readings
                  FROM manual.procedure p
                 WHERE (:state::text IS NULL OR p.state = :state)
                   AND (:q::text IS NULL OR p.title ILIKE '%' || :q || '%' OR p.slug ILIKE '%' || :q || '%' OR p.purpose ILIKE '%' || :q || '%'
                        OR EXISTS (SELECT 1 FROM unnest(p.steps) s WHERE s ILIKE '%' || :q || '%'))
                 ORDER BY array_position(manual.categories(), p.category), p.sort_order, p.title
                """).param("state", state == null || state.isBlank() ? null : state.trim().toUpperCase(), Types.VARCHAR)
                .param("q", q == null || q.isBlank() ? null : q.trim(), Types.VARCHAR).query().listOfRows()));
        out.put("keys", texts(jdbc.sql("SELECT manual.known_keys()").query().singleValue()));
        out.put("categories", texts(jdbc.sql("SELECT manual.categories()").query().singleValue()));
        out.put("capabilities", texts(jdbc.sql("SELECT helpdesk.support_capabilities()").query().singleValue()));
        out.put("counts", jdbc.sql("""
                SELECT count(*) FILTER (WHERE state = 'PUBLISHED') AS published, count(*) FILTER (WHERE state = 'DRAFT') AS draft,
                       count(*) FILTER (WHERE state = 'ARCHIVED') AS archived,
                       (SELECT count(*) FROM manual.view WHERE at > now() - interval '30 days') AS readings_30d
                  FROM manual.procedure
                """).query().singleRow());
        return out;
    }

    /** the manual as an office reads it, for the administrator's preview */
    @GetMapping("/admin/preview")
    @PreAuthorize(ADMINS)
    @Transactional(readOnly = true)
    Map<String, Object> preview(@RequestParam String office, @RequestParam(required = false) String menu, @RequestParam(required = false) String capabilities) {
        List<String> keys = new ArrayList<>();
        keys.add(office.trim());
        if (menu != null && !menu.isBlank() && !menu.trim().equals(office.trim())) keys.add(menu.trim());
        List<String> caps = capabilities == null || capabilities.isBlank() ? List.of() : List.of(capabilities.split("\\s*,\\s*"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", office.trim());
        out.put("keys", keys);
        out.put("capabilities", caps);
        out.put("edition", edition());
        out.put("procedures", rows(jdbc.sql("SELECT * FROM manual.procedures_for(:k, :c)").param("k", keys.toArray(String[]::new))
                .param("c", caps.toArray(String[]::new)).query().listOfRows()));
        return out;
    }

    @PostMapping("/admin/procedures")
    @PreAuthorize(ADMINS)
    @Transactional
    Map<String, Object> create(@Valid @RequestBody ProcedureIn in) {
        return save(null, in);
    }

    @PutMapping("/admin/procedures/{id}")
    @PreAuthorize(ADMINS)
    @Transactional
    Map<String, Object> edit(@PathVariable UUID id, @Valid @RequestBody ProcedureIn in) {
        return save(id, in);
    }

    private Map<String, Object> save(UUID id, ProcedureIn in) {
        AuditContext a = actor();
        List<String> steps = in.steps().stream().map(s -> s == null ? "" : s.trim()).filter(s -> !s.isEmpty()).toList();
        if (steps.isEmpty()) {
            throw new DomainRuleViolation("MANUAL_STEP_EMPTY", "A procedure has at least one step.");
        }
        Map<String, Object> r = jdbc.sql("""
                SELECT * FROM manual.save_procedure(:id, :slug, :title, :purpose, :cat, :offices, :caps, :menu, :route, :steps, :expected, :ord, :by, :office, :note)
                """).param("id", id, Types.OTHER).param("slug", in.slug().trim().toLowerCase()).param("title", in.title()).param("purpose", in.purpose())
                .param("cat", in.category().trim().toUpperCase())
                .param("offices", in.offices().stream().map(String::trim).filter(s -> !s.isEmpty()).toArray(String[]::new))
                .param("caps", (in.capabilities() == null ? List.<String>of() : in.capabilities()).stream().map(String::trim).filter(s -> !s.isEmpty()).toArray(String[]::new))
                .param("menu", in.menuId(), Types.VARCHAR).param("route", in.route(), Types.VARCHAR).param("steps", steps.toArray(String[]::new))
                .param("expected", in.expected()).param("ord", in.sortOrder(), Types.INTEGER).param("by", a.actorId(), Types.OTHER).param("office", a.actorOffice())
                .param("note", in.note(), Types.VARCHAR).query().singleRow();
        cache.clear();
        return row(r);
    }

    @PostMapping("/admin/procedures/{id}/{action}")
    @PreAuthorize(ADMINS)
    @Transactional
    Map<String, Object> act(@PathVariable UUID id, @PathVariable String action, @RequestBody(required = false) NoteIn in) {
        String act = action.trim().toUpperCase();
        if (!ACTIONS.contains(act)) {
            throw new DomainRuleViolation("MANUAL_ACTION", "A procedure is published, unpublished, archived or restored.");
        }
        AuditContext a = actor();
        Map<String, Object> r = jdbc.sql("SELECT * FROM manual.set_state(:id, :act, :by, :office, :note)").param("id", id, Types.OTHER).param("act", act)
                .param("by", a.actorId(), Types.OTHER).param("office", a.actorOffice()).param("note", in == null ? null : in.note(), Types.VARCHAR).query().singleRow();
        cache.clear();
        return row(r);
    }

    @GetMapping("/admin/procedures/{id}/versions")
    @PreAuthorize(ADMINS)
    @Transactional(readOnly = true)
    Map<String, Object> versions(@PathVariable UUID id) {
        Map<String, Object> current = jdbc.sql("SELECT * FROM manual.procedure WHERE id = :id").param("id", id, Types.OTHER).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("procedure", id.toString()));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("current", row(current));
        out.put("versions", jdbc.sql("""
                SELECT v.version, v.snapshot, v.saved_at, v.saved_office, v.note,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = v.saved_by) AS saved_by
                  FROM manual.procedure_version v WHERE v.procedure_id = :id ORDER BY v.version DESC
                """).param("id", id, Types.OTHER).query().listOfRows().stream().map(m -> {
            Map<String, Object> x = new LinkedHashMap<>(m);
            x.put("snapshot", String.valueOf(m.get("snapshot")));
            return x;
        }).toList());
        return out;
    }

    @PutMapping("/admin/order")
    @PreAuthorize(ADMINS)
    @Transactional
    Map<String, Object> order(@Valid @RequestBody OrderIn in) {
        AuditContext a = actor();
        Integer n = jdbc.sql("SELECT manual.reorder(:ids, :by, :office)").param("ids", in.ids().toArray(UUID[]::new)).param("by", a.actorId(), Types.OTHER)
                .param("office", a.actorOffice()).query(Integer.class).single();
        cache.clear();
        return Map.of("reordered", n);
    }

    /** a major step of the edition: the administrator releases what the publications since add up to */
    @PostMapping("/admin/edition")
    @PreAuthorize(ADMINS)
    @Transactional
    Map<String, Object> release(@RequestBody(required = false) NoteIn in) {
        AuditContext a = actor();
        String v = jdbc.sql("SELECT manual.bump_edition(:by, :office, :note, true)").param("by", a.actorId(), Types.OTHER).param("office", a.actorOffice())
                .param("note", in == null || in.note() == null ? "released" : in.note(), Types.VARCHAR).query(String.class).single();
        cache.clear();
        return Map.of("version", v);
    }

    // ── rows ─────────────────────────────────────────────────────────────────────

    private static List<Map<String, Object>> rows(List<Map<String, Object>> in) {
        return in.stream().map(ManualController::row).toList();
    }

    /** the text arrays of a row as lists, so the page reads JSON and not a driver's array */
    private static Map<String, Object> row(Map<String, Object> m) {
        Map<String, Object> x = new LinkedHashMap<>(m);
        for (String k : List.of("offices", "capabilities", "steps")) {
            if (x.containsKey(k)) x.put(k, texts(x.get(k)));
        }
        return x;
    }

    private static List<String> texts(Object v) {
        try {
            if (v instanceof java.sql.Array a) {
                Object[] arr = (Object[]) a.getArray();
                List<String> out = new ArrayList<>(arr.length);
                for (Object o : arr) out.add(String.valueOf(o));
                return out;
            }
        } catch (java.sql.SQLException e) {
            throw new IllegalStateException(e);
        }
        if (v instanceof String[] s) return List.of(s);
        if (v instanceof List<?> l) return l.stream().map(String::valueOf).toList();
        return List.of();
    }
}
