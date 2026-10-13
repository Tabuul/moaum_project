package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * V440 through the API: before Post-UTME registration and admission status checking close, the applicants of the session who
 * have not yet submitted, or not yet checked, are reminded once per deadline and day; what the portal sent a student or a member
 * of staff is read by the offices, and a failed message is sent again to the address the record holds now.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class ApplicantDeadlinesIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String ict;
    String tag;
    String ses;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(900_000) + 100_000);
        ict = TestTokens.token(it.person("ZZAPD-ICT-" + tag, "ZZAPDICT"), List.of("ict"));
        ses = "2089/2090";
        it.session(ses, 2089);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        return String.valueOf(r.getBody().get("code"));
    }

    /** an applicant of the session with an account the engine can reach; submitted or not */
    private UUID applicant(String jamb, String surname, boolean submitted) {
        return it.db(() -> {
            UUID cand = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state)
                    VALUES (:id, :s, :j, :sn, 'Invented', (SELECT name FROM ref.programme WHERE code = 'C00061'), 'UTME', 100, 'PROPOSED')
                    """).param("id", cand).param("s", ses).param("j", jamb).param("sn", surname).update();
            UUID acct = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) VALUES (:id, :s, :c, :k, :e, :p, 'SET_ON_FIRST_LOGIN')")
                    .param("id", acct).param("s", ses).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.test").param("p", "0803" + jamb.substring(4, 11)).update();
            UUID app = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, submitted_at) VALUES (:id, :a, :c, :s, :no, CASE WHEN :sub THEN now() END)")
                    .param("id", app).param("a", acct).param("c", cand).param("s", ses).param("no", "APP/89/" + jamb.substring(6, 12)).param("sub", submitted).update();
            return app;
        });
    }

    private UUID window(String type, int daysAhead) {
        return it.db(() -> {
            jdbc.sql("UPDATE policy.portal_window SET superseded_at = now() WHERE window_type = :t AND session = :ses AND superseded_at IS NULL").param("t", type).param("ses", ses).update();
            return jdbc.sql("INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, created_office) VALUES (:t, :ses, NULL, now() - interval '1 day', "
                    + "(((now() AT TIME ZONE 'Africa/Lagos')::date + :d)::timestamp + interval '12 hours') AT TIME ZONE 'Africa/Lagos', 'ict') RETURNING id")
                    .param("t", type).param("ses", ses).param("d", daysAhead).query(UUID.class).single();
        });
    }

    private void drain() {
        for (int i = 0; i < 30; i++) {
            int ran = it.db(() -> jdbc.sql("SELECT count(*) FROM platform.run_notice_job(100000)").query(Integer.class).single());
            if (ran == 0) {
                return;
            }
        }
    }

    private int told(UUID application, UUID window, int days, String template) {
        return it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'application' AND about_id = :a AND template_key = :t AND event_key LIKE :k")
                .param("a", application).param("t", template).param("k", "window-closing:" + window + ":%:" + days).query(Integer.class).single());
    }

    @Test
    void applicantsNotYetDoneAreRemindedBeforeTheirWindowsClose() {
        int base = new Random().nextInt(80_000_000) + 10_000_000;
        UUID a = applicant("8089" + String.format("%08d", base) + "AD", "ZZAPDA" + tag, false);
        UUID b = applicant("8089" + String.format("%08d", base + 1) + "BD", "ZZAPDB" + tag, true);
        // Post-UTME registration closes in three days: A has not submitted, B has
        UUID reg = window("POST_UTME_REGISTRATION", 3);
        assertThat(it.db(() -> jdbc.sql("SELECT policy.applicant_window_done('POST_UTME_REGISTRATION', :s, :a)").param("s", ses).param("a", a).query(Boolean.class).single())).isFalse();
        assertThat(it.db(() -> jdbc.sql("SELECT policy.applicant_window_done('POST_UTME_REGISTRATION', :s, :a)").param("s", ses).param("a", b).query(Boolean.class).single())).isTrue();
        assertThat(((Number) body(it.call(ict, HttpMethod.POST, "/api/v1/notices/closing-reminders/run", Map.of())).get("queued")).intValue()).isGreaterThanOrEqualTo(1);
        drain();
        assertThat(told(a, reg, 3, "WINDOW_CLOSING:POST_UTME_REGISTRATION")).isEqualTo(3);   // e-mail, SMS and the portal
        assertThat(told(b, reg, 3, "WINDOW_CLOSING:POST_UTME_REGISTRATION")).isEqualTo(0);
        String subject = it.db(() -> jdbc.sql("SELECT subject FROM platform.notice WHERE about_id = :a AND template_key = 'WINDOW_CLOSING:POST_UTME_REGISTRATION' AND channel = 'EMAIL'").param("a", a).query(String.class).single());
        assertThat(subject).contains("Post-UTME registration").contains("closes in 3 days");
        // admission status checking closes tomorrow: B submitted and never checked, A never submitted and so has nothing to check
        UUID check = window("ADMISSION_STATUS_CHECKING", 1);
        assertThat(((Number) body(it.call(ict, HttpMethod.POST, "/api/v1/notices/closing-reminders/run", Map.of())).get("queued")).intValue()).isGreaterThanOrEqualTo(1);
        drain();
        assertThat(told(b, check, 1, "WINDOW_CLOSING:ADMISSION_STATUS_CHECKING")).isEqualTo(3);
        assertThat(told(a, check, 1, "WINDOW_CLOSING:ADMISSION_STATUS_CHECKING")).isEqualTo(0);
        assertThat(it.db(() -> jdbc.sql("SELECT body FROM platform.notice WHERE about_id = :a AND template_key = 'WINDOW_CLOSING:ADMISSION_STATUS_CHECKING' AND channel = 'SMS'").param("a", b).query(String.class).single())).contains("closes tomorrow");
        // B checks: done; the same day again queues nothing more
        it.db(() -> jdbc.sql("INSERT INTO admissions.status_check (application_id, session, result) VALUES (:a, :s, 'NOT_YET')").param("a", b).param("s", ses).update());
        assertThat(it.db(() -> jdbc.sql("SELECT policy.applicant_window_done('ADMISSION_STATUS_CHECKING', :s, :a)").param("s", ses).param("a", b).query(Boolean.class).single())).isTrue();
        body(it.call(ict, HttpMethod.POST, "/api/v1/notices/closing-reminders/run", Map.of()));
        drain();
        assertThat(told(b, check, 1, "WINDOW_CLOSING:ADMISSION_STATUS_CHECKING")).isEqualTo(3);
    }

    @SuppressWarnings("unchecked")
    @Test
    void aPersonsMessagesAreReadAndOneIsSentAgainToTheAddressOnRecord() {
        UUID student = it.student("ITMSG" + tag, "C00023", "MOAUM/ADM/89/08" + tag.substring(0, 4), null, 100);
        UUID failed = it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', 'not an address', :s, 'body', 'student', :st)").param("s", "IT message " + tag).param("st", student).query(UUID.class).single());
        UUID portal = it.db(() -> jdbc.sql("SELECT platform.queue_notice('PORTAL', NULL, :s, 'body', 'student', :st, :k, NULL, NULL)").param("s", "IT portal " + tag).param("st", student).param("k", "it-msg:" + tag).query(UUID.class).single());
        // read by the offices that read the whole University; not by a Dean
        List<Map<String, Object>> messages = (List<Map<String, Object>>) (List<?>) it.getList(ict, "/api/v1/students/" + student + "/messages").getBody();
        assertThat(messages.stream().map(m -> String.valueOf(m.get("id")))).contains(failed.toString(), portal.toString());
        assertThat(messages.stream().filter(m -> failed.toString().equals(String.valueOf(m.get("id")))).findFirst().orElseThrow().get("state")).isEqualTo("FAILED");
        assertThat(it.get(ItSupport.token("dean"), "/api/v1/students/" + student + "/messages").getStatusCode().value()).isEqualTo(403);
        // the record's address corrected, the message is sent again to it; once; never a portal notice; never another student's
        it.db(() -> jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:s, '08031234567', :e) ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email")
                .param("s", student).param("e", "msg-" + tag + "@example.test").update());
        Map<String, Object> again = body(it.call(ict, HttpMethod.POST, "/api/v1/students/" + student + "/messages/" + failed + "/resend", Map.of()));
        UUID resent = UUID.fromString(String.valueOf(again.get("resent")));
        Map<String, Object> row = it.db(() -> jdbc.sql("SELECT state, recipient, resent_from FROM platform.notice WHERE id = :id").param("id", resent).query().singleRow());
        assertThat(row.get("state")).isEqualTo("QUEUED");
        assertThat(row.get("recipient")).isEqualTo("msg-" + tag + "@example.test");
        assertThat(row.get("resent_from")).isEqualTo(failed);
        assertThat(((List<Map<String, Object>>) again.get("messages")).stream().filter(m -> failed.toString().equals(String.valueOf(m.get("id")))).findFirst().orElseThrow().get("resent")).isEqualTo(true);
        assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/students/" + student + "/messages/" + failed + "/resend", Map.of()))).isEqualTo("NOTICE_RESEND_DONE");
        assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/students/" + student + "/messages/" + portal + "/resend", Map.of()))).isEqualTo("NOTICE_RESEND_CHANNEL");
        assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/students/" + student + "/messages/" + resent + "/resend", Map.of()))).isEqualTo("NOTICE_RESEND_STATE");
        UUID other = it.student("ITMSGO" + tag, "C00023", "MOAUM/ADM/89/09" + tag.substring(0, 4), null, 100);
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/students/" + other + "/messages/" + failed + "/resend", Map.of()).getStatusCode().value()).isEqualTo(404);
        // a member of staff: read by HR, sent again to the e-mail the person holds
        UUID person = it.person("ZZAPD-STAFF-" + tag, "ZZAPDSTAFF");
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", "staff-msg-" + tag + "@example.test").param("p", person).update());
        UUID staffFailed = it.db(() -> jdbc.sql("SELECT platform.queue_notice('EMAIL', 'nope', :s, 'body', 'person', :p)").param("s", "IT staff message " + tag).param("p", person).query(UUID.class).single());
        String hrm = ItSupport.token("hrm");
        assertThat(((List<Map<String, Object>>) (List<?>) it.getList(hrm, "/api/v1/hr/staff/" + person + "/messages").getBody()).stream().map(m -> String.valueOf(m.get("id")))).contains(staffFailed.toString());
        Map<String, Object> staffAgain = body(it.call(hrm, HttpMethod.POST, "/api/v1/hr/staff/" + person + "/messages/" + staffFailed + "/resend", Map.of()));
        assertThat(it.db(() -> jdbc.sql("SELECT recipient FROM platform.notice WHERE id = :id").param("id", UUID.fromString(String.valueOf(staffAgain.get("resent")))).query(String.class).single()))
                .isEqualTo("staff-msg-" + tag + "@example.test");
    }
}
