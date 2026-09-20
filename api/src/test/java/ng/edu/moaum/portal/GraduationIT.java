package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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

/** The degree audit is computed from the published record; Senate approves on its minute. Needs DATABASE_URL. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class GraduationIT {

    static final String SESSION = "2093/2094";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic = ItSupport.token("academic");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2093);
    }

    @Test
    @SuppressWarnings("unchecked")
    void theAuditComputesTheClassAndSenateApprovesOnItsMinute() {
        UUID student = it.student("ZZGFINALIST", "C00023", null, "MOAUM/MTC/93/9001", 400);
        String status = jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", student).query(String.class).single();
        if ("GRADUATED".equals(status)) {
            return; // an earlier run on this database took the journey
        }

        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :s, :sess, 400)
                    ON CONFLICT (student_id, session) DO NOTHING
                    """).param("s", student).param("sess", SESSION).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state)
                    VALUES ('ZZG 401', 'A final-year course for the test', 3, 1, 400, 'MTC', 'LIVE') ON CONFLICT (code) DO NOTHING
                    """).update();
            UUID offering = jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZG 401', :sess, 1)
                    ON CONFLICT (course_code, session, semester) DO UPDATE SET semester = EXCLUDED.semester RETURNING id
                    """).param("sess", SESSION).query(UUID.class).single();
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at)
                    VALUES (gen_random_uuid(), :s, :sess, 1, 400, 'APPROVED', now())
                    ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED' RETURNING id
                    """).param("s", student).param("sess", SESSION).query(UUID.class).single();
            jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 15, 'APPROVED')
                    ON CONFLICT (registration_id, offering_id) DO NOTHING
                    """).param("r", reg).param("o", offering).update();
            UUID examSession = jdbc.sql("""
                    INSERT INTO assessment.exam_session (id, session, semester, kind, exams_from, exams_to, sheets_due, state, opened_at)
                    VALUES (gen_random_uuid(), :sess, 1, 'MAIN', DATE '2094-12-08', DATE '2094-12-19', DATE '2095-01-16', 'OPEN', now())
                    ON CONFLICT (session, semester, kind) DO UPDATE SET state = 'OPEN' RETURNING id
                    """).param("sess", SESSION).query(UUID.class).single();
            UUID sheet = jdbc.sql("""
                    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, stage, senate_minute, published_at, submitted_at)
                    VALUES (gen_random_uuid(), :o, :es, 'PUBLISHED', 'SEN/2094/01', now(), now())
                    ON CONFLICT (offering_id, exam_session_id) DO UPDATE SET stage = 'PUBLISHED' RETURNING id
                    """).param("o", offering).param("es", examSession).query(UUID.class).single();
            jdbc.sql("""
                    INSERT INTO assessment.score (sheet_id, student_id, ca, exam) VALUES (:sh, :s, 30, 45)
                    ON CONFLICT (sheet_id, student_id, version) DO NOTHING
                    """).param("sh", sheet).param("s", student).update();
            return null;
        });

        ResponseEntity<Map> audit = it.call(academic, HttpMethod.POST, "/api/v1/graduation/sessions/2093/2094/audit", null);
        assertThat(audit.getStatusCode().value()).as(String.valueOf(audit.getBody())).isEqualTo(200);
        assertThat(((Number) audit.getBody().get("passed")).intValue()).isGreaterThanOrEqualTo(1);

        ResponseEntity<Map> view = it.get(academic, "/api/v1/graduation/sessions/2093/2094");
        assertThat(view.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> classes = (List<Map<String, Object>>) view.getBody().get("classification");
        Map<String, Object> first = classes.stream().filter(c -> "First Class Honours".equals(c.get("clazz"))).findFirst().orElseThrow();
        assertThat(((Number) first.get("students")).intValue()).isGreaterThanOrEqualTo(1);

        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/graduation/sessions/2093/2094/approve", Map.of("senateMinute", " ")).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> approved = it.call(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/graduation/sessions/2093/2094/approve",
                Map.of("senateMinute", "SEN/2094/02"));
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", student).query(String.class).single())
                .isEqualTo("GRADUATED");
    }
}
