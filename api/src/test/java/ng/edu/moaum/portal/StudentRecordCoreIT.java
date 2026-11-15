package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * GET /api/v1/me?view=core: the student's record as every student screen but the dashboard reads it — the same fields as the full
 * record, in the same order and with the same values, without the dashboard's panels (the school fees, the portal's windows, the
 * results and the standing, the carry-overs, the registration, the notices, the graduation, the pre-resumption steps), which are
 * most of what the database does for a student's page (performance audit §Z). The e-mails and SMS the full record's notices list
 * are read on their own at /me/notifications/sent, and a student the fee gate holds still reads the record. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentRecordCoreIT {

    /** the dashboard's panels: in the full record, never in the core */
    static final List<String> PANELS = List.of("fees", "windows", "gpa", "cgpa", "standing", "probation", "carryovers", "registration",
            "notices", "graduation", "academic");

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void theCoreRecordIsTheFullRecordWithoutTheDashboardsPanels() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        UUID student = it.student(it.freeSurname("ZZMECORE"), "C00023", null, it.freeNumber("MOAUM/MEC/26/", 5), 200);
        String token = TestTokens.token(student, List.of("student"));
        // an e-mail and an SMS the portal sent about the student, a portal notice (the bell's), and a code that confirms a contact —
        // a message for its mailbox alone (platform.notice_carries_secret), never listed back on the portal
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO platform.notice (channel, recipient, subject, body, about_kind, about_id, state, sent_at, created_at) VALUES
                      ('EMAIL', 'zz.mecore@example.invalid', 'StudentRecordCoreIT: your result', 'A result was published.', 'student', :s, 'SENT', now(), now() - interval '4 minutes'),
                      ('SMS', '08000000000', 'StudentRecordCoreIT: payment', 'Your payment was received.', 'student', :s, 'QUEUED', NULL, now() - interval '3 minutes'),
                      ('PORTAL', 'portal', 'StudentRecordCoreIT: window', 'Course registration is open.', 'student', :s, 'SENT', now(), now() - interval '2 minutes'),
                      ('EMAIL', 'zz.mecore@example.invalid', 'StudentRecordCoreIT: confirm', 'Your code to confirm this e-mail is 123456.', 'student', :s, 'SENT', now(), now() - interval '1 minute')
                    """).param("s", student).update();
            return null;
        });

        ResponseEntity<Map> full = it.get(token, "/api/v1/me");
        ResponseEntity<Map> core = it.get(token, "/api/v1/me?view=core");
        assertThat(full.getStatusCode().value()).as(String.valueOf(full.getBody())).isEqualTo(200);
        assertThat(core.getStatusCode().value()).as(String.valueOf(core.getBody())).isEqualTo(200);
        // a panel with nothing in it (no CGPA yet, no registration) is left out of the JSON like any other null
        assertThat(full.getBody()).containsKeys("fees", "windows", "gpa", "carryovers", "notices", "academic");
        assertThat(core.getBody()).doesNotContainKeys(PANELS.toArray(String[]::new));
        Map<String, Object> expected = new LinkedHashMap<>(full.getBody());
        PANELS.forEach(expected::remove);
        assertThat(core.getBody()).isEqualTo(expected);
        assertThat(new ArrayList<>(core.getBody().keySet())).isEqualTo(new ArrayList<>(expected.keySet()));
        // who the student is and the menu's flags are all there
        assertThat(core.getBody()).containsKeys("id", "name", "matricNo", "session", "entryMode", "portalAccess", "dashboard", "collegeArea",
                "summerArea", "siwesArea", "contact", "hasPhoto");
        assertThat(core.getBody().get("id")).isEqualTo(student.toString());
        // any other view is the full record
        assertThat(it.get(token, "/api/v1/me?view=everything").getBody()).isEqualTo(full.getBody());

        // the notices filed about the student, as the full record's: every channel (the notifications page keeps the e-mails and
        // SMS), newest first, without the message that carries a code for its mailbox alone (filed all the same)
        ResponseEntity<List> sent = it.getList(token, "/api/v1/me/notifications/sent");
        assertThat(sent.getStatusCode().value()).isEqualTo(200);
        assertThat(sent.getBody()).isEqualTo(full.getBody().get("notices"));
        assertThat(sent.getBody()).extracting(n -> ((Map) n).get("subject"))
                .containsExactly("StudentRecordCoreIT: window", "StudentRecordCoreIT: payment", "StudentRecordCoreIT: your result");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject = 'StudentRecordCoreIT: confirm'")
                .param("s", student).query(Long.class).single()).isEqualTo(1L);
        // the student's own, nobody else's
        String another = TestTokens.token(it.student(it.freeSurname("ZZMECORE"), "C00023", null, it.freeNumber("MOAUM/MEC/26/", 5), 200), List.of("student"));
        assertThat(it.getList(another, "/api/v1/me/notifications/sent").getBody()).isEmpty();
        assertThat(it.getList(TestTokens.token(UUID.randomUUID(), List.of("registrar")), "/api/v1/me/notifications/sent")
                .getStatusCode().value()).isEqualTo(403);
    }
}
