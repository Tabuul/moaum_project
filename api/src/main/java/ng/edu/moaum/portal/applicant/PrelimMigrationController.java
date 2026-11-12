package ng.edu.moaum.portal.applicant;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.ErrorResponseException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V737: old-portal applicants of the two preliminary programmes — Preliminary Technology & Industrial Studies and Preliminary
 * Science — brought across a programme at a time (the template of the route, the file staged on the server a chunk at a time,
 * checked in a dry run, previewed, confirmed and imported with real progress, the history of every upload); the application fees
 * paid on the old portal held until the Bursary verifies them (never by the officer who uploaded them); and an applicant's
 * programme corrected between the two routes by the Director of ICT (one record, the same number, the fee and the history kept).
 * The rules are the database's (admissions.prelim_migration_*, prelim_legacy_*, prelim_change_route*); this door holds who may do
 * what, the route each reader is held to, and carries the rows.
 *
 * Who: the Director of ICT, the Academic Office, a Database Operator over the whole University, super and the Head of the ICT
 * Support Desk upload; an ICT Support Agent only on a posting over the whole University that carries MIGRATE_PRELIM_APPLICANTS. The
 * Bursary (and super) verify the fees. The Director of ICT, super and the Head of the Support Desk change a programme; an agent only
 * with CHANGE_PRELIM_PROGRAMME on a posting over the whole University. The Registry reads everything; each preliminary office
 * reads its own programme's uploads, fees and corrections.
 */
@RestController
@RequestMapping("/api/v1/admissions/preliminary/migration")
class PrelimMigrationController {

    /** who uploads: the Director of ICT, the Academic Office, a Database Operator (over the whole University), super, the Head of the
     *  ICT Support Desk, and an ICT Support Agent the Director authorised (the capability on a University-wide posting) */
    private static final String MIGRATORS =
            "hasAnyAuthority('OFFICE_ict','OFFICE_academic','OFFICE_dbops','OFFICE_super','OFFICE_helpdeskhead','OFFICE_ictagent')";
    /** who verifies a fee paid on the old portal: the Bursary (the database refuses the officer who uploaded it) */
    private static final String FEE_DECIDERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    /** who reads the uploads, the fees and the history: the uploaders, the Bursary, the Registry and the two programmes' offices (their own) */
    private static final String READERS =
            "hasAnyAuthority('OFFICE_ict','OFFICE_academic','OFFICE_dbops','OFFICE_super','OFFICE_helpdeskhead','OFFICE_ictagent',"
            + "'OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_prelim','OFFICE_prelimtech')";
    /** who changes an applicant's programme between the two routes */
    private static final String CORRECTORS = "hasAnyAuthority('OFFICE_ict','OFFICE_super','OFFICE_helpdeskhead','OFFICE_ictagent')";
    /** who reads an applicant's record and the corrections: the correctors, the Academic Office, the Registry, the programmes' offices */
    private static final String CORRECTION_READERS =
            "hasAnyAuthority('OFFICE_ict','OFFICE_super','OFFICE_helpdeskhead','OFFICE_ictagent','OFFICE_academic','OFFICE_registrar',"
            + "'OFFICE_dregistrar','OFFICE_prelim','OFFICE_prelimtech')";

    /* the same sets, for the acting office (hasAnyAuthority matches any office the token carries) */
    private static final Set<String> MIGRATOR_OFFICES = Set.of("ict", "academic", "dbops", "super", "helpdeskhead", "ictagent");
    private static final Set<String> READER_OFFICES = Set.of("ict", "academic", "dbops", "super", "helpdeskhead", "ictagent",
            "bursar", "registrar", "dregistrar", "prelim", "prelimtech");
    private static final Set<String> CORRECTOR_OFFICES = Set.of("ict", "super", "helpdeskhead", "ictagent");
    private static final Set<String> CORRECTION_READER_OFFICES = Set.of("ict", "super", "helpdeskhead", "ictagent", "academic",
            "registrar", "dregistrar", "prelim", "prelimtech");
    private static final Set<String> FEE_DECIDER_OFFICES = Set.of("bursar", "super");
    /** who reads the preliminary desk (PrelimDeskController's READERS: its central offices, and a Head of Department or a Dean over
     *  their own): a row's link to the desk is offered only to them */
    private static final Set<String> DESK_READER_OFFICES = Set.of("prelim", "prelimtech", "academic", "registrar", "dregistrar", "super", "admin", "ict",
            "hod", "dean");
    /** the offices of a route of their own: each reads its own programme's uploads, fees and corrections */
    private static final Set<String> ROUTE_OFFICES = Set.of("prelim", "prelimtech");

    static final String MIGRATE = "MIGRATE_PRELIM_APPLICANTS";
    static final String CHANGE = "CHANGE_PRELIM_PROGRAMME";

    /** the two programmes an old-portal applicant comes into, in the order the University names them */
    static final List<String> ROUTES = List.of("PRELIMINARY_TECHNOLOGY", "PRELIMINARY_SCIENCE");
    private static final Map<String, String> FILE_NAMES = Map.of(
            "PRELIMINARY_TECHNOLOGY", "PRELIMINARY_TECHNOLOGY_INDUSTRIAL_STUDIES_APPLICANTS_TEMPLATE.xlsx",
            "PRELIMINARY_SCIENCE", "PRELIMINARY_SCIENCES_APPLICANTS_TEMPLATE.xlsx");

