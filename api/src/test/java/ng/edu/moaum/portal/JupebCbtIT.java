package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.OffsetDateTime;
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
 * V365, through the API: JUPEB examined on the University's one CBT engine. The JUPEB Office allows a subject CBT, builds its bank, creates and
 * publishes an examination of it with the part of the continuous assessment it counts towards; the GST office and a University student are
 * refused; a JUPEB student — admitted, registered for the subject, the semester's share of the fee paid — sits it through the JUPEB door,
 * on a paper without its keys; the office sees the candidate; and the approved result goes into the JUPEB continuous assessment.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class JupebCbtIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String office;
    String gst = ItSupport.token("gst");
    String session;
    String tag;
    UUID subject;
    UUID app;
    String candidate;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        office = TestTokens.token(it.person("ZZJCBT-OFFICER", "ZZJCBTOFFICER"), List.of("jupeb"));
        session = jdbc.sql("SELECT jupeb.current_session()").query(String.class).single();
        it.session(session, Integer.parseInt(session.substring(0, 4)));
        tag = UUID.randomUUID().toString().replace("-", "").substring(0, 5).toUpperCase();
        String prog = jdbc.sql("SELECT code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND NOT archived ORDER BY code LIMIT 1").query(String.class).single();
        it.db(() -> {
            subject = jdbc.sql("INSERT INTO jupeb.subject (code, title) VALUES (:c, :t) RETURNING id").param("c", "ZJ" + tag).param("t", "JUPEB CBT check " + tag).query(UUID.class).single();
            UUID s2 = jdbc.sql("INSERT INTO jupeb.subject (code, title) VALUES (:c, 'Second') RETURNING id").param("c", "ZK" + tag).query(UUID.class).single();
            UUID s3 = jdbc.sql("INSERT INTO jupeb.subject (code, title) VALUES (:c, 'Third') RETURNING id").param("c", "ZL" + tag).query(UUID.class).single();
            UUID comb = jdbc.sql("INSERT INTO jupeb.combination (code, name, subject1, subject2, subject3) VALUES (:c, 'Check', :a, :b, :d) RETURNING id")
                    .param("c", "ZJC" + tag).param("a", subject).param("b", s2).param("d", s3).query(UUID.class).single();
            UUID acc = jdbc.sql("INSERT INTO jupeb.account (email, password_hash) VALUES (:e, '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id")
                    .param("e", "zz.jcbt." + tag.toLowerCase() + "@example.com").query(UUID.class).single();
            app = jdbc.sql("""
                    INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, programme_code, combination_id, state_of_origin, state, subjects_registered_at, exam_no)
                    VALUES (:acc, :s, :no, 'ZZJCBT', 'Candidate', :e, :p, :c, 'Benue', 'STUDENT', now(), :x) RETURNING id
                    """).param("acc", acc).param("s", session).param("no", "JUPEB/APP/" + session.substring(0, 4) + "/9" + String.format("%05d", Math.abs(tag.hashCode() % 100000)))
                    .param("e", "zz.jcbt." + tag.toLowerCase() + "@example.com").param("p", prog).param("c", comb).param("x", "ZJ-" + tag).query(UUID.class).single();
            jdbc.sql("INSERT INTO jupeb.subject_registration (application_id, subject_id, session) VALUES (:a, :s, :ses)").param("a", app).param("s", subject).param("ses", session).update();
            jdbc.sql("""
                    INSERT INTO jupeb.fee_reference (application_id, kind, reference, amount, session, expires_at, confirmed_at)
                    VALUES (:a, 'SCHOOL_FIRST', :r, 1000, :s, now() + interval '1 day', now())
                    """).param("a", app).param("r", "ZJCBT-" + tag).param("s", session).update();
            return null;
        });
        candidate = TestTokens.token(app, List.of("applicant"));
    }

    private UUID question(String stem, int answer) {
        ResponseEntity<Map> r = it.call(office, HttpMethod.POST, "/api/v1/cbt/questions", Map.of("course", "JUPEB:ZJ" + tag, "kind", "MCQ", "stem", stem,
                "options", List.of("a", "b", "c", "d"), "answer", answer, "marks", 1, "difficulty", "MEDIUM", "explanation", "the key is " + answer));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return UUID.fromString(String.valueOf(r.getBody().get("id")));
    }

    @Test
    void aJupebSubjectIsExaminedOnTheOneEngineAndItsResultGoesIntoTheJupebAssessment() {
        OffsetDateTime now = OffsetDateTime.now();
        Map<String, Object> body = new java.util.LinkedHashMap<>(Map.of("office", "JUPEB", "jupebSubjectId", subject, "session", session, "semester", 1, "title", "JUPEB CBT " + tag,
                "durationMinutes", 30, "selection", "FIXED", "passMark", 40, "startsAt", now.minusMinutes(1).toString(), "endsAt", now.plusHours(2).toString()));

        // not yet a CBT subject; the JUPEB Office allows it, the GST office may not
        ResponseEntity<Map> refused = it.call(office, HttpMethod.POST, "/api/v1/cbt/exams", body);
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("CBT_COURSE_NOT_ENABLED");
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/catalogue/jupeb/" + subject, Map.of("enabled", true)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(office, HttpMethod.PUT, "/api/v1/cbt/catalogue/jupeb/" + subject, Map.of("enabled", true)).getStatusCode().value()).isEqualTo(200);

        // the subject's bank, the JUPEB Office's alone
        UUID q1 = question("JUPEB first " + tag, 0);
        UUID q2 = question("JUPEB second " + tag, 2);
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/questions", Map.of("course", "JUPEB:ZJ" + tag, "kind", "MCQ", "stem", "not mine", "options", List.of("a", "b"), "answer", 0))
                .getStatusCode().value()).isEqualTo(403);
        List<Map<String, Object>> banks = (List<Map<String, Object>>) (List) it.getList(office, "/api/v1/cbt/courses").getBody();
        assertThat(banks).anySatisfy(b -> assertThat(b.get("code")).isEqualTo("JUPEB:ZJ" + tag));

        // the examination, its paper, and the part of the continuous assessment it counts towards
        ResponseEntity<Map> made = it.call(office, HttpMethod.POST, "/api/v1/cbt/exams", body);
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        String exam = String.valueOf(made.getBody().get("id"));
        assertThat(made.getBody().get("office")).isEqualTo("JUPEB");
        assertThat(made.getBody().get("course_code")).isEqualTo("ZJ" + tag);
        assertThat(it.call(office, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/paper", Map.of("questions", List.of(Map.of("id", q1), Map.of("id", q2)))).getStatusCode().value()).isEqualTo(200);
        UUID comp = it.db(() -> jdbc.sql("INSERT INTO jupeb.ca_component (session, code, title, max_score) VALUES (:s, :c, 'CBT test', 20) RETURNING id")
                .param("s", session).param("c", "ZJ" + tag).query(UUID.class).single());
        ResponseEntity<Map> examSheet = it.call(office, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam, Map.of("title", "JUPEB CBT " + tag, "settings", Map.of("sheetComponent", "EXAM")));
        assertThat(examSheet.getStatusCode().value()).as("a JUPEB examination is never the University's examination component").isEqualTo(422);
        ResponseEntity<Map> setCa = it.call(office, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam, Map.of("title", "JUPEB CBT " + tag,
                "startsAt", now.minusMinutes(1).toString(), "endsAt", now.plusHours(2).toString(), "settings", Map.of("sheetComponent", "CA", "jupebCaComponentId", comp.toString())));
        assertThat(setCa.getStatusCode().value()).as(String.valueOf(setCa.getBody())).isEqualTo(200);
        assertThat(it.call(office, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of()).getStatusCode().value()).isEqualTo(200);

        // the GST office reads nothing of it; a University student cannot start it
        assertThat(it.get(gst, "/api/v1/cbt/exams/" + exam).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("student"), HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of()).getStatusCode().value()).isEqualTo(404);

        // the JUPEB student: the examination listed, eligible, started through the JUPEB door; the paper without keys
        ResponseEntity<Map> mine = it.get(candidate, "/api/v1/jupeb/me/cbt");
        assertThat(mine.getStatusCode().value()).as(String.valueOf(mine.getBody())).isEqualTo(200);
        assertThat(l(mine.getBody().get("rows"))).anySatisfy(r -> { assertThat(r.get("exam_id")).isEqualTo(exam); assertThat(r.get("eligibility")).isNull(); assertThat(r.get("course_code")).isEqualTo("ZJ" + tag); });
        ResponseEntity<Map> started = it.call(candidate, HttpMethod.POST, "/api/v1/jupeb/me/cbt/exams/" + exam + "/start", Map.of());
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        String attempt = String.valueOf(started.getBody().get("attemptId"));
        Map<String, String> h = Map.of("X-Attempt-Token", String.valueOf(started.getBody().get("token")));
        ResponseEntity<Map> room = it.callWith(candidate, HttpMethod.GET, "/api/v1/jupeb/me/cbt/attempts/" + attempt, null, h);
        assertThat(room.getStatusCode().value()).as(String.valueOf(room.getBody())).isEqualTo(200);
        assertThat(String.valueOf(room.getBody())).doesNotContain("the key is");
        assertThat(m(room.getBody().get("candidate")).get("number")).isEqualTo("ZJ-" + tag);
        // the University student's door does not open a JUPEB attempt
        assertThat(it.callWith(ItSupport.token("student"), HttpMethod.GET, "/api/v1/me/cbt/attempts/" + attempt, null, h).getStatusCode().value()).isEqualTo(404);
        assertThat(it.callWith(candidate, HttpMethod.PUT, "/api/v1/jupeb/me/cbt/attempts/" + attempt + "/answers",
                Map.of("answers", List.of(Map.of("q", q1, "a", List.of(0), "seq", 1), Map.of("q", q2, "a", List.of(2), "seq", 1))), h).getStatusCode().value()).isEqualTo(200);
        assertThat(it.callWith(candidate, HttpMethod.POST, "/api/v1/jupeb/me/cbt/attempts/" + attempt + "/submit", Map.of(), h).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(candidate, "/api/v1/jupeb/me/cbt/attempts/" + attempt + "/result").getBody().get("code")).isEqualTo("CBT_RESULT_NOT_PUBLISHED");

        // the office sees the candidate; closes, completes, approves; the result into the JUPEB continuous assessment
        ResponseEntity<Map> cands = it.get(office, "/api/v1/cbt/exams/" + exam + "/candidates");
        assertThat(l(cands.getBody().get("rows"))).anySatisfy(r -> { assertThat(r.get("student_id")).isEqualTo(app.toString()); assertThat(r.get("attempt_status")).isEqualTo("SUBMITTED"); });
        assertThat(it.get(office, "/api/v1/cbt/exams/" + exam + "/candidates/" + app).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(office, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/close", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(office, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/complete", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(office, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/approve", Map.of()).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> written = it.call(office, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/to-sheet", Map.of());
        assertThat(written.getStatusCode().value()).as(String.valueOf(written.getBody())).isEqualTo(200);
        assertThat(((Number) written.getBody().get("written")).intValue()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT score FROM jupeb.ca_score WHERE application_id = :a AND subject_id = :s AND component_id = :c")
                .param("a", app).param("s", subject).param("c", comp).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("20");
    }
}
