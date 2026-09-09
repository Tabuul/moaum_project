package ng.edu.moaum.portal.platform;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * What is actually true about this service — the same questions
 * {@code web/server.js} answers on {@code /healthz}, so that the two can be
 * compared: which migrations are applied, and whether the admission settings
 * for the coming session are a draft or in force.
 */
@RestController
@RequestMapping("/api/v1/platform")
class PlatformController {

    private static final Instant STARTED = Instant.now();

    private final JdbcClient jdbc;
    private final String commit;

    PlatformController(JdbcClient jdbc, @Value("${moaum.commit:${RAILWAY_GIT_COMMIT_SHA:}}") String commit) {
        this.jdbc = jdbc;
        this.commit = commit;
    }

    @GetMapping("/status")
    Map<String, Object> status() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("service", "portal-api");
        body.put("commit", commit == null || commit.isBlank() ? null : commit);
        body.put("startedAt", STARTED.toString());
        body.put("database", database());
        return body;
    }

    /** the migration ledger: what has been applied to this database, in order */
    @GetMapping("/migrations")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')")
    Map<String, Object> migrations() {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT filename, sha256, applied_at, applied_by FROM public.schema_migration ORDER BY filename
                """).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("count", rows.size());
        out.put("latest", rows.isEmpty() ? null : rows.get(rows.size() - 1).get("filename"));
        out.put("commit", commit == null || commit.isBlank() ? null : commit);
        out.put("startedAt", STARTED.toString());
        out.put("migrations", rows);
        return out;
    }

    private Map<String, Object> database() {
        Map<String, Object> db = new LinkedHashMap<>();
        try {
            Map<String, Object> row = jdbc.sql("""
                    SELECT (SELECT count(*) FROM public.schema_migration)            AS applied,
                           (SELECT max(filename) FROM public.schema_migration)       AS latest,
                           (SELECT state FROM admissions.session_policy
                             WHERE session = '2025/2026')                            AS admission_settings
                    """).query().singleRow();
            db.put("reachable", true);
            db.put("migrationsApplied", row.get("applied"));
            db.put("latestMigration", row.get("latest"));
            db.put("admissionSettings2025_2026", row.get("admission_settings") == null ? "absent" : row.get("admission_settings"));
        } catch (DataAccessException e) {
            db.put("reachable", false);
            db.put("why", e.getMostSpecificCause().getMessage());
        }
        return db;
    }
}
