package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

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
 * V594, end to end: a Login Issues ticket asked from the sign-in page (V363) about the student portal is matched to the student
 * holding the number given — typed in lower case with a space — and shown so on the desk's queue and the ticket; one about the
 * applicant portal is not. Selected with every eligible ticket of the search, it is reset by the reset from tickets: the student
 * reset to the matriculation number, made to change it, the ticket resolved. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SignInTicketResetIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static final String BASE = "/api/v1/helpdesk/tickets/password-reset";

    /** a request from the sign-in page, as the sign-in help form submits it (helpdesk.submit_public), routed as it routes it */
    private UUID ask(ItSupport it, String email, String accountType, String number) {
        return it.db(() -> {
            UUID id = jdbc.sql("SELECT helpdesk.submit_public(:n, :e, :p, CAST(:d AS jsonb), :desc)")
                    .param("n", "Zzsip Requester").param("e", email).param("p", "08031234567")
                    .param("d", "{\"account_type\": \"" + accountType + "\", \"username\": \"" + number + "\", \"error\": \"Invalid username or password\"}")
                    .param("desc", "My password is not accepted on the portal").query(UUID.class).single();
            jdbc.sql("SELECT helpdesk.route(:t)").param("t", id).query(String.class).single();
            return id;
        });
    }

    private Map<String, Object> waitFor(ItSupport it, String token, String id) throws InterruptedException {
        Map<String, Object> op = null;
        for (int i = 0; i < 120; i++) {
            op = it.get(token, BASE + "/operations/" + id).getBody();
            String status = String.valueOf(op.get("status"));
            if (!"PENDING".equals(status) && !"PROCESSING".equals(status)) return op;
            Thread.sleep(500);
        }
        return op;
    }

    @Test
    void aRequestFromTheSignInPageIsResetAsTheStudentsOwnTicket() throws InterruptedException {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = it.freeDraw(10000, 99999, k -> List.of("ZZSIPA" + k, "ZZ-SIP-HD-" + k, "MOAU/SC/SIP/26/" + k));
        String matric = "MOAU/SC/SIP/26/" + n;
        UUID s = it.student("ZZSIPA" + n, "C00023", "MOAUM/ADM/89/" + (100000 + n), matric, 200);
        String head = TestTokens.token(it.person("ZZ-SIP-HD-" + n, "ZZSIPHD" + n), List.of("helpdeskhead"));
        String email = "zzsip" + n + "@example.com";

        // the student portal, the number typed in lower case with a space; and the applicant portal with the same number
        UUID mine = ask(it, email, "Student portal", matric.toLowerCase().replace("/26/", "/26/ "));
        UUID other = ask(it, email, "Applicant portal", matric);
        String number = jdbc.sql("SELECT number FROM helpdesk.ticket WHERE id = :t").param("t", mine).query(String.class).single();
        String otherNumber = jdbc.sql("SELECT number FROM helpdesk.ticket WHERE id = :t").param("t", other).query(String.class).single();

        // the desk's queue: the student found under the request, eligible; the other not
        Map<String, Object> row = ((List<Map<String, Object>>) it.get(head, "/api/v1/helpdesk/tickets?issue=login&status=open&q=" + number).getBody().get("rows")).get(0);
        assertThat(row).containsEntry("requester_kind", "PUBLIC").containsEntry("reset_state", "ELIGIBLE").containsEntry("matched_student_id", s.toString())
                .containsEntry("matched_matric", matric);
        Map<String, Object> otherRow = ((List<Map<String, Object>>) it.get(head, "/api/v1/helpdesk/tickets?issue=login&status=open&q=" + otherNumber).getBody().get("rows")).get(0);
        assertThat(otherRow).containsEntry("reset_state", "NO_STUDENT");
        assertThat(otherRow.get("matched_student_id")).isNull();
        assertThat((List<String>) it.get(head, "/api/v1/helpdesk/tickets?issue=login&status=open&eligibleIds=true&q=" + email).getBody().get("ids"))
                .contains(mine.toString()).doesNotContain(other.toString());
        Map<String, Object> figures = (Map<String, Object>) it.get(head, BASE + "/summary").getBody().get("figures");
        assertThat(((Number) figures.get("unmatched")).intValue()).isPositive();
        assertThat(((Number) figures.get("public")).intValue()).isGreaterThanOrEqualTo(2);

        // checked: one eligible, the other refused with its reason
        ResponseEntity<Map> checked = it.call(head, HttpMethod.POST, BASE + "/validate", Map.of("ticketIds", List.of(mine.toString(), other.toString())));
        assertThat(checked.getStatusCode().value()).as(String.valueOf(checked.getBody())).isEqualTo(200);
        assertThat(checked.getBody()).containsEntry("eligible", 1);
        assertThat((List<Map<String, Object>>) checked.getBody().get("rows")).extracting(r -> r.get("code"))
                .containsExactlyInAnyOrder("ELIGIBLE", "TICKET_NO_STUDENT");

        // reset and resolved
        ResponseEntity<Map> started = it.call(head, HttpMethod.POST, BASE + "/execute", Map.of("ticketIds", List.of(mine.toString()),
                "reason", "Login tickets asked from the sign-in page", "resolution", "Your password was reset: sign in with your matriculation number, then choose your own."));
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        Map<String, Object> op = waitFor(it, head, String.valueOf(started.getBody().get("id")));
        assertThat(op).containsEntry("status", "COMPLETED").containsEntry("succeeded", 1);
        assertThat(jdbc.sql("SELECT status FROM helpdesk.ticket WHERE id = :t").param("t", mine).query(String.class).single()).isEqualTo("RESOLVED");
        assertThat(jdbc.sql("SELECT must_change FROM iam.student_account WHERE student_id = :s").param("s", s).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE ticket_id = :t AND student_id = :s AND action = 'PASSWORD_RESET'")
                .param("t", mine).param("s", s).query(Long.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT status FROM helpdesk.ticket WHERE id = :t").param("t", other).query(String.class).single()).isNotIn("RESOLVED", "CLOSED");
    }
}
