package ng.edu.moaum.portal.reports;

import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import ng.edu.moaum.portal.platform.NoticeRepository;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.databind.ObjectMapper;

/**
 * Reports as evidence (V229): the due register — what is due, when, and whether a copy answers it —
 * and the snapshots kept when a return is run: the rows as they were, who took them, the verification
 * code the printed footing carries, and the act of filing. The register itself stays the source of
 * every live figure; a snapshot is the record of what was filed.
 */
@RestController
@RequestMapping("/api/v1/reports")
class SnapshotsController {

    /** every office that takes a return may keep one and read the due register */
    private static final String READERS =
            "hasAnyAuthority('OFFICE_vc','OFFICE_dvc','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records',"
            + "'OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_hrm','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_pgschool','OFFICE_pgsecretary')";

    private static final ObjectMapper JSON = new ObjectMapper();

    @Value("${moaum.portal-url:https://moaum-portal-production.up.railway.app}")
    private String portalUrl;

    private final JdbcClient jdbc;
    private final NoticeRepository notices;

    SnapshotsController(JdbcClient jdbc, NoticeRepository notices) {
        this.jdbc = jdbc;
        this.notices = notices;
    }

    public record FileIn2(@NotBlank String filename, @NotBlank String contentType, @NotBlank String base64) {
    }

    public record EmailIn(@NotNull List<String> to, String message, @NotNull List<FileIn2> attachments) {
    }

    /**
     * Email a kept return to the people it is for, with the files attached (the PDF and the Excel
     * workbook the portal built from the kept rows). One notice per recipient, queued in this
     * transaction against the snapshot, so the kept copy lists every dispatch and its state.
     */
    @PostMapping("/snapshots/{id}/email")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> email(Authentication authentication, @PathVariable UUID id, @Valid @RequestBody EmailIn body) {
        Map<String, Object> s = one(id);
        List<String> to = body.to().stream().map(String::trim).filter(t -> t.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")).distinct().toList();
        if (to.isEmpty()) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Give at least one email address");
        if (to.size() > 20) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "At most twenty recipients at a time");
        List<NoticeRepository.Attachment> files = new java.util.ArrayList<>();
        long total = 0;
        for (FileIn2 f : body.attachments()) {
            byte[] bytes = java.util.Base64.getDecoder().decode(f.base64());
            total += bytes.length;
            if (total > 15_000_000L) throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE, "The attachments exceed 15 MB");
            files.add(new NoticeRepository.Attachment(f.filename().replaceAll("[/\\\\]", "-"), f.contentType(), bytes));
        }
        String subject = s.get("title") + " · " + s.get("period") + " — Rev. Fr. Moses Orshio Adasu University";
        String text = "Please find attached the " + s.get("title") + " for " + s.get("period") + ", kept by the portal on "
                + String.valueOf(s.get("taken_at")).substring(0, 10) + " (" + s.get("row_count") + " rows).\n\n"
                + (body.message() == null || body.message().isBlank() ? "" : body.message().trim() + "\n\n")
                + "Verification code: " + s.get("verification_code") + "\n"
                + "The figures on the attached copy can be checked against what the University kept at "
                + portalUrl + "/verify/report/" + s.get("verification_code") + "\n";
        List<Map<String, Object>> queued = new java.util.ArrayList<>();
        for (String r : to) {
            UUID nid = notices.queueEmail(r, subject, text, "report_snapshot", id, files);
            queued.add(Map.of("notice", nid, "to", r));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("queued", queued);
        out.put("attachments", files.stream().map(f -> Map.of("filename", f.filename(), "bytes", f.content().length)).toList());
        return out;
    }

    /** the emails a kept copy went out by, newest first */
    @GetMapping("/snapshots/{id}/dispatches")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> dispatches(@PathVariable UUID id) {
        return jdbc.sql("""
                SELECT n.id, n.recipient, n.subject, n.state, n.created_at, n.sent_at, n.last_error,
                       (SELECT string_agg(a.filename, ', ' ORDER BY a.created_at) FROM platform.notice_attachment a WHERE a.notice_id = n.id) AS files
                  FROM platform.notice n WHERE n.about_kind = 'report_snapshot' AND n.about_id = :id
                 ORDER BY n.created_at DESC
                """).param("id", id).query().listOfRows();
    }

    /** the due register as at today (or the day asked for): one row per return */
    @GetMapping("/due")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> due(@RequestParam(required = false) String asAt) {
        LocalDate day = asAt == null || asAt.isBlank() ? LocalDate.now() : LocalDate.parse(asAt.trim());
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM reports.due_register(:d)").param("d", day).query().listOfRows();
        long overdue = rows.stream().filter(r -> "OVERDUE".equals(r.get("state"))).count();
        long dueSoon = rows.stream().filter(r -> "DUE".equals(r.get("state")) && r.get("days") != null && ((Number) r.get("days")).intValue() <= 30).count();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("asAt", day.toString());
        out.put("rows", rows);
        out.put("overdue", overdue);
        out.put("dueSoon", dueSoon);
        return out;
    }

