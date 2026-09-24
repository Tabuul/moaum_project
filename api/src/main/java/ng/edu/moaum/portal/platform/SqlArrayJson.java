package ng.edu.moaum.portal.platform;

import java.sql.Array;
import java.sql.SQLException;

import tools.jackson.core.JsonGenerator;
import tools.jackson.databind.SerializationContext;
import tools.jackson.databind.ValueSerializer;
import tools.jackson.databind.module.SimpleModule;

import org.springframework.boot.jackson.autoconfigure.JsonMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * A Postgres array column read through JdbcClient arrives as a {@link java.sql.Array} (a PgArray). Left to
 * itself Jackson serialises it as a bean — {@code {"array": [...], "baseType": ..., "resultSet": ...}} — and
 * fails part-way through the result set, after the 200 has already been written, so the screen receives a
 * cut body. Every such column is written as the plain JSON array it is.
 */
@Configuration
class SqlArrayJson {

    @Bean
    JsonMapperBuilderCustomizer sqlArrays() {
        SimpleModule module = new SimpleModule("sql-arrays");
        module.addSerializer(Array.class, new ValueSerializer<Array>() {
            @Override
            public void serialize(Array value, JsonGenerator gen, SerializationContext ctxt) {
                Object[] items;
                try {
                    Object raw = value.getArray();
                    items = raw instanceof Object[] o ? o : new Object[0];
                } catch (SQLException e) {
                    items = new Object[0];
                }
                gen.writeStartArray();
                for (Object item : items) {
                    if (item == null) gen.writeNull();
                    else ctxt.writeValue(gen, item);
                }
                gen.writeEndArray();
            }
        });
        return builder -> builder.addModule(module);
    }
}
