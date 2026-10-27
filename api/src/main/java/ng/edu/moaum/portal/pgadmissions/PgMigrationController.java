package ng.edu.moaum.portal.pgadmissions;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Old-portal postgraduate applicants migrated (V675): the template built from the PG application this portal holds, the file
 * staged on the server a chunk at a time, checked (the dry run) and imported in chunks with real progress, the old programmes
 * mapped, the fees paid on the old portal verified by another officer, the documents attached, and the legacy figures. The rules
 * are the database's (admissions.pg_migration_*); this door holds who may do what and carries the rows.
 */
@RestController
@RequestMapping("/api/v1/pg/migration")
class PgMigrationController {

    /* who reads the migration: the School, its Secretary, the Academic Office, the Registry and the Bursary (for the fees);
       V679: and the Director of ICT and the Database Operators */
    private static final String READERS =
            "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar','OFFICE_ict','OFFICE_dbops','OFFICE_super')";
    /* who migrates: the School of Postgraduate Studies, its Secretary and the Academic Office; V679: the Director of ICT and a Database
       Operator over the whole University (27 Oct 2026, "all this should be on ict director and database operators dashboard") —
       never ICT Support */
    private static final String MIGRATORS = "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_academic','OFFICE_ict','OFFICE_dbops','OFFICE_super')";
    /* who verifies a fee paid on the old portal: the Bursary or the PG Secretary (the database refuses the officer who uploaded it) */
    private static final String FEE_DECIDERS = "hasAnyAuthority('OFFICE_pgsecretary','OFFICE_bursar','OFFICE_super')";

    private static final int MAX_DOC = 8 * 1024 * 1024;
    private static final Set<String> STATUSES = Set.of("READY", "WARNING", "DUPLICATE_IN_FILE", "CONFLICT", "REQUIRES_REVIEW", "ERROR");
    private static final Set<String> RESULTS = Set.of("CREATED", "UPDATED", "RECONCILED", "LINKED", "UNCHANGED", "SKIPPED", "FAILED");

    private final JdbcClient jdbc;
    private final FileObjects files;
    private final tools.jackson.databind.ObjectMapper mapper;
    private final OfficeScope scope;

    PgMigrationController(JdbcClient jdbc, FileObjects files, tools.jackson.databind.ObjectMapper mapper, OfficeScope scope) {
        this.jdbc = jdbc;
        this.files = files;
        this.mapper = mapper;
        this.scope = scope;
    }

    /** V679: the migration reaches every PG programme of the University, so a Database Operator works it only on a grant over the
     *  whole University (SCOPE_UNIVERSITY for one held to a faculty, department or programme); asked before every request here */
    @ModelAttribute
    void universityOperatorOnly() {
        scope.requireUniversityOperator("The old-portal PG migration");
    }

