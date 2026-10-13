package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

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
 * V443: a course is never tied to a session — the Head of Department's desk lists the department's courses for the semester
 * with the class in the session if one exists, and allocating a course the session holds no class for opens the class as part
 * of the allocation (the ICT desk opens it the same way, once); and a course belongs to the department whose code it carries —
 * a course created under another department's prefix is that department's at once, a prefix that is no department's code is
 * named to one by the Academic Office and its courses moved there, a department's own code refused as a prefix. Runs again on
 * the same database. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CoursePoolIT {

    static final String SESSION = "2124/2125";

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
        it.session(SESSION, 2124);
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().is2xxSuccessful()).as(String.valueOf(r.getBody())).isTrue();
        return r.getBody();
    }

    private static void refused(ResponseEntity<Map> r, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo(code);
    }

    @Test
    void aCourseIsNeverTiedToASessionAndBelongsToTheDepartmentWhoseCodeItCarries() {
        int n = new Random().nextInt(800) + 100;
        String academic = ItSupport.token("academic");
        String hod = it.officer("hod", "department", "MTC");
        UUID lecturer = it.person("ZZ-POOL-" + n, "ZZPOOL" + n);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'lecturer', 'department', 'MTC', 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'lecturer' AND a.scope_id = 'MTC')
                """).param("p", lecturer).update());

        // ── 1 · the pool, not the session: a course of the department with no class in a session the calendar never opened ──
        String code = "ZZP " + n;
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + code,
                Map.of("title", "Pool course " + n, "units", 2, "semester", 1, "level", 200, "deptCode", "MTC", "kind", "Core", "state", "LIVE")));
        List<Map<String, Object>> listed = (List<Map<String, Object>>) (List<?>) it.getList(hod, "/api/v1/allocation?dept=MTC&session=" + SESSION + "&semester=1").getBody();
        Map<String, Object> row = listed.stream().filter(r -> code.equals(r.get("course_code"))).findFirst().orElse(null);
        assertThat(row).as("the course is listed although the session holds no class for it").isNotNull();
        assertThat(row.get("id")).isNull();
        assertThat(row.get("no_class")).isEqualTo(true);
        // the wrong semester opens nothing; the right one opens the class, found again the second time, by the ICT desk too
        refused(it.call(hod, HttpMethod.POST, "/api/v1/allocation/open", Map.of("courseCode", code, "session", SESSION, "semester", 2)), "CLASS_NOT_IN_SEMESTER");
        String id = String.valueOf(ok(it.call(hod, HttpMethod.POST, "/api/v1/allocation/open", Map.of("courseCode", code, "session", SESSION, "semester", 1))).get("id"));
        assertThat(String.valueOf(ok(it.call(hod, HttpMethod.POST, "/api/v1/allocation/open", Map.of("courseCode", code, "session", SESSION, "semester", 1))).get("id"))).isEqualTo(id);
        assertThat(String.valueOf(ok(it.call(ItSupport.token("ict"), HttpMethod.POST, "/api/v1/allocation/desk/classes/open",
                Map.of("courseCode", code, "session", SESSION, "semester", 1))).get("offering"))).isEqualTo(id);
        // and the class is allocated as any other
        ok(it.call(hod, HttpMethod.POST, "/api/v1/allocation/" + id, Map.of("lecturer", lecturer.toString())));
        listed = (List<Map<String, Object>>) (List<?>) it.getList(hod, "/api/v1/allocation?dept=MTC&session=" + SESSION + "&semester=1").getBody();
        row = listed.stream().filter(r -> code.equals(r.get("course_code"))).findFirst().orElseThrow();
        assertThat(String.valueOf(row.get("id"))).isEqualTo(id);
        assertThat(String.valueOf(row.get("lecturer_id"))).isEqualTo(lecturer.toString());
        // another department's course is not the HOD's to open
        String other = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL AND code <> 'MTC' ORDER BY code LIMIT 1").query(String.class).single();
        String theirs = "ZZO " + n;
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + theirs,
                Map.of("title", "Other course " + n, "units", 2, "semester", 1, "level", 200, "deptCode", other, "kind", "Core", "state", "LIVE")));
        refused(it.call(hod, HttpMethod.POST, "/api/v1/allocation/open", Map.of("courseCode", theirs, "session", SESSION, "semester", 1)), "ALLOC_DEPT");

        // ── 2 · the code names the owner: a course created under MTC's prefix by another department is MTC's at once ──
        String astray = "MTC 9" + n;
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + astray,
                Map.of("title", "Astray course " + n, "units", 2, "semester", 1, "level", 200, "deptCode", other, "kind", "Core", "state", "LIVE")));
        assertThat(jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", astray).query(String.class).single()).isEqualTo("MTC");
        // a prefix that is no department's code: named to MTC by the Academic Office, its courses moved there; a department's own code refused
        String mapped = "ZZQ " + n;
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + mapped,
                Map.of("title", "Mapped course " + n, "units", 2, "semester", 1, "level", 200, "deptCode", other, "kind", "Core", "state", "LIVE")));
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.PUT, "/api/v1/catalogue/code-owners/ZZQ", Map.of("department", "MTC", "apply", true)).getStatusCode().value()).isEqualTo(403);
        refused(it.call(academic, HttpMethod.PUT, "/api/v1/catalogue/code-owners/MTC", Map.of("department", other, "apply", false)), "CODE_PREFIX_IS_DEPARTMENT");
        Map<String, Object> named = ok(it.call(academic, HttpMethod.PUT, "/api/v1/catalogue/code-owners/ZZQ", Map.of("department", "MTC", "apply", true, "reason", "ZZQ is Mathematics'")));
        assertThat(((Number) named.get("moved")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", mapped).query(String.class).single()).isEqualTo("MTC");
        assertThat(jdbc.sql("SELECT source FROM catalogue.course_owner_history WHERE course_code = :c ORDER BY changed_at DESC LIMIT 1").param("c", mapped).query(String.class).single()).isEqualTo("CODE");
        List<Map<String, Object>> owners = (List<Map<String, Object>>) ok(it.get(academic, "/api/v1/catalogue/code-owners")).get("rows");
        Map<String, Object> zzq = owners.stream().filter(r -> "ZZQ".equals(r.get("prefix"))).findFirst().orElseThrow();
        assertThat(zzq.get("mapped_dept")).isEqualTo("MTC");
        assertThat(((Number) zzq.get("astray")).intValue()).isZero();
        ok(it.call(academic, HttpMethod.DELETE, "/api/v1/catalogue/code-owners/ZZQ", null));
    }
}
