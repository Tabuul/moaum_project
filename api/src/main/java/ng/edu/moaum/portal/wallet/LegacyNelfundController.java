package ng.edu.moaum.portal.wallet;

import java.sql.Types;
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
 * The old portal's NELFUND payments reconciled onto the wallet (V327). The Bursary stages the old portal's export as it
 * is; the portal matches each row to a current student by strong identifiers only, judges it by status, amount and
 * session, and shows the counts before anything is written — a dry run writes nothing. On the Bursary's word the
 * matched rows are posted to the students' wallets as NELFUND credits of the session they name, once, carrying the old
 * reference and the old date. What cannot be reconciled waits in the queue with its reason for a Finance officer to
 * match on evidence or reject.
 */
@RestController
@RequestMapping("/api/v1/nelfund/legacy")
class LegacyNelfundController {

    private static final String VIEWERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_audit','OFFICE_deputyaudit','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String BURSARY = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_super')";
    private static final Set<String> STATUSES = Set.of("UNPROCESSED", "MATCHED", "POSTED", "REQUIRES_REVIEW", "REJECTED", "DUPLICATE", "UNMATCHED");
    private static final Set<String> ACTIONS = Set.of("match", "reject");
    private static final int MAX_ROWS = 50_000;

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    LegacyNelfundController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record ImportIn(@NotNull @Size(max = MAX_ROWS) List<Map<String, Object>> rows, @Size(max = 200) String fileName, @Size(max = 9) String session,
                           Boolean dryRun, @Size(max = 500) String note) {
    }

    public record ResolveIn(UUID studentId, @Size(max = 1000) String reason) {
    }

