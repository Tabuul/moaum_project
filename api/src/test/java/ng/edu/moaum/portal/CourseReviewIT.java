package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V445: the ownership review — the list searched by title, by the owner's department name and by "200 level"; a course marked
 * by the Academic Office and by its own Head (another department's Head refused; an incorrect owner needs a note); the owner
 * corrected in bulk — previewed, refused without a reason and by the Bursary, applied in one act on the trail; the history
 * reading the title change and the owner change; possible duplicates by title; the review's dashboard. Runs again on the
 * same database. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseReviewIT {

    @LocalServerPort
    int port;

    @Autowired
    JdbcClient jdbc;

    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().is2xxSuccessful()).as(String.valueOf(r.getBody())).isTrue();
        return r.getBody();
    }

    private static void refused(ResponseEntity<Map> r, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo(code);
    }

    private void course(String academic, String code, String title, String dept) {
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + code,
                Map.of("title", title, "units", 2, "semester", 1, "level", 200, "deptCode", dept, "kind", "Core", "state", "LIVE")));
    }

    @Test
    void theReviewListsMarksCorrectsInBulkAndRemembers() {
        int n = new Random().nextInt(8000) + 1000;
        String academic = ItSupport.token("academic");
        String bursar = ItSupport.token("bursar");
        String other = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL AND code <> 'MTC' ORDER BY code LIMIT 1").query(String.class).single();
        String otherName = jdbc.sql("SELECT name FROM ref.department WHERE code = :c").param("c", other).query(String.class).single();
        String hodOther = it.officer("hod", "department", other);
        String hodMtc = it.officer("hod", "department", "MTC");
        // two courses with a prefix that names no department, owned by the other department (wrongly, as it will turn out)
        String a = "ZZR " + n, b = "ZZR " + (n + 1);
        course(academic, a, "Introduction to Reviewing " + n, other);
        course(academic, b, "Intro to Reviewing " + n, other);     // the same title read loosely: a possible duplicate

        // the list: by title, by the owner's department name, by "200 level"
        List<Map<String, Object>> rows = (List<Map<String, Object>>) ok(it.get(academic, "/api/v1/catalogue/courses/list?q=Introduction to Reviewing " + n)).get("rows");
        assertThat(rows).anySatisfy(r -> assertThat(r.get("code")).isEqualTo(a));
        rows = (List<Map<String, Object>>) ok(it.get(academic, "/api/v1/catalogue/courses/list?q=" + otherName + "&size=2000")).get("rows");
        assertThat(rows).anySatisfy(r -> assertThat(r.get("code")).isEqualTo(a));
        rows = (List<Map<String, Object>>) ok(it.get(academic, "/api/v1/catalogue/courses/list?q=200 level&size=2000")).get("rows");
        assertThat(rows).allSatisfy(r -> assertThat(((Number) r.get("level")).intValue()).isEqualTo(200));
        Map<String, Object> row = rows.stream().filter(r -> a.equals(r.get("code"))).findFirst().orElseThrow();
        assertThat(row.get("review_status")).isEqualTo("NOT_REVIEWED");
        assertThat(String.valueOf(row.get("issues"))).contains("POSSIBLE_DUPLICATE");
        assertThat(row.get("updated_at")).isNotNull();

        // the review's word: the Academic Office on any course; the owning department's Head; another department's Head refused; a note where needed
        refused(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses/" + a + "/review", Map.of("status", "INCORRECT_OWNER")), "REVIEW_NOTE");
        assertThat(ok(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses/" + a + "/review", Map.of("status", "INCORRECT_OWNER", "note", "Belongs to Mathematics"))).get("review_status")).isEqualTo("INCORRECT_OWNER");
        assertThat(ok(it.call(hodOther, HttpMethod.POST, "/api/v1/catalogue/courses/" + b + "/review", Map.of("status", "REQUIRES_REVIEW", "note", "Check with Mathematics"))).get("review_status")).isEqualTo("REQUIRES_REVIEW");
        refused(it.call(hodMtc, HttpMethod.POST, "/api/v1/catalogue/courses/" + b + "/review", Map.of("status", "CORRECT")), "REVIEW_SCOPE");
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/catalogue/courses/" + a + "/review", Map.of("status", "CORRECT")).getStatusCode().value()).isEqualTo(403);
        rows = (List<Map<String, Object>>) ok(it.get(academic, "/api/v1/catalogue/courses/list?review=INCORRECT_OWNER&size=2000")).get("rows");
        assertThat(rows).anySatisfy(r -> assertThat(r.get("code")).isEqualTo(a));

        // the dashboard counts them
        Map<String, Object> summary = ok(it.get(academic, "/api/v1/catalogue/review/summary"));
        assertThat(((Number) summary.get("incorrect_owner")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) summary.get("possible_duplicates")).intValue()).isGreaterThanOrEqualTo(2);
        List<Map<String, Object>> dups = (List<Map<String, Object>>) (List<?>) it.getList(academic, "/api/v1/catalogue/possible-duplicates").getBody();
        assertThat(dups).anySatisfy(d -> assertThat(List.of(String.valueOf(d.get("keep_code")), String.valueOf(d.get("merge_code")))).containsExactlyInAnyOrder(a, b));

        // the bulk correction: previewed (nothing moved), refused by the Bursary and without a reason, then applied in one act on the trail
        Map<String, Object> preview = ok(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses/bulk-owner", Map.of("codes", List.of(a, b), "department", "MTC")));
        assertThat(preview.get("dryRun")).isEqualTo(true);
        assertThat(((Number) preview.get("courses")).intValue()).isEqualTo(2);
        assertThat(((Map<String, Object>) preview.get("byDepartment")).get(otherName)).isEqualTo(2);
        assertThat(jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", a).query(String.class).single()).isEqualTo(other);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/catalogue/courses/bulk-owner", Map.of("codes", List.of(a, b), "department", "MTC", "reason", "x", "dryRun", false)).getStatusCode().value()).isEqualTo(403);
        refused(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses/bulk-owner", Map.of("codes", List.of(a, b), "department", "MTC", "dryRun", false)), "CAT_OWNER_REASON");
        Map<String, Object> moved = ok(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/courses/bulk-owner",
                Map.of("codes", List.of(a, b), "department", "MTC", "reason", "Correction of incorrect department assignments from the initial bulk upload", "dryRun", false)));
        assertThat(((List<?>) moved.get("moved")).size()).isEqualTo(2);
        assertThat(jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", a).query(String.class).single()).isEqualTo("MTC");
        assertThat(jdbc.sql("SELECT source FROM catalogue.course_owner_history h JOIN catalogue.course c ON c.id = h.course_id WHERE c.code = :c ORDER BY h.changed_at DESC LIMIT 1").param("c", a).query(String.class).single()).isEqualTo("BULK");
        // a course the Head of Mathematics now owns is theirs to mark
        assertThat(ok(it.call(hodMtc, HttpMethod.POST, "/api/v1/catalogue/courses/" + a + "/review", Map.of("status", "CORRECT"))).get("review_status")).isEqualTo("CORRECT");

        // the history: the owner change on the trail, the course's creation on the spine
        Map<String, Object> history = ok(it.get(academic, "/api/v1/catalogue/courses/" + a + "/history"));
        List<Map<String, Object>> h = (List<Map<String, Object>>) history.get("rows");
        assertThat(h).anySatisfy(x -> { assertThat(x.get("action")).isEqualTo("OWNER_CHANGED"); assertThat(x.get("old_value")).isEqualTo(other); assertThat(x.get("new_value")).isEqualTo("MTC"); assertThat(x.get("source")).isEqualTo("BULK"); });
        assertThat(h).anySatisfy(x -> assertThat(x.get("action")).isEqualTo("CREATED"));
        assertThat(history.get("review_status")).isEqualTo("CORRECT");
        assertThat(history.get("created_at")).isNotNull();
    }
}
