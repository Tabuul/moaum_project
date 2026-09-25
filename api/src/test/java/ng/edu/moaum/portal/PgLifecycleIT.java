package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The postgraduate lifecycle end to end, one connected record (V255): an applicant applies and pays, the
 * department, the faculty and the School decide, the applicant pays the checking and acceptance fees in their
 * turn, the School admits — and the same password opens the student portal on the admission number. The
 * student's research runs supervisor → proposal → seminar → title → panel → draft → viva → corrections →
 * final → clearance → Board → Senate, each stage in order and each document kept by version, and the award
 * ends on the register: a graduand row and the status GRADUATED. The application's trail and the notices
 * are checked along the way. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgLifecycleIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String secretary = ItSupport.token("pgsecretary");
    String school;
    String academic;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        // the desks that decide are people on the register: each decision names who took it
        school = TestTokens.token(it.person("ZZPG-DEAN", "ZZPGDEAN"), List.of("pgschool"));
        academic = TestTokens.token(it.person("ZZPG-ACAD", "ZZPGACADEMIC"), List.of("academic"));
    }

    @Test
    void fromApplicationToAward() {
        String email = "zzpg." + UUID.randomUUID().toString().substring(0, 8) + "@example.com";
        String password = "Candidate2026!";
        String programme = jdbc.sql("SELECT code FROM ref.programme WHERE category = 'POST GRADUATE' AND NOT archived AND pg_research ORDER BY code LIMIT 1")
                .query(String.class).single();

        // ── the applicant applies: the application is numbered and the fee reference minted ──
        Map<String, Object> form = new java.util.LinkedHashMap<>();
        form.put("surname", "ZZPGCANDIDATE"); form.put("otherNames", "Lifecycle"); form.put("sex", "F"); form.put("dob", "1995-04-12");
        form.put("state", "Benue"); form.put("lga", "Makurdi"); form.put("email", email); form.put("phone", "08012345678");
        form.put("password", password); form.put("programme", programme);
        form.put("priorInstitution", "Benue State University"); form.put("priorAward", "B.Sc. Computer Science"); form.put("priorClass", "Second Class Upper");
        form.put("priorCgpa", "4.10"); form.put("priorYear", "2019");
        form.put("proposalTitle", "A study for the lifecycle test"); form.put("proposalText", "Enough words to be a proposal.");
        form.put("referees", List.of(Map.of("name", "Prof. Referee One", "institution", "BSU", "position", "Professor")));
        ResponseEntity<Map> applied = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form);
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        UUID app = UUID.fromString(String.valueOf(applied.getBody().get("application_id")));
        String appRef = String.valueOf(applied.getBody().get("reference"));

        // the trail begins at once, and the applicant is told
        assertThat(events(app)).contains("CREATED", "SUBMITTED");
        assertThat(notices(app)).isGreaterThanOrEqualTo(1);

        // ── the application fee, confirmed by the Secretary against this application (another's reference is refused) ──
        assertThat(it.call(secretary, HttpMethod.POST, "/api/v1/pg/applications/" + UUID.randomUUID() + "/confirm-fee", Map.of("reference", appRef)).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> paid = it.call(secretary, HttpMethod.POST, "/api/v1/pg/applications/" + app + "/confirm-fee", Map.of("reference", appRef));
        assertThat(paid.getStatusCode().value()).as(String.valueOf(paid.getBody())).isEqualTo(200);
        assertThat(events(app)).contains("APPLICATION_FEE_CONFIRMED");

        // ── the applicant signs in on the email and sees the history; the acceptance fee is not yet theirs to pay ──
        ResponseEntity<Map> signedIn = it.anon(HttpMethod.POST, "/api/v1/pg/sign-in", Map.of("identifier", email, "password", password));
        assertThat(signedIn.getStatusCode().value()).as(String.valueOf(signedIn.getBody())).isEqualTo(200);
        String applicant = String.valueOf(signedIn.getBody().get("token"));
        ResponseEntity<Map> me = it.get(applicant, "/api/v1/pg/me");
        assertThat(me.getStatusCode().value()).isEqualTo(200);
        assertThat((List<?>) me.getBody().get("history")).hasSizeGreaterThanOrEqualTo(3);
        assertThat(it.call(applicant, HttpMethod.POST, "/api/v1/pg/fee-reference?kind=ACCEPTANCE", null).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(applicant, HttpMethod.POST, "/api/v1/pg/fee-reference?kind=CHECKING", null).getStatusCode().value()).isEqualTo(422);

        // ── a Head of Department with no department of their own reaches nothing; the desks decide in order ──
        assertThat(it.get(ItSupport.token("hod"), "/api/v1/pg/applications/" + app).getStatusCode().value()).isEqualTo(403);
        assertThat(state(it.call(academic, HttpMethod.POST, "/api/v1/pg/applications/" + app + "/dept-decision", Map.of("recommend", true, "note", "Strong first degree")))).isEqualTo("DEPT_RECOMMENDED");
        assertThat(state(it.call(academic, HttpMethod.POST, "/api/v1/pg/applications/" + app + "/faculty-decision", Map.of("recommend", true)))).isEqualTo("FAC_RECOMMENDED");
        assertThat(state(it.call(school, HttpMethod.POST, "/api/v1/pg/applications/" + app + "/spgs-decision", Map.of("offer", true, "note", "Offered")))).isEqualTo("OFFERED");

        // the decision is sealed until the checking fee; the department's words are sealed with it
        me = it.get(applicant, "/api/v1/pg/me");
        assertThat(me.getBody().get("state")).isEqualTo("DECISION_LOCKED");
        assertThat(me.getBody().get("deptNote")).isNull();

        // ── the checking fee, then the acceptance fee, each in its turn; paying acceptance accepts the offer ──
        ResponseEntity<Map> chk = it.call(applicant, HttpMethod.POST, "/api/v1/pg/fee-reference?kind=CHECKING", null);
        assertThat(chk.getStatusCode().value()).as(String.valueOf(chk.getBody())).isEqualTo(200);
        assertThat(it.call(secretary, HttpMethod.POST, "/api/v1/pg/applications/" + app + "/confirm-fee", Map.of("reference", chk.getBody().get("reference"))).getStatusCode().value()).isEqualTo(200);
        me = it.get(applicant, "/api/v1/pg/me");
        assertThat(me.getBody().get("state")).isEqualTo("OFFERED");
        assertThat(me.getBody().get("deptNote")).isEqualTo("Strong first degree");
        ResponseEntity<Map> acc = it.call(applicant, HttpMethod.POST, "/api/v1/pg/fee-reference?kind=ACCEPTANCE", null);
        assertThat(acc.getStatusCode().value()).as(String.valueOf(acc.getBody())).isEqualTo(200);
        assertThat(state(it.call(secretary, HttpMethod.POST, "/api/v1/pg/applications/" + app + "/confirm-fee", Map.of("reference", acc.getBody().get("reference"))))).isEqualTo("ACCEPTED");
        assertThat(events(app)).contains("CHECKING_FEE_CONFIRMED", "ACCEPTANCE_FEE_CONFIRMED", "ACCEPTED");

        // ── the School admits: the applicant becomes a student, and the same password opens the student portal ──
        ResponseEntity<Map> admitted = it.call(school, HttpMethod.POST, "/api/v1/pg/applications/" + app + "/admit", null);
        assertThat(admitted.getStatusCode().value()).as(String.valueOf(admitted.getBody())).isEqualTo(200);
        UUID student = UUID.fromString(String.valueOf(admitted.getBody().get("studentId")));
        assertThat(events(app)).contains("ADMITTED");
        me = it.get(applicant, "/api/v1/pg/me");
        Map<String, Object> asStudent = (Map<String, Object>) me.getBody().get("student");
        assertThat(asStudent).isNotNull();
        String admissionNo = String.valueOf(asStudent.get("admission_no"));
        ResponseEntity<Map> door = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", admissionNo, "password", password));
        assertThat(door.getStatusCode().value()).as(String.valueOf(door.getBody())).isEqualTo(200);
        assertThat(door.getBody().get("studentId")).isEqualTo(student.toString());
        assertThat(jdbc.sql("SELECT email FROM people.student_contact WHERE student_id = :s").param("s", student).query(String.class).single()).isEqualTo(email.toLowerCase());

        // ── the student's research, stage by stage, with each document kept by version ──
        String cand = TestTokens.token(student, List.of("student"));
        assertThat(it.get(cand, "/api/v1/pg/research/me").getBody().get("stage")).isEqualTo("REGISTERED");
        UUID research = UUID.fromString(String.valueOf(it.get(cand, "/api/v1/pg/research/me").getBody().get("id")));
        // a draft is not taken before the title is registered
        assertThat(it.call(cand, HttpMethod.POST, "/api/v1/pg/research/me/documents", doc("DRAFT", "draft.pdf")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(school, HttpMethod.POST, "/api/v1/pg/research/" + research + "/supervisor", Map.of("name", "Prof. ZZ Supervisor", "role", "FIRST", "external", false)).getBody().get("stage")).isEqualTo("SUPERVISED");
        ResponseEntity<Map> prop = it.call(cand, HttpMethod.POST, "/api/v1/pg/research/me/documents", doc("PROPOSAL", "proposal.pdf"));
        assertThat(prop.getStatusCode().value()).as(String.valueOf(prop.getBody())).isEqualTo(200);
        assertThat((List<?>) prop.getBody().get("documents")).hasSize(1);
        assertThat(it.call(cand, HttpMethod.POST, "/api/v1/pg/research/me/topic", Map.of("topic", "A topic for the lifecycle test")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(cand, HttpMethod.POST, "/api/v1/pg/research/me/proposal", null).getBody().get("stage")).isEqualTo("PROPOSAL_SUBMITTED");
        // the desk cannot skip a stage
        ResponseEntity<Map> skipped = it.call(school, HttpMethod.POST, "/api/v1/pg/research/" + research + "/action", Map.of("action", "SEMINAR"));
        assertThat(skipped.getStatusCode().value()).isEqualTo(422);
        assertThat(skipped.getBody().get("code")).isEqualTo("PG_STAGE_ORDER");
        assertThat(act(research, Map.of("action", "APPROVE_PROPOSAL"))).isEqualTo("PROPOSAL_APPROVED");
        assertThat(act(research, Map.of("action", "SEMINAR", "pgsr", "Dr. PGSR"))).isEqualTo("SEMINAR_HELD");
        assertThat(act(research, Map.of("action", "REGISTER_TITLE", "plagiarismPct", 82))).isEqualTo("TITLE_REGISTERED");
        assertThat(act(research, Map.of("action", "PANEL"))).isEqualTo("PANEL_CONSTITUTED");
        // the candidate's draft moves the record to draft submitted
        assertThat(it.call(cand, HttpMethod.POST, "/api/v1/pg/research/me/documents", doc("DRAFT", "draft.pdf")).getBody().get("stage")).isEqualTo("DRAFT_SUBMITTED");
        assertThat(act(research, Map.of("action", "VIVA", "vivaScore", 66, "vivaOutcome", "PASS_MINOR"))).isEqualTo("VIVA_HELD");
        assertThat(act(research, Map.of("action", "CORRECTIONS", "correctionsDue", "2026-12-31"))).isEqualTo("CORRECTIONS");
        assertThat(it.call(cand, HttpMethod.POST, "/api/v1/pg/research/me/documents", doc("CORRECTED", "corrected.pdf")).getBody().get("stage")).isEqualTo("CORRECTIONS");
        ResponseEntity<Map> fin = it.call(cand, HttpMethod.POST, "/api/v1/pg/research/me/documents", doc("FINAL", "final.pdf"));
        assertThat(fin.getBody().get("stage")).isEqualTo("FINAL_SUBMITTED");
        List<Map<String, Object>> docs = (List<Map<String, Object>>) fin.getBody().get("documents");
        assertThat(docs).hasSize(4);
        UUID finalDoc = UUID.fromString(String.valueOf(docs.get(0).get("id")));
        assertThat(it.call(school, HttpMethod.POST, "/api/v1/pg/research/" + research + "/documents/" + finalDoc + "/review", Map.of("status", "ACCEPTED")).getStatusCode().value()).isEqualTo(200);
        assertThat(act(research, Map.of("action", "CLEAR"))).isEqualTo("CLEARED");
        assertThat(act(research, Map.of("action", "RECOMMEND"))).isEqualTo("AWARD_RECOMMENDED");
        // an award needs the Senate minute and a matriculated student; recorded, it ends on the register
        assertThat(it.call(school, HttpMethod.POST, "/api/v1/pg/research/" + research + "/action", Map.of("action", "AWARD")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(school, HttpMethod.POST, "/api/v1/pg/research/" + research + "/action", Map.of("action", "AWARD", "senateMinute", "SEN/TEST/EARLY")).getStatusCode().value()).isEqualTo(422);
        it.db(() -> jdbc.sql("UPDATE people.student SET matric_no = :m, status = 'ACTIVE', matriculated_at = now() WHERE id = :s")
                .param("m", "MOAUM/PGT/26/" + String.format("%04d", (int) (Math.random() * 9000) + 1000)).param("s", student).update());
        assertThat(act(research, Map.of("action", "AWARD", "senateMinute", "SEN/TEST/" + UUID.randomUUID().toString().substring(0, 4)))).isEqualTo("AWARDED");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo("GRADUATED");
        assertThat(jdbc.sql("SELECT senate_state FROM records.graduand WHERE student_id = :s").param("s", student).query(String.class).single()).isEqualTo("APPROVED");
        ResponseEntity<Map> summary = it.get(cand, "/api/v1/pg/coursework/summary");
        assertThat(summary.getBody().get("graduand")).isNotNull();
        assertThat(summary.getBody().get("status")).isEqualTo("GRADUATED");
        // the candidate was told at each turn of the research
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s").param("s", student).query(Long.class).single()).isGreaterThanOrEqualTo(8);

        // ── the School reads the whole trail on the application ──
        ResponseEntity<Map> detail = it.get(school, "/api/v1/pg/applications/" + app);
        List<Map<String, Object>> history = (List<Map<String, Object>>) detail.getBody().get("history");
        assertThat(history.stream().map(h -> String.valueOf(h.get("kind"))).toList()).contains("CREATED", "SUBMITTED", "APPLICATION_FEE_CONFIRMED", "DEPT_RECOMMENDED", "FAC_RECOMMENDED", "OFFERED", "CHECKING_FEE_CONFIRMED", "ACCEPTED", "ADMITTED");
    }

    private String act(UUID research, Map<String, Object> body) {
        ResponseEntity<Map> r = it.call(school, HttpMethod.POST, "/api/v1/pg/research/" + research + "/action", body);
        assertThat(r.getStatusCode().value()).as(body.get("action") + ": " + r.getBody()).isEqualTo(200);
        return String.valueOf(r.getBody().get("stage"));
    }

    private static String state(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return String.valueOf(((Map<String, Object>) r.getBody().get("application")).get("state"));
    }

    private static Map<String, Object> doc(String kind, String name) {
        byte[] pdf = "%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n".getBytes();
        return Map.of("kind", kind, "filename", name, "contentType", "application/pdf", "contentBase64", Base64.getEncoder().encodeToString(pdf), "note", "test");
    }

    private List<String> events(UUID app) {
        return jdbc.sql("SELECT kind FROM admissions.pg_application_event WHERE application_id = :a ORDER BY at").param("a", app).query(String.class).list();
    }

    private long notices(UUID app) {
        return jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'pg_application' AND about_id = :a").param("a", app).query(Long.class).single();
    }
}
