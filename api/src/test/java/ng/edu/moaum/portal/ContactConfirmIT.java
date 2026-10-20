package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import ng.edu.moaum.portal.auth.PasswordResetService;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V575, end to end: contacts a department uploads are held unconfirmed. The forgotten-password door sends no link to them and the
 * desk's reset link is refused (AUTH_CONTACT_UNCONFIRMED); the student sees them on the first screen (iam/me), has a code sent to
 * the e-mail and confirms it — after which the link goes there — and says the phone is not theirs, which empties it; another
 * student's phone is confirmed at the desk. The upload counts what became of its contacts. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ContactConfirmIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    PasswordResetService resets;

    private static final Pattern CODE = Pattern.compile("\\b(\\d{6})\\b");

    private long notices(String to) {
        return jdbc.sql("SELECT count(*) FROM platform.notice WHERE lower(recipient) = lower(:r)").param("r", to).query(Long.class).single();
    }

    @Test
    void uploadedContactsWaitForTheStudentBeforeAResetLinkGoesThere() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        String matA = "MOAU/SC/CNF/26/" + n, matB = "MOAU/SC/CNG/26/" + n;
        UUID a = it.student("ZZCNFA" + n, "C00023", "MOAUM/ADM/85/" + (100000 + n), matA, 200);
        UUID b = it.student("ZZCNFB" + n, "C00023", "MOAUM/ADM/85/" + (200000 + n), matB, 200);
        String email = "zzcnf" + n + "@example.com", phoneA = String.format("0803%07d", n), phoneB = String.format("0806%07d", n);
        String registrar = TestTokens.token(it.person("ZZ-CNF-RG-" + n, "ZZCNFRG" + n), List.of("registrar"));
        UUID agent = it.person("ZZ-CNF-AG-" + n, "ZZCNFAG" + n);
        it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','EDIT_CONTACT'])
                """).param("p", agent).update());
        String agentTok = TestTokens.token(agent, List.of("ictagent"));

        // uploaded: held unconfirmed
        ResponseEntity<Map> up = it.call(registrar, HttpMethod.POST, "/api/v1/student-contacts/upload", Map.of("fileName", "contacts.csv", "rows", List.of(
                Map.of("number", matA, "phone", phoneA, "email", email), Map.of("number", matB, "phone", phoneB))));
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT email_pending AND phone_pending FROM people.student_contact WHERE student_id = :s").param("s", a).query(Boolean.class).single()).isTrue();

        // no link to them: the door is silent, the desk is refused
        it.anon(HttpMethod.POST, "/api/v1/auth/forgot", Map.of("identifier", matA));
        assertThat(notices(email)).isZero();
        Throwable refused = catchThrowable(() -> AuditContextHolder.with(new AuditContext(agent, "ictagent", "integration test", null, null),
                () -> new TransactionTemplate(transactions).execute(s -> resets.forStudent(a))));
        assertThat(refused).isInstanceOf(DomainRuleViolation.class);
        assertThat(((DomainRuleViolation) refused).code()).isEqualTo("AUTH_CONTACT_UNCONFIRMED");

        // the student is asked on the first screen, confirms the e-mail by its code, and says the phone is not theirs
        String student = TestTokens.token(a, List.of("student"));
        Map<String, Object> confirm = (Map<String, Object>) it.get(student, "/api/v1/iam/me").getBody().get("contactConfirm");
        assertThat(confirm).containsEntry("email", email).containsEntry("phone", phoneA);
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/contact/confirm/code", Map.of("field", "EMAIL")).getStatusCode().value()).isEqualTo(200);
        String body = jdbc.sql("SELECT body FROM platform.notice WHERE lower(recipient) = lower(:r) ORDER BY created_at DESC LIMIT 1").param("r", email).query(String.class).single();
        Matcher m = CODE.matcher(body);
        assertThat(m.find()).as(body).isTrue();
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/contact/confirm", Map.of("field", "EMAIL", "code", "000000".equals(m.group(1)) ? "111111" : "000000"))
                .getBody()).containsEntry("outcome", "WRONG");
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/contact/confirm", Map.of("field", "EMAIL", "code", m.group(1))).getBody()).containsEntry("outcome", "CONFIRMED");
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/contact/not-mine", Map.of("field", "PHONE")).getBody()).containsEntry("outcome", "REFUSED");
        assertThat(jdbc.sql("SELECT coalesce(phone, '-') FROM people.student_contact WHERE student_id = :s").param("s", a).query(String.class).single()).isEqualTo("-");
        assertThat(it.get(student, "/api/v1/iam/me").getBody()).doesNotContainKey("contactConfirm");

        // confirmed: the link now goes to it
        long before = notices(email);
        it.anon(HttpMethod.POST, "/api/v1/auth/forgot", Map.of("identifier", matA));
        assertThat(notices(email)).isGreaterThan(before);

        // the desk confirms another student's phone after checking with them; an office without contact editing cannot
        assertThat(it.get(agentTok, "/api/v1/helpdesk/support/students/" + b).getBody().get("contact")).asInstanceOf(org.assertj.core.api.InstanceOfAssertFactories.MAP)
                .containsEntry("phone_pending", true);
        ResponseEntity<Map> desk = it.call(agentTok, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + b + "/contact/confirm",
                Map.of("field", "PHONE", "reason", "Read back to the student on a call"));
        assertThat(desk.getStatusCode().value()).as(String.valueOf(desk.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT phone_pending FROM people.student_contact WHERE student_id = :s").param("s", b).query(Boolean.class).single()).isFalse();

        // what became of the upload's contacts
        Map<String, Object> mine = ((List<Map<String, Object>>) it.get(registrar, "/api/v1/student-contacts").getBody().get("uploads")).stream()
                .filter(u -> String.valueOf(u.get("id")).equals(String.valueOf(up.getBody().get("uploadId")))).findFirst().orElseThrow();
        assertThat(mine).containsEntry("waiting", 0).containsEntry("confirmed", 2).containsEntry("rejected", 1);
    }
}
