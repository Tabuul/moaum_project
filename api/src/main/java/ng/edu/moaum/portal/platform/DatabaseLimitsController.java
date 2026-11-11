package ng.edu.moaum.portal.platform;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import javax.sql.DataSource;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 11 November 2026: the time limits the live database places on the portal's statements, where each was set, the portal's own
 * limits, and the statements stopped since the API started (QueryCancellations) — what the Directorate of ICT reads on its Slow
 * statements page when a screen says it was stopped. The Admissions dashboard's intake was stopped on the live portal although the
 * portal limits screens' reads alone; this says whether the database, its role or the connection carries a statement timeout of
 * its own, and what it stopped.
 *
 * <p>Read on a connection outside any transaction, so the portal's own read limit (set on a read-only transaction) is not mistaken
 * for the database's. Nothing personal: settings, the portal's configuration and the stopped statements' routes.
 */
@RestController
class DatabaseLimitsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final List<String> LIMITS = List.of("statement_timeout", "lock_timeout", "idle_in_transaction_session_timeout",
            "transaction_timeout", "idle_session_timeout");

    private final JdbcClient jdbc;
    private final QueryCancellations cancellations;
    private final PlatformTransactionManager transactions;
    private final ObjectProvider<JdbcTemplate> templates;
    private final DataSource dataSource;
    private final long readLimitMs;

    DatabaseLimitsController(JdbcClient jdbc, QueryCancellations cancellations, PlatformTransactionManager transactions,
                             ObjectProvider<JdbcTemplate> templates, DataSource dataSource,
                             @Value("${moaum.db.request-read-timeout-ms:90000}") long readLimitMs) {
        this.jdbc = jdbc;
        this.cancellations = cancellations;
        this.transactions = transactions;
        this.templates = templates;
        this.dataSource = dataSource;
        this.readLimitMs = readLimitMs;
    }

    @GetMapping("/api/v1/platform/database-limits")
    @PreAuthorize(READERS)
    Map<String, Object> limits() {
        Map<String, Object> out = new LinkedHashMap<>();
        // the settings as a fresh pooled connection holds them, with where each came from (pg_settings.source)
        List<Map<String, Object>> settings = new ArrayList<>(jdbc.sql("""
                SELECT name, setting, unit, source, reset_val, boot_val FROM pg_settings WHERE name IN (:names)
                """).param("names", LIMITS).query().listOfRows());
        settings.sort(java.util.Comparator.comparingInt(r -> LIMITS.indexOf(String.valueOf(r.get("name")))));
        out.put("settings", settings);
        out.put("database", jdbc.sql("""
                SELECT current_database() AS name, current_user AS role, current_setting('server_version') AS version,
                       current_setting('is_superuser') = 'on' AS superuser
                """).query().singleRow());
        // the defaults stated on the database and on the role (ALTER DATABASE / ALTER ROLE … SET), the time limits alone
        try {
            out.put("defaults", jdbc.sql("""
                    SELECT CASE WHEN s.setdatabase = 0 THEN 'role'
                                WHEN s.setrole = 0 THEN 'database'
                                ELSE 'role in database' END AS scope,
                           split_part(c, '=', 1) AS name, substr(c, length(split_part(c, '=', 1)) + 2) AS value
                      FROM pg_db_role_setting s
                      CROSS JOIN LATERAL unnest(s.setconfig) c
                     WHERE (s.setdatabase = 0 OR s.setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database()))
                       AND (s.setrole = 0 OR s.setrole = (SELECT oid FROM pg_roles WHERE rolname = current_user))
                       AND split_part(c, '=', 1) IN (:names)
                     ORDER BY 1, 2
                    """).param("names", LIMITS).query().listOfRows());
        } catch (RuntimeException notReadable) {
            out.put("defaults", null);
            out.put("defaultsUnreadable", "The portal's database role may not read the stated defaults (pg_db_role_setting).");
        }
        // the portal's own limits
        Map<String, Object> portal = new LinkedHashMap<>();
        portal.put("readLimitMs", readLimitMs > 0 ? readLimitMs : null);
        portal.put("transactionTimeoutSeconds", transactions instanceof AbstractPlatformTransactionManager m && m.getDefaultTimeout() > 0
                ? m.getDefaultTimeout() : null);
        JdbcTemplate template = templates.getIfAvailable();
        portal.put("queryTimeoutSeconds", template != null && template.getQueryTimeout() > 0 ? template.getQueryTimeout() : null);
        HikariDataSource hikari = hikari(dataSource);
        portal.put("connectionOptions", hikari == null ? null : options(hikari.getJdbcUrl(), hikari.getDataSourceProperties()));
        portal.put("poolSize", hikari == null ? null : hikari.getMaximumPoolSize());
        out.put("portal", portal);
        out.put("reading", reading(settings, readLimitMs));
        // the statements stopped since the API started, newest first
        List<Map<String, Object>> stopped = new ArrayList<>();
        for (QueryCancellations.Cancellation c : cancellations.latest()) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("at", c.at().toString());
            row.put("cause", c.cause().name());
            row.put("transaction", c.transaction());
            row.put("portalLimitMs", c.portalLimitMs());
            row.put("ranForMs", c.ranForMs());
            row.put("method", c.method());
            row.put("route", c.route());
            row.put("office", c.office());
            row.put("reference", c.reference());
            row.put("databaseSaid", c.databaseSaid());
            stopped.add(row);
        }
        out.put("stopped", stopped);
        out.put("stoppedTotal", cancellations.total());
        out.put("since", cancellations.since().toString());
        return out;
    }

    /** the statement timeout in a sentence: whether the database stops the portal's statements, after how long, set where */
    static String reading(List<Map<String, Object>> settings, long readLimitMs) {
        Map<String, Object> st = settings.stream().filter(r -> "statement_timeout".equals(r.get("name"))).findFirst().orElse(null);
        String portal = readLimitMs > 0
                ? "The portal limits a screen's read to " + ProblemHandler.seconds(readLimitMs) + "; it places no limit on a write."
                : "The portal places no limit of its own on a screen's read or a write.";
        if (st == null) {
            return portal;
        }
        long ms = millis(String.valueOf(st.get("setting")), st.get("unit") == null ? "ms" : String.valueOf(st.get("unit")));
        if (ms <= 0) {
            return "The database places no time limit on one statement of the portal's connections. " + portal;
        }
        return "The database stops any statement of the portal's, read or write, after " + ProblemHandler.seconds(ms)
                + " — set by " + source(String.valueOf(st.get("source"))) + ". " + portal;
    }

    static long millis(String setting, String unit) {
        try {
            long n = Long.parseLong(setting.trim());
            return switch (unit.trim()) {
                case "s" -> n * 1000;
                case "min" -> n * 60_000;
                case "h" -> n * 3_600_000;
                default -> n;
            };
        } catch (NumberFormatException notANumber) {
            return 0;
        }
    }

    /** where a setting came from, in words (pg_settings.source) */
    static String source(String source) {
        return switch (source) {
            case "default" -> "PostgreSQL's default";
            case "configuration file" -> "the database server's configuration (postgresql.conf or ALTER SYSTEM)";
            case "database" -> "a setting on the database (ALTER DATABASE … SET)";
            case "user" -> "a setting on the portal's database role (ALTER ROLE … SET)";
            case "database user" -> "a setting on the portal's role in this database (ALTER ROLE … IN DATABASE … SET)";
            case "client" -> "the connection's own options (the DATABASE_URL's options, or PGOPTIONS)";
            case "session" -> "a setting made on the connection";
            case "environment variable" -> "the database server's environment";
            case "command line" -> "the database server's command line";
            default -> source;
        };
    }

    private static HikariDataSource hikari(DataSource ds) {
        try {
            return ds instanceof HikariDataSource h ? h : ds.isWrapperFor(HikariDataSource.class) ? ds.unwrap(HikariDataSource.class) : null;
        } catch (java.sql.SQLException notWrapped) {
            return null;
        }
    }

    /** the connection's server options alone (the JDBC URL's options= or the driver property), never the URL, which may carry more */
    static String options(String jdbcUrl, java.util.Properties properties) {
        String fromProperty = properties == null ? null : properties.getProperty("options");
        if (fromProperty != null && !fromProperty.isBlank()) {
            return fromProperty;
        }
        if (jdbcUrl == null || !jdbcUrl.contains("?")) {
            return null;
        }
        for (String pair : jdbcUrl.substring(jdbcUrl.indexOf('?') + 1).split("&")) {
            int eq = pair.indexOf('=');
            if (eq > 0 && "options".equalsIgnoreCase(pair.substring(0, eq))) {
                return java.net.URLDecoder.decode(pair.substring(eq + 1), java.nio.charset.StandardCharsets.UTF_8);
            }
        }
        return null;
    }
}
