package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * V513–V517 through the offices' doors: HR reads the staff without an employment record (a lecturer listed with the grant's
 * department, gone once appointed); the Academic Office sees a waiting overload no Head can decide; the Registry registers a student
 * late with the window closed (a lecturer cannot), and the registration is submitted; a sponsor's key reads a student's enrolment and
 * fee clearance on the integration door. Each run files everything under its own session and numbers. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PrdFollowupsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    /** one number for the people this run invents, none of them already on the database */
    int n;
    String instrument;
    String feeSession;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        n = it.freeDraw(1000, 9999, k -> List.of("ZZ/NOEMP/" + k, "ZZNOEMP" + k, "ZZNOHEAD" + k, "ZZLATE" + k, "MOAUM/ENR/26/" + k, "ZZENROL" + k, "MOAUM/ADM/26/90" + k));
        instrument = "IT/LATE516/" + n;
    }

    @AfterEach
    void clean() {
        it.db(() -> {
            if (feeSession != null) jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", feeSession).update();
            jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            return jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
        });
    }

    @Test
    void humanResourcesSeesALecturerWithoutAnEmploymentRecordUntilAppointed() {
        String dept = jdbc.sql("SELECT code FROM ref.department WHERE ended_on IS NULL ORDER BY code LIMIT 1").query(String.class).single();
        String staffNo = "ZZ/NOEMP/" + n;
        UUID person = it.person(staffNo, "ZZNOEMP" + n);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'lecturer', 'department', :d, 'integration test', :p, current_date)
                """).param("p", person).param("d", dept).update());
        String hr = ItSupport.token("hrm");
        Map<String, Object> list = it.get(hr, u -> u.path("/api/v1/hr/appointments/without-employment").queryParam("q", staffNo).build()).getBody();
        assertThat((List<Map<String, Object>>) list.get("rows")).singleElement().satisfies(r -> {
            assertThat(r.get("category")).isEqualTo("ACADEMIC");
            assertThat(r.get("department")).isEqualTo(dept);
            assertThat(r.get("source")).isEqualTo("LECTURER");
        });
        String grade = "ZZUASS " + (n % 90 + 10);
        assertThat(it.call(hr, HttpMethod.PUT, "/api/v1/hr/grades", Map.of("grade", grade, "step", 1, "category", "ACADEMIC", "basic", 150000, "reason", "Integration test: an academic grade"))
                .getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> made = it.call(hr, HttpMethod.POST, "/api/v1/hr/appointments",
                Map.of("staff_no", staffNo, "category", "ACADEMIC", "grade", grade, "step", "1", "appointment_date", "2026-10-01", "department", dept));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        assertThat((List<?>) it.get(hr, u -> u.path("/api/v1/hr/appointments/without-employment").queryParam("q", staffNo).build()).getBody().get("rows")).isEmpty();
    }

    @Test
    void theAcademicOfficeSeesAWaitingOverloadNoHeadCanDecide() {
        String prog = jdbc.sql("""
                SELECT p.code FROM ref.programme p WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false) AND p.dept_code IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM registration.department_heads(p.dept_code)) ORDER BY p.code LIMIT 1
                """).query(String.class).single();
        int y = it.freeYear(5800, 5900);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        UUID student = it.student("ZZNOHEAD" + n, prog, "MOAUM/ADM/" + yy + "/88" + n, "MOAUM/NOH/" + yy + "/" + n, 100);
        ResponseEntity<Map> asked = it.call(TestTokens.token(student, List.of("student")), HttpMethod.POST, "/api/v1/me/overload",
                Map.of("session", session, "semester", 1, "units", 26, "reason", "Integration test: no Head to decide it"));
        assertThat(asked.getStatusCode().value()).as(String.valueOf(asked.getBody())).isEqualTo(200);
        Map<String, Object> list = it.get(ItSupport.token("academic"), "/api/v1/registration/overloads?session=" + session).getBody();
        assertThat(((Number) list.get("noHead")).intValue()).isEqualTo(1);
        assertThat((List<Map<String, Object>>) list.get("rows")).singleElement().satisfies(r -> assertThat(r.get("has_head")).isEqualTo(false));
    }

    @Test
    void theRegistryRegistersAStudentLateWithTheWindowClosed() {
        int y = it.freeYear(5900, 5999);
        String session = y + "/" + (y + 1);
        feeSession = session;
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        String prog = jdbc.sql("""
                SELECT p.code FROM ref.programme p WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false) AND p.dept_code IS NOT NULL
                   AND registration.siwes_units(p.code, 100, 1) IS NULL ORDER BY p.code LIMIT 1
                """).query(String.class).single();
        String number = "MOAUM/LTR/" + yy + "/" + n;
        UUID student = it.student("ZZLATE" + n, prog, "MOAUM/ADM/" + yy + "/89" + n, number, 100);
        String[] codes = { "ZLA " + (n % 900 + 100), "ZLB " + (n % 900 + 100), "ZLC " + (n % 900 + 100) };
        it.db(() -> {
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", prog).query(String.class).single();
            for (String c : codes) {
                jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, 'Late Registration Course', 6, 1, 100, :d, 'Core', 'LIVE') ON CONFLICT (code) DO NOTHING")
                        .param("c", c).param("d", dept).update();
                jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, 100, 'Core') ON CONFLICT DO NOTHING").param("c", c).param("p", prog).update();
                jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :c, :s, 1) ON CONFLICT DO NOTHING").param("c", c).param("s", session).update();
            }
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 30000, 100, :p)").param("s", session).param("p", prog).update();
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           :i, 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).param("i", instrument).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = :i ON CONFLICT DO NOTHING").param("i", instrument).update();
            jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED' ELSE 'INSTALMENT_1' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = :i ON CONFLICT DO NOTHING
                    """).param("i", instrument).update();
            String ref = jdbc.sql("SELECT finance.new_purpose_reference(:st, :s, 30000, 'School fees ' || :s)").param("st", student).param("s", session).query(String.class).single();
            jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the late registration test')").param("r", ref).query(String.class).single();
            jdbc.sql("SELECT policy.window_act('COURSE_REGISTRATION', :s, 1, 'OPEN', NULL, NULL, NULL, false, 'integration test: opened', gen_random_uuid(), 'ict')").param("s", session).query().listOfRows();
            jdbc.sql("SELECT policy.window_act('COURSE_REGISTRATION', :s, 1, 'CLOSE', NULL, NULL, NULL, NULL, 'integration test: closed', gen_random_uuid(), 'ict')").param("s", session).query().listOfRows();
            return 0;
        });
        String registry = ItSupport.token("registrar");
        Map<String, Object> view = it.get(registry, u -> u.path("/api/v1/registration/late/student").queryParam("number", number).queryParam("session", session)
                .queryParam("semester", 1).build()).getBody();
        assertThat(view.get("window")).as(String.valueOf(view)).isNotNull();
        List<Map<String, Object>> menu = (List<Map<String, Object>>) view.get("menu");
        assertThat(menu).hasSize(3).allSatisfy(m -> { assertThat(m.get("blocked_by")).isNull(); assertThat(m.get("window_set_aside")).isEqualTo(true); });
        List<String> offerings = menu.stream().map(m -> String.valueOf(m.get("offering_id"))).toList();
        Map<String, Object> body = Map.of("studentId", student, "session", session, "semester", 1, "offerings", offerings, "reason", "Integration test: admitted late by Senate");
        assertThat(it.call(ItSupport.token("lecturer"), HttpMethod.POST, "/api/v1/registration/late", body).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> done = it.call(registry, HttpMethod.POST, "/api/v1/registration/late", body);
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("units", 18);
        assertThat(String.valueOf(done.getBody().get("status"))).isIn("SUBMITTED", "APPROVED");
        List<Map<String, Object>> rows = (List<Map<String, Object>>) it.get(ItSupport.token("academic"), "/api/v1/registration/late?session=" + session).getBody().get("rows");
        assertThat(rows).anySatisfy(r -> assertThat(r.get("student_id")).isEqualTo(student.toString()));
    }

    @Test
    void aSponsorsKeyReadsAStudentsEnrolmentOnTheIntegrationDoor() {
        String matric = "MOAUM/ENR/26/" + n;
        UUID student = it.student("ZZENROL" + n, "C00061", "MOAUM/ADM/26/90" + n, matric, 200);
        String session = jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
        it.db(() -> jdbc.sql("""
                INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at)
                VALUES (gen_random_uuid(), :st, :s, 1, 200, 'SUBMITTED', now()) ON CONFLICT DO NOTHING
                """).param("st", student).param("s", session).update());
        String ict = ItSupport.token("ict");
        ResponseEntity<Map> reg = it.call(ict, HttpMethod.POST, "/api/v1/apimgmt/consumers", Map.of("name", "ZZ NELFUND " + n, "owner", "Integration test", "scopes", "students:enrolment"));
        assertThat(reg.getStatusCode().value()).as(String.valueOf(reg.getBody())).isEqualTo(200);
        String key = String.valueOf(it.call(ict, HttpMethod.POST, "/api/v1/apimgmt/consumers/" + reg.getBody().get("id") + "/keys", Map.of("days", 30)).getBody().get("key"));
        RestClient door = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
        ResponseEntity<Map> ok = door.get().uri(u -> u.path("/api/integration/v1/students/enrolment").queryParam("matric", matric).build()).header("X-API-Key", key).retrieve().toEntity(Map.class);
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
        assertThat(ok.getBody()).containsEntry("matric_no", matric).containsEntry("session", session).containsEntry("registered", true).containsEntry("in_study", true)
                .containsKeys("fees_cleared_for_registration", "fees_cleared_for_examination").doesNotContainKeys("amount", "balance", "due");
        ResponseEntity<Map> status = door.get().uri(u -> u.path("/api/integration/v1/students/status").queryParam("matric", matric).build()).header("X-API-Key", key).retrieve().toEntity(Map.class);
        assertThat(status.getStatusCode().value()).isEqualTo(403);
    }
}
