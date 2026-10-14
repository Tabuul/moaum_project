package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V460: a course's units per programme, set on Programme Structure — which the Director of ICT now keeps too. A programme binds a
 * course at its own units; the structure shows them beside the course's; a change of basis keeps them; the course's own number
 * takes the course's units again; and the programme's students not yet scored are registered at the programme's units.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StructureUnitsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static Map<String, Object> row(ResponseEntity<Map> structure, String code) {
        return ((List<Map<String, Object>>) structure.getBody().get("rows")).stream().filter(r -> code.equals(r.get("code"))).findFirst().orElseThrow();
    }

    private static Map<String, Object> bind(String programme, String course, String basis, Integer units) {
        Map<String, Object> m = new HashMap<>();
        m.put("programme", programme);
        m.put("course", course);
        m.put("level", 100);
        m.put("basis", basis);
        m.put("units", units);
        return m;
    }

    @Test
    void aProgrammeTakesACourseAtItsOwnUnitsAndTheDirectorOfIctKeepsTheStructure() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String tag = UUID.randomUUID().toString().substring(0, 4).toUpperCase().replaceAll("[^A-Z]", "Z");
        String code = "ZZS " + (100 + new java.util.Random().nextInt(800));
        String programme = "C00023";
        it.db(() -> jdbc.sql("""
                INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                VALUES (:c, :t, 3, 1, 100, (SELECT dept_code FROM ref.programme WHERE code = :p), 'Core', 'LIVE')
                ON CONFLICT (code) DO UPDATE SET units = 3
                """).param("c", code).param("t", "Units per programme " + tag).param("p", programme).update());
        String ict = TestTokens.token(it.person("ZZ-ICT-STRUCT", "ZZICTSTRUCT"), List.of("ict"));

        // the Director of ICT binds the course into the programme at 2 units, its own
        ResponseEntity<Map> bound = it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/bind", bind(programme, code, "Core", 2));
        assertThat(bound.getStatusCode().value()).as(String.valueOf(bound.getBody())).isEqualTo(200);
        assertThat(bound.getBody().get("units")).isEqualTo(2);
        Map<String, Object> r = row(it.get(ict, "/api/v1/catalogue/structure?prog=" + programme), code);
        assertThat(r).containsEntry("units", 2).containsEntry("own_units", 2).containsEntry("course_units", 3);

        // a change of basis alone keeps the programme's units
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/bind", bind(programme, code, "Elective", null)).getStatusCode().value()).isEqualTo(200);
        r = row(it.get(ict, "/api/v1/catalogue/structure?prog=" + programme), code);
        assertThat(r).containsEntry("basis", "Elective").containsEntry("units", 2);

        // the course's own number takes the course's units again
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/bind", bind(programme, code, "Elective", 3)).getStatusCode().value()).isEqualTo(200);
        r = row(it.get(ict, "/api/v1/catalogue/structure?prog=" + programme), code);
        assertThat(r).containsEntry("units", 3);
        assertThat(r.get("own_units")).isNull();

        // the Director of ICT keeps the structure, but does not edit the course itself
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/catalogue/courses/" + code,
                Map.of("title", "x", "units", 4, "semester", 1, "level", 100)).getStatusCode().value()).isEqualTo(403);
        it.db(() -> jdbc.sql("DELETE FROM catalogue.course_offer WHERE course_code = :c").param("c", code).update());
    }
}
