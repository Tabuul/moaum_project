package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * Oct 2026: the sign-in help form checks a student's number against the register as it is typed — a matriculation number, or the
 * admission number a student signs in with before one is issued, however it is typed (case, spaces) — and says only whether a
 * student holds it, never whose; a staff or applicant name is not checked; and a request for the student portal naming a number
 * no student holds is refused when sent, while one naming a real number goes to the desk. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SignInHelpCheckIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private ResponseEntity<Map> anonymous(String path, Object body) {
        return org.springframework.web.client.RestClient.builder().baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { }).build()
                .post().uri(path).contentType(org.springframework.http.MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    @Test
    void aStudentsNumberIsCheckedAgainstTheRegisterAndAnUnknownOneIsNotSent() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String matric = it.freeNumber("MOAU/ZZ/HLP/26/", 5);
        String admission = it.freeNumber("MOAUM/ADM/26/8", 5);
        it.student(it.freeSurname("ZZHELPCHECK"), "C00023", admission, matric, 100);
        String unknown = it.freeNumber("MOAU/ZZ/HLP/26/", 5);
        String check = "/api/v1/helpdesk/sign-in-help/check";

        // found however it is typed; the answer says whether, never whose
        ResponseEntity<Map> found = anonymous(check, Map.of("accountType", "Student portal", "number", " " + matric.toLowerCase().replace("/", " / ") + " "));
        assertThat(found.getStatusCode().value()).as(String.valueOf(found.getBody())).isEqualTo(200);
        assertThat(found.getBody()).containsOnlyKeys("applies", "found").containsEntry("applies", true).containsEntry("found", true);
        assertThat(anonymous(check, Map.of("accountType", "Student portal", "number", admission)).getBody()).containsEntry("found", true);
        assertThat(anonymous(check, Map.of("accountType", "Student portal", "number", unknown)).getBody()).containsEntry("found", false);
        assertThat(anonymous(check, Map.of("accountType", "Student portal", "number", "MO")).getBody()).containsEntry("found", false);
        // a staff or applicant name is not checked
        assertThat(anonymous(check, Map.of("accountType", "Staff portal", "number", "SS/1234")).getBody()).containsOnlyKeys("applies").containsEntry("applies", false);

        // sent: an unknown student number is refused; a real one goes to the desk
        String email = "zz-helpcheck-" + UUID.randomUUID().toString().substring(0, 8) + "@example.edu";
        ResponseEntity<Map> refused = anonymous("/api/v1/helpdesk/sign-in-help", Map.of("name", "Ada Okafor", "email", email, "description", "The reset link never arrives.",
                "details", Map.of("account_type", "Student portal", "username", unknown, "error", "Invalid password")));
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);
        assertThat(refused.getBody()).containsEntry("code", "HELPDESK_HELP_NUMBER_UNKNOWN");
        ResponseEntity<Map> sent = anonymous("/api/v1/helpdesk/sign-in-help", Map.of("name", "Ada Okafor", "email", email, "description", "The reset link never arrives.",
                "details", Map.of("account_type", "Student portal", "username", matric.toLowerCase(), "error", "Invalid password")));
        assertThat(sent.getStatusCode().value()).as(String.valueOf(sent.getBody())).isEqualTo(200);
        assertThat(String.valueOf(sent.getBody().get("number"))).matches("TICK-\\d{4}-\\d{5}");
        // a staff request is not held to the student register
        ResponseEntity<Map> staff = anonymous("/api/v1/helpdesk/sign-in-help", Map.of("name", "Ada Okafor", "email", "x" + email, "description", "Locked out of the staff portal.",
                "details", Map.of("account_type", "Staff portal", "username", "SS/NOT-A-NUMBER", "error", "Account locked")));
        assertThat(staff.getStatusCode().value()).as(String.valueOf(staff.getBody())).isEqualTo(200);
    }
}
