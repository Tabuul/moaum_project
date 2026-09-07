package ng.edu.moaum.portal.platform;

import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;

import org.springframework.boot.jdbc.autoconfigure.JdbcConnectionDetails;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.context.annotation.Conditional;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.type.AnnotatedTypeMetadata;

/**
 * Railway (and Heroku-shaped hosts) hand the database over as one
 * {@code DATABASE_URL} of the form {@code postgres://user:pass@host:port/db}.
 * When it is present it is the truth about where the database is, so it is
 * offered as {@link JdbcConnectionDetails}, which Spring Boot prefers over
 * the {@code spring.datasource.*} properties. Without it, the properties
 * (and their local defaults) apply.
 */
@Configuration
class DatabaseUrlConfig {

    static final String VARIABLE = "DATABASE_URL";

    @Bean
    @Conditional(DatabaseUrlPresent.class)
    JdbcConnectionDetails railwayDatabase(Environment environment) {
        return parse(environment.getProperty(VARIABLE));
    }

    static JdbcConnectionDetails parse(String databaseUrl) {
        URI uri = URI.create(databaseUrl.trim());
        String scheme = uri.getScheme();
        if (scheme == null || !(scheme.equals("postgres") || scheme.equals("postgresql"))) {
            throw new IllegalStateException(VARIABLE + " is not a postgres:// URL");
        }
        int port = uri.getPort() == -1 ? 5432 : uri.getPort();
        String database = uri.getPath() == null ? "" : uri.getPath().replaceFirst("^/", "");
        String query = uri.getRawQuery() == null ? "" : "?" + uri.getRawQuery();
        String jdbcUrl = "jdbc:postgresql://" + uri.getHost() + ":" + port + "/" + database + query;
        String username = null;
        String password = null;
        if (uri.getRawUserInfo() != null) {
            String[] parts = uri.getRawUserInfo().split(":", 2);
            username = URLDecoder.decode(parts[0], StandardCharsets.UTF_8);
            password = parts.length == 2 ? URLDecoder.decode(parts[1], StandardCharsets.UTF_8) : null;
        }
        final String user = username;
        final String pass = password;
        return new JdbcConnectionDetails() {
            @Override
            public String getJdbcUrl() {
                return jdbcUrl;
            }

            @Override
            public String getUsername() {
                return user;
            }

            @Override
            public String getPassword() {
                return pass;
            }
        };
    }

    /** True when {@code DATABASE_URL} is set and non-blank. */
    static class DatabaseUrlPresent implements Condition {
        @Override
        public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
            String value = context.getEnvironment().getProperty(VARIABLE);
            return value != null && !value.isBlank();
        }
    }
}
