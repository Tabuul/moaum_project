package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.HashMap;
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
import org.springframework.web.client.RestClient;

/**
 * V508–V511, the PRD v2.0 gaps closed, through the offices' doors: a student asks for an overload and their own Head of Department
 * grants it (another department's cannot), and the semester's maximum is the grant; the School of Postgraduate Studies replaces a
 * supervisor and removes a panel member, the history kept; Human Resources sets a grade and appoints from the form and an upload,
 * the rows that fail named; an API key reads a student's status on the integration door within its scope, a wrong key refused.
 * Each run files everything under its own session and numbers. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PrdGapsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    /** one number for the people this run invents, none of them already on the database */
    int n;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        n = it.freeDraw(1000, 9999, k -> List.of("ZZOVL" + k, "ZZPGS" + k, "MOAUM/ADM/24/86" + k, "ZZ/HR/" + k, "MOAUM/API/26/" + k, "ZZAPI" + k, "MOAUM/ADM/26/87" + k));
    }

    @Test
    void aStudentAsksForAnOverloadAndTheirOwnHeadOfDepartmentGrantsTheSemestersMaximum() {
        int y = 5400 + new Random().nextInt(400);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        UUID student = it.student("ZZOVL" + n, "C00061", "MOAUM/ADM/" + yy + "/85" + n, "MOAUM/OVL/" + yy + "/" + n, 100);
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
        String other = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL AND code <> :d ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
        String me = TestTokens.token(student, List.of("student"));
        int max = jdbc.sql("SELECT max_units FROM registration.unit_rule_base(:s, 100, :ses, 1)").param("s", student).param("ses", session).query(Integer.class).single();

        Map<String, Object> state = it.get(me, "/api/v1/me/overload?session=" + session + "&semester=1").getBody();
        assertThat(state).containsEntry("may_ask", true).containsEntry("regular_max", max);
        ResponseEntity<Map> tooMany = it.call(me, HttpMethod.POST, "/api/v1/me/overload", Map.of("session", session, "semester", 1, "units", max + 20, "reason", "Integration test: far too many"));
        assertThat(tooMany.getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> asked = it.call(me, HttpMethod.POST, "/api/v1/me/overload", Map.of("session", session, "semester", 1, "units", max + 4, "reason", "Integration test: final year with carry-overs"));
        assertThat(asked.getStatusCode().value()).as(String.valueOf(asked.getBody())).isEqualTo(200);
        String id = String.valueOf(((Map<String, Object>) asked.getBody().get("request")).get("id"));

        // the other department's Head neither sees it nor decides it; the student's own does, and the grant is the maximum
        String otherHod = it.officer("hod", "department", other);
        List<Map<String, Object>> theirs = (List<Map<String, Object>>) it.get(otherHod, "/api/v1/registration/overloads?session=" + session).getBody().get("rows");
        assertThat(theirs).noneSatisfy(r -> assertThat(r.get("id")).isEqualTo(id));
        assertThat(it.call(otherHod, HttpMethod.POST, "/api/v1/registration/overloads/" + id + "/decide", Map.of("decision", "GRANTED", "units", max + 2, "reason", "Integration test: another department"))
                .getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("academic"), HttpMethod.POST, "/api/v1/registration/overloads/" + id + "/decide", Map.of("decision", "GRANTED", "units", max + 2, "reason", "Integration test: the Academic Office"))
                .getStatusCode().value()).isEqualTo(403);
        String hod = it.officer("hod", "department", dept);
        List<Map<String, Object>> mine = (List<Map<String, Object>>) it.get(hod, "/api/v1/registration/overloads?session=" + session).getBody().get("rows");
        assertThat(mine).anySatisfy(r -> assertThat(r.get("id")).isEqualTo(id));
        ResponseEntity<Map> granted = it.call(hod, HttpMethod.POST, "/api/v1/registration/overloads/" + id + "/decide", Map.of("decision", "GRANTED", "units", max + 2, "reason", "Integration test: two more for the project"));
        assertThat(granted.getStatusCode().value()).as(String.valueOf(granted.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT max_units FROM registration.unit_rule(:s, 100, :ses, 1)").param("s", student).param("ses", session).query(Integer.class).single()).isEqualTo(max + 2);
        assertThat(((Map<String, Object>) it.get(me, "/api/v1/me/overload?session=" + session + "&semester=1").getBody().get("request"))).containsEntry("status", "GRANTED").containsEntry("granted_max", max + 2);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND template_key = 'OVERLOAD_GRANTED'").param("s", student).query(Long.class).single()).isPositive();
    }

    @Test
    void theSchoolReplacesASupervisorAndRemovesAPanelMemberWithTheHistoryKept() {
        UUID student = it.student("ZZPGS" + n, "C90001", "MOAUM/ADM/24/86" + n, null, 700);
        UUID research = UUID.randomUUID();
        UUID[] rows = it.db(() -> {
            jdbc.sql("INSERT INTO admissions.pg_research (id, student_id, degree_kind, stage) VALUES (:r, :s, 'DISSERTATION', 'SUPERVISED')").param("r", research).param("s", student).update();
            UUID sup = jdbc.sql("INSERT INTO admissions.pg_research_supervisor (research_id, name, role, assigned_at) VALUES (:r, 'Dr Old First', 'FIRST', now() - interval '90 days') RETURNING id")
                    .param("r", research).query(UUID.class).single();
            UUID mem = jdbc.sql("INSERT INTO admissions.pg_research_panel (research_id, name, role, is_external) VALUES (:r, 'Prof Declined External', 'EXTERNAL', true) RETURNING id")
                    .param("r", research).query(UUID.class).single();
            return new UUID[] { sup, mem };
        });
        String school = ItSupport.token("pgschool");
        String base = "/api/v1/pg/research/" + research;
        assertThat(it.call(ItSupport.token("hod"), HttpMethod.POST, base + "/supervisors/" + rows[0] + "/end", Map.of("on", LocalDate.now().toString(), "reason", "Integration test: a Head tries"))
                .getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(school, HttpMethod.POST, base + "/supervisors/" + rows[0] + "/end", Map.of("on", LocalDate.now().toString(), "reason", "Integration test: ending the only first"))
                .getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> replaced = it.call(school, HttpMethod.POST, base + "/supervisors/" + rows[0] + "/replace",
                Map.of("name", "Prof New First", "on", LocalDate.now().minusDays(2).toString(), "reason", "Integration test: the supervisor retired"));
        assertThat(replaced.getStatusCode().value()).as(String.valueOf(replaced.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) replaced.getBody().get("supervisors")).extracting(s -> s.get("name")).containsExactly("Prof New First");
        assertThat((List<Map<String, Object>>) replaced.getBody().get("supervisorHistory")).singleElement()
                .satisfies(h -> { assertThat(h.get("name")).isEqualTo("Dr Old First"); assertThat(h.get("replaced_by")).isEqualTo("Prof New First"); });
        Map<String, Object> removed = new HashMap<>(Map.of("on", LocalDate.now().toString(), "reason", "Integration test: the examiner declined", "replacement", "Prof Accepted External", "external", true));
        ResponseEntity<Map> panel = it.call(school, HttpMethod.POST, base + "/panel/" + rows[1] + "/remove", removed);
        assertThat(panel.getStatusCode().value()).as(String.valueOf(panel.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) panel.getBody().get("panel")).extracting(m -> m.get("name")).containsExactly("Prof Accepted External");
        assertThat((List<Map<String, Object>>) panel.getBody().get("panelHistory")).extracting(m -> m.get("name")).containsExactly("Prof Declined External");
    }

    @Test
    void humanResourcesSetsAGradeAndAppointsFromTheFormAndAnUpload() {
        String hr = ItSupport.token("hrm");
        String dept = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL ORDER BY code LIMIT 1").query(String.class).single();
        String grade = "ZZTISS " + (n % 90 + 10);
        assertThat(it.call(ItSupport.token("lecturer"), HttpMethod.PUT, "/api/v1/hr/grades", Map.of("grade", grade, "step", 1, "category", "NON_ACADEMIC", "basic", 100000, "reason", "Integration test: a lecturer tries"))
                .getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> g = it.call(hr, HttpMethod.PUT, "/api/v1/hr/grades", Map.of("grade", grade, "step", 1, "category", "NON_ACADEMIC", "basic", 100000, "housing", 20000, "reason", "Integration test: a grade for the test"));
        assertThat(g.getStatusCode().value()).as(String.valueOf(g.getBody())).isEqualTo(200);

        Map<String, Object> one = new HashMap<>(Map.of("staff_no", "ZZ/HR/" + n, "surname", "Zzappointed", "given_names", "Form Officer", "category", "NON_ACADEMIC",
                "grade", grade, "step", "1", "appointment_date", LocalDate.now().toString(), "unit", "", "department", dept));
        one.put("account_number", "0123456789");
        List<Map<String, Object>> checked = (List<Map<String, Object>>) (List) it.callList(hr, HttpMethod.POST, "/api/v1/hr/appointments/check", Map.of("rows", List.of(one))).getBody();
        assertThat(checked.get(0)).containsEntry("ok", true).containsEntry("action", "CREATE");
        ResponseEntity<Map> made = it.call(hr, HttpMethod.POST, "/api/v1/hr/appointments", one);
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT account_last4 || '/' || status FROM hrm.employment WHERE staff_no = :s").param("s", "ZZ/HR/" + n).query(String.class).single()).isEqualTo("6789/ACTIVE");
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/hr/appointments", one).getStatusCode().value()).isEqualTo(403);

        Map<String, Object> good = new HashMap<>(Map.of("row", "2", "staff_no", "ZZ/HR/U" + n, "surname", "Zzuploaded", "given_names", "Upload Officer", "category", "NON_ACADEMIC",
                "grade", grade, "step", "1", "appointment_date", "01/10/2026", "department", dept));
        Map<String, Object> again = new HashMap<>(Map.of("row", "3", "staff_no", "ZZ/HR/" + n, "category", "NON_ACADEMIC", "grade", grade, "step", "1", "appointment_date", "01/10/2026", "department", dept));
        Map<String, Object> up = it.call(hr, HttpMethod.POST, "/api/v1/hr/appointments/upload", Map.of("rows", List.of(good, again))).getBody();
        assertThat(up).as(String.valueOf(up)).containsEntry("appointed", 1).containsEntry("skipped", 1);
        Map<String, Object> overview = it.get(hr, "/api/v1/hr/appointments").getBody();
        assertThat((List<Map<String, Object>>) overview.get("grades")).anySatisfy(x -> assertThat(x.get("grade")).isEqualTo(grade));
    }

    @Test
    void anApiKeyReadsAStudentsStatusWithinItsScopeOnTheIntegrationDoor() {
        String matric = "MOAUM/API/26/" + n;
        it.student("ZZAPI" + n, "C00061", "MOAUM/ADM/26/87" + n, matric, 200);
        String ict = ItSupport.token("ict");
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/apimgmt/consumers", Map.of("name", "ZZ sponsor " + n, "owner", "Integration test", "scopes", "payments:read"))
                .getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> reg = it.call(ict, HttpMethod.POST, "/api/v1/apimgmt/consumers", Map.of("name", "ZZ sponsor " + n, "owner", "Integration test", "scopes", "students:status", "quotaDay", 100));
        assertThat(reg.getStatusCode().value()).as(String.valueOf(reg.getBody())).isEqualTo(200);
        String key = String.valueOf(it.call(ict, HttpMethod.POST, "/api/v1/apimgmt/consumers/" + reg.getBody().get("id") + "/keys", Map.of("days", 30)).getBody().get("key"));

        RestClient door = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
        ResponseEntity<Map> none = door.get().uri(u -> u.path("/api/integration/v1/students/status").queryParam("matric", matric).build()).retrieve().toEntity(Map.class);
        assertThat(none.getStatusCode().value()).isEqualTo(401);
        ResponseEntity<Map> ok = door.get().uri(u -> u.path("/api/integration/v1/students/status").queryParam("matric", matric).build()).header("X-API-Key", key).retrieve().toEntity(Map.class);
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
        assertThat(ok.getBody()).containsEntry("matric_no", matric).containsEntry("status", "IN_STUDY").containsEntry("name", "ZZAPI" + n + ", I.").doesNotContainKeys("email", "phone");
        ResponseEntity<Map> missing = door.get().uri(u -> u.path("/api/integration/v1/students/status").queryParam("matric", "MOAUM/API/26/X" + n).build()).header("X-API-Key", key).retrieve().toEntity(Map.class);
        assertThat(missing.getStatusCode().value()).isEqualTo(404);
        List<Map<String, Object>> calls = (List<Map<String, Object>>) (List) it.getList(ict, "/api/v1/apimgmt/calls").getBody();
        assertThat(calls).anySatisfy(c -> { assertThat(c.get("subject")).isEqualTo(matric); assertThat(c.get("outcome")).isEqualTo("OK"); });
    }
}
