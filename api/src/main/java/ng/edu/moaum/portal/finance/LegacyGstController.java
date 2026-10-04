package ng.edu.moaum.portal.finance;

import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.interceptor.TransactionAspectSupport;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Old-portal GST payments reconciled into the GST/EPS entitlement (V323). The Bursary stages the old portal's export
 * as it is, the portal matches each row to a current student by strong identifiers only, validates it against the fee
 * the Bursar stated for that session and against the ledger, and shows the counts before anything is written; a dry
 * run writes nothing at all. On the Bursary's word the validated rows go onto the one ledger as confirmed references
 * of purpose 'GST fee <session>', channel Legacy, carrying the old reference and the old date — the row the gateway
 * would have written — and every reader of the entitlement follows. What cannot be reconciled waits in the exception
 * queue with its reason for a Finance officer to match, reconcile with an override reason, relabel or reject.
 */
@RestController
@RequestMapping("/api/v1/finance/legacy-gst")
class LegacyGstController {

    /** who reads old-portal financial records: the Bursary, audit, the Registry, ICT and the administrators */
    private static final String VIEWERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_audit','OFFICE_deputyaudit','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    /** who stages, applies and resolves: the Bursary alone (and the Super Administrator) */
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_super')";
    private static final Set<String> STATUSES = Set.of("UNPROCESSED", "MATCHED", "RECONCILED", "REQUIRES_REVIEW", "REJECTED", "DUPLICATE", "UNMATCHED");
    private static final Set<String> ACTIONS = Set.of("match", "reconcile", "relabel", "reject");
    private static final int MAX_ROWS = 50_000;

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    LegacyGstController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record ImportIn(@NotNull @Size(max = MAX_ROWS) List<Map<String, Object>> rows, @Size(max = 200) String fileName, @Size(max = 9) String session,
                           Boolean dryRun, @Size(max = 500) String note) {
    }

    public record ResolveIn(UUID studentId, @Size(max = 1000) String reason) {
    }

    /* ── the figures ── */

