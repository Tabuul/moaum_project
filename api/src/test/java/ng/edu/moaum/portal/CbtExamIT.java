package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import ng.edu.moaum.portal.cbt.CbtClock;

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
 * The CBT examination engine (V322), end to end through the API: the GST office authors in three kinds and builds, publishes and runs an
 * examination; eligibility is the server's judgement (registered, GST fee paid, window open, attempts left); the paper reaches the candidate
 * without its keys; answers save as they go; a second sign-in follows the policy; the violation policy warns and ends; the score is computed
 * at submission and seen by the office at once but by the student only when published; the clock finalises what the browser abandoned;
 * results are reviewed, approved, amended with a reason, published, and sent to the score sheet; the other office and a lecturer are refused.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CbtExamIT {

    static final String SESSION = "2118/2119";
    static final String PROGRAMME = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    CbtClock clock;

    ItSupport it;
    String gst = ItSupport.token("gst");
    String eps = ItSupport.token("eps");
    String bursar = ItSupport.token("bursar");
    String registrar = ItSupport.token("registrar");
    String lecturer = ItSupport.token("lecturer");
    UUID s;
    UUID s2;
    String student;
    String student2;
    String code;
    UUID offering;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2118);
        int n = new Random().nextInt(9000) + 1000;
        s = it.student("ZZCBT" + n, PROGRAMME, "MOAUM/ADM/18/" + String.format("%06d", n), "MOAUM/CBT/18/" + n, 100);
        s2 = it.student("ZZCBX" + n, PROGRAMME, "MOAUM/ADM/18/" + String.format("%06d", n + 1), "MOAUM/CBX/18/" + n, 100);
        student = TestTokens.token(s, List.of("student"));
        student2 = TestTokens.token(s2, List.of("student"));
        code = "GST " + (500 + n % 299);
        it.db(() -> {
            for (UUID id : List.of(s, s2)) {
                jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :id").param("ses", SESSION).param("id", id).update();
                jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08055550322', :e, now()) ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email")
                        .param("s", id).param("e", "zzcbt" + id.toString().substring(0, 8) + "@example.com").update();
            }
            jdbc.sql("UPDATE finance.gst_fee SET superseded_at = now() WHERE session = :ses AND superseded_at IS NULL").param("ses", SESSION).update();
            jdbc.sql("UPDATE finance.gst_setting SET required_for_gst_eps = true, required_for_all = false, covers_eps = true WHERE id = 1").update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, :t, 2, 1, 100, :d, 'GST', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", code).param("t", "CBT General Studies " + n).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, 100, 'GST') ON CONFLICT DO NOTHING").param("c", code).param("p", PROGRAMME).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :c, :s, 1) ON CONFLICT (course_code, session, semester) DO NOTHING")
                    .param("c", code).param("s", SESSION).update();
            return null;
        });
        offering = jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = 1").param("c", code).param("s", SESSION).query(UUID.class).single();
    }

    /* ── helpers ── */

    private UUID question(String kind, String stem, List<String> options, Integer answer, List<Integer> answers, int marks) {
        ResponseEntity<Map> r = it.call(gst, HttpMethod.POST, "/api/v1/cbt/questions", mapOf("course", code, "kind", kind, "stem", stem, "options", options, "answer", answer, "answers", answers, "marks", marks, "difficulty", "MEDIUM"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return UUID.fromString(String.valueOf(r.getBody().get("id")));
    }

    private static Map<String, Object> mapOf(Object... kv) {
        Map<String, Object> m = new java.util.LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) m.put((String) kv[i], kv[i + 1]);
        return m;
    }

    private Map<String, Object> examBody(String title, OffsetDateTime starts, OffsetDateTime ends, int violationLimit, String action, String secondSession) {
        return mapOf("office", "GST", "offeringId", offering, "title", title, "instructions", "Answer every question.", "durationMinutes", 30, "selection", "FIXED",
                "randomizeQuestions", false, "randomizeOptions", false, "passMark", 50, "attemptLimit", 1, "securityMode", "STANDARD", "venue", "REMOTE",
                "violationLimit", violationLimit, "violationAction", action, "secondSession", secondSession, "startsAt", starts.toString(), "endsAt", ends.toString());
    }

    /** the student registered on the offering (with no fee stated, so the gate is quiet), the registration submitted */
    private void register(UUID who, String token) {
        ResponseEntity<Map> r = it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(offering)));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        it.db(() -> jdbc.sql("UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE student_id = :s AND session = :ses AND semester = 1").param("s", who).param("ses", SESSION).update());
    }

    private void stateTheFee() {
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", SESSION, "amount", 10000)).getStatusCode().value()).isEqualTo(200);
    }

    private void pay(String token) {
        ResponseEntity<Map> ref = it.call(token, HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", SESSION));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        String reference = String.valueOf(ref.getBody().get("reference"));
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", reference).query(String.class).single());
    }

    private Map<String, String> tok(String token) {
        return Map.of("X-Attempt-Token", token);
    }

    private List<Map<String, Object>> bankRows(String courseCode) {
        return l(it.get(gst, "/api/v1/cbt/questions?course=" + courseCode).getBody().get("rows"));
    }

    /** the examination built, its paper set and published: four questions, five marks */
    private UUID publishedExam(String title, int violationLimit, String action, String secondSession, List<UUID> paper) {
        OffsetDateTime now = OffsetDateTime.now();
        ResponseEntity<Map> created = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams", examBody(title, now.minusMinutes(1), now.plusHours(2), violationLimit, action, secondSession));
        assertThat(created.getStatusCode().value()).as(String.valueOf(created.getBody())).isEqualTo(200);
        UUID exam = UUID.fromString(String.valueOf(created.getBody().get("id")));
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/paper", Map.of("questions", paper.stream().map(q -> Map.of("id", q)).toList())).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> published = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of());
        assertThat(published.getStatusCode().value()).as(String.valueOf(published.getBody())).isEqualTo(200);
        assertThat(published.getBody().get("state")).isEqualTo("PUBLISHED");
        return exam;
    }

    private List<UUID> paper() {
        return List.of(
                question("MCQ", "One of four", List.of("a", "b", "c", "d"), 2, null, 1),
                question("TRUE_FALSE", "The sky is up", List.of("True", "False"), 0, null, 1),
                question("MULTI", "Which are even", List.of("1", "2", "3", "4"), null, List.of(1, 3), 2),
                question("MCQ", "Worth one", List.of("x", "y"), 1, null, 1));
    }

    @Test
    void theOfficeBuildsPublishesAndIsTheOnlyOneWhoMay() {
        // the bank: three kinds, in the office's own course; the other office and a lecturer are refused the GST course
        List<UUID> paper = paper();
        assertThat(it.call(eps, HttpMethod.POST, "/api/v1/cbt/questions", mapOf("course", code, "stem", "No", "options", List.of("a", "b"), "answer", 0)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> bankRead = it.get(gst, "/api/v1/cbt/questions?course=" + code);
        assertThat(bankRead.getStatusCode().value()).as(String.valueOf(bankRead.getBody())).isEqualTo(200);
        Map<String, Object> bank = bankRead.getBody();
        assertThat(l(bank.get("rows"))).hasSizeGreaterThanOrEqualTo(4);
        assertThat(l(bank.get("rows"))).anySatisfy(q -> { assertThat(q.get("kind")).isEqualTo("MULTI"); assertThat(String.valueOf(q.get("answers"))).contains("1").contains("3"); });
        List<Map<String, Object>> courses = it.getList(eps, "/api/v1/cbt/courses").getBody();
        assertThat(courses).noneSatisfy(c -> assertThat(c.get("code")).isEqualTo(code));

        // the examination: only the GST office creates one over a GST course
        OffsetDateTime now = OffsetDateTime.now();
        assertThat(it.call(eps, HttpMethod.POST, "/api/v1/cbt/exams", examBody("Not mine", now, now.plusHours(1), 2, "WARN", "CONTINUE")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(lecturer, HttpMethod.POST, "/api/v1/cbt/exams", examBody("Not mine", now, now.plusHours(1), 2, "WARN", "CONTINUE")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> created = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams", examBody("First CBT", now.minusMinutes(1), now.plusHours(2), 2, "WARN", "CONTINUE"));
        assertThat(created.getStatusCode().value()).as(String.valueOf(created.getBody())).isEqualTo(200);
        UUID exam = UUID.fromString(String.valueOf(created.getBody().get("id")));
        assertThat(String.valueOf(created.getBody().get("reference"))).startsWith("CBT/2118-2119/");
        assertThat(created.getBody().get("state")).isEqualTo("DRAFT");
        // no paper, no publication
        ResponseEntity<Map> empty = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of());
        assertThat(empty.getStatusCode().value()).isEqualTo(422);
        assertThat(empty.getBody().get("code")).isEqualTo("CBT_PAPER_EMPTY");
        // the EPS office reads nothing of it
        assertThat(it.get(eps, "/api/v1/cbt/exams/" + exam).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(eps, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/paper", Map.of("questions", List.of(Map.of("id", paper.get(0))))).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/paper", Map.of("questions", paper.stream().map(q -> Map.of("id", q)).toList())).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> detail = it.get(gst, "/api/v1/cbt/exams/" + exam).getBody();
        assertThat(l(detail.get("paper"))).hasSize(4);
        assertThat(((Number) detail.get("pool_marks")).intValue()).isEqualTo(5);
        assertThat(detail.get("paper_problem")).isNull();

        // registered candidates are told on publication
        register(s, student);
        ResponseEntity<Map> published = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of());
        assertThat(published.getStatusCode().value()).as(String.valueOf(published.getBody())).isEqualTo(200);
        assertThat(published.getBody().get("live_state")).isEqualTo("OPEN");
        long told = jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject LIKE :c").param("s", s).param("c", code + " CBT examination%").query(Long.class).single();
        assertThat(told).isGreaterThanOrEqualTo(1);
        // the published paper is fixed
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/paper", Map.of("questions", List.of())).getBody().get("code")).isEqualTo("CBT_STATE");
        // the office's list and summary count it
        Map<String, Object> list = it.get(gst, "/api/v1/cbt/exams?office=GST&session=" + SESSION).getBody();
        assertThat(l(list.get("rows"))).anySatisfy(r -> { assertThat(r.get("id")).isEqualTo(exam.toString()); assertThat(((Number) r.get("candidates")).intValue()).isEqualTo(1); });
        Map<String, Object> summary = it.get(registrar, "/api/v1/cbt/summary?office=GST&session=" + SESSION).getBody();
        assertThat(((Number) m(summary.get("summary")).get("open")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(it.get(eps, "/api/v1/cbt/summary?office=GST&session=" + SESSION).getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void eligibilityIsTheServersJudgementAndThePaperCarriesNoKey() {
        List<UUID> paper = paper();
        UUID exam = publishedExam("Second CBT", 2, "WARN", "CONTINUE", paper);
        // not registered: the examination is not even the student's
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of()).getStatusCode().value()).isEqualTo(404);
        assertThat(l(it.get(student, "/api/v1/me/cbt?session=" + SESSION).getBody().get("rows"))).isEmpty();
        // registered, then the fee stated: held on the GST payment, with the business code
        register(s, student);
        stateTheFee();
        Map<String, Object> mine = it.get(student, "/api/v1/me/cbt?session=" + SESSION).getBody();
        assertThat(l(mine.get("rows"))).anySatisfy(r -> { assertThat(r.get("exam_id")).isEqualTo(exam.toString()); assertThat(String.valueOf(r.get("eligibility"))).startsWith("GST_PAYMENT_REQUIRED"); });
        ResponseEntity<Map> held = it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of());
        assertThat(held.getStatusCode().value()).isEqualTo(422);
        assertThat(held.getBody().get("code")).isEqualTo("GST_PAYMENT_REQUIRED");
        // paid: eligible; a future examination is not yet open
        pay(student);
        OffsetDateTime now = OffsetDateTime.now();
        ResponseEntity<Map> future = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams", examBody("Tomorrow", now.plusDays(1), now.plusDays(1).plusHours(2), 2, "WARN", "CONTINUE"));
        UUID later = UUID.fromString(String.valueOf(future.getBody().get("id")));
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/exams/" + later + "/paper", Map.of("questions", paper.stream().map(q -> Map.of("id", q)).toList())).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + later + "/publish", Map.of()).getBody().get("live_state")).isEqualTo("UPCOMING");
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + later + "/start", Map.of()).getBody().get("code")).isEqualTo("CBT_EXAM_NOT_STARTED");

        ResponseEntity<Map> started = it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of());
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        String attempt = String.valueOf(started.getBody().get("attemptId"));
        String token = String.valueOf(started.getBody().get("token"));
        assertThat(started.getBody().get("status")).isEqualTo("IN_PROGRESS");

        // the paper: without the token nothing; with another student's token nothing; with the token, the questions and never a key
        assertThat(it.get(student, "/api/v1/me/cbt/attempts/" + attempt).getBody().get("code")).isEqualTo("CBT_TOKEN_REQUIRED");
        assertThat(it.callWith(student2, HttpMethod.GET, "/api/v1/me/cbt/attempts/" + attempt, null, tok(token)).getStatusCode().value()).isEqualTo(404);
        ResponseEntity<Map> room = it.callWith(student, HttpMethod.GET, "/api/v1/me/cbt/attempts/" + attempt, null, tok(token));
        assertThat(room.getStatusCode().value()).as(String.valueOf(room.getBody())).isEqualTo(200);
        List<Map<String, Object>> questions = l(room.getBody().get("questions"));
        assertThat(questions).hasSize(4);
        String json = String.valueOf(questions);
        assertThat(json).doesNotContain("answer").doesNotContain("correct").doesNotContain("explanation");
        assertThat(questions.get(0).keySet()).containsExactlyInAnyOrder("n", "id", "kind", "stem", "marks", "options");
        assertThat(m(questions.get(2)).get("kind")).isEqualTo("MULTI");
        // the options are a JSON array of position and text — what a screen renders, never a database object
        assertThat(l(questions.get(0).get("options"))).hasSize(4);
        assertThat(l(questions.get(0).get("options")).get(0).keySet()).containsExactlyInAnyOrder("i", "text");
        assertThat(l(l(bankRows(code)).get(0).get("options"))).isNotEmpty();

        // answers save as they go; a question not on the paper is refused; the office's monitor sees the activity, never the answers
        UUID q1 = UUID.fromString(String.valueOf(questions.get(0).get("id"))), q2 = UUID.fromString(String.valueOf(questions.get(1).get("id"))),
             q3 = UUID.fromString(String.valueOf(questions.get(2).get("id"))), q4 = UUID.fromString(String.valueOf(questions.get(3).get("id")));
        ResponseEntity<Map> saved = it.callWith(student, HttpMethod.PUT, "/api/v1/me/cbt/attempts/" + attempt + "/answers", Map.of("answers", List.of(
                Map.of("q", q1, "a", List.of(2)), Map.of("q", q2, "a", List.of(0)), Map.of("q", q3, "a", List.of(1)), Map.of("q", q4, "a", List.of(1)))), tok(token));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat(((Number) saved.getBody().get("answered")).intValue()).isEqualTo(4);
        assertThat(it.callWith(student, HttpMethod.PUT, "/api/v1/me/cbt/attempts/" + attempt + "/answers", Map.of("answers", List.of(Map.of("q", UUID.randomUUID(), "a", List.of(0)))), tok(token)).getBody().get("code")).isEqualTo("CBT_QUESTION_NOT_ON_PAPER");
        Map<String, Object> monitor = it.get(gst, "/api/v1/cbt/exams/" + exam + "/monitor").getBody();
        assertThat(((Number) m(monitor.get("counts")).get("in_progress")).intValue()).isEqualTo(1);
        assertThat(l(monitor.get("rows"))).anySatisfy(r -> { assertThat(r.get("student_id")).isEqualTo(s.toString()); assertThat(((Number) r.get("answered")).intValue()).isEqualTo(4); assertThat(r.keySet()).doesNotContain("answers", "chosen"); });

        // the browser's reports: the first a warning, the second the final warning, a disconnection recorded but not counted
        ResponseEntity<Map> first = it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/events", Map.of("events", List.of(Map.of("kind", "TAB_SWITCH", "detail", "hidden 4s"))), tok(token));
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
        assertThat(first.getBody().get("level")).isEqualTo("WARNING");
        assertThat(((Number) first.getBody().get("violations")).intValue()).isEqualTo(1);
        ResponseEntity<Map> second = it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/events", Map.of("events", List.of(Map.of("kind", "WINDOW_BLUR"), Map.of("kind", "NETWORK_DISCONNECT"))), tok(token));
        assertThat(second.getBody().get("level")).isEqualTo("FINAL_WARNING");
        assertThat(((Number) second.getBody().get("violations")).intValue()).isEqualTo(2);
        assertThat(second.getBody().get("status")).isEqualTo("IN_PROGRESS");

        // submission: scored at once — 1 + 1 + 0 (one of the two even numbers) + 1 of 5 = 60%, B, passed — and the student sees nothing until it is published
        ResponseEntity<Map> submitted = it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/submit", Map.of(), tok(token));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("status")).isEqualTo("SUBMITTED");
        assertThat(it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/ping", Map.of(), tok(token)).getBody().get("status")).isEqualTo("SUBMITTED");
        assertThat(it.callWith(student, HttpMethod.PUT, "/api/v1/me/cbt/attempts/" + attempt + "/answers", Map.of("answers", List.of(Map.of("q", q1, "a", List.of(0)))), tok(token)).getBody().get("code")).isEqualTo("CBT_ATTEMPT_CLOSED");
        assertThat(it.get(student, "/api/v1/me/cbt/attempts/" + attempt + "/result").getBody().get("code")).isEqualTo("CBT_RESULT_NOT_PUBLISHED");
        Map<String, Object> office = it.get(gst, "/api/v1/cbt/exams/" + exam + "/candidates/" + s).getBody();
        Map<String, Object> cand = m(office.get("candidate"));
        assertThat(cand.get("attempt_status")).isEqualTo("SUBMITTED");
        assertThat(new BigDecimal(String.valueOf(cand.get("score")))).isEqualByComparingTo("3");
        assertThat(new BigDecimal(String.valueOf(cand.get("percentage")))).isEqualByComparingTo("60");
        assertThat(cand.get("grade")).isEqualTo("B");
        assertThat(cand.get("passed")).isEqualTo(true);
        assertThat(l(office.get("events"))).extracting(e -> e.get("kind")).contains("STARTED", "TAB_SWITCH", "WARNING", "WINDOW_BLUR", "FINAL_WARNING", "NETWORK_DISCONNECT", "SUBMITTED");
        // one attempt allowed
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of()).getBody().get("code")).isEqualTo("CBT_ATTEMPT_LIMIT");

        // the results: reviewed, approved, amended with a reason, published; then only stronger authority changes them
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/approve", Map.of()).getBody().get("code")).isEqualTo("CBT_NOT_COMPLETED");
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/close", Map.of()).getBody().get("state")).isEqualTo("CLOSED");
        ResponseEntity<Map> completed = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/complete", Map.of());
        assertThat(completed.getBody().get("state")).isEqualTo("COMPLETED");
        assertThat(completed.getBody().get("results_state")).isEqualTo("AUTO_SCORED");
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/review", Map.of()).getBody().get("results_state")).isEqualTo("UNDER_REVIEW");
        assertThat(it.call(eps, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/attempts/" + attempt + "/result", Map.of("score", 4, "outcome", "SCORED", "reason", "not mine")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/attempts/" + attempt + "/result", Map.of("score", 4, "outcome", "SCORED", "reason", "")).getStatusCode().value()).isEqualTo(400);
        ResponseEntity<Map> amended = it.call(gst, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/attempts/" + attempt + "/result", Map.of("score", 4, "outcome", "SCORED", "reason", "Marking review: the fourth key was corrected"));
        assertThat(amended.getStatusCode().value()).as(String.valueOf(amended.getBody())).isEqualTo(200);
        assertThat(l(amended.getBody().get("versions"))).hasSize(2);
        assertThat(new BigDecimal(String.valueOf(m(amended.getBody().get("candidate")).get("percentage")))).isEqualByComparingTo("80");
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/approve", Map.of()).getBody().get("results_state")).isEqualTo("APPROVED");

        // onto the score sheet as the examination component, scaled to the course's examination maximum; without a CA the mark is incomplete
        UUID sheet = it.db(() -> jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id, stage) VALUES (gen_random_uuid(), :o, 'ENTRY') RETURNING id").param("o", offering).query(UUID.class).single());
        ResponseEntity<Map> toSheet = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/to-sheet", Map.of());
        assertThat(toSheet.getStatusCode().value()).as(String.valueOf(toSheet.getBody())).isEqualTo(200);
        assertThat(((Number) toSheet.getBody().get("written")).intValue()).isEqualTo(1);
        Map<String, Object> mark = jdbc.sql("SELECT exam, ca, outcome, reason FROM assessment.score WHERE sheet_id = :sh AND student_id = :s ORDER BY version DESC LIMIT 1").param("sh", sheet).param("s", s).query().singleRow();
        int caMax = jdbc.sql("SELECT ca_max FROM catalogue.course WHERE code = :c").param("c", code).query(Integer.class).single();
        assertThat(((Number) mark.get("exam")).intValue()).isEqualTo(Math.round(80f * (100 - caMax) / 100f));
        assertThat(mark.get("outcome")).isEqualTo("INCOMPLETE");
        assertThat(String.valueOf(mark.get("reason"))).startsWith("CBT CBT/2118-2119/");
        assertThat(((Number) it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/to-sheet", Map.of()).getBody().get("written")).intValue()).isEqualTo(0);

        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/publish", Map.of()).getBody().get("results_state")).isEqualTo("PUBLISHED");
        ResponseEntity<Map> result = it.get(student, "/api/v1/me/cbt/attempts/" + attempt + "/result");
        assertThat(result.getStatusCode().value()).as(String.valueOf(result.getBody())).isEqualTo(200);
        assertThat(new BigDecimal(String.valueOf(result.getBody().get("percentage")))).isEqualByComparingTo("80");
        assertThat(result.getBody().get("grade")).isEqualTo("A");
        assertThat(l(it.get(student, "/api/v1/me/cbt?session=" + SESSION).getBody().get("rows"))).anySatisfy(r -> { assertThat(r.get("exam_id")).isEqualTo(exam.toString()); assertThat(r.get("result_published")).isEqualTo(true); assertThat(r.get("grade")).isEqualTo("A"); });
        // published: the office may no longer amend or withdraw; the Registrar may
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/attempts/" + attempt + "/result", Map.of("score", 5, "outcome", "SCORED", "reason", "late")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/unpublish", Map.of()).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/attempts/" + attempt + "/result", Map.of("score", 5, "outcome", "SCORED", "reason", "Senate's correction")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(registrar, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/unpublish", Map.of()).getBody().get("results_state")).isEqualTo("APPROVED");
        assertThat(it.get(student, "/api/v1/me/cbt/attempts/" + attempt + "/result").getBody().get("code")).isEqualTo("CBT_RESULT_NOT_PUBLISHED");
        // the analytics count the sitting
        Map<String, Object> analytics = it.get(registrar, "/api/v1/cbt/exams/" + exam + "/analytics").getBody();
        assertThat(((Number) m(analytics.get("totals")).get("scored")).intValue()).isEqualTo(1);
        assertThat(l(analytics.get("byProgramme"))).anySatisfy(g -> assertThat(g.get("programme_code")).isEqualTo(PROGRAMME));
        // a question that has been sat keeps its options and key
        ResponseEntity<Map> edit = it.call(gst, HttpMethod.PUT, "/api/v1/cbt/questions/" + q1, mapOf("stem", "One of four, reworded", "options", List.of("a", "b", "c"), "answer", 1, "kind", "MCQ"));
        assertThat(edit.getBody().get("code")).isEqualTo("CBT_QUESTION_SAT");
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/questions/" + q1, mapOf("stem", "One of four, reworded", "options", List.of("a", "b", "c", "d"), "answer", 2, "kind", "MCQ", "explanation", "c is right")).getStatusCode().value()).isEqualTo(200);
    }

    @Test
    void partialCreditMarksAMultipleSelectQuestionByItsRule() {
        List<UUID> paper = paper();
        OffsetDateTime now = OffsetDateTime.now();
        Map<String, Object> body = examBody("Partial credit CBT", now.minusMinutes(1), now.plusHours(2), 2, "WARN", "CONTINUE");
        body.put("partialCredit", true);
        ResponseEntity<Map> created = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams", body);
        assertThat(created.getStatusCode().value()).as(String.valueOf(created.getBody())).isEqualTo(200);
        assertThat(created.getBody().get("partial_credit")).isEqualTo(true);
        UUID exam = UUID.fromString(String.valueOf(created.getBody().get("id")));
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/paper", Map.of("questions", paper.stream().map(q -> Map.of("id", q)).toList())).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of()).getBody().get("state")).isEqualTo("PUBLISHED");
        register(s, student);
        ResponseEntity<Map> started = it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of());
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        String attempt = String.valueOf(started.getBody().get("attemptId"));
        String token = String.valueOf(started.getBody().get("token"));
        ResponseEntity<Map> room = it.callWith(student, HttpMethod.GET, "/api/v1/me/cbt/attempts/" + attempt, null, tok(token));
        assertThat(m(room.getBody().get("exam")).get("partial_credit")).isEqualTo(true);
        List<Map<String, Object>> questions = l(room.getBody().get("questions"));
        UUID multi = UUID.fromString(String.valueOf(questions.stream().filter(q -> "MULTI".equals(q.get("kind"))).findFirst().orElseThrow().get("id")));
        // one of the two right options, nothing wrong: half the question's two marks; everything else left blank
        it.callWith(student, HttpMethod.PUT, "/api/v1/me/cbt/attempts/" + attempt + "/answers", Map.of("answers", List.of(Map.of("q", multi, "a", List.of(1)))), tok(token));
        ResponseEntity<Map> submitted = it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/submit", Map.of(), tok(token));
        assertThat(submitted.getBody().get("status")).isEqualTo("SUBMITTED");
        Map<String, Object> cand = m(it.get(gst, "/api/v1/cbt/exams/" + exam + "/candidates/" + s).getBody().get("candidate"));
        assertThat(new BigDecimal(String.valueOf(cand.get("score")))).as("1 of 5: half of the multiple-select question's 2 marks").isEqualByComparingTo("1");
        assertThat(new BigDecimal(String.valueOf(cand.get("percentage")))).isEqualByComparingTo("20");
        // the same answer on an all-or-nothing paper earns nothing: the rule is the examination's
        assertThat(jdbc.sql("SELECT assessment.cbt_marks_for('MULTI', ARRAY[1,3], ARRAY[1], 2, false)").query(BigDecimal.class).single()).isEqualByComparingTo("0");
        assertThat(jdbc.sql("SELECT assessment.cbt_marks_for('MULTI', ARRAY[1,3], ARRAY[0,1,2,3], 2, true)").query(BigDecimal.class).single()).as("select everything earns nothing").isEqualByComparingTo("0");
    }

    @Test
    void aSecondSignInFollowsThePolicyAndTheClockFinalisesWhatTheBrowserAbandoned() {
        List<UUID> paper = paper();
        UUID exam = publishedExam("Third CBT", 1, "TERMINATE", "CONTINUE", paper);
        register(s, student);
        register(s2, student2);
        stateTheFee();
        pay(student);
        pay(student2);
        ResponseEntity<Map> first = it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of());
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
        String attempt = String.valueOf(first.getBody().get("attemptId"));
        String token1 = String.valueOf(first.getBody().get("token"));
        // opened again: the same attempt continues, the token rotates, the first screen is refused, the second sign-in is on the record
        ResponseEntity<Map> again = it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of());
        assertThat(String.valueOf(again.getBody().get("attemptId"))).isEqualTo(attempt);
        String token2 = String.valueOf(again.getBody().get("token"));
        assertThat(token2).isNotEqualTo(token1);
        assertThat(it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/ping", Map.of(), tok(token1)).getBody().get("code")).isEqualTo("CBT_SESSION_REPLACED");
        assertThat(it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/ping", Map.of(), tok(token2)).getBody().get("status")).isEqualTo("IN_PROGRESS");
        Map<String, Object> detail = it.get(gst, "/api/v1/cbt/exams/" + exam + "/candidates/" + s).getBody();
        assertThat(l(detail.get("events"))).extracting(e -> e.get("kind")).contains("MULTIPLE_LOGIN", "SESSION_REPLACED");
        assertThat(((Number) m(detail.get("candidate")).get("violations")).intValue()).isEqualTo(1);
        // over the limit of one: the policy terminates, and the office sees it in the monitor's events
        ResponseEntity<Map> over = it.callWith(student, HttpMethod.POST, "/api/v1/me/cbt/attempts/" + attempt + "/events", Map.of("events", List.of(Map.of("kind", "FULLSCREEN_EXIT"))), tok(token2));
        assertThat(over.getBody().get("action")).isEqualTo("TERMINATED");
        assertThat(over.getBody().get("status")).isEqualTo("TERMINATED");
        Map<String, Object> monitor = it.get(gst, "/api/v1/cbt/exams/" + exam + "/monitor").getBody();
        assertThat(((Number) m(monitor.get("counts")).get("terminated")).intValue()).isEqualTo(1);
        assertThat(l(monitor.get("events"))).anySatisfy(e -> assertThat(e.get("kind")).isEqualTo("TERMINATED"));
        // the monitor's delta: nothing since its own cursor
        String cursor = String.valueOf(monitor.get("cursor"));
        assertThat(l(it.get(gst, "/api/v1/cbt/exams/" + exam + "/monitor?since=" + cursor.replace("+", "%2B")).getBody().get("rows"))).isEmpty();

        // the second candidate walks away: the clock finalises the attempt from the answers saved so far
        ResponseEntity<Map> other = it.call(student2, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of());
        String attempt2 = String.valueOf(other.getBody().get("attemptId"));
        String tokenB = String.valueOf(other.getBody().get("token"));
        ResponseEntity<Map> room = it.callWith(student2, HttpMethod.GET, "/api/v1/me/cbt/attempts/" + attempt2, null, tok(tokenB));
        UUID q1 = UUID.fromString(String.valueOf(l(room.getBody().get("questions")).get(0).get("id")));
        it.callWith(student2, HttpMethod.PUT, "/api/v1/me/cbt/attempts/" + attempt2 + "/answers", Map.of("answers", List.of(Map.of("q", q1, "a", List.of(2)))), tok(tokenB));
        it.db(() -> jdbc.sql("UPDATE assessment.cbt_attempt SET ends_at = now() - interval '1 minute' WHERE id = :a").param("a", UUID.fromString(attempt2)).update());
        assertThat(clock.sweep()).isGreaterThanOrEqualTo(1);
        Map<String, Object> swept = m(it.get(gst, "/api/v1/cbt/exams/" + exam + "/candidates/" + s2).getBody().get("candidate"));
        assertThat(swept.get("attempt_status")).isEqualTo("TIME_EXPIRED");
        assertThat(new BigDecimal(String.valueOf(swept.get("score")))).isEqualByComparingTo("1");
        // the office closes an attempt itself, with a reason; a lecturer reads nothing
        assertThat(it.get(lecturer, "/api/v1/cbt/exams/" + exam + "/monitor").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> candidates = it.get(gst, "/api/v1/cbt/exams/" + exam + "/candidates?status=TERMINATED");
        assertThat(((Number) candidates.getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) it.get(gst, "/api/v1/cbt/exams/" + exam + "/candidates?status=TIME_EXPIRED").getBody().get("total")).intValue()).isEqualTo(1);
        // a second sign-in refused where the policy says so
        it.db(() -> jdbc.sql("UPDATE assessment.cbt_exam SET second_session = 'DENY', attempt_limit = 2 WHERE id = :e").param("e", exam).update());
        ResponseEntity<Map> fresh = it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of());
        assertThat(fresh.getStatusCode().value()).as(String.valueOf(fresh.getBody())).isEqualTo(200);
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/cbt/exams/" + exam + "/start", Map.of()).getBody().get("code")).isEqualTo("CBT_SECOND_SESSION_DENIED");
        // cancelled: the attempt in progress is terminated and the office's reason is on the examination
        ResponseEntity<Map> cancelled = it.call(gst, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/cancel", Map.of("reason", "Power failure at the centre"));
        assertThat(cancelled.getBody().get("state")).isEqualTo("CANCELLED");
        assertThat(((Number) m(cancelled.getBody().get("counts")).get("in_progress")).intValue()).isEqualTo(0);
    }
}
