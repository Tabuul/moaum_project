package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.OffsetDateTime;
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

/**
 * V364, through the API: a course is examined by CBT only once the catalogue allows it; the University's examinations office runs CBT for its
 * own courses within its scope and with the examination's own settings; a blueprint the pool cannot satisfy is refused, saying what is short;
 * a candidate's paper carries no key, a proctored examination waits for consent, a late save never overwrites a newer one, a question may be
 * marked for review, and the score is the candidate's on submission only where the examination's release policy says so.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CbtEngineIT {

    static final String SESSION = "2118/2119";
    static final String PROGRAMME = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String gst = ItSupport.token("gst");
    String academic = ItSupport.token("academic");
    UUID s;
    String student;
    String dept;
    int n;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    private static Map<String, Object> mapOf(Object... kv) {
        Map<String, Object> m = new java.util.LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) m.put((String) kv[i], kv[i + 1]);
        return m;
    }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2118);
        int pick;
        do {
            pick = new Random().nextInt(9000) + 1000;
        } while (jdbc.sql("SELECT count(*) FROM catalogue.course WHERE code IN (:a, :b)").param("a", "ZZE " + pick).param("b", "GST " + pick).query(Long.class).single() > 0
                || jdbc.sql("SELECT count(*) FROM people.student WHERE matric_no = :m").param("m", "MOAUM/CBE/18/" + pick).query(Long.class).single() > 0);
        n = pick;
        s = it.student("ZZCBE" + n, PROGRAMME, "MOAUM/ADM/18/" + String.format("%06d", 500000 + n), "MOAUM/CBE/18/" + n, 100);
        student = TestTokens.token(s, List.of("student"));
        dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single();
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :id").param("ses", SESSION).param("id", s).update();
            jdbc.sql("UPDATE finance.gst_fee SET superseded_at = now() WHERE session = :ses AND superseded_at IS NULL").param("ses", SESSION).update();
            return null;
        });
    }

    private UUID offeringOf(String code, String kind) {
        it.db(() -> {
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, :t, 2, 1, 100, :d, :k, 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", code).param("t", "CBT engine " + code).param("d", dept).param("k", kind).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, 100, :b) ON CONFLICT DO NOTHING")
                    .param("c", code).param("p", PROGRAMME).param("b", "GST".equals(kind) ? "GST" : "Core").update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :c, :s, 1) ON CONFLICT (course_code, session, semester) DO NOTHING")
                    .param("c", code).param("s", SESSION).update();
            return null;
        });
        return jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = 1").param("c", code).param("s", SESSION).query(UUID.class).single();
    }

    private void register(UUID offering) {
        ResponseEntity<Map> r = it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(offering)));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        it.db(() -> jdbc.sql("UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE student_id = :s AND session = :ses AND semester = 1")
                .param("s", s).param("ses", SESSION).update());
    }

    private UUID question(String token, String code, String stem, int answer, String difficulty) {
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, "/api/v1/cbt/questions", mapOf("course", code, "kind", "MCQ", "stem", stem, "options", List.of("a", "b", "c", "d"),
                "answer", answer, "marks", 1, "difficulty", difficulty, "explanation", "the key is " + answer));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return UUID.fromString(String.valueOf(r.getBody().get("id")));
    }

    private Map<String, Object> examBody(String office, UUID offering, String selection, int total, Map<String, Object> settings) {
        OffsetDateTime now = OffsetDateTime.now();
        return mapOf("office", office, "offeringId", offering, "title", "V364 " + office, "durationMinutes", 30, "selection", selection, "totalQuestions", total,
                "randomizeQuestions", true, "randomizeOptions", true, "passMark", 50, "attemptLimit", 1, "violationLimit", 3, "violationAction", "WARN",
                "secondSession", "CONTINUE", "startsAt", now.minusMinutes(1).toString(), "endsAt", now.plusHours(2).toString(), "settings", settings);
    }

    @Test
    void aCourseIsExaminedByCbtOnlyWhenAllowedAndTheExaminationsOfficeWorksWithinItsScope() {
        String code = "ZZE " + n;
        UUID offering = offeringOf(code, "Core");
        String exams = it.officer("exams", "department", dept);
        String otherDept = jdbc.sql("SELECT code FROM ref.department WHERE code <> :d ORDER BY code LIMIT 1").param("d", dept).query(String.class).single();
        String otherExams = it.officer("exams", "department", otherDept);

        // not yet a CBT course: no examination of it
        ResponseEntity<Map> refused = it.call(exams, HttpMethod.POST, "/api/v1/cbt/exams", examBody("EXAMS", offering, "FIXED", 0, null));
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("CBT_COURSE_NOT_ENABLED");
        // the examinations officer does not set the catalogue; the Academic Office does
        assertThat(it.call(exams, HttpMethod.PUT, "/api/v1/cbt/catalogue/" + code, Map.of("enabled", true)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> allowed = it.call(academic, HttpMethod.PUT, "/api/v1/cbt/catalogue/" + code, Map.of("enabled", true));
        assertThat(allowed.getStatusCode().value()).as(String.valueOf(allowed.getBody())).isEqualTo(200);
        assertThat(allowed.getBody().get("cbt_enabled")).isEqualTo(true);
        ResponseEntity<Map> listed = it.get(academic, "/api/v1/cbt/catalogue?q=" + n + "&enabled=true");
        assertThat(l(listed.getBody().get("rows"))).anySatisfy(r -> assertThat(r.get("code")).isEqualTo(code));

        // another department's examinations officer may not examine it
        ResponseEntity<Map> outside = it.call(otherExams, HttpMethod.POST, "/api/v1/cbt/exams", examBody("EXAMS", offering, "FIXED", 0, null));
        assertThat(outside.getStatusCode().value()).as(String.valueOf(outside.getBody())).isIn(403, 422);

        // the department's examinations officer creates it with its own settings; a forward-only paper has nothing to mark for review
        ResponseEntity<Map> made = it.call(exams, HttpMethod.POST, "/api/v1/cbt/exams", examBody("EXAMS", offering, "RANDOM", 3,
                mapOf("examType", "TEST", "negativeMarks", 0.25, "allowBack", false, "detectors", List.of("TAB", "FULLSCREEN"), "countedEvents", List.of("TAB_SWITCH"),
                      "proctoring", "CAMERA", "sheetComponent", "CA", "warnAt", 2, "finalWarnAt", 3, "disconnectMinutes", 10)));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        String exam = String.valueOf(made.getBody().get("id"));
        Map<String, Object> e = made.getBody();
        assertThat(e.get("office")).isEqualTo("EXAMS");
        assertThat(e.get("exam_type")).isEqualTo("TEST");
        assertThat(e.get("allow_back")).isEqualTo(false);
        assertThat(e.get("allow_review")).isEqualTo(false);
        assertThat(e.get("detectors")).isEqualTo(List.of("FULLSCREEN", "TAB"));
        assertThat(e.get("proctoring")).isEqualTo("CAMERA");
        assertThat(e.get("sheet_component")).isEqualTo("CA");
        // the GST office and the other department read nothing of it
        assertThat(it.get(gst, "/api/v1/cbt/exams/" + exam).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(otherExams, "/api/v1/cbt/exams/" + exam).getStatusCode().value()).isIn(403, 422);

        // a blueprint the pool cannot satisfy is refused, saying what is short; one it can is kept
        question(exams, code, "V364 easy one " + n, 0, "EASY");
        question(exams, code, "V364 hard one " + n, 1, "HARD");
        question(exams, code, "V364 hard two " + n, 2, "HARD");
        ResponseEntity<Map> short_ = it.call(exams, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/blueprint",
                Map.of("dimension", "DIFFICULTY", "rows", List.of(Map.of("value", "HARD", "questions", 3))));
        assertThat(short_.getStatusCode().value()).isEqualTo(422);
        assertThat(short_.getBody().get("code")).isEqualTo("CBT_BLUEPRINT_SHORT");
        assertThat(String.valueOf(short_.getBody().get("detail") == null ? short_.getBody().get("title") : short_.getBody().get("detail")) + short_.getBody())
                .contains("Hard needs 3, the pool holds 2");
        ResponseEntity<Map> kept = it.call(exams, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/blueprint",
                Map.of("dimension", "DIFFICULTY", "rows", List.of(Map.of("value", "EASY", "questions", 1), Map.of("value", "HARD", "questions", 2))));
        assertThat(kept.getStatusCode().value()).as(String.valueOf(kept.getBody())).isEqualTo(200);
        assertThat(l(kept.getBody().get("blueprintRows"))).hasSize(2);

        // published, CBT cannot be withdrawn from the course while the examination is to be completed
        assertThat(it.call(exams, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of()).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> inUse = it.call(academic, HttpMethod.PUT, "/api/v1/cbt/catalogue/" + code, Map.of("enabled", false));
        assertThat(inUse.getStatusCode().value()).isEqualTo(422);
        assertThat(inUse.getBody().get("code")).isEqualTo("CBT_COURSE_IN_USE");

        // a registered student is held to the University's own fee rule: the session's fees cleared for examinations
        register(offering);
        String why = jdbc.sql("SELECT assessment.cbt_eligibility(:e, :s)").param("e", UUID.fromString(exam)).param("s", s).query(String.class).single();
        assertThat(why).startsWith("CBT_FEES_NOT_CLEARED");
    }

    @Test
    void theCandidatesPaperIsFrozenWaitsForConsentAndSavesInOrder() {
        String code = "GST " + n;
        UUID offering = offeringOf(code, "GST");
        assertThat(jdbc.sql("SELECT cbt_enabled FROM catalogue.course WHERE code = :c").param("c", code).query(Boolean.class).single()).as("a General Studies course starts allowed").isTrue();
        UUID q1 = question(gst, code, "V364 first " + n, 0, "MEDIUM");
        UUID q2 = question(gst, code, "V364 second " + n, 1, "MEDIUM");
        ResponseEntity<Map> made = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams", examBody("GST", offering, "FIXED", 0,
                mapOf("negativeMarks", 0.5, "scoreOnSubmit", true, "proctoring", "CAMERA", "allowReview", true)));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        String exam = String.valueOf(made.getBody().get("id"));
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/paper", Map.of("questions", List.of(Map.of("id", q1), Map.of("id", q2)))).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of()).getStatusCode().value()).isEqualTo(200);
        register(offering);

        ResponseEntity<Map> started = it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of());
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        String attempt = String.valueOf(started.getBody().get("attemptId"));
        Map<String, String> h = Map.of("X-Attempt-Token", String.valueOf(started.getBody().get("token")));

        // the paper: the settings the screen needs, and never a key or an explanation
        ResponseEntity<Map> room = it.callWith(student, HttpMethod.GET, "/api/v1/me/cbt/attempts/" + attempt, null, h);
        assertThat(room.getStatusCode().value()).as(String.valueOf(room.getBody())).isEqualTo(200);
        assertThat(m(room.getBody().get("exam")).get("proctoring")).isEqualTo("CAMERA");
        assertThat(m(room.getBody().get("exam")).get("detectors")).isInstanceOf(List.class);
        for (Map<String, Object> q : l(room.getBody().get("questions"))) {
            assertThat(q).doesNotContainKeys("answer", "answers", "explanation");
        }
        assertThat(String.valueOf(room.getBody())).doesNotContain("the key is");

        // nothing is saved before the candidate consents to the camera
        ResponseEntity<Map> early = it.callWith(student, HttpMethod.PUT, "/api/v1/me/cbt/attempts/" + attempt + "/answers",
                Map.of("answers", List.of(Map.of("q", q1, "a", List.of(1), "seq", 1))), h);
        assertThat(early.getStatusCode().value()).isEqualTo(422);
        assertThat(early.getBody().get("code")).isEqualTo("CBT_CONSENT_REQUIRED");
        assertThat(it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/camera", Map.of("consent", true), h).getStatusCode().value()).isEqualTo(200);

        // a wrong answer saved second, marked for review; the right one arriving late with an earlier count changes nothing
        assertThat(it.callWith(student, HttpMethod.PUT, "/api/v1/me/cbt/attempts/" + attempt + "/answers",
                Map.of("answers", List.of(Map.of("q", q1, "a", List.of(1), "seq", 2, "flag", true))), h).getStatusCode().value()).isEqualTo(200);
        assertThat(it.callWith(student, HttpMethod.PUT, "/api/v1/me/cbt/attempts/" + attempt + "/answers",
                Map.of("answers", List.of(Map.of("q", q1, "a", List.of(0), "seq", 1))), h).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> again = it.callWith(student, HttpMethod.GET, "/api/v1/me/cbt/attempts/" + attempt, null, h);
        assertThat(m(again.getBody().get("answers")).get(q1.toString())).isEqualTo(List.of(1));
        assertThat((List<Object>) again.getBody().get("flagged")).contains(q1.toString());
        // the screen's report names the question and how long
        ResponseEntity<Map> ev = it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/events",
                Map.of("events", List.of(Map.of("kind", "WINDOW_BLUR", "n", 1, "ms", 2500))), h);
        assertThat(ev.getStatusCode().value()).as(String.valueOf(ev.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT question_no FROM assessment.cbt_event WHERE attempt_id = :a AND kind = 'WINDOW_BLUR'").param("a", UUID.fromString(attempt)).query(Integer.class).single()).isEqualTo(1);

        // submitted: one wrong (−0.5), one unanswered — never below nought; seen at once because this examination releases it on submission
        assertThat(it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/submit", Map.of(), h).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> result = it.get(student, "/api/v1/me/cbt/attempts/" + attempt + "/result");
        assertThat(result.getStatusCode().value()).as(String.valueOf(result.getBody())).isEqualTo(200);
        assertThat(new java.math.BigDecimal(String.valueOf(result.getBody().get("score")))).isEqualByComparingTo("0");
    }
}
