package ng.edu.moaum.portal.platform;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.Map;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
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
 * V546: the live database's own slowest statements (pg_stat_statements), each named with the portal's functions it calls and the
 * screens known to issue it — what the live portal records, not a copy on another machine. Read-only; where the statistics are
 * not available here the answer says why. V555: over the last days by the daily snapshots (StatementSnapshots), and reset by ICT.
 */
@RestController
@RequestMapping("/api/v1/platform/slow-statements")
class SlowStatementsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String WRITERS = "hasAnyAuthority('OFFICE_ict','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    SlowStatementsController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    @SuppressWarnings("unchecked")
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> statements(@RequestParam(defaultValue = "MEAN") String order, @RequestParam(defaultValue = "5") int minCalls,
                                   @RequestParam(defaultValue = "100") int limit, @RequestParam(required = false) Integer days) {
        String o = switch (order.trim().toUpperCase()) { case "TOTAL", "MAX", "CALLS" -> order.trim().toUpperCase(); default -> "MEAN"; };
        Integer d = days == null || days <= 0 ? null : Math.min(days, 35);
        String text = jdbc.sql("SELECT platform.slow_statements(:o, :m, :l, :d)::text").param("o", o).param("m", Math.max(1, minCalls))
                .param("l", Math.max(1, Math.min(limit, 500))).param("d", d, java.sql.Types.INTEGER).query(String.class).single();
        Map<String, Object> out = new java.util.LinkedHashMap<>(json.readValue(text, Map.class));
        out.put("screens", jdbc.sql("SELECT function_name, screens, note, set_at FROM platform.statement_screen ORDER BY function_name").query().listOfRows());
        // V555: the last resets, and the statements told to ICT as turned slow
        out.put("resets", jdbc.sql("SELECT reset_at, office, reason FROM platform.statement_reset ORDER BY reset_at DESC LIMIT 5").query().listOfRows());
        out.put("alerts", jdbc.sql("""
                SELECT a.day, a.mean_ms, a.before_ms, a.calls, left(regexp_replace(s.query, '\\s+', ' ', 'g'), 300) AS query
                  FROM platform.statement_alert a
                  LEFT JOIN LATERAL (SELECT x.query FROM platform.statement_snapshot x WHERE x.queryid = a.queryid ORDER BY x.taken_at DESC LIMIT 1) s ON true
                 WHERE a.day >= current_date - 14 ORDER BY a.day DESC, a.mean_ms DESC LIMIT 20
                """).query().listOfRows());
        return out;
    }

    public record ResetIn(@NotBlank @Size(min = 5, max = 300) String reason) {
    }

    /** V555: this database's statement statistics reset by ICT, with the reason — the counts start again from now */
    @PostMapping("/reset")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> reset(@Valid @RequestBody ResetIn body) {
        return json.readValue(jdbc.sql("SELECT platform.reset_statement_stats(:r)::text").param("r", body.reason().trim()).query(String.class).single(), Map.class);
    }

    public record ScreenIn(@NotBlank @Size(max = 300) String screens, @Size(max = 300) String note) {
    }

    /** the screens a function is known to be called from, for naming its statements */
    @PutMapping("/screens/{function}")
    @PreAuthorize(WRITERS)
    @Transactional
    Map<String, Object> screen(@PathVariable String function, @Valid @RequestBody ScreenIn body) {
        String f = function.trim().toLowerCase();
        if (!f.matches("[a-z_]+\\.[a-z_0-9]+")) {
            throw new DomainRuleViolation("STATEMENT_SCREEN_FUNCTION", "Name the function as schema.name, e.g. finance.day_book.",
                    new DomainRuleViolation.Remedy("Use the name the statement shows.", "ICT"));
        }
        jdbc.sql("""
                INSERT INTO platform.statement_screen (function_name, screens, note) VALUES (:f, :s, :n)
                ON CONFLICT (function_name) DO UPDATE SET screens = excluded.screens, note = excluded.note, set_at = now()
                """).param("f", f).param("s", body.screens().trim()).param("n", body.note() == null || body.note().isBlank() ? null : body.note().trim(), java.sql.Types.VARCHAR)
                .update();
        return Map.of("function", f, "screens", body.screens().trim(), "list",
                jdbc.sql("SELECT function_name, screens, note, set_at FROM platform.statement_screen ORDER BY function_name").query().listOfRows());
    }
}