    private Object parse(String text) {
        return text == null ? null : mapper.readValue(text, Object.class);
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parseMap(String text) {
        return text == null ? Map.of() : (Map<String, Object>) mapper.readValue(text, Map.class);
    }

    private static String kindOf(String kind) {
        String k = kind == null ? "" : kind.trim().toUpperCase();
        if (!Set.of("APPLICANTS", "ADMITTED").contains(k)) {
            throw new DomainRuleViolation("PGMIG_KIND", "A migration is of PG applicants or of admitted PG applicants.",
                    new DomainRuleViolation.Remedy("Choose one of the two uploads.", "School of Postgraduate Studies"));
        }
        return k;
    }

    /* ── the template: the real fields, and this portal's faculties, departments, programmes, sessions and words ── */

    @GetMapping("/template")
    @PreAuthorize(MIGRATORS)
    @Transactional(readOnly = true)
    Map<String, Object> template(@RequestParam String kind) {
        String k = kindOf(kind);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", k);
        out.put("columns", jdbc.sql("SELECT key, header, section, required, note FROM admissions.pg_migration_columns(:k)").param("k", k).query().listOfRows());
        out.put("faculties", jdbc.sql("""
                SELECT f.code, f.name FROM ref.faculty f
                 WHERE EXISTS (SELECT 1 FROM ref.programme g WHERE g.faculty_code = f.code AND g.category = 'POST GRADUATE' AND NOT g.archived)
                 ORDER BY f.name
                """).query().listOfRows());
        out.put("departments", jdbc.sql("""
                SELECT d.code, d.name, f.name AS faculty FROM ref.department d JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE EXISTS (SELECT 1 FROM ref.programme g WHERE g.dept_code = d.code AND g.category = 'POST GRADUATE' AND NOT g.archived)
                 ORDER BY d.name
                """).query().listOfRows());
        out.put("programmes", jdbc.sql("""
                SELECT g.code, g.name, g.pg_award AS award, d.name AS department, f.name AS faculty
                  FROM ref.programme g JOIN ref.department d ON d.code = g.dept_code JOIN ref.faculty f ON f.code = g.faculty_code
                 WHERE g.category = 'POST GRADUATE' AND NOT g.archived
                 ORDER BY g.name, g.code
                """).query().listOfRows());
        out.put("specialisations", jdbc.sql("""
                SELECT s.programme_code, g.name AS programme, s.code, s.name
                  FROM catalogue.programme_specialisation s JOIN ref.programme g ON g.code = s.programme_code
                 WHERE s.active AND g.category = 'POST GRADUATE' AND NOT g.archived
                 ORDER BY g.name, s.name
                """).query().listOfRows());
        out.put("sessions", jdbc.sql("""
                SELECT name, string_agg(DISTINCT lower(state), ', ') AS state FROM (
                    SELECT name, state FROM admissions.pg_academic_session UNION ALL SELECT name, state FROM policy.academic_session) s
                 GROUP BY name ORDER BY name DESC
                """).query().listOfRows());
        out.put("statuses", jdbc.sql("""
                SELECT initcap(lower(s.word)) AS word, s.state FROM admissions.pg_legacy_status s
                 WHERE (:k = 'ADMITTED') = (s.state IN ('OFFERED', 'ACCEPTED')) ORDER BY s.state, s.word
                """).param("k", k).query().listOfRows());
        return out;
    }

    /* ── a batch: opened, its rows staged, checked, imported, finished or set aside ── */

    public record OpenIn(@NotBlank String kind, @NotBlank @Size(max = 255) String fileName, @Size(max = 64) String sha256,
                         @Min(1) @Max(20000) int rows, Boolean tell) {
    }

    @PostMapping("/batches")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> open(@Valid @RequestBody OpenIn body) {
        return parseMap(jdbc.sql("SELECT admissions.pg_migration_open(:k, :f, :s, :n, :t)::text")
                .param("k", kindOf(body.kind())).param("f", body.fileName())
                .param("s", body.sha256() == null || body.sha256().isBlank() ? null : body.sha256().trim().toLowerCase(), Types.VARCHAR)
                .param("n", body.rows()).param("t", body.tell() == null || body.tell())
                .query(String.class).single());
    }

    public record RowsIn(@Min(1) int first, @NotNull @Size(min = 1, max = 1000) List<Map<String, Object>> rows) {
    }

    @PostMapping("/batches/{id}/rows")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> stage(@PathVariable UUID id, @Valid @RequestBody RowsIn body) {
        return parseMap(jdbc.sql("SELECT admissions.pg_migration_stage(:b, :first, :rows::jsonb)::text")
                .param("b", id).param("first", body.first()).param("rows", mapper.writeValueAsString(body.rows()))
                .query(String.class).single());
    }

    public record RangeIn(@Min(1) int from, @Min(1) int to) {
    }

    @PostMapping("/batches/{id}/check")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> check(@PathVariable UUID id, @Valid @RequestBody RangeIn body) {
        return parseMap(jdbc.sql("SELECT admissions.pg_migration_check(:b, :f, :t)::text")
                .param("b", id).param("f", body.from()).param("t", body.to()).query(String.class).single());
    }

    @PostMapping("/batches/{id}/import")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> importRows(@PathVariable UUID id, @Valid @RequestBody RangeIn body) {
        return parseMap(jdbc.sql("SELECT admissions.pg_migration_import(:b, :f, :t)::text")
                .param("b", id).param("f", body.from()).param("t", body.to()).query(String.class).single());
    }

    @PostMapping("/batches/{id}/finish")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> finish(@PathVariable UUID id) {
        return parseMap(jdbc.sql("SELECT admissions.pg_migration_finish(:b)::text").param("b", id).query(String.class).single());
    }

    public record ReasonIn(@NotBlank @Size(max = 1000) String reason) {
    }

    @PostMapping("/batches/{id}/abandon")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> abandon(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        return parseMap(jdbc.sql("SELECT admissions.pg_migration_abandon(:b, :r)::text").param("b", id).param("r", body.reason()).query(String.class).single());
    }

    /** the history of migration batches, newest first */
    @GetMapping("/batches")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> batches(@RequestParam(defaultValue = "100") int limit) {
        return jdbc.sql("""
                SELECT b.id, b.reference, b.kind, b.state, b.file_name, b.file_sha256, b.rows_expected, b.started_at, b.checked_at, b.completed_at,
                       b.abandoned_at, b.abandoned_reason, b.started_office,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.started_by) AS started_by,
                       c.created, c.updated, c.reconciled, c.linked, c.unchanged, c.skipped, c.failed, c.admitted, c.duplicates, c.errors, c.conflicts, c.review
                  FROM admissions.pg_migration_batch b
                  CROSS JOIN LATERAL (
                      SELECT count(*) FILTER (WHERE r.result = 'CREATED') AS created, count(*) FILTER (WHERE r.result = 'UPDATED') AS updated,
                             count(*) FILTER (WHERE r.result = 'RECONCILED') AS reconciled, count(*) FILTER (WHERE r.result = 'LINKED') AS linked,
                             count(*) FILTER (WHERE r.result = 'UNCHANGED') AS unchanged, count(*) FILTER (WHERE r.result = 'SKIPPED') AS skipped,
                             count(*) FILTER (WHERE r.result = 'FAILED') AS failed,
                             count(*) FILTER (WHERE r.target_state IN ('OFFERED', 'ACCEPTED', 'ADMITTED') AND r.result IN ('CREATED', 'UPDATED', 'RECONCILED')) AS admitted,
                             count(*) FILTER (WHERE r.verdict = 'DUPLICATE_IN_FILE') AS duplicates, count(*) FILTER (WHERE r.verdict = 'ERROR') AS errors,
                             count(*) FILTER (WHERE r.verdict = 'CONFLICT') AS conflicts, count(*) FILTER (WHERE r.verdict = 'REQUIRES_REVIEW') AS review
                        FROM admissions.pg_migration_row r WHERE r.batch_id = b.id) c
                 ORDER BY b.started_at DESC LIMIT :n
                """).param("n", Math.max(1, Math.min(limit, 500))).query().listOfRows();
    }

    @GetMapping("/batches/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> batch(@PathVariable UUID id) {
        String s = jdbc.sql("SELECT admissions.pg_migration_summary(:b)::text").param("b", id).query(String.class).optional().orElse(null);
        if (s == null) {
            throw new NotFound("migration batch", id);
        }
        return parseMap(s);
    }

    /** the rows of a batch as checked or imported, filtered and paged on the server */
    @GetMapping("/batches/{id}/rows")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> rows(@PathVariable UUID id, @RequestParam(required = false) String status, @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        int sz = Math.max(1, Math.min(size, 500));
        String st = status == null || status.isBlank() ? "ALL" : status.trim().toUpperCase();
        String where = rowFilter(st);
        String like = q == null || q.isBlank() ? null : "%" + q.trim().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        long total = jdbc.sql("SELECT count(*) FROM admissions.pg_migration_row r WHERE r.batch_id = :b AND " + where
                        + " AND (:like::text IS NULL OR r.legacy_no ILIKE :like OR r.applicant ILIKE :like OR r.email ILIKE :like)")
                .param("b", id).param("st", st).param("like", like, Types.VARCHAR).query(Long.class).single();
        List<Map<String, Object>> rows = listRows(id, where, st, like, sz, Math.max(page, 0) * sz);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", Math.max(page, 0));
        out.put("size", sz);
        out.put("rows", rows);
        return out;
    }

    /** every row that is not plainly ready, for the downloadable error report */
    @GetMapping("/batches/{id}/report")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> report(@PathVariable UUID id) {
        return listRows(id, rowFilter("PROBLEMS"), "PROBLEMS", null, 20000, 0);
    }

    private static String rowFilter(String st) {
        if ("ALL".equals(st)) return "true";
        if ("PROBLEMS".equals(st)) return "(r.verdict IS DISTINCT FROM 'READY' OR r.result IN ('FAILED', 'SKIPPED'))";
        if (STATUSES.contains(st)) return "r.verdict = :st";
        if (RESULTS.contains(st)) return "r.result = :st";
        throw new DomainRuleViolation("PGMIG_FILTER", "No such filter: " + st + ".", new DomainRuleViolation.Remedy("Choose a filter from the list.", "You"));
    }

    private List<Map<String, Object>> listRows(UUID batch, String where, String st, String like, int limit, int offset) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.id, r.row_no, r.legacy_no, r.applicant, r.email, r.verdict, r.match, r.action, r.programme_code, r.session, r.target_state,
                       r.problems::text AS problems, r.result, r.result_note, r.decided_new, r.decided_new_reason, r.application_id, r.student_id,
                       (SELECT a.application_no FROM admissions.pg_application a WHERE a.id = r.application_id) AS application_no,
                       (SELECT coalesce(s.matric_no, s.admission_no) FROM people.student s WHERE s.id = r.student_id) AS student_no,
                       r.data ->> 'sheetRow' AS sheet_row, r.data ->> 'programme' AS programme_given, r.data ->> 'programmeCode' AS programme_code_given,
                       r.data ->> 'department' AS department_given, r.data ->> 'faculty' AS faculty_given,
                       coalesce(r.data ->> 'admissionStatus', r.data ->> 'applicationStatus') AS status_given,
                       (SELECT g.name FROM ref.programme g WHERE g.code = r.programme_code) AS programme_name,
                       (SELECT d.name FROM ref.programme g JOIN ref.department d ON d.code = g.dept_code WHERE g.code = r.programme_code) AS department_name,
                       (SELECT f.name FROM ref.programme g JOIN ref.faculty f ON f.code = g.faculty_code WHERE g.code = r.programme_code) AS faculty_name
                  FROM admissions.pg_migration_row r
                 WHERE r.batch_id = :b AND """ + where + """
                   AND (:like::text IS NULL OR r.legacy_no ILIKE :like OR r.applicant ILIKE :like OR r.email ILIKE :like)
                 ORDER BY r.row_no LIMIT :lim OFFSET :off
                """).param("b", batch).param("st", st).param("like", like, Types.VARCHAR).param("lim", limit).param("off", offset)
                .query().listOfRows();
        List<Map<String, Object>> out = new ArrayList<>(rows.size());
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.put("problems", parse((String) r.get("problems")));
            out.add(m);
        }
        return out;
    }

    /** the School's word on a row held as a possible same person: a new applicant all the same */
    @PostMapping("/rows/{rowId}/new")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> decideNew(@PathVariable UUID rowId, @Valid @RequestBody ReasonIn body) {
        return parseMap(jdbc.sql("SELECT admissions.pg_migration_row_new(:r, :why)::text").param("r", rowId).param("why", body.reason()).query(String.class).single());
    }

    /* ── the old programmes mapped to this portal's ── */

    @GetMapping("/programme-map")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> programmeMap() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("mappings", jdbc.sql("""
                SELECT m.id, m.legacy_code, m.legacy_name, m.programme_code, g.name AS programme_name, d.name AS department, f.name AS faculty,
                       (SELECT s.name FROM catalogue.programme_specialisation s WHERE s.id = m.specialisation_id) AS specialisation,
                       m.state, m.reason, m.mapped_at, m.mapped_office,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = m.mapped_by) AS mapped_by,
                       m.withdrawn_at, m.withdrawn_reason
                  FROM admissions.pg_legacy_programme m JOIN ref.programme g ON g.code = m.programme_code
                  JOIN ref.department d ON d.code = g.dept_code JOIN ref.faculty f ON f.code = g.faculty_code
                 ORDER BY m.state, m.legacy_name
                """).query().listOfRows());
        out.put("unmapped", jdbc.sql("SELECT * FROM admissions.pg_legacy_unmapped()").query().listOfRows());
        out.put("programmes", jdbc.sql("""
                SELECT g.code, g.name, g.pg_award AS award, d.name AS department, f.name AS faculty
                  FROM ref.programme g JOIN ref.department d ON d.code = g.dept_code JOIN ref.faculty f ON f.code = g.faculty_code
                 WHERE g.category = 'POST GRADUATE' AND NOT g.archived ORDER BY g.name, g.code
                """).query().listOfRows());
        out.put("specialisations", jdbc.sql("""
                SELECT s.id, s.programme_code, s.name FROM catalogue.programme_specialisation s JOIN ref.programme g ON g.code = s.programme_code
                 WHERE s.active AND g.category = 'POST GRADUATE' AND NOT g.archived ORDER BY s.name
                """).query().listOfRows());
        return out;
    }

    public record MapIn(@Size(max = 60) String legacyCode, @Size(max = 200) String legacyName, @NotBlank @Size(max = 20) String programme,
                        UUID specialisationId, @NotBlank @Size(max = 1000) String reason) {
    }

    @PostMapping("/programme-map")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> map(@Valid @RequestBody MapIn body) {
        UUID id = jdbc.sql("SELECT admissions.pg_legacy_map_programme(:c, :n, :p, :s, :r)")
                .param("c", body.legacyCode(), Types.VARCHAR).param("n", body.legacyName(), Types.VARCHAR).param("p", body.programme())
                .param("s", body.specialisationId(), Types.OTHER).param("r", body.reason()).query(UUID.class).single();
        return Map.of("id", id);
    }

    @PostMapping("/programme-map/{id}/withdraw")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> unmap(@PathVariable UUID id, @Valid @RequestBody ReasonIn body) {
        jdbc.sql("SELECT admissions.pg_legacy_unmap(:id, :r)").param("id", id).param("r", body.reason()).query().listOfRows();
        return Map.of("id", id, "state", "WITHDRAWN");
    }

    /* ── the figures, the records behind them, and the search by either number ── */

    @GetMapping("/figures")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> figures() {
        return parseMap(jdbc.sql("SELECT admissions.pg_legacy_figures()::text").query(String.class).single());
    }

    @GetMapping("/list")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam String view, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        int sz = Math.max(1, Math.min(size, 500));
        return parseMap(jdbc.sql("SELECT admissions.pg_legacy_list(:v, :n, :o)::text")
                .param("v", view).param("n", sz).param("o", Math.max(page, 0) * sz).query(String.class).single());
    }

    @GetMapping("/find")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> find(@RequestParam String q) {
        if (q == null || q.trim().length() < 3) {
            return List.of();
        }
        return jdbc.sql("SELECT * FROM admissions.pg_legacy_find(:q)").param("q", q.trim()).query().listOfRows();
    }

    /* ── a fee paid on the old portal, verified or rejected ── */

    public record DecideIn(boolean verify, @NotBlank @Size(max = 1000) String note) {
    }

    @PostMapping("/fees/{id}/decide")
    @PreAuthorize(FEE_DECIDERS)
    @Transactional
    Map<String, Object> decideFee(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        return parseMap(jdbc.sql("SELECT admissions.pg_legacy_fee_decide(:f, :v, :n)::text")
                .param("f", id).param("v", body.verify()).param("n", body.note()).query(String.class).single());
    }

    /* ── an old document's file, attached to the application through the PG documents ── */

    public record FileIn(@NotBlank @Size(max = 255) String filename, @NotBlank @Size(max = 100) String contentType, @NotBlank String base64) {
    }

    @PostMapping("/documents/{id}/file")
    @PreAuthorize(MIGRATORS)
    @Transactional
    Map<String, Object> attach(@PathVariable UUID id, @Valid @RequestBody FileIn body) {
        Map<String, Object> d = jdbc.sql("""
                SELECT d.application_id, d.kind, d.label, d.document_id FROM admissions.pg_legacy_document d WHERE d.id = :id FOR UPDATE
                """).param("id", id).query().listOfRows().stream().findFirst().orElse(null);
        if (d == null) {
            throw new NotFound("old-portal document", id);
        }
        if (d.get("application_id") == null) {
            throw new DomainRuleViolation("PGMIG_DOC_STUDENT", "This document belongs to a student already on the register, not to an application; its file is kept with the student's records.",
                    new DomainRuleViolation.Remedy("Upload it through the student's records.", "Registry"));
        }
        if (d.get("document_id") != null) {
            throw new DomainRuleViolation("PGMIG_DOC_ATTACHED", "The file for this document is already attached.",
                    new DomainRuleViolation.Remedy("Open the application to read it.", "School of Postgraduate Studies"));
        }
        String kind = String.valueOf(d.get("kind"));
        String type = body.contentType().trim().toLowerCase();
        boolean image = "PASSPORT".equals(kind);
        if (image ? !Set.of("image/jpeg", "image/png").contains(type) : !"application/pdf".equals(type)) {
            throw new DomainRuleViolation("PGMIG_DOC_TYPE", image ? "A passport photograph is a JPEG or PNG image." : "A document is a single PDF file.",
                    new DomainRuleViolation.Remedy("Scan or export it in that form and attach it again.", "You"));
        }
        byte[] content;
        try {
            content = java.util.Base64.getDecoder().decode(body.base64());
        } catch (IllegalArgumentException notBase64) {
            throw new DomainRuleViolation("PGMIG_DOC_ENCODING", "The file did not arrive intact.", new DomainRuleViolation.Remedy("Try again.", "You"));
        }
        if (content.length == 0 || content.length > MAX_DOC) {
            throw new DomainRuleViolation("PGMIG_DOC_SIZE", "A document is between 1 byte and 8 MB; this one is " + content.length + " bytes.",
                    new DomainRuleViolation.Remedy("Reduce the scan's resolution and attach it again.", "You"));
        }
        // the bytes say what the file is, not its name
        boolean looks = "application/pdf".equals(type) ? startsWith(content, new byte[] {'%', 'P', 'D', 'F'})
                : "image/png".equals(type) ? startsWith(content, new byte[] {(byte) 0x89, 'P', 'N', 'G'})
                : startsWith(content, new byte[] {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF});
        if (!looks) {
            throw new DomainRuleViolation("PGMIG_DOC_TYPE", "The file is not the " + (image ? "image" : "PDF") + " its name says.",
                    new DomainRuleViolation.Remedy("Attach the document itself.", "You"));
        }
        UUID app = (UUID) d.get("application_id");
        String name = body.filename().trim().replaceAll("[\\\\/:*?\"<>|\\r\\n]+", "_");
        UUID oid = files.store("admissions.pg_document", app, name, type, content);
        UUID doc = jdbc.sql("""
                INSERT INTO admissions.pg_document (application_id, kind, filename, content_type, bytes, object_id)
                VALUES (:app, :k, :fn, :ct, :b, :o) RETURNING id
                """).param("app", app).param("k", kind).param("fn", name).param("ct", type)
                .param("b", oid == null ? content : null, Types.BINARY).param("o", oid, Types.OTHER).query(UUID.class).single();
        jdbc.sql("""
                UPDATE admissions.pg_legacy_document SET document_id = :doc, attached_at = now(), attached_by = :who WHERE id = :id
                """).param("doc", doc).param("who", AuditContextHolder.required().actorId()).param("id", id).update();
        jdbc.sql("SELECT admissions.pg_app_event(:app, 'OLD_PORTAL_DOCUMENT_ATTACHED', :n)")
                .param("app", app).param("n", d.get("label") + " from the old portal attached: " + name).query().listOfRows();
        return Map.of("id", id, "documentId", doc);
    }

    private static boolean startsWith(byte[] b, byte[] prefix) {
        if (b.length < prefix.length) return false;
        for (int i = 0; i < prefix.length; i++) {
            if (b[i] != prefix[i]) return false;
        }
        return true;
    }
}
