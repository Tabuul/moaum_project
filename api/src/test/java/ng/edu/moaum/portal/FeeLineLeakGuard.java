package ng.edu.moaum.portal;

import java.net.URI;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.LinkedHashMap;
import java.util.Map;

import org.junit.jupiter.api.extension.AfterAllCallback;
import org.junit.jupiter.api.extension.BeforeAllCallback;
import org.junit.jupiter.api.extension.ExtensionContext;

/**
 * Every integration-test class leaves the fee lines as it found them. A planned session with fees stated is the session a later
 * test's student reads by default, so a fee line one class leaves behind turns another class red at random (StudentPortalIT and
 * PortalWindowsIT, Oct 2026). Registered for every test class (META-INF/services, autodetection in junit-platform.properties):
 * for a class named *IT run against a database, the active fee lines (ended_at IS NULL) are read before the class and after it,
 * and the class fails, naming them, if any it added is still active. Ending a line (ended_at) or deleting it both put it right.
 */
public class FeeLineLeakGuard implements BeforeAllCallback, AfterAllCallback {

    private static final ExtensionContext.Namespace NS = ExtensionContext.Namespace.create(FeeLineLeakGuard.class);

    private static boolean applies(ExtensionContext ctx) {
        String url = System.getenv("DATABASE_URL");
        return url != null && !url.isBlank() && ctx.getTestClass().map(c -> c.getSimpleName().endsWith("IT")).orElse(false);
    }

    /** the active fee lines: id → "session · item" */
    private static Map<String, String> activeLines() throws Exception {
        URI u = URI.create(System.getenv("DATABASE_URL"));
        String[] cred = u.getUserInfo() == null ? new String[] { "", "" } : u.getUserInfo().split(":", 2);
        String jdbc = "jdbc:postgresql://" + u.getHost() + (u.getPort() > 0 ? ":" + u.getPort() : "") + u.getPath();
        Map<String, String> out = new LinkedHashMap<>();
        try (Connection c = DriverManager.getConnection(jdbc, cred[0], cred.length > 1 ? cred[1] : "");
             Statement s = c.createStatement();
             ResultSet r = s.executeQuery("SELECT id::text, session || ' · ' || item FROM finance.fee_schedule WHERE ended_at IS NULL")) {
            while (r.next()) out.put(r.getString(1), r.getString(2));
        }
        return out;
    }

    @Override
    public void beforeAll(ExtensionContext ctx) throws Exception {
        if (!applies(ctx)) return;
        ctx.getStore(NS).put("before", activeLines());
    }

    @Override
    @SuppressWarnings("unchecked")
    public void afterAll(ExtensionContext ctx) throws Exception {
        if (!applies(ctx)) return;
        Map<String, String> before = (Map<String, String>) ctx.getStore(NS).get("before");
        if (before == null) return;
        Map<String, String> left = new LinkedHashMap<>(activeLines());
        left.keySet().removeAll(before.keySet());
        if (!left.isEmpty()) {
            throw new AssertionError(ctx.getRequiredTestClass().getSimpleName() + " left " + left.size() + " fee line(s) active: " + left.values()
                    + ". Delete (or end) the fee lines a test states in an @AfterEach: a planned session with fees stated is the session a later test's student reads by default.");
        }
    }
}
