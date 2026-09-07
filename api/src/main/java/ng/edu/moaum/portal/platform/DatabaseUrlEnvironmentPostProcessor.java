package ng.edu.moaum.portal.platform;

import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;

/**
 * Railway (and Heroku-shaped hosts) hand the database over as one
 * {@code DATABASE_URL} of the form {@code postgres://user:pass@host:port/db}.
 * JDBC wants three properties. This turns the one into the three, and only
 * when {@code spring.datasource.url} has not been set some other way — an
 * explicit setting always wins.
 */
public class DatabaseUrlEnvironmentPostProcessor implements EnvironmentPostProcessor {

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        String databaseUrl = environment.getProperty("DATABASE_URL");
        if (databaseUrl == null || databaseUrl.isBlank()) {
            return;
        }
        Map<String, Object> derived = new HashMap<>();
        URI uri = URI.create(databaseUrl.trim());
        String scheme = uri.getScheme();
        if (scheme == null || !(scheme.equals("postgres") || scheme.equals("postgresql"))) {
            return;
        }
        int port = uri.getPort() == -1 ? 5432 : uri.getPort();
        String database = uri.getPath() == null ? "" : uri.getPath().replaceFirst("^/", "");
        String query = uri.getRawQuery() == null ? "" : "?" + uri.getRawQuery();
        derived.put("spring.datasource.url", "jdbc:postgresql://" + uri.getHost() + ":" + port + "/" + database + query);
        if (uri.getRawUserInfo() != null) {
            String[] parts = uri.getRawUserInfo().split(":", 2);
            derived.put("spring.datasource.username", URLDecoder.decode(parts[0], StandardCharsets.UTF_8));
            if (parts.length == 2) {
                derived.put("spring.datasource.password", URLDecoder.decode(parts[1], StandardCharsets.UTF_8));
            }
        }
        // addLast: application.properties and real environment variables take precedence
        environment.getPropertySources().addLast(new MapPropertySource("databaseUrl", derived));
    }
}
