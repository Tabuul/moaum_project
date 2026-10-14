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

/**
 * Postgraduate coursework on the University's engines (V389), through the API: a course the School adds on its desk is a
 * course of the pool; the School opens its classes in its session (a Head of Department cannot); a PG student reads the
 * School's classes on the one registration screen, registers on them, and the PG window closes it; the old registration
 * refuses; the summary carries the next steps from the record; ICT sets a PG examination session; the broadsheet reads the
 * PG stream; a student without a PG application has none to read, nor anyone else's documents; the Bursary's review of what
 * PG students paid is the Bursary's and Audit's, and the readiness and public status name the School's session. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgCoursePoolIT {

    static final String SESSION = "2123/2124";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String school = ItSupport.token("pgschool");
    final String ict = ItSupport.token("ict");
    final String registrar = ItSupport.token("registrar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2123);
        it.db(() -> {
            jdbc.sql("INSERT INTO admissions.pg_academic_session (name, starts_on, ends_on, semesters, state) VALUES (:s, date '2123-10-01', date '2124-08-31', 2, 'PLANNED') ON CONFLICT (name) DO NOTHING")
                    .param("s", SESSION).update();
            jdbc.sql("""
                    INSERT INTO admissions.pg_semester (session, number, registration_opens, registration_closes, lectures_from, state)
                    VALUES (:s, 1, current_date - 1, current_date + 30, current_date, 'OPEN')
                    ON CONFLICT (session, number) DO UPDATE SET state = 'OPEN', registration_opens = current_date - 1, registration_closes = current_date + 30
                    """).param("s", SESSION).update();
            return null;
        });
    }

    @AfterEach
    void tearDown() {
        it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/PG_COURSE_REGISTRATION", Map.of("session", SESSION, "semester", 1, "action", "REOPEN", "reason", "integration test: reopened"));
        it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update());
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    @Test
    void aPgStudentRegistersOnTheSchoolsClassesOnTheUniversitysEngine() {
        String n = String.format("%06d", Math.abs(UUID.randomUUID().getMostSignificantBits() % 1_000_000L));
        String hex = UUID.randomUUID().toString().replaceAll("[^a-f]", "").toUpperCase() + "ABCDEF";
        String course = "Z" + hex.substring(0, 2) + " 811";
        Map<String, Object> prog = it.db(() -> jdbc.sql("""
                SELECT code, dept_code, admissions.pg_award_level(pg_award) AS level FROM ref.programme
                 WHERE category = 'POST GRADUATE' AND NOT coalesce(archived, false) ORDER BY code LIMIT 1
                """).query().singleRow());
        String programme = String.valueOf(prog.get("code"));
        int level = ((Number) prog.get("level")).intValue();
        UUID stu = UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
                VALUES (:id, :a, :m, 'ZZPGPOOL', 'Invented', :p, 'POSTGRADUATE', :s, :l, :l, 'ACTIVE', now())
                """).param("id", stu).param("a", "MOAUM/ADM/23/" + n).param("m", "MOAUM/PGX/23/" + n).param("p", programme).param("s", SESSION).param("l", level).update());
        String student = TestTokens.token(stu, List.of("student"));
        String hod = it.officer("hod", "department", String.valueOf(prog.get("dept_code")));

        // (1) a course the School adds on its desk is a course of the pool, bound to the programme at its level
        ok(it.call(school, HttpMethod.POST, "/api/v1/pg/coursework/courses", Map.of("programmeCode", programme, "code", course, "title", "Pool Check Seminar", "units", 3, "kind", "CORE", "semester", 1)));
        assertThat(jdbc.sql("SELECT count(*) FROM catalogue.course_offer WHERE course_code = :c AND programme_code = :p AND level = :l")
                .param("c", course).param("p", programme).param("l", level).query(Long.class).single()).isEqualTo(1L);

        // (2) the School opens its classes; a Head of Department cannot
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/pg/coursework/classes/open", Map.of("session", SESSION, "semester", 1)).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> opened = ok(it.call(school, HttpMethod.POST, "/api/v1/pg/coursework/classes/open", Map.of("session", SESSION, "semester", 1)));
        String cls = ((List<Map<String, Object>>) opened.get("classes")).stream().filter(c -> course.equals(c.get("course_code")))
                .map(c -> String.valueOf(c.get("id"))).findFirst().orElseThrow();
        assertThat(opened.get("gate")).isNull();

        // (3) the one registration screen: the School's classes, the PG window
        Map<String, Object> view = ok(it.get(student, "/api/v1/me/registration?session=" + SESSION + "&semester=1"));
        assertThat(((Map) view.get("window")).get("pg")).isEqualTo(true);
        assertThat(((List<Map<String, Object>>) view.get("menu")).stream().map(m -> String.valueOf(m.get("offering_id")))).contains(cls);
        ok(it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(cls))));
        ok(it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/PG_COURSE_REGISTRATION", Map.of("session", SESSION, "semester", 1, "action", "CLOSE", "reason", "the School pauses registration")));
        assertThat(code(it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(cls))))).isEqualTo("COURSE_REGISTRATION_CLOSED");
        ok(it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/PG_COURSE_REGISTRATION", Map.of("session", SESSION, "semester", 1, "action", "REOPEN", "reason", "resumed")));

        // (4) the old registration refuses; the summary carries the next steps from the record
        assertThat(code(it.call(student, HttpMethod.POST, "/api/v1/pg/coursework/register", Map.of("session", SESSION, "semester", 1, "courseIds", List.of())))).isEqualTo("PG_REGISTRATION_MOVED");
        Map<String, Object> summary = ok(it.get(student, "/api/v1/pg/coursework/summary"));
        assertThat(((List<Map<String, Object>>) summary.get("next")).stream().map(s -> s.get("key"))).contains("FEES", "REGISTRATION", "MATRICULATION");

        // (5) ICT sets the School's examination session; the broadsheet reads the PG stream
        List<Map<String, Object>> sessions = it.callList(ict, HttpMethod.GET, "/api/v1/results/exam-sessions?session=" + SESSION, null).getBody();
        if (sessions.stream().noneMatch(e -> "PG".equals(e.get("stream")))) {
            Map<String, Object> made = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions", Map.of("session", SESSION, "semester", 1, "kind", "MAIN",
                    "examsFrom", "2124-02-01", "examsTo", "2124-02-20", "sheetsDue", "2124-03-10", "stream", "PG")));
            assertThat(made.get("stream")).isEqualTo("PG");
        }
        assertThat(it.get(registrar, "/api/v1/results/broadsheet?prog=" + programme + "&level=" + level + "&session=" + SESSION + "&sem=1&stream=PG").getStatusCode().value()).isEqualTo(200);

        // (6) a student without a PG application has no offer to read
        assertThat(it.get(student, "/api/v1/pg/student/application").getStatusCode().value()).isEqualTo(404);
        // and no document of anyone else's application is reachable by its id
        UUID other = it.db(() -> jdbc.sql("SELECT d.id FROM admissions.pg_document d JOIN admissions.pg_application a ON a.id = d.application_id WHERE a.student_id IS DISTINCT FROM :me LIMIT 1")
                .param("me", stu).query(UUID.class).optional().orElse(UUID.randomUUID()));
        assertThat(it.get(student, "/api/v1/pg/student/documents/" + other + "/content").getStatusCode().value()).isEqualTo(404);

        // (7) V393: the review of what PG students paid is the Bursary's and Audit's; the unstated list is the fee page's
        // readers'; the readiness names the School's session, and the public status answers yes or no about it
        String[] ses = SESSION.split("/");
        assertThat(it.getList(ItSupport.token("bursar"), "/api/v1/finance/sessions/" + ses[0] + "/" + ses[1] + "/postgraduate/review").getStatusCode().value()).isEqualTo(200);
        assertThat(it.getList(registrar, "/api/v1/finance/sessions/" + ses[0] + "/" + ses[1] + "/postgraduate/review").getStatusCode().value()).isEqualTo(403);
        assertThat(it.getList(registrar, "/api/v1/finance/sessions/" + ses[0] + "/" + ses[1] + "/postgraduate/unstated").getStatusCode().value()).isEqualTo(200);
        Map<String, Object> ready = ok(it.get(ict, "/api/v1/platform/readiness?session=" + SESSION));
        assertThat(((List<Map<String, Object>>) ready.get("checks")).stream().map(c -> c.get("key"))).contains("pg_registration", "pg_intake_fees");
        // V452: the intake's PG fees — stated, or which session's are charged until they are
        Map<String, Object> pgFees = ((List<Map<String, Object>>) ready.get("checks")).stream().filter(c -> "pg_intake_fees".equals(c.get("key"))).findFirst().orElseThrow();
        assertThat(String.valueOf(pgFees.get("detail"))).containsAnyOf("Stated for ", "Not stated for ");
        Map<String, Object> status = ok(it.anon(HttpMethod.GET, "/api/v1/platform/status", null));
        assertThat((Map<String, Object>) status.get("postgraduate")).containsKeys("session", "current", "semesterOpen", "classes", "feesStated", "ready");
    }
}
