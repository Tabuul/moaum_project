package ng.edu.moaum.portal.dbops;

import java.sql.Types;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FigureCache;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
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
 * V640: the Database Operations office, under /api/v1/dbops — the operator's home (the students by programme type, the
 * examination readiness of the current semester, data quality), the controlled query engine (a definition, never SQL: validated,
 * held to the office's scope, run read-only, a page at a time), saved and shared queries and reports, official report references,
 * the query log, and data quality with every figure opening its records. Nothing here writes a student's record, a payment, a
 * registration or a result.
 */
@RestController
@RequestMapping("/api/v1/dbops")
class DatabaseOperationsController {

    private static final Set<String> DQ_KINDS = Set.of("INVALID_PROGRAMME", "MISSING_FACULTY_DEPARTMENT", "MISSING_ENTRY_SESSION", "INVALID_LEVEL",
            "LEVEL_INCONSISTENT", "MISSING_MATRIC", "DUPLICATE_MATRIC", "DUPLICATE_JAMB", "UNCLASSIFIED", "CONFLICTING_STATUS",
            "GRADUATED_STILL_ACTIVE", "BEYOND_MAXIMUM_PERIOD", "PAID_NOT_REGISTERED", "REGISTERED_NOT_PAID");
    private static final String DQ_READERS = "hasAnyAuthority('OFFICE_dbops','OFFICE_ict','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic',"
            + "'OFFICE_records','OFFICE_dean','OFFICE_hod','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;
    private final Operations ops;
    private final FigureCache figures;

    DatabaseOperationsController(JdbcClient jdbc, Operations ops, FigureCache figures) {
        this.jdbc = jdbc;
        this.ops = ops;
        this.figures = figures;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private Map<String, Object> period() {
        return jdbc.sql("SELECT session, semester FROM reporting.readiness_period()").query().singleRow();
    }

    /* ── the operator's home ───────────────────────────────────────────────────────────────────────────────────────────── */

    /** the students by programme type (current, graduated, in spillover), the readiness of the current semester and the data
     *  quality — worked out once for the scope and kept a few minutes, with the time they were read and a refresh */
    @GetMapping("/home")
    @PreAuthorize(Operations.OPERATOR)
    @Transactional(readOnly = true)
    Map<String, Object> home(@RequestParam(defaultValue = "false") boolean refresh) {
        OfficeScope.Bound b = ops.bound(null, null, null);
        Map<String, Object> p = period();
        String s = (String) p.get("session");
        int sem = ((Number) p.get("semester")).intValue();
        String key = "dbops-home:" + b.fac() + ":" + b.dept() + ":" + b.prog() + ":" + s + ":" + sem;
        FigureCache.Answer<Map<String, Object>> a = figures.get(key, refresh, () -> homeFigures(b, s, sem));
        Map<String, Object> out = new LinkedHashMap<>(a.value());
        out.put("at", a.at());
        out.put("refreshing", a.refreshing());
        out.put("scope", ops.words(b));
        out.put("period", p);
        return out;
    }

    private Map<String, Object> homeFigures(OfficeScope.Bound b, String session, int semester) {
        Map<String, Object> out = new LinkedHashMap<>();
        jdbc.sql("SELECT set_config('plan_cache_mode', 'force_generic_plan', true)").query().singleRow();
        out.put("students", jdbc.sql("""
                SELECT coalesce(l.programme_type, 'UNCLASSIFIED') AS programme_type,
                       coalesce(t.label, 'Unclassified') AS label,
                       count(*) FILTER (WHERE l.status <> ALL (ARRAY['GRADUATED', 'COMPLETED', 'WITHDRAWN', 'VOLUNTARY_WITHDRAWAL', 'EXPELLED',
                                                                     'TRANSFERRED_OUT', 'DECEASED', 'PROGRESSED'])) AS current,
                       count(*) FILTER (WHERE l.status IN ('GRADUATED', 'COMPLETED')) AS graduated,
                       count(*) FILTER (WHERE coalesce(l.spillover_state, '') LIKE 'SPILLOVER%') AS spillover,
                       count(*) AS total
                  FROM people.learner l
                  LEFT JOIN finance.programme_type t ON t.code = l.programme_type
                 WHERE (CAST(:f AS text) IS NULL OR l.faculty_code = CAST(:f AS text))
                   AND (CAST(:d AS text) IS NULL OR l.dept_code = CAST(:d AS text))
                   AND (CAST(:p AS text) IS NULL OR l.programme_code = CAST(:p AS text))
                 GROUP BY 1, 2
                 ORDER BY min(coalesce(t.ord, 999)), 1
                """).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR).query().listOfRows());
        out.put("readiness", jdbc.sql("""
                SELECT total, paid_registered, paid_not_registered, not_paid, not_paid_registered, no_fee_stated, part_paid, exam_cards, exceptions
                  FROM reporting.exam_readiness_summary(CAST(:s AS text), CAST(:sem AS int), CAST(:f AS text), CAST(:d AS text), CAST(:p AS text),
                       NULL, NULL, NULL, 'CARD', 'all')
                """).param("s", session).param("sem", semester).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR)
                .param("p", b.prog(), Types.VARCHAR).query().listOfRows().stream().findFirst().orElse(null));
        out.put("quality", jdbc.sql("SELECT * FROM reporting.data_quality(CAST(:f AS text), CAST(:d AS text), CAST(:p AS text), CAST(:s AS text), CAST(:sem AS int))")
                .param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR)
                .param("s", session).param("sem", semester).query().listOfRows());
        out.put("reports", jdbc.sql("""
                SELECT reference, kind, title, scope, row_count, helpdesk.person_name(generated_by) AS generated_by, actor_office, generated_at
                  FROM reporting.official_report ORDER BY generated_at DESC LIMIT 8
                """).query().listOfRows());
        return out;
    }

    /* ── the query engine ─────────────────────────────────────────────────────────────────────────────────────────────── */

    /** the sources, fields and operators the acting office may query (amounts only for the offices that read them) */
    @GetMapping("/query/sources")
    @PreAuthorize(Operations.QUERY_READERS)
    Map<String, Object> sources() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("sources", QueryEngine.describe(Operations.office(), Operations.amounts()));
        out.put("operators", QueryEngine.OPS);
        out.put("period", jdbc.sql("SELECT session, semester FROM reporting.readiness_period()").query().singleRow());
        return out;
    }

    public record Run(@NotNull QueryEngine.Definition definition, Integer page, Integer size, Boolean export) {
    }

    /** a definition run: validated, held to the scope, read-only, a page (or up to 50,000 rows for an export) */
    @PostMapping("/query/run")
    @PreAuthorize(Operations.QUERY_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> run(@Valid @RequestBody Run body) {
        String office = Operations.office();
        OfficeScope.Bound b = ops.bound(null, null, null);
        boolean exp = Boolean.TRUE.equals(body.export());
        int size = Math.max(1, Math.min(body.size() == null ? 50 : body.size(), exp ? 50000 : 1000));
        int page = Math.max(1, body.page() == null ? 1 : body.page());
        QueryEngine.Built built = QueryEngine.build(body.definition(), office, Operations.amounts(), new String[] {b.fac(), b.dept(), b.prog()},
                size, (page - 1) * size);
        if (QueryEngine.source(body.definition().source(), office).period()) {
            jdbc.sql("SELECT set_config('plan_cache_mode', 'force_generic_plan', true)").query().singleRow();
        }
        JdbcClient.StatementSpec q = jdbc.sql(built.sql());
        for (Map.Entry<String, Object[]> e : built.params().entrySet()) q = q.param(e.getKey(), e.getValue()[0], (Integer) e.getValue()[1]);
        List<Map<String, Object>> rows = q.query().listOfRows();
        long total = built.grouped() ? rows.size() : rows.isEmpty() ? 0 : ((Number) rows.get(0).get("__total")).longValue();
        List<Map<String, Object>> clean = new ArrayList<>(rows.size());
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("__total");
            clean.add(m);
        }
        List<Map<String, Object>> cols = new ArrayList<>();
        for (QueryEngine.Field f : built.columns()) {
            cols.add(Map.of("key", f.key(), "label", f.label(), "type", f.type().name(), "money", f.money()));
        }
        Map<String, Object> def = definitionWords(body.definition());
        if (page == 1 || exp) ops.log(exp ? "EXPORT" : "RUN", body.definition().source().toUpperCase(), null, def, ops.words(b), (int) total, null,
                exp ? null : "SCREEN", null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("columns", cols);
        out.put("rows", clean);
        out.put("total", total);
        out.put("page", page);
        out.put("size", size);
        out.put("grouped", built.grouped());
        out.put("scope", ops.words(b));
        out.put("at", Instant.now());
        return out;
    }

    private static Map<String, Object> definitionWords(QueryEngine.Definition d) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("source", d.source());
        if (d.session() != null) m.put("session", d.session());
        if (d.semester() != null) m.put("semester", d.semester());
        if (d.rule() != null) m.put("rule", d.rule());
        m.put("filters", d.filters() == null ? List.of() : d.filters());
        if (d.columns() != null) m.put("columns", d.columns());
        if (d.sort() != null) m.put("sort", d.sort());
        if (d.group() != null) m.put("group", d.group());
        return m;
    }

    public record Issue(@NotBlank @Size(max = 300) String title, @NotNull QueryEngine.Definition definition, Integer rows) {
    }

    /** an official reference for a query's report (DBO/STUDENT|REG|PAYMENT|EXAM|QUERY/YYYY/NNNNNN), with the definition it was drawn with */
    @PostMapping("/query/issue")
    @PreAuthorize(Operations.QUERY_READERS)
    @Transactional
    Map<String, Object> issue(@Valid @RequestBody Issue body) {
        QueryEngine.Source src = QueryEngine.source(body.definition().source(), Operations.office());
        // validated as a run would be: an official reference is never issued for a definition that would be refused
        OfficeScope.Bound b = ops.bound(null, null, null);
        QueryEngine.build(body.definition(), Operations.office(), Operations.amounts(), new String[] {b.fac(), b.dept(), b.prog()}, 1, 0);
        String words = ops.words(b);
        String ref = jdbc.sql("SELECT reporting.issue_report(:k, :t, CAST(:fl AS jsonb), :sc, NULL, :n, NULL)")
                .param("k", src.reportKind()).param("t", body.title().trim()).param("fl", Operations.json(definitionWords(body.definition())))
                .param("sc", words).param("n", body.rows(), Types.INTEGER).query(String.class).single();
        ops.log("ISSUE", src.key(), body.title().trim(), definitionWords(body.definition()), words, body.rows(), ref, null, null);
        return Map.of("reference", ref, "generatedAt", Instant.now(), "scope", words);
    }

    /* ── saved and shared queries and reports ─────────────────────────────────────────────────────────────────────────── */

    private static final String SAVED = """
            SELECT q.id, q.name, q.description, q.kind, q.source, q.definition::text AS definition, q.shared_offices,
                   helpdesk.person_name(q.owner_id) AS owner, q.owner_office, q.owner_id = :me AS mine, q.created_at, q.updated_at
              FROM reporting.saved_query q
            """;

    private List<Map<String, Object>> savedRows(String where, Map<String, Object> params) {
        JdbcClient.StatementSpec s = jdbc.sql(SAVED + where);
        for (Map.Entry<String, Object> e : params.entrySet()) s = s.param(e.getKey(), e.getValue());
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : s.query().listOfRows()) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.put("definition", new tools.jackson.databind.ObjectMapper().readValue(String.valueOf(r.get("definition")), Map.class));
            Object arr = r.get("shared_offices");
            try {
                m.put("shared_offices", arr instanceof java.sql.Array a ? List.of((String[]) a.getArray()) : List.of());
            } catch (java.sql.SQLException e) {
                m.put("shared_offices", List.of());
            }
            out.add(m);
        }
        return out;
    }

    /** my saved queries and reports, and those shared with the office I am acting in */
    @GetMapping("/saved")
    @PreAuthorize(Operations.SAVED_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> saved(@RequestParam(required = false) String kind) {
        String k = kind == null ? null : kind.trim().toUpperCase();
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("me", AuditContextHolder.required().actorId());
        p.put("office", Operations.office());
        p.put("kind", k == null ? "" : k);
        return savedRows("""
                 WHERE q.archived_at IS NULL AND (q.owner_id = :me OR CAST(:office AS text) = ANY (q.shared_offices))
                   AND (:kind = '' OR q.kind = :kind)
                 ORDER BY (q.owner_id = :me) DESC, q.name
                """, p);
    }

    public record Save(@NotBlank @Size(min = 3, max = 150) String name, @Size(max = 1000) String description, @NotBlank String kind,
                       @NotNull Map<String, Object> definition, List<String> sharedOffices) {
    }

    private static final tools.jackson.databind.ObjectMapper MAPPER = new tools.jackson.databind.ObjectMapper();

    /** a saved definition is validated as a run would be: a query that would be refused is never saved */
    private String validated(String kind, Map<String, Object> definition) {
        if ("QUERY".equals(kind)) {
            QueryEngine.Definition d = MAPPER.convertValue(definition, QueryEngine.Definition.class);
            OfficeScope.Bound b = ops.bound(null, null, null);
            QueryEngine.build(d, Operations.office(), Operations.amounts(), new String[] {b.fac(), b.dept(), b.prog()}, 1, 0);
            return d.source().trim().toUpperCase();
        }
        if ("EXAM_READINESS".equals(kind)) {
            Set<String> allowed = Set.of("session", "semester", "fac", "dept", "prog", "level", "type", "course", "rule", "by", "category", "cfac", "cdept", "view");
            for (Map.Entry<String, Object> e : definition.entrySet()) {
                if (!allowed.contains(e.getKey())) {
                    throw new DomainRuleViolation("SAVED_QUERY_FIELD", "A readiness report keeps its filters only; " + e.getKey() + " is not one.",
                            new DomainRuleViolation.Remedy("Save the report from the Examination Readiness screen.", "You"));
                }
                Object v = e.getValue();
                if (v != null && !(v instanceof String || v instanceof Number || v instanceof Boolean) || String.valueOf(v).length() > 60) {
                    throw new DomainRuleViolation("SAVED_QUERY_FIELD", "The filter " + e.getKey() + " is not a plain value.",
                            new DomainRuleViolation.Remedy("Save the report from the Examination Readiness screen.", "You"));
                }
            }
            return "EXAM_READINESS";
        }
        throw new DomainRuleViolation("SAVED_QUERY_KIND", "A saved report is a query or an examination readiness report.",
                new DomainRuleViolation.Remedy("Save from the query builder or the Examination Readiness screen.", "You"));
    }

    private static String[] offices(List<String> offices) {
        return offices == null ? new String[0] : offices.stream().filter(o -> o != null && o.matches("[a-z]{2,30}")).distinct().limit(40).toArray(String[]::new);
    }

    @PostMapping("/saved")
    @PreAuthorize(Operations.SAVED_READERS)
    @Transactional
    Map<String, Object> save(@Valid @RequestBody Save body) {
        String kind = body.kind().trim().toUpperCase();
        if ("QUERY".equals(kind) && !QueryEngine.READERS_ALL.contains(Operations.office())) {
            throw new DomainRuleViolation("SAVED_QUERY_KIND", "Your office saves readiness reports, not queries.",
                    new DomainRuleViolation.Remedy("Save the report from the Examination Readiness screen.", "You"));
        }
        String source = validated(kind, body.definition());
        UUID id = jdbc.sql("""
                INSERT INTO reporting.saved_query (name, description, kind, source, definition, owner_id, owner_office, shared_offices)
                VALUES (:n, :ds, :k, :src, CAST(:def AS jsonb), :me, :o, CAST(:sh AS text[]))
                RETURNING id
                """).param("n", body.name().trim()).param("ds", blank(body.description()), Types.VARCHAR).param("k", kind).param("src", source)
                .param("def", Operations.json(body.definition())).param("me", AuditContextHolder.required().actorId()).param("o", Operations.office())
                .param("sh", offices(body.sharedOffices()), Types.ARRAY).query(UUID.class).single();
        ops.log("SAVE", source, body.name().trim(), body.definition(), null, null, null, null, id);
        return one(id);
    }

    private Map<String, Object> one(UUID id) {
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("me", AuditContextHolder.required().actorId());
        p.put("id", id);
        return savedRows(" WHERE q.id = :id", p).stream().findFirst().orElseThrow(() -> new NotFound("saved report", id.toString()));
    }

    private Map<String, Object> mine(UUID id) {
        Map<String, Object> r = one(id);
        if (!Boolean.TRUE.equals(r.get("mine"))) {
            throw new DomainRuleViolation("SAVED_QUERY_OWNER", "A saved report is changed by its owner alone.",
                    new DomainRuleViolation.Remedy("Save a copy of your own.", "You"));
        }
        return r;
    }

    public record Update(@NotBlank @Size(min = 3, max = 150) String name, @Size(max = 1000) String description, @NotNull Map<String, Object> definition) {
    }

    @PutMapping("/saved/{id}")
    @PreAuthorize(Operations.SAVED_READERS)
    @Transactional
    Map<String, Object> update(@PathVariable UUID id, @Valid @RequestBody Update body) {
        Map<String, Object> r = mine(id);
        String source = validated(String.valueOf(r.get("kind")), body.definition());
        jdbc.sql("UPDATE reporting.saved_query SET name = :n, description = :ds, source = :src, definition = CAST(:def AS jsonb) WHERE id = :id")
                .param("n", body.name().trim()).param("ds", blank(body.description()), Types.VARCHAR).param("src", source)
                .param("def", Operations.json(body.definition())).param("id", id).update();
        ops.log("SAVE", source, body.name().trim(), body.definition(), null, null, null, null, id);
        return one(id);
    }

    public record Share(@NotNull List<String> offices) {
    }

    /** shared with offices of the register — the Director of ICT, the Academic Office, the Registrar, the Bursar, a Dean, a Head — who
     *  read it within their own scope */
    @PostMapping("/saved/{id}/share")
    @PreAuthorize(Operations.SAVED_READERS)
    @Transactional
    Map<String, Object> share(@PathVariable UUID id, @Valid @RequestBody Share body) {
        Map<String, Object> r = mine(id);
        jdbc.sql("UPDATE reporting.saved_query SET shared_offices = CAST(:sh AS text[]) WHERE id = :id")
                .param("sh", offices(body.offices()), Types.ARRAY).param("id", id).update();
        ops.log("SHARE", String.valueOf(r.get("source")), String.valueOf(r.get("name")), Map.of("offices", List.of(offices(body.offices()))), null, null, null, null, id);
        return one(id);
    }

    @PostMapping("/saved/{id}/archive")
    @PreAuthorize(Operations.SAVED_READERS)
    @Transactional
    Map<String, Object> archive(@PathVariable UUID id) {
        Map<String, Object> r = mine(id);
        jdbc.sql("UPDATE reporting.saved_query SET archived_at = now() WHERE id = :id").param("id", id).update();
        ops.log("ARCHIVE", String.valueOf(r.get("source")), String.valueOf(r.get("name")), null, null, null, null, null, id);
        return Map.of("archived", true);
    }

    /** the offices a report may be shared with */
    @GetMapping("/offices")
    @PreAuthorize(Operations.SAVED_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> offices() {
        return jdbc.sql("SELECT code, label FROM ref.office WHERE code NOT IN ('student', 'applicant', 'extexaminer') ORDER BY label").query().listOfRows();
    }

    /* ── the query log and the official reports ───────────────────────────────────────────────────────────────────────── */

    /** the query log: everyone's for the Database Operations office, ICT and the auditors; one's own for every other office */
    @GetMapping("/history")
    @PreAuthorize(Operations.SAVED_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> history(@RequestParam(defaultValue = "false") boolean all, @RequestParam(required = false) String action,
                                @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        boolean everyone = all && Operations.AUDITORS.contains(Operations.office());
        int sz = Math.max(1, Math.min(size, 500));
        int pg = Math.max(1, page);
        String act = action == null ? null : action.trim().toUpperCase();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT l.at, helpdesk.person_name(l.actor_id) AS actor, l.actor_office, l.action, l.source, l.title, l.definition::text AS definition,
                       l.scope, l.row_count, l.reference, l.format, count(*) OVER () AS total_rows
                  FROM reporting.query_log l
                 WHERE (CAST(:all AS boolean) OR l.actor_id = :me)
                   AND (CAST(:act AS text) IS NULL OR l.action = CAST(:act AS text))
                 ORDER BY l.at DESC
                 LIMIT :n OFFSET :o
                """).param("all", everyone).param("me", AuditContextHolder.required().actorId()).param("act", act, Types.VARCHAR)
                .param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        return Map.of("rows", rows, "total", total, "page", pg, "size", sz, "everyone", everyone);
    }

    /** the register of official reports: all of it for the Database Operations office, ICT and the auditors; one's own otherwise */
    @GetMapping("/reports")
    @PreAuthorize(Operations.SAVED_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> reports(@RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size,
                                @RequestParam(required = false) String q) {
        boolean everyone = Operations.AUDITORS.contains(Operations.office());
        int sz = Math.max(1, Math.min(size, 500));
        int pg = Math.max(1, page);
        String like = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.reference, r.kind, r.title, r.filters::text AS filters, r.scope, r.figures::text AS figures, r.row_count, r.parts::text AS parts,
                       helpdesk.person_name(r.generated_by) AS generated_by, r.actor_office, r.generated_at, count(*) OVER () AS total_rows
                  FROM reporting.official_report r
                 WHERE (CAST(:all AS boolean) OR r.generated_by = :me)
                   AND (CAST(:q AS text) IS NULL OR lower(r.reference || ' ' || r.title) LIKE CAST(:q AS text))
                 ORDER BY r.generated_at DESC
                 LIMIT :n OFFSET :o
                """).param("all", everyone).param("me", AuditContextHolder.required().actorId()).param("q", like, Types.VARCHAR)
                .param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        return Map.of("rows", rows, "total", total, "page", pg, "size", sz);
    }

    public record Logged(@NotBlank @Size(max = 10) String action, @NotBlank @Size(max = 40) String source, @Size(max = 300) String title,
                        Integer rows, @Size(max = 40) String reference, @Size(max = 10) String format, Map<String, Object> definition) {
    }

    /** an export or print from a Database Operations screen, on the query log with its reference */
    @PostMapping("/log")
    @PreAuthorize(Operations.SAVED_READERS)
    Map<String, Object> logged(@Valid @RequestBody Logged body) {
        String action = "PRINT".equalsIgnoreCase(body.action()) ? "PRINT" : "EXPORT";
        String src = body.source().trim().toUpperCase();
        if (!src.matches("[A-Z_]{3,40}")) src = "QUERY";
        String fmt = body.format() == null ? null : body.format().toUpperCase();
        if (fmt != null && !Set.of("XLSX", "PDF", "PRINT").contains(fmt)) fmt = null;
        Map<String, Object> def = body.definition() == null || body.definition().size() > 30 ? null : body.definition();
        ops.log(action, src, body.title(), def, null, body.rows(), body.reference(), fmt, null);
        return Map.of("logged", true);
    }

    /* ── data quality ─────────────────────────────────────────────────────────────────────────────────────────────────── */

    @GetMapping("/data-quality")
    @PreAuthorize(DQ_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> quality(@RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String prog, @RequestParam(required = false) String session,
                                @RequestParam(required = false) Integer semester) {
        OfficeScope.Bound b = ops.bound(fac, dept, prog);
        Map<String, Object> p = period();
        String s = session != null && session.matches("[0-9]{4}/[0-9]{4}") ? session : (String) p.get("session");
        int sem = semester != null && semester >= 1 && semester <= 3 ? semester : ((Number) p.get("semester")).intValue();
        jdbc.sql("SELECT set_config('plan_cache_mode', 'force_generic_plan', true)").query().singleRow();
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM reporting.data_quality(CAST(:f AS text), CAST(:d AS text), CAST(:p AS text), CAST(:s AS text), CAST(:sem AS int))")
                .param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR)
                .param("s", s).param("sem", sem).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("scope", ops.words(b));
        out.put("session", s);
        out.put("semester", sem);
        out.put("at", Instant.now());
        return out;
    }

    /** the records behind a data quality figure, names A to Z */
    @GetMapping("/data-quality/{kind}")
    @PreAuthorize(DQ_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> qualityRows(@PathVariable String kind, @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                    @RequestParam(required = false) String prog, @RequestParam(required = false) String session,
                                    @RequestParam(required = false) Integer semester, @RequestParam(defaultValue = "1") int page,
                                    @RequestParam(defaultValue = "50") int size) {
        String k = kind.trim().toUpperCase();
        if (!DQ_KINDS.contains(k)) throw new NotFound("data quality figure", kind);
        OfficeScope.Bound b = ops.bound(fac, dept, prog);
        Map<String, Object> p = period();
        String s = session != null && session.matches("[0-9]{4}/[0-9]{4}") ? session : (String) p.get("session");
        int sem = semester != null && semester >= 1 && semester <= 3 ? semester : ((Number) p.get("semester")).intValue();
        int sz = Math.max(1, Math.min(size, 50000));
        int pg = Math.max(1, page);
        jdbc.sql("SELECT set_config('plan_cache_mode', 'force_generic_plan', true)").query().singleRow();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT st.id AS student_id, st.surname, st.other_names, st.matric_no, st.jamb_reg_no AS jamb_no, st.status, st.current_level AS level,
                       st.entry_session, pr.name AS programme, d.name AS department, f.name AS faculty, q.detail, count(*) OVER () AS total_rows
                  FROM reporting.data_quality_rows(CAST(:f AS text), CAST(:d AS text), CAST(:p AS text), CAST(:s AS text), CAST(:sem AS int)) q
                  JOIN people.student st ON st.id = q.student_id
                  LEFT JOIN ref.programme pr ON pr.code = st.programme_code
                  LEFT JOIN ref.department d ON d.code = pr.dept_code
                  LEFT JOIN ref.faculty f ON f.code = pr.faculty_code
                 WHERE q.kind = :k
                 ORDER BY st.surname, st.other_names, st.matric_no
                 LIMIT :n OFFSET :o
                """).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR)
                .param("s", s).param("sem", sem).param("k", k).param("n", sz).param("o", (pg - 1) * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        if (pg == 1) ops.log("RUN", "DATA_QUALITY", "Data quality: " + k, Map.of("kind", k, "session", s, "semester", sem), ops.words(b), (int) total, null, "SCREEN", null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", k);
        out.put("rows", rows);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("scope", ops.words(b));
        out.put("at", Instant.now());
        return out;
    }
}
