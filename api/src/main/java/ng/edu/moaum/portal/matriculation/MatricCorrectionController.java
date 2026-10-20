package ng.edu.moaum.portal.matriculation;

import java.sql.Types;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V579: a matriculation number corrected, the old number kept. The student is found by the current or a former number, the
 * name, the JAMB, admission or application number; the number the configuration gives is proposed; the correction is checked,
 * prepared by the Academic Office, the Registry or the Director of ICT, and decided — approved and made at once, or rejected —
 * by another officer (the Director of ICT decides a legacy migration correction only). The rules are the database's
 * (people.prepare_matric_correction and its neighbours); ICT Support reads, to help a student, and changes nothing.
 */
@RestController
@RequestMapping("/api/v1/matriculation/corrections")
class MatricCorrectionController {

    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict',"
            + "'OFFICE_ictagent','OFFICE_super','OFFICE_audit','OFFICE_deputyaudit')";
    static final String PREPARERS = "hasAnyAuthority('OFFICE_academic','OFFICE_records','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    /** the database holds the Director of ICT to legacy migration corrections */
    static final String DECIDERS = PREPARERS;
    static final Set<String> EVIDENCE_TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    static final Set<String> KINDS = Set.of("LEGACY_MIGRATION", "FACULTY_CODE", "PROGRAMME_CODE", "YEAR", "SERIES", "SEQUENCE", "DUPLICATE",
            "DATA_ENTRY", "PROGRAMME_CHANGE", "OTHER");

    public record CheckIn(@NotNull UUID student, @Size(max = 40) String newNo) {
    }

    public record PrepareIn(@NotNull UUID student, @NotBlank @Size(max = 40) String newNo, @NotBlank String kind,
                            @NotBlank @Size(min = 10, max = 2000) String reason, @Size(max = 200) String approvalRef) {
    }

    public record DecideIn(@NotNull Boolean approve, @Size(max = 2000) String note) {
    }

    public record CancelIn(@NotBlank @Size(min = 10, max = 2000) String reason) {
    }

    public record EvidenceIn(@NotBlank @Size(max = 200) String filename, @NotBlank String dataUrl) {
    }

    private final JdbcClient jdbc;
    private final FileObjects files;
    private final tools.jackson.databind.ObjectMapper json;

