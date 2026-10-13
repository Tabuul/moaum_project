package ng.edu.moaum.portal.clearance;

import java.sql.Types;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The offices' side of fresh and final clearance (V415): each office's desk on its own stage, a student's clearance in
 * full, the office's word (against the record — the database refuses a clearance the record does not support), the
 * documents, the Registry's starting, overview and workflow settings, and a support agent's read-only view. Every act
 * is held here, on the server, to the office's units and its faculty or department; hiding a button is never the guard.
 */
@RestController
@RequestMapping("/api/v1/clearance")
class ClearanceDeskController {

    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dean',"
            + "'OFFICE_hod','OFFICE_facultyofficer','OFFICE_bursar','OFFICE_library','OFFICE_services','OFFICE_housing','OFFICE_alumni',"
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    static final String SIGNERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dean','OFFICE_hod',"
            + "'OFFICE_facultyofficer','OFFICE_bursar','OFFICE_library','OFFICE_services','OFFICE_housing','OFFICE_alumni')";
    static final String STARTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";
    static final String MANAGERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super','OFFICE_admin','OFFICE_vc','OFFICE_dvc')";
    static final String CONFIGURERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    /** the senior officers who may give a word past the engine's checks, with a reason */
    static final Set<String> OVERRIDERS = Set.of("registrar", "dregistrar");
    private static final Set<String> STATES = Set.of("CLEARED", "UNDER_REVIEW", "NOT_CLEARED", "REQUIRES_ACTION", "REJECTED", "NOT_APPLICABLE");
    private static final Set<String> OVERALLS = Set.of("IN_PROGRESS", "PARTIALLY_CLEARED", "PENDING_ACTION", "NOT_CLEARED", "REJECTED", "CLEARED", "COMPLETED");
    private static final Set<String> STAGE_STATES = Set.of("WAITING", "PENDING", "UNDER_REVIEW", "REQUIRES_ACTION", "NOT_CLEARED", "REJECTED", "CLEARED", "NOT_APPLICABLE");
    static final int MAX_DOC = 5 * 1024 * 1024;
    /** the rule's code in a database refusal — CLR_OUTSTANDING, never the driver's leading "ERROR" — and its words */
    private static final Pattern CODED = Pattern.compile("([A-Z][A-Z0-9]*_[A-Z0-9_]{2,60}): ([^\\n]+)");

    private final ClearanceDesk desk;
    private final OfficeScope scope;
    private final JdbcClient jdbc;
    private final FileObjects files;
    private final TransactionTemplate tx;
    private final tools.jackson.databind.ObjectMapper json;

    ClearanceDeskController(ClearanceDesk desk, OfficeScope scope, JdbcClient jdbc, FileObjects files, PlatformTransactionManager transactions,
                            tools.jackson.databind.ObjectMapper json) {
        this.desk = desk;
        this.scope = scope;
        this.jdbc = jdbc;
        this.files = files;
        this.tx = new TransactionTemplate(transactions);
        this.json = json;
    }

