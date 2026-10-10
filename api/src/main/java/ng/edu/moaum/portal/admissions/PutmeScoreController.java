package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
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
 * V385: the Post-UTME CBT scores from the engine to the admission, through the portal and on the record. The Directorate of ICT
 * reads every candidate's best approved attempt of a session, generates the official score file (a snapshot with its reference and
 * hash), downloads it as a spreadsheet and sends it to the Academic Office. The Academic Office receives it, previews what an
 * import would do to each line, and imports it into the same screening score the admission has always read — a released score is
 * never touched, a different score already held is kept or, with a reason, replaced with the old value on the history. Every act
 * is on the file's own record; the CBT score and the admission result stay two different things.
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}/putme-scores")
class PutmeScoreController {

    /** who reads the scores and the files */
    private static final String READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_admin','OFFICE_super')";
    /** who exports, sends and cancels: the Directorate of ICT */
    private static final String ICT = "hasAnyAuthority('OFFICE_ict','OFFICE_super')";
    /** who receives, downloads, rejects and imports: the Academic Office */
    private static final String ACADEMIC = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    public record ExportIn(UUID examId) {
    }

    public record NoteIn(@Size(max = 2000) String message, @Size(max = 2000) String reason) {
    }

    public record ImportIn(@Size(max = 10) String mode, @Size(max = 2000) String reason) {
    }

    private final JdbcClient jdbc;

    PutmeScoreController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static AuditContext actor() {
        return AuditContextHolder.required();
    }

    private Map<String, Object> export(UUID id, String session) {
        return jdbc.sql("""
                SELECT x.*, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = x.generated_by) AS generated_by_name,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = x.sent_by) AS sent_by_name,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = x.received_by) AS received_by_name,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = x.imported_by) AS imported_by_name,
                       (SELECT jsonb_agg(jsonb_build_object('id', i.id, 'mode', i.mode, 'reason', i.reason, 'received', i.received, 'applied', i.applied, 'unchanged', i.unchanged,
                                                             'replaced', i.replaced, 'kept', i.kept, 'released', i.released, 'notFound', i.not_found, 'importedAt', i.imported_at,
                                                             'importedBy', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = i.imported_by)) ORDER BY i.imported_at)
                          FROM admissions.putme_score_import i WHERE i.export_id = x.id)::text AS imports
                  FROM admissions.putme_score_export x WHERE x.id = :id AND x.session = :s
                """).param("id", id).param("s", session).query().listOfRows().stream().findFirst().map(LinkedHashMap::new)
                .orElseThrow(() -> new NotFound("score file", id.toString()));
    }

    private List<Map<String, Object>> exports(String session) {
        return jdbc.sql("""
                SELECT x.id, x.reference, x.session, x.exam_id, x.exam_title, x.state, x.rows_count, x.sha256, x.message, x.generated_at, x.sent_at, x.received_at, x.downloaded_at,
                       x.imported_at, x.rejected_at, x.cancelled_at, x.closing_note,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = x.generated_by) AS generated_by_name,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = x.sent_by) AS sent_by_name
                  FROM admissions.putme_score_export x WHERE x.session = :s ORDER BY x.generated_at DESC
                """).param("s", session).query().listOfRows();
    }

