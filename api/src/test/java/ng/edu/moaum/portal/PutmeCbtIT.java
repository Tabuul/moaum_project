package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * Post-UTME on the one CBT engine (V385), end to end: the Directorate of ICT fills the session's Post-UTME bank and makes the examination;
 * publishing waits for a programme screened by examination; the public door is closed until the Director opens it, then answers a wrong
 * verification with one word and a right one with a token that opens the examination and no dashboard; the candidate lists, starts, reads the
 * paper without its keys, answers, reports, submits and is told nothing of the score — not on submission, not on the list, not at the result
 * door; the Directorate monitors by JAMB number, approves the results, may not publish them through the examination, generates the official
 * file, downloads it and sends it; the Academic Office receives, previews and imports it into the screening score, once; the result-checking
 * door reads nothing until the window is open and the Academic Office releases the scores; the wrong offices are refused. Needs DATABASE_URL.
 * The two tests share one admission session, whose newest open examination decides what the door asks for: they run in order.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class PutmeCbtIT {

    static final String SESSION = "2098/2099";
    static final String PATH = "/api/v1/admissions/sessions/2098/2099";
    static final String SCORES = PATH + "/putme-scores";
    static final String PROGRAMME = "C00066";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String ict = ItSupport.token("ict");
    final String academic = ItSupport.token("academic");
    final String bursar = ItSupport.token("bursar");
    final String housing = ItSupport.token("housing");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2098);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
        // a UTME list loads only under a stated general cut-off
        it.db(() -> jdbc.sql("INSERT INTO admissions.load_cutoff (session, cutoff) VALUES (:s, 140) ON CONFLICT (session) DO UPDATE SET cutoff = 140").param("s", SESSION).update());
        // the two windows closed, as they are until the Director first opens them; an earlier run's acts undone
        it.db(() -> jdbc.sql("DELETE FROM policy.portal_window_event WHERE session = :s AND window_type IN ('POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING')").param("s", SESSION).update());
        it.db(() -> jdbc.sql("DELETE FROM policy.portal_window WHERE session = :s AND window_type IN ('POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING')").param("s", SESSION).update());
    }

    ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    private static String jamb() {
        return "2098" + String.format("%08d", new Random().nextInt(100_000_000)) + "PC";
    }

    /** a registered applicant of the programme, paid and submitted; returns [token, applicationNo, jamb, applicationId] */
    private String[] applicant(String surname) {
        String j = jamb();
        ResponseEntity<Map> loaded = it.call(academic, HttpMethod.POST, "/api/v1/admissions/caps-batches", Map.of(
                "session", SESSION, "source", "CAPS_DOWNLOAD", "filename", "CAPS-putmecbt-" + j + ".xlsx",
                "fileSha256", String.format("%064x", new Random().nextLong() & Long.MAX_VALUE), "listKind", "UTME", "downloadedOn", "2026-09-01",
                "rows", List.of(Map.of("jambRegNo", j, "surname", surname, "otherNames", "Invented", "jambCode", PROGRAMME, "entryMode", "UTME", "sex", "F", "stateOfOrigin", "Benue", "lga", "Gwer West", "aggregate", 240,
                        "raw", Map.of("Subject1", "Use of English", "Subject2", "Lit. in English", "Subject3", "Christian Rel. Know", "Subject4", "Government")))));
        assertThat(loaded.getStatusCode().value()).as(String.valueOf(loaded.getBody())).isEqualTo(201);
        ResponseEntity<Map> registered = post("/api/v1/applicant/register", Map.of("session", SESSION, "jambKey", j, "email", j.toLowerCase() + "@example.com", "phone", "0803" + j.substring(5, 12), "password", "a long enough password"));
        assertThat(registered.getStatusCode().value()).as(String.valueOf(registered.getBody())).isEqualTo(200);
        String token = String.valueOf(registered.getBody().get("token"));
        String appNo = String.valueOf(registered.getBody().get("applicationNo"));
        String reference = String.valueOf(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")).getBody().get("reference"));
        assertThat(it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + reference + "/confirm", Map.of("channel", "Bank transfer")).getStatusCode().value()).isEqualTo(200);
        it.call(token, HttpMethod.PUT, "/api/v1/applicant/me/next-of-kin", Map.of("nextOfKin", surname + ", Terhemba · 0806 552 1180"));
        String pdf = Base64.getEncoder().encodeToString("%PDF-1.4 invented".getBytes());
        for (String kind : List.of("OLEVEL_STATEMENT", "BIRTH_CERT", "LGA_ID", "JAMB_SLIP", "PASSPORT")) {
            it.call(token, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", kind, "filename", kind.toLowerCase() + ".pdf", "contentType", "application/pdf", "contentBase64", pdf));
        }
        ResponseEntity<Map> submitted = it.call(token, HttpMethod.POST, "/api/v1/applicant/me/submit", Map.of("declaration", true));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        String appId = jdbc.sql("SELECT id::text FROM admissions.application WHERE session = :s AND application_no = :n").param("s", SESSION).param("n", appNo).query(String.class).single();
        return new String[] {token, appNo, j, appId};
    }

    private UUID question(String bank, String stem, int answer) {
        ResponseEntity<Map> r = it.call(ict, HttpMethod.POST, "/api/v1/cbt/questions", Map.of("course", bank, "stem", stem, "options", List.of("a", "b", "c", "d"), "answer", answer, "kind", "MCQ", "marks", 1));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        UUID id = UUID.fromString(String.valueOf(r.getBody().get("id")));
        it.approve(id);
        return id;
    }

    private static Map<String, String> tok(String token) {
        return Map.of("X-Attempt-Token", token);
    }

    private void window(String type, String action) {
        it.db(() -> jdbc.sql("SELECT policy.window_act(:t, :s, NULL, :a, NULL, NULL, NULL, false, 'integration test', gen_random_uuid(), 'ict')")
                .param("t", type).param("s", SESSION).param("a", action).query().listOfRows());
    }

    @Test
    @Order(1)
    void fromTheBankToTheReleasedScore() {
        String tag = String.format("%04d", new Random().nextInt(10_000));
        it.db(() -> jdbc.sql("INSERT INTO admissions.screening_exam_programme (session, programme_code) VALUES (:s, :p) ON CONFLICT DO NOTHING").param("s", SESSION).param("p", PROGRAMME).update());
        String[] c = applicant("ZZPUTMECBT-" + tag);

        // ── 1 · the session's bank, the Directorate's; the examination of the session; published once a programme is screened ──
        String bank = "PUTME:" + SESSION;
        assertThat(it.get(academic, "/api/v1/cbt/questions?course=" + bank).getStatusCode().value()).isEqualTo(403);
        List<Map<String, Object>> banks = it.getList(ict, "/api/v1/cbt/courses?office=POST_UTME").getBody();
        assertThat(banks.stream().map(b -> b.get("code"))).contains(bank);
        List<UUID> paper = List.of(question(bank, "one " + tag, 1), question(bank, "two " + tag, 2), question(bank, "three " + tag, 3));
        Map<String, Object> examIn = new java.util.LinkedHashMap<>();
        examIn.put("office", "POST_UTME"); examIn.put("session", SESSION); examIn.put("title", "Post-UTME CBT " + tag); examIn.put("durationMinutes", 30);
        examIn.put("selection", "FIXED"); examIn.put("randomizeQuestions", false); examIn.put("randomizeOptions", false); examIn.put("passMark", 0); examIn.put("attemptLimit", 1);
        examIn.put("securityMode", "STANDARD"); examIn.put("venue", "LAB"); examIn.put("violationLimit", 3); examIn.put("violationAction", "WARN"); examIn.put("secondSession", "DENY");
        examIn.put("startsAt", OffsetDateTime.now().minusMinutes(1).toString()); examIn.put("endsAt", OffsetDateTime.now().plusHours(2).toString());
        examIn.put("settings", Map.of("putmeVerify", "APPLICATION_NO"));
        ResponseEntity<Map> created = it.call(ict, HttpMethod.POST, "/api/v1/cbt/exams", examIn);
        assertThat(created.getStatusCode().value()).as(String.valueOf(created.getBody())).isEqualTo(200);
        String exam = String.valueOf(created.getBody().get("id"));
        assertThat(created.getBody().get("office")).isEqualTo("POST_UTME");
        assertThat(created.getBody().get("putme_session")).isEqualTo(SESSION);
        assertThat(created.getBody().get("putme_verify")).isEqualTo("APPLICATION_NO");
        // a score on submission is refused for a Post-UTME examination
        ResponseEntity<Map> sos = it.call(ict, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam, Map.of("title", "Post-UTME CBT " + tag, "settings", Map.of("scoreOnSubmit", true)));
        assertThat(sos.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(sos.getBody())).contains("CBT_PUTME_NO_SCORE_ON_SUBMIT");
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/paper", Map.of("questions", paper.stream().map(q -> Map.of("id", q)).toList())).getStatusCode().value()).isEqualTo(200);
        // the Academic Office reads but does not manage the Directorate's examinations
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of()).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> published = it.call(ict, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of());
        assertThat(published.getStatusCode().value()).as(String.valueOf(published.getBody())).isEqualTo(200);
        assertThat(published.getBody().get("state")).isEqualTo("PUBLISHED");

        // ── 2 · the public door: closed until the Director opens it; one word for a wrong verification; a token for the right one ──
        ResponseEntity<Map> pub = it.anon(HttpMethod.GET, "/api/v1/putme/cbt/public?session=" + SESSION, null);
        assertThat(pub.getStatusCode().value()).as(String.valueOf(pub.getBody())).isEqualTo(200);
        assertThat(pub.getBody().get("session")).isEqualTo(SESSION);
        assertThat(((Map<String, Object>) pub.getBody().get("cbt")).get("state")).isEqualTo("CLOSED");
        assertThat(pub.getBody().get("factor")).isEqualTo("APPLICATION_NO");
        ResponseEntity<Map> shut = post("/api/v1/putme/cbt/verify", Map.of("session", SESSION, "jambRegNo", c[2], "proof", c[1]));
        assertThat(shut.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(shut.getBody())).contains("CBT_PUTME_WINDOW");
        window("POST_UTME_CBT", "OPEN");
        ResponseEntity<Map> wrong = post("/api/v1/putme/cbt/verify", Map.of("session", SESSION, "jambRegNo", c[2], "proof", "APP/98/999999"));
        assertThat(wrong.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(wrong.getBody())).contains("Candidate verification failed").doesNotContain(c[1]);
        ResponseEntity<Map> verified = post("/api/v1/putme/cbt/verify", Map.of("session", SESSION, "jambRegNo", c[2].toLowerCase(), "proof", c[1]));
        assertThat(verified.getStatusCode().value()).as(String.valueOf(verified.getBody())).isEqualTo(200);
        String candidate = String.valueOf(verified.getBody().get("token"));
        assertThat(((Map<String, Object>) verified.getBody().get("candidate")).get("jambRegNo")).isEqualTo(c[2]);
        assertThat((List<?>) verified.getBody().get("exams")).hasSize(1);
        // the examination token opens no dashboard; the applicant's own sign-in opens no examination
        assertThat(it.get(candidate, "/api/v1/applicant/me").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(candidate, "/api/v1/me").getStatusCode().value()).isIn(403, 404);
        assertThat(it.get(c[0], "/api/v1/putme/cbt").getStatusCode().value()).isEqualTo(403);

        // ── 3 · the room: the paper without its keys, the answers, the reports, the submission — and no score anywhere ──
        Map<String, Object> mine = it.get(candidate, "/api/v1/putme/cbt").getBody();
        Map<String, Object> listed = ((List<Map<String, Object>>) mine.get("rows")).get(0);
        assertThat(listed.get("exam_id")).isEqualTo(exam);
        assertThat(listed.get("eligibility")).isNull();
        ResponseEntity<Map> started = it.call(candidate, HttpMethod.POST, "/api/v1/putme/cbt/exams/" + exam + "/start", Map.of());
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        String attempt = String.valueOf(started.getBody().get("attemptId"));
        String key = String.valueOf(started.getBody().get("token"));
        ResponseEntity<Map> room = it.callWith(candidate, HttpMethod.GET, "/api/v1/putme/cbt/attempts/" + attempt, null, tok(key));
        assertThat(room.getStatusCode().value()).as(String.valueOf(room.getBody())).isEqualTo(200);
        List<Map<String, Object>> questions = (List<Map<String, Object>>) room.getBody().get("questions");
        assertThat(questions).hasSize(3);
        // the paper carries no key: each question has its stem and options and nothing of the answer; the body's "answers" are the candidate's own saves
        for (Map<String, Object> q : questions) assertThat(q).doesNotContainKeys("answers", "answer", "key", "explanation");
        assertThat(((Map<String, Object>) room.getBody().get("candidate")).get("number")).isEqualTo(c[2]);
        // every question answered with its key (the paper is unshuffled, so the key is the authored position)
        List<Map<String, Object>> answers = new java.util.ArrayList<>();
        for (Map<String, Object> q : questions) {
            int n = ((Number) q.get("n")).intValue();
            answers.add(Map.of("q", q.get("id"), "a", List.of(n), "seq", n));
        }
        assertThat(it.callWith(candidate, HttpMethod.PUT, "/api/v1/putme/cbt/attempts/" + attempt + "/answers", Map.of("answers", answers), tok(key)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.callWith(candidate, HttpMethod.POST, "/api/v1/putme/cbt/attempts/" + attempt + "/events", Map.of("events", List.of(Map.of("kind", "TAB_SWITCH", "detail", "test"))), tok(key)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> submitted = it.callWith(candidate, HttpMethod.POST, "/api/v1/putme/cbt/attempts/" + attempt + "/submit", Map.of(), tok(key));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("status")).isEqualTo("SUBMITTED");
        assertThat(String.valueOf(submitted.getBody().get("message"))).contains("SUBMITTED SUCCESSFULLY");
        assertThat(submitted.getBody()).doesNotContainKeys("score", "percentage", "passed", "grade");
        ResponseEntity<Map> result = it.get(candidate, "/api/v1/putme/cbt/attempts/" + attempt + "/result");
        assertThat(result.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(result.getBody())).contains("CBT_PUTME_NO_RESULT_HERE");
        Map<String, Object> after = ((List<Map<String, Object>>) it.get(candidate, "/api/v1/putme/cbt").getBody().get("rows")).get(0);
        assertThat(after.get("attempt_status")).isEqualTo("SUBMITTED");
        assertThat(after.get("score")).isNull();
        assertThat(after.get("percentage")).isNull();
        assertThat(after.get("result_published")).isEqualTo(false);
        // the engine scored it: three of three
        assertThat(jdbc.sql("SELECT percentage FROM assessment.cbt_attempt WHERE id = :a").param("a", UUID.fromString(attempt)).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("100");

        // ── 4 · the Directorate: the monitor by JAMB number; the results approved, never published through the examination ──
        Map<String, Object> monitor = it.get(ict, "/api/v1/cbt/exams/" + exam + "/monitor").getBody();
        assertThat(((List<Map<String, Object>>) monitor.get("rows")).stream().map(r -> r.get("number"))).contains(c[2]);
        for (String action : List.of("close", "complete")) assertThat(it.call(ict, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/" + action, Map.of()).getStatusCode().value()).isEqualTo(200);
        for (String action : List.of("review", "approve")) assertThat(it.call(ict, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/" + action, Map.of()).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> publish = it.call(ict, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/results/publish", Map.of());
        assertThat(publish.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(publish.getBody())).contains("CBT_PUTME_NOT_PUBLISHED_HERE");

        // ── 5 · the official file: generated, downloaded, sent; the Academic Office receives, previews, imports — once ──
        assertThat(it.get(housing, SCORES).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> scores = it.get(ict, SCORES + "?q=" + c[2]).getBody();
        assertThat(((Number) scores.get("total")).intValue()).isEqualTo(1);
        Map<String, Object> row = ((List<Map<String, Object>>) scores.get("rows")).get(0);
        assertThat(row.get("official")).isEqualTo(true);
        assertThat(new java.math.BigDecimal(String.valueOf(row.get("percentage")))).isEqualByComparingTo("100");
        assertThat(it.call(academic, HttpMethod.POST, SCORES + "/exports", Map.of("examId", exam)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> exported = it.call(ict, HttpMethod.POST, SCORES + "/exports", Map.of("examId", exam));
        assertThat(exported.getStatusCode().value()).as(String.valueOf(exported.getBody())).isEqualTo(200);
        String file = String.valueOf(exported.getBody().get("id"));
        assertThat(String.valueOf(exported.getBody().get("reference"))).startsWith("PUTME-SCORE-2098-");
        assertThat(((Number) exported.getBody().get("rows_count")).intValue()).isEqualTo(1);
        assertThat(String.valueOf(exported.getBody().get("sha256"))).hasSize(64);
        Map<String, Object> one = it.get(ict, SCORES + "/exports/" + file).getBody();
        assertThat(((List<Map<String, Object>>) one.get("rows")).get(0).get("jamb_reg_no")).isEqualTo(c[2]);
        // not yet sent: the Academic Office cannot import it
        assertThat(it.call(academic, HttpMethod.POST, SCORES + "/exports/" + file + "/import", Map.of("mode", "KEEP")).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> sent = it.call(ict, HttpMethod.POST, SCORES + "/exports/" + file + "/send", Map.of("message", "Please import"));
        assertThat(sent.getStatusCode().value()).as(String.valueOf(sent.getBody())).isEqualTo(200);
        assertThat(sent.getBody().get("state")).isEqualTo("SENT_TO_ACADEMIC");
        assertThat(it.call(ict, HttpMethod.POST, SCORES + "/exports/" + file + "/import", Map.of("mode", "KEEP")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.POST, SCORES + "/exports/" + file + "/RECEIVE", Map.of()).getBody().get("state")).isEqualTo("RECEIVED");
        Map<String, Object> preview = it.get(academic, SCORES + "/exports/" + file + "/preview").getBody();
        assertThat(((Map<String, Object>) preview.get("summary")).get("NEW")).isEqualTo(1);
        ResponseEntity<Map> imported = it.call(academic, HttpMethod.POST, SCORES + "/exports/" + file + "/import", Map.of("mode", "KEEP"));
        assertThat(imported.getStatusCode().value()).as(String.valueOf(imported.getBody())).isEqualTo(200);
        assertThat(imported.getBody().get("state")).isEqualTo("IMPORTED");
        assertThat(((Map<String, Object>) imported.getBody().get("import")).get("applied")).isEqualTo(1);
        assertThat(jdbc.sql("SELECT screening_score FROM admissions.application WHERE id = :a").param("a", UUID.fromString(c[3])).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("100");
        Map<String, Object> again = it.call(academic, HttpMethod.POST, SCORES + "/exports/" + file + "/import", Map.of("mode", "KEEP")).getBody();
        assertThat(((Map<String, Object>) again.get("import")).get("applied")).isEqualTo(0);
        assertThat(((Map<String, Object>) again.get("import")).get("unchanged")).isEqualTo(1);
        // replacing needs a reason
        assertThat(it.call(academic, HttpMethod.POST, SCORES + "/exports/" + file + "/import", Map.of("mode", "REPLACE")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.getList(academic, SCORES + "/history/" + c[3]).getBody()).hasSize(1);
        // the candidate is now scored on the record: a second sitting is refused on that ground
        assertThat(String.valueOf(((List<Map<String, Object>>) it.get(candidate, "/api/v1/putme/cbt").getBody().get("rows")).get(0).get("eligibility"))).startsWith("CBT_");

        // ── 6 · the result-checking door: closed; open but unreleased; released by the Academic Office ──
        ResponseEntity<Map> closed = post("/api/v1/putme/results/check", Map.of("session", SESSION, "jambRegNo", c[2], "proof", c[1]));
        assertThat(closed.getStatusCode().value()).as(String.valueOf(closed.getBody())).isEqualTo(200);
        assertThat(closed.getBody().get("outcome")).isEqualTo("CLOSED");
        window("POST_UTME_RESULT_CHECKING", "OPEN");
        assertThat(post("/api/v1/putme/results/check", Map.of("session", SESSION, "jambRegNo", c[2], "proof", c[1])).getBody().get("outcome")).isEqualTo("NOT_RELEASED");
        assertThat(post("/api/v1/putme/results/check", Map.of("session", SESSION, "jambRegNo", c[2], "proof", "nope")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/screening-scores/release", Map.of()).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> released = post("/api/v1/putme/results/check", Map.of("session", SESSION, "jambRegNo", c[2], "proof", c[1]));
        assertThat(released.getBody().get("outcome")).isEqualTo("RELEASED");
        assertThat(new java.math.BigDecimal(String.valueOf(released.getBody().get("score")))).isEqualByComparingTo("100");
        // an imported file is not cancelled; a released score is never touched by a further import
        assertThat(it.call(ict, HttpMethod.POST, SCORES + "/exports/" + file + "/cancel", Map.of("reason", "too late")).getStatusCode().value()).isEqualTo(422);
        Map<String, Object> afterRelease = it.call(academic, HttpMethod.POST, SCORES + "/exports/" + file + "/import", Map.of("mode", "REPLACE", "reason", "test")).getBody();
        assertThat(((Map<String, Object>) afterRelease.get("import")).get("released")).isEqualTo(1);
    }

    /** V388: by default the door asks for the JAMB registration number alone and shows no application number; the result-checking page still asks for it */
    @Test
    @Order(2)
    void theJambNumberAloneOpensTheExaminationButNotTheScore() {
        String tag = String.format("%04d", new Random().nextInt(10_000));
        it.db(() -> jdbc.sql("INSERT INTO admissions.screening_exam_programme (session, programme_code) VALUES (:s, :p) ON CONFLICT DO NOTHING").param("s", SESSION).param("p", PROGRAMME).update());
        String[] c = applicant("ZZPUTMEJAMB-" + tag);
        String bank = "PUTME:" + SESSION;
        List<UUID> paper = List.of(question(bank, "alone one " + tag, 1), question(bank, "alone two " + tag, 2));
        Map<String, Object> examIn = new java.util.LinkedHashMap<>();
        examIn.put("office", "POST_UTME"); examIn.put("session", SESSION); examIn.put("title", "Post-UTME CBT by JAMB number " + tag); examIn.put("durationMinutes", 30);
        examIn.put("selection", "FIXED"); examIn.put("randomizeQuestions", false); examIn.put("randomizeOptions", false); examIn.put("passMark", 0); examIn.put("attemptLimit", 1);
        examIn.put("securityMode", "STANDARD"); examIn.put("venue", "LAB"); examIn.put("violationLimit", 3); examIn.put("violationAction", "WARN"); examIn.put("secondSession", "DENY");
        // the newest open examination of the session decides what the door asks for
        examIn.put("startsAt", OffsetDateTime.now().toString()); examIn.put("endsAt", OffsetDateTime.now().plusHours(2).toString());
        ResponseEntity<Map> created = it.call(ict, HttpMethod.POST, "/api/v1/cbt/exams", examIn);
        assertThat(created.getStatusCode().value()).as(String.valueOf(created.getBody())).isEqualTo(200);
        String exam = String.valueOf(created.getBody().get("id"));
        assertThat(created.getBody().get("putme_verify")).isEqualTo("NONE");
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/cbt/exams/" + exam + "/paper", Map.of("questions", paper.stream().map(q -> Map.of("id", q)).toList())).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/cbt/exams/" + exam + "/publish", Map.of()).getStatusCode().value()).isEqualTo(200);
        window("POST_UTME_CBT", "OPEN");

        Map<String, Object> pub = it.anon(HttpMethod.GET, "/api/v1/putme/cbt/public?session=" + SESSION, null).getBody();
        assertThat(pub.get("session")).isEqualTo(SESSION);
        assertThat(pub.get("factor")).isEqualTo("NONE");
        assertThat(pub.get("resultFactor")).isEqualTo("APPLICATION_NO");
        // a JAMB number not on the record is still refused with one word, and counted
        ResponseEntity<Map> unknown = post("/api/v1/putme/cbt/verify", Map.of("session", SESSION, "jambRegNo", jamb()));
        assertThat(unknown.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(unknown.getBody())).contains("Candidate verification failed");
        // the candidate's JAMB number alone opens the door; the application number is not shown
        ResponseEntity<Map> verified = post("/api/v1/putme/cbt/verify", Map.of("session", SESSION, "jambRegNo", c[2]));
        assertThat(verified.getStatusCode().value()).as(String.valueOf(verified.getBody())).isEqualTo(200);
        Map<String, Object> who = (Map<String, Object>) verified.getBody().get("candidate");
        assertThat(who.get("jambRegNo")).isEqualTo(c[2]);
        assertThat(who.get("applicationNo")).isNull();
        String candidate = String.valueOf(verified.getBody().get("token"));
        Map<String, Object> mine = it.get(candidate, "/api/v1/putme/cbt").getBody();
        assertThat(((Map<String, Object>) mine.get("candidate")).get("applicationNo")).isNull();
        assertThat(((List<Map<String, Object>>) mine.get("rows")).stream().map(r -> r.get("exam_id"))).contains(exam);
        assertThat(it.call(candidate, HttpMethod.POST, "/api/v1/putme/cbt/exams/" + exam + "/start", Map.of()).getStatusCode().value()).isEqualTo(200);
        // the token still opens no dashboard
        assertThat(it.get(candidate, "/api/v1/applicant/me").getStatusCode().value()).isEqualTo(403);

        // the result-checking page: the JAMB number alone reads nothing; with the application number it reads the record
        window("POST_UTME_RESULT_CHECKING", "OPEN");
        assertThat(post("/api/v1/putme/results/check", Map.of("session", SESSION, "jambRegNo", c[2])).getStatusCode().value()).isEqualTo(422);
        assertThat(post("/api/v1/putme/results/check", Map.of("session", SESSION, "jambRegNo", c[2], "proof", "")).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> withNumber = post("/api/v1/putme/results/check", Map.of("session", SESSION, "jambRegNo", c[2], "proof", c[1]));
        assertThat(withNumber.getStatusCode().value()).as(String.valueOf(withNumber.getBody())).isEqualTo(200);
        assertThat(withNumber.getBody().get("outcome")).isEqualTo("NOT_RELEASED");
    }
}