    MatricCorrectionController(JdbcClient jdbc, FileObjects files, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.files = files;
        this.json = json;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static UUID actor() {
        return AuditContextHolder.current().map(AuditContext::actorId).orElse(null);
    }

    private Object parse(String text) {
        return text == null ? null : json.readValue(text, Object.class);
    }

    /** the students a search finds: by the current or a former number, the name, the JAMB, admission or application number,
     *  the record's id; within a faculty, department, programme or level */
    @GetMapping("/search")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object search(@RequestParam(required = false) String q, @RequestParam(required = false) String faculty, @RequestParam(required = false) String department,
                  @RequestParam(required = false) String programme, @RequestParam(required = false) Integer level) {
        if (blank(q) == null && blank(faculty) == null && blank(department) == null && blank(programme) == null && level == null) {
            return java.util.List.of();
        }
        return parse(jdbc.sql("""
                SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]')::text
                  FROM people.matric_correction_search(:q, :f, :d, :p, :l, 200) x
                """).param("q", blank(q), Types.VARCHAR).param("f", blank(faculty), Types.VARCHAR).param("d", blank(department), Types.VARCHAR)
                .param("p", blank(programme), Types.VARCHAR).param("l", level, Types.INTEGER).query(String.class).single());
    }

    /** the faculties, departments and programmes the search narrows to */
    @GetMapping("/places")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object places() {
        return parse(jdbc.sql("""
                SELECT coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'deptCode', d.code, 'department', d.name, 'facultyCode', f.code,
                                                             'faculty', f.name, 'category', p.category) ORDER BY f.name, d.name, p.name), '[]')::text
                  FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE NOT coalesce(p.archived, false)
                """).query(String.class).single());
    }

    /** one student: the record as the check reads it, the numbers proposed, the numbers through time, the corrections */
    @GetMapping("/students/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable UUID id) {
        String found = jdbc.sql("SELECT (people.matric_correction_check(:s, NULL)->'student')::text").param("s", id).query(String.class).optional().orElse(null);
        if (found == null || "null".equals(found)) {
            throw new NotFound("student", id);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", parse(found));
        out.put("suggestions", parse(jdbc.sql("SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]')::text FROM people.matric_correction_suggestions(:s) x")
                .param("s", id).query(String.class).single()));
        out.put("history", parse(jdbc.sql("SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]')::text FROM people.matric_number_history(:s) x")
                .param("s", id).query(String.class).single()));
        out.put("corrections", parse(jdbc.sql("SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]')::text FROM people.matric_corrections(NULL, NULL, :s, 100) x")
                .param("s", id).query(String.class).single()));
        return out;
    }

    /** what correcting the student's number to this one would do, and what stands in its way */
    @PostMapping("/check")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object check(@Valid @RequestBody CheckIn body) {
        return parse(jdbc.sql("SELECT people.matric_correction_check(:s, :n)::text").param("s", body.student()).param("n", body.newNo(), Types.VARCHAR)
                .query(String.class).single());
    }

    /** a correction prepared: checked, refused on any problem; nothing reaches the student until another officer decides it */
    @PostMapping
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> prepare(@Valid @RequestBody PrepareIn body) {
        if (!KINDS.contains(body.kind())) {
            throw new DomainRuleViolation("MATRIC_CORRECTION_KIND", "Say what was wrong with the number.", new DomainRuleViolation.Remedy("Choose the kind of error.", "You"));
        }
        Map<String, Object> made = asMap(parse(jdbc.sql("SELECT people.prepare_matric_correction(:s, :n, :k, :r, :a)::text")
                .param("s", body.student()).param("n", body.newNo().trim()).param("k", body.kind()).param("r", body.reason().trim())
                .param("a", blank(body.approvalRef()), Types.VARCHAR).query(String.class).single()));
        return detail(UUID.fromString(String.valueOf(made.get("id"))));
    }

    /** the corrections, the latest first: by state, reference, number or name */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object list(@RequestParam(required = false) String state, @RequestParam(required = false) String q) {
        return parse(jdbc.sql("SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]')::text FROM people.matric_corrections(:st, :q, NULL, 1000) x")
                .param("st", blank(state), Types.VARCHAR).param("q", blank(q), Types.VARCHAR).query(String.class).single());
    }

    /** one correction: as recorded, the check as it stands now while it waits, its evidence, and whether the reader may decide it */
    @GetMapping("/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        return detail(id);
    }

    private Map<String, Object> detail(UUID id) {
        String row = jdbc.sql("""
                SELECT to_jsonb(x)::text FROM people.matric_corrections(NULL, NULL, NULL, 5000) x WHERE x.id = :id
                """).param("id", id).query(String.class).optional().orElseThrow(() -> new NotFound("correction", id));
        Map<String, Object> out = new LinkedHashMap<>(asMap(parse(row)));
        if ("PENDING_REVIEW".equals(out.get("state"))) {
            out.put("check", parse(jdbc.sql("""
                    SELECT people.matric_correction_check(c.student_id, c.new_no, c.id)::text FROM people.matric_correction c WHERE c.id = :id
                    """).param("id", id).query(String.class).single()));
        }
        UUID me = actor();
        String office = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        boolean decider = Set.of("academic", "records", "registrar", "dregistrar", "super").contains(office)
                || ("ict".equals(office) && "LEGACY_MIGRATION".equals(out.get("kind")));
        out.put("mayDecide", "PENDING_REVIEW".equals(out.get("state")) && decider && me != null && !me.toString().equals(String.valueOf(out.get("prepared_by"))));
        out.put("evidence", jdbc.sql("""
                SELECT e.id, e.filename, e.content_type, e.size_bytes, e.added_at, people.officer_name(e.added_by) AS added_by
                  FROM people.matric_correction_evidence e WHERE e.correction_id = :c ORDER BY e.added_at
                """).param("c", id).query().listOfRows());
        return out;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object o) {
        return o instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
    }

    /** decided by another officer: rejected with a note, or approved and made at once */
    @PostMapping("/{id}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        Map<String, Object> result = asMap(parse(jdbc.sql("SELECT people.decide_matric_correction(:c, :a, :n)::text").param("c", id)
                .param("a", body.approve()).param("n", blank(body.note()), Types.VARCHAR).query(String.class).single()));
        Map<String, Object> out = new LinkedHashMap<>(detail(id));
        out.put("result", result);
        return out;
    }

