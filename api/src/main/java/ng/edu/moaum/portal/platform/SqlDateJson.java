package ng.edu.moaum.portal.platform;

import tools.jackson.core.JsonGenerator;
import tools.jackson.databind.SerializationContext;
import tools.jackson.databind.ValueSerializer;
import tools.jackson.databind.module.SimpleModule;

import org.springframework.boot.jackson.autoconfigure.JsonMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * A Postgres {@code date} column read through JdbcClient arrives as a {@link java.sql.Date} at midnight in the server's own
 * time zone. Left to itself Jackson writes it as that instant in UTC, so on a server whose clock zone is ahead of UTC —
 * Lagos is an hour ahead — 15 October went out as {@code 2026-10-14T23:00:00.000Z} and every screen showed the day before
 * (found on a receipt's day paid, V480). A date is a calendar day: it is written as one, {@code 2026-10-15}, whatever the
 * server's zone. On a server in UTC the browser reads the same day as before.
 */
@Configuration
class SqlDateJson {

    /** the module, apart from the bean, so a test can hold the mapper to it */
    static SimpleModule module() {
        SimpleModule module = new SimpleModule("sql-dates");
        module.addSerializer(java.sql.Date.class, new ValueSerializer<java.sql.Date>() {
            @Override
            public void serialize(java.sql.Date value, JsonGenerator gen, SerializationContext ctxt) {
                gen.writeString(value.toLocalDate().toString());
            }
        });
        return module;
    }

    @Bean
    JsonMapperBuilderCustomizer sqlDates() {
        SimpleModule module = module();
        return builder -> builder.addModule(module);
    }
}