    private static final Set<String> VERDICTS = Set.of("READY", "WARNING", "DUPLICATE_IN_FILE", "CONFLICT", "REQUIRES_REVIEW", "ERROR");
    private static final Set<String> RESULTS = Set.of("CREATED", "UPDATED", "RECONCILED", "UNCHANGED", "SKIPPED", "FAILED");
    private static final Set<String> FEE_STATES = Set.of("REQUIRES_REVIEW", "VERIFIED", "REJECTED");
    /** a chunk of rows is at most 1,000; a body above this is not a chunk of the template */
    private static final long MAX_BODY = 12L * 1024 * 1024;

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final PrelimApplicantService prelim;
    private final TransactionTemplate tx;
    private final TransactionTemplate readTx;
    private final tools.jackson.databind.ObjectMapper mapper;

    PrelimMigrationController(JdbcClient jdbc, OfficeScope scope, PrelimApplicantService prelim, PlatformTransactionManager transactions,
                              tools.jackson.databind.ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.prelim = prelim;
        this.mapper = mapper;
        this.tx = new TransactionTemplate(transactions);
        this.readTx = new TransactionTemplate(transactions);
        this.readTx.setReadOnly(true);
    }

    /** the upload reaches every applicant of a programme, so a Database Operator works it only on a grant over the whole University
     *  (SCOPE_UNIVERSITY for one held to a faculty, department or programme); asked before every request here, as V679 for PG */
    @ModelAttribute
    void universityOperatorOnly() {
        scope.requireUniversityOperator("The old-portal preliminary applicant migration");
    }

    /* ── who is asking ── */

    private static String office() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    private static UUID actor() {
        return AuditContextHolder.current().map(AuditContext::actorId).orElse(null);
    }

    /** whether the acting person, as an ICT Support Agent, holds the capability on a posting over the whole University (the
     *  database's own helpdesk.agent_scope_for — a FACULTY, DEPARTMENT or COLLEGE posting does not reach an applicant) */
    private boolean agentHolds(String capability) {
        UUID me = actor();
        if (me == null) return false;
        return Boolean.TRUE.equals(jdbc.sql("SELECT global FROM helpdesk.agent_scope_for(:p, :c)").param("p", me).param("c", capability)
                .query(Boolean.class).optional().orElse(false));
    }

    private boolean mayMigrate() {
        String o = office();
        if ("ictagent".equals(o)) return agentHolds(MIGRATE);
        return MIGRATOR_OFFICES.contains(o);
    }

    private boolean mayChange() {
        String o = office();
        if ("ictagent".equals(o)) return agentHolds(CHANGE);
        return CORRECTOR_OFFICES.contains(o);
    }

    /** the uploads, their rows and the old-portal fees: an agent reads them only with the migration's own capability (changing a
     *  programme reads the corrections and finds an applicant, never the files) */
    private boolean mayReadMigration() {
        String o = office();
        if ("ictagent".equals(o)) return agentHolds(MIGRATE);
        return READER_OFFICES.contains(o);
    }

    private boolean mayReadCorrections() {
        String o = office();
        if ("ictagent".equals(o)) return agentHolds(CHANGE);
        return CORRECTION_READER_OFFICES.contains(o);
    }

