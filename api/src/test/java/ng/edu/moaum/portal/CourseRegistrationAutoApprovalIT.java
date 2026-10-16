package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * Course registration approved automatically (V491), end to end on the student's own door: with the session set to AUTO_APPROVAL
 * and the semester's fees paid, the student's submission is approved at once (no Head of Department) and the Head is refused; the
 * examination card's issue is counted; a second submission changes nothing; the reset keeps the registration on its record, leaves
 * the payments alone and lets the student register again, approved again; the window closed, no reset; the Head's approval
 * restored, a submission waits for the Head; set back to AUTO_APPROVAL, the waiting registration is approved, and one whose fees
 * are not paid is held for review with the reason. Each run files everything under its own session. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CourseRegistrationAutoApprovalIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");
    final String academic = ItSupport.token("academic");
    final String instrument = "BUR/IT/AUTO491";
    /** the run's own session: its fee lines apply to every student at the level, so they are taken away after the test */
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    /** the clearance scheme the test put in force and the fee lines it stated, taken away: a planned session with fees stated is
     *  the session a later test's student reads by default */
    @AfterEach
    void clean() {
        it.db(() -> {
            if (session != null) jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
            jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            return jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
        });
    }

    private ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    /** a student with an account of their own, signed in: the Registry's first password changed at once */
    private String signedIn(UUID student, String matric) {
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 4910")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 4910")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 4910", "next", "Own-Password-4910")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    private void payInFull(String token, String session) {
        Map<String, Object> ref = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 100000)).getBody();
        ResponseEntity<Map> ok = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "auto approval test"));
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
    }

    private ResponseEntity<Map> rule(String session, String mode) {
        return it.call(academic, HttpMethod.PUT, "/api/v1/registration/approval/rules",
                Map.of("session", session, "mode", mode, "allowStudentReset", true, "cardOnApproval", true, "reason", "Integration test: " + mode.toLowerCase()));
    }

    private Map<String, Object> registration(String token, String session) {
        return (Map<String, Object>) it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1").getBody().get("registration");
    }

    @Test
    void aRegistrationThatPassesTheRulesIsApprovedAtOnceResetAndRegisteredAgain() {
        int y = 2300 + new Random().nextInt(600);
        session = y + "/" + (y + 1);
        String sp = y + "/" + (y + 1);
        it.session(session, y);
        int n = 1000 + new Random().nextInt(8999);
        String yy = String.format("%02d", y % 100);  // two digits, as the admission and matric shapes ask
        String matric = "MOAUM/ITA/" + yy + "/" + n;
        UUID student = it.student("ZZAUTO" + n, "C00061", "MOAUM/ADM/" + yy + "/49" + n, matric, 100);
        UUID unpaid = it.student("ZZAUTOUNPAID" + n, "C00061", "MOAUM/ADM/" + yy + "/48" + n, "MOAUM/ITA/" + yy + "/9" + n, 100);
        String token = signedIn(student, matric);

        // the Bursar states the session's school fees and the scheme is in force; the student pays them in full
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + sp + "/schedule", Map.of("item", "School fees", "amount", 100000, "level", 100)).getStatusCode().value()).isEqualTo(200);
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           :i, 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).param("i", instrument).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = :i ON CONFLICT DO NOTHING").param("i", instrument).update();
            jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED' ELSE 'INSTALMENT_1' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = :i ON CONFLICT DO NOTHING
                    """).param("i", instrument).update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES ('ITA 101', 'Auto Course One', 12, 1, 100, :d, 'Core', 'LIVE'), ('ITA 102', 'Auto Course Two', 6, 1, 100, :d, 'Elective', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('ITA 101', 'C00061', 100, 'Core'), ('ITA 102', 'C00061', 100, 'Elective') ON CONFLICT DO NOTHING").update();
            return jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ITA 101', :s, 1), (gen_random_uuid(), 'ITA 102', :s, 1) ON CONFLICT (course_code, session, semester, stream) DO NOTHING")
                    .param("s", session).update();
        });
        payInFull(token, session);
        long payments = jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND confirmed_at IS NOT NULL").param("s", student).query(Long.class).single();

        // the Academic Office suspends the Head's approval for the session, with a reason; a student cannot
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/registration/approval/rules", Map.of("session", session, "mode", "AUTO_APPROVAL", "allowStudentReset", true,
                "cardOnApproval", true, "reason", "a student trying")).getStatusCode().value()).isEqualTo(403);
        assertThat(rule(session, "AUTO_APPROVAL").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(token, "/api/v1/registration/approval/rule?session=" + session + "&semester=1").getBody()).containsEntry("mode", "AUTO_APPROVAL");

        // TEST 1-3: the student registers and submits; approved at once, AUTO, no Head
        Map<String, Object> view = it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1").getBody();
        assertThat(view.get("approval")).isInstanceOf(Map.class);
        List<UUID> offerings = ((List<Map<String, Object>>) view.get("menu")).stream().filter(m -> String.valueOf(m.get("course_code")).startsWith("ITA "))
                .map(m -> UUID.fromString(String.valueOf(m.get("offering_id")))).toList();
        assertThat(offerings).hasSize(2);
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", offerings)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> submitted = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("result")).isEqualTo("approved");
        Map<String, Object> reg = registration(token, session);
        assertThat(reg).containsEntry("status", "APPROVED").containsEntry("approval_mode", "AUTO");
        String regId = String.valueOf(reg.get("id"));
        // the Head of Department neither approves nor returns while approval is automatic
        String hod = it.officer("hod", "department", jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single());
        assertThat(it.call(hod, HttpMethod.POST, "/api/v1/registration/course-registrations/" + regId + "/return", Map.of("comment", "no")).getBody().get("code"))
                .isEqualTo("REG_AUTO_APPROVAL_ACTIVE");
        // TEST 24: a second submission changes nothing
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1)).getBody().get("result")).isEqualTo("already approved");
        // TEST 4-7: the examination card is the student's own and its issue is counted, once a semester
        assertThat(it.get(token, "/api/v1/me/check-code?kind=EXAM&session=" + session + "&semester=1").getStatusCode().value()).isEqualTo(200);
        it.get(token, "/api/v1/me/check-code?kind=EXAM&session=" + session + "&semester=1");
        assertThat(jdbc.sql("SELECT times FROM registration.exam_card_issue WHERE student_id = :s AND session = :ses AND semester = 1").param("s", student).param("ses", session)
                .query(Integer.class).single()).isEqualTo(2);
        assertThat(it.get(token, "/api/v1/me/docket").getBody().get("clearsExamination")).isEqualTo(true);

        // TEST 8-12, 29, 30: the reset — the registration kept on its record, the courses cleared, the payments left alone
        Map<String, Object> afterView = it.get(token, "/api/v1/me/registration?session=" + session + "&semester=1").getBody();
        assertThat((Map<String, Object>) afterView.get("reset")).containsEntry("allowed", true);
        ResponseEntity<Map> reset = it.call(token, HttpMethod.POST, "/api/v1/me/registration/reset", Map.of("session", session, "semester", 1));
        assertThat(reset.getStatusCode().value()).as(String.valueOf(reset.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) reset.getBody().get("result")).containsEntry("reset", true).containsEntry("courses", 2);
        Map<String, Object> cleared = registration(token, session);
        assertThat(cleared).containsEntry("status", "DRAFT");
        assertThat(cleared.get("entries") == null || ((List<?>) cleared.get("entries")).isEmpty()).isTrue();
        assertThat(jdbc.sql("SELECT previous_status || '/' || course_count || '/' || units || '/' || source FROM registration.registration_reset WHERE registration_id = CAST(:r AS uuid)")
                .param("r", regId).query(String.class).single()).isEqualTo("APPROVED/2/18/STUDENT_PORTAL");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND confirmed_at IS NOT NULL").param("s", student).query(Long.class).single())
                .isEqualTo(payments);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND template_key = 'REG_RESET'").param("s", student).query(Long.class).single()).isPositive();
        // TEST 22: a student resets only their own: the door takes no student or registration from the browser
        assertThat(it.call(signedIn(unpaid, "MOAUM/ITA/" + yy + "/9" + n), HttpMethod.POST, "/api/v1/me/registration/reset", Map.of("session", session, "semester", 1))
                .getBody().get("code")).isEqualTo("REG_RESET_NOTHING");

        // TEST 13-15: registered again, approved again
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", offerings)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1)).getBody().get("result")).isEqualTo("approved");
        Map<String, Object> overview = it.get(academic, "/api/v1/registration/approval/overview?session=" + session + "&semester=1").getBody();
        assertThat(((Number) overview.get("reregistered")).intValue()).isEqualTo(1);
        assertThat(((Number) overview.get("auto_approved")).intValue()).isEqualTo(1);

        // TEST 21: the window closed, no reset
        it.db(() -> jdbc.sql("SELECT policy.window_act('COURSE_REGISTRATION', :s, 1, 'CLOSE', NULL, NULL, NULL, NULL, 'integration test closes it', gen_random_uuid(), 'ict')")
                .param("s", session).query().listOfRows());
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/me/registration/reset", Map.of("session", session, "semester", 1)).getBody().get("code")).isEqualTo("COURSE_REGISTRATION_CLOSED");
        it.db(() -> jdbc.sql("SELECT policy.window_act('COURSE_REGISTRATION', :s, 1, 'REOPEN', NULL, NULL, NULL, NULL, 'integration test reopens it', gen_random_uuid(), 'ict')")
                .param("s", session).query().listOfRows());

        // TEST 31: the Head's approval restored: the next submission waits on the Head
        assertThat(rule(session, "HOD_APPROVAL_REQUIRED").getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/me/registration/reset", Map.of("session", session, "semester", 1)).getStatusCode().value()).isEqualTo(200);
        it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", offerings));
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1)).getBody().get("result")).isEqualTo("submitted");
        assertThat(registration(token, session)).containsEntry("status", "SUBMITTED");

        // TEST 26, 27: set back to automatic approval — the waiting registration that passes is approved; one whose fees are not
        // paid is held for review with the reason, never approved blindly
        it.db(() -> {
            UUID r = UUID.randomUUID();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at) VALUES (:id, :s, :ses, 1, 100, 'SUBMITTED', now())")
                    .param("id", r).param("s", unpaid).param("ses", session).update();
            return jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type) SELECT :id, o.id, 12, 'CURRENT' FROM catalogue.offering o WHERE o.course_code = 'ITA 101' AND o.session = :ses")
                    .param("id", r).param("ses", session).update();
        });
        Map<String, Object> processed = (Map<String, Object>) rule(session, "AUTO_APPROVAL").getBody().get("processed");
        assertThat(processed).containsEntry("considered", 2).containsEntry("approved", 1).containsEntry("review", 1);
        assertThat(registration(token, session)).containsEntry("status", "APPROVED").containsEntry("approval_mode", "AUTO");
        Map<String, Object> review = it.get(academic, "/api/v1/registration/approval/overview/list?session=" + session + "&kind=REVIEW").getBody();
        List<Map<String, Object>> held = (List<Map<String, Object>>) review.get("rows");
        assertThat(held).hasSize(1);
        assertThat(String.valueOf(held.get(0).get("review_reason"))).containsAnyOf("not stated", "not fully paid");
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/registration/approval/registrations/" + held.get(0).get("registration_id") + "/revalidate", Map.of())
                .getBody()).containsEntry("approved", false);
    }
}
