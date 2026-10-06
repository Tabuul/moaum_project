package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;

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
 * One course offered to many programmes across departments (V332), over the API: the Head of one department creates a
 * course with an offer to their own programme (bound at once) and to another department's programme (proposed); the
 * code is detected as existing however it is spaced; the proposal is decided by the programme's own Head and by nobody
 * else; the course is edited and renamed without becoming another course; a binding ended is kept on the record; a
 * Head reaches only courses their department owns or carries; a student token is refused. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseOfferingIT {

    static final String OWN_DEPT = "MTC", OWN_PROG = "C00023";     // Mathematics and Computer Science · B.Sc. Computer Science
    static final String OTHER_DEPT = "PHY", OTHER_PROG = "C00029"; // Physics · B.Sc. Physics
    static final String CODE = "ZZO 901", RENAMED = "ZZO 902";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;
    String hodOwn, hodOther, academic;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        hodOwn = it.officer("hod", "department", OWN_DEPT);
        hodOther = it.officer("hod", "department", OTHER_DEPT);
        academic = ItSupport.token("academic");
        // the shared CI database may carry this test's course from an earlier run; nothing hangs on it, so it goes
        it.db(() -> {
            for (String c : List.of(CODE, RENAMED, "MOAUZZO 903", "MOAU-ZZO 903")) {
                if (jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :c").param("c", c).query(Long.class).single() > 0) {
                    jdbc.sql("SELECT catalogue.remove_course(:c)").param("c", c).query().singleRow();
                }
            }
            return null;
        });
    }

    private static List<Map> rows(ResponseEntity<Map> r, String key) {
        return (List<Map>) r.getBody().get(key);
    }

    @Test
    void oneCourseIsOfferedAcrossDepartmentsWithoutASecondRecord() {
        // the Head creates the course under their own department, offered to their own programme and proposed to another department's
        ResponseEntity<Map> created = it.call(hodOwn, HttpMethod.POST, "/api/v1/catalogue/courses", Map.of(
                "code", CODE, "title", "Data Structures (IT)", "units", 3, "semester", 1, "level", 200, "dept", OWN_DEPT, "kind", "Core",
                "offers", List.of(Map.of("programme", OWN_PROG, "level", 200), Map.of("programme", OTHER_PROG, "level", 200, "reason", "Physics takes it as a borrowed course"))));
        assertThat(created.getStatusCode().value()).as(String.valueOf(created.getBody())).isEqualTo(200);
        assertThat(created.getBody().get("code")).isEqualTo(CODE);
        // live at once, on the department's list and in registration: no Faculty Board or Senate step
        assertThat(created.getBody().get("state")).isEqualTo("LIVE");
        assertThat(jdbc.sql("SELECT state FROM catalogue.course WHERE code = :c").param("c", CODE).query(String.class).single()).isEqualTo("LIVE");
        assertThat(((Number) created.getBody().get("bound")).intValue()).isEqualTo(1);
        assertThat(((Number) created.getBody().get("proposed")).intValue()).isEqualTo(1);
        String id = String.valueOf(created.getBody().get("id"));
        assertThat(id).hasSize(36);
        // the code is detected as existing, however it is spaced or cased
        ResponseEntity<Map> exists = it.get(hodOther, b -> b.path("/api/v1/catalogue/courses/exists").queryParam("code", "zzo901").queryParam("title", "Data Structures (IT)").queryParam("level", 200).build());
        assertThat(exists.getStatusCode().value()).isEqualTo(200);
        assertThat(((Map) exists.getBody().get("byCode")).get("code")).isEqualTo(CODE);
        assertThat(rows(exists, "byTitle")).extracting(r -> r.get("code")).contains(CODE);
        // the proposal waits for the other department: its Head sees it to decide, the proposing Head cannot decide it
        ResponseEntity<Map> waiting = it.get(hodOther, "/api/v1/catalogue/offer-proposals");
        assertThat(waiting.getStatusCode().value()).as(String.valueOf(waiting.getBody())).isEqualTo(200);
        Map proposal = rows(waiting, "toDecide").stream().filter(p -> CODE.equals(p.get("course_code"))).findFirst().orElseThrow();
        String pid = String.valueOf(proposal.get("id"));
        assertThat(rows(it.get(hodOwn, "/api/v1/catalogue/offer-proposals"), "mine")).extracting(p -> p.get("id")).contains(pid);
        assertThat(it.call(hodOwn, HttpMethod.POST, "/api/v1/catalogue/offer-proposals/" + pid + "/approve", Map.of()).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> approved = it.call(hodOther, HttpMethod.POST, "/api/v1/catalogue/offer-proposals/" + pid + "/approve", Map.of("note", "Approved at the departmental board"));
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat(approved.getBody().get("state")).isEqualTo("APPROVED");
        // one course, two departments, two programmes
        ResponseEntity<Map> detail = it.get(hodOwn, b -> b.path("/api/v1/catalogue/courses/{c}/detail").build(CODE));
        assertThat(detail.getStatusCode().value()).isEqualTo(200);
        assertThat(rows(detail, "offers")).extracting(o -> o.get("programme_code")).containsExactlyInAnyOrder(OWN_PROG, OTHER_PROG);
        assertThat(rows(detail, "departments")).extracting(d -> d.get("code")).containsExactlyInAnyOrder(OWN_DEPT, OTHER_DEPT);
        assertThat(rows(detail, "offers").stream().filter(o -> OTHER_PROG.equals(o.get("programme_code"))).findFirst().orElseThrow().get("source")).isEqualTo("PROPOSAL");
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course WHERE title = 'Data Structures (IT)'").query(Long.class).single()).isEqualTo(1L);
        // a second proposal of the same offer is refused; so is a proposal of what is already offered
        assertThat(it.call(hodOwn, HttpMethod.POST, b -> b.path("/api/v1/catalogue/courses/{c}/offers").build(CODE), Map.of("programme", OTHER_PROG, "level", 200)).getStatusCode().value()).isEqualTo(422);
        // the other Head cannot edit the course; its own Head edits it and it stays the same course
        assertThat(it.call(hodOther, HttpMethod.PUT, b -> b.path("/api/v1/catalogue/courses/{c}").build(CODE), Map.of("title", "Hijacked", "units", 2, "semester", 1, "level", 200)).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> edited = it.call(hodOwn, HttpMethod.PUT, b -> b.path("/api/v1/catalogue/courses/{c}").build(CODE), Map.of("title", "Data Structures and Algorithms (IT)", "units", 4, "semester", 1, "level", 200, "kind", "Core"));
        assertThat(edited.getStatusCode().value()).as(String.valueOf(edited.getBody())).isEqualTo(200);
        assertThat(String.valueOf(edited.getBody().get("id"))).isEqualTo(id);
        ResponseEntity<Map> renamed = it.call(hodOwn, HttpMethod.POST, b -> b.path("/api/v1/catalogue/courses/{c}/rename").build(CODE), Map.of("code", "zzo902"));
        assertThat(renamed.getStatusCode().value()).as(String.valueOf(renamed.getBody())).isEqualTo(200);
        assertThat(renamed.getBody().get("code")).isEqualTo(RENAMED);
        assertThat(String.valueOf(renamed.getBody().get("id"))).isEqualTo(id);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course_offer WHERE course_code = :c").param("c", RENAMED).query(Long.class).single()).isEqualTo(2L);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.offer_proposal WHERE course_code = :c").param("c", RENAMED).query(Long.class).single()).isEqualTo(1L);
        // the binding into the other programme is that department's to end, and it is kept on the record
        assertThat(it.call(hodOwn, HttpMethod.DELETE, b -> b.path("/api/v1/catalogue/courses/{c}/offers").queryParam("programme", OTHER_PROG).queryParam("level", 200).build(RENAMED), null).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> ended = it.call(hodOther, HttpMethod.DELETE, b -> b.path("/api/v1/catalogue/courses/{c}/offers").queryParam("programme", OTHER_PROG).queryParam("level", 200).queryParam("reason", "Dropped from the structure").build(RENAMED), null);
        assertThat(ended.getStatusCode().value()).as(String.valueOf(ended.getBody())).isEqualTo(200);
        assertThat(ended.getBody().get("outcome")).isEqualTo("REMOVED");
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course_offer_history WHERE course_code = :c AND programme_code = :p").param("c", RENAMED).param("p", OTHER_PROG).query(Long.class).single()).isEqualTo(1L);
        // the list is the office's scope: the owning Head sees it, the other Head no longer carries it, a student is refused
        assertThat(rows(it.get(hodOwn, "/api/v1/catalogue/courses/list?q=ZZO&size=20"), "rows")).extracting(r -> r.get("code")).contains(RENAMED);
        assertThat(rows(it.get(hodOther, "/api/v1/catalogue/courses/list?q=ZZO&size=20"), "rows")).extracting(r -> r.get("code")).doesNotContain(RENAMED);
        assertThat(rows(it.get(academic, "/api/v1/catalogue/courses/list?dept=" + OWN_DEPT + "&q=ZZO&size=20"), "rows")).extracting(r -> r.get("code")).contains(RENAMED);
        assertThat(it.get(TestTokens.token(java.util.UUID.randomUUID(), List.of("student")), "/api/v1/catalogue/courses/list").getStatusCode().value()).isEqualTo(403);
        // the Academic Office binds across departments without a proposal
        ResponseEntity<Map> direct = it.call(academic, HttpMethod.POST, b -> b.path("/api/v1/catalogue/courses/{c}/offers").build(RENAMED), Map.of("programme", OTHER_PROG, "level", 300, "basis", "Elective"));
        assertThat(direct.getStatusCode().value()).as(String.valueOf(direct.getBody())).isEqualTo(200);
        assertThat(direct.getBody().get("outcome")).isEqualTo("BOUND");
    }

    @Test
    void aCodeUploadedWithoutItsHyphenIsCorrectedInPlace() {
        // the old portal's upload wrote the prefix without its hyphen; the catalogue kept it
        it.db(() -> {
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES ('MOAUZZO 903', 'Numerical Methods (IT)', 2, 1, 300, :d, 'Core', 'LIVE')").param("d", OWN_DEPT).update();
            jdbc.sql("SELECT catalogue.bind_offer('MOAUZZO 903', :p, 300, 'Core', NULL, 'IMPORT')").param("p", OWN_PROG).query().singleRow();
            return null;
        });
        String id = jdbc.sql("SELECT id::text FROM catalogue.course WHERE code = 'MOAUZZO 903'").query(String.class).single();
        // the desk lists it with the code it should read; the other department's Head does not see it
        ResponseEntity<List> fixes = it.getList(hodOwn, "/api/v1/catalogue/code-fixes");
        assertThat(fixes.getStatusCode().value()).isEqualTo(200);
        Map fix = ((List<Map>) fixes.getBody()).stream().filter(f -> "MOAUZZO 903".equals(f.get("code"))).findFirst().orElseThrow();
        assertThat(fix.get("proposed")).isEqualTo("MOAU-ZZO 903");
        assertThat(fix.get("twin_exists")).isEqualTo(false);
        assertThat(((List<Map>) it.getList(hodOther, "/api/v1/catalogue/code-fixes").getBody())).extracting(f -> f.get("code")).doesNotContain("MOAUZZO 903");
        // corrected in one act: the same course, the binding still on it
        ResponseEntity<Map> applied = it.call(hodOwn, HttpMethod.POST, "/api/v1/catalogue/code-fixes/apply", Map.of());
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        assertThat(((Number) applied.getBody().get("renamed")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(jdbc.sql("SELECT id::text FROM catalogue.course WHERE code = 'MOAU-ZZO 903'").query(String.class).single()).isEqualTo(id);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course_offer WHERE course_code = 'MOAU-ZZO 903' AND programme_code = :p").param("p", OWN_PROG).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = 'MOAUZZO 903'").query(Long.class).single()).isEqualTo(0L);
    }
}
