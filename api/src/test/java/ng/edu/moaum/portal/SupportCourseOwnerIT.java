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
 * The ICT Support Desk edits a course and changes its owner as a Head of Department edits the department's courses (Oct 2026): the Head
 * of the desk anywhere — the course page offers both — an agent whose posting carries editing courses within the posting's faculty, on
 * a ticket the change goes on; a move out of the posting's reach is refused and nothing moves; an agent without the posting is refused,
 * a Head of Department still does not move a course. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SupportCourseOwnerIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    String tag;
    String deptA;
    String deptA2;
    String faculty;
    String deptB;

    private static int status(ResponseEntity<Map> r) {
        return r.getStatusCode().value();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    /** a course code of the standard form no other run uses */
    private static String newCode() {
        ThreadLocalRandom r = ThreadLocalRandom.current();
        return "Z" + (char) ('A' + r.nextInt(26)) + (char) ('A' + r.nextInt(26)) + " 2" + String.format("%02d", r.nextInt(100));
    }

    private String course(String dept) {
        String code = newCode();
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + code,
                Map.of("title", "Support owner check " + code, "units", 3, "semester", 1, "level", 200, "deptCode", dept, "kind", "Core", "state", "LIVE")));
        return code;
    }

    private String deptOf(String course) {
        return jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", course).query(String.class).single();
    }

    private UUID person(String office) {
        UUID p = it.person("ZZ-SCO-" + office + tag, "ZZSCO" + office.toUpperCase() + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, :o, 'platform', NULL, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = :o AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", p).param("o", office).update());
        return p;
    }

    /** a support ticket with the agent assigned */
    private UUID ticket(String number, UUID agent) {
        return it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.ticket (number, category_id, subject, description, requester_kind, requester_id, requester_name, queue_code, faculty_code, department_code, assigned_to)
                SELECT :n, c.id, 'A course under the wrong department', 'The course belongs to the other department', 'STAFF', :a, 'ZZSCO', 'COURSE_REGISTRATION_SUPPORT', NULL, NULL, :a
                  FROM helpdesk.category c WHERE c.code = 'REGISTRATION'
                RETURNING id
                """).param("n", number).param("a", agent).query(UUID.class).single());
    }

    private ResponseEntity<Map> move(String token, String course, String dept, String ticket) {
        return it.call(token, HttpMethod.POST, "/api/v1/catalogue/courses/" + course + "/owner" + (ticket == null ? "" : "?ticket=" + ticket),
                Map.of("department", dept, "reason", "It is taught and examined by that department"));
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(ThreadLocalRandom.current().nextInt(100000, 999999));
        Map<String, Object> pair = jdbc.sql("""
                SELECT d1.code AS a, d2.code AS a2, d1.faculty_code AS f FROM ref.department d1
                  JOIN ref.department d2 ON d2.faculty_code = d1.faculty_code AND d2.code > d1.code AND d2.ended_on IS NULL
                 WHERE d1.ended_on IS NULL AND d1.faculty_code IS NOT NULL ORDER BY d1.code, d2.code LIMIT 1
                """).query().singleRow();
        deptA = String.valueOf(pair.get("a"));
        deptA2 = String.valueOf(pair.get("a2"));
        faculty = String.valueOf(pair.get("f"));
        deptB = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL AND faculty_code IS DISTINCT FROM :f ORDER BY code LIMIT 1")
                .param("f", faculty).query(String.class).single();
    }

    @Test
    void theSupportDeskEditsACourseAndChangesItsOwnerWithinItsReach() {
        // the Head of the desk: the course page offers both; edited, then moved, anywhere
        String head = TestTokens.token(person("helpdeskhead"), List.of("helpdeskhead"));
        String x = course(deptA);
        Map<String, Object> may = (Map<String, Object>) ok(it.get(head, "/api/v1/catalogue/courses/" + x + "/detail")).get("may");
        assertThat(may).containsEntry("edit", true).containsEntry("changeOwner", true);
        ok(it.call(head, HttpMethod.PUT, "/api/v1/catalogue/courses/" + x, Map.of("title", "Support owner check edited", "units", 2, "semester", 1, "level", 200)));
        assertThat(jdbc.sql("SELECT title FROM catalogue.course WHERE code = :c").param("c", x).query(String.class).single()).isEqualTo("Support owner check edited");
        assertThat(ok(move(head, x, deptB, null))).containsEntry("dept_code", deptB);
        assertThat(deptOf(x)).isEqualTo(deptB);

        // an agent without a posting that carries editing courses: refused
        UUID agent = person("ictagent");
        String tok = TestTokens.token(agent, List.of("ictagent"));
        String y = course(deptA);
        assertThat(code(move(tok, y, deptA2, null))).isEqualTo("STRUCTURE_CAPABILITY");
        assertThat(deptOf(y)).isEqualTo(deptA);

        // posted over the faculty with editing courses: within it on a ticket — moved, on the ticket's timeline; out of it, refused, nothing moves
        it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'FACULTY', :f, ARRAY['EDIT_COURSES'])
                """).param("p", agent).param("f", faculty).update());
        assertThat((Map<String, Object>) ok(it.get(tok, "/api/v1/catalogue/courses/" + y + "/detail")).get("may")).containsEntry("changeOwner", true);
        String number = "TICK-6560-" + ThreadLocalRandom.current().nextInt(10000, 99999);
        UUID t = ticket(number, agent);
        assertThat(ok(move(tok, y, deptA2, number))).containsEntry("dept_code", deptA2);
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = :t AND to_value LIKE 'Changed the owner of " + y + " from " + deptA + " to " + deptA2 + "%'")
                .param("t", t).query(Integer.class).single()).isEqualTo(1);
        ok(it.call(tok, HttpMethod.PUT, "/api/v1/catalogue/courses/" + y, Map.of("title", "Support owner check by the agent", "units", 3, "semester", 1, "level", 200)));
        ResponseEntity<Map> out = move(tok, y, deptB, null);
        assertThat(code(out)).as(String.valueOf(out.getBody())).isEqualTo("STRUCTURE_SCOPE");
        assertThat(deptOf(y)).isEqualTo(deptA2);
        String z = course(deptB);
        assertThat((Map<String, Object>) ok(it.get(tok, "/api/v1/catalogue/courses/" + z + "/detail")).get("may")).containsEntry("changeOwner", false);
        assertThat(code(move(tok, z, deptA, null))).isEqualTo("STRUCTURE_SCOPE");
        assertThat(deptOf(z)).isEqualTo(deptB);

        // a Head of Department still does not move a course
        assertThat(status(move(ItSupport.token("hod"), z, deptA, null))).isEqualTo(403);
    }
}