    /** a refusal of the office, as the portal words one: 403 with its code and what to do */
    private static ErrorResponseException forbidden(String code, String detail, String remedy, String office) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, detail);
        p.setTitle(code.endsWith("_CAPABILITY") ? "Not in your support posting" : "Not for your office");
        p.setProperty("code", code);
        p.setProperty("remedy", Map.of("message", remedy, "office", office));
        return new ErrorResponseException(HttpStatus.FORBIDDEN, p, null);
    }

    private void requireMigrator() {
        if (mayMigrate()) return;
        if ("ictagent".equals(office())) {
            throw forbidden("PRELIMMIG_CAPABILITY", "Your support posting does not carry uploading old-portal preliminary applicants over the whole University.",
                    "Ask the Director of ICT to grant it with a posting over the whole University.", "Director of ICT");
        }
        throw forbidden("PRELIMMIG_OFFICE", "The Director of ICT, the Academic Office or a Database Operator uploads old-portal preliminary applicants.",
                "Ask the Director of ICT.", "Director of ICT");
    }

    private void requireReader() {
        if (mayReadMigration()) return;
        if ("ictagent".equals(office())) {
            throw forbidden("PRELIMMIG_CAPABILITY", "Your support posting does not carry the old-portal preliminary applicant migration.",
                    "Ask the Director of ICT to grant it with a posting over the whole University.", "Director of ICT");
        }
        throw forbidden("PRELIMMIG_OFFICE", "This office does not read the old-portal preliminary applicant migration.", "Ask the Director of ICT.", "Director of ICT");
    }

    private void requireCorrector() {
        if (mayChange()) return;
        if ("ictagent".equals(office())) {
            throw forbidden("PRELIM_CHANGE_CAPABILITY", "Your support posting does not carry changing a preliminary applicant's programme over the whole University.",
                    "Ask the Director of ICT to grant it with a posting over the whole University.", "Director of ICT");
        }
        throw forbidden("PRELIM_CHANGE_OFFICE", "A preliminary applicant's programme is changed by the Director of ICT.", "Ask the Director of ICT.", "Director of ICT");
    }

    private void requireCorrectionReader() {
        if (mayReadCorrections()) return;
        if ("ictagent".equals(office())) {
            throw forbidden("PRELIM_CHANGE_CAPABILITY", "Your support posting does not carry changing a preliminary applicant's programme.",
                    "Ask the Director of ICT to grant it with a posting over the whole University.", "Director of ICT");
        }
        throw forbidden("PRELIM_CHANGE_OFFICE", "This office does not read preliminary applicants' programme corrections.", "Ask the Director of ICT.", "Director of ICT");
    }

    /** finding an applicant is the upload's search and the correction's: a reader of either */
    private void requireFinder() {
        if (mayReadMigration() || mayReadCorrections()) return;
        if ("ictagent".equals(office())) {
            throw forbidden("PRELIMMIG_CAPABILITY", "Your support posting carries neither the old-portal preliminary applicant migration nor changing a preliminary applicant's programme.",
                    "Ask the Director of ICT to grant one with a posting over the whole University.", "Director of ICT");
        }
        throw forbidden("PRELIMMIG_OFFICE", "This office does not find preliminary applicants here.", "Ask the Director of ICT.", "Director of ICT");
    }

    /* ── the routes: the two preliminary programmes, and the one a programme's office is held to ── */

    /** one of the two programmes, by its code or its page's slug */
    private static String routeOf(String raw) {
        String r = raw == null ? "" : PrelimApplicantService.SLUGS.getOrDefault(raw.trim().toLowerCase(), raw.trim().toUpperCase());
        if (!ROUTES.contains(r)) {
            throw new DomainRuleViolation("PRELIMMIG_ROUTE", "An old-portal upload is of Preliminary Technology & Industrial Studies or of Preliminary Science.",
                    new DomainRuleViolation.Remedy("Choose one of the two programmes.", "You"));
        }
        return r;
    }

    /** the routes the acting office reads: both, or a programme office's own */
    private List<String> ownRoutes() {
        String o = office();
        if (!ROUTE_OFFICES.contains(o)) return ROUTES;
        List<String> mine = jdbc.sql("SELECT route FROM admissions.prelim_programme WHERE office_code = :o").param("o", o).query(String.class).list();
        return ROUTES.stream().filter(mine::contains).toList();
    }

    /** the route a read is about: the one named (within the office's own), the office's own for a programme office, or every route (null) */
    private String readRoute(String requested) {
        List<String> own = ownRoutes();
        String r = requested == null || requested.isBlank() ? null : routeOf(requested);
        if (ROUTE_OFFICES.contains(office())) {
            if (own.isEmpty()) throw new org.springframework.security.access.AccessDeniedException("The " + office() + " office has no preliminary programme of its own");
            if (r == null) return own.size() == 1 ? own.get(0) : null;
            if (!own.contains(r)) throw new org.springframework.security.access.AccessDeniedException("The " + office() + " office does not read " + r);
        }
        return r;
    }

    private String sessionOf(String route) {
        return jdbc.sql("SELECT policy.route_session(:r)").param("r", route).query(String.class).single();
    }

    /** the batch's route, which the reader must read; not found otherwise */
    private String batchRoute(UUID batch) {
        String r = jdbc.sql("SELECT route FROM admissions.prelim_migration_batch WHERE id = :b").param("b", batch).query(String.class).optional()
                .orElseThrow(() -> new NotFound("preliminary migration batch", batch));
        if (!ownRoutes().contains(r)) throw new NotFound("preliminary migration batch", batch);
        return r;
    }

    /** the application's route, if it is a preliminary application of one of the two programmes the reader reads; not found otherwise */
    private String applicationRoute(UUID app) {
        String r = jdbc.sql("SELECT route FROM admissions.prelim_review WHERE application_id = :a").param("a", app).query(String.class).optional().orElse(null);
        if (r == null || !ownRoutes().contains(r)) throw new NotFound("preliminary application", app);
        return r;
    }

    /* ── reading the database's answers ── */

    @SuppressWarnings("unchecked")
    private Map<String, Object> parseMap(String text) {
        return text == null ? Map.of() : (Map<String, Object>) mapper.readValue(text, Map.class);
    }

    private Object parse(Object pg) {
        return pg == null ? null : mapper.readValue(pg.toString(), Object.class);
    }

    /** a page of the database's own list ({total, rows}), with the page and size asked for: {total, page, size, rows} */
    @SuppressWarnings("unchecked")
    private Map<String, Object> paged(String json, int page, int size) {
        Map<String, Object> out = new LinkedHashMap<>(parseMap(json));
        out.putIfAbsent("total", 0);
        out.put("page", page);
        out.put("size", size);
        Object rows = out.get("rows");
        out.put("rows", rows instanceof List<?> l ? new ArrayList<>((List<Map<String, Object>>) l) : new ArrayList<Map<String, Object>>());
        return out;
    }

    private static int sizeOf(int size, int max) {
        return Math.max(1, Math.min(size, max));
    }

    /* ── what the caller may do, and the two programmes ── */

    @GetMapping("/access")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> access() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", office());
        out.put("mayMigrate", mayMigrate());
        out.put("mayDecideFees", FEE_DECIDER_OFFICES.contains(office()));
        out.put("mayChangeProgramme", mayChange());
        out.put("mayRead", mayReadMigration());
        out.put("mayReadCorrections", mayReadCorrections());
        out.put("mayReadDesk", DESK_READER_OFFICES.contains(office()));
        List<Map<String, Object>> routes = new ArrayList<>();
        for (String r : ownRoutes()) routes.add(routeFacts(r));
        out.put("routes", routes);
        return out;
    }

    /** a programme: its name, its office, the session it admits into, the fee the Bursary stated and its application window */
    private Map<String, Object> routeFacts(String route) {
        String s = sessionOf(route);
        Map<String, Object> p = jdbc.sql("""
                SELECT p.route, p.name, p.office_code, o.label AS office, p.max_sittings
                  FROM admissions.prelim_programme p LEFT JOIN ref.office o ON o.code = p.office_code WHERE p.route = :r
                """).param("r", route).query().singleRow();
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("route", route);
        m.put("name", p.get("name"));
        m.put("office", p.get("office"));
        m.put("officeCode", p.get("office_code"));
        m.put("session", s);
        m.put("maxSittings", p.get("max_sittings"));
        m.put("fee", fee(s, route));
        Map<String, Object> w = jdbc.sql("""
                SELECT state, opens_at AS "opensAt", closes_at AS "closesAt"
                  FROM policy.window_state((SELECT window_type FROM admissions.prelim_programme WHERE route = :r), :s, NULL)
                """).param("r", route).param("s", s).query().listOfRows().stream().findFirst().orElse(null);
        m.put("window", w);
        return m;
    }

    /** the application fee the Bursary stated for the route and session: the fee, the portal charge, whether it is stated */
    private Map<String, Object> fee(String session, String route) {
        Map<String, Object> f = jdbc.sql("SELECT * FROM admissions.route_fee_rule(:s, :r)").param("s", session).param("r", route)
                .query().listOfRows().stream().findFirst().orElse(null);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("application", f == null ? null : f.get("application_fee"));
        m.put("portal", f == null ? null : f.get("portal_charge"));
        m.put("stated", f != null && !Boolean.FALSE.equals(f.get("stated")) && f.get("application_fee") != null);
        return m;
    }

    /* ── the template: the database's columns for the route, and this portal's targets, qualifications and words ── */

    @GetMapping("/template")
    @PreAuthorize(MIGRATORS)
    @Transactional(readOnly = true)
    Map<String, Object> template(@RequestParam String route) {
        requireMigrator();
        String r = routeOf(route);
        String s = sessionOf(r);
        Map<String, Object> p = jdbc.sql("SELECT name, max_sittings FROM admissions.prelim_programme WHERE route = :r").param("r", r).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("route", r);
        out.put("name", p.get("name"));
        out.put("session", s);
        out.put("fileName", FILE_NAMES.get(r));
        out.put("maxSittings", p.get("max_sittings"));
        List<Map<String, Object>> columns = new ArrayList<>();
        for (Map<String, Object> c : jdbc.sql("SELECT key, header, section, required, note, choices FROM admissions.prelim_migration_columns(:r)")
                .param("r", r).query().listOfRows()) {
            Map<String, Object> m = new LinkedHashMap<>(c);
            m.put("choices", c.get("choices") == null ? null : PrelimApplicantService.strings(c.get("choices")));
            columns.add(m);
        }
        out.put("columns", columns);
        out.put("targets", jdbc.sql("""
                SELECT t.id, coalesce(g.name, t.requested_name) AS name, t.programme_code AS code, t.group_name AS "group", t.kind,
                       (SELECT coalesce(jsonb_agg(jsonb_build_object('code', sp.code, 'name', sp.name) ORDER BY sp.ord, sp.name), '[]'::jsonb)::text
                          FROM admissions.prelim_specialisation sp WHERE sp.target_id = t.id AND sp.active) AS specialisations
                  FROM admissions.prelim_target t LEFT JOIN ref.programme g ON g.code = t.programme_code
                 WHERE t.route = :r AND t.state = 'MAPPED'
                 ORDER BY t.ord, coalesce(g.name, t.requested_name)
                """).param("r", r).query().listOfRows().stream().map(t -> {
                    Map<String, Object> m = new LinkedHashMap<>(t);
                    m.put("specialisations", PrelimApplicantService.json(t.get("specialisations")));
                    return m;
                }).toList());
        out.put("qualifications", jdbc.sql("""
                SELECT q.code, q.label FROM admissions.qualification_type q JOIN admissions.prelim_programme p ON q.code = ANY (p.qualification_types)
                 WHERE p.route = :r AND q.active ORDER BY q.ord
                """).param("r", r).query().listOfRows());
        out.put("examBodies", choicesOf(columns, "olevel1Body"));
        out.put("subjects", subjects());
        // the grades are the database's own scale (admissions.grade_rank): every grade it ranks, in its order
        out.put("grades", jdbc.sql("""
                SELECT g FROM (SELECT chr(64 + l) || d AS g FROM generate_series(1, 26) l, generate_series(1, 9) d) x
                 WHERE admissions.grade_rank(g) < 99 ORDER BY admissions.grade_rank(g), g
                """).query(String.class).list());
        Map<String, Object> words = new LinkedHashMap<>();
        for (String kind : List.of("APPLICATION", "ADMISSION", "PAYMENT")) {
            words.put(kind.toLowerCase(), jdbc.sql("""
                    SELECT initcap(s.word) AS word, s.value FROM admissions.prelim_legacy_status s
                     WHERE s.kind = :k AND btrim(s.word) <> '' ORDER BY s.value, s.word
                    """).param("k", kind).query().listOfRows());
        }
        out.put("statusWords", words);
        out.put("fee", fee(s, r));
        return out;
    }

    private static List<String> choicesOf(List<Map<String, Object>> columns, String key) {
        for (Map<String, Object> c : columns) {
            if (key.equals(c.get("key")) && c.get("choices") instanceof List<?> l) return l.stream().map(String::valueOf).toList();
        }
        return List.of();
    }

    /** the O'Level subjects a file may name: the database's own list (admissions.prelim_olevel_subjects — the form's subjects and every
     *  subject a preliminary rule names), the one the check reads */
    private List<String> subjects() {
        return jdbc.sql("SELECT s.name FROM admissions.prelim_olevel_subjects() s").query(String.class).list();
    }

    /* ── a batch: opened, its rows staged, checked, imported, finished or set aside ── */

    public record OpenIn(@NotBlank @Size(max = 40) String route, @NotBlank @Size(max = 255) String fileName, @Size(max = 64) String sha256,
                         @Min(1) @Max(20000) int rows, Boolean update, Boolean tell) {
    }

    @PostMapping("/batches")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody OpenIn body) {
        requireMigrator();
        AuditContextHolder.required();
        return parseMap(jdbc.sql("SELECT admissions.prelim_migration_open(:r, :f, :s, :n, :u, :t)::text")
                .param("r", routeOf(body.route())).param("f", body.fileName().trim())
                .param("s", body.sha256() == null || body.sha256().isBlank() ? null : body.sha256().trim().toLowerCase(), Types.VARCHAR)
                .param("n", body.rows()).param("u", Boolean.TRUE.equals(body.update())).param("t", body.tell() == null || body.tell())
                .query(String.class).single());
    }

    public record RowsIn(@Min(1) int first, @NotNull @Size(min = 1, max = 1000) List<Map<String, Object>> rows) {
    }

    @PostMapping("/batches/{id}/rows")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> stage(@PathVariable UUID id, @Valid @RequestBody RowsIn body, HttpServletRequest request) {
        requireMigrator();
        if (request.getContentLengthLong() > MAX_BODY) {
            throw new DomainRuleViolation("PRELIMMIG_CHUNK_SIZE", "A chunk of the file is at most " + (MAX_BODY / 1024 / 1024) + " MB; this one is larger.",
                    new DomainRuleViolation.Remedy("Send the rows in smaller chunks (the page sends 500 at a time).", "You"));
        }
        batchRoute(id);
        // each cell as text, trimmed, blanks dropped: the database keeps only the template's columns and cleans each cell again
        List<Map<String, String>> rows = new ArrayList<>(body.rows().size());
        for (Map<String, Object> r : body.rows()) {
            Map<String, String> m = new LinkedHashMap<>();
            if (r != null) {
                for (Map.Entry<String, Object> e : r.entrySet()) {
                    Object v = e.getValue();
                    if (e.getKey() == null || e.getKey().length() > 60 || v == null || v instanceof Map || v instanceof List) continue;
                    String t = String.valueOf(v).trim();
                    if (!t.isEmpty()) m.put(e.getKey(), t.length() > 1000 ? t.substring(0, 1000) : t);
                }
            }
            rows.add(m);
        }
        return parseMap(jdbc.sql("SELECT admissions.prelim_migration_stage(:b, :first, :rows::jsonb)::text")
                .param("b", id).param("first", body.first()).param("rows", mapper.writeValueAsString(rows))
                .query(String.class).single());
    }

    public record RangeIn(@Min(1) int from, @Min(1) int to) {
    }

    @PostMapping("/batches/{id}/check")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> check(@PathVariable UUID id, @Valid @RequestBody RangeIn body) {
        requireMigrator();
        batchRoute(id);
        return parseMap(jdbc.sql("SELECT admissions.prelim_migration_check(:b, :f, :t)::text")
                .param("b", id).param("f", body.from()).param("t", body.to()).query(String.class).single());
    }

    @PostMapping("/batches/{id}/import")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> importRows(@PathVariable UUID id, @Valid @RequestBody RangeIn body) {
        requireMigrator();
        AuditContextHolder.required();
        batchRoute(id);
        return parseMap(jdbc.sql("SELECT admissions.prelim_migration_import(:b, :f, :t)::text")
                .param("b", id).param("f", body.from()).param("t", body.to()).query(String.class).single());
    }

    @PostMapping("/batches/{id}/finish")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> finish(@PathVariable UUID id) {
        requireMigrator();
        batchRoute(id);
        return parseMap(jdbc.sql("SELECT admissions.prelim_migration_finish(:b)::text").param("b", id).query(String.class).single());
    }

    public record ReasonIn(@NotBlank @Size(max = 1000) String reason) {
    }

    @PostMapping("/batches/{id}/abandon")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> abandon(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        requireMigrator();
        batchRoute(id);
        return parseMap(jdbc.sql("SELECT admissions.prelim_migration_abandon(:b, :r)::text").param("b", id).param("r", body.reason().trim())
                .query(String.class).single());
    }

    /** the history of uploads, newest first: a programme's, or both (a programme's office: its own) */
    @GetMapping("/batches")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> batches(@RequestParam(required = false) String route, @RequestParam(defaultValue = "0") int page,
                                @RequestParam(defaultValue = "50") int size) {
        requireReader();
        String r = readRoute(route);
        int sz = sizeOf(size, 500);
        int pg = Math.max(page, 0);
        return paged(jdbc.sql("SELECT admissions.prelim_migration_batches(:r, :n, :o)::text")
                .param("r", r, Types.VARCHAR).param("n", sz).param("o", pg * sz).query(String.class).single(), pg, sz);
    }

    @GetMapping("/batches/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> batch(@PathVariable UUID id) {
        requireReader();
        batchRoute(id);
        return parseMap(jdbc.sql("SELECT admissions.prelim_migration_summary(:b)::text").param("b", id).query(String.class).single());
    }

    /** the rows of a batch as checked or imported, filtered and paged on the server: by verdict, by result, or every row with a problem */
    @GetMapping("/batches/{id}/rows")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> rows(@PathVariable UUID id, @RequestParam(required = false) String status, @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        requireReader();
        batchRoute(id);
        int sz = sizeOf(size, 500);
        int pg = Math.max(page, 0);
        String st = status == null || status.isBlank() ? "ALL" : status.trim().toUpperCase();
        String where = rowFilter(st);
        String like = q == null || q.isBlank() ? null : "%" + q.trim().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        long total = jdbc.sql("""
                SELECT count(*) FROM admissions.prelim_migration_row r LEFT JOIN admissions.application a ON a.id = r.application_id
                 WHERE r.batch_id = :b AND (""" + where + ")" + LIKE)
                .param("b", id).param("st", st).param("like", like, Types.VARCHAR).query(Long.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", listRows(id, where, st, like, sz, pg * sz, true));
        return out;
    }

    /** every row that is not plainly ready or did not import, for the downloadable error report (the cells as given are left out:
     *  the report names the row, the applicant, the old number, the verdict or result, and each problem with its fix) */
    @GetMapping("/batches/{id}/report")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> report(@PathVariable UUID id) {
        requireReader();
        batchRoute(id);
        return listRows(id, rowFilter("PROBLEMS"), "PROBLEMS", null, 20000, 0, false);
    }

    private static final String LIKE = """
             AND (:like::text IS NULL OR r.legacy_no ILIKE :like OR r.applicant ILIKE :like OR r.email ILIKE :like OR a.application_no ILIKE :like)
            """;

    private static String rowFilter(String st) {
        if ("ALL".equals(st)) return "true";
        if ("PROBLEMS".equals(st)) return "(r.verdict IS DISTINCT FROM 'READY' OR r.result IN ('FAILED', 'SKIPPED'))";
        if (VERDICTS.contains(st)) return "r.verdict = :st";
        if (RESULTS.contains(st)) return "r.result = :st";
        throw new DomainRuleViolation("PRELIMMIG_FILTER", "No such filter: " + st + ".", new DomainRuleViolation.Remedy("Choose a filter from the list.", "You"));
    }

    /** the rows, with the matched application's own route and session (appRoute, appSession): a row matched to an application of the
     *  other programme or another session links to where that application is */
    private List<Map<String, Object>> listRows(UUID batch, String where, String st, String like, int limit, int offset, boolean withData) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.id, r.row_no, r.data ->> 'sheetRow' AS sheet_row, r.legacy_no, r.applicant, r.email, r.fee_ref, r.verdict, r.match, r.action,
                       r.problems::text AS problems, r.result, r.result_note, r.decided_new, r.decided_new_reason, r.application_id, r.imported_at,
                       a.application_no, pr.route AS "appRoute", a.session AS "appSession", CASE WHEN :data THEN r.data::text END AS data
                  FROM admissions.prelim_migration_row r LEFT JOIN admissions.application a ON a.id = r.application_id
                  LEFT JOIN admissions.prelim_review pr ON pr.application_id = r.application_id
                 WHERE r.batch_id = :b AND (""" + where + ")" + LIKE + """
                 ORDER BY r.row_no LIMIT :lim OFFSET :off
                """).param("b", batch).param("st", st).param("like", like, Types.VARCHAR).param("lim", limit).param("off", offset).param("data", withData)
                .query().listOfRows();
        List<Map<String, Object>> out = new ArrayList<>(rows.size());
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.put("problems", parse(r.get("problems")));
            if (withData) m.put("data", parse(r.get("data")));
            else m.remove("data");
            out.add(m);
        }
        return out;
    }

    /** the uploader's word on a row held as a possible same person: a new applicant all the same, with the reason */
    @PostMapping("/rows/{rowId}/new")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> decideNew(@PathVariable UUID rowId, @Valid @RequestBody ReasonIn body) {
        requireMigrator();
        UUID batch = jdbc.sql("SELECT batch_id FROM admissions.prelim_migration_row WHERE id = :r").param("r", rowId).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("preliminary migration row", rowId));
        batchRoute(batch);
        return parseMap(jdbc.sql("SELECT admissions.prelim_migration_row_new(:r, :why)::text").param("r", rowId).param("why", body.reason().trim())
                .query(String.class).single());
    }

    /* ── the application fees paid on the old portal: the reconciliation, the list, the Bursary's decision ── */

    @GetMapping("/fees/figures")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> feeFigures(@RequestParam(required = false) String route) {
        requireReader();
        return parseMap(jdbc.sql("SELECT admissions.prelim_legacy_fee_figures(:r)::text").param("r", readRoute(route), Types.VARCHAR)
                .query(String.class).single());
    }

    @GetMapping("/fees")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> fees(@RequestParam(required = false) String route, @RequestParam(required = false) String state,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        requireReader();
        String r = readRoute(route);
        String st = state == null || state.isBlank() ? null : state.trim().toUpperCase();
        if (st != null && !FEE_STATES.contains(st)) {
            throw new DomainRuleViolation("PRELIMMIG_FEE_FILTER", "A fee paid on the old portal is held for review, verified or rejected.",
                    new DomainRuleViolation.Remedy("Choose REQUIRES_REVIEW, VERIFIED or REJECTED.", "You"));
        }
        int sz = sizeOf(size, 500);
        int pg = Math.max(page, 0);
        Map<String, Object> out = paged(jdbc.sql("SELECT admissions.prelim_legacy_fees(:r, :st, :n, :o)::text")
                .param("r", r, Types.VARCHAR).param("st", st, Types.VARCHAR).param("n", sz).param("o", pg * sz).query(String.class).single(), pg, sz);
        // the officer who uploaded a fee does not verify it (the database refuses PRELIMMIG_SAME_OFFICER): the screen says so on that fee
        // instead of offering the act
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> rows = (List<Map<String, Object>>) out.get("rows");
        String me = actor() == null ? "" : actor().toString();
        boolean decider = FEE_DECIDER_OFFICES.contains(office());
        for (Map<String, Object> m : rows) {
            boolean own = me.equals(String.valueOf(m.get("uploadedById")));
            m.put("uploadedByYou", own);
            m.put("mayDecide", decider && !own && "REQUIRES_REVIEW".equals(String.valueOf(m.getOrDefault("state", ""))));
        }
        out.put("mayDecide", decider);
        return out;
    }

    public record DecideIn(boolean verify, @NotBlank @Size(max = 1000) String note, @Size(max = 100) String reference) {
    }

    @PostMapping("/fees/{id}/decide")
    @PreAuthorize(FEE_DECIDERS)
    @Transactional
    Map<String, Object> decideFee(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        AuditContextHolder.required();
        String app = jdbc.sql("SELECT application_id::text FROM admissions.prelim_legacy_fee WHERE id = :f").param("f", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("old-portal application fee", id));
        applicationRoute(UUID.fromString(app));
        return parseMap(jdbc.sql("SELECT admissions.prelim_legacy_fee_decide(:f, :v, :n, :ref)::text")
                .param("f", id).param("v", body.verify()).param("n", body.note().trim())
                .param("ref", body.reference() == null || body.reference().isBlank() ? null : body.reference().trim(), Types.VARCHAR)
                .query(String.class).single());
    }

    /* ── finding an applicant: by this portal's number, the old portal's, the email, the phone or the name ── */

    @GetMapping("/find")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> find(@RequestParam String q) {
        requireFinder();   // an agent with either capability finds an applicant: the upload's and the correction's own search
        if (q == null || q.trim().length() < 3) return List.of();
        // the office's own routes go to the database, which applies them before it cuts the page at 50: a programme office never loses
        // its own applicants behind the other programme's (null: both routes)
        List<String> own = ownRoutes();
        String routes = own.containsAll(ROUTES) ? null : String.join(",", own);
        return jdbc.sql("SELECT * FROM admissions.prelim_legacy_find(:q, string_to_array(:routes, ','))")
                .param("q", q.trim()).param("routes", routes, Types.VARCHAR).query().listOfRows();
    }

    /* ── the programme correction: the record, the check, the change, and the history ── */

    /** an applicant's record as the correction reads it */
    @GetMapping("/applicants/{appId}")
    @PreAuthorize(CORRECTION_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> applicant(@PathVariable UUID appId) {
        requireCorrectionReader();
        applicationRoute(appId);
        return record(appId);
    }

    private Map<String, Object> record(UUID app) {
        Map<String, Object> a = jdbc.sql("""
                SELECT a.id, a.application_no, a.session, a.created_at, a.fee_confirmed_at, c.surname, c.other_names, c.sex, c.programme, c.offer_state,
                       r.route, pp.name AS route_name, r.state, r.submitted_at, r.published_at, r.decided_at, r.target_id, r.target_programme,
                       coalesce(g.name, t.requested_name) AS target_name, t.group_name AS target_group, sp.code AS specialisation_code, sp.name AS specialisation_name,
                       (SELECT x.value FROM admissions.screening_answer x WHERE x.application_id = a.id AND x.field = 'date_of_birth') AS date_of_birth,
                       (SELECT count(*) FROM admissions.application_document d WHERE d.application_id = a.id AND d.superseded_at IS NULL) AS documents,
                       (SELECT f.application_fee + f.portal_charge FROM admissions.route_fee_rule(a.session, r.route) f) AS route_fee,
                       EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee lf WHERE lf.application_id = a.id AND lf.state = 'REQUIRES_REVIEW') AS fee_held
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  JOIN admissions.prelim_review r ON r.application_id = a.id JOIN admissions.prelim_programme pp ON pp.route = r.route
                  LEFT JOIN admissions.prelim_target t ON t.id = r.target_id LEFT JOIN ref.programme g ON g.code = t.programme_code
                  LEFT JOIN admissions.prelim_specialisation sp ON sp.id = r.specialisation_id
                 WHERE a.id = :a
                """).param("a", app).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", a.get("id"));
        out.put("applicationNo", a.get("application_no"));
        Map<String, Object> legacy = prelim.legacy(app, true);
        out.put("legacyNo", legacy == null ? null : legacy.get("number"));
        out.put("name", a.get("surname") + ", " + a.get("other_names"));
        out.put("surname", a.get("surname"));
        out.put("otherNames", a.get("other_names"));
        out.put("sex", a.get("sex"));
        out.put("dateOfBirth", a.get("date_of_birth"));
        out.put("route", a.get("route"));
        out.put("routeName", a.get("route_name"));
        out.put("programme", a.get("programme"));
        out.put("session", a.get("session"));
        out.put("state", a.get("state"));
        out.put("offerState", a.get("offer_state"));
        out.put("submittedAt", a.get("submitted_at"));
        out.put("decidedAt", a.get("decided_at"));
        out.put("publishedAt", a.get("published_at"));
        out.put("appliedAt", a.get("created_at"));
        Map<String, Object> target = new LinkedHashMap<>();
        target.put("id", a.get("target_id"));
        target.put("code", a.get("target_programme"));
        target.put("name", a.get("target_name"));
        target.put("group", a.get("target_group"));
        target.put("specialisationCode", a.get("specialisation_code"));
        target.put("specialisationName", a.get("specialisation_name"));
        out.put("target", a.get("target_id") == null ? null : target);
        Map<String, Object> fee = new LinkedHashMap<>();
        boolean paid = a.get("fee_confirmed_at") != null;
        boolean held = Boolean.TRUE.equals(a.get("fee_held"));
        boolean free = a.get("route_fee") instanceof java.math.BigDecimal f && f.signum() == 0;
        fee.put("status", paid ? "PAID" : held ? "HELD" : free ? "NOT_REQUIRED" : "UNPAID");
        fee.put("confirmedAt", a.get("fee_confirmed_at"));
        fee.put("routeFee", a.get("route_fee"));
        fee.put("references", jdbc.sql("""
                SELECT f.reference, f.amount, f.confirmed_at AS "confirmedAt", f.receipt_no AS "receiptNo", f.channel
                  FROM admissions.fee_reference f WHERE f.application_id = :a AND f.kind = 'APPLICATION' AND f.confirmed_at IS NOT NULL ORDER BY f.confirmed_at
                """).param("a", app).query().listOfRows());
        fee.put("oldPortal", prelim.legacyFees(app));
        out.put("fee", fee);
        out.put("documents", a.get("documents"));
        out.put("legacy", legacy);
        out.put("routeChanges", prelim.routeChanges(app));
        String other = ROUTES.stream().filter(x -> !x.equals(a.get("route"))).findFirst().orElse(null);
        out.put("otherRoute", other == null || !ROUTES.contains(String.valueOf(a.get("route"))) ? null : Map.of("route", other,
                "name", jdbc.sql("SELECT name FROM admissions.prelim_programme WHERE route = :r").param("r", other).query(String.class).single()));
        out.put("may", mayChange() && ROUTES.contains(String.valueOf(a.get("route"))));
        return out;
    }

    /** what the change would do, and whether it may be made: the database's own check (it writes nothing) */
    @GetMapping("/applicants/{appId}/change-check")
    @PreAuthorize(CORRECTORS)
    @Transactional(readOnly = true)
    Map<String, Object> changeCheck(@PathVariable UUID appId, @RequestParam(required = false) String to) {
        requireCorrector();
        String from = applicationRoute(appId);
        String target = to == null || to.isBlank() ? ROUTES.stream().filter(x -> !x.equals(from)).findFirst().orElse(from) : routeOf(to);
        return parseMap(jdbc.sql("SELECT admissions.prelim_change_route_check(:a, :to)::text").param("a", appId).param("to", target)
                .query(String.class).single());
    }

    public record ChangeIn(@NotBlank @Size(max = 40) String to, @NotBlank @Size(max = 40) String from, @NotBlank @Size(max = 2000) String reason) {
    }

    /**
     * The applicant's programme changed to the other preliminary programme: one record, the same number, the fee and the history kept.
     * A refusal of the database's rules (PRELIM_CHANGE_*) is written down in a transaction of its own — the change itself is undone —
     * and answered as the portal answers every refusal (422 and its code); a refusal of the office is a 403.
     */
    @PostMapping("/applicants/{appId}/change-programme")
    @PreAuthorize(CORRECTORS)
    Map<String, Object> changeProgramme(@PathVariable UUID appId, @Valid @RequestBody ChangeIn body) {
        AuditContextHolder.required();
        readTx.execute(st -> {
            requireCorrector();
            return applicationRoute(appId);
        });
        // the programme asked for as given (by code or slug): the database refuses anything but the other preliminary route
        // (PRELIM_CHANGE_ROUTE), and the refusal is written down like every other
        String to = PrelimApplicantService.SLUGS.getOrDefault(body.to().trim().toLowerCase(), body.to().trim().toUpperCase());
        String from = PrelimApplicantService.SLUGS.getOrDefault(body.from().trim().toLowerCase(), body.from().trim().toUpperCase());
        String reason = body.reason().trim();
        String result;
        try {
            result = tx.execute(st -> jdbc.sql("SELECT admissions.prelim_change_route(:a, :to, :from, :why)::text")
                    .param("a", appId).param("to", to).param("from", from).param("why", reason).query(String.class).single());
        } catch (DataAccessException refused) {
            String[] coded = ruleRefusal(refused);
            if (coded != null && coded[0].startsWith("PRELIM_CHANGE_")) {
                try {
                    tx.execute(st -> jdbc.sql("SELECT admissions.prelim_route_change_refused(:a, :to, :why, :c, :m)")
                            .param("a", appId).param("to", to).param("why", reason).param("c", coded[0]).param("m", coded[1])
                            .query().listOfRows());
                } catch (RuntimeException notWritten) {
                    LOG.warn("the refused programme change of {} was not written down: {}", appId, notWritten.getMessage());
                }
            }
            throw refused;
        }
        Map<String, Object> out = new LinkedHashMap<>(parseMap(result));
        out.put("record", readTx.execute(st -> record(appId)));
        return out;
    }

    private static final org.slf4j.Logger LOG = org.slf4j.LoggerFactory.getLogger(PrelimMigrationController.class);

    /** the code and words of a rule the database refused on (SQLSTATE 23514, "CODE: words"), or null for any other failure */
    private static String[] ruleRefusal(Throwable e) {
        for (Throwable c = e; c != null; c = c.getCause() == c ? null : c.getCause()) {
            if (c instanceof org.postgresql.util.PSQLException pg) {
                if (!"23514".equals(pg.getSQLState())) return null;
                String message = pg.getServerErrorMessage() == null ? pg.getMessage() : pg.getServerErrorMessage().getMessage();
                java.util.regex.Matcher m = message == null ? null
                        : java.util.regex.Pattern.compile("^([A-Z][A-Z0-9_]{3,60}): (.+)$", java.util.regex.Pattern.DOTALL).matcher(message);
                return m != null && m.matches() ? new String[] {m.group(1), m.group(2)} : null;
            }
        }
        return null;
    }

    /** the history of programme corrections: a programme's (to it or from it), or every one (a programme's office: its own) */
    @GetMapping("/corrections")
    @PreAuthorize(CORRECTION_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> corrections(@RequestParam(required = false) String route, @RequestParam(defaultValue = "0") int page,
                                    @RequestParam(defaultValue = "50") int size) {
        requireCorrectionReader();
        String r = readRoute(route);
        int sz = sizeOf(size, 500);
        int pg = Math.max(page, 0);
        return paged(jdbc.sql("SELECT admissions.prelim_route_changes(:r, :n, :o)::text")
                .param("r", r, Types.VARCHAR).param("n", sz).param("o", pg * sz).query(String.class).single(), pg, sz);
    }
}
