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
import ng.edu.moaum.portal.shared.AuditContextHolder;
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

    private final JdbcClient jdbc;

    SnapshotsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
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