    /** the scores of a session: every applicant's best approved attempt, searched and filtered; the examinations and the files beside them */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> scores(@PathVariable String session, @PathVariable String year, @RequestParam(required = false) UUID exam,
                               @RequestParam(required = false) String q, @RequestParam(required = false) String prog, @RequestParam(required = false) String fac,
                               @RequestParam(required = false) String status, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "100") int size) {
        String s = session + "/" + year;
        int sz = Math.max(1, Math.min(size, 1000)), pg = Math.max(1, page);
        String st = status == null || status.isBlank() ? null : status.trim().toUpperCase();
        String where = """
                 WHERE (:q::text IS NULL OR lower(x.surname || ' ' || x.other_names) LIKE :q OR lower(x.jamb_reg_no) LIKE :q OR lower(coalesce(x.application_no, '')) LIKE :q)
                   AND (:prog::text IS NULL OR x.programme_code = :prog) AND (:fac::text IS NULL OR x.faculty = :fac)
                   AND (:st::text IS NULL OR (:st = 'OFFICIAL' AND x.official) OR (:st = 'UNAPPROVED' AND NOT x.official) OR (:st = 'EXPORTED' AND x.exported_in IS NOT NULL)
                        OR (:st = 'NOT_EXPORTED' AND x.exported_in IS NULL) OR (:st = 'IMPORTED' AND x.existing_score IS NOT NULL) OR (:st = 'RELEASED' AND x.score_released_at IS NOT NULL)
                        OR (:st = 'VOID' AND x.outcome = 'VOID'))
                """;
        java.util.function.UnaryOperator<JdbcClient.StatementSpec> bind = spec -> spec.param("s", s).param("e", exam, Types.OTHER)
                .param("q", q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%", Types.VARCHAR)
                .param("prog", prog == null || prog.isBlank() ? null : prog.trim(), Types.VARCHAR).param("fac", fac == null || fac.isBlank() ? null : fac.trim(), Types.VARCHAR)
                .param("st", st, Types.VARCHAR);
        long total = bind.apply(jdbc.sql("SELECT count(*) FROM admissions.putme_cbt_scores(:s, :e) x" + where)).query(Long.class).single();
        List<Map<String, Object>> rows = bind.apply(jdbc.sql("SELECT x.* FROM admissions.putme_cbt_scores(:s, :e) x" + where + " ORDER BY x.jamb_reg_no LIMIT :lim OFFSET :off"))
                .param("lim", sz).param("off", (long) (pg - 1) * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        out.put("counts", bind.apply(jdbc.sql("""
                SELECT count(*) AS scored, count(*) FILTER (WHERE x.official) AS official, count(*) FILTER (WHERE x.exported_in IS NOT NULL) AS exported,
                       count(*) FILTER (WHERE x.existing_score IS NOT NULL) AS imported, count(*) FILTER (WHERE x.score_released_at IS NOT NULL) AS released,
                       round(avg(x.percentage) FILTER (WHERE x.official), 2) AS average, max(x.percentage) FILTER (WHERE x.official) AS highest, min(x.percentage) FILTER (WHERE x.official) AS lowest,
                       (SELECT count(*) FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE a.session = :s AND a.submitted_at IS NOT NULL AND c.entry_mode <> 'CCE') AS applicants
                  FROM admissions.putme_cbt_scores(:s, :e) x
                """)).query().singleRow());
        out.put("exams", jdbc.sql("""
                SELECT e.id, e.reference, e.title, e.state, e.results_state, assessment.cbt_live_state(e) AS live_state, e.starts_at, e.ends_at,
                       (SELECT count(DISTINCT a.candidate_id) FROM assessment.cbt_attempt a WHERE a.exam_id = e.id AND a.status <> 'IN_PROGRESS') AS sat
                  FROM assessment.cbt_exam e WHERE e.office = 'POST_UTME' AND e.putme_session = :s ORDER BY e.starts_at DESC NULLS LAST
                """).param("s", s).query().listOfRows());
        out.put("exports", exports(s));
        out.put("faculties", jdbc.sql("SELECT DISTINCT x.faculty FROM admissions.putme_cbt_scores(:s, NULL) x WHERE x.faculty IS NOT NULL ORDER BY 1").param("s", s).query(String.class).list());
        out.put("programmes", jdbc.sql("SELECT DISTINCT x.programme_code AS code, x.programme AS name FROM admissions.putme_cbt_scores(:s, NULL) x WHERE x.programme_code IS NOT NULL ORDER BY 2").param("s", s).query().listOfRows());
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /** the official file generated: a snapshot of every approved score, with its reference and hash */
    @PostMapping("/exports")
    @PreAuthorize(ICT)
    @Transactional
    Map<String, Object> export(@PathVariable String session, @PathVariable String year, @RequestBody(required = false) ExportIn in) {
        String s = session + "/" + year;
        AuditContext ctx = actor();
        UUID id = jdbc.sql("SELECT (admissions.putme_export_scores(:s, :e, :by, :o)).id").param("s", s).param("e", in == null ? null : in.examId(), Types.OTHER)
                .param("by", ctx.actorId(), Types.OTHER).param("o", ctx.actorOffice(), Types.VARCHAR).query(UUID.class).single();
        return export(id, s);
    }

    /** one file, with its lines (for the spreadsheet) and its history */
    @GetMapping("/exports/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        String s = session + "/" + year;
        Map<String, Object> out = export(id, s);
        out.put("rows", jdbc.sql("""
                SELECT r.sn, r.application_id, r.jamb_reg_no, r.application_no, r.candidate_name, r.faculty, r.department, r.programme, r.exam_title, r.questions, r.attempted,
                       r.max_marks, r.score, r.percentage, r.exam_date, r.attempt_status, r.outcome
                  FROM admissions.putme_score_export_row r WHERE r.export_id = :id ORDER BY r.sn
                """).param("id", id).query().listOfRows());
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /** the Directorate's acts: send to the Academic Office (with a message), or cancel before it is imported (with a reason) */
    @PostMapping("/exports/{id}/send")
    @PreAuthorize(ICT)
    @Transactional
    Map<String, Object> send(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @RequestBody(required = false) NoteIn in) {
        String s = session + "/" + year;
        export(id, s);
        jdbc.sql("SELECT (admissions.putme_send_export(:id, :m, :by)).state").param("id", id).param("m", in == null ? null : in.message(), Types.VARCHAR)
                .param("by", actor().actorId(), Types.OTHER).query(String.class).single();
        return export(id, s);
    }

    @PostMapping("/exports/{id}/cancel")
    @PreAuthorize(ICT)
    @Transactional
    Map<String, Object> cancel(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @Valid @RequestBody NoteIn in) {
        String s = session + "/" + year;
        export(id, s);
        jdbc.sql("SELECT (admissions.putme_export_act(:id, 'CANCEL', :n, :by)).state").param("id", id).param("n", in.reason(), Types.VARCHAR)
                .param("by", actor().actorId(), Types.OTHER).query(String.class).single();
        return export(id, s);
    }

    /** the Academic Office's acts: receive, mark downloaded, reject (with a reason) */
    @PostMapping("/exports/{id}/{action}")
    @PreAuthorize(ACADEMIC)
    @Transactional
    Map<String, Object> act(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @PathVariable String action, @RequestBody(required = false) NoteIn in) {
        String s = session + "/" + year;
        String a = action == null ? "" : action.trim().toUpperCase();
        if (!List.of("RECEIVE", "DOWNLOAD", "REJECT").contains(a)) throw new NotFound("action", action);
        export(id, s);
        jdbc.sql("SELECT (admissions.putme_export_act(:id, :a, :n, :by)).state").param("id", id).param("a", a).param("n", in == null ? null : in.reason(), Types.VARCHAR)
                .param("by", actor().actorId(), Types.OTHER).query(String.class).single();
        return export(id, s);
    }

    /** what the import would do to each line — nothing written */
    @GetMapping("/exports/{id}/preview")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> preview(@PathVariable String session, @PathVariable String year, @PathVariable UUID id) {
        String s = session + "/" + year;
        Map<String, Object> out = export(id, s);
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM admissions.putme_import_preview(:id)").param("id", id).query().listOfRows();
        out.put("rows", rows);
        Map<String, Long> summary = new java.util.TreeMap<>();
        for (Map<String, Object> r : rows) summary.merge(String.valueOf(r.get("outcome")), 1L, Long::sum);
        out.put("summary", summary);
        return out;
    }

    /** the import: an existing different score KEPT (the default) or REPLACED with a reason; a released score never touched */
    @PostMapping("/exports/{id}/import")
    @PreAuthorize(ACADEMIC)
    @Transactional
    Map<String, Object> importScores(@PathVariable String session, @PathVariable String year, @PathVariable UUID id, @RequestBody(required = false) ImportIn in) {
        String s = session + "/" + year;
        export(id, s);
        AuditContext ctx = actor();
        String mode = in == null || in.mode() == null || in.mode().isBlank() ? "KEEP" : in.mode().trim().toUpperCase();
        if ("REPLACE".equals(mode) && (in.reason() == null || in.reason().isBlank())) {
            throw new DomainRuleViolation("PUTME_IMPORT_REASON", "Replacing scores already on the record names the reason.",
                    new DomainRuleViolation.Remedy("Give the reason, or keep the existing scores.", "Academic Office"));
        }
        Map<String, Object> imp = jdbc.sql("SELECT * FROM admissions.putme_import_scores(:id, :m, :r, :by, :o)").param("id", id).param("m", mode)
                .param("r", in == null ? null : in.reason(), Types.VARCHAR).param("by", ctx.actorId(), Types.OTHER).param("o", ctx.actorOffice(), Types.VARCHAR).query().singleRow();
        Map<String, Object> out = export(id, s);
        out.put("import", imp);
        return out;
    }

    /** one application's Post-UTME score history: every entry and replacement, with the file and the reason */
    @GetMapping("/history/{application}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history(@PathVariable String session, @PathVariable String year, @PathVariable UUID application) {
        String s = session + "/" + year;
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.application WHERE id = :a AND session = :s)").param("a", application).param("s", s).query(Boolean.class).single()) {
            throw new NotFound("application", application);
        }
        return jdbc.sql("""
                SELECT h.id, h.action, h.previous_score, h.new_score, h.reason, h.changed_at, h.changed_office, x.reference,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = h.changed_by) AS changed_by
                  FROM admissions.putme_score_history h LEFT JOIN admissions.putme_score_export x ON x.id = h.export_id
                 WHERE h.application_id = :a ORDER BY h.changed_at
                """).param("a", application).query().listOfRows();
    }

    /** V385: the Academic Office's own tally — files waiting on it, so the desk shows what has arrived */
    @GetMapping("/inbox")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> inbox(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        if (!List.of("academic", "registrar", "dregistrar", "super", "ict", "admin").contains(acting)) throw new AccessDeniedException("The Post-UTME score files are the Academic Office's and the Directorate of ICT's.");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("exports", exports(s));
        out.put("waiting", jdbc.sql("SELECT count(*) FROM admissions.putme_score_export WHERE session = :s AND state IN ('SENT_TO_ACADEMIC', 'RECEIVED', 'DOWNLOADED')").param("s", s).query(Long.class).single());
        out.put("now", OffsetDateTime.now());
        return out;
    }
}
