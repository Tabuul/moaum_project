package ng.edu.moaum.portal.platform;

import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * The University's official identity as the services read it (V320): the one row of
 * {@code platform.institution_profile}, cached for a minute. A notice, a mail header or a report
 * subject names the University through {@link #name()} rather than a string of its own, so a change
 * of name on the Institution Profile reaches every message the portal sends.
 */
@Component
public class Branding {

    /** what the code carried before the profile existed: the fallback when the row cannot be read */
    public static final String DEFAULT_NAME = "Rev. Fr. Moses Orshio Adasu University, Makurdi";
    public static final String DEFAULT_SHORT_NAME = "MOAUM";

    private static volatile Branding instance;

    private final JdbcClient jdbc;
    private volatile Map<String, Object> cached;
    private volatile long cachedAt;

    Branding(JdbcClient jdbc) {
        this.jdbc = jdbc;
        instance = this;
    }

    /** the profile row as a map of its columns, refreshed at most once a minute */
    public Map<String, Object> profile() {
        Map<String, Object> p = cached;
        if (p != null && System.currentTimeMillis() - cachedAt < 60_000) {
            return p;
        }
        try {
            p = jdbc.sql("""
                    SELECT name, short_name, motto, address, city, state, country, phone, email, website,
                           logo_object_id, logo_jpeg_object_id, logo_version, footer_note, show_generated_by, show_page_numbers, date_format, updated_at
                      FROM platform.institution_profile WHERE id
                    """).query().singleRow();
        } catch (RuntimeException unreadable) {
            p = Map.of("name", DEFAULT_NAME, "short_name", DEFAULT_SHORT_NAME);
        }
        cached = p;
        cachedAt = System.currentTimeMillis();
        return p;
    }

    /** forget the cached row: the next read comes from the database — on this bean and on the one the static
     *  readers hold (one and the same in a running service; two in a test JVM that has built several contexts) */
    public void invalidate() {
        cached = null;
        Branding other = instance;
        if (other != null && other != this) {
            other.cached = null;
        }
    }

    private static String field(String column, String fallback) {
        Branding b = instance;
        if (b == null) return fallback;
        Object v = b.profile().get(column);
        return v == null || String.valueOf(v).isBlank() ? fallback : String.valueOf(v);
    }

    /** the University's name, as the profile has it */
    public static String name() {
        return field("name", DEFAULT_NAME);
    }

    /** the University's short name */
    public static String shortName() {
        return field("short_name", DEFAULT_SHORT_NAME);
    }
}