    @GetMapping("/summary")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String session) {
        String s = blank(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("summary", jdbc.sql("SELECT * FROM finance.legacy_nelfund_summary(NULL, :s)").param("s", s, Types.VARCHAR).query().singleRow());
        out.put("exceptions", exceptions(null, s));
        out.put("imports", recentImports(20));
        out.put("sessions", jdbc.sql("""
                SELECT lp.session, count(*) AS rows, count(*) FILTER (WHERE rc.status = 'POSTED') AS posted,
                       count(*) FILTER (WHERE rc.status IN ('REQUIRES_REVIEW', 'UNMATCHED')) AS open, coalesce(sum(lp.amount) FILTER (WHERE lp.normalized_status = 'SUCCESS'), 0) AS amount
                  FROM finance.legacy_nelfund_payment lp JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = lp.id
                 GROUP BY lp.session ORDER BY lp.session DESC NULLS LAST
                """).query().listOfRows());
        return out;
    }

    private List<Map<String, Object>> exceptions(UUID importId, String session) {
        return jdbc.sql("""
                SELECT rc.status, coalesce(rc.reason_code, '') AS code, count(*) AS n, coalesce(sum(lp.amount), 0) AS amount
                  FROM finance.legacy_nelfund_reconciliation rc JOIN finance.legacy_nelfund_payment lp ON lp.id = rc.payment_id
                 WHERE (:i::uuid IS NULL OR rc.import_id = :i) AND (:s::text IS NULL OR lp.session = :s) AND rc.status <> 'POSTED'
                 GROUP BY rc.status, rc.reason_code ORDER BY rc.status, n DESC
                """).param("i", importId, Types.OTHER).param("s", session, Types.VARCHAR).query().listOfRows();
    }

    private List<Map<String, Object>> recentImports(int limit) {
        return jdbc.sql("""
                SELECT i.*, CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS uploaded_by_name,
                       (SELECT count(*) FROM finance.legacy_nelfund_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'POSTED') AS posted,
                       (SELECT count(*) FROM finance.legacy_nelfund_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'MATCHED') AS matched,
                       (SELECT count(*) FROM finance.legacy_nelfund_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'REQUIRES_REVIEW') AS requires_review,
                       (SELECT count(*) FROM finance.legacy_nelfund_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'UNMATCHED') AS unmatched,
                       (SELECT count(*) FROM finance.legacy_nelfund_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'DUPLICATE') AS duplicates,
                       (SELECT count(*) FROM finance.legacy_nelfund_reconciliation rc WHERE rc.import_id = i.id AND rc.status = 'REJECTED') AS rejected,
                       (SELECT coalesce(sum(e.amount), 0) FROM finance.legacy_nelfund_reconciliation rc JOIN finance.wallet_entry e ON e.id = rc.wallet_entry_id WHERE rc.import_id = i.id AND rc.status = 'POSTED') AS posted_amount
                  FROM finance.legacy_nelfund_import i LEFT JOIN iam.person p ON p.id = i.uploaded_by
                 ORDER BY i.uploaded_at DESC LIMIT :n
                """).param("n", limit).query().listOfRows();
    }

    /* ── a run: staged, matched and validated at once; posted to the wallets only on apply; a dry run writes nothing ── */

    @PostMapping("/imports")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> stage(@Valid @RequestBody ImportIn in) {
        if (in.rows().isEmpty()) {
            throw new DomainRuleViolation("LEGACY_ROWS_REQUIRED", "The file has no payment rows to read.", new DomainRuleViolation.Remedy("Upload the old portal's NELFUND payment export.", "Bursary"));
        }
        boolean dry = Boolean.TRUE.equals(in.dryRun());
        UUID id = jdbc.sql("SELECT (finance.legacy_nelfund_new_import(:f, :s, :n)).id")
                .param("f", blank(in.fileName()), Types.VARCHAR).param("s", blank(in.session()), Types.VARCHAR).param("n", blank(in.note()), Types.VARCHAR).query(UUID.class).single();
        Map<String, Object> staged = jdbc.sql("SELECT * FROM finance.legacy_nelfund_stage(:i, :j::jsonb)").param("i", id).param("j", mapper.writeValueAsString(in.rows())).query().singleRow();
        jdbc.sql("SELECT finance.legacy_nelfund_match(:i)").param("i", id).query(Integer.class).single();
        jdbc.sql("SELECT finance.legacy_nelfund_validate(:i)").param("i", id).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(one(id, null, null, 1, 500));
        out.put("staging", staged);
        out.put("dryRun", dry);
        if (dry) {
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
        Map<String, Object> imp = jdbc.sql("SELECT * FROM finance.legacy_nelfund_import WHERE id = :id").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("import", id.toString()));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("import", imp);
        out.put("summary", jdbc.sql("SELECT * FROM finance.legacy_nelfund_summary(:i, NULL)").param("i", id).query().singleRow());
        out.put("exceptions", exceptions(id, null));
        out.putAll(rows(id, status, null, q, page, size));
        return out;
    }

    @PostMapping("/imports/{id}/apply")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> apply(@PathVariable UUID id) {
        Map<String, Object> applied = jdbc.sql("SELECT * FROM finance.legacy_nelfund_apply(:i)").param("i", id).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(one(id, null, null, 1, 100));
        out.put("applied", applied);
        return out;
    }

    /* ── the rows ── */

    private static final String ROW_SQL = """
            SELECT lp.id, lp.import_id, i.reference AS import_reference, lp.row_no, lp.source_system, lp.source_transaction_id, lp.source_reference,
                   lp.source_student_id, lp.matric_no, lp.jamb_no, lp.application_no, lp.student_name,
                   lp.amount, lp.currency, lp.paid_at, lp.paid_at_text, lp.session, lp.legacy_status, lp.normalized_status, lp.imported_at,
                   rc.status, rc.reason_code, rc.reason, rc.student_id, rc.match_method, rc.match_confidence, rc.candidates::text AS candidates,
                   rc.wallet_entry_id, rc.posted_at, rc.posted_office, rc.resolved_at, rc.resolved_office, rc.override_reason,
                   s.surname, s.other_names, coalesce(s.matric_no, s.admission_no) AS number, s.programme_code, s.current_level AS level,
                   e.reference AS wallet_reference, e.at AS wallet_at, e.session AS wallet_session,
                   CASE WHEN pb.id IS NULL THEN NULL ELSE pb.surname || ', ' || pb.given_names END AS posted_by_name
              FROM finance.legacy_nelfund_payment lp
              JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = lp.id
              JOIN finance.legacy_nelfund_import i ON i.id = lp.import_id
              LEFT JOIN people.student s ON s.id = rc.student_id
              LEFT JOIN finance.wallet_entry e ON e.id = rc.wallet_entry_id
              LEFT JOIN iam.person pb ON pb.id = rc.posted_by
            """;
    private static final String ROW_WHERE = """
             WHERE (:i::uuid IS NULL OR lp.import_id = :i)
               AND (:st::text IS NULL OR rc.status = :st OR (:st = 'OPEN' AND rc.status IN ('REQUIRES_REVIEW', 'UNMATCHED')))
               AND (:s::text IS NULL OR lp.session = :s)
               AND (:q::text IS NULL OR lower(coalesce(lp.source_reference, '')) LIKE :q OR lower(coalesce(lp.source_transaction_id, '')) LIKE :q
                    OR lower(coalesce(lp.matric_no, '')) LIKE :q OR lower(coalesce(lp.jamb_no, '')) LIKE :q OR lower(coalesce(lp.application_no, '')) LIKE :q OR lower(coalesce(lp.student_name, '')) LIKE :q
                    OR lower(coalesce(s.surname || ' ' || s.other_names, '')) LIKE :q OR lower(coalesce(s.matric_no, '')) LIKE :q OR lower(coalesce(s.jamb_reg_no, '')) LIKE :q
                    OR lower(coalesce(e.reference, '')) LIKE :q OR lp.amount::text = :raw)
            """;

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, UUID importId, String status, String session, String q) {
        String like = q == null ? null : "%" + q.toLowerCase() + "%";
        return spec.param("i", importId, Types.OTHER).param("st", status, Types.VARCHAR).param("s", session, Types.VARCHAR)
                .param("q", like, Types.VARCHAR).param("raw", q == null ? "" : q, Types.VARCHAR);
    }

    private Map<String, Object> rows(UUID importId, String status, String session, String q, int page, int size) {
        String st = blank(status);
        if (st != null && !"OPEN".equals(st) && !STATUSES.contains(st)) {
            throw new DomainRuleViolation("LEGACY_STATUS_UNKNOWN", "No reconciliation status is called " + st + ".", new DomainRuleViolation.Remedy("One of " + String.join(", ", STATUSES) + ", or OPEN.", "Bursary"));
        }
        int sz = Math.max(1, Math.min(size, 500)); int pg = Math.max(1, page);
        String qq = blank(q);
        long total = bind(jdbc.sql("SELECT count(*) FROM finance.legacy_nelfund_payment lp JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = lp.id LEFT JOIN people.student s ON s.id = rc.student_id LEFT JOIN finance.wallet_entry e ON e.id = rc.wallet_entry_id " + ROW_WHERE),
                importId, st, session, qq).query(Long.class).single();
        List<Map<String, Object>> list = bind(jdbc.sql(ROW_SQL + ROW_WHERE + " ORDER BY CASE rc.status WHEN 'REQUIRES_REVIEW' THEN 0 WHEN 'UNMATCHED' THEN 1 WHEN 'MATCHED' THEN 2 ELSE 3 END, lp.row_no LIMIT :l OFFSET :o"),
                importId, st, session, qq).param("l", sz).param("o", (pg - 1) * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", list);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    @GetMapping("/rows")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> search(@RequestParam(required = false) UUID importId, @RequestParam(required = false) String status, @RequestParam(required = false) String session,
                               @RequestParam(required = false) String q, @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "100") int size) {
        return rows(importId, status, blank(session), q, page, size);
    }

    @GetMapping("/rows/{id}")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> row(@PathVariable UUID id) {
        Map<String, Object> r = jdbc.sql(ROW_SQL + " WHERE lp.id = :id").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("old-portal NELFUND payment", id.toString()));
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("raw", jdbc.sql("SELECT raw::text FROM finance.legacy_nelfund_payment WHERE id = :id").param("id", id).query(String.class).single());
        return out;
    }

    @PostMapping("/rows/{id}/{action}")
    @PreAuthorize(BURSARY)
    @Transactional
    Map<String, Object> resolve(@PathVariable UUID id, @PathVariable String action, @RequestBody(required = false) ResolveIn in) {
        if (!ACTIONS.contains(action)) {
            throw new DomainRuleViolation("LEGACY_ACTION_UNKNOWN", "An old-portal payment is matched or rejected.", new DomainRuleViolation.Remedy("match or reject", "Bursary"));
        }
        UUID student = in == null ? null : in.studentId();
        String reason = in == null ? null : blank(in.reason());
        jdbc.sql("SELECT finance.legacy_nelfund_resolve(:p, :a, :s, :r)").param("p", id).param("a", action.toUpperCase()).param("s", student, Types.OTHER).param("r", reason, Types.VARCHAR).query().singleRow();
        return row(id);
    }

    @GetMapping("/students")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> students(@RequestParam String q) {
        String like = "%" + q.trim().toLowerCase() + "%";
        return jdbc.sql("""
                SELECT s.id, s.surname || ', ' || s.other_names AS name, coalesce(s.matric_no, s.admission_no) AS number, s.jamb_reg_no, s.programme_code, s.current_level AS level, s.status
                  FROM people.student s
                 WHERE lower(s.surname || ' ' || s.other_names) LIKE :q OR lower(coalesce(s.matric_no, '')) LIKE :q OR lower(coalesce(s.admission_no, '')) LIKE :q OR lower(coalesce(s.jamb_reg_no, '')) LIKE :q
                 ORDER BY s.surname, s.other_names LIMIT 20
                """).param("q", like).query().listOfRows();
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
