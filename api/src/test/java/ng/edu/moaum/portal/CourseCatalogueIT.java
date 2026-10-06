package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * The course catalogue's upload with owners and offerings (V338), on a department and programmes of the test's own so nothing
 * else is touched: one row per offering becomes ONE course with an offering per programme, CORE or ELECTIVE for each; an
 * invalid file writes nothing; the offering keeps the title it was registered under; a re-upload updates the same record; an
 * owner change is kept with its reason. Only central offices upload. The catalogue reset is withdrawn (V340): it has no
 * endpoint and no function. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseCatalogueIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String ict;
    String academic;
    String hod;
    String d1;
    String d2;
    String p1;
    String p2;
    String p3;
    String x;
    String y;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        ict = TestTokens.token(it.person("ZZCAT-ICT", "ZZCATICT"), List.of("ict"));
        academic = TestTokens.token(it.person("ZZCAT-ACAD", "ZZCATACAD"), List.of("academic"));
        hod = it.officer("hod", "department", "MTC");
        Random r = new Random();
        String tag = Long.toString(Math.abs(r.nextLong()), 36).toUpperCase().replaceAll("[^A-Z]", "") + "QWERTY";
        d1 = "Z" + tag.substring(0, 4);
        d2 = "Z" + tag.substring(1, 5) + "B";
        p1 = programmeCode(r);
        p2 = programmeCode(r);
        p3 = programmeCode(r);
        String letters = "Z" + tag.substring(0, 2);
        x = letters + " " + (100 + r.nextInt(90));
        y = letters + " " + (200 + r.nextInt(90));
        it.db(() -> {
            jdbc.sql("INSERT INTO ref.department (code, name, faculty_code) VALUES (:c, 'CATALOGUE IT ' || :c, 'SC')").param("c", d1).update();
            jdbc.sql("INSERT INTO ref.department (code, name, faculty_code) VALUES (:c, 'CATALOGUE IT ' || :c, 'SC')").param("c", d2).update();
            for (String[] pr : new String[][] {{p1, d1, "B.Sc. Catalogue One"}, {p2, d1, "B.Sc. Catalogue Two"}, {p3, d2, "B.Sc. Catalogue Three"}}) {
                jdbc.sql("INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, category) VALUES (:c, :n || ' ' || :c, :d, 'SC', 180, 'UNDER GRADUATE')")
                        .param("c", pr[0]).param("n", pr[2]).param("d", pr[1]).update();
            }
            return null;
        });
    }

    private String programmeCode(Random r) {
        String c;
        do {
            c = "C9" + String.format("%04d", r.nextInt(10000));
        } while (jdbc.sql("SELECT count(*) FROM ref.programme WHERE code = :c").param("c", c).query(Long.class).single() > 0);
        return c;
    }

    private static Map<String, Object> row(String code, String title, String ownerDept, String ownerProg, String offerProg, String type, int level) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("code", code);
        m.put("title", title);
        m.put("units", "3");
        m.put("level", String.valueOf(level));
        m.put("semester", "1");
        m.put("ownerFaculty", "SC");
        m.put("ownerDepartment", ownerDept);
        m.put("ownerProgramme", ownerProg);
        m.put("offeringProgramme", offerProg);
        m.put("offeringType", type);
        return m;
    }

    private ResponseEntity<Map> upload(String token, List<Map<String, Object>> rows, boolean commit) {
        return it.call(token, HttpMethod.POST, "/api/v1/catalogue/catalogue-import?commit=" + commit, Map.of("rows", rows, "fileName", "catalogue-it.xlsx"));
    }

    private Map<String, Object> summary(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return (Map<String, Object>) r.getBody().get("summary");
    }

    private void uploadGood() {
        Map<String, Object> y1 = row(y, "Catalogue Programming", d1, p1, p1, "CORE", 200);
        y1.put("prerequisite", x);
        ResponseEntity<Map> done = upload(ict, List.of(
                row(x, "Catalogue Foundations", d1, p1, p1, "CORE", 100),
                row(x, "Catalogue Foundations", d1, p1, p2, "ELECTIVE", 100),
                row(x, "Catalogue Foundations", d1, p1, p3, "CORE", 100),
                y1), true);
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody().get("committed")).isEqualTo(true);
        assertThat(String.valueOf(done.getBody().get("ref"))).startsWith("COURSE-IMPORT-");
    }

    @Test
    void anUploadIsJudgedFirstAndMakesOneCourseWithAnOfferingPerProgramme() {
        // only the central offices upload
        assertThat(upload(hod, List.of(row(x, "T", d1, p1, p1, "CORE", 100)), false).getStatusCode().value()).isEqualTo(403);

        // a file with invalid rows is judged, and writes nothing
        Map<String, Object> wrongOwnerProg = row(x, "Catalogue Foundations", d1, p3, p1, "CORE", 100);
        List<Map<String, Object>> bad = List.of(
                row(x, "Catalogue Foundations", "NO SUCH DEPARTMENT", null, p1, "CORE", 100),
                row(x, "Catalogue Foundations", d1, p1, p2, "MAYBE", 100),
                row(x, "Catalogue Foundations", d1, p1, p1, "CORE", 100),
                row(x, "Catalogue Foundations", d1, p1, p1, "ELECTIVE", 100),
                wrongOwnerProg,
                row(x, "Catalogue Foundations", d1, p1, "C00000", "CORE", 100));
        Map<String, Object> s = summary(upload(academic, bad, false));
        assertThat(((Number) s.get("invalid")).intValue()).isGreaterThanOrEqualTo(5);
        // four rows offer the course to the same programme at the same level: the three after the first are duplicates
        assertThat(((Number) s.get("duplicateOfferings")).intValue()).isEqualTo(3);
        assertThat(((Number) s.get("ownerErrors")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) s.get("typeErrors")).intValue()).isEqualTo(1);
        assertThat(((Number) s.get("programmeErrors")).intValue()).isGreaterThanOrEqualTo(1);
        ResponseEntity<Map> refused = upload(academic, bad, true);
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("CAT_IMPORT_INVALID");
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :c").param("c", x).query(Long.class).single()).isZero();

        // a valid file: ONE course for its three rows, an offering per programme, CORE or ELECTIVE for each, its owner and prerequisite kept
        Map<String, Object> preview = summary(upload(ict, List.of(
                row(x, "Catalogue Foundations", d1, p1, p1, "CORE", 100),
                row(x, "Catalogue Foundations", d1, p1, p2, "ELECTIVE", 100),
                row(x, "Catalogue Foundations", d1, p1, p3, "CORE", 100)), false));
        assertThat(((Number) preview.get("newCourses")).intValue()).isEqualTo(1);
        assertThat(((Number) preview.get("newOfferings")).intValue()).isEqualTo(3);
        uploadGood();
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :c").param("c", x).query(Long.class).single()).isEqualTo(1L);
        Map<String, Object> course = jdbc.sql("SELECT dept_code, owner_programme, state, kind FROM catalogue.course WHERE code = :c").param("c", x).query().singleRow();
        assertThat(course.get("dept_code")).isEqualTo(d1);
        assertThat(course.get("owner_programme")).isEqualTo(p1);
        assertThat(course.get("state")).isEqualTo("LIVE");
        List<Map<String, Object>> offers = jdbc.sql("SELECT programme_code, basis FROM catalogue.course_offer WHERE course_code = :c ORDER BY programme_code")
                .param("c", x).query().listOfRows();
        assertThat(offers).hasSize(3);
        assertThat(offers).anySatisfy(o -> { assertThat(o.get("programme_code")).isEqualTo(p2); assertThat(o.get("basis")).isEqualTo("Elective"); });
        assertThat(offers).anySatisfy(o -> { assertThat(o.get("programme_code")).isEqualTo(p3); assertThat(o.get("basis")).isEqualTo("Core"); });
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course_prerequisite WHERE course_code = :y AND requires_code = :x").param("y", y).param("x", x).query(Long.class).single()).isEqualTo(1L);

        // the same file again: the same course, no duplicate, every offering existing
        Map<String, Object> again = summary(upload(ict, List.of(row(x, "Catalogue Foundations", d1, p1, p1, "CORE", 100)), false));
        assertThat(((Number) again.get("existingCourses")).intValue()).isEqualTo(1);
        assertThat(((Number) again.get("existingOfferings")).intValue()).isEqualTo(1);

        // the course detail names its owner programme and prerequisite
        ResponseEntity<Map> detail = it.get(academic, b -> b.path("/api/v1/catalogue/courses/{code}/detail").build(x));
        assertThat(detail.getStatusCode().value()).isEqualTo(200);
        assertThat(((Map) detail.getBody().get("course")).get("owner_programme")).isEqualTo(p1);
    }

    @Test
    void aRegisteredOfferingKeepsItsTitleTheResetIsGoneAndAnOwnerChangeIsKept() {
        uploadGood();
        UUID courseId = jdbc.sql("SELECT id FROM catalogue.course WHERE code = :c").param("c", x).query(UUID.class).single();
        // history on X: a session offering a student is registered on
        String session = "2097/2098";
        it.session(session, 2097);
        UUID student = it.student("ZZCATSTUDENT" + d1, p1, "MOAUM/ADM/97/" + String.format("%06d", new Random().nextInt(1000000)), null, 100);
        UUID offering = UUID.randomUUID();
        UUID registration = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:o, :c, :s, 1)").param("o", offering).param("c", x).param("s", session).update();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :st, :s, 1, 100, 'APPROVED', now(), now())")
                    .param("r", registration).param("st", student).param("s", session).update();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status) VALUES (:r, :o, 3, 'CURRENT', 'APPROVED')")
                    .param("r", registration).param("o", offering).update();
            return null;
        });
        // a correction of the title after it was registered: the registered offering keeps the old one
        assertThat(summary(upload(ict, List.of(row(x, "Catalogue Foundations (Corrected)", d1, p1, p1, "CORE", 100)), true))).isNotNull();
        assertThat(jdbc.sql("SELECT title FROM catalogue.offering WHERE id = :o").param("o", offering).query(String.class).single()).isEqualTo("Catalogue Foundations");
        assertThat(jdbc.sql("SELECT title FROM assessment.student_results(:s) WHERE course_code = :c").param("s", student).param("c", x).query(String.class).single())
                .isEqualTo("Catalogue Foundations");

        // the catalogue reset is withdrawn (V340): no endpoint answers, no function remains, and the course is untouched
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/catalogue/reset", Map.of("scope", "DEPARTMENT", "ref", d1, "reason", "Wrong owners", "confirm", "RESET COURSES"))
                .getStatusCode().value()).isIn(404, 405);
        assertThat(it.get(ict, "/api/v1/catalogue/reset/history").getStatusCode().value()).isIn(400, 404, 405);
        assertThat(jdbc.sql("SELECT to_regprocedure('catalogue.course_reset(text,text,text,text)') IS NULL AND to_regprocedure('catalogue.course_reset_preview(text,text)') IS NULL")
                .query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT state FROM catalogue.course WHERE code = :c").param("c", x).query(String.class).single()).isEqualTo("LIVE");

        // a re-upload updates the same course; the registered offering still reads its own title
        upload(ict, List.of(row(x, "Catalogue Foundations Revised", d1, p1, p1, "CORE", 100)), true);
        Map<String, Object> back = jdbc.sql("SELECT id, state, title FROM catalogue.course WHERE code = :c").param("c", x).query().singleRow();
        assertThat(back.get("id")).isEqualTo(courseId);
        assertThat(back.get("state")).isEqualTo("LIVE");
        assertThat(back.get("title")).isEqualTo("Catalogue Foundations Revised");
        assertThat(jdbc.sql("SELECT count(*) FROM registration.entry WHERE offering_id = :o").param("o", offering).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT title FROM catalogue.offering WHERE id = :o").param("o", offering).query(String.class).single()).isEqualTo("Catalogue Foundations");

        // the owner is changed on the desk, with its reason kept; a Head of Department does not change it
        assertThat(it.call(hod, HttpMethod.POST, ub -> ub.path("/api/v1/catalogue/courses/{code}/owner").build(x), Map.of("department", d2, "reason", "x")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> moved = it.call(academic, HttpMethod.POST, b -> b.path("/api/v1/catalogue/courses/{code}/owner").build(x),
                Map.of("department", d2, "programme", p3, "reason", "Taught and examined by the second department"));
        assertThat(moved.getStatusCode().value()).as(String.valueOf(moved.getBody())).isEqualTo(200);
        assertThat(moved.getBody().get("dept_code")).isEqualTo(d2);
        Map<String, Object> last = jdbc.sql("SELECT from_dept, to_dept, to_programme, reason, source FROM catalogue.course_owner_history WHERE course_id = :id ORDER BY changed_at DESC LIMIT 1")
                .param("id", courseId).query().singleRow();
        assertThat(last.get("from_dept")).isEqualTo(d1);
        assertThat(last.get("to_dept")).isEqualTo(d2);
        assertThat(last.get("to_programme")).isEqualTo(p3);
        assertThat(last.get("source")).isEqualTo("DESK");
        assertThat(String.valueOf(last.get("reason"))).contains("second department");
        // an owner programme must belong to the owner department
        ResponseEntity<Map> wrong = it.call(academic, HttpMethod.POST, b -> b.path("/api/v1/catalogue/courses/{code}/owner").build(x),
                Map.of("department", d2, "programme", p1, "reason", "wrong programme"));
        assertThat(wrong.getStatusCode().value()).isEqualTo(422);
        assertThat(wrong.getBody().get("code")).isEqualTo("CAT_OWNER_PROGRAMME");
    }
}
