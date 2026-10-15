package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * V478: a department's course allocation template, issued from the register and checked on upload against the template the
 * portal issued. An ICT support agent whose posting carries the bulk allocation over the Faculty of Science downloads the
 * Mathematics and Computer Science template — only that department's classes of the kind and semester, its lecturers — and
 * is refused another faculty's department; the completed file is previewed row by row (a lecturer of another department,
 * another department's course, an unknown course, a duplicate, another session refused) before the valid rows are imported,
 * the import carrying the template and the ticket; a department written over in the file, or a template uploaded for
 * another department, is refused whole. A postgraduate template holds only postgraduate classes, allocated once the School
 * has opened them; the School uploads a postgraduate template only. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class AllocationTemplateIT {

    static final String SESSION = "2134/2135";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    String agentTok;
    UUID agent;
    String otherDept;
    UUID lecA;
    UUID lecC;
    String tag;

    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    static String code(ResponseEntity<Map> r) { return r.getBody() == null ? null : String.valueOf(r.getBody().get("code")); }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private UUID lecturer(String staff, String surname, String dept) {
        UUID id = it.person(staff, surname);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, 'lecturer', 'department', :d, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'lecturer' AND a.scope_id = :d AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", id).param("d", dept).update());
        it.db(() -> jdbc.sql("UPDATE iam.person SET ended_on = NULL, ended_reason = NULL WHERE id = :p").param("p", id).update());
        return id;
    }

    private void course(String code, int level, String dept) {
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/registration/courses/" + code,
                Map.of("title", "Template check " + code, "units", 2, "semester", 1, "level", level, "deptCode", dept, "kind", "Core", "state", "LIVE")));
    }

    private Map<String, Object> row(int n, String staff, String course, String role) {
        Map<String, Object> r = new HashMap<>();
        r.put("row", n);
        r.put("staffId", staff);
        r.put("courseCode", course);
        r.put("session", SESSION);
        r.put("semester", "1");
        r.put("role", role);
        return r;
    }

    private Map<String, Object> template(String reference, String pageDept, String fileDept, String type) {
        Map<String, Object> t = new HashMap<>();
        t.put("reference", reference);
        t.put("dept", pageDept);
        t.put("session", SESSION);
        t.put("semester", 1);
        t.put("programmeType", type);
        t.put("fileDept", fileDept);
        t.put("fileSession", SESSION);
        t.put("fileSemester", 1);
        t.put("fileProgrammeType", type);
        return t;
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2134);
        tag = String.valueOf(ThreadLocalRandom.current().nextInt(100, 999));
        otherDept = jdbc.sql("SELECT code FROM ref.department WHERE faculty_code <> 'SC' AND ended_on IS NULL ORDER BY code LIMIT 1").query(String.class).single();
        agent = it.person("ZZ-TPL-AG", "ZZTPLAGENT");
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                    SELECT gen_random_uuid(), :p, 'ictagent', 'platform', NULL, 'integration test', :p, current_date
                     WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'ictagent')
                    """).param("p", agent).update();
            jdbc.sql("DELETE FROM helpdesk.agent_assignment WHERE person_id = :p").param("p", agent).update();
            jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'FACULTY', 'SC', ARRAY['BULK_ALLOCATE'])")
                    .param("p", agent).update();
            return null;
        });
        agentTok = TestTokens.token(agent, List.of("ictagent"));
        lecA = lecturer("ZZ-TPL-A", "ZZTPLA", "MTC");
        lecturer("ZZ-TPL-B", "ZZTPLB", "MTC");
        lecC = lecturer("ZZ-TPL-C", "ZZTPLC", otherDept);
        course("ZZT 301", 300, "MTC");
        course("ZZT 302", 300, "MTC");
        course("ZZT 801", 800, "MTC");
        course("ZZU 301", 300, otherDept);
        // a fresh start for the classes this test allocates
        it.db(() -> jdbc.sql("UPDATE catalogue.offering SET lecturer_id = NULL, second_examiner_id = NULL WHERE session = :s AND course_code LIKE 'ZZT %'").param("s", SESSION).update());
    }

    @Test
    void aDepartmentTemplateCarriesTheRegisterAndItsUploadIsHeldToIt() {
        // the department summary and the template: only Mathematics and Computer Science's undergraduate classes and lecturers
        Map<String, Object> options = ok(it.get(agentTok, "/api/v1/allocation/template/options"));
        assertThat(l(options.get("departments"))).anyMatch(d -> "MTC".equals(d.get("code"))).noneMatch(d -> otherDept.equals(d.get("code")));
        Map<String, Object> summary = (Map<String, Object>) ok(it.get(agentTok, "/api/v1/allocation/template/context?dept=MTC&session=" + SESSION + "&semester=1&programmeType=UNDERGRADUATE")).get("summary");
        assertThat(((Number) summary.get("classes")).intValue()).isGreaterThanOrEqualTo(2);
        Map<String, Object> issued = ok(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/template",
                Map.of("dept", "MTC", "session", SESSION, "semester", 1, "programmeType", "UNDERGRADUATE")));
        Map<String, Object> ctx = (Map<String, Object>) issued.get("context");
        String ref = String.valueOf(ctx.get("reference"));
        assertThat(ref).matches("CAT-\\d{4}-\\d{6}");
        assertThat(ctx.get("deptCode")).isEqualTo("MTC");
        assertThat(l(issued.get("classes"))).extracting(c -> c.get("code")).contains("ZZT 301", "ZZT 302").doesNotContain("ZZT 801", "ZZU 301");
        assertThat(l(issued.get("lecturers"))).extracting(x -> x.get("staff_number")).contains("ZZ-TPL-A", "ZZ-TPL-B").doesNotContain("ZZ-TPL-C");
        assertThat(jdbc.sql("SELECT issued_office FROM catalogue.allocation_template WHERE reference = :r").param("r", ref).query(String.class).single()).isEqualTo("ictagent");
        // another faculty's department is outside the posting: refused, whatever the address says
        assertThat(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/template",
                Map.of("dept", otherDept, "session", SESSION, "semester", 1, "programmeType", "UNDERGRADUATE")).getStatusCode().value()).isEqualTo(403);

        // the completed file, previewed: nothing written
        List<Map<String, Object>> rows = List.of(
                row(13, "ZZ-TPL-A", "ZZT 301", "Lecturer"),
                row(14, "ZZ-TPL-C", "ZZT 302", "Lecturer"),
                row(15, "ZZ-TPL-A", "ZZU 301", "Lecturer"),
                row(16, "ZZ-TPL-A", "ZZT 999", "Lecturer"),
                row(17, "ZZ-TPL-A", "ZZT 301", "Lecturer"));
        Map<String, Object> wrongSession = new HashMap<>(row(18, "ZZ-TPL-B", "ZZT 302", "Lecturer"));
        wrongSession.put("session", "2133/2134");
        List<Map<String, Object>> all = new java.util.ArrayList<>(rows);
        all.add(wrongSession);
        Map<String, Object> v = ok(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/import/validate",
                Map.of("rows", all, "template", template(ref, "MTC", "MTC", "UNDERGRADUATE"))));
        Map<Integer, Map<String, Object>> byRow = new HashMap<>();
        for (Map<String, Object> f : l(v.get("rows"))) byRow.put(((Number) f.get("row")).intValue(), f);
        assertThat(byRow.get(13).get("status")).isIn("VALID", "WARNING");
        assertThat((List<String>) byRow.get(14).get("codes")).contains("LECTURER_NOT_IN_DEPARTMENT");
        assertThat((List<String>) byRow.get(15).get("codes")).contains("WRONG_DEPARTMENT");
        assertThat((List<String>) byRow.get(16).get("codes")).contains("COURSE_NOT_FOUND");
        assertThat(byRow.get(17).get("status")).isEqualTo("DUPLICATE");
        assertThat((List<String>) byRow.get(18).get("codes")).contains("WRONG_SESSION");
        assertThat(((Map<String, Object>) v.get("template")).get("reference")).isEqualTo(ref);
        assertThat(jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE course_code = 'ZZT 301' AND session = :s AND semester = 1").param("s", SESSION)
                .query(UUID.class).optional()).as("nothing written by the preview").isEmpty();

        // the template refused whole: uploaded for another department, its department written over in the file, unknown
        assertThat(code(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/import/validate",
                Map.of("rows", rows, "template", template(ref, otherDept, "MTC", "UNDERGRADUATE"))))).isEqualTo("ALLOC_TEMPLATE_DEPARTMENT");
        assertThat(code(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/import/validate",
                Map.of("rows", rows, "template", template(ref, "MTC", otherDept, "UNDERGRADUATE"))))).isEqualTo("ALLOC_TEMPLATE_ALTERED");
        assertThat(code(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/import/validate",
                Map.of("rows", rows, "template", template("CAT-1999-000001", "MTC", "MTC", "UNDERGRADUATE"))))).isEqualTo("ALLOC_TEMPLATE_UNKNOWN");

        // a newer template for the same department is named, not refused
        String newer = String.valueOf(((Map<String, Object>) ok(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/template",
                Map.of("dept", "MTC", "session", SESSION, "semester", 1, "programmeType", "UNDERGRADUATE"))).get("context")).get("reference"));
        Map<String, Object> again = ok(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/import/validate", Map.of("rows", rows, "template", template(ref, "MTC", "MTC", "UNDERGRADUATE"))));
        assertThat(((Map<String, Object>) again.get("template")).get("newer")).isEqualTo(newer);

        // imported on a ticket the agent works: the valid row only; the record carries the template and the ticket
        int n = ThreadLocalRandom.current().nextInt(10000, 99999);
        UUID ticket = it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.ticket (number, category_id, subject, description, requester_kind, requester_id, requester_name, queue_code, assigned_to)
                SELECT :n, c.id, 'A class with no lecturer', 'ZZT 301 shows no lecturer', 'STAFF', :a, 'ZZTPLA', 'COURSE_REGISTRATION_SUPPORT', :a
                  FROM helpdesk.category c WHERE c.code = 'REGISTRATION' RETURNING id
                """).param("n", "TICK-4780-" + n).param("a", agent).query(UUID.class).single());
        Map<String, Object> body = new HashMap<>();
        body.put("rows", rows);
        body.put("template", template(ref, "MTC", "MTC", "UNDERGRADUATE"));
        body.put("ticket", "TICK-4780-" + n);
        body.put("importKey", UUID.randomUUID());
        body.put("fileName", "ZZ template.xlsx");
        Map<String, Object> done = ok(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/import", body));
        assertThat(((Number) done.get("imported")).intValue()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE course_code = 'ZZT 301' AND session = :s AND semester = 1 AND stream = 'REGULAR'").param("s", SESSION)
                .query(UUID.class).single()).isEqualTo(lecA);
        Map<String, Object> rec = jdbc.sql("""
                SELECT t.reference, i.programme_type, i.ticket_id FROM catalogue.allocation_import i JOIN catalogue.allocation_template t ON t.id = i.template_id WHERE i.id = :i
                """).param("i", UUID.fromString(String.valueOf(done.get("id")))).query().singleRow();
        assertThat(rec.get("reference")).isEqualTo(ref);
        assertThat(rec.get("programme_type")).isEqualTo("UNDERGRADUATE");
        assertThat(rec.get("ticket_id")).isEqualTo(ticket);
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = :t AND action = 'SUPPORT_COURSE_ALLOCATION'").param("t", ticket).query(Integer.class).single())
                .isGreaterThanOrEqualTo(1);
        List<Map<String, Object>> recent = it.getList(agentTok, "/api/v1/allocation/templates?limit=20").getBody();
        assertThat(recent).anyMatch(t -> ref.equals(t.get("reference")) && ((Number) t.get("imported")).intValue() == 1);

        // a lead of another department the register already has comes back in the template as it is: on record, not refused
        it.db(() -> jdbc.sql("SELECT catalogue.open_class('ZZT 302', :s, 1, NULL)").param("s", SESSION).query().listOfRows());
        it.db(() -> jdbc.sql("UPDATE catalogue.offering SET lecturer_id = :c WHERE course_code = 'ZZT 302' AND session = :s AND semester = 1 AND stream = 'REGULAR'")
                .param("c", lecC).param("s", SESSION).update());
        Map<String, Object> back = ok(it.call(agentTok, HttpMethod.POST, "/api/v1/allocation/import/validate",
                Map.of("rows", List.of(row(20, "ZZ-TPL-C", "ZZT 302", "Lecturer")), "template", template(newer, "MTC", "MTC", "UNDERGRADUATE"))));
        assertThat(l(back.get("rows")).get(0).get("status")).as(String.valueOf(back.get("rows"))).isEqualTo("EXISTING");
    }

    @Test
    void aPostgraduateTemplateHoldsThePostgraduateClassesAndTheSchoolUploadsOnlyThose() {
        String school = TestTokens.token(it.person("ZZ-TPL-PGS", "ZZTPLPGSECRETARY"), List.of("pgsecretary"));
        // the School: postgraduate templates only, and never a file that is not one
        assertThat(code(it.call(school, HttpMethod.POST, "/api/v1/allocation/template",
                Map.of("dept", "MTC", "session", SESSION, "semester", 1, "programmeType", "UNDERGRADUATE")))).isEqualTo("ALLOC_TEMPLATE_PG_ONLY");
        assertThat(code(it.call(school, HttpMethod.POST, "/api/v1/allocation/import/validate",
                Map.of("rows", List.of(row(5, "ZZ-TPL-A", "ZZT 801", "Lecturer")))))).isEqualTo("ALLOC_TEMPLATE_REQUIRED");
        Map<String, Object> issued = ok(it.call(school, HttpMethod.POST, "/api/v1/allocation/template",
                Map.of("dept", "MTC", "session", SESSION, "semester", 1, "programmeType", "POSTGRADUATE")));
        String ref = String.valueOf(((Map<String, Object>) issued.get("context")).get("reference"));
        assertThat(l(issued.get("classes"))).extracting(c -> c.get("code")).contains("ZZT 801").doesNotContain("ZZT 301", "ZZT 302");
        // a postgraduate class is the School's to open; until it is, its allocation waits
        it.db(() -> jdbc.sql("DELETE FROM catalogue.offering o WHERE o.course_code = 'ZZT 801' AND o.session = :s AND o.stream = 'PG' AND NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.offering_id = o.id)")
                .param("s", SESSION).update());
        Map<String, Object> v = ok(it.call(school, HttpMethod.POST, "/api/v1/allocation/import/validate",
                Map.of("rows", List.of(row(5, "ZZ-TPL-A", "ZZT 801", "Lecturer"), row(6, "ZZ-TPL-A", "ZZT 301", "Lecturer")),
                        "template", template(ref, "MTC", "MTC", "POSTGRADUATE"))));
        assertThat((List<String>) l(v.get("rows")).get(0).get("codes")).contains("PG_CLASS_NOT_OPEN");
        assertThat((List<String>) l(v.get("rows")).get(1).get("codes")).contains("WRONG_PROGRAMME_TYPE");
        // opened as the School opens its classes: allocated from the template
        it.db(() -> jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester, stream) VALUES (gen_random_uuid(), 'ZZT 801', :s, 1, 'PG')").param("s", SESSION).update());
        Map<String, Object> body = new HashMap<>();
        body.put("rows", List.of(row(5, "ZZ-TPL-A", "ZZT 801", "Lecturer")));
        body.put("template", template(ref, "MTC", "MTC", "POSTGRADUATE"));
        body.put("importKey", UUID.randomUUID());
        assertThat(((Number) ok(it.call(school, HttpMethod.POST, "/api/v1/allocation/import", body)).get("imported")).intValue()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT lecturer_id FROM catalogue.offering WHERE course_code = 'ZZT 801' AND session = :s AND stream = 'PG'").param("s", SESSION)
                .query(UUID.class).single()).isEqualTo(lecA);
        assertThat(lecC).isNotNull();
    }
}