    @PostMapping("/{id}/cancel")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody CancelIn body) {
        jdbc.sql("SELECT people.cancel_matric_correction(:c, :r)::text").param("c", id).param("r", body.reason().trim()).query(String.class).single();
        return detail(id);
    }

    /** a file supporting the correction — PDF, JPEG or PNG, up to 5 MB — in the file store where there is one; added while it waits */
    @PostMapping("/{id}/evidence")
    @PreAuthorize(PREPARERS)
    @Transactional
    Map<String, Object> evidence(@PathVariable UUID id, @Valid @RequestBody EvidenceIn body) {
        String state = jdbc.sql("SELECT state FROM people.matric_correction WHERE id = :c").param("c", id).query(String.class).optional()
                .orElseThrow(() -> new NotFound("correction", id));
        if (!"PENDING_REVIEW".equals(state)) {
            throw new DomainRuleViolation("MATRIC_CORRECTION_DECIDED", "Evidence is added while the correction waits for a decision.",
                    new DomainRuleViolation.Remedy("Prepare a new correction if one is needed.", "Registry"));
        }
        String u = body.dataUrl();
        int comma = u.indexOf(',');
        String meta = comma > 0 && u.startsWith("data:") ? u.substring(5, comma) : "";
        String type = meta.contains(";") ? meta.substring(0, meta.indexOf(';')) : meta;
        if (!EVIDENCE_TYPES.contains(type)) {
            throw new DomainRuleViolation("MATRIC_CORRECTION_EVIDENCE_TYPE", "Evidence is a PDF, JPEG or PNG file.", new DomainRuleViolation.Remedy("Scan or save it as one of those.", "You"));
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(u.substring(comma + 1).replaceAll("\\s", ""));
        } catch (IllegalArgumentException bad) {
            throw new DomainRuleViolation("MATRIC_CORRECTION_EVIDENCE_FILE", "The file could not be read.", new DomainRuleViolation.Remedy("Choose the file again.", "You"));
        }
        if (bytes.length == 0 || bytes.length > 5 * 1024 * 1024) {
            throw new DomainRuleViolation("MATRIC_CORRECTION_EVIDENCE_SIZE", "Evidence is up to 5 MB.", new DomainRuleViolation.Remedy("Scan it at a lower resolution.", "You"));
        }
        UUID object = files.store("people.matric_correction_evidence", id, body.filename(), type, bytes);
        jdbc.sql("""
                INSERT INTO people.matric_correction_evidence (correction_id, filename, content_type, size_bytes, content, object_id, added_by)
                VALUES (:c, :f, :t, :n, :b, :o, nullif(current_setting('moaum.actor_id', true), '')::uuid)
                """).param("c", id).param("f", body.filename().trim()).param("t", type).param("n", (long) bytes.length)
                .param("b", object == null ? bytes : null, Types.BINARY).param("o", object, Types.OTHER).update();
        return detail(id);
    }

    @GetMapping("/{id}/evidence/{evidence}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> evidenceFile(@PathVariable UUID id, @PathVariable UUID evidence) {
        Map<String, Object> e = jdbc.sql("SELECT filename, content_type, content, object_id FROM people.matric_correction_evidence WHERE id = :e AND correction_id = :c")
                .param("e", evidence).param("c", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("evidence", evidence));
        byte[] bytes = e.get("content") instanceof byte[] b ? b : files.load(UUID.fromString(String.valueOf(e.get("object_id"))));
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(String.valueOf(e.get("content_type"))))
                .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + String.valueOf(e.get("filename")).replaceAll("[^A-Za-z0-9._ -]", "_") + "\"")
                .body(bytes);
    }
}
