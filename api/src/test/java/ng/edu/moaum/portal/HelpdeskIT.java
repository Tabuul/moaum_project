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
 * ICT support tickets (V251), end to end: a student submits and receives a number; another student cannot read it;
 * the public page opens it only with the right email; the first agent to read it opens it; the agent takes it, starts
 * work, notes internally (never shown to the student), updates the student, resolves; the student reopens on a
 * reason; the agent resolves again; the student confirms and the ticket closes, with the whole history on it. A
 * wrongly typed file is refused, and a category is deactivated rather than deleted.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class HelpdeskIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;

    UUID student;
    UUID other;
    UUID agentId;
    String studentToken;
    String otherToken;
    String agent;
    String director = ItSupport.token("ict");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        student = it.student("ZZHDSTUDENT", "C00023", null, "MOAUM/MTC/95/9701", 300);
        other = it.student("ZZHDOTHER", "C00023", null, "MOAUM/MTC/95/9702", 300);
        studentToken = TestTokens.token(student, List.of("student"));
        otherToken = TestTokens.token(other, List.of("student"));
        agentId = it.person("MOAUM/IT/HD01", "ZZHDAGENT");
        it.db(() -> {
            jdbc.sql("UPDATE iam.person SET email = 'agent@example.edu' WHERE id = :id").param("id", agentId).update();
            jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from)
                    SELECT gen_random_uuid(), :p, 'ictagent', 'platform', 'integration test', :p, current_date
                     WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = 'ictagent')
                    """).param("p", agentId).update();
            return null;
        });
        agent = TestTokens.token(agentId, List.of("ictagent"));
    }

    /** the public page: no token at all */
    private ResponseEntity<Map> anonymous(String path, Object body) {
        return org.springframework.web.client.RestClient.builder().baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { }).build()
                .post().uri(path).contentType(org.springframework.http.MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    private static Object path(Map body, String key) {
        return body == null ? null : body.get(key);
    }

    @Test
    void aTicketWalksItsLifecycleAndStaysPrivateToItsRequester() {
        // the student's profile is filled from the account
        ResponseEntity<Map> profile = it.get(studentToken, "/api/v1/helpdesk/my/profile");
        assertThat(profile.getStatusCode().value()).as(String.valueOf(profile.getBody())).isEqualTo(200);
        assertThat(path(profile.getBody(), "kind")).isEqualTo("STUDENT");
        assertThat(path(profile.getBody(), "number")).isEqualTo("MOAUM/MTC/95/9701");

        // a payment ticket without its required fields is refused, with them it is numbered
        ResponseEntity<Map> refused = it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets", Map.of(
                "category", "PAYMENT", "subject", "Payment not showing", "description", "I paid school fees on Monday and the portal still says unpaid.",
                "email", "zzhd@example.edu", "details", Map.of()));
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);
        ResponseEntity<Map> made = it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets", Map.of(
                "category", "PAYMENT", "subject", "Payment not showing", "description", "I paid school fees on Monday and the portal still says unpaid.",
                "email", "zzhd@example.edu", "details", Map.of("payment_reference", "RRR-77", "payment_date", "2026-09-01", "payment_type", "School fees", "amount", "45000")));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        String id = String.valueOf(path(made.getBody(), "id"));
        String number = String.valueOf(path(made.getBody(), "number"));
        assertThat(number).matches("TICK-\\d{4}-\\d{5}");

        // the requester was told, and the desk too
        Long notices = jdbc.sql("SELECT count(*) FROM platform.notice WHERE recipient IN ('zzhd@example.edu', 'agent@example.edu') AND subject LIKE '%' || :n || '%'")
                .param("n", number).query(Long.class).single();
        assertThat(notices).isGreaterThanOrEqualTo(2L);

        // another student cannot read it; the public page needs the right email
        assertThat(it.get(otherToken, "/api/v1/helpdesk/my/tickets/" + id).getStatusCode().value()).isEqualTo(404);
        ResponseEntity<Map> wrongEmail = anonymous("/api/v1/helpdesk/track", Map.of("number", number, "email", "someone@else.edu"));
        assertThat(wrongEmail.getStatusCode().value()).isEqualTo(404);
        ResponseEntity<Map> tracked = anonymous("/api/v1/helpdesk/track", Map.of("number", number, "email", "ZZHD@example.edu"));
        assertThat(tracked.getStatusCode().value()).as(String.valueOf(tracked.getBody())).isEqualTo(200);
        assertThat(path(tracked.getBody(), "status")).isEqualTo("SUBMITTED");

        // a PNG that is not a PNG is refused; a real one is kept
        byte[] fake = "not really a png".getBytes();
        ResponseEntity<Map> badFile = it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets/" + id + "/attachments",
                Map.of("filename", "receipt.png", "contentType", "image/png", "contentBase64", Base64.getEncoder().encodeToString(fake)));
        assertThat(badFile.getStatusCode().value()).isEqualTo(422);
        assertThat(path(badFile.getBody(), "code")).isEqualTo("HELPDESK_FILE_TYPE");
        byte[] png = new byte[] {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 'I', 'H', 'D', 'R'};
        ResponseEntity<Map> goodFile = it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets/" + id + "/attachments",
                Map.of("filename", "receipt.png", "contentType", "image/png", "contentBase64", Base64.getEncoder().encodeToString(png)));
        assertThat(goodFile.getStatusCode().value()).as(String.valueOf(goodFile.getBody())).isEqualTo(200);
        String att = String.valueOf(path(goodFile.getBody(), "id"));
        assertThat(it.get(otherToken, "/api/v1/helpdesk/my/tickets/" + id + "/attachments/" + att + "/content").getStatusCode().value()).isEqualTo(404);

        // the first agent to read it opens it, on the record
        ResponseEntity<Map> read = it.get(agent, "/api/v1/helpdesk/tickets/" + id);
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        assertThat(path(read.getBody(), "status")).isEqualTo("OPENED");
        assertThat(path(read.getBody(), "opened_by_name")).isEqualTo("ZZHDAGENT, Invented");

        // the agent takes it, cannot resolve before starting, starts, notes internally, updates the student, resolves
        assertThat(it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/assign", Map.of("agentId", agentId.toString())).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> early = it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/resolve",
                Map.of("summary", "Payment matched", "details", "The payment was matched to the ledger and the receipt reissued."));
        assertThat(early.getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/status", Map.of("status", "IN_PROGRESS")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/comments", Map.of("body", "Ledger shows RRR-77 unmatched; asking the Bursary.", "internal", true)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/comments", Map.of("body", "We have found the payment and are matching it now.", "internal", false)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> resolved = it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/resolve",
                Map.of("summary", "Payment matched", "details", "The payment was matched to the ledger and the receipt reissued to the student."));
        assertThat(resolved.getStatusCode().value()).as(String.valueOf(resolved.getBody())).isEqualTo(200);

        // the student sees the update but never the internal note
        ResponseEntity<Map> mine = it.get(studentToken, "/api/v1/helpdesk/my/tickets/" + id);
        assertThat(mine.getStatusCode().value()).isEqualTo(200);
        List<Map> comments = (List<Map>) path(mine.getBody(), "comments");
        assertThat(comments).extracting(c -> c.get("body")).doesNotContain("Ledger shows RRR-77 unmatched; asking the Bursary.");
        assertThat(comments).extracting(c -> c.get("body")).contains("We have found the payment and are matching it now.");
        List<Map> timeline = (List<Map>) path(mine.getBody(), "timeline");
        assertThat(timeline).extracting(e -> e.get("action")).doesNotContain("INTERNAL_NOTE");
        assertThat(path(mine.getBody(), "status")).isEqualTo("RESOLVED");

        // not satisfied: reopened on a reason (and only on a reason); resolved again; confirmed; closed with the history complete
        assertThat(it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets/" + id + "/reopen", Map.of("reason", "")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets/" + id + "/reopen", Map.of("reason", "The receipt still shows the old amount.")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/status", Map.of("status", "IN_PROGRESS")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/tickets/" + id + "/resolve",
                Map.of("summary", "Receipt corrected", "details", "The receipt was regenerated with the amount as paid; the student can print it again.")).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> confirmed = it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets/" + id + "/confirm", Map.of());
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
        ResponseEntity<Map> after = it.get(agent, "/api/v1/helpdesk/tickets/" + id);
        assertThat(path(after.getBody(), "status")).isEqualTo("CLOSED");
        assertThat(path(after.getBody(), "closed_by_kind")).isEqualTo("REQUESTER");
        List<Map> history = (List<Map>) path(after.getBody(), "timeline");
        assertThat(history).extracting(e -> e.get("action")).contains("SUBMITTED", "OPENED", "ASSIGNED", "STATUS_CHANGED", "INTERNAL_NOTE", "UPDATE", "RESOLUTION", "REOPENED", "CLOSED", "ATTACHMENT");

        // a closed ticket takes no more updates
        assertThat(it.call(studentToken, HttpMethod.POST, "/api/v1/helpdesk/my/tickets/" + id + "/comments", Map.of("body", "One more thing")).getStatusCode().value()).isEqualTo(422);

        // the desk's queue finds it by number and by payment reference; the figures count it
        ResponseEntity<Map> byRef = it.get(director, "/api/v1/helpdesk/tickets?q=RRR-77&status=all");
        assertThat(byRef.getStatusCode().value()).isEqualTo(200);
        assertThat(((List<Map>) path(byRef.getBody(), "rows"))).extracting(r -> r.get("number")).contains(number);
        ResponseEntity<Map> stats = it.get(director, "/api/v1/helpdesk/stats");
        assertThat(stats.getStatusCode().value()).isEqualTo(200);
        assertThat(((Number) ((Map) path(stats.getBody(), "totals")).get("total")).longValue()).isGreaterThanOrEqualTo(1L);

        // a student cannot reach the desk
        assertThat(it.get(studentToken, "/api/v1/helpdesk/tickets").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(studentToken, "/api/v1/helpdesk/tickets/" + id).getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void theDirectorKeepsCategoriesAndSettingsAndAnAgentCannot() {
        assertThat(it.get(agent, "/api/v1/helpdesk/admin/categories").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> made = it.call(director, HttpMethod.POST, "/api/v1/helpdesk/admin/categories", Map.of(
                "name", "Printing " + UUID.randomUUID().toString().substring(0, 6), "suggestedPriority", "LOW",
                "fields", List.of(Map.of("key", "printer", "label", "Which printer", "type", "select", "required", true, "options", List.of("Library", "Registry")))));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        String id = String.valueOf(path(made.getBody(), "id"));
        ResponseEntity<Map> off = it.call(director, HttpMethod.PUT, "/api/v1/helpdesk/admin/categories/" + id, Map.of("name", "Printing (retired)", "active", false, "suggestedPriority", "LOW", "fields", List.of()));
        assertThat(off.getStatusCode().value()).as(String.valueOf(off.getBody())).isEqualTo(200);
        ResponseEntity<Map> settings = it.call(director, HttpMethod.PUT, "/api/v1/helpdesk/admin/settings", Map.of("autoCloseDays", 14, "notifyAgentsOnNew", true,
                "sla", List.of(Map.of("priority", "URGENT", "firstResponseHours", 1, "resolutionHours", 12))));
        assertThat(settings.getStatusCode().value()).as(String.valueOf(settings.getBody())).isEqualTo(200);
        assertThat(path(settings.getBody(), "auto_close_days")).isEqualTo(14);
        ResponseEntity<Map> bad = it.call(director, HttpMethod.PUT, "/api/v1/helpdesk/admin/settings", Map.of("sla", List.of(Map.of("priority", "HIGH", "firstResponseHours", 10, "resolutionHours", 5))));
        assertThat(bad.getStatusCode().value()).isEqualTo(422);
        it.call(director, HttpMethod.PUT, "/api/v1/helpdesk/admin/settings", Map.of("notifyAgentsOnNew", true));
    }
}