    public record KeepIn(@NotBlank String report, @NotBlank String title, String subtitle, @NotBlank String period,
                         Map<String, Object> parameters, String dueOn,
                         @NotNull List<String> headers, @NotNull List<List<Object>> rows, Map<String, Object> totals, String note) {
    }

    /** keep a copy of a return as it was run: returns the snapshot id and its verification code */
    @PostMapping("/snapshots")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> keep(Authentication authentication, @Valid @RequestBody KeepIn body) {
        UUID me = UUID.fromString(authentication.getName());
        String office = AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
        LocalDate due = body.dueOn() == null || body.dueOn().isBlank() ? null : LocalDate.parse(body.dueOn().trim());
        Map<String, Object> row = jdbc.sql("""
                INSERT INTO reports.snapshot (report, title, subtitle, period, parameters, due_on, headers, rows, totals, row_count, note, taken_by, taken_office)
                VALUES (:report, :title, :subtitle, :period, :parameters::jsonb, :due, :headers::jsonb, :rows::jsonb, :totals::jsonb, :n, :note, :by, :office)
                RETURNING id, verification_code, taken_at
                """)
                .param("report", body.report().trim()).param("title", body.title().trim())
                .param("subtitle", body.subtitle(), Types.VARCHAR).param("period", body.period().trim())
                .param("parameters", JSON.writeValueAsString(body.parameters() == null ? Map.of() : body.parameters()))
                .param("due", due, Types.DATE)
                .param("headers", JSON.writeValueAsString(body.headers()))
                .param("rows", JSON.writeValueAsString(body.rows()))
                .param("totals", body.totals() == null ? null : JSON.writeValueAsString(body.totals()), Types.VARCHAR)
                .param("n", body.rows().size()).param("note", body.note(), Types.VARCHAR)
                .param("by", me).param("office", office, Types.VARCHAR)
                .query().singleRow();
        return row;
    }

    /** the snapshots kept, newest first — for one return, or all */
    @GetMapping("/snapshots")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> list(@RequestParam(required = false) String report, @RequestParam(defaultValue = "50") int limit) {
        String r = report == null || report.isBlank() ? null : report.trim();
        return jdbc.sql("""
                SELECT s.id, s.report, s.title, s.period, s.due_on, s.row_count, s.taken_at, s.taken_office, s.verification_code,
                       s.filed_to, s.filed_at,
                       trim(coalesce(p.surname, '') || ' ' || coalesce(p.given_names, '')) AS taken_by_name,
                       trim(coalesce(f.surname, '') || ' ' || coalesce(f.given_names, '')) AS filed_by_name
                  FROM reports.snapshot s
                  LEFT JOIN iam.person p ON p.id = s.taken_by
                  LEFT JOIN iam.person f ON f.id = s.filed_by
                 WHERE (:r::text IS NULL OR s.report = :r)
                 ORDER BY s.taken_at DESC LIMIT :lim
                """).param("r", r, Types.VARCHAR).param("lim", Math.max(1, Math.min(500, limit))).query().listOfRows();
    }

    /** one snapshot, whole — headers, rows and totals as kept */
    @GetMapping("/snapshots/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> one(@PathVariable UUID id) {
        return jdbc.sql("""
                SELECT s.id, s.report, s.title, s.subtitle, s.period, s.parameters::text AS parameters, s.due_on,
                       s.headers::text AS headers, s.rows::text AS rows, s.totals::text AS totals, s.row_count, s.note,
                       s.taken_at, s.taken_office, s.verification_code, s.filed_to, s.filed_at, s.filed_note,
                       trim(coalesce(p.surname, '') || ' ' || coalesce(p.given_names, '')) AS taken_by_name,
                       trim(coalesce(f.surname, '') || ' ' || coalesce(f.given_names, '')) AS filed_by_name
                  FROM reports.snapshot s
                  LEFT JOIN iam.person p ON p.id = s.taken_by
                  LEFT JOIN iam.person f ON f.id = s.filed_by
                 WHERE s.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such snapshot"));
    }

    public record FileIn(@NotBlank String filedTo, String note) {
    }

    /** record that a kept return was filed — with whom, and any note */
    @PostMapping("/snapshots/{id}/file")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> file(Authentication authentication, @PathVariable UUID id, @Valid @RequestBody FileIn body) {
        UUID me = UUID.fromString(authentication.getName());
        int n = jdbc.sql("""
                UPDATE reports.snapshot SET filed_to = :to, filed_at = now(), filed_by = :by, filed_note = :note
                 WHERE id = :id AND filed_at IS NULL
                """).param("to", body.filedTo().trim()).param("by", me).param("note", body.note(), Types.VARCHAR).param("id", id).update();
        if (n == 0) throw new ResponseStatusException(HttpStatus.CONFLICT, "This snapshot is already filed, or does not exist");
        return one(id);
    }
}