    @GetMapping("/summary")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String session) {
        String s = blank(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("summary", jdbc.sql("SELECT * FROM finance.legacy_gst_summary(NULL, :s)").param("s", s, Types.VARCHAR).query().singleRow());
        out.put("exceptions", exceptions(null, s));
        out.put("imports", recentImports(20));
        out.put("sessions", jdbc.sql("""
                SELECT lp.session, count(*) AS rows, count(*) FILTER (WHERE rc.status = 'RECONCILED') AS reconciled,
                       count(*) FILTER (WHERE rc.status IN ('REQUIRES_REVIEW', 'UNMATCHED')) AS open, coalesce(sum(lp.amount) FILTER (WHERE lp.normalized_status = 'SUCCESS'), 0) AS amount
                  FROM finance.legacy_gst_payment lp JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = lp.id
                 GROUP BY lp.session ORDER BY lp.session DESC NULLS LAST
                """).query().listOfRows());
        out.put("fees", jdbc.sql("""
                SELECT session, amount, level, entry_mode, faculty_code, programme_code FROM finance.gst_fee WHERE superseded_at IS NULL ORDER BY session DESC, stated_at
                """).query().listOfRows());
        out.put("now", OffsetDateTime.now());
        return out;
    }

    private List<Map<String, Object>> exceptions(UUID importId, String session) {
        return jdbc.sql("""
                SELECT rc.status, coalesce(rc.reason_code, '') AS code, count(*) AS n, coalesce(sum(lp.amount), 0) AS amount
                  FROM finance.legacy_gst_reconciliation rc JOIN finance.legacy_gst_payment lp ON lp.id = rc.payment_id
                 WHERE (:i::uuid IS NULL OR rc.import_id = :i) AND (:s::text IS NULL OR lp.session = :s) AND rc.status <> 'RECONCILED'
                 GROUP BY rc.status, rc.reason_code ORDER BY rc.status, n DESC
                """).param("i", importId, Types.OTHER).param("s", session, Types.VARCHAR).query().listOfRows();
    }

    private List<Map<String, Object>> recentImports(int limit) {
        return jdbc.sql("""
                SELECT i.*, CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS uploaded_by_name,
                       (SELECT count(*) FROM finance.legacy_gst_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'RECONCILED') AS reconciled,
                       (SELECT count(*) FROM finance.legacy_gst_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'MATCHED') AS matched,
                       (SELECT count(*) FROM finance.legacy_gst_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'REQUIRES_REVIEW') AS requires_review,
                       (SELECT count(*) FROM finance.legacy_gst_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'UNMATCHED') AS unmatched,
                       (SELECT count(*) FROM finance.legacy_gst_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'DUPLICATE') AS duplicates,
                       (SELECT count(*) FROM finance.legacy_gst_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'REJECTED') AS rejected,
                       (SELECT coalesce(sum(r.amount), 0) FROM finance.legacy_gst_reconciliation rc JOIN finance.payment_reference r ON r.id = rc.payment_reference_id WHERE rc.import_id = i.id) AS reconciled_amount
                  FROM finance.legacy_gst_import i LEFT JOIN iam.person p ON p.id = i.uploaded_by
                 ORDER BY i.uploaded_at DESC LIMIT :n
                """).param("n", limit).query().listOfRows();
    }

    /* ── a run: staged, matched and validated at once; written to the ledger only on apply; a dry run writes nothing ── */

    @PostMapping("/imports")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> stage(@Valid @RequestBody ImportIn in) {
        if (in.rows().isEmpty()) {
            throw new DomainRuleViolation("LEGACY_ROWS_REQUIRED", "The file has no payment rows to read.", new DomainRuleViolation.Remedy("Upload the old portal's GST payment export.", "Bursary"));
        }
        boolean dry = Boolean.TRUE.equals(in.dryRun());
        UUID id = jdbc.sql("SELECT (finance.legacy_gst_new_import(:f, :s, :n)).id")
                .param("f", blank(in.fileName()), Types.VARCHAR).param("s", blank(in.session()), Types.VARCHAR).param("n", blank(in.note()), Types.VARCHAR).query(UUID.class).single();
        Map<String, Object> staged = jdbc.sql("SELECT * FROM finance.legacy_gst_stage(:i, :j::jsonb)").param("i", id).param("j", mapper.writeValueAsString(in.rows())).query().singleRow();
        jdbc.sql("SELECT finance.legacy_gst_match(:i)").param("i", id).query(Integer.class).single();
        jdbc.sql("SELECT finance.legacy_gst_validate(:i)").param("i", id).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(one(id, null, null, 1, 500));
        out.put("staging", staged);
        out.put("dryRun", dry);
        if (dry) {
            // everything above is undone when the transaction ends: the counts are the preview, nothing is on the record
            TransactionAspectSupport.currentTransactionStatus().setRollbackOnly();
        }
        return out;
    }

    @GetMapping("/imports")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> imports(@RequestParam(defaultValue = "50") int limit) {
        return recentImports(Math.max(1, Math.min(limit, 200)));
    }

    @GetMapping("/imports/{id}")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id, @RequestParam(required = false) String status, @RequestParam(required = false) String q,
                            @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "100") int size) {
        Map<String, Object> imp = jdbc.sql("SELECT * FROM finance.legacy_gst_import WHERE id = :id").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("import", id.toString()));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("import", imp);
        out.put("summary", jdbc.sql("SELECT * FROM finance.legacy_gst_summary(:i, NULL)").param("i", id).query().singleRow());
        out.put("exceptions", exceptions(id, null));
        out.putAll(rows(id, status, null, null, q, page, size));
        return out;
    }

    @PostMapping("/imports/{id}/apply")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> apply(@PathVariable UUID id) {
        Map<String, Object> applied = jdbc.sql("SELECT * FROM finance.legacy_gst_apply(:i)").param("i", id).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(one(id, null, null, 1, 100));
        out.put("applied", applied);
        return out;
    }

    /* ── the rows: search, the queue, one payment, the officer's hand ── */

    private static final String ROW_SQL = """
            SELECT lp.id, lp.import_id, i.reference AS import_reference, lp.row_no, lp.source_system, lp.source_transaction_id, lp.source_reference, lp.gateway, lp.gateway_reference,
                   lp.source_student_id, lp.matric_no, lp.jamb_no, lp.application_no, lp.student_name, lp.payment_type, finance.legacy_gst_type_of(lp.payment_type) AS maps_to,
                   lp.amount, lp.currency, lp.paid_at, lp.paid_at_text, lp.session, lp.semester, lp.legacy_status, lp.normalized_status, lp.imported_at,
                   rc.status, rc.reason_code, rc.reason, rc.student_id, rc.match_method, rc.match_confidence, rc.candidates::text AS candidates, rc.fee_amount,
                   rc.payment_reference_id, rc.reconciled_at, rc.reconciled_office, rc.resolved_at, rc.resolved_office, rc.override_reason,
                   s.surname, s.other_names, coalesce(s.matric_no, s.admission_no) AS number, s.programme_code, s.current_level AS level,
                   r.reference AS ledger_reference, r.receipt_no AS ledger_receipt, r.confirmed_at AS ledger_confirmed_at, r.purpose AS ledger_purpose,
                   CASE WHEN rb.id IS NULL THEN NULL ELSE rb.surname || ', ' || rb.given_names END AS reconciled_by_name
              FROM finance.legacy_gst_payment lp
              JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = lp.id
              JOIN finance.legacy_gst_import i ON i.id = lp.import_id
              LEFT JOIN people.student s ON s.id = rc.student_id
              LEFT JOIN finance.payment_reference r ON r.id = rc.payment_reference_id
              LEFT JOIN iam.person rb ON rb.id = rc.reconciled_by
            """;
    private static final String ROW_WHERE = """
             WHERE (:i::uuid IS NULL OR lp.import_id = :i)
               AND (:st::text IS NULL OR rc.status = :st OR (:st = 'OPEN' AND rc.status IN ('REQUIRES_REVIEW', 'UNMATCHED')))
               AND (:code::text IS NULL OR rc.reason_code = :code)
               AND (:s::text IS NULL OR lp.session = :s)
               AND (:q::text IS NULL OR lower(coalesce(lp.source_reference, '')) LIKE :q OR lower(coalesce(lp.source_transaction_id, '')) LIKE :q OR lower(coalesce(lp.gateway_reference, '')) LIKE :q
                    OR lower(coalesce(lp.matric_no, '')) LIKE :q OR lower(coalesce(lp.jamb_no, '')) LIKE :q OR lower(coalesce(lp.application_no, '')) LIKE :q OR lower(coalesce(lp.student_name, '')) LIKE :q
                    OR lower(coalesce(s.surname || ' ' || s.other_names, '')) LIKE :q OR lower(coalesce(s.matric_no, '')) LIKE :q OR lower(coalesce(s.jamb_reg_no, '')) LIKE :q
                    OR lower(coalesce(r.reference, '')) LIKE :q OR lp.amount::text = :raw)
            """;

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, UUID importId, String status, String code, String session, String q) {
        String st = blank(status) == null ? null : status.trim().toUpperCase();
        if (st != null && !STATUSES.contains(st) && !"OPEN".equals(st)) st = null;
        String needle = blank(q) == null ? null : "%" + q.trim().toLowerCase() + "%";
        return spec.param("i", importId, Types.OTHER).param("st", st, Types.VARCHAR).param("code", blank(code) == null ? null : code.trim().toUpperCase(), Types.VARCHAR)
                .param("s", blank(session), Types.VARCHAR).param("q", needle, Types.VARCHAR).param("raw", blank(q) == null ? "" : q.trim().replace(",", ""));
    }

    private Map<String, Object> rows(UUID importId, String status, String code, String session, String q, int page, int size) {
        int sz = Math.max(1, Math.min(size, 500)), pg = Math.max(1, page);
        long total = bind(jdbc.sql("SELECT count(*) FROM finance.legacy_gst_payment lp JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = lp.id LEFT JOIN people.student s ON s.id = rc.student_id LEFT JOIN finance.payment_reference r ON r.id = rc.payment_reference_id" + ROW_WHERE),
                importId, status, code, session, q).query(Long.class).single();
        List<Map<String, Object>> rows = bind(jdbc.sql(ROW_SQL + ROW_WHERE + " ORDER BY lp.session DESC NULLS LAST, lp.import_id, lp.row_no LIMIT :lim OFFSET :off"), importId, status, code, session, q)
                .param("lim", sz).param("off", (long) (pg - 1) * sz).query().listOfRows();
        for (Map<String, Object> r : rows) r.put("candidates", candidates(r.get("candidates")));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        return out;
    }

    private Object candidates(Object text) {
        if (text == null) return List.of();
        try {
            return mapper.readValue(String.valueOf(text), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { });
        } catch (RuntimeException e) {
            return List.of();
        }
    }

    @GetMapping("/rows")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> search(@RequestParam(required = false) UUID importId, @RequestParam(required = false) String status, @RequestParam(required = false) String code,
                               @RequestParam(required = false) String session, @RequestParam(required = false) String q,
                               @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "100") int size) {
        return rows(importId, status, code, session, q, page, size);
    }

    /** every row for the report — the reconciliation report, or the exceptions with status OPEN — bounded */
    @GetMapping("/report")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> report(@RequestParam(required = false) UUID importId, @RequestParam(required = false) String status, @RequestParam(required = false) String session) {
        List<Map<String, Object>> rows = bind(jdbc.sql(ROW_SQL + ROW_WHERE + " ORDER BY s.surname NULLS LAST, s.other_names, lp.row_no LIMIT 20000"), importId, status, null, session, null).query().listOfRows();
        for (Map<String, Object> r : rows) r.remove("candidates");
        return rows;
    }

    @GetMapping("/rows/{id}")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> row(@PathVariable UUID id) {
        Map<String, Object> r = jdbc.sql(ROW_SQL + " WHERE lp.id = :id").param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("legacy payment", id.toString()));
        r.put("candidates", candidates(r.get("candidates")));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("row", r);
        out.put("raw", jdbc.sql("SELECT raw::text FROM finance.legacy_gst_payment WHERE id = :id").param("id", id).query(String.class).optional()
                .map(t -> mapper.readValue(t, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { })).orElse(Map.of()));
        if (r.get("student_id") != null && r.get("session") != null) {
            out.put("standing", jdbc.sql("SELECT * FROM finance.gst_entitlement(:s, :ses)").param("s", r.get("student_id")).param("ses", r.get("session")).query().singleRow());
            out.put("ledger", jdbc.sql("""
                    SELECT r.id, r.reference, r.purpose, r.amount, r.confirmed_at, r.channel, r.receipt_no, r.note FROM finance.payment_reference r
                     WHERE r.student_id = :s AND r.session = :ses AND r.confirmed_at IS NOT NULL ORDER BY r.confirmed_at
                    """).param("s", r.get("student_id")).param("ses", r.get("session")).query().listOfRows());
        }
        return out;
    }

    @PostMapping("/rows/{id}/{action}")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> resolve(@PathVariable UUID id, @PathVariable String action, @Valid @RequestBody ResolveIn in) {
        String a = action == null ? "" : action.trim().toLowerCase();
        if (!ACTIONS.contains(a)) throw new NotFound("action", action);
        jdbc.sql("SELECT (finance.legacy_gst_resolve(:id, :a, :s, :r)).status").param("id", id).param("a", a.toUpperCase()).param("s", in.studentId(), Types.OTHER)
                .param("r", in.reason(), Types.VARCHAR).query(String.class).single();
        return row(id);
    }

    /** a student for the officer's hand: by number, JAMB number or name, never more than twenty */
    @GetMapping("/students")
    @PreAuthorize(BURSARY)
    @Transactional(readOnly = true)
    List<Map<String, Object>> students(@RequestParam String q) {
        String needle = "%" + q.trim().toLowerCase() + "%";
        if (q.trim().length() < 3) return List.of();
        return jdbc.sql("""
                SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.matric_no, s.admission_no, s.jamb_reg_no, s.surname, s.other_names, s.programme_code, p.name AS programme,
                       s.current_level AS level, s.status, s.entry_session
                  FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                 WHERE lower(coalesce(s.matric_no, '')) LIKE :q OR lower(coalesce(s.admission_no, '')) LIKE :q OR lower(coalesce(s.jamb_reg_no, '')) LIKE :q
                    OR lower(s.surname || ' ' || s.other_names) LIKE :q OR lower(s.other_names || ' ' || s.surname) LIKE :q
                 ORDER BY s.surname, s.other_names LIMIT 20
                """).param("q", needle).query().listOfRows();
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