    private static String office() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse(null);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static String str(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    /** a process the acting office may read: within its faculty or department, and of a workflow one of its units takes part in */
    private Map<String, Object> readable(UUID id) {
        Map<String, Object> p = desk.process(id).orElseThrow(() -> new NotFound("clearance", id));
        OfficeScope.Bound b = scope.bound(null, null, null);
        if (b.dept() != null && !b.dept().equalsIgnoreCase(String.valueOf(p.get("dept_code")))) throw new NotFound("clearance", id);
        if (b.fac() != null && !b.fac().equalsIgnoreCase(String.valueOf(p.get("faculty_code")))) throw new NotFound("clearance", id);
        if (b.prog() != null && !b.prog().equalsIgnoreCase(String.valueOf(p.get("programme_code")))) throw new NotFound("clearance", id);
        String office = office();
        List<String> mine = desk.unitsOf(office);
        if (!mine.isEmpty() && !ClearanceDesk.ANY_UNIT.contains(office)) {
            boolean takesPart = jdbc.sql("SELECT EXISTS (SELECT 1 FROM clearance.workflow_stage WHERE workflow = :w AND active AND unit IN (:u))")
                    .param("w", p.get("workflow")).param("u", mine).query(Boolean.class).single();
            if (!takesPart) throw new NotFound("clearance", id);
        }
        return p;
    }

    /** the units the office may give its word on, refused for any other */
    private String signable(String unit) {
        String u = unit == null ? "" : unit.trim().toUpperCase();
        if (!desk.unitsOf(office()).contains(u)) {
            throw new AccessDeniedException("the " + u.toLowerCase() + " stage is not your office's to decide");
        }
        return u;
    }

    /* ── reading ── */

    @GetMapping("/workflows")
    @PreAuthorize(READERS)
    Map<String, Object> workflows() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("workflows", desk.workflows());
        out.put("units", desk.units());
        out.put("myUnits", desk.unitsOf(office()));
        out.put("canConfigure", Set.of("academic", "registrar", "dregistrar", "super").contains(office()));
        out.put("canStart", Set.of("academic", "registrar", "dregistrar").contains(office()));
        out.put("canOverride", OVERRIDERS.contains(office()));
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session WHERE state IS DISTINCT FROM 'CANCELLED' ORDER BY starts_on DESC").query(String.class).list());
        out.put("currentSession", jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null));
        return out;
    }

    /** V416: what waits on the acting office — its own stages, within its faculty or department — for its dashboard */
    @GetMapping("/awaiting")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> awaiting() {
        List<String> mine = desk.unitsOf(office());
        if (mine.isEmpty()) return List.of();
        OfficeScope.Bound b = scope.bound(null, null, null);
        return desk.awaiting(mine, b.fac(), b.dept());
    }

    /** the desk: a workflow's processes in a session, held to the office's bound, paged; export=true for a report (at most 20,000) */
    @GetMapping("/desk")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> desk(@RequestParam(defaultValue = "FRESH") String workflow, @RequestParam String session,
                             @RequestParam(required = false) String unit, @RequestParam(required = false) String status,
                             @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                             @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                             @RequestParam(required = false) String sex, @RequestParam(required = false) String entry,
                             @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page,
                             @RequestParam(defaultValue = "50") int size, @RequestParam(defaultValue = "false") boolean export,
                             @RequestParam(defaultValue = "false") boolean docs) {
        String office = office();
        List<String> mine = desk.unitsOf(office);
        String u = blank(unit) == null ? null : unit.trim().toUpperCase();
        if (u == null && !mine.isEmpty() && !ClearanceDesk.ANY_UNIT.contains(office)) {
            // an office's desk opens on its own stage: the first of its units the workflow has
            u = jdbc.sql("SELECT unit FROM clearance.workflow_stage WHERE workflow = :w AND active AND unit IN (:u) ORDER BY ord LIMIT 1")
                    .param("w", workflow.toUpperCase()).param("u", mine).query(String.class).optional().orElse(mine.get(0));
        }
        if (u != null && !mine.isEmpty() && !ClearanceDesk.ANY_UNIT.contains(office) && !mine.contains(u)) {
            throw new AccessDeniedException("the " + u.toLowerCase() + " stage is not your office's");
        }
        String st = blank(status) == null ? null : status.trim().toUpperCase();
        if (st != null && !(u == null ? OVERALLS : STAGE_STATES).contains(st)) {
            throw new DomainRuleViolation("CLR_FILTER", "No such status to filter by.", new DomainRuleViolation.Remedy("Choose a status from the tiles.", "You"));
        }
        OfficeScope.Bound b = scope.bound(fac, dept, prog);
        int sz = export ? Math.min(Math.max(size, 1), 20000) : Math.min(Math.max(size, 1), 200);
        Map<String, Object> out = desk.desk(new ClearanceDesk.Filter(workflow, session, u, st, b.fac(), b.dept(), b.prog(), level, blank(sex), blank(entry),
                blank(q), export ? 0 : Math.max(page, 0), sz, docs));
        out.put("myUnits", mine);
        out.put("scope", Map.of("faculty", b.fac() == null ? "" : b.fac(), "department", b.dept() == null ? "" : b.dept()));
        return out;
    }

    /** a student's clearance in full: stages, every word given, documents and — for the units the office may see — the evidence */
    @GetMapping("/processes/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> process(@PathVariable UUID id) {
        Map<String, Object> p = readable(id);
        String office = office();
        List<String> mine = desk.unitsOf(office);
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> head = new LinkedHashMap<>(p);
        head.remove("verify_code");
        out.put("process", head);
        List<Map<String, Object>> stages = desk.stages(p);
        out.put("stages", stages);
        out.put("history", desk.history(p, true));
        out.put("documents", desk.documents(id));
        Map<String, Object> evidence = new LinkedHashMap<>();
        for (Map<String, Object> s : stages) {
            String unit = String.valueOf(s.get("unit"));
            boolean mayRead = ClearanceDesk.ANY_UNIT.contains(office) || mine.contains(unit) || Set.of("vc", "dvc", "super", "admin").contains(office);
            if ("HEALTH".equals(unit) && !ClearanceDesk.HEALTH_READERS.contains(office)) mayRead = false;   // the clinic's finding stays with the clinic
            if (mayRead && Boolean.TRUE.equals(s.get("applies"))) {
                try {
                    evidence.put(unit, json.readValue(String.valueOf(desk.evidence(id, unit)), Map.class));
                } catch (RuntimeException e) {
                    evidence.put(unit, Map.of());
                }
            }
        }
        out.put("evidence", evidence);
        out.put("myUnits", mine);
        out.put("canOverride", OVERRIDERS.contains(office));
        out.put("canCancel", Set.of("academic", "registrar", "dregistrar").contains(office) && p.get("cancelled_at") == null);
        return out;
    }

    /* ── the office's word ── */

    public record Decision(@NotBlank String state, @Size(max = 500) String item, @Size(max = 500) String note,
                           @Size(max = 1000) String internalNote, Boolean override) {

        boolean overriding() {
            return Boolean.TRUE.equals(override);
        }
    }

    @PostMapping("/processes/{id}/stages/{unit}")
    @PreAuthorize(SIGNERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @PathVariable String unit, @Valid @RequestBody Decision body) {
        readable(id);
        String u = signable(unit);
        String state = body.state().trim().toUpperCase();
        if (!STATES.contains(state)) {
            throw new DomainRuleViolation("CLR_STATE", "That is not a word a stage takes.", new DomainRuleViolation.Remedy("Clear, hold as not cleared, ask for action or reject.", "You"));
        }
        if (body.overriding() && !OVERRIDERS.contains(office())) {
            throw new AccessDeniedException("an override is the Registrar's or the Deputy Registrar's");
        }
        AuditContext ctx = AuditContextHolder.required();
        String overall = jdbc.sql("SELECT clearance.decide(:p, :u, :s, :i, :n, :in, :o, :a, :off)")
                .param("p", id).param("u", u).param("s", state).param("i", body.item(), Types.VARCHAR).param("n", body.note(), Types.VARCHAR)
                .param("in", body.internalNote(), Types.VARCHAR).param("o", body.overriding()).param("a", ctx.actorId()).param("off", ctx.actorOffice())
                .query(String.class).single();
        return Map.of("process", id, "unit", u, "state", state, "overall", overall);
    }

    public record BulkClear(@NotNull @Size(min = 1, max = 500) List<UUID> processes, @NotBlank String unit, @Size(max = 500) String note) {
    }

    /** many students cleared at once at the office's stage: each on its own, against its own record; the refusals named */
    @PostMapping("/desk/clear")
    @PreAuthorize(SIGNERS)
    Map<String, Object> clearMany(@Valid @RequestBody BulkClear body) {
        String u = signable(body.unit());
        AuditContext ctx = AuditContextHolder.required();
        int cleared = 0;
        List<Map<String, Object>> refused = new ArrayList<>();
        for (UUID id : body.processes()) {
            try {
                tx.executeWithoutResult(s -> {
                    readable(id);
                    jdbc.sql("SELECT clearance.decide(:p, :u, 'CLEARED', NULL, :n, NULL, false, :a, :off)")
                            .param("p", id).param("u", u).param("n", body.note(), Types.VARCHAR).param("a", ctx.actorId()).param("off", ctx.actorOffice())
                            .query(String.class).single();
                });
                cleared++;
            } catch (DataAccessException | NotFound e) {
                String m = String.valueOf(e instanceof DataAccessException d && d.getMostSpecificCause() != null ? d.getMostSpecificCause().getMessage() : e.getMessage());
                Matcher c = CODED.matcher(m);
                boolean coded = c.find();
                refused.add(Map.of("process", id, "code", coded ? c.group(1) : "CLR_REFUSED", "why", coded ? c.group(2).trim() : "Refused"));
            }
        }
        return Map.of("cleared", cleared, "refused", refused);
    }

    public record Cancel(@NotBlank @Size(max = 500) String reason) {
    }

    @PostMapping("/processes/{id}/cancel")
    @PreAuthorize(STARTERS)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody Cancel body) {
        readable(id);
        jdbc.sql("SELECT clearance.cancel(:p, :r, :a)").param("p", id).param("r", body.reason()).param("a", AuditContextHolder.required().actorId())
                .query().singleRow();
        return Map.of("process", id, "cancelled", true);
    }

    /* ── starting ── */

    public record Start(@NotBlank String workflow, @NotBlank String session, @NotBlank String student, String basis, @Size(max = 500) String reason) {
    }

    @PostMapping("/start")
    @PreAuthorize(STARTERS)
    @Transactional
    Map<String, Object> start(@Valid @RequestBody Start body) {
        UUID student = desk.studentBy(body.student()).orElseThrow(() -> new NotFound("student", body.student()));
        String basis = blank(body.basis()) == null ? "MANUAL" : body.basis().trim().toUpperCase();
        if (!Set.of("MANUAL", "OVERRIDE").contains(basis)) basis = "MANUAL";
        if ("OVERRIDE".equals(basis) && !OVERRIDERS.contains(office())) {
            throw new AccessDeniedException("starting past the eligibility check is the Registrar's or the Deputy Registrar's");
        }
        AuditContext ctx = AuditContextHolder.required();
        UUID id = jdbc.sql("SELECT clearance.start(:w, :s, :sess, :b, :r, :a, :o)")
                .param("w", body.workflow().toUpperCase()).param("s", student).param("sess", body.session()).param("b", basis)
                .param("r", body.reason(), Types.VARCHAR).param("a", ctx.actorId()).param("o", ctx.actorOffice()).query(UUID.class).single();
        String ref = jdbc.sql("SELECT reference FROM clearance.process WHERE id = :id").param("id", id).query(String.class).single();
        return Map.of("process", id, "reference", ref);
    }

    public record StartEligible(@NotBlank String workflow, @NotBlank String session, Integer limit) {
    }

    /** every eligible student of the session with none under way, up to the limit at a time; each told once */
    @PostMapping("/start-eligible")
    @PreAuthorize(STARTERS)
    @Transactional
    Map<String, Object> startEligible(@Valid @RequestBody StartEligible body) {
        AuditContext ctx = AuditContextHolder.required();
        return jdbc.sql("SELECT started, remaining FROM clearance.start_eligible(:w, :s, :a, :o, :l)")
                .param("w", body.workflow().toUpperCase()).param("s", body.session()).param("a", ctx.actorId()).param("o", ctx.actorOffice())
                .param("l", body.limit() == null ? 500 : Math.min(Math.max(body.limit(), 1), 2000)).query().singleRow();
    }

    public record StartGraduands(@NotBlank String session, String fac, String dept, String prog) {
    }

    /**
     * V416: final clearance started for every graduand of a session (on records.graduand, within the office's bound and
     * the faculty, department or programme asked for) who has none under way — each on its own, against its own record,
     * told once; a graduand the engine refuses is named with the reason, the others are started.
     */
    @PostMapping("/start-graduands")
    @PreAuthorize(STARTERS)
    Map<String, Object> startGraduands(@Valid @RequestBody StartGraduands body) {
        OfficeScope.Bound b = scope.bound(body.fac(), body.dept(), body.prog());
        AuditContext ctx = AuditContextHolder.required();
        List<Map<String, Object>> todo = jdbc.sql("""
                SELECT g.student_id, coalesce(s.matric_no, s.admission_no) AS number, s.surname || ', ' || s.other_names AS name
                  FROM records.graduand g
                  JOIN people.student s ON s.id = g.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE g.session = :s
                   AND (:fac::text IS NULL OR p.faculty_code = :fac) AND (:dept::text IS NULL OR p.dept_code = :dept) AND (:prog::text IS NULL OR p.code = :prog)
                   AND NOT EXISTS (SELECT 1 FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = g.student_id AND q.cancelled_at IS NULL)
                 ORDER BY s.surname, s.other_names
                 LIMIT 3000
                """).param("s", body.session()).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR)
                .param("prog", b.prog(), Types.VARCHAR).query().listOfRows();
        int started = 0;
        List<Map<String, Object>> refused = new ArrayList<>();
        for (Map<String, Object> g : todo) {
            try {
                tx.executeWithoutResult(st -> jdbc.sql("SELECT clearance.start('FINAL', :s, :sess, 'BULK', NULL, :a, :o)")
                        .param("s", g.get("student_id")).param("sess", body.session()).param("a", ctx.actorId()).param("o", ctx.actorOffice())
                        .query(UUID.class).single());
                started++;
            } catch (DataAccessException e) {
                String m = String.valueOf(e.getMostSpecificCause() == null ? e.getMessage() : e.getMostSpecificCause().getMessage());
                Matcher c = CODED.matcher(m);
                boolean coded = c.find();
                refused.add(Map.of("student", g.get("student_id"), "number", String.valueOf(g.get("number")), "name", String.valueOf(g.get("name")),
                        "code", coded ? c.group(1) : "CLR_REFUSED", "why", coded ? c.group(2).trim() : "Refused"));
            }
        }
        return Map.of("started", started, "refused", refused);
    }

    @GetMapping("/overview")
    @PreAuthorize(MANAGERS)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@RequestParam(defaultValue = "FRESH") String workflow, @RequestParam String session) {
        Map<String, Object> o = desk.overview(workflow, session);
        try {
            o.put("overall", json.readValue(String.valueOf(o.get("overall")), Map.class));
            Map<String, Object> e = new LinkedHashMap<>(castMap(o.get("eligible")));
            e.put("reasons", json.readValue(String.valueOf(e.get("reasons")), List.class));
            o.put("eligible", e);
        } catch (RuntimeException ignored) {
            // the figures are still there as text
        }
        return o;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castMap(Object o) {
        return o instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
    }

    /* ── the workflow settings ── */

    public record WorkflowIn(@Size(max = 80) String label, Boolean active, Integer reminderDays, Boolean certificate,
                             @Size(max = 500) String description, @NotNull @Size(min = 1, max = 12) List<Map<String, Object>> stages) {
    }

    @PutMapping("/workflows/{code}")
    @PreAuthorize(CONFIGURERS)
    @Transactional
    Map<String, Object> setWorkflow(@PathVariable String code, @Valid @RequestBody WorkflowIn body) {
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("SELECT clearance.set_workflow(:c, :l, :a, :r, :cert, :d, :by)").param("c", code).param("l", body.label(), Types.VARCHAR)
                .param("a", body.active(), Types.BOOLEAN).param("r", body.reminderDays(), Types.INTEGER).param("cert", body.certificate(), Types.BOOLEAN)
                .param("d", body.description(), Types.VARCHAR).param("by", ctx.actorId()).query().singleRow();
        int n = jdbc.sql("SELECT clearance.set_stages(:c, :s::jsonb, :by)").param("c", code).param("s", json.writeValueAsString(body.stages()))
                .param("by", ctx.actorId()).query(Integer.class).single();
        return Map.of("workflow", code.toUpperCase(), "stages", n);
    }

    /* ── documents ── */

    public record Upload(@NotBlank String unit, @NotBlank @Size(max = 120) String label, @NotBlank @Size(max = 200) String fileName,
                         @NotBlank String contentBase64) {
    }

    /** the type a file's first bytes say it is — PDF, JPEG or PNG — never what the browser claims */
    static String typeOf(byte[] b) {
        if (b.length > 4 && b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F') return "application/pdf";
        if (b.length > 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8) return "image/jpeg";
        if (b.length > 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') return "image/png";
        return null;
    }

    static byte[] decode(String base64) {
        String b = base64.contains(",") ? base64.substring(base64.indexOf(',') + 1) : base64;
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(b.trim());
        } catch (IllegalArgumentException e) {
            throw new DomainRuleViolation("CLR_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > MAX_DOC) {
            throw new DomainRuleViolation("CLR_FILE_SIZE", "A clearance document is at most 5 MB.", new DomainRuleViolation.Remedy("Scan it at a lower resolution, or as a PDF.", "You"));
        }
        if (typeOf(bytes) == null) {
            throw new DomainRuleViolation("CLR_FILE_TYPE", "A clearance document is a PDF, JPEG or PNG.", new DomainRuleViolation.Remedy("Save it as one of those and upload it again.", "You"));
        }
        return bytes;
    }

    /** the document stored through the portal's file store (the bytes in the database when no store is configured) */
    static UUID store(JdbcClient jdbc, FileObjects files, UUID process, String unit, String label, String fileName, byte[] bytes, UUID actor, String office) {
        String type = typeOf(bytes);
        UUID object = files.store("clearance.document", process, fileName, type, bytes);
        UUID id = jdbc.sql("SELECT clearance.add_document(:p, :u, :l, :f, :t, :n, :o, :a, :off)")
                .param("p", process).param("u", unit).param("l", label).param("f", fileName).param("t", type).param("n", bytes.length)
                .param("o", object, Types.OTHER).param("a", actor).param("off", office).query(UUID.class).single();
        if (object == null) {
            jdbc.sql("INSERT INTO clearance.document_blob (document_id, content) VALUES (:id, :c)").param("id", id).param("c", bytes).update();
        }
        return id;
    }

    /** a document of the process given, as its bytes — never one of another process, whatever the address says */
    static ResponseEntity<byte[]> file(JdbcClient jdbc, FileObjects files, UUID document, UUID process) {
        Map<String, Object> d = jdbc.sql("""
                SELECT d.file_name, d.content_type, d.object_id, b.content FROM clearance.document d LEFT JOIN clearance.document_blob b ON b.document_id = d.id
                 WHERE d.id = :id AND d.process_id = :p
                """).param("id", document).param("p", process).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("document", document));
        byte[] bytes = files.resolve((byte[]) d.get("content"), (UUID) d.get("object_id"));
        if (bytes == null) throw new NotFound("document", document);
        String name = String.valueOf(d.get("file_name")).replaceAll("[^A-Za-z0-9._ -]", "_");
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(d.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + name + "\"").header("Cache-Control", "no-store").body(bytes);
    }

    @PostMapping("/processes/{id}/documents")
    @PreAuthorize(SIGNERS)
    @Transactional
    Map<String, Object> upload(@PathVariable UUID id, @Valid @RequestBody Upload body) {
        readable(id);
        String u = signable(body.unit());
        AuditContext ctx = AuditContextHolder.required();
        UUID doc = store(jdbc, files, id, u, body.label().trim(), body.fileName().trim(), decode(body.contentBase64()), ctx.actorId(), ctx.actorOffice());
        return Map.of("document", doc);
    }

    @GetMapping("/documents/{id}/file")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> documentFile(@PathVariable UUID id) {
        UUID process = jdbc.sql("SELECT process_id FROM clearance.document WHERE id = :id").param("id", id).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("document", id));
        Map<String, Object> p = readable(process);
        String unit = jdbc.sql("SELECT unit FROM clearance.document WHERE id = :id").param("id", id).query(String.class).single();
        if ("HEALTH".equals(unit) && !ClearanceDesk.HEALTH_READERS.contains(office())) throw new NotFound("document", id);
        return file(jdbc, files, id, (UUID) p.get("id"));
    }

    public record Review(@NotBlank String state, @Size(max = 500) String reason) {
    }

    @PostMapping("/documents/{id}/review")
    @PreAuthorize(SIGNERS)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @Valid @RequestBody Review body) {
        Map<String, Object> d = jdbc.sql("SELECT process_id, unit FROM clearance.document WHERE id = :id").param("id", id).query().listOfRows().stream()
                .findFirst().orElseThrow(() -> new NotFound("document", id));
        readable((UUID) d.get("process_id"));
        signable(String.valueOf(d.get("unit")));
        jdbc.sql("SELECT clearance.review_document(:d, :s, :r, :a)").param("d", id).param("s", body.state()).param("r", body.reason(), Types.VARCHAR)
                .param("a", AuditContextHolder.required().actorId()).query().singleRow();
        return Map.of("document", id, "state", body.state().toUpperCase());
    }

    /* ── a support agent's view ── */

    /**
     * What an ICT Support agent may see of a student's clearance, to tell them which office is pending and what it asked
     * for: the stages and their words, the documents' states — no internal note, no evidence, no act. The student must be
     * within the agent's posting, with the capability to view students; the Head of the Support Desk sees every student.
     */
    @GetMapping("/support/students/{student}")
    @PreAuthorize("hasAnyAuthority('OFFICE_ictagent','OFFICE_helpdeskhead')")
    @Transactional(readOnly = true)
    Map<String, Object> support(@PathVariable UUID student, Authentication auth) {
        UUID me = UUID.fromString(auth.getName());
        if (!"helpdeskhead".equals(office())) {
            boolean sees = Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.agent_may_see_student(:p, :s)").param("p", me).param("s", student)
                    .query(Boolean.class).optional().orElse(false));
            List<String> caps = jdbc.sql("SELECT unnest(helpdesk.agent_capabilities_for(:p, :s))").param("p", me).param("s", student).query(String.class).list();
            if (!sees || !caps.contains("VIEW_STUDENT")) throw new NotFound("student", student);
        } else if (desk.studentBy(student.toString()).isEmpty()) {
            throw new NotFound("student", student);
        }
        List<Map<String, Object>> out = new ArrayList<>();
        for (UUID id : jdbc.sql("SELECT id FROM clearance.process WHERE student_id = :s ORDER BY started_at DESC").param("s", student).query(UUID.class).list()) {
            Map<String, Object> p = desk.process(id).orElseThrow();
            Map<String, Object> one = new LinkedHashMap<>();
            for (String k : List.of("id", "reference", "workflow", "workflow_label", "session", "started_at", "completed_at", "cancelled_at", "overall")) one.put(k, p.get(k));
            List<Map<String, Object>> stages = new ArrayList<>();
            for (Map<String, Object> s : desk.stages(p)) {
                Map<String, Object> st = new LinkedHashMap<>();
                for (String k : List.of("unit", "label", "required", "applies", "opened", "state", "decided_at", "officer")) st.put(k, s.get(k));
                st.put("item", "HEALTH".equals(s.get("unit")) ? null : s.get("item"));
                stages.add(st);
            }
            one.put("stages", stages);
            one.put("documents", desk.documents(id).stream().map(d -> Map.of("unit", d.get("unit"), "label", d.get("label"), "state", d.get("state"),
                    "superseded", d.get("superseded"))).toList());
            out.add(one);
        }
        return Map.of("student", student, "processes", out);
    }
}
