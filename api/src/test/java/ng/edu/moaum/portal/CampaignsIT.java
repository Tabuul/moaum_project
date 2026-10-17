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
 * V426 through the API: a campaign written by ICT reaches the students its filters name — previewed, tested, sent as a job,
 * reported; a Dean is held to their own faculty; a student's preference switches an optional SMS off; the offices read the
 * compliance picture, a Dean within their faculty.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class CampaignsIT {

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
        ict = TestTokens.token(it.person("ZZCMP-ICT-" + tag, "ZZCMPICT"), List.of("ict"));
        ses = "2087/2088";
        it.session(ses, 2087);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private UUID studentOfSession(String surname, String programme, String adm, String matric, String email, String phone) {
        UUID s = it.student(surname, programme, adm, matric, 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :s").param("ses", ses).param("s", s).update();
            jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:s, :p, :e) ON CONFLICT (student_id) DO UPDATE SET phone = EXCLUDED.phone, email = EXCLUDED.email")
                    .param("s", s).param("p", phone, java.sql.Types.VARCHAR).param("e", email, java.sql.Types.VARCHAR).update();
            return null;
        });
        return s;
    }

    private void drain() {
        for (int i = 0; i < 20; i++) {
            int ran = it.db(() -> jdbc.sql("SELECT count(*) FROM platform.run_notice_job(100000)").query(Integer.class).single());
            if (ran == 0) {
                return;
            }
        }
    }

    @SuppressWarnings("unchecked")
    @Test
    void aCampaignIsPreviewedTestedSentAsAJobAndReported() {
        int n = it.freeDraw(1000, 10000, k -> List.of("MOAUM/ADM/87/00" + k, "MOAUM/CMP/87/" + k, "MOAUM/ADM/87/01" + k, "ITCMPA" + k, "ITCMPB" + k));
        UUID a = studentOfSession("ITCMPA" + n, "C00023", "MOAUM/ADM/87/00" + n, "MOAUM/CMP/87/" + n, "cmp-a-" + n + "@example.test", "0800" + (1000000 + n));
        UUID b = studentOfSession("ITCMPB" + n, "C00023", "MOAUM/ADM/87/01" + n, null, null, "0800" + (2000000 + n));
        // the form's lists come with the campaigns
        Map<String, Object> page = body(it.get(ict, "/api/v1/notices/campaigns"));
        assertThat((List<?>) page.get("templates")).isNotEmpty();
        assertThat((List<?>) page.get("faculties")).isNotEmpty();
        // an announcement to the session's students, by e-mail, SMS and the portal
        Map<String, Object> created = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns", Map.of(
                "name", "IT resumption " + tag, "templateKey", "ANNOUNCEMENT", "students", true,
                "filters", Map.of("session", ses), "channels", List.of("EMAIL", "SMS", "PORTAL"),
                "vars", Map.of("TITLE", "Resumption " + tag, "MESSAGE", "Lectures resume on Monday.", "SMS_MESSAGE", "Lectures resume on Monday.", "SIGNATURE", "Office of the Registrar"))));
        String id = String.valueOf(created.get("id"));
        assertThat(created.get("state")).isEqualTo("DRAFT");
        // the words are required of an announcement
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns", Map.of("name", "x", "templateKey", "ANNOUNCEMENT", "students", true, "channels", List.of("EMAIL"), "vars", Map.of())).getStatusCode().value()).isEqualTo(422);
        // the preview: both students; one e-mail good, one missing; both phones good
        Map<String, Object> preview = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns/" + id + "/preview", Map.of()));
        assertThat(((Number) preview.get("total")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) preview.get("emailMissing")).intValue()).isGreaterThanOrEqualTo(1);
        // a test to one address lands in the outbox about nobody
        Map<String, Object> test = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns/" + id + "/test", Map.of("email", "cmp-test-" + tag + "@example.test")));
        assertThat(((Number) test.get("queued")).intValue()).isEqualTo(1);
        // sent: the first batch goes in the request; the rest by the scheduler (here by hand); reported by channel
        Map<String, Object> sent = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns/" + id + "/send", Map.of()));
        assertThat(sent.get("job")).isNotNull();
        drain();
        Map<String, Object> one = body(it.get(ict, "/api/v1/notices/campaigns/" + id));
        assertThat(one.get("state")).isEqualTo("SENT");
        List<Map<String, Object>> report = (List<Map<String, Object>>) one.get("report");
        assertThat(report).extracting(r -> r.get("channel")).contains("EMAIL", "SMS", "PORTAL");
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND event_key = :k").param("s", a).param("k", "campaign:" + id).query(Integer.class).single())).isEqualTo(3);
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND event_key = :k").param("s", b).param("k", "campaign:" + id).query(Integer.class).single())).isEqualTo(2);
        assertThat(it.db(() -> jdbc.sql("SELECT subject FROM platform.notice WHERE about_id = :s AND event_key = :k AND channel = 'EMAIL'").param("s", a).param("k", "campaign:" + id).query(String.class).single())).isEqualTo("Resumption " + tag);
        // a campaign sent is not edited, and cancelling it is refused
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/notices/campaigns/" + id, Map.of("name", "again", "templateKey", "ANNOUNCEMENT", "students", true, "channels", List.of("EMAIL"), "vars", Map.of("TITLE", "t", "MESSAGE", "m"))).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/notices/campaigns/" + id + "/cancel", Map.of("reason", "x")).getStatusCode().value()).isEqualTo(422);
        // the student sees it on the portal
        String token = TestTokens.token(a, List.of("student"));
        Map<String, Object> bell = body(it.get(token, "/api/v1/me/notifications"));
        assertThat(((List<Map<String, Object>>) bell.get("notices")).stream().map(x -> x.get("subject"))).contains("Resumption " + tag);
    }

    @SuppressWarnings("unchecked")
    @Test
    void aDeanAddressesOnlyTheirOwnFacultyAndReadsComplianceWithinIt() {
        String facA = it.db(() -> jdbc.sql("SELECT faculty_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single());
        String facOther = it.db(() -> jdbc.sql("SELECT faculty_code FROM ref.programme WHERE faculty_code <> :f AND NOT coalesce(archived, false) ORDER BY code LIMIT 1").param("f", facA).query(String.class).single());
        UUID deanPerson = it.person("ZZCMP-DEAN-" + tag, "ZZCMPDEAN");
        it.db(() -> jdbc.sql("INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from) VALUES (gen_random_uuid(), :p, 'dean', 'faculty', :f, 'IT', :p, current_date)")
                .param("p", deanPerson).param("f", facA).update());
        String dean = TestTokens.token(deanPerson, List.of("dean"));
        // the other faculty is refused with the code the screen reads; the Dean's own is accepted
        ResponseEntity<Map> refused = it.call(dean, HttpMethod.POST, "/api/v1/notices/campaigns", Map.of("name", "IT dean " + tag, "templateKey", "PORTAL_MIGRATION", "students", true, "filters", Map.of("faculty", facOther), "channels", List.of("EMAIL")));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(refused.getBody())).contains("CAMPAIGN_SCOPE");
        Map<String, Object> own = body(it.call(dean, HttpMethod.POST, "/api/v1/notices/campaigns", Map.of("name", "IT dean own " + tag, "templateKey", "PORTAL_MIGRATION", "students", true, "filters", Map.of("faculty", facA, "session", ses), "channels", List.of("EMAIL"))));
        assertThat(own.get("state")).isEqualTo("DRAFT");
        // the staff are not the Dean's to write to
        assertThat(it.call(dean, HttpMethod.POST, "/api/v1/notices/campaigns", Map.of("name", "IT dean staff " + tag, "templateKey", "PORTAL_MIGRATION", "staff", true, "filters", Map.of("faculty", facA), "channels", List.of("EMAIL"))).getStatusCode().value()).isEqualTo(422);
        // the compliance picture: ICT reads the whole register after the reading is taken; the Dean reads their faculty, whatever they ask for
        body(it.call(ict, HttpMethod.POST, "/api/v1/biodata/compliance/refresh", Map.of()));
        Map<String, Object> all = body(it.get(ict, "/api/v1/biodata/compliance"));
        assertThat(((Map<String, Object>) all.get("summary")).get("computed_at")).isNotNull();
        assertThat(all.get("faculty")).isNull();
        assertThat(it.get(dean, "/api/v1/biodata/compliance?faculty=" + facOther).getStatusCode().value()).isEqualTo(422);
        Map<String, Object> mine = body(it.get(dean, "/api/v1/biodata/compliance"));
        assertThat(mine.get("faculty")).isEqualTo(facA);
        Map<String, Object> list = body(it.get(dean, "/api/v1/biodata/compliance/students?status=INCOMPLETE&size=20"));
        assertThat(((Number) list.get("total")).longValue()).isGreaterThanOrEqualTo(0);
        for (Map<String, Object> row : (List<Map<String, Object>>) list.get("rows")) {
            assertThat(row.get("status")).isEqualTo("INCOMPLETE");
        }
        assertThat(it.getList(ict, "/api/v1/biodata/compliance/duplicates?kind=PHONE").getStatusCode().value()).isEqualTo(200);
    }

    /** V430: staff reach read by ICT; a staff member with no e-mail is asked for one at sign-in and may put it off; the switch */
    @SuppressWarnings("unchecked")
    @Test
    void staffReachIsReadAndAStaffMemberWithoutAnAddressIsAskedAtSignIn() {
        UUID person = it.person("ZZCMP-REACH-" + tag, "ZZCMPREACH");
        it.db(() -> {
            jdbc.sql("UPDATE iam.person SET email = NULL, phone = '0800' || :n WHERE id = :p").param("n", tag + "1").param("p", person).update();
            jdbc.sql("INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from) VALUES (gen_random_uuid(), :p, 'lecturer', 'department', (SELECT code FROM ref.department WHERE ended_on IS NULL ORDER BY code LIMIT 1), 'IT', :p, current_date)")
                    .param("p", person).update();
            return null;
        });
        String staff = TestTokens.token(person, List.of("lecturer"));
        // the sign-in answer carries the prompt: ASK, with the phone it does hold
        Map<String, Object> me = body(it.get(staff, "/api/v1/iam/me"));
        Map<String, Object> prompt = (Map<String, Object>) me.get("contactPrompt");
        assertThat(prompt).isNotNull();
        assertThat(prompt.get("state")).isEqualTo("ASK");
        assertThat(prompt.get("kind")).isEqualTo("person");
        assertThat(prompt.get("phone_ok")).isEqualTo(true);
        // put off: not asked again for seven days
        body(it.call(staff, HttpMethod.POST, "/api/v1/me/contact-prompt/skip", Map.of()));
        assertThat(((Map<String, Object>) body(it.get(staff, "/api/v1/iam/me")).get("contactPrompt")).get("state")).isEqualTo("NONE");
        // ICT reads the staff reach: the person is phone-only
        Map<String, Object> reach = body(it.get(ict, "/api/v1/biodata/compliance/staff?status=PHONE_ONLY&q=ZZCMPREACH"));
        assertThat(((Number) reach.get("total")).longValue()).isGreaterThanOrEqualTo(1);
        assertThat(((List<Map<String, Object>>) reach.get("rows")).stream().map(r -> r.get("status"))).containsOnly("PHONE_ONLY");
        assertThat(((Map<String, Object>) reach.get("summary")).get("phone_only")).isNotNull();
        // a student is refused the staff reach
        assertThat(it.get(TestTokens.token(it.student("ITREACHS" + tag, "C00023", "MOAUM/ADM/87/05" + tag.substring(0, 4), null, 100), List.of("student")), "/api/v1/biodata/compliance/staff").getStatusCode().value()).isIn(403, 422);
        // the switch on the settings; run now reminds the person by SMS and on the portal, once
        body(it.call(ict, HttpMethod.PUT, "/api/v1/notices/settings", Map.of("staffContactRemind", true)));
        assertThat(body(it.get(ict, "/api/v1/notices/settings")).get("staff_contact_remind")).isEqualTo(true);
        body(it.call(ict, HttpMethod.POST, "/api/v1/notices/staff-contact-reminders/run", Map.of()));
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :p AND template_key = 'STAFF_CONTACT_REMINDER'").param("p", person).query(Integer.class).single())).isEqualTo(2);
        body(it.call(ict, HttpMethod.POST, "/api/v1/notices/staff-contact-reminders/run", Map.of()));
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :p AND template_key = 'STAFF_CONTACT_REMINDER'").param("p", person).query(Integer.class).single())).isEqualTo(2);
        body(it.call(ict, HttpMethod.PUT, "/api/v1/notices/settings", Map.of("staffContactRemind", false)));
    }

    @SuppressWarnings("unchecked")
    @Test
    void aStudentsPreferenceSwitchesAnOptionalSmsOffButNeverAMandatoryOne() {
        int n = it.freeDraw(1000, 10000, k -> List.of("MOAUM/ADM/87/02" + k, "MOAUM/PRF/87/" + k, "ITPREF" + k));
        UUID a = studentOfSession("ITPREF" + n, "C00023", "MOAUM/ADM/87/02" + n, "MOAUM/PRF/87/" + n, "pref-" + n + "@example.test", "0800" + (3000000 + n));
        String token = TestTokens.token(a, List.of("student"));
        Map<String, Object> before = body(it.get(token, "/api/v1/me/notifications/preferences"));
        assertThat(before.get("sms")).isEqualTo(true);
        Map<String, Object> after = body(it.call(token, HttpMethod.PUT, "/api/v1/me/notifications/preferences", Map.of("sms", false)));
        assertThat(after.get("sms")).isEqualTo(false);
        assertThat(after.get("email")).isEqualTo(true);
        int ann = it.db(() -> jdbc.sql("SELECT platform.tell_student(:s, 'ANNOUNCEMENT', NULL, '{\"TITLE\":\"IT\",\"MESSAGE\":\"Hello\",\"SMS_MESSAGE\":\"Hello\",\"SIGNATURE\":\"Registry\"}'::jsonb, :k)")
                .param("s", a).param("k", "it:pref:ann:" + n).query(Integer.class).single());
        int win = it.db(() -> jdbc.sql("SELECT platform.tell_student(:s, 'WINDOW_OPENED', 'COURSE_REGISTRATION', '{\"WINDOW\":\"Course registration\",\"SESSION\":\"2087/2088\",\"SEMESTER\":\"\"}'::jsonb, :k)")
                .param("s", a).param("k", "it:pref:win:" + n).query(Integer.class).single());
        assertThat(ann).isEqualTo(2);   // e-mail and the portal; the SMS switched off
        assertThat(win).isEqualTo(3);   // mandatory: every channel
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND event_key = :k AND channel = 'SMS'").param("s", a).param("k", "it:pref:ann:" + n).query(Integer.class).single())).isEqualTo(0);
    }
}
