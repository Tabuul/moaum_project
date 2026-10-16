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
                    ON CONFLICT (course_code, session, semester, stream) DO UPDATE SET semester = EXCLUDED.semester RETURNING id
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
                    ON CONFLICT (session, semester, kind, stream) DO UPDATE SET state = 'OPEN' RETURNING id
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

    /** V493: a postgraduate on a programme without research, registered in the session with every required course passed, is
     *  a finalist by coursework; the audit judges them by that coursework, and their award is not put in an undergraduate class */
    @Test
    @SuppressWarnings("unchecked")
    void aPostgraduateIsAFinalistByTheRequiredCourseworkAndIsNotClassified() {
        String pgSession = "2155/2156";
        it.session(pgSession, 2155);
        Map<String, Object> prog = jdbc.sql("""
                SELECT p.code, p.dept_code, admissions.pg_award_level(p.pg_award) AS lvl FROM ref.programme p
                 WHERE p.category = 'POST GRADUATE' AND NOT coalesce(p.pg_research, false) AND NOT coalesce(p.archived, false) ORDER BY p.code LIMIT 1
                """).query().singleRow();
        String code = String.valueOf(prog.get("code"));
        int lvl = ((Number) prog.get("lvl")).intValue();
        UUID student = it.student("ZZGPGFINALIST", code, null, "MOAUM/PGG/55/9001", lvl);
        String status = jdbc.sql("SELECT status FROM people.student WHERE id = :id").param("id", student).query(String.class).single();
        if ("GRADUATED".equals(status)) {
            return; // an earlier run on this database took the journey
        }
        String course = "ZGP " + (lvl + 1);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_mode = 'POSTGRADUATE', entry_level = :l, current_level = :l WHERE id = :s").param("l", lvl).param("s", student).update();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES (:c, 'A required postgraduate course for the test', 3, 1, :l, :d, 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", course).param("l", lvl).param("d", prog.get("dept_code")).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, :l, 'Core') ON CONFLICT DO NOTHING")
                    .param("c", course).param("p", code).param("l", lvl).update();
            // every course the programme requires of the student, this one and any other test bound to the same programme
            // (PgCoursePoolIT binds a Core course to the first postgraduate programme), registered and passed in the session
            List<String> required = jdbc.sql("SELECT course_code FROM admissions.pg_coursework_audit(:s) WHERE state <> 'PASSED'")
                    .param("s", student).query(String.class).list();
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at)
                    VALUES (gen_random_uuid(), :s, :sess, 1, :l, 'APPROVED', now())
                    ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED' RETURNING id
                    """).param("s", student).param("sess", pgSession).param("l", lvl).query(UUID.class).single();
            for (String c : required) {
                UUID offering = jdbc.sql("""
                        INSERT INTO catalogue.offering (id, course_code, session, semester, stream) VALUES (gen_random_uuid(), :c, :sess, 1, 'PG')
                        ON CONFLICT (course_code, session, semester, stream) DO UPDATE SET semester = EXCLUDED.semester RETURNING id
                        """).param("c", c).param("sess", pgSession).query(UUID.class).single();
                jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED') ON CONFLICT (registration_id, offering_id) DO NOTHING")
                        .param("r", reg).param("o", offering).update();
                UUID sheet = jdbc.sql("SELECT id FROM assessment.score_sheet WHERE offering_id = :o").param("o", offering).query(UUID.class).optional().orElse(null);
                if (sheet == null) {
                    sheet = UUID.randomUUID();
                    jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at, submitted_at) VALUES (:id, :o, 'PUBLISHED', 'SEN/2156/01', now(), now())")
                            .param("id", sheet).param("o", offering).update();
                }
                jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) SELECT :sh, :s, 30, 45, 'GRADED' WHERE NOT EXISTS (SELECT 1 FROM assessment.score WHERE sheet_id = :sh AND student_id = :s)")
                        .param("sh", sheet).param("s", student).update();
            }
            return required.size();
        });

        ResponseEntity<Map> audit = it.call(academic, HttpMethod.POST, "/api/v1/graduation/sessions/2155/2156/audit", null);
        assertThat(audit.getStatusCode().value()).as(String.valueOf(audit.getBody())).isEqualTo(200);
        ResponseEntity<Map> view = it.get(academic, "/api/v1/graduation/sessions/2155/2156");
        assertThat(view.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) view.getBody().get("finalists")).anySatisfy(f -> {
            assertThat(f.get("studentId")).isEqualTo(student.toString());
            assertThat(f.get("unmet")).isNull();
        });
        // the undergraduate classes count no postgraduate award
        String cls = jdbc.sql("SELECT class_of_degree FROM records.student_graduation(:s)").param("s", student).query(String.class).optional().orElse(null);
        assertThat(jdbc.sql("SELECT finalist FROM records.student_graduation(:s)").param("s", student).query(Boolean.class).single()).isTrue();
        assertThat(cls).isNull();   // a postgraduate award is not put in an undergraduate class
    }
}
