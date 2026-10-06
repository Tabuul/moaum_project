package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
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
 * The postgraduate lifecycle completed (V337): a department sees, decides and returns its own paid applications only — on the
 * list, the record, the documents, the dashboards, the register and the coursework desk; the School's word is final on every
 * recommendation and it may return one to the department; a valid applicant checks their status in the School's own window,
 * paying once; an accepted applicant is screened and only a cleared one reaches the register; and Matriculation Management
 * counts an endorsed postgraduate registration. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgLifecycleCompleteIT {

    static final String PG_CHECKING = "POSTGRADUATE_ADMISSION_STATUS_CHECKING";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String secretary = ItSupport.token("pgsecretary");
    String ict = ItSupport.token("ict");
    String school;
    String academic;
    String session;
    String progX;
    String deptX;
    String progY;
    String deptY;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        school = TestTokens.token(it.person("ZZPG-DEAN", "ZZPGDEAN"), List.of("pgschool"));
        academic = TestTokens.token(it.person("ZZPG-ACAD", "ZZPGACADEMIC"), List.of("academic"));
        session = jdbc.sql("SELECT admissions.pg_current_session()").query(String.class).single();
        it.session(session, Integer.parseInt(session.substring(0, 4)));
        // two postgraduate programmes of two departments
        List<Map<String, Object>> two = jdbc.sql("""
                SELECT DISTINCT ON (dept_code) code, dept_code FROM ref.programme
                 WHERE category = 'POST GRADUATE' AND NOT archived AND dept_code IS NOT NULL
                 ORDER BY dept_code, code LIMIT 2
                """).query().listOfRows();
        progX = String.valueOf(two.get(0).get("code"));
        deptX = String.valueOf(two.get(0).get("dept_code"));
        progY = String.valueOf(two.get(1).get("code"));
        deptY = String.valueOf(two.get(1).get("dept_code"));
        clean();
    }

    @AfterEach
    void tearDown() {
        clean();
    }

    /** the test's own window and screening policy, so the session is as every other test expects it: checking open, no screening */
    private void clean() {
        it.db(() -> {
            jdbc.sql("DELETE FROM policy.portal_window_event WHERE window_type = :t AND session = :s").param("t", PG_CHECKING).param("s", session).update();
            jdbc.sql("DELETE FROM policy.portal_window WHERE window_type = :t AND session = :s").param("t", PG_CHECKING).param("s", session).update();
            jdbc.sql("DELETE FROM admissions.pg_screening_policy WHERE session = :s").param("s", session).update();
            return null;
        });
    }

    record Applied(UUID id, String token, String reference) {
    }

    /** an application to a programme, its fee confirmed when asked, and the applicant signed in */
    private Applied apply(String programme, boolean pay) {
        String email = "zzpgc." + UUID.randomUUID().toString().substring(0, 8) + "@example.com";
        Map<String, Object> form = new LinkedHashMap<>();
        form.put("surname", "ZZPGCOMPLETE");
        form.put("otherNames", "Lifecycle");
        form.put("email", email);
        form.put("password", "Candidate2026!");
        form.put("programme", programme);
        form.put("nationality", "Nigerian");
        form.put("contactAddress", "No. 1 Test Road, Makurdi");
        ResponseEntity<Map> applied = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form);
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        UUID app = UUID.fromString(String.valueOf(applied.getBody().get("application_id")));
        String ref = String.valueOf(applied.getBody().get("reference"));
        if (pay) {
            confirm(app, ref);
        }
        ResponseEntity<Map> signedIn = it.anon(HttpMethod.POST, "/api/v1/pg/sign-in", Map.of("identifier", email, "password", "Candidate2026!"));
        assertThat(signedIn.getStatusCode().value()).as(String.valueOf(signedIn.getBody())).isEqualTo(200);
        return new Applied(app, String.valueOf(signedIn.getBody().get("token")), ref);
    }

    private void confirm(UUID app, Object reference) {
        ResponseEntity<Map> paid = it.call(secretary, HttpMethod.POST, "/api/v1/pg/applications/" + app + "/confirm-fee", Map.of("reference", reference));
        assertThat(paid.getStatusCode().value()).as(String.valueOf(paid.getBody())).isEqualTo(200);
    }

    private void pay(Applied a, String kind) {
        ResponseEntity<Map> ref = it.call(a.token(), HttpMethod.POST, "/api/v1/pg/fee-reference?kind=" + kind, null);
        assertThat(ref.getStatusCode().value()).as(kind + ": " + ref.getBody()).isEqualTo(200);
        confirm(a.id(), ref.getBody().get("reference"));
    }

    private static String state(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return String.valueOf(((Map<String, Object>) r.getBody().get("application")).get("state"));
    }

    private ResponseEntity<Map> post(String token, String path, Object body) {
        return it.call(token, HttpMethod.POST, path, body);
    }

    private static List<String> numbers(ResponseEntity<Map> list, String key) {
        return ((List<Map<String, Object>>) list.getBody().get(key)).stream().map(r -> String.valueOf(r.get("application_no"))).toList();
    }

    private String numberOf(UUID app) {
        return jdbc.sql("SELECT application_no FROM admissions.pg_application WHERE id = :a").param("a", app).query(String.class).single();
    }

    /** a recommended application on the School's desk */
    private void toTheSchool(UUID app) {
        assertThat(state(post(academic, "/api/v1/pg/applications/" + app + "/dept-decision", Map.of("recommend", true)))).isEqualTo("DEPT_RECOMMENDED");
        assertThat(state(post(academic, "/api/v1/pg/applications/" + app + "/faculty-decision", Map.of("recommend", true)))).isEqualTo("FAC_RECOMMENDED");
    }

    @Test
    void aDepartmentSeesAndDecidesItsOwnPaidApplicationsOnly() {
        Applied mine = apply(progX, true);
        Applied unpaid = apply(progX, false);
        Applied theirs = apply(progY, true);
        String hod = it.officer("hod", "department", deptX);

        // the list: its own department's paid applications
        ResponseEntity<Map> list = it.get(hod, "/api/v1/pg/applications?session=" + session);
        assertThat(list.getStatusCode().value()).isEqualTo(200);
        assertThat(numbers(list, "rows")).contains(numberOf(mine.id())).doesNotContain(numberOf(theirs.id()), numberOf(unpaid.id()));
        // the record, its documents and its decision: another department's refused, an id typed in or not
        assertThat(it.get(hod, "/api/v1/pg/applications/" + theirs.id()).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(hod, "/api/v1/pg/applications/" + theirs.id() + "/documents.pdf").getStatusCode().value()).isEqualTo(403);
        assertThat(post(hod, "/api/v1/pg/applications/" + theirs.id() + "/dept-decision", Map.of("recommend", true)).getStatusCode().value()).isEqualTo(403);
        assertThat(post(hod, "/api/v1/pg/applications/" + theirs.id() + "/return", Map.of("note", "Not yours")).getStatusCode().value()).isEqualTo(403);
        // an unpaid application is not the department's to decide
        ResponseEntity<Map> early = post(hod, "/api/v1/pg/applications/" + unpaid.id() + "/dept-decision", Map.of("recommend", true));
        assertThat(early.getStatusCode().value()).isEqualTo(422);
        assertThat(early.getBody().get("code")).isEqualTo("PG_FEE_UNCONFIRMED");
        // the School's home reached by the department shows its own; the Secretary's home is not the department's at all
        ResponseEntity<Map> home = it.get(hod, "/api/v1/pg/dashboard?session=" + session);
        assertThat(home.getStatusCode().value()).isEqualTo(200);
        assertThat(numbers(home, "recent")).doesNotContain(numberOf(theirs.id()), numberOf(unpaid.id()));
        assertThat(it.get(hod, "/api/v1/pg/secretary/dashboard?session=" + session).getStatusCode().value()).isEqualTo(403);
        // the register of postgraduate students: its own department's only
        ResponseEntity<Map> register = it.get(hod, "/api/v1/pg/students");
        String deptName = jdbc.sql("SELECT name FROM ref.department WHERE code = :d").param("d", deptX).query(String.class).single();
        assertThat(((List<Map<String, Object>>) register.getBody().get("rows"))).allSatisfy(r -> assertThat(r.get("department_name")).isEqualTo(deptName));
        // the coursework desk: another department's programme refused, the registrations its own
        // the refusal is a problem document (a map), the answer a list
        assertThat(it.get(hod, "/api/v1/pg/coursework/courses?programme=" + progY).getStatusCode().value()).isEqualTo(403);
        assertThat(it.callList(hod, HttpMethod.GET, "/api/v1/pg/coursework/courses?programme=" + progX, null).getStatusCode().value()).isEqualTo(200);
        // the department's own: decided
        assertThat(state(post(hod, "/api/v1/pg/applications/" + mine.id() + "/dept-decision", Map.of("recommend", true, "note", "Strong")))).isEqualTo("DEPT_RECOMMENDED");
        // the School reads them all
        assertThat(numbers(it.get(school, "/api/v1/pg/applications?session=" + session), "rows")).contains(numberOf(theirs.id()), numberOf(unpaid.id()));
    }

    @Test
    void correctionGoesBackAndTheSchoolHasTheFinalWord() {
        Applied a = apply(progX, true);
        String path = "/api/v1/pg/applications/" + a.id();
        // a return says what to correct; the applicant reads it, corrects and resubmits
        ResponseEntity<Map> blank = post(academic, path + "/return", Map.of("note", " "));
        assertThat(blank.getStatusCode().value()).isIn(400, 422);
        assertThat(state(post(academic, path + "/return", Map.of("note", "Upload your NYSC certificate")))).isEqualTo("RETURNED");
        Map me = it.get(a.token(), "/api/v1/pg/me").getBody();
        assertThat(me.get("state")).isEqualTo("RETURNED");
        assertThat(((Map) me.get("returned")).get("note")).isEqualTo("Upload your NYSC certificate");
        assertThat(post(a.token(), "/api/v1/pg/first-degree", Map.of("institution", "Benue State University", "award", "B.Sc.")).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> again = post(a.token(), "/api/v1/pg/resubmit", null);
        assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(200);
        assertThat(again.getBody().get("state")).isEqualTo("SUBMITTED");

        // the department does not recommend: the applicant reads "under review", the record is locked, the department cannot change it
        assertThat(state(post(academic, path + "/dept-decision", Map.of("recommend", false, "note", "Weak class of degree")))).isEqualTo("DEPT_DECLINED");
        me = it.get(a.token(), "/api/v1/pg/me").getBody();
        assertThat(me.get("state")).isEqualTo("UNDER_REVIEW");
        assertThat(me.get("deptNote")).isNull();
        assertThat(String.valueOf(me.get("history"))).doesNotContain("DEPT_DECLINED", "Weak class of degree");
        ResponseEntity<Map> locked = post(a.token(), "/api/v1/pg/first-degree", Map.of("institution", "Another"));
        assertThat(locked.getStatusCode().value()).isEqualTo(422);
        assertThat(locked.getBody().get("code")).isEqualTo("PG_RECORD_LOCKED");
        ResponseEntity<Map> twice = post(academic, path + "/dept-decision", Map.of("recommend", true));
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody().get("code")).isEqualTo("PG_NOT_WITH_DEPARTMENT");

        // the School returns the recommendation to the department, which decides again; the trail keeps both
        assertThat(post(academic, path + "/return-to-department", Map.of("note", "Reconsider")).getStatusCode().value()).isEqualTo(403);
        assertThat(state(post(school, path + "/return-to-department", Map.of("note", "Reconsider the HND")))).isEqualTo("SUBMITTED");
        assertThat(state(post(academic, path + "/dept-decision", Map.of("recommend", false)))).isEqualTo("DEPT_DECLINED");
        // a department's "not recommended" reaches the School, whose decision is final
        assertThat(post(academic, path + "/spgs-decision", Map.of("offer", false)).getStatusCode().value()).isEqualTo(403);
        assertThat(state(post(school, path + "/spgs-decision", Map.of("offer", false, "note", "Not offered this session")))).isEqualTo("NOT_OFFERED");
        List<String> kinds = jdbc.sql("SELECT kind FROM admissions.pg_application_event WHERE application_id = :a ORDER BY at").param("a", a.id()).query(String.class).list();
        assertThat(kinds).contains("RETURNED", "RESUBMITTED", "DEPT_DECLINED", "RETURNED_TO_DEPARTMENT", "NOT_OFFERED");
    }

    @Test
    void everyValidApplicantChecksInTheSchoolsWindowPayingOnce() {
        Applied pending = apply(progX, true);
        Applied unpaid = apply(progX, false);
        // valid, undecided, the window open by default: pays once and reads PENDING, again and again
        assertThat(post(unpaid.token(), "/api/v1/pg/fee-reference?kind=CHECKING", null).getStatusCode().value()).isEqualTo(422);
        pay(pending, "CHECKING");
        Map chk = (Map) it.get(pending.token(), "/api/v1/pg/me").getBody().get("statusChecking");
        assertThat(chk.get("status")).isEqualTo("PENDING");
        assertThat(it.get(pending.token(), "/api/v1/pg/me").getBody().get("statusChecking")).isEqualTo(chk);
        ResponseEntity<Map> second = post(pending.token(), "/api/v1/pg/fee-reference?kind=CHECKING", null);
        assertThat(second.getStatusCode().value()).isEqualTo(422);
        assertThat(second.getBody().get("code")).isEqualTo("PG_FEE_PAID");

        // the Director of ICT closes checking: no new checking fee, and nobody reads a status
        Applied late = apply(progX, true);
        ResponseEntity<Map> closed = post(ict, "/api/v1/portal-windows/" + PG_CHECKING, Map.of("session", session, "action", "CLOSE", "reason", "integration test: checking closed", "lateFeeEnabled", false));
        assertThat(closed.getStatusCode().value()).as(String.valueOf(closed.getBody())).isEqualTo(200);
        assertThat(((Map) closed.getBody().get("after")).get("state")).isEqualTo("CLOSED");
        ResponseEntity<Map> refused = post(late.token(), "/api/v1/pg/fee-reference?kind=CHECKING", null);
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("PG_CHECKING_CLOSED");
        assertThat(((Map) it.get(pending.token(), "/api/v1/pg/me").getBody().get("statusChecking")).get("status")).isNull();
        // a semester or a late period is not the checking window's
        assertThat(post(ict, "/api/v1/portal-windows/" + PG_CHECKING, Map.of("session", session, "semester", 1, "action", "REOPEN", "reason", "x", "lateFeeEnabled", false)).getStatusCode().value()).isEqualTo(422);
        // reopened: the paid applicant reads their status again at no cost
        assertThat(post(ict, "/api/v1/portal-windows/" + PG_CHECKING, Map.of("session", session, "action", "REOPEN", "reason", "integration test: reopened", "lateFeeEnabled", false)).getStatusCode().value()).isEqualTo(200);
        assertThat(((Map) it.get(pending.token(), "/api/v1/pg/me").getBody().get("statusChecking")).get("status")).isEqualTo("PENDING");
        // the ICT page lists the window beside the postgraduate application
        List<Map<String, Object>> windows = (List<Map<String, Object>>) it.get(ict, "/api/v1/portal-windows/applications?session=" + session).getBody().get("windows");
        assertThat(windows).extracting(w -> w.get("type")).contains(PG_CHECKING);
    }

    @Test
    void screeningClearsTheAcceptedApplicantOntoTheRegister() {
        // the School screens the session's accepted applicants, at a venue, from a day
        ResponseEntity<Map> policy = it.call(school, HttpMethod.PUT, "/api/v1/pg/sessions/" + session + "/screening-policy",
                Map.of("required", true, "venue", "PG School Hall", "startsOn", session.substring(0, 4) + "-11-02", "instructions", "Come with originals.",
                        "requiredDocuments", List.of("First degree certificate", "NYSC certificate")));
        assertThat(policy.getStatusCode().value()).as(String.valueOf(policy.getBody())).isEqualTo(200);
        assertThat(((Map) policy.getBody().get("policy")).get("required_documents")).isEqualTo(List.of("First degree certificate", "NYSC certificate"));

        Applied a = apply(progX, true);
        String path = "/api/v1/pg/applications/" + a.id();
        toTheSchool(a.id());
        assertThat(state(post(school, path + "/spgs-decision", Map.of("offer", true)))).isEqualTo("OFFERED");
        pay(a, "CHECKING");
        pay(a, "ACCEPTANCE");
        // accepted: screening opened, the applicant told where and what to bring; not yet on the register
        Map scr = (Map) it.get(a.token(), "/api/v1/pg/me").getBody().get("screening");
        assertThat(scr.get("required")).isEqualTo(true);
        assertThat(((Map) scr.get("record")).get("state")).isEqualTo("PENDING");
        assertThat(((Map) scr.get("policy")).get("venue")).isEqualTo("PG School Hall");
        ResponseEntity<Map> early = post(school, path + "/admit", null);
        assertThat(early.getStatusCode().value()).isEqualTo(422);
        assertThat(early.getBody().get("code")).isEqualTo("PG_SCREENING_NOT_CLEARED");
        // a department never screens
        String hod = it.officer("hod", "department", deptX);
        assertThat(post(hod, path + "/screening/decision", Map.of("decision", "CLEARED")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(hod, "/api/v1/pg/screening?session=" + session).getStatusCode().value()).isEqualTo(403);

        // scheduled, then a correction with its reason the applicant reads
        ResponseEntity<Map> sched = post(secretary, path + "/screening/schedule", Map.of("venue", "Room 4, PG School", "at", session.substring(0, 4) + "-11-03T09:00:00+01:00"));
        assertThat(sched.getStatusCode().value()).as(String.valueOf(sched.getBody())).isEqualTo(200);
        assertThat(((Map) sched.getBody().get("screening")).get("state")).isEqualTo("SCHEDULED");
        ResponseEntity<Map> noReason = post(secretary, path + "/screening/decision", Map.of("decision", "NOT_CLEARED"));
        assertThat(noReason.getStatusCode().value()).isEqualTo(422);
        assertThat(noReason.getBody().get("code")).isEqualTo("PG_SCREENING_REASON");
        ResponseEntity<Map> fix = post(secretary, path + "/screening/decision",
                Map.of("decision", "CORRECTION_REQUIRED", "reason", "Bring the original NYSC certificate", "missingDocuments", List.of("NYSC certificate")));
        assertThat(fix.getStatusCode().value()).as(String.valueOf(fix.getBody())).isEqualTo(200);
        Map rec = (Map) ((Map) it.get(a.token(), "/api/v1/pg/me").getBody().get("screening")).get("record");
        assertThat(rec.get("state")).isEqualTo("CORRECTION_REQUIRED");
        assertThat(rec.get("reason")).isEqualTo("Bring the original NYSC certificate");
        assertThat(rec.get("missing_documents")).isEqualTo(List.of("NYSC certificate"));
        // the applicant may bring the missing document in while screening is under way
        assertThat(post(a.token(), "/api/v1/pg/documents", Map.of("kind", "NYSC", "filename", "nysc.pdf", "contentType", "application/pdf",
                "base64", java.util.Base64.getEncoder().encodeToString("%PDF-1.4\n%%EOF\n".getBytes()))).getStatusCode().value()).isEqualTo(200);

        // cleared: on the register at once, the student account open; the decision is not taken twice
        ResponseEntity<Map> cleared = post(secretary, path + "/screening/decision",
                Map.of("decision", "CLEARED", "verifiedDocuments", List.of("First degree certificate", "NYSC certificate"), "remarks", "All originals seen"));
        assertThat(state(cleared)).isEqualTo("ADMITTED");
        assertThat(cleared.getBody().get("student")).isNotNull();
        assertThat(post(secretary, path + "/screening/decision", Map.of("decision", "NOT_CLEARED", "reason", "x")).getBody().get("code")).isEqualTo("PG_SCREENING_DECIDED");
        Map me = it.get(a.token(), "/api/v1/pg/me").getBody();
        assertThat(me.get("state")).isEqualTo("ADMITTED");
        assertThat(me.get("student")).isNotNull();
        UUID student = jdbc.sql("SELECT student_id FROM admissions.pg_application WHERE id = :a").param("a", a.id()).query(UUID.class).single();
        assertThat(jdbc.sql("SELECT address FROM people.student_contact WHERE student_id = :s").param("s", student).query(String.class).single()).isEqualTo("No. 1 Test Road, Makurdi");
        assertThat(jdbc.sql("SELECT admissions.screening_ok_student(:s)").param("s", student).query(Boolean.class).single()).isTrue();
        // the screening desk lists the applicant as cleared
        Map desk = it.get(secretary, "/api/v1/pg/screening?session=" + session).getBody();
        assertThat(((List<Map<String, Object>>) desk.get("rows")).stream().filter(r -> a.id().toString().equals(String.valueOf(r.get("id")))).findFirst().orElseThrow().get("screening_state")).isEqualTo("CLEARED");
        List<String> kinds = jdbc.sql("SELECT kind FROM admissions.pg_application_event WHERE application_id = :a ORDER BY at").param("a", a.id()).query(String.class).list();
        assertThat(kinds).contains("SCREENING_PENDING", "SCREENING_SCHEDULED", "SCREENING_CORRECTION_REQUIRED", "SCREENING_CLEARED", "ADMITTED");

        // Matriculation Management counts the postgraduate's endorsed registration of the session
        String faculty = jdbc.sql("SELECT faculty_code FROM ref.programme WHERE code = :p").param("p", progX).query(String.class).single();
        it.db(() -> jdbc.sql("""
                INSERT INTO admissions.pg_registration (student_id, session, semester, mode, state, endorsed_at)
                VALUES (:s, :sess, 1, 'FULL_TIME', 'ENDORSED', now())
                """).param("s", student).param("sess", session).update());
        Boolean registered = jdbc.sql("SELECT registered FROM people.matric_candidates(:s, :f) WHERE student_id = :st")
                .param("s", session).param("f", faculty).param("st", student).query(Boolean.class).optional().orElse(null);
        assertThat(registered).as("the student is a matriculation candidate of the faculty, registered").isTrue();
    }
}
