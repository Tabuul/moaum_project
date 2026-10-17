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
 * V425: the central notification engine through the API — the templates ICT edits and previews, a test message through the
 * outbox, a window opened reaching the session's students as a job (e-mail, SMS and the portal, once), the student's bell
 * and read marks, their biodata status and confirmation, and a staff member's own contact.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class NotificationsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String ict;
    String tag;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(900_000) + 100_000);
        ict = TestTokens.token(it.person("ZZNOT-ICT-" + tag, "ZZNOTICT"), List.of("ict"));
    }

    /** the scheduler's work, done here by hand: every open notification job drained, oldest first, until none is left */
    private void drain() {
        for (int i = 0; i < 20; i++) {
            int ran = it.db(() -> jdbc.sql("SELECT count(*) FROM platform.run_notice_job(100000)").query(Integer.class).single());
            if (ran == 0) {
                return;
            }
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @SuppressWarnings("unchecked")
    @Test
    void templatesAreListedEditedPreviewedAndTested() {
        List<Map<String, Object>> all = it.getList(ict, "/api/v1/notices/templates").getBody();
        assertThat(all).extracting(t -> t.get("key")).contains("WINDOW_OPENED", "WINDOW_CLOSED:SCHOOL_FEES_PAYMENT", "BIODATA_REMINDER", "PORTAL_MIGRATION", "ANNOUNCEMENT");
        // a variant for one window, edited by ICT; the preview fills the sample values
        String key = "WINDOW_OPENED:POST_UTME_RESULT_CHECKING";
        Map<String, Object> saved = body(it.call(ict, HttpMethod.PUT, "/api/v1/notices/templates/" + key, Map.of(
                "label", "Post-UTME result checking opened", "purpose", "IT " + tag,
                "emailSubject", "[WINDOW] for [SESSION] is open", "emailBody", "Dear [FIRST_NAME], [WINDOW] for [SESSION] is open. [PORTAL_URL]",
                "smsBody", "[UNIVERSITY_SHORT]: [WINDOW] for [SESSION] is open.", "mandatory", true, "priority", "HIGH", "enabled", true)));
        assertThat(saved.get("key")).isEqualTo(key);
        Map<String, Object> preview = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/templates/" + key + "/preview", Map.of("WINDOW", "Post-UTME result checking", "SESSION", "2031/2032")));
        Map<String, Object> email = (Map<String, Object>) preview.get("email");
        assertThat(email.get("subject")).isEqualTo("Post-UTME result checking for 2031/2032 is open");
        assertThat(String.valueOf(email.get("body"))).startsWith("Dear Adaeze, Post-UTME result checking for 2031/2032 is open.").doesNotContain("[");
        assertThat(preview.get("portal")).isNull();
        // a bad key is refused; a test message to one address lands in the outbox, queued, about nobody
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/notices/templates/bad key", Map.of("label", "x", "smsBody", "y")).getStatusCode().value()).isEqualTo(422);
        Map<String, Object> test = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/templates/" + key + "/test", Map.of("email", "it-" + tag + "@example.test")));
        assertThat(test.get("queued")).isEqualTo(1);
        Map<String, Object> row = it.db(() -> jdbc.sql("SELECT state, template_key, about_kind FROM platform.notice WHERE recipient = :r").param("r", "it-" + tag + "@example.test").query().singleRow());
        assertThat(row.get("state")).isEqualTo("QUEUED");
        assertThat(row.get("template_key")).isEqualTo(key);
        // an address that is not one is never queued
        Map<String, Object> bad = body(it.call(ict, HttpMethod.POST, "/api/v1/notices/templates/" + key + "/test", Map.of("email", "not-an-address-" + tag)));
        assertThat(bad.get("queued")).isEqualTo(0);
        assertThat(it.db(() -> jdbc.sql("SELECT last_error FROM platform.notice WHERE recipient = :r").param("r", "not-an-address-" + tag).query(String.class).single())).isEqualTo("INVALID_EMAIL");
        // the history is searchable by what it is about and by words
        Map<String, Object> outbox = body(it.get(ict, "/api/v1/platform/notices?kind=test&q=it-" + tag));
        assertThat((List<Map<String, Object>>) outbox.get("recent")).extracting(r -> r.get("recipient")).contains("it-" + tag + "@example.test");
        assertThat(outbox.get("byChannel")).isNotNull();
    }

    @SuppressWarnings("unchecked")
    @Test
    void aWindowOpenedReachesTheSessionsStudentsOnceAsAJobAndTheStudentReadsItOnThePortal() {
        String ses = "2089/2090";
        it.session(ses, 2089);
        int n = it.freeDraw(1000, 10000, k -> List.of("MOAUM/ADM/89/00" + k, "MOAUM/NOT/89/" + k, "ITNOTIFY" + k));
        UUID student = it.student("ITNOTIFY" + n, "C00023", "MOAUM/ADM/89/00" + n, "MOAUM/NOT/89/" + n, 100);
        it.db(() -> {
            jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:s, '0800000' || :n, 'notify-' || :n || '@example.test')").param("s", student).param("n", n).update();
            jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :s").param("ses", ses).param("s", student).update();
            return null;
        });
        String token = TestTokens.token(student, List.of("student"));
        Map<String, Object> before = body(it.get(token, "/api/v1/me/notifications/unread"));
        int unreadBefore = ((Number) before.get("unread")).intValue();
        // a window is told of only when its state changes: closed first (the default is open), then opened — the message is
        // queued as a job, the first batch sent in the Director's own request, the audience counted
        body(it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/COURSE_REGISTRATION", Map.of("session", ses, "semester", 1, "action", "CLOSE", "reason", "IT " + tag + " closed first")));
        drain();
        // (on a database that ran this test before, the window was already closed and the closing told nobody: count from here)
        int unreadAfterClose = ((Number) body(it.get(token, "/api/v1/me/notifications/unread")).get("unread")).intValue();
        Map<String, Object> opened = body(it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/COURSE_REGISTRATION",
                Map.of("session", ses, "semester", 1, "action", "OPEN", "closesAt", "2089-12-01T23:59:00+01:00", "reason", "IT " + tag)));
        assertThat(((Number) opened.get("told")).intValue()).isGreaterThanOrEqualTo(1);
        drain();
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice_job WHERE payload ->> 'session' = :s AND state <> 'DONE'").param("s", ses).query(Integer.class).single())).isEqualTo(0);
        List<Map<String, Object>> mine = it.db(() -> jdbc.sql("SELECT channel, subject, state FROM platform.notice WHERE about_id = :s AND event_key LIKE 'window:%:OPEN' ORDER BY channel")
                .param("s", student).query().listOfRows());
        assertThat(mine).extracting(m -> m.get("channel")).containsExactly("EMAIL", "PORTAL", "SMS");
        // the e-mail's subject files the SMS too; the portal notice carries its own shorter title
        assertThat(mine.stream().filter(m -> !"PORTAL".equals(m.get("channel"))).map(m -> m.get("subject"))).containsOnly("Course registration for " + ses + ", semester 1 is open");
        assertThat(mine.stream().filter(m -> "PORTAL".equals(m.get("channel"))).map(m -> m.get("subject"))).containsOnly("Course registration is open");
        // the student's bell: the opening is one more unread portal notice; the newest read, then all read
        Map<String, Object> bell = body(it.get(token, "/api/v1/me/notifications"));
        assertThat(((Number) bell.get("unread")).intValue()).isEqualTo(unreadAfterClose + 1);
        assertThat(unreadAfterClose).isGreaterThanOrEqualTo(unreadBefore);
        Map<String, Object> notice = ((List<Map<String, Object>>) bell.get("notices")).get(0);
        assertThat(notice.get("subject")).isEqualTo("Course registration is open");
        assertThat(String.valueOf(notice.get("body"))).contains("Course registration for " + ses + ", semester 1 is now open");
        assertThat(notice.get("read_at")).isNull();
        Map<String, Object> read = body(it.call(token, HttpMethod.POST, "/api/v1/me/notifications/" + notice.get("id") + "/read", Map.of()));
        assertThat(read.get("read")).isEqualTo(true);
        assertThat(((Number) body(it.get(token, "/api/v1/me/notifications/unread")).get("unread")).intValue()).isEqualTo(unreadAfterClose);
        body(it.call(token, HttpMethod.POST, "/api/v1/me/notifications/read-all", Map.of()));
        assertThat(((Number) body(it.get(token, "/api/v1/me/notifications/unread")).get("unread")).intValue()).isEqualTo(0);
        // closed again: a new event, told once more on every channel — three more than before, whatever an earlier run left
        int closesBefore = it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND event_key LIKE 'window:%:CLOSE'").param("s", student).query(Integer.class).single());
        body(it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/COURSE_REGISTRATION", Map.of("session", ses, "semester", 1, "action", "CLOSE", "reason", "IT " + tag)));
        drain();
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND event_key LIKE 'window:%:CLOSE'").param("s", student).query(Integer.class).single())).isEqualTo(closesBefore + 3);
    }

    @SuppressWarnings("unchecked")
    @Test
    void theStudentsBiodataStatusIsReadAndConfirmedAndAStaffMemberKeepsTheirOwnContact() {
        int n = it.freeDraw(1000, 10000, k -> List.of("MOAUM/ADM/88/01" + k, "ITBIO" + k));
        UUID student = it.student("ITBIO" + n, "C00023", "MOAUM/ADM/88/01" + n, null, 100);
        String token = TestTokens.token(student, List.of("student"));
        Map<String, Object> status = body(it.get(token, "/api/v1/me/biodata-status"));
        assertThat(status.get("status")).isEqualTo("INCOMPLETE");
        assertThat(((Number) status.get("required")).intValue()).isGreaterThan(((Number) status.get("completed")).intValue());
        // confirming an incomplete record is refused with the code the screen reads
        ResponseEntity<Map> refused = it.call(token, HttpMethod.POST, "/api/v1/me/biodata/confirm", Map.of());
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(refused.getBody())).contains("BIODATA_INCOMPLETE");
        // the engine's settings: read by ICT, the reminder switch and the review period stated
        Map<String, Object> settings = body(it.call(ict, HttpMethod.PUT, "/api/v1/notices/settings", Map.of("remindEnabled", true, "reviewDays", 365)));
        assertThat(settings.get("remind_enabled")).isEqualTo(true);
        assertThat(((Number) settings.get("review_days")).intValue()).isEqualTo(365);
        assertThat(((Map<String, Object>) body(it.get(ict, "/api/v1/notices/settings/counts")).get("counts")).get("total")).isNotNull();
        body(it.call(ict, HttpMethod.PUT, "/api/v1/notices/settings", Map.of("remindEnabled", false, "reviewDays", 0)));
        // a staff member's own contact: a bad phone refused, a good one kept on the person
        UUID staff = it.person("ZZNOT-STF-" + tag, "ZZNOTSTAFF");
        String staffToken = TestTokens.token(staff, List.of("lecturer"));
        assertThat(it.call(staffToken, HttpMethod.PUT, "/api/v1/staff/contact", Map.of("email", "staff-" + tag + "@example.test", "phone", "12")).getStatusCode().value()).isEqualTo(422);
        Map<String, Object> contact = body(it.call(staffToken, HttpMethod.PUT, "/api/v1/staff/contact", Map.of("email", "staff-" + tag + "@example.test", "phone", "0801 234 " + tag.substring(0, 4))));
        assertThat(contact.get("email")).isEqualTo("staff-" + tag + "@example.test");
        assertThat(contact.get("email_valid")).isEqualTo(true);
        assertThat(it.db(() -> jdbc.sql("SELECT email FROM iam.person WHERE id = :p").param("p", staff).query(String.class).single())).isEqualTo("staff-" + tag + "@example.test");
        // a student never reaches the staff contact endpoint
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/staff/contact", Map.of("email", "x@example.test")).getStatusCode().value()).isIn(403, 422);
    }
}
