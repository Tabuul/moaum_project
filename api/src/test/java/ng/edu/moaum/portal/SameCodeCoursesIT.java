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
 * V646: one course code, different titles — separate courses, through the API. The Academic Office creates CSC 401 Computer
 * Networks (CCMAS); the New course check says the code carries it and that another title is a separate course; Advanced Computer
 * Systems under the same code is created as its own course (key … BMAS) and the same code and title is refused; the structure
 * upload's preview lists a row of another title, the upload refuses it until the row says, and a separate course is created when it
 * does; the Duplicate course code report lists the courses under the code; the Registry makes a separate course and moves the
 * programme to it, a Head of Department cannot; the course list finds every course under the code. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SameCodeCoursesIT {

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

    @Test
    void oneCodeCarriesSeparateCoursesTellsThemApartAndNeverWritesOneTitleOverAnother() {
        // a code of the run's own: Z and two letters, 401
        String hex = UUID.randomUUID().toString().replaceAll("[^a-f]", "").toUpperCase() + "ABCDEF";
        String code = "Z" + hex.substring(0, 2) + " 401";
        String dept = it.db(() -> jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single());

        Map<String, Object> first = ok(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses",
                Map.of("code", code, "title", "Computer Networks", "units", 3, "semester", 1, "level", 400, "dept", dept, "kind", "Core", "curriculum", "CCMAS")));
        assertThat(first.get("code")).isEqualTo(code);

        // the check before a course is created: the code carries Computer Networks; another title is a separate course
        Map<String, Object> exists = ok(it.get(academic, "/api/v1/catalogue/courses/exists?code=" + code + "&title=Advanced Computer Systems"));
        assertThat(exists.get("byCode")).isNull();
        assertThat((List<Map>) exists.get("underCode")).extracting(r -> r.get("title")).containsExactly("Computer Networks");

        Map<String, Object> second = ok(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses",
                Map.of("code", code, "title", "Advanced Computer Systems", "units", 3, "semester", 1, "level", 400, "dept", dept, "kind", "Core", "curriculum", "BMAS")));
        assertThat(second.get("code")).isEqualTo(code + " BMAS");
        ResponseEntity<Map> same = it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses",
                Map.of("code", code, "title", "computer networks", "units", 3, "semester", 1, "level", 400, "dept", dept, "kind", "Core"));
        assertThat(same.getStatusCode().is4xxClientError()).as(String.valueOf(same.getBody())).isTrue();
        assertThat(String.valueOf(same.getBody())).contains("already exists");
        assertThat(jdbc.sql("SELECT string_agg(title, ' / ' ORDER BY code) FROM catalogue.course WHERE catalogue.shown_code(code) = :c").param("c", code)
                .query(String.class).single()).isEqualTo("Computer Networks / Advanced Computer Systems");

        // the structure upload: a row of another title previewed, refused until it says, created as a separate course when it does
        Map<String, Object> row = Map.of("code", code.replace(" ", ""), "title", "Computer Architecture", "units", "3", "level", "400", "semester", "1", "status", "C");
        ResponseEntity<List> titles = it.callList(ict, HttpMethod.POST, "/api/v1/catalogue/import/titles",
                Map.of("groups", List.of(Map.of("programme", PROGRAMME, "rows", List.of(row)))));
        assertThat(titles.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map>) titles.getBody()).singleElement().satisfies(t -> {
            assertThat(t.get("code")).isEqualTo(code);
            assertThat((List<Map>) t.get("held")).hasSize(2);
        });
        ResponseEntity<Map> undecided = it.call(ict, HttpMethod.POST, "/api/v1/catalogue/import", Map.of("programme", PROGRAMME, "rows", List.of(row), "curriculum", "CCMAS"));
        assertThat(undecided.getStatusCode().value()).isEqualTo(422);
        assertThat(undecided.getBody().get("code")).isEqualTo("COURSE_TITLE_DIFFERS");
        Map<String, Object> separate = new java.util.HashMap<>(row);
        separate.put("titleChoice", "SEPARATE");
        ok(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/import", Map.of("programme", PROGRAMME, "rows", List.of(separate), "curriculum", "CCMAS")));
        assertThat(jdbc.sql("SELECT title FROM catalogue.course WHERE code = :c").param("c", code + " CCMAS").query(String.class).single()).isEqualTo("Computer Architecture");
        assertThat(jdbc.sql("SELECT title FROM catalogue.course WHERE code = :c").param("c", code).query(String.class).single()).isEqualTo("Computer Networks");

        // the Duplicate course code report lists the three; the course list finds them all under the code
        ResponseEntity<List> report = it.getList(academic, "/api/v1/catalogue/same-code");
        assertThat(report.getStatusCode().value()).isEqualTo(200);
        assertThat(((List<Map>) report.getBody()).stream().filter(r -> code.equals(r.get("shown_code"))).toList()).hasSize(3)
                .allSatisfy(r -> assertThat(((Number) r.get("courses_under_code")).intValue()).isEqualTo(3));
        Map<String, Object> list = ok(it.get(academic, "/api/v1/catalogue/courses/list?q=" + code));
        assertThat((List<Map>) list.get("rows")).extracting(r -> r.get("code")).contains(code, code + " BMAS", code + " CCMAS");

        // the Registry makes a separate course under the code and moves the programme to it; a Head of Department cannot
        it.db(() -> jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, 400, 'Core') ON CONFLICT DO NOTHING")
                .param("c", code).param("p", PROGRAMME).update());
        String hod = it.officer("hod", "department", dept);
        Map<String, Object> body = Map.of("title", "Data Communications", "curriculum", "BMAS", "bindings", List.of(Map.of("programme", PROGRAMME, "level", 400)),
                "reason", "The BMAS students take their own course");
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/catalogue/courses/" + code + "/separate", body).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> done = ok(it.call(registrar, HttpMethod.POST, "/api/v1/catalogue/courses/" + code + "/separate", body));
        assertThat(done).containsEntry("code", code + " BMAS2").containsEntry("shownCode", code).containsEntry("bindingsMoved", 1);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course_offer WHERE course_code = :c AND programme_code = :p AND level = 400").param("c", code + " BMAS2").param("p", PROGRAMME)
                .query(Integer.class).single()).isEqualTo(1);
    }
}
