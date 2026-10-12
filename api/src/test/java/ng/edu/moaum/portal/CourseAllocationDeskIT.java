package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * Course allocation from the Director of ICT's and the ICT Support Desk's dashboards (V408): the Director works every class of
 * the University through the one allocation engine — checked first, a duplicate refused in the University's words, a
 * reassignment only with its reason, a co-lecturer across departments, removed only with a reason, an inactive or non-teaching
 * person refused — and every act is on the allocation history (the department desk's too); the lecturer is told and finds the
 * class on their teaching page. A CPO works only the faculty their posting names, only with the capabilities the Head granted,
 * a class outside refused whatever the address says, a ticket they cannot see refused, the bulk import held to the posting
 * row by row; the department desk's own acts stay closed to them. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseAllocationDeskIT {

    static final String SESSION = "2133/2134";
    static final String DESK = "/api/v1/allocation/desk";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic = ItSupport.token("academic");
    String director;
    String agentTok;
    UUID agent;
    UUID lecturerA;
    UUID lecturerB;
    UUID lecturerC;
    String otherDept;
    UUID mine1;
    UUID mine2;
    UUID outside;
    /** the history before this run is another run's: every count here is of what this run did */
    String since;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    private UUID lecturer(String staff, String surname, String dept) {
        UUID id = it.person(staff, surname);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'lecturer', 'department', :d, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'lecturer' AND a.scope_id = :d AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", id).param("d", dept).update());
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = lower(:s) || '@example.com', ended_on = NULL, ended_reason = NULL WHERE id = :p").param("s", staff).param("p", id).update());
        return id;
    }

    private void course(String code, String title, int units, String dept) {
        ResponseEntity<Map> r = it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + code,
                Map.of("title", title, "units", units, "semester", 1, "level", 300, "deptCode", dept, "kind", "Core", "state", "LIVE"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
    }

    private UUID offering(String code) {
        ResponseEntity<Map> r = it.call(academic, HttpMethod.PUT, "/api/v1/registration/offerings", Map.of("courseCode", code, "session", SESSION, "semester", 1));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return UUID.fromString(String.valueOf(r.getBody().get("id")));
    }

    private void posting(String... capabilities) {
        it.db(() -> {
            jdbc.sql("DELETE FROM helpdesk.agent_assignment WHERE person_id = :p").param("p", agent).update();
            if (capabilities.length > 0) {
                jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'FACULTY', 'SC', :c)")
                        .param("p", agent).param("c", capabilities).update();
            }
            return null;
        });
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2133);
        director = TestTokens.token(it.person("ZZ-ALD-ICT", "ZZALDDIRECTOR"), List.of("ict"));
        agent = it.person("ZZ-ALD-CPO", "ZZALDAGENT");
        agentTok = TestTokens.token(agent, List.of("ictagent"));
        lecturerA = lecturer("ZZ-ALD-A", "ZZALDA", "MTC");                        // Mathematics and Computer Science · Science
        lecturerB = lecturer("ZZ-ALD-B", "ZZALDB", "MTC");
        otherDept = jdbc.sql("SELECT code FROM ref.department WHERE faculty_code <> 'SC' AND ended_on IS NULL ORDER BY code LIMIT 1").query(String.class).single();
        lecturerC = lecturer("ZZ-ALD-C", "ZZALDC", otherDept);
        course("ZZD 301", "Allocation desk one", 3, "MTC");
        course("ZZD 302", "Allocation desk two", 2, "MTC");
        course("ZZE 301", "Another faculty's course", 3, otherDept);
        mine1 = offering("ZZD 301");
        mine2 = offering("ZZD 302");
        outside = offering("ZZE 301");
        posting();
        it.db(() -> {
            jdbc.sql("DELETE FROM catalogue.offering_teacher WHERE offering_id IN (SELECT id FROM catalogue.offering WHERE session = :s)").param("s", SESSION).update();
            jdbc.sql("UPDATE catalogue.offering SET lecturer_id = NULL, second_examiner_id = NULL, allocated_on = NULL WHERE session = :s").param("s", SESSION).update();
            return null;
        });
        since = jdbc.sql("SELECT clock_timestamp()::text").query(String.class).single();
    }

    private ResponseEntity<Map> allocate(String tok, UUID offering, UUID lecturer, String reason, String ticket) {
        Map<String, Object> body = new HashMap<>();
        body.put("lecturer", lecturer);
        if (reason != null) body.put("reason", reason);
        if (ticket != null) body.put("ticket", ticket);
        return it.call(tok, HttpMethod.POST, DESK + "/classes/" + offering + "/lecturer", body);
    }

    private static int status(ResponseEntity<?> r) {
        return r.getStatusCode().value();
    }

    private static String code(ResponseEntity<Map> r) {
        return String.valueOf(r.getBody() == null ? null : r.getBody().get("code"));
    }

    private List<String> events(UUID offering) {
        return jdbc.sql("SELECT action || '/' || role || '/' || source FROM catalogue.allocation_event WHERE offering_id = :o AND at >= :t::timestamptz ORDER BY at, action")
                .param("o", offering).param("t", since).query(String.class).list();
    }

    @Test
    void theDirectorAllocatesAcrossTheUniversityThroughTheOneEngineAndEveryActIsOnTheHistory() {
        // the dashboard and the list: the University's classes, the unallocated among them
        Map<String, Object> over = it.get(director, DESK + "/overview?session=" + SESSION + "&semester=1").getBody();
        assertThat(((Number) over.get("unallocated")).intValue()).isGreaterThanOrEqualTo(3);
        List<Map<String, Object>> rows = l(it.get(director, DESK + "/classes?session=" + SESSION + "&semester=1&status=UNALLOCATED&q=ZZ").getBody().get("rows"));
        assertThat(rows).extracting(r -> r.get("course_code")).contains("ZZD 301", "ZZD 302", "ZZE 301");

        // the lecturer found by staff number; the checks before anything is written
        List<Map<String, Object>> found = it.getList(director, DESK + "/lecturers?q=ZZ-ALD-A&session=" + SESSION + "&semester=1").getBody();
        assertThat(found).extracting(r -> String.valueOf(r.get("id"))).containsExactly(lecturerA.toString());
        Map<String, Object> checks = it.get(director, DESK + "/check?offering=" + mine1 + "&lecturer=" + lecturerA).getBody();
        assertThat(checks.get("ok")).isEqualTo(true);
        assertThat(l(checks.get("checks"))).extracting(c -> c.get("code") + "/" + c.get("level")).contains("COURSE/OK", "ACTIVE/OK", "TEACHING/OK", "DUPLICATE/OK", "LOAD/OK");

        // allocated through the engine; the same allocation again refused in the University's words
        ResponseEntity<Map> done = allocate(director, mine1, lecturerA, null, null);
        assertThat(status(done)).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(String.valueOf(done.getBody().get("message"))).startsWith("Course successfully allocated to");
        assertThat(jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE id = :o").param("o", mine1).query(UUID.class).single()).isEqualTo(lecturerA);
        ResponseEntity<Map> again = allocate(director, mine1, lecturerA, null, null);
        assertThat(status(again)).isEqualTo(422);
        assertThat(String.valueOf(again.getBody().get("detail"))).isEqualTo("Course already allocated to this lecturer for the selected session and semester.");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :o AND channel = 'EMAIL' AND subject LIKE 'Course allocation: ZZD 301%'").param("o", mine1)
                .query(Integer.class).single()).isGreaterThanOrEqualTo(1);

        // reassigned only with a reason; the history keeps who had it
        assertThat(code(allocate(director, mine1, lecturerB, null, null))).isEqualTo("ALLOC_REASON");
        assertThat(status(allocate(director, mine1, lecturerB, "Dr ZZALDA is on sabbatical this semester", null))).isEqualTo(200);
        assertThat(jdbc.sql("""
                SELECT count(*) FROM catalogue.allocation_event WHERE offering_id = :o AND action = 'REASSIGNED' AND lecturer_id = :b AND previous_lecturer_id = :a
                   AND reason = 'Dr ZZALDA is on sabbatical this semester' AND source = 'DESK' AND actor_office = 'ict' AND at >= :t::timestamptz
                """).param("t", since).param("o", mine1).param("a", lecturerA).param("b", lecturerB).query(Integer.class).single()).isEqualTo(1);
        // the lecturer finds the class on their teaching page; the former lead does not lead it any more
        List<Map<String, Object>> taught = it.getList(TestTokens.token(lecturerB, List.of("lecturer")), "/api/v1/allocation/history?scope=me").getBody();
        assertThat(taught).extracting(r -> r.get("course_code") + "/" + r.get("role")).contains("ZZD 301/Lecturer");

        // a co-lecturer from another faculty: teaching across departments allowed, said; twice refused; removed only with a reason
        Map<String, Object> cross = it.get(director, DESK + "/check?offering=" + mine1 + "&lecturer=" + lecturerC + "&role=CO_LECTURER").getBody();
        assertThat(l(cross.get("checks"))).anyMatch(c -> "TEACHING".equals(c.get("code")) && String.valueOf(c.get("words")).contains("teaching across departments"));
        assertThat(status(it.call(director, HttpMethod.POST, DESK + "/classes/" + mine1 + "/co-lecturers", Map.of("lecturer", lecturerC)))).isEqualTo(200);
        assertThat(code(it.call(director, HttpMethod.POST, DESK + "/classes/" + mine1 + "/co-lecturers", Map.of("lecturer", lecturerC)))).isEqualTo("ALLOC_DUPLICATE");
        assertThat(code(it.call(director, HttpMethod.POST, DESK + "/classes/" + mine1 + "/co-lecturers/" + lecturerC + "/remove", Map.of()))).isEqualTo("ALLOC_REASON");
        assertThat(status(it.call(director, HttpMethod.POST, DESK + "/classes/" + mine1 + "/co-lecturers/" + lecturerC + "/remove",
                Map.of("reason", "Added to the wrong class")))).isEqualTo(200);
        assertThat(events(mine1)).containsSubsequence("ALLOCATED/LECTURER/DESK", "REASSIGNED/LECTURER/DESK", "CO_LECTURER_ADDED/CO_LECTURER/DESK", "CO_LECTURER_REMOVED/CO_LECTURER/DESK");

        // a person who has left, and one who holds no lecturer office, are refused with the reason
        it.db(() -> jdbc.sql("UPDATE iam.person SET ended_on = current_date - 1, ended_reason = 'Retired (integration test)' WHERE id = :p").param("p", lecturerC).update());
        assertThat(code(allocate(director, mine2, lecturerC, null, null))).isEqualTo("ALLOC_ACTIVE");
        UUID noOffice = it.person("ZZ-ALD-N", "ZZALDNOOFFICE");
        assertThat(code(allocate(director, mine2, noOffice, null, null))).isEqualTo("ALLOC_TEACHING");

        // the department desk's allocation is on the same history, as the department's
        String hod = it.officer("hod", "department", "MTC");
        ResponseEntity<Map> byHod = it.call(hod, HttpMethod.POST, "/api/v1/allocation/" + mine2, Map.of("lecturer", lecturerA));
        assertThat(status(byHod)).as(String.valueOf(byHod.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT actor_office FROM catalogue.allocation_event WHERE offering_id = :o AND action = 'ALLOCATED' AND at >= :t::timestamptz").param("o", mine2).param("t", since).query(String.class).single()).isEqualTo("hod");

        // the class's own page: who teaches it and its history
        Map<String, Object> one = it.get(director, DESK + "/classes/" + mine1).getBody();
        assertThat(m(one.get("lecturer")).get("id")).isEqualTo(lecturerB.toString());
        assertThat(l(one.get("history"))).hasSizeGreaterThanOrEqualTo(4);
    }

    @Test
    void aCpoAllocatesOnlyWithinTheirPostingWithWhatTheHeadGranted() {
        // no posting carries course allocation: nothing is reachable
        assertThat(code(it.get(agentTok, DESK + "/overview?session=" + SESSION + "&semester=1"))).isEqualTo("ALLOC_CAPABILITY");

        posting("VIEW_STUDENT", "VIEW_ALLOCATIONS", "ALLOCATE_COURSES");
        List<Map<String, Object>> rows = l(it.get(agentTok, DESK + "/classes?session=" + SESSION + "&semester=1&q=ZZ").getBody().get("rows"));
        assertThat(rows).extracting(r -> r.get("course_code")).contains("ZZD 301").doesNotContain("ZZE 301");
        // another faculty's class refused, read or written, whatever the address says
        assertThat(code(it.get(agentTok, DESK + "/classes/" + outside))).isEqualTo("ALLOC_SCOPE");
        assertThat(code(allocate(agentTok, outside, lecturerA, null, null))).isEqualTo("ALLOC_SCOPE");
        // the department desk's own acts stay the academic offices'
        assertThat(status(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/" + mine1, Map.of("lecturer", lecturerA)))).isEqualTo(403);

        // on a ticket of their own queue: the allocation and the ticket's timeline; a ticket they cannot see refused
        int n = java.util.concurrent.ThreadLocalRandom.current().nextInt(10000, 99998);
        String mineNo = "TICK-2133-" + n;
        String otherNo = "TICK-2133-" + (n + 1);
        UUID tkt = ticket(mineNo, "SC", "MTC");
        ticket(otherNo, null, otherDept);
        assertThat(code(allocate(agentTok, mine1, lecturerA, null, otherNo))).isEqualTo("ALLOC_TICKET_SCOPE");
        assertThat(code(allocate(agentTok, mine1, lecturerA, null, "TICK-0000-00000"))).isEqualTo("ALLOC_TICKET");
        assertThat(status(allocate(agentTok, mine1, lecturerA, "The student reported the class had no lecturer", mineNo))).isEqualTo(200);
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.allocation_event WHERE offering_id = :o AND ticket_id = :t AND actor_office = 'ictagent' AND at >= :since::timestamptz").param("since", since)
                .param("o", mine1).param("t", tkt).query(Integer.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = :t AND action = 'SUPPORT_COURSE_ALLOCATION'").param("t", tkt).query(Integer.class).single()).isEqualTo(1);

        // what the posting does not carry: removing a co-lecturer, the bulk import
        assertThat(status(it.call(agentTok, HttpMethod.POST, DESK + "/classes/" + mine1 + "/co-lecturers", Map.of("lecturer", lecturerB)))).isEqualTo(200);
        assertThat(code(it.call(agentTok, HttpMethod.POST, DESK + "/classes/" + mine1 + "/co-lecturers/" + lecturerB + "/remove", Map.of("reason", "Not this class")))).isEqualTo("ALLOC_CAPABILITY");
        List<Map<String, Object>> file = List.of(
                Map.of("row", 2, "staffId", "ZZ-ALD-B", "courseCode", "ZZD 302", "session", SESSION, "semester", "1"),
                Map.of("row", 3, "staffId", "ZZ-ALD-C", "courseCode", "ZZE 301", "session", SESSION, "semester", "1"));
        assertThat(code(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/import/validate", Map.of("rows", file)))).isEqualTo("ALLOC_CAPABILITY");
        posting("VIEW_ALLOCATIONS", "ALLOCATE_COURSES", "BULK_ALLOCATE");
        Map<String, Object> judged = it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/import/validate", Map.of("rows", file)).getBody();
        assertThat(l(judged.get("rows"))).extracting(r -> r.get("courseCode") + "/" + r.get("status")).containsExactly("ZZD 302/VALID", "ZZE 301/ERROR");
        assertThat(l(judged.get("rows")).get(1).get("codes").toString()).contains("OUT_OF_SCOPE");
    }

    @Test
    void theDepartmentDeskReadsTheSameChecksAndHistoryAndSaysWhy() {
        String hod = it.officer("hod", "department", "MTC");
        String base = "/api/v1/allocation/";
        // the checks the ICT desk reads, for the department's own classes only
        Map<String, Object> checks = it.get(hod, base + mine1 + "/check?lecturer=" + lecturerA).getBody();
        assertThat(checks.get("ok")).isEqualTo(true);
        assertThat(code(it.get(hod, base + outside + "/check?lecturer=" + lecturerA))).isEqualTo("ALLOC_DEPT");
        // a person who holds no lecturer office takes no class here either
        UUID noOffice = it.person("ZZ-ALD-N", "ZZALDNOOFFICE");
        assertThat(code(it.call(hod, HttpMethod.POST, base + mine1, Map.of("lecturer", noOffice)))).isEqualTo("ALLOC_TEACHING");
        // allocated; the lead replaced only with a reason; the same lead with a new second examiner needs none
        assertThat(status(it.call(hod, HttpMethod.POST, base + mine1, Map.of("lecturer", lecturerA)))).isEqualTo(200);
        assertThat(code(it.call(hod, HttpMethod.POST, base + mine1, Map.of("lecturer", lecturerB)))).isEqualTo("ALLOC_REASON");
        assertThat(status(it.call(hod, HttpMethod.POST, base + mine1, Map.of("lecturer", lecturerB, "reason", "Dr ZZALDA moved to postgraduate teaching")))).isEqualTo(200);
        assertThat(status(it.call(hod, HttpMethod.POST, base + mine1, Map.of("lecturer", lecturerB, "secondExaminer", lecturerA)))).isEqualTo(200);
        // a co-lecturer from another faculty, removed only with a reason
        assertThat(status(it.call(hod, HttpMethod.POST, base + mine1 + "/teachers", Map.of("lecturer", lecturerC)))).isEqualTo(200);
        assertThat(code(it.call(hod, HttpMethod.DELETE, base + mine1 + "/teachers/" + lecturerC, null))).isEqualTo("ALLOC_REASON");
        assertThat(status(it.call(hod, HttpMethod.DELETE, b -> b.path(base + mine1 + "/teachers/" + lecturerC).queryParam("reason", "Added by mistake").build(), null))).isEqualTo(200);
        // the class's history and the department's: the record the ICT desk reads, another department's class refused
        List<Map<String, Object>> history = it.getList(hod, base + mine1 + "/history").getBody();
        assertThat(history).anyMatch(h -> "REASSIGNED".equals(h.get("action")) && "Dr ZZALDA moved to postgraduate teaching".equals(h.get("reason")) && "hod".equals(h.get("actor_office")));
        assertThat(history).anyMatch(h -> "CO_LECTURER_REMOVED".equals(h.get("action")) && "Added by mistake".equals(h.get("reason")));
        assertThat(history).anyMatch(h -> "SECOND_EXAMINER_SET".equals(h.get("action")));
        List<Map<String, Object>> dept = it.getList(hod, base + "events?dept=MTC&session=" + SESSION + "&semester=1").getBody();
        assertThat(dept).extracting(h -> h.get("course_code")).contains("ZZD 301").doesNotContain("ZZE 301");
        assertThat(code(it.get(hod, base + outside + "/history"))).isEqualTo("ALLOC_DEPT");
    }

    /** a ticket raised by a member of staff, in the agent's posted queue, for a department */
    private UUID ticket(String number, String faculty, String dept) {
        return it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.ticket (number, category_id, subject, description, requester_kind, requester_id, requester_name, queue_code, faculty_code, department_code)
                SELECT :n, c.id, 'A class with no lecturer', 'The class shows no lecturer on the timetable', 'STAFF', :r, 'ZZALDA', 'STUDENT_BIODATA_SUPPORT',
                       coalesce(:f, (SELECT faculty_code FROM ref.department WHERE code = :d)), :d
                  FROM helpdesk.category c WHERE c.code = 'REGISTRATION'
                RETURNING id
                """).param("n", number).param("r", lecturerA).param("f", faculty, java.sql.Types.VARCHAR).param("d", dept).query(UUID.class).single());
    }
}
