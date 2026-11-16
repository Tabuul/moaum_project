package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;

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
 * V662: the Database Operators work the Academic menu the Director of ICT works — Upload or Create Faculties, Departments,
 * Programmes and Courses, Course Allocation and Migrate from Old Portal — each held to its grant. An operator granted over the
 * whole University creates (and removes) a faculty, uploads a programme's course structure, reaches every class on the allocation
 * desk, checks past results (the database's own rule, assessment.past_results_office, admits it) and confirms a past results upload
 * (15 Nov 2026: each row states the course as taken). An operator held to one department uploads its own programme's structure, is
 * refused another department's, reaches its department on the desk, and is refused the University's register and the old-portal
 * migration, its uploads among it (SCOPE_UNIVERSITY). A lecturer is refused all of it.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class DatabaseOperatorAcademicIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static void ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
    }

    private static void refused(ResponseEntity<Map> r, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isIn(403, 422);
        if (code != null) assertThat(r.getBody()).as(String.valueOf(r.getBody())).containsEntry("code", code);
    }

    @Test
    void theUniversitysOperatorWorksTheAcademicMenuAndADepartmentsOperatorItsOwnPart() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 100 + new Random().nextInt(899);
        String[] place = it.db(() -> {
            String[] one = jdbc.sql("""
                    SELECT p.dept_code || ',' || p.faculty_code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' ORDER BY p.code LIMIT 1
                    """).query(String.class).single().split(",");
            String other = jdbc.sql("""
                    SELECT p.code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' AND p.dept_code <> :d ORDER BY p.code LIMIT 1
                    """).param("d", one[0]).query(String.class).single();
            String own = jdbc.sql("SELECT 'C' || x FROM generate_series(96500, 96999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 1")
                    .query(String.class).single();
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                    VALUES (:c, 'B.Sc. Operator Upload Test', :d, :f, 'UNDER GRADUATE', 0, 400, 4)
                    """).param("c", own).param("d", one[0]).param("f", one[1]).update();
            return new String[] {one[0], one[1], own, other};
        });
        String dept = place[0], own = place[2], other = place[3];
        String uni = it.officer("dbops", "institution", "University");
        String held = it.officer("dbops", "department", dept);
        String lecturer = it.officer("lecturer", "department", dept);
        Map<String, Object> structure = Map.of("programme", own, "rows",
                List.of(Map.of("code", "ZOP " + n, "title", "Operator Upload Check", "units", "2", "level", "100", "semester", "1", "status", "C")));
        String session = jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
        Map<String, Object> pastResult = Map.of("session", session, "semester", 1,
                "rows", List.of(Map.of("line", "2", "matric", "NO/SUCH/" + n, "course", "ZOP " + n, "title", "Operator Upload Check", "creditUnits", "2",
                                       "category", "Core", "total", "50")));
        Map<String, Object> confirm = Map.of("kind", "RESULTS", "fileName", "operator-check.xlsx", "rows", 1,
                "reason", "DatabaseOperatorAcademicIT: the operator's past results check");
        String faculty = "ZQ" + n;

        // ── the operator granted over the whole University: what the Director of ICT does ──
        ok(it.call(uni, HttpMethod.POST, "/api/v1/catalogue/faculties", Map.of("code", faculty, "name", "Operator Check Faculty " + n)));
        ok(it.call(uni, HttpMethod.DELETE, "/api/v1/catalogue/faculties/" + faculty, null));
        ResponseEntity<Map> upload = it.call(uni, HttpMethod.POST, "/api/v1/catalogue/import", structure);
        ok(upload);
        assertThat(((Number) upload.getBody().get("offers")).intValue()).isEqualTo(1);
        ResponseEntity<Map> desk = it.get(uni, "/api/v1/allocation/desk/options");
        ok(desk);
        assertThat(desk.getBody()).containsEntry("scope", "The University");
        assertThat((List<String>) desk.getBody().get("capabilities")).contains("VIEW_ALLOCATIONS", "ALLOCATE_COURSES", "BULK_ALLOCATE");
        ResponseEntity<Map> checked = it.call(uni, HttpMethod.POST, "/api/v1/results/legacy/results/preview", pastResult);
        assertThat(checked.getStatusCode().value()).as(String.valueOf(checked.getBody())).isEqualTo(200);   // the database's past-results rule admits it
        // and confirms a past results upload of its own, closed as it was left, and reads the uploads
        ResponseEntity<Map> confirmed = it.call(uni, HttpMethod.POST, "/api/v1/results/legacy/uploads", confirm);
        ok(confirmed);
        ok(it.call(uni, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + confirmed.getBody().get("id") + "/finish", Map.of("complete", false)));
        assertThat(it.getList(uni, "/api/v1/results/legacy/uploads").getStatusCode().value()).isEqualTo(200);

        // ── the operator held to one department: its own programmes' structures and classes, nothing of the University's ──
        ok(it.call(held, HttpMethod.POST, "/api/v1/catalogue/import", structure));
        refused(it.call(held, HttpMethod.POST, "/api/v1/catalogue/import", Map.of("programme", other, "rows", structure.get("rows"))), "SCOPE_DEPARTMENT");
        refused(it.call(held, HttpMethod.POST, "/api/v1/catalogue/faculties", Map.of("code", faculty, "name", "Not Mine")), "SCOPE_UNIVERSITY");
        refused(it.call(held, HttpMethod.POST, "/api/v1/catalogue/programmes/import", Map.of("rows", List.of())), "SCOPE_UNIVERSITY");
        refused(it.call(held, HttpMethod.POST, "/api/v1/results/legacy/results/preview", pastResult), "SCOPE_UNIVERSITY");
        refused(it.call(held, HttpMethod.POST, "/api/v1/results/legacy/uploads", confirm), "SCOPE_UNIVERSITY");
        refused(it.call(held, HttpMethod.POST, "/api/v1/results/legacy/students/preview", Map.of("rows", List.of())), "SCOPE_UNIVERSITY");
        ResponseEntity<Map> heldDesk = it.get(held, "/api/v1/allocation/desk/options");
        ok(heldDesk);
        assertThat(String.valueOf(heldDesk.getBody().get("scope"))).isEqualToIgnoringCase(dept);
        assertThat((List<Map<String, Object>>) heldDesk.getBody().get("departments")).extracting(d -> String.valueOf(d.get("code")).toUpperCase())
                .containsExactly(dept.toUpperCase());
        assertThat(jdbc.sql("SELECT count(*) FROM ref.faculty WHERE code = :c").param("c", faculty).query(Integer.class).single()).isZero();

        // ── a lecturer: none of it ──
        assertThat(it.call(lecturer, HttpMethod.POST, "/api/v1/catalogue/faculties", Map.of("code", faculty, "name", "No")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(lecturer, HttpMethod.POST, "/api/v1/catalogue/import", structure).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(lecturer, "/api/v1/allocation/desk/options").getStatusCode().value()).isEqualTo(403);
    }
}
