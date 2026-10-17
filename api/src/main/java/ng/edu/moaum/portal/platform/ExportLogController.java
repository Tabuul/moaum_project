package ng.edu.moaum.portal.platform;

import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import tools.jackson.databind.ObjectMapper;

/**
 * V523: the export log. The portal's export engine (frontend lib/exportbrand) records each report it hands a signed-in person —
 * the report, Excel or print / PDF, the rows, the filters, the screen and the document's serial — and the database records it for
 * the person and office of the request's audit context (platform.log_export), never for whoever the screen names. Internal Audit,
 * the Deputy Director of Audit and super read the log. V529: an export is unusual when it is large or one of many by the same person
 * in a short time (platform.export_watch, set by Internal Audit or super); Internal Audit is told of it as it is recorded, and the
 * list marks it and finds it.
 */
@RestController
@RequestMapping("/api/v1/exports")
@Validated
class ExportLogController {

    static final String READERS = "hasAnyAuthority('OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";
    static final String WATCH_SETTERS = "hasAnyAuthority('OFFICE_audit','OFFICE_super')";

    private final JdbcClient jdbc;
    private final ObjectMapper json;

    ExportLogController(JdbcClient jdbc, ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    public record WatchIn(boolean enabled, @Min(10) @Max(1_000_000) int largeRows, @Min(2) @Max(1000) int burstCount,
                          @Min(5) @Max(1440) int burstMinutes) {
    }

    public record ExportIn(@NotBlank @Size(max = 300) String report, @NotBlank @Size(max = 10) String format, @Min(0) int rows,
                           Map<String, Object> filters, @Size(max = 2000) String screen, @Size(max = 120) String serial) {
    }

    /** an export, as the screen made it; anyone signed in, each for themselves */
    @PostMapping
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> record(@Valid @RequestBody ExportIn in) {
        UUID id = jdbc.sql("SELECT platform.log_export(:r, :f, :n, CAST(:j AS jsonb), :s, :z)")
                .param("r", in.report()).param("f", in.format()).param("n", in.rows())
                .param("j", json.writeValueAsString(in.filters() == null ? Map.of() : in.filters()))
                .param("s", in.screen(), Types.VARCHAR).param("z", in.serial(), Types.VARCHAR)
                .query(UUID.class).single();
        return Map.of("id", id);
    }

    /** the log, newest first: a range of days (Lagos), an office, a format, and words found in the report, the person, the
     *  number, the screen or the serial */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                             @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                             @RequestParam(required = false) String office, @RequestParam(required = false) String format,
                             @RequestParam(required = false) String q, @RequestParam(defaultValue = "false") boolean unusual,
                             @RequestParam(defaultValue = "1") @Min(1) int page, @RequestParam(defaultValue = "50") @Min(1) @Max(500) int size) {
        String where = """
                  FROM platform.export_log l
                  LEFT JOIN iam.person p ON p.id = l.person_id
                  LEFT JOIN LATERAL (SELECT st.matric_no, st.admission_no, st.surname || ', ' || st.other_names AS name
                                       FROM people.student st WHERE st.person_id = l.person_id LIMIT 1) st ON true
                 WHERE (CAST(:from AS date) IS NULL OR l.at >= (CAST(:from AS date)::timestamp AT TIME ZONE 'Africa/Lagos'))
                   AND (CAST(:to AS date) IS NULL OR l.at < ((CAST(:to AS date) + 1)::timestamp AT TIME ZONE 'Africa/Lagos'))
                   AND (CAST(:office AS text) IS NULL OR l.office = CAST(:office AS text))
                   AND (CAST(:format AS text) IS NULL OR l.format = upper(CAST(:format AS text)))
                   AND (NOT CAST(:unusual AS boolean) OR EXISTS (SELECT 1 FROM platform.export_unusual(l.id) u WHERE u.large OR u.burst))
                   AND (CAST(:q AS text) IS NULL
                        OR l.report ILIKE '%' || CAST(:q AS text) || '%' OR l.serial ILIKE '%' || CAST(:q AS text) || '%'
                        OR l.screen ILIKE '%' || CAST(:q AS text) || '%'
                        OR coalesce(p.surname || ', ' || p.given_names, st.name, '') ILIKE '%' || CAST(:q AS text) || '%'
                        OR coalesce(p.staff_number, st.matric_no, st.admission_no, '') ILIKE '%' || CAST(:q AS text) || '%')
                """;
        String o = blank(office);
        String f = blank(format);
        String w = blank(q);
        long total = jdbc.sql("SELECT count(*)" + where)
                .param("from", from, Types.DATE).param("to", to, Types.DATE).param("office", o, Types.VARCHAR)
                .param("format", f, Types.VARCHAR).param("q", w, Types.VARCHAR).param("unusual", unusual).query(Long.class).single();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT l.id, l.at, l.person_id, coalesce(p.surname || ', ' || p.given_names, st.name) AS name,
                       coalesce(p.staff_number, st.matric_no, st.admission_no) AS number, l.office, o.label AS office_label,
                       l.report, l.format, l.row_count, l.filters::text AS filters, l.screen, l.serial,
                       coalesce((SELECT u.large FROM platform.export_unusual(l.id) u), false) AS large,
                       coalesce((SELECT u.burst FROM platform.export_unusual(l.id) u), false) AS burst
                """ + where.replace("LEFT JOIN iam.person p ON p.id = l.person_id",
                        "LEFT JOIN iam.person p ON p.id = l.person_id\n  LEFT JOIN ref.office o ON o.code = l.office") + """
                 ORDER BY l.at DESC, l.id
                 LIMIT :size OFFSET :offset
                """)
                .param("from", from, Types.DATE).param("to", to, Types.DATE).param("office", o, Types.VARCHAR)
                .param("format", f, Types.VARCHAR).param("q", w, Types.VARCHAR).param("unusual", unusual)
                .param("size", size).param("offset", (long) (page - 1) * size).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("total", total);
        out.put("page", page);
        out.put("size", size);
        out.put("offices", jdbc.sql("""
                SELECT l.office AS code, coalesce(o.label, l.office) AS label, count(*) AS exports
                  FROM platform.export_log l LEFT JOIN ref.office o ON o.code = l.office
                 GROUP BY l.office, o.label ORDER BY 2
                """).query().listOfRows());
        out.put("watch", watch());
        return out;
    }

    /** V529: what makes an export unusual, and who set it last */
    @GetMapping("/watch")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> watch() {
        return jdbc.sql("""
                SELECT w.enabled, w.large_rows, w.burst_count, w.burst_minutes, w.updated_at, w.updated_office,
                       p.surname || ', ' || p.given_names AS updated_by_name
                  FROM platform.export_watch w LEFT JOIN iam.person p ON p.id = w.updated_by WHERE w.id = 1
                """).query().singleRow();
    }

    /** V529: Internal Audit (or super) sets the watch; the change, with its reason, is on the audit spine */
    @PutMapping("/watch")
    @PreAuthorize(WATCH_SETTERS)
    @Transactional
    Map<String, Object> setWatch(@Valid @RequestBody WatchIn in) {
        jdbc.sql("""
                UPDATE platform.export_watch
                   SET enabled = :e, large_rows = :l, burst_count = :c, burst_minutes = :m,
                       updated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
                       updated_office = nullif(current_setting('moaum.actor_office', true), ''), updated_at = now()
                 WHERE id = 1
                """).param("e", in.enabled()).param("l", in.largeRows()).param("c", in.burstCount()).param("m", in.burstMinutes()).update();
        return watch();
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
