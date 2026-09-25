package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.Base64;
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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * External examiners (V254), end to end: the Academic Office records and invites an examiner; the activation link opens
 * once and sets the password; the office registers a project, releases a report and assigns it; the examiner sees only
 * their own project and documents, saves a draft, cannot submit half-scored, submits, and can no longer change it; another
 * examiner is refused; the office reopens on a reason, the examiner resubmits, the office locks; a student is refused the
 * desk and the examiner is refused the desk.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ExaminersIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;
    String academic = ItSupport.token("academic");
    UUID student;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session("2091/2092", 2091);
        student = it.student("ZZEXPROJECT", "C00023", null, "MOAUM/MTC/95/9801", 400);
    }

    private ResponseEntity<Map> anonymous(HttpMethod method, String path, Object body) {
        RestClient c = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(status -> true, (request, response) -> { }).build();
        RestClient.RequestBodySpec spec = c.method(method).uri(path).contentType(MediaType.APPLICATION_JSON);
        return (body == null ? spec : spec.body(body)).retrieve().toEntity(Map.class);
    }

    private static Object path(Map body, String key) {
        return body == null ? null : body.get(key);
    }

    @Test
    void theWholeJourneyAndItsWalls() {
        // the examiner recorded and invited; the token read straight from the outbox the way the email carries it
        String email = "zz.examiner." + UUID.randomUUID().toString().substring(0, 6) + "@example.edu";
        ResponseEntity<Map> made = it.call(academic, HttpMethod.POST, "/api/v1/examiners", Map.of("firstName", "Ngozi", "lastName", "Okonkwo", "title", "Prof.", "email", email, "institution", "University of Jos", "invite", true));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        String examinerId = String.valueOf(path(made.getBody(), "id"));
        String link = jdbc.sql("SELECT body FROM platform.notice WHERE recipient = :e ORDER BY created_at DESC LIMIT 1").param("e", email).query(String.class).single();
        String token = link.replaceAll("(?s).*activate\\?token=([0-9a-f]+).*", "$1");
        assertThat(token).hasSize(64);

        // the public link tells who is invited, refuses a weak password, activates once
        assertThat(anonymous(HttpMethod.GET, "/api/v1/examiners/invitation/" + token, null).getStatusCode().value()).isEqualTo(200);
        assertThat(anonymous(HttpMethod.POST, "/api/v1/examiners/activate", Map.of("token", token, "password", "short")).getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> activated = anonymous(HttpMethod.POST, "/api/v1/examiners/activate", Map.of("token", token, "password", "A-long-enough-password-2026"));
        assertThat(activated.getStatusCode().value()).as(String.valueOf(activated.getBody())).isEqualTo(200);
        assertThat(anonymous(HttpMethod.POST, "/api/v1/examiners/activate", Map.of("token", token, "password", "A-long-enough-password-2026")).getStatusCode().value()).isEqualTo(422);
        UUID personId = jdbc.sql("SELECT person_id FROM extexam.examiner WHERE id = :id::uuid").param("id", examinerId).query(UUID.class).single();
        assertThat(jdbc.sql("SELECT status FROM extexam.examiner WHERE id = :id::uuid").param("id", examinerId).query(String.class).single()).isEqualTo("ACTIVE");
        assertThat(jdbc.sql("SELECT username FROM iam.credential WHERE person_id = :p").param("p", personId).query(String.class).single()).isEqualTo(email);
        String examiner = TestTokens.token(personId, List.of("extexaminer"));

        // a second examiner, for the walls
        ResponseEntity<Map> other = it.call(academic, HttpMethod.POST, "/api/v1/examiners", Map.of("firstName", "Bala", "lastName", "Usman", "email", "zz.other." + UUID.randomUUID().toString().substring(0, 6) + "@example.edu", "institution", "ABU Zaria"));
        UUID otherPerson = jdbc.sql("SELECT person_id FROM extexam.examiner WHERE id = :id::uuid").param("id", String.valueOf(path(other.getBody(), "id"))).query(UUID.class).single();
        it.db(() -> { jdbc.sql("UPDATE extexam.examiner SET status = 'ACTIVE', activated_at = now() WHERE person_id = :p").param("p", otherPerson).update(); return null; });
        String otherExaminer = TestTokens.token(otherPerson, List.of("extexaminer"));

        // the project registered, a report released, and the project assigned
        ResponseEntity<Map> project = it.call(academic, HttpMethod.POST, "/api/v1/examiners/projects", Map.of("studentId", student.toString(), "session", "2091/2092", "title", "A checked project on numerical methods", "abstractText", "We study a thing.", "supervisorName", "Dr Invented"));
        assertThat(project.getStatusCode().value()).as(String.valueOf(project.getBody())).isEqualTo(200);
        String projectId = String.valueOf(path(project.getBody(), "id"));
        byte[] pdf = "%PDF-1.4 a small report".getBytes();
        ResponseEntity<Map> doc = it.call(academic, HttpMethod.POST, "/api/v1/examiners/projects/" + projectId + "/documents", Map.of("kind", "REPORT", "filename", "report.pdf", "contentType", "application/pdf", "contentBase64", Base64.getEncoder().encodeToString(pdf)));
        assertThat(doc.getStatusCode().value()).as(String.valueOf(doc.getBody())).isEqualTo(200);
        String docId = String.valueOf(path(doc.getBody(), "id"));
        ResponseEntity<Map> fake = it.call(academic, HttpMethod.POST, "/api/v1/examiners/projects/" + projectId + "/documents", Map.of("kind", "SOURCE", "filename", "code.zip", "contentType", "application/zip", "contentBase64", Base64.getEncoder().encodeToString("not a zip".getBytes())));
        assertThat(fake.getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> assigned = it.call(academic, HttpMethod.POST, "/api/v1/examiners/assignments", Map.of("projectId", projectId, "examinerId", examinerId, "deadline", LocalDate.now().plusDays(21).toString()));
        assertThat(assigned.getStatusCode().value()).as(String.valueOf(assigned.getBody())).isEqualTo(200);
        String assignmentId = String.valueOf(path(assigned.getBody(), "id"));

        // the examiner sees the project and the document; the other examiner does not; the examiner cannot reach the desk
        ResponseEntity<Map> mine = it.get(examiner, "/api/v1/examiners/me/projects/" + assignmentId);
        assertThat(mine.getStatusCode().value()).as(String.valueOf(mine.getBody())).isEqualTo(200);
        assertThat(((List<Map>) path(mine.getBody(), "documents"))).extracting(d -> d.get("id")).contains(docId);
        assertThat(it.get(otherExaminer, "/api/v1/examiners/me/projects/" + assignmentId).getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(otherExaminer, "/api/v1/examiners/me/projects/" + assignmentId + "/documents/" + docId + "/content").getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(examiner, "/api/v1/examiners/list").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(examiner, "/api/v1/examiners/projects/" + projectId).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(TestTokens.token(student, List.of("student")), "/api/v1/examiners/list").getStatusCode().value()).isEqualTo(403);

        // a draft saved; a score over the maximum refused; submission refused while lines are unscored
        List<Map> lines = (List<Map>) path(mine.getBody(), "lines");
        assertThat(lines).isNotEmpty();
        String first = String.valueOf(lines.get(0).get("criterion_id"));
        ResponseEntity<Map> over = it.call(examiner, HttpMethod.PUT, "/api/v1/examiners/me/projects/" + assignmentId + "/assessment", Map.of("scores", List.of(Map.of("criterionId", first, "score", 999))));
        assertThat(over.getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> partial = it.call(examiner, HttpMethod.PUT, "/api/v1/examiners/me/projects/" + assignmentId + "/assessment", Map.of("scores", List.of(Map.of("criterionId", first, "score", 3, "comment", "Apt")), "generalComments", "Draft comments on a solid piece of work."));
        assertThat(partial.getStatusCode().value()).as(String.valueOf(partial.getBody())).isEqualTo(200);
        assertThat(it.call(examiner, HttpMethod.POST, "/api/v1/examiners/me/projects/" + assignmentId + "/assessment/submit", Map.of()).getStatusCode().value()).isEqualTo(422);
        assertThat(jdbc.sql("SELECT status FROM extexam.assignment WHERE id = :id::uuid").param("id", assignmentId).query(String.class).single()).isEqualTo("IN_REVIEW");

        // every line scored, a recommendation given, submitted; then read-only
        List<Map<String, Object>> full = lines.stream().map(l -> Map.<String, Object>of("criterionId", String.valueOf(l.get("criterion_id")), "score", ((Number) l.get("max_score")).doubleValue() / 2, "comment", "Half marks")).toList();
        ResponseEntity<Map> saved = it.call(examiner, HttpMethod.PUT, "/api/v1/examiners/me/projects/" + assignmentId + "/assessment", Map.of("scores", full, "generalComments", "Competent throughout, with a thin literature review.", "finalRecommendation", "PASS_WITH_CORRECTIONS", "corrections", "Widen the review."));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        ResponseEntity<Map> submitted = it.call(examiner, HttpMethod.POST, "/api/v1/examiners/me/projects/" + assignmentId + "/assessment/submit", Map.of());
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        Map a = (Map) path(submitted.getBody(), "assessment");
        assertThat(a.get("state")).isEqualTo("SUBMITTED");
        assertThat(((Number) a.get("percentage")).doubleValue()).isEqualTo(50.0);
        assertThat(it.call(examiner, HttpMethod.PUT, "/api/v1/examiners/me/projects/" + assignmentId + "/assessment", Map.of("generalComments", "Changed after submission")).getStatusCode().value()).isEqualTo(422);

        // the desk reads it in full, reopens on a reason (not without), the examiner resubmits, the desk locks
        ResponseEntity<Map> desk = it.get(academic, "/api/v1/examiners/assignments/" + assignmentId);
        assertThat(desk.getStatusCode().value()).isEqualTo(200);
        String assessmentId = String.valueOf(path(desk.getBody(), "assessment_id"));
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/examiners/assessments/" + assessmentId + "/reopen", Map.of("reason", "")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/examiners/assessments/" + assessmentId + "/reopen", Map.of("reason", "The defence marks want a second look")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(examiner, HttpMethod.POST, "/api/v1/examiners/me/projects/" + assignmentId + "/assessment/submit", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/examiners/assessments/" + assessmentId + "/lock", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(jdbc.sql("SELECT status FROM extexam.assignment WHERE id = :id::uuid").param("id", assignmentId).query(String.class).single()).isEqualTo("LOCKED");

        // the history holds the journey; the reports and the moderation feed count it
        List<Map> history = (List<Map>) path(it.get(academic, "/api/v1/examiners/assignments/" + assignmentId).getBody(), "history");
        assertThat(history).extracting(h -> h.get("action")).contains("PROJECT_ASSIGNED", "PROJECT_VIEWED", "ASSESSMENT_STARTED", "ASSESSMENT_SAVED", "ASSESSMENT_SUBMITTED", "ASSESSMENT_REOPENED", "ASSESSMENT_RESUBMITTED", "ASSESSMENT_LOCKED");
        ResponseEntity<Map> report = it.get(academic, "/api/v1/examiners/reports?kind=submitted&session=2091/2092");
        assertThat(report.getStatusCode().value()).isEqualTo(200);
        assertThat(((List<Map>) path(report.getBody(), "rows"))).extracting(r -> r.get("id")).contains(assignmentId);
        assertThat(it.getList(academic, "/api/v1/examiners/moderation?session=2091/2092").getStatusCode().value()).isEqualTo(200);
    }
}
