package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
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
 * One course held once (V386), through the API: the twins the pool already holds (made with the guard off, as the old
 * portal's data was) are listed with the code to keep; a Head of Department previews the merge and cannot make it; the
 * Registry merges with a reason, and the old code opens the course kept with its alias; the pool refuses the old code as a
 * new course; a course may be taught in both semesters (never with the third) and is listed in each; the programme-structure
 * upload binds the course held however its code is written. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseMergeIT {

    static final String PROGRAMME = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String ict = ItSupport.token("ict");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    @Test
    void theTwinsAreMergedIntoTheCourseKeptAndACourseMayBeTaughtInBothSemesters() {
        // a prefix of the run's own: Z and two letters
        String hex = UUID.randomUUID().toString().replaceAll("[^a-f]", "").toUpperCase() + "ABCDEF";
        String p = "Z" + hex.substring(0, 2);
        String twin = p + "101";
        String keep = p + " 101";
        String dept = it.db(() -> jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single());
        String hod = it.officer("hod", "department", dept);
        it.db(() -> {
            jdbc.sql("ALTER TABLE catalogue.course DISABLE TRIGGER trg_course_code_guard").update();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    VALUES (:t, 'Merge Check', 2, 1, 100, :d, 'Core', 'LIVE'), (:k, 'Merge Check', 2, 1, 100, :d, 'Core', 'LIVE')
                    """).param("t", twin).param("k", keep).param("d", dept).update();
            jdbc.sql("ALTER TABLE catalogue.course ENABLE TRIGGER trg_course_code_guard").update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:t, :p, 100, 'Core'), (:t, :p, 200, 'Core'), (:k, :p, 100, 'Core')")
                    .param("t", twin).param("k", keep).param("p", PROGRAMME).update();
            return null;
        });

        // (1) the twins listed, the clean code to keep
        List<Map<String, Object>> dups = (List<Map<String, Object>>) it.callList(academic, HttpMethod.GET, "/api/v1/catalogue/duplicate-codes", null).getBody();
        Map<String, Object> pair = dups.stream().filter(d -> twin.equals(d.get("merge_code"))).findFirst().orElseThrow();
        assertThat(pair.get("keep_code")).isEqualTo(keep);
        assertThat(pair.get("evidence")).isEqualTo("SAME_CODE_WRITTEN_DIFFERENTLY");

        // (2) the Head of Department previews; only the Academic Office or the Registry merges, and with a reason
        Map<String, Object> preview = ok(it.call(hod, HttpMethod.POST, "/api/v1/catalogue/courses/merge/preview", Map.of("keep", keep, "merge", twin)));
        assertThat(preview.get("blocked")).isNull();
        assertThat(((Map) preview.get("moved")).get("bindingsAlreadyHeld")).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :t").param("t", twin).query(Long.class).single()).isEqualTo(1L);
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/catalogue/courses/merge", Map.of("keep", keep, "merge", twin, "reason", "x")).getStatusCode().value()).isEqualTo(403);
        assertThat(code(it.call(registrar, HttpMethod.POST, "/api/v1/catalogue/courses/merge", Map.of("keep", keep, "merge", twin)))).isEqualTo("MERGE_REASON");
        Map<String, Object> merged = ok(it.call(registrar, HttpMethod.POST, "/api/v1/catalogue/courses/merge",
                Map.of("keep", keep, "merge", twin, "reason", "the old portal wrote it without its space")));
        assertThat(merged.get("evidence")).isEqualTo("SAME_CODE_WRITTEN_DIFFERENTLY");

        // (3) the old code opens the course kept, which carries the binding it lacked and the alias
        Map<String, Object> detail = ok(it.get(academic, "/api/v1/catalogue/courses/" + twin + "/detail"));
        assertThat(((Map) detail.get("course")).get("code")).isEqualTo(keep);
        assertThat(((List<Map<String, Object>>) detail.get("aliases")).stream().map(a -> a.get("alias_code"))).containsExactly(twin);
        assertThat(((List<Map<String, Object>>) detail.get("offers")).stream().map(o -> o.get("level"))).contains(100, 200);

        // (4) the pool refuses the old code, or the code written another way, as a new course
        ResponseEntity<Map> again = it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses",
                Map.of("code", p + "-101", "title", "Merge Check", "units", 2, "semester", 1, "level", 100, "dept", dept, "kind", "Core"));
        assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(422);

        // (5) taught in both semesters, listed in each; never with the third
        Map<String, Object> both = ok(it.call(academic, HttpMethod.PUT, "/api/v1/catalogue/courses/" + keep,
                Map.of("title", "Merge Check", "units", 2, "semester", 1, "level", 100, "kind", "Core", "bothSemesters", true)));
        assertThat(both.get("both_semesters")).isEqualTo(true);
        Map<String, Object> second = ok(it.get(academic, "/api/v1/catalogue/courses/list?q=" + p + "&semester=2"));
        assertThat(((List<Map<String, Object>>) second.get("rows")).stream().map(r -> r.get("code"))).contains(keep);
        assertThat(code(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses",
                Map.of("code", p + " 309", "title", "Merge Third", "units", 2, "semester", 3, "level", 300, "dept", dept, "kind", "Core", "bothSemesters", true))))
                .isEqualTo("CAT_SEMESTER_BOTH");

        // (6) the structure upload binds the course held however its code is written, and reads "Both"
        ok(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/import", Map.of("programme", PROGRAMME, "rows", List.of(
                Map.of("code", p.toLowerCase() + "-101", "title", "Merge Check", "units", "2", "level", "300", "semester", "Both", "status", "C"),
                Map.of("code", p + " 205", "title", "Merge Upload Both", "units", "3", "level", "200", "semester", "1 & 2", "status", "C")))));
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course WHERE catalogue.code_key(code) = :k").param("k", p + "101").query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course_offer WHERE course_code = :k AND programme_code = :p AND level = 300")
                .param("k", keep).param("p", PROGRAMME).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT both_semesters FROM catalogue.course WHERE code = :c").param("c", p + " 205").query(Boolean.class).single()).isTrue();
    }
}
