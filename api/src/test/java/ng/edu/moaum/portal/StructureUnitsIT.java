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

        // the review's report lists the course, with the programme at its own units
        List<Map<String, Object>> report = (List<Map<String, Object>>) (List<?>) it.getList(ict, "/api/v1/catalogue/units-by-programme").getBody();
        Map<String, Object> mine = report.stream().filter(x -> code.equals(x.get("code"))).findFirst().orElseThrow();
        assertThat(mine).containsEntry("courseUnits", 3);
        assertThat((List<Map<String, Object>>) mine.get("programmes")).anySatisfy(x ->
                assertThat(x).containsEntry("programme", programme).containsEntry("units", 2).containsEntry("own", true));

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

        // the structure upload's preview says, before anything loads, that the programme would take the course at the file's
        // units and the course stays at its own — and lists nothing where the file agrees with what the programme takes now
        Map<String, Object> group = Map.of("programme", programme, "rows", List.of(Map.of("code", code, "units", "2", "level", "100")));
        ResponseEntity<Map> preview = it.call(ict, HttpMethod.POST, "/api/v1/catalogue/import/units", Map.of("groups", List.of(group)));
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        List<Map<String, Object>> changes = (List<Map<String, Object>>) preview.getBody().get("rows");
        assertThat(changes).hasSize(1);
        assertThat(changes.get(0)).containsEntry("change", "PROGRAMME_OWN").containsEntry("fileUnits", 2).containsEntry("courseUnits", 3).containsEntry("nowUnits", 3);
        Map<String, Object> same = Map.of("programme", programme, "rows", List.of(Map.of("code", code, "units", "3", "level", "100")));
        assertThat((List<?>) it.call(ict, HttpMethod.POST, "/api/v1/catalogue/import/units", Map.of("groups", List.of(same))).getBody().get("rows")).isEmpty();

        // V464: the review's Change — what setting the programme's units would reach, counted first; then set, basis kept;
        // the course's own number takes the course's units again; a programme that does not take the course is not found
        ResponseEntity<Map> impact = it.get(ict, b -> b.path("/api/v1/catalogue/structure/units-impact").queryParam("programme", programme)
                .queryParam("course", code).queryParam("level", 100).queryParam("units", 2).build());
        assertThat(impact.getStatusCode().value()).as(String.valueOf(impact.getBody())).isEqualTo(200);
        assertThat(impact.getBody()).containsEntry("nowUnits", 3).containsEntry("newUnits", 2).containsEntry("follow", 0).containsEntry("kept", 0);
        ResponseEntity<Map> set = it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/units", Map.of("programme", programme, "course", code, "level", 100, "units", 2));
        assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
        assertThat(set.getBody()).containsEntry("units", 2).containsEntry("followed", 0);
        r = row(it.get(ict, "/api/v1/catalogue/structure?prog=" + programme), code);
        assertThat(r).containsEntry("basis", "Elective").containsEntry("units", 2).containsEntry("own_units", 2);
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/units", Map.of("programme", programme, "course", code, "level", 100, "units", 3))
                .getBody()).containsEntry("units", 3);
        assertThat(row(it.get(ict, "/api/v1/catalogue/structure?prog=" + programme), code).get("own_units")).isNull();
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/units", Map.of("programme", programme, "course", code, "level", 300, "units", 2))
                .getStatusCode().value()).isEqualTo(404);
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/structure/units", Map.of("programme", programme, "course", code, "level", 100, "units", 13))
                .getStatusCode().value()).isEqualTo(400);
        it.db(() -> jdbc.sql("DELETE FROM catalogue.course_offer WHERE course_code = :c").param("c", code).update());
    }
}
