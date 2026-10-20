package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * V582: password resets from support tickets, end to end. A CPO over the Faculty of Science with BULK_RESET_FROM_TICKETS filters
 * the queue to login and password tickets, takes every eligible one the filters find, and checks the tickets ticked: two login
 * tickets of one student (one reset), a course registration ticket (not eligible), a login ticket of a student with no
 * matriculation number (not reset, with why). The reset (PWR-TKT/…) resets the student once — on the default credential, the
 * change forced, no password returned — and resolves both tickets; the ticket left out stays open. A forged request naming a
 * course registration ticket resets nobody; the student bulk reset's capability does not give this one; the same request again
 * is the same operation; the ticket's history and the reports read it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class TicketPasswordResetIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static final String BASE = "/api/v1/helpdesk/tickets/password-reset";

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

    private String raise(ItSupport it, String token, UUID student, String category, String subject) {
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + student + "/tickets",
                Map.of("category", category, "subject", subject, "description", "Raised for the ticket reset check",
                       "details", "LOGIN".equals(category) ? Map.of("account_type", "Student portal", "username", "as on the record", "error", "Wrong password")
                               : Map.of("session", "2025/2026", "semester", "1", "level", "200")));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return String.valueOf(r.getBody().get("id"));
    }

    @Test
    void theStudentsOfTheLoginTicketsTickedAreResetOnceEachAndTheirTicketsResolved() throws InterruptedException {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        String m1 = "MOAU/SC/TKT/26/" + n;
        UUID s1 = it.student("ZZTKTA" + n, "C00023", "MOAUM/ADM/88/" + (100000 + n), m1, 200);
        UUID noMatric = it.student("ZZTKTB" + n, "C00023", "MOAUM/ADM/88/" + (200000 + n), null, 100);
        UUID agent = it.person("ZZ-TKT-AG-" + n, "ZZTKTAG" + n);
        UUID plain = it.person("ZZ-TKT-PL-" + n, "ZZTKTPL" + n);
        String agentTok = TestTokens.token(agent, List.of("ictagent"));
        String plainTok = TestTokens.token(plain, List.of("ictagent"));
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                    VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','RESET_PASSWORD','CREATE_TICKET','BULK_RESET_FROM_TICKETS'])
                    """).param("p", agent).update();
            // the student bulk reset's capability, not this one
            jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                    VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','RESET_PASSWORD','BULK_RESET_PASSWORD'])
                    """).param("p", plain).update();
            // a ticket's updates go to the e-mail or phone on the record (made-up ones)
            for (UUID st : List.of(s1, noMatric)) {
                jdbc.sql("""
                        INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08022226666', :e, now())
                        ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email, phone = EXCLUDED.phone
                        """).param("s", st).param("e", "zztkt" + n + st.toString().substring(0, 4) + "@example.com").update();
            }
            return null;
        });
        String login1 = raise(it, agentTok, s1, "LOGIN", "Cannot sign in " + n);
        String login2 = raise(it, agentTok, s1, "LOGIN", "Forgot my password " + n);
        String registration = raise(it, agentTok, s1, "REGISTRATION", "Course will not register " + n);
        String loginNoMatric = raise(it, agentTok, noMatric, "LOGIN", "Cannot sign in " + n);
        // the course registration ticket is routed to its own queue: the agent is posted there too, so it is seen and refused as not a login ticket
        it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                SELECT :p, t.queue_code, 'FACULTY', 'SC', ARRAY['VIEW_STUDENT'] FROM helpdesk.ticket t
                 WHERE t.id = CAST(:t AS uuid) AND t.queue_code IS NOT NULL AND t.queue_code <> 'ICT_SUPPORT'
                """).param("p", agent).param("t", registration).update());

        // the queue filtered to login and password tickets: each row says where it stands
        Map<String, Object> queue = it.get(agentTok, "/api/v1/helpdesk/tickets?issue=login&q=" + n + "&size=50").getBody();
        Map<String, Object> states = new HashMap<>();
        ((List<Map<String, Object>>) queue.get("rows")).forEach(r -> states.put(String.valueOf(r.get("id")), r.get("reset_state")));
        assertThat(states).containsEntry(login1, "ELIGIBLE").containsEntry(login2, "ELIGIBLE").containsEntry(loginNoMatric, "ELIGIBLE").doesNotContainKey(registration);
        Map<String, Object> other = it.get(agentTok, "/api/v1/helpdesk/tickets?issue=other&q=" + n).getBody();
        assertThat((List<Map<String, Object>>) other.get("rows")).extracting(r -> r.get("id")).containsExactly(registration);
        Map<String, Object> every = it.get(agentTok, "/api/v1/helpdesk/tickets?issue=login&eligibleIds=true&q=" + n).getBody();
        assertThat((List<String>) every.get("ids")).containsExactlyInAnyOrder(login1, login2, loginNoMatric);

        // the capability: the student bulk reset's does not give it, another office has none of it
        assertThat(it.call(plainTok, HttpMethod.POST, BASE + "/validate", Map.of("ticketIds", List.of(login1))).getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
        assertThat(it.call(TestTokens.token(UUID.randomUUID(), List.of("bursar")), HttpMethod.POST, BASE + "/validate", Map.of("ticketIds", List.of(login1)))
                .getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(agentTok, BASE + "/summary").getBody()).containsEntry("may", true);
        assertThat(it.get(plainTok, BASE + "/summary").getBody()).containsEntry("may", false);

        // the check: one student for two tickets, the course registration ticket and the student without a number not reset
        List<String> ticked = List.of(login1, login2, registration, loginNoMatric);
        Map<String, Object> check = it.call(agentTok, HttpMethod.POST, BASE + "/validate", Map.of("ticketIds", ticked)).getBody();
        assertThat(check).containsEntry("selected", 4).containsEntry("eligible", 2).containsEntry("students", 1).containsEntry("consolidated", 1)
                .containsEntry("notEligible", 2);
        Map<String, String> codes = new HashMap<>();
        ((List<Map<String, Object>>) check.get("rows")).forEach(r -> codes.put(String.valueOf(r.get("ticket_id")), String.valueOf(r.get("code"))));
        assertThat(codes).containsEntry(login1, "ELIGIBLE").containsEntry(registration, "TICKET_NOT_LOGIN").containsEntry(loginNoMatric, "RESET_NO_MATRIC");
        assertThat((List<Map<String, Object>>) check.get("grouped")).singleElement().satisfies(g -> assertThat((List<String>) g.get("tickets")).hasSize(2));

        // a forged request naming only a course registration ticket resets nobody
        ResponseEntity<Map> forged = it.call(agentTok, HttpMethod.POST, BASE + "/execute",
                Map.of("ticketIds", List.of(registration), "reason", "Students login and password tickets"));
        assertThat(forged.getStatusCode().value()).isEqualTo(422);
        assertThat(forged.getBody()).containsEntry("code", "TICKET_RESET_NONE");

        // the reset: the student once, both tickets resolved, the change forced, no password returned
        Map<String, Object> body = Map.of("ticketIds", ticked, "reason", "Students login and password tickets at the desk", "key", "tkt-" + n);
        ResponseEntity<Map> started = it.call(agentTok, HttpMethod.POST, BASE + "/execute", body);
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        String id = String.valueOf(started.getBody().get("id"));
        assertThat(String.valueOf(started.getBody().get("reference"))).matches("PWR-TKT/\\d{4}/\\d{6}");
        Map<String, Object> op = waitFor(it, agentTok, id);
        assertThat(op).containsEntry("status", "COMPLETED").containsEntry("succeeded", 1).containsEntry("ticketCount", 2).containsEntry("students", 1)
                .containsEntry("consolidated", 1).containsEntry("resolved", 2);
        assertThat(String.valueOf(op)).doesNotContain("$2a$").doesNotContain("password_hash").doesNotContain("temporary password:");
        assertThat(jdbc.sql("SELECT string_agg(status, ',' ORDER BY number) FROM helpdesk.ticket WHERE id IN (CAST(:a AS uuid), CAST(:b AS uuid))")
                .param("a", login1).param("b", login2).query(String.class).single()).isEqualTo("RESOLVED,RESOLVED");
        assertThat(jdbc.sql("SELECT status FROM helpdesk.ticket WHERE id = CAST(:t AS uuid)").param("t", loginNoMatric).query(String.class).single()).isNotIn("RESOLVED", "CLOSED");
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND action = 'PASSWORD_RESET'").param("s", s1).query(Long.class).single()).isEqualTo(1L);
        Map<String, Object> acc = jdbc.sql("SELECT must_change, password_hash = crypt(:m, password_hash) AS hash_is_number FROM iam.student_account WHERE student_id = :s")
                .param("s", s1).param("m", m1).query().singleRow();
        assertThat(acc).containsEntry("must_change", true).containsEntry("hash_is_number", false);
        ResponseEntity<Map> signIn = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", m1, "password", m1));
        assertThat(signIn.getStatusCode().value()).as(String.valueOf(signIn.getBody())).isEqualTo(200);
        assertThat(signIn.getBody().get("mustChange")).isEqualTo(true);

        // the same request again is the same operation; a settled ticket is not reset again
        assertThat(it.call(agentTok, HttpMethod.POST, BASE + "/execute", body).getBody()).containsEntry("id", id);
        Map<String, Object> afterwards = it.call(agentTok, HttpMethod.POST, BASE + "/validate", Map.of("ticketIds", List.of(login1))).getBody();
        assertThat((List<Map<String, Object>>) afterwards.get("rows")).singleElement().satisfies(r -> assertThat(r.get("code")).isEqualTo("TICKET_SETTLED"));

        // the ticket's history and the reports
        List<Map<String, Object>> history = (List<Map<String, Object>>) (List<?>) it.getList(agentTok, BASE + "/history/" + login1).getBody();
        assertThat(history).extracting(h -> h.get("kind") + ":" + h.get("result")).contains("FROM_TICKETS:RESET");
        assertThat(String.valueOf(history)).doesNotContain(m1 + "\"");
        List<Map<String, Object>> report = (List<Map<String, Object>>) (List<?>) it.getList(agentTok, BASE + "/reports/operations").getBody();
        assertThat(report).filteredOn(r -> String.valueOf(op.get("reference")).equals(r.get("reference"))).hasSize(2);
        List<Map<String, Object>> issues = (List<Map<String, Object>>) (List<?>) it.getList(agentTok, BASE + "/reports/login-issues").getBody();
        assertThat(issues).extracting(r -> r.get("number")).contains(jdbc.sql("SELECT number FROM helpdesk.ticket WHERE id = CAST(:t AS uuid)").param("t", login1).query(String.class).single());
    }
}
