package ng.edu.moaum.portal.transfers;

import java.sql.Types;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

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
 * V727: the old portal's inter-departmental transfers continued here. The reconciliation list of its transfer payments
 * (people.legacy_transfer_payment: LINKED to an application, AWAITING_APPLICATION, USED — paid for the transfer the old portal
 * approved, restored here, never a credit for another — UNMATCHED with the reason, NOT_COUNTED, OUT_OF_SCOPE, REJECTED) and an
 * officer's decision on a row; the scope — from which date its payments count and which of its
 * items count; the upload of its export, checked first and then committed, each row an application at the stage it reached (or
 * joined to the student's application here); the loads; and the reconciliation report. The rules are the database's, which checks
 * the office again: the Academic Office, the Registry, the Bursary or ICT decide and state the scope; the Academic Office, the
 * Registry or ICT load the export.
 */
@RestController
@RequestMapping("/api/v1/transfers/legacy")
class TransferLegacyController {

    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar','OFFICE_studentaccounts','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    static final String DECIDERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar','OFFICE_ict','OFFICE_super')";
    static final String LOADERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    static final Set<String> STATUSES = Set.of("LINKED", "AWAITING_APPLICATION", "USED", "UNMATCHED", "NOT_COUNTED", "OUT_OF_SCOPE", "REJECTED");

    /** the list's rows: the payment, the student, the application it counts toward, the student's live application (the one a
     *  LINK names by default) and the decision; filtered by search alone, the status applied by the caller */
    private static final String ROWS = """
            WITH x AS MATERIALIZED (
                SELECT l.payment_id, l.student_id, s.matric_no, s.surname || ', ' || s.other_names AS name, s.status AS student_status,
                       s.programme_code, p.name AS programme, p.dept_code,
                       l.session_label, l.item, l.item_kind, l.amount, l.payref, l.paid_on, l.channel, l.status, l.match_method,
                       l.application_id, t.state AS application_state, tp.name AS application_to_programme, lg.legacy_ref,
                       r.reference, r.archived_at IS NOT NULL AS archived,
                       l.reason, l.moved_hint, l.decided_at, l.decided_office, l.decided_note, l.decided_by, l.built_at,
                       lv.id AS live_application_id, lv.state AS live_application_state
                  FROM people.legacy_transfer_payment l
                  JOIN finance.payment_reference r ON r.id = l.payment_id
                  LEFT JOIN people.student s ON s.id = l.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN people.transfer_application t ON t.id = l.application_id
                  LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
                  LEFT JOIN people.transfer_legacy lg ON lg.application_id = l.application_id
                  LEFT JOIN LATERAL (SELECT a.id, a.state FROM people.transfer_application a
                                      WHERE a.student_id = l.student_id AND a.state = ANY (people.transfer_live_states()) LIMIT 1) lv ON true
                 WHERE CAST(:q AS text) IS NULL
                    OR lower(concat_ws(' ', s.matric_no, s.surname, s.other_names, l.payref, r.reference, l.item)) LIKE CAST(:q AS text))
            """;

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    TransferLegacyController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String like(String search) {
        String s = blank(search);
        if (s == null) return null;
        if (s.length() > 80) s = s.substring(0, 80);
        return "%" + s.toLowerCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
    }

    /** the counts by status, every status named (0 when none) */
    private static Map<String, Object> counts(List<Map<String, Object>> grouped, String key, String value, List<String> order) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (String s : order) m.put(s, 0);
        for (Map<String, Object> g : grouped) m.put(String.valueOf(g.get(key)), ((Number) g.get(value)).intValue());
        return m;
    }

    private static final List<String> STATUS_ORDER = List.of("LINKED", "AWAITING_APPLICATION", "USED", "UNMATCHED", "NOT_COUNTED", "OUT_OF_SCOPE", "REJECTED");

    /** the reconciliation list, the status and the search applied; the counts by status with the search alone, so each stays a door */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String status, @RequestParam(required = false) String search,
                             @RequestParam(defaultValue = "1000") int limit) {
        String st = blank(status) == null ? null : status.trim().toUpperCase();
        if (st != null && "ALL".equals(st)) st = null;
        if (st != null && !STATUSES.contains(st)) {
            throw new DomainRuleViolation("LEGACY_TRANSFER_STATUS", "'" + status + "' is not a status of the reconciliation list.",
                    new DomainRuleViolation.Remedy("Choose Linked, Awaiting application, Used, Unmatched, Not counted, Out of scope or Rejected, or leave it for all.", "You"));
        }
        int n = Math.max(1, Math.min(limit, 5000));
        String q = like(search);
        List<Map<String, Object>> rows = jdbc.sql(ROWS + """
                SELECT count(*) OVER () AS total_rows, x.*, helpdesk.person_name(x.decided_by) AS decided_by_name
                  FROM x WHERE CAST(:st AS text) IS NULL OR x.status = CAST(:st AS text)
                 ORDER BY x.paid_on DESC NULLS LAST, x.name, x.payref LIMIT :n
                """).param("q", q, Types.VARCHAR).param("st", st, Types.VARCHAR).param("n", n).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        List<Map<String, Object>> grouped = jdbc.sql(ROWS + "SELECT x.status, count(*) AS n FROM x GROUP BY x.status")
                .param("q", q, Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("counts", counts(grouped, "status", "n", STATUS_ORDER));
        out.put("total", total);
        out.put("limit", n);
        return out;
    }

    public record Decision(@NotBlank @Pattern(regexp = "LINK|NOT_COUNTED|REJECT|RELEASE") String decision, UUID application, @Size(max = 600) String note) {
    }

    /** an officer's decision on a row (link it to an application of the same student, not counted, reject, release to the rule),
     *  with a reason — kept, and the list never rebuilt over it */
    @PostMapping("/{paymentId}/decision")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID paymentId, @Valid @RequestBody Decision body) {
        boolean listed = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.legacy_transfer_payment WHERE payment_id = :p)")
                .param("p", paymentId).query(Boolean.class).single());
        if (!listed) {
            throw new NotFound("old-portal transfer payment", paymentId.toString());
        }
        if ("LINK".equals(body.decision()) && body.application() == null) {
            throw new DomainRuleViolation("LEGACY_TRANSFER_APPLICATION", "A payment is linked to an application: name it.",
                    new DomainRuleViolation.Remedy("Choose the student's transfer application.", "You"));
        }
        AuditContext ctx = AuditContextHolder.required();
        String status = jdbc.sql("SELECT people.decide_legacy_transfer_payment(:p, :d, :a, :n, :actor, :office)")
                .param("p", paymentId).param("d", body.decision()).param("a", body.application(), Types.OTHER)
                .param("n", body.note(), Types.VARCHAR).param("actor", ctx.actorId()).param("office", ctx.actorOffice())
                .query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("paymentId", paymentId);
        out.put("status", status);
        return out;
    }

    /** the list built again from the records (all students): safe to run again; a decided row is kept */
    @PostMapping("/reconcile")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> reconcile() {
        List<Map<String, Object>> grouped = jdbc.sql("SELECT * FROM people.legacy_transfer_reconcile(NULL)").query().listOfRows();
        return Map.of("statuses", counts(grouped, "status", "payments", STATUS_ORDER));
    }

    /* ── the scope: from which date the old portal's payments count, and which of its items ── */

    @GetMapping("/scope")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> scope() {
        Map<String, Object> s = jdbc.sql("""
                SELECT s.counts_from, s.set_at, s.set_by, helpdesk.person_name(s.set_by) AS set_by_name, s.set_office, s.reason
                  FROM people.legacy_transfer_setting s WHERE s.id = 1
                """).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("countsFrom", s.get("counts_from"));
        out.put("setAt", s.get("set_at"));
        out.put("setBy", s.get("set_by_name"));
        out.put("setOffice", s.get("set_office"));
        out.put("reason", s.get("reason"));
        out.put("items", jdbc.sql("SELECT i.item, i.kind, i.counts, i.reason FROM people.legacy_transfer_item i ORDER BY i.counts DESC, i.kind, i.item")
                .query().listOfRows());
        return out;
    }

    public record Scope(@NotBlank @Pattern(regexp = "\\d{4}-\\d{2}-\\d{2}") String countsFrom, @Size(max = 600) String reason) {
    }

    /** the date from which the old portal's transfer payments count, stated with a reason; the list is built again */
    @PutMapping("/scope")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> setScope(@Valid @RequestBody Scope body) {
        LocalDate from;
        try {
            from = LocalDate.parse(body.countsFrom().trim());
        } catch (DateTimeParseException e) {
            throw new DomainRuleViolation("LEGACY_TRANSFER_SCOPE", "The date is not a date.",
                    new DomainRuleViolation.Remedy("Pick the date from which the old portal's transfer payments count.", "You"));
        }
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("SELECT people.set_legacy_transfer_scope(:d, :r, :actor, :office)")
                .param("d", java.sql.Date.valueOf(from), Types.DATE).param("r", body.reason(), Types.VARCHAR)
                .param("actor", ctx.actorId()).param("office", ctx.actorOffice()).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(scope());
        List<Map<String, Object>> grouped = jdbc.sql("SELECT l.status, count(*) AS n FROM people.legacy_transfer_payment l GROUP BY l.status").query().listOfRows();
        out.put("statuses", counts(grouped, "status", "n", STATUS_ORDER));
        return out;
    }

    /* ── the old portal's export: checked, then committed ── */

    public record Rows(@NotNull @Size(min = 1, max = 2000) List<Map<String, Object>> rows) {
    }

    public record Upload(@NotNull @Size(min = 1, max = 2000) List<Map<String, Object>> rows, @Size(max = 200) String filename, Boolean partial) {
    }

    private static final List<String> CHECK_ORDER = List.of("NEW", "ATTACH", "EXISTS", "ALREADY_MOVED", "FROM_MISMATCH", "CONFLICT", "NOT_ELIGIBLE",
            "NO_STUDENT", "OUT_OF_SCOPE", "DUPLICATE_ROW", "INVALID");

    /** each row read without writing: what would become of it (NEW, ATTACH, EXISTS … INVALID) and why */
    @PostMapping("/upload/check")
    @PreAuthorize(LOADERS)
    @Transactional(readOnly = true)
    Map<String, Object> check(@Valid @RequestBody Rows body) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT c.*, s.surname || ', ' || s.other_names AS name, s.programme_code AS from_programme_code, fp.name AS from_programme,
                       tp.name AS to_programme
                  FROM people.legacy_transfer_upload_check(CAST(:j AS jsonb)) c
                  LEFT JOIN people.student s ON s.id = c.student_id
                  LEFT JOIN ref.programme fp ON fp.code = s.programme_code
                  LEFT JOIN ref.programme tp ON tp.code = c.to_programme_code
                 ORDER BY c.row_no
                """).param("j", json.writeValueAsString(body.rows())).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("counts", tally(rows, CHECK_ORDER));
        return out;
    }

    /** the export loaded: each NEW row an application at the stage the old portal reached, ATTACH joined to the student's application
     *  here, the payments its payment numbers name counted toward it; refused whole while a row cannot be loaded, unless partial */
    @PostMapping("/upload")
    @PreAuthorize(LOADERS)
    @Transactional
    Map<String, Object> commit(@Valid @RequestBody Upload body) {
        AuditContext ctx = AuditContextHolder.required();
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM people.legacy_transfer_upload_commit(CAST(:j AS jsonb), :f, :p, :actor, :office) ORDER BY row_no")
                .param("j", json.writeValueAsString(body.rows())).param("f", blank(body.filename()), Types.VARCHAR)
                .param("p", Boolean.TRUE.equals(body.partial())).param("actor", ctx.actorId()).param("office", ctx.actorOffice())
                .query().listOfRows();
        // the load the function recorded: this transaction's (now() is the transaction's moment), by this officer
        Map<String, Object> load = jdbc.sql("""
                SELECT l.id, l.filename, l.rows_read, l.loaded, l.attached, l.left_out
                  FROM people.legacy_transfer_load l WHERE l.committed_by = :actor AND l.committed_at = now()
                 ORDER BY l.id LIMIT 1
                """).param("actor", ctx.actorId()).query().listOfRows().stream().findFirst().orElse(Map.of());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("loadId", load.get("id"));
        out.put("filename", load.get("filename"));
        out.put("rowsRead", load.get("rows_read"));
        out.put("loaded", load.get("loaded"));
        out.put("attached", load.get("attached"));
        out.put("leftOut", load.get("left_out"));
        out.put("counts", tally(rows, CHECK_ORDER));
        out.put("rows", rows);
        return out;
    }

    private static Map<String, Object> tally(List<Map<String, Object>> rows, List<String> order) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (String s : order) m.put(s, 0);
        for (Map<String, Object> r : rows) m.merge(String.valueOf(r.get("status")), 1, (a, b) -> ((Number) a).intValue() + ((Number) b).intValue());
        return m;
    }

    /** the loads, newest first */
    @GetMapping("/loads")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> loads() {
        return jdbc.sql("""
                SELECT l.id, l.filename, l.rows_read, l.loaded, l.attached, l.left_out, l.committed_at, l.committed_by,
                       helpdesk.person_name(l.committed_by) AS committed_by_name, l.committed_office
                  FROM people.legacy_transfer_load l ORDER BY l.committed_at DESC, l.id LIMIT 500
                """).query().listOfRows();
    }

    /** the reconciliation report, read from the records as they stand — every key the database's report gives, passed through as given
     *  (paymentsUsed, studentsAwaitingApplication, creditAwaitingApplication, owedWhenTheyApply, studentsOwingWhenTheyApply,
     *  payerApplicationsLive, outstandingOldPortalPayers — the balance still owed on the live applications of old-portal payers — among them) */
    @GetMapping("/report")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> report() {
        String text = jdbc.sql("SELECT people.legacy_transfer_report()::text").query(String.class).single();
        @SuppressWarnings("unchecked")
        Map<String, Object> m = json.readValue(text, Map.class);
        return m;
    }
}
