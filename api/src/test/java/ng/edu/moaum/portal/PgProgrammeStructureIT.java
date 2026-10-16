package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * V471: the School of Postgraduate Studies and the ICT Support Desk on the one programme structure. The School's Secretary
 * creates a postgraduate course (one record of the pool, bound at once), binds courses into a postgraduate programme at 700,
 * 800 or 900 level as Core, Elective, Borrowed, Deficiency or Research, edits and ends and restores them, and removes a
 * binding while the course stays — never an undergraduate programme's structure, an undergraduate course, a level below 700.
 * An ICT support agent in service reads the structure and allocates courses across the University (the baseline), but binds,
 * edits and sets prerequisites only with what a posting grants, within its faculty; a change made on a ticket the agent can
 * see is put on the ticket's timeline, a ticket they cannot see is refused. A prerequisite never loops; the structure's checks
 * find what is wrong. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgProgrammeStructureIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    /** a postgraduate programme, its department and faculty; an undergraduate programme of another faculty */
    String pg;
    String pgDept;
    String pgFaculty;
    String ug;
    String ugDept;
    String tag;

    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    private static int status(ResponseEntity<Map> r) { return r.getStatusCode().value(); }

    private static String code(ResponseEntity<Map> r) { return r.getBody() == null ? null : String.valueOf(r.getBody().get("code")); }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    /** a course code of the standard form no other run uses */
    private static String newCode(int hundreds) {
        ThreadLocalRandom r = ThreadLocalRandom.current();
        return "Z" + (char) ('A' + r.nextInt(26)) + (char) ('A' + r.nextInt(26)) + " " + hundreds + String.format("%02d", r.nextInt(100));
    }

    private void course(String code, int level, String dept) {
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + code,
                Map.of("title", "Structure check " + code, "units", 3, "semester", 1, "level", level, "deptCode", dept, "kind", "Core", "state", "LIVE")));
    }

    private String office(String office, String who) {
        UUID p = it.person("ZZ-PGS-" + who, "ZZPGS" + who);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, :o, 'platform', NULL, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = :o AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", p).param("o", office).update());
        return TestTokens.token(p, List.of(office));
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(ThreadLocalRandom.current().nextInt(100000, 999999));
        Map<String, Object> p = jdbc.sql("""
                SELECT p.code, p.dept_code, d.faculty_code FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code
                 WHERE p.category = 'POST GRADUATE' AND NOT coalesce(p.archived, false) ORDER BY p.code LIMIT 1
                """).query().singleRow();
        pg = String.valueOf(p.get("code"));
        pgDept = String.valueOf(p.get("dept_code"));
        pgFaculty = String.valueOf(p.get("faculty_code"));
        Map<String, Object> u = jdbc.sql("""
                SELECT p.code, p.dept_code FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code
                 WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false) AND d.faculty_code <> :f ORDER BY p.code LIMIT 1
                """).param("f", pgFaculty).query().singleRow();
        ug = String.valueOf(u.get("code"));
        ugDept = String.valueOf(u.get("dept_code"));
    }

    /** Oct 2026: the School's course upload is shown row by row before anything is written — a new course, a course the pool
     *  holds (bound as it is), a programme that is not a postgraduate programme on record */
    @Test
    void theCourseUploadIsPreviewedRowByRowBeforeAnythingIsWritten() {
        String sec = office("pgsecretary", "PRV" + tag);
        String fresh = newCode(8);
        String pooled = newCode(8);
        while (pooled.equals(fresh)) pooled = newCode(8);
        course(pooled, 800, pgDept);
        Map<String, Object> pv = ok(it.call(sec, HttpMethod.POST, "/api/v1/pg/coursework/courses/import/preview", Map.of("rows", List.of(
                Map.of("programme", pg, "code", fresh, "title", "Preview new " + tag, "units", "3", "kind", "Core", "semester", "1"),
                Map.of("programme", pg, "code", pooled, "title", "Another title", "units", "3", "kind", "Elective", "semester", "1"),
                Map.of("programme", "No such programme " + tag, "code", fresh, "title", "Preview", "units", "3", "kind", "Core", "semester", "1"),
                Map.of("programme", ug, "code", fresh, "title", "Preview", "units", "3", "kind", "Core", "semester", "1")))));
        assertThat(l(pv.get("rows")).stream().map(r -> r.get("outcome")).toList()).containsExactly("NEW_COURSE", "EXISTING_COURSE", "NO_PROGRAMME", "NO_PROGRAMME");
        assertThat(String.valueOf(l(pv.get("rows")).get(1).get("message"))).startsWith("Existing course found: " + pooled);
        assertThat(pv.get("willWrite")).isEqualTo(2);
        assertThat(l(pv.get("rows")).get(2).get("level")).isNull();   // no level read for a programme not found
        // nothing written by the preview
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :c").param("c", fresh).query(Long.class).single()).isZero();
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.pg_course WHERE code IN (:a, :b)").param("a", fresh).param("b", pooled).query(Long.class).single()).isZero();
    }

    @Test
    void theSchoolKeepsItsProgrammesStructuresOnTheOnePool() {
        String sec = office("pgsecretary", "SEC" + tag);
        // the School's programme picker holds postgraduate programmes only
        List<Map<String, Object>> progs = it.getList(sec, "/api/v1/catalogue/programmes").getBody();
        assertThat(progs).isNotEmpty().allMatch(x -> "POST GRADUATE".equals(x.get("category")));

        // a new postgraduate course: one record, bound at once as Research; never below 700 level
        String research = newCode(8);
        Map<String, Object> made = ok(it.call(sec, HttpMethod.POST, "/api/v1/catalogue/courses", Map.of("code", research, "title", "Dissertation " + tag, "units", 6, "semester", 1,
                "level", 800, "dept", pgDept, "kind", "Core", "offers", List.of(Map.of("programme", pg, "level", 800, "basis", "Research")))));
        assertThat(made.get("bound")).isEqualTo(1);
        assertThat(code(it.call(sec, HttpMethod.POST, "/api/v1/catalogue/courses", Map.of("code", newCode(3), "title", "Too low", "units", 3, "semester", 1,
                "level", 300, "dept", pgDept, "kind", "Core")))).isEqualTo("STRUCTURE_PG_ONLY");
        // a course the School adds on its own desk lands on the pool too, at no second record (the desk reads the pool)
        List<Map<String, Object>> desk = it.getList(sec, "/api/v1/pg/coursework/courses?programme=" + pg).getBody();
        assertThat(desk).anyMatch(r -> research.equals(r.get("code")) && "RESEARCH".equals(r.get("kind")));

        // an existing course of the pool bound at a postgraduate level and basis; an undergraduate level or GST refused
        String methods = newCode(7);
        course(methods, 700, pgDept);
        ok(it.call(sec, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", pg, "course", methods, "level", 700, "basis", "Deficiency")));
        assertThat(code(it.call(sec, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", pg, "course", methods, "level", 300, "basis", "Core")))).isEqualTo("CAT_PG_LEVEL");
        assertThat(code(it.call(sec, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", pg, "course", methods, "level", 800, "basis", "GST")))).isEqualTo("CAT_BASIS");
        // an undergraduate programme's structure, and a course an undergraduate programme takes, are not the School's
        assertThat(code(it.call(sec, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", ug, "course", methods, "level", 100)))).isEqualTo("STRUCTURE_PG_ONLY");
        String ugCourse = newCode(2);
        course(ugCourse, 200, ugDept);
        ok(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", ug, "course", ugCourse, "level", 200)));
        assertThat(code(it.call(sec, HttpMethod.PUT, "/api/v1/catalogue/courses/" + ugCourse, Map.of("title", "Renamed by the School", "units", 3, "semester", 1, "level", 200)))).isEqualTo("STRUCTURE_PG_ONLY");
        // the undergraduate desk keeps its own rule: no 700-level binding into an undergraduate programme
        assertThat(code(it.call(academic, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", ug, "course", ugCourse, "level", 700)))).isEqualTo("CAT_UG_LEVEL");

        // the structure as the School reads it: its levels and bases, its courses, what it may do
        Map<String, Object> structure = ok(it.get(sec, "/api/v1/catalogue/structure?prog=" + pg));
        assertThat((List<Integer>) structure.get("levels")).containsExactly(700, 800, 900);
        assertThat((List<String>) structure.get("bases")).contains("Deficiency", "Research").doesNotContain("GST");
        assertThat(l(structure.get("rows"))).anyMatch(r -> research.equals(r.get("code")) && "Research".equals(r.get("basis")))
                .anyMatch(r -> methods.equals(r.get("code")) && Integer.valueOf(700).equals(r.get("level")));
        assertThat(((Map<String, Object>) structure.get("may")).get("change")).isEqualTo(true);

        // edited: the title; a level below 700 refused; ended (deactivated) and restored, never deleted
        ok(it.call(sec, HttpMethod.PUT, "/api/v1/catalogue/courses/" + methods, Map.of("title", "Research Methods " + tag, "units", 3, "semester", 1, "level", 700)));
        assertThat(code(it.call(sec, HttpMethod.PUT, "/api/v1/catalogue/courses/" + methods, Map.of("title", "x", "units", 3, "semester", 1, "level", 400)))).isEqualTo("STRUCTURE_PG_ONLY");
        assertThat(ok(it.call(sec, HttpMethod.POST, "/api/v1/catalogue/courses/" + methods + "/end", Map.of())).get("state")).isEqualTo("ENDED");
        assertThat(ok(it.call(sec, HttpMethod.POST, "/api/v1/catalogue/courses/" + methods + "/restore", Map.of())).get("state")).isEqualTo("LIVE");
        assertThat(status(it.call(sec, HttpMethod.DELETE, "/api/v1/catalogue/courses/" + methods, null))).isEqualTo(403);

        // the School's course list holds postgraduate courses only
        Map<String, Object> list = ok(it.get(sec, "/api/v1/catalogue/courses/list?q=" + tag.substring(0, 4)));
        assertThat(((Map<String, Object>) list.get("scope")).get("ptype")).isEqualTo("PG");
        Map<String, Object> mine = ok(it.get(sec, "/api/v1/catalogue/courses/list?q=" + ugCourse));
        assertThat(l(mine.get("rows"))).noneMatch(r -> ugCourse.equals(r.get("code")));

        // removed from the programme: the binding goes, the course stays; a ticket is the support desk's
        assertThat(code(it.call(sec, HttpMethod.DELETE, "/api/v1/catalogue/structure/bind?programme=" + pg + "&course=" + methods + "&level=700&ticket=TICK-0000-00000", null))).isEqualTo("STRUCTURE_TICKET");
        assertThat(ok(it.call(sec, HttpMethod.DELETE, "/api/v1/catalogue/structure/bind?programme=" + pg + "&course=" + methods + "&level=700", null)).get("removed")).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code = :c").param("c", methods).query(Integer.class).single()).isEqualTo(1);

        // the School's dashboard counts
        Map<String, Object> summary = ok(it.get(sec, "/api/v1/catalogue/structure/pg-summary"));
        assertThat(((Number) summary.get("programmes_with_courses")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) summary.get("courses")).intValue()).isGreaterThanOrEqualTo(1);
        List<Map<String, Object>> withCourses = it.getList(sec, "/api/v1/catalogue/structure/programmes?empty=false").getBody();
        assertThat(withCourses).anyMatch(r -> pg.equals(r.get("code"))).allMatch(r -> "POST GRADUATE".equals(r.get("category")));
    }

    @Test
    void anAgentWorksTheStructureWithWhatThePostingGrantsAndAllocatesEverywhere() {
        UUID agent = it.person("ZZ-PGS-AG" + tag, "ZZPGSAGENT" + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'ictagent', 'platform', NULL, 'integration test', :p, current_date)
                """).param("p", agent).update());
        String tok = TestTokens.token(agent, List.of("ictagent"));
        String target = newCode(8);
        course(target, 800, pgDept);

        // in service, never posted: reads the structure and allocates across the University; binds nothing
        Map<String, Object> access = ok(it.get(tok, "/api/v1/catalogue/structure/access"));
        assertThat((List<String>) access.get("capabilities")).containsExactly("VIEW_PROGRAMME_STRUCTURE");
        assertThat(((Map<String, Object>) ok(it.get(tok, "/api/v1/catalogue/structure?prog=" + pg)).get("may")).get("change")).isEqualTo(false);
        assertThat(code(it.call(tok, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", pg, "course", target, "level", 800)))).isEqualTo("STRUCTURE_CAPABILITY");
        String session = jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse("2133/2134");
        assertThat(status(it.get(tok, "/api/v1/allocation/desk/overview?session=" + session + "&semester=1"))).isEqualTo(200);
        ResponseEntity<Map> bulk = it.call(tok, HttpMethod.POST, "/api/v1/allocation/import/validate", Map.of("rows", List.of(Map.of("row", 2, "staffId", "ZZ-NONE", "courseCode", target, "session", session, "semester", "1"))));
        assertThat(code(bulk)).isEqualTo("ALLOC_CAPABILITY");   // the bulk import stays the Head's to grant

        // a posting over the programme's faculty with binding, editing and prerequisites: within it, not outside
        it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'FACULTY', :f, ARRAY['BIND_COURSES','EDIT_COURSES','MANAGE_PREREQUISITES'])
                """).param("p", agent).param("f", pgFaculty).update());
        assertThat((List<String>) ok(it.get(tok, "/api/v1/catalogue/structure/access")).get("capabilities"))
                .contains("VIEW_PROGRAMME_STRUCTURE", "BIND_COURSES", "EDIT_COURSES", "MANAGE_PREREQUISITES");
        String ugCourse = newCode(1);
        course(ugCourse, 100, ugDept);
        assertThat(code(it.call(tok, HttpMethod.POST, "/api/v1/catalogue/structure/bind", Map.of("programme", ug, "course", ugCourse, "level", 100)))).isEqualTo("STRUCTURE_SCOPE");

        // on a ticket the agent works: bound, and on the ticket's timeline; a ticket the agent cannot see refused
        int n = ThreadLocalRandom.current().nextInt(10000, 99998);
        UUID mine = ticket("TICK-4710-" + n, agent, agent);
        ticket("TICK-4710-" + (n + 1), agent, null);
        assertThat(status(it.call(tok, HttpMethod.POST, "/api/v1/catalogue/structure/bind?ticket=TICK-4710-" + (n + 1), Map.of("programme", pg, "course", target, "level", 800)))).isEqualTo(403);
        ok(it.call(tok, HttpMethod.POST, "/api/v1/catalogue/structure/bind?ticket=TICK-4710-" + n, Map.of("programme", pg, "course", target, "level", 800, "basis", "Core")));
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = :t AND action = 'SUPPORT_PROGRAMME_STRUCTURE' AND to_value LIKE 'Bound %'")
                .param("t", mine).query(Integer.class).single()).isEqualTo(1);

        // prerequisites: added, a loop refused however far round, removed
        String first = newCode(7);
        course(first, 700, pgDept);
        String second = newCode(8);
        course(second, 800, pgDept);
        ok(it.call(tok, HttpMethod.POST, "/api/v1/catalogue/courses/" + target + "/prerequisites", Map.of("requires", second)));
        ok(it.call(tok, HttpMethod.POST, "/api/v1/catalogue/courses/" + second + "/prerequisites", Map.of("requires", first)));
        assertThat(code(it.call(tok, HttpMethod.POST, "/api/v1/catalogue/courses/" + first + "/prerequisites", Map.of("requires", target)))).isEqualTo("CAT_PREREQ_CYCLE");
        assertThat(code(it.call(tok, HttpMethod.POST, "/api/v1/catalogue/courses/" + first + "/prerequisites", Map.of("requires", first)))).isEqualTo("CAT_PREREQ_SELF");
        assertThat(l(ok(it.call(tok, HttpMethod.DELETE, "/api/v1/catalogue/courses/" + second + "/prerequisites?requires=" + first, null)).get("prerequisites"))).isEmpty();
        // a course outside the posting's faculty: its prerequisites are not the agent's
        assertThat(code(it.call(tok, HttpMethod.POST, "/api/v1/catalogue/courses/" + ugCourse + "/prerequisites", Map.of("requires", first)))).isEqualTo("STRUCTURE_SCOPE");

        // taken off the desk (every posting ended): neither the structure nor allocation
        it.db(() -> jdbc.sql("UPDATE helpdesk.agent_assignment SET active = false, effective_to = current_date WHERE person_id = :p").param("p", agent).update());
        assertThat(code(it.get(tok, "/api/v1/catalogue/structure?prog=" + pg))).isEqualTo("STRUCTURE_CAPABILITY");
        assertThat(code(it.get(tok, "/api/v1/allocation/desk/overview?session=" + session + "&semester=1"))).isEqualTo("ALLOC_CAPABILITY");
    }

    @Test
    void theChecksFindWhatIsWrongWithAStructure() {
        String odd = newCode(3);
        course(odd, 300, pgDept);
        String a = newCode(7);
        String b = newCode(7);
        course(a, 700, pgDept);
        course(b, 700, pgDept);
        // what the desks refuse, written behind them: a postgraduate binding at 300 level, and a prerequisite loop
        it.db(() -> {
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, 300, 'Core'), (:a, :p, 700, 'Core')")
                    .param("c", odd).param("a", a).param("p", pg).update();
            jdbc.sql("INSERT INTO catalogue.course_prerequisite (course_code, requires_code) VALUES (:a, :b), (:b, :a)").param("a", a).param("b", b).update();
            return null;
        });
        try {
            Map<String, Object> checks = ok(it.get(academic, "/api/v1/catalogue/structure/issues?category=POST_GRADUATE"));
            assertThat(l(checks.get("rows"))).anyMatch(r -> "LEVEL_OFF_PROGRAMME".equals(r.get("kind")) && odd.equals(r.get("course_code")) && pg.equals(r.get("programme_code")))
                    .anyMatch(r -> "PREREQUISITE_CYCLE".equals(r.get("kind")) && a.equals(r.get("course_code")));
            Map<String, Object> one = ok(it.get(academic, "/api/v1/catalogue/structure/issues?category=POST_GRADUATE&kind=LEVEL_OFF_PROGRAMME"));
            assertThat(l(one.get("rows"))).allMatch(r -> "LEVEL_OFF_PROGRAMME".equals(r.get("kind")));
            // the School reads its own programmes' checks whatever it asks for
            Map<String, Object> school = ok(it.get(office("pgschool", "DEAN" + tag), "/api/v1/catalogue/structure/issues?category=UNDER_GRADUATE"));
            assertThat(school.get("category")).isEqualTo("POST GRADUATE");
            // an agent taken off the desk reads no check
            UUID gone = it.person("ZZ-PGS-OFF" + tag, "ZZPGSOFF" + tag);
            it.db(() -> jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities, active, effective_to)
                    VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'GLOBAL', NULL, ARRAY['VIEW_STUDENT'], false, current_date)
                    """).param("p", gone).update());
            assertThat(code(it.get(TestTokens.token(gone, List.of("ictagent")), "/api/v1/catalogue/structure/issues"))).isEqualTo("STRUCTURE_CAPABILITY");
        } finally {
            it.db(() -> {
                jdbc.sql("DELETE FROM catalogue.course_prerequisite WHERE course_code IN (:a, :b)").param("a", a).param("b", b).update();
                jdbc.sql("DELETE FROM catalogue.course_offer WHERE course_code IN (:c, :a) AND programme_code = :p").param("c", odd).param("a", a).param("p", pg).update();
                return null;
            });
        }
    }

    /** a support ticket on the agent's queue, with the agent (or no one) assigned */
    private UUID ticket(String number, UUID requester, UUID assigned) {
        return it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.ticket (number, category_id, subject, description, requester_kind, requester_id, requester_name, queue_code, faculty_code, department_code, assigned_to)
                SELECT :n, c.id, 'A course missing from registration', 'The programme does not show the course', 'STAFF', :r, 'ZZPGS', 'COURSE_REGISTRATION_SUPPORT', NULL, NULL, :a
                  FROM helpdesk.category c WHERE c.code = 'REGISTRATION'
                RETURNING id
                """).param("n", number).param("r", requester).param("a", assigned, java.sql.Types.OTHER).query(UUID.class).single());
    }
}
