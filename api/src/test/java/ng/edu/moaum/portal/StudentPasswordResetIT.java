package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * A student's password reset to the matriculation number at the ICT Support Desk (V485), end to end: the desk reads the account
 * (never a hash) and resets it on the student's ticket; a second click is the same reset; the student signs in with the
 * matriculation number, reaches nothing but the change until it is made (the server refuses the rest), changes it, and from then
 * the number opens nothing while the new password does; a later reset ends the sessions the student holds and leaves a locked
 * account locked unless the agent unlocks it; a posting without the capability, a student outside the posting's scope, another
 * office and a student without a matriculation number are refused; the policy's ticket rule, hourly limit and switch hold. Each
 * run uses its own students. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentPasswordResetIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private ResponseEntity<Map> reset(String token, UUID student, Map<String, Object> body) {
        return it.call(token, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + student + "/password", body);
    }

    private Map<String, Object> body(String reason, Object... more) {
        Map<String, Object> m = new HashMap<>(Map.of("method", "DEFAULT", "reason", reason));
        for (int i = 0; i + 1 < more.length; i += 2) m.put(String.valueOf(more[i]), more[i + 1]);
        return m;
    }

    private void policy(String head, boolean enabled, String ticket, int hourly) {
        ResponseEntity<Map> r = it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/settings/password-reset",
                Map.of("enabled", enabled, "unlockByDefault", true, "ticket", ticket, "hourly", hourly,
                       "statuses", List.of("ACTIVE", "PROBATION", "DEFERRED", "DORMANT", "GRADUATED")));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
    }

    @Test
    void ictSupportResetsAStudentToTheMatriculationNumberAndTheChangeIsForcedOnTheServer() {
        int n = 10000 + new Random().nextInt(89999);
        String matric = "MOAU/SC/PWR/26/" + n;
        UUID student = it.student("ZZPWR" + n, "C00023", "MOAUM/ADM/86/" + (800000 + n), matric, 400);
        UUID outside = it.student("ZZPWRO" + n, "C00001", "MOAUM/ADM/86/" + (900000 + n), "MOAU/ED/PWR/26/" + n, 200);
        UUID unmatriculated = it.student("ZZPWRA" + n, "C00023", "MOAUM/ADM/86/" + (700000 + n), null, 100);
        UUID agent = it.person("ZZ-PWR-AGENT", "ZZPWRAGENT");
        UUID viewer = it.person("ZZ-PWR-VIEWER", "ZZPWRVIEWER");
        String agentTok = TestTokens.token(agent, List.of("ictagent"));
        String viewerTok = TestTokens.token(viewer, List.of("ictagent"));
        String head = TestTokens.token(it.person("ZZ-PWR-HEAD", "ZZPWRHEAD"), List.of("helpdeskhead"));
        it.db(() -> {
            jdbc.sql("DELETE FROM helpdesk.agent_assignment WHERE person_id IN (:a, :b)").param("a", agent).param("b", viewer).update();
            // a CPO over the Faculty of Science who resets passwords, and one who only reads records
            jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                    VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','RESET_PASSWORD','CREATE_TICKET','VIEW_SUPPORT_AUDIT'])
                    """).param("p", agent).update();
            jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT'])")
                    .param("p", viewer).update();
            jdbc.sql("""
                    INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08022224444', :e, now())
                    ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email
                    """).param("s", student).param("e", "zzpwr" + n + "@example.com").update();
            return null;
        });
        String base = "/api/v1/helpdesk/support/students/" + student;
        policy(head, true, "OPTIONAL", 30);
        try {
            // TEST 1 · the student found and read before the reset: the record and the account, never a hash
            ResponseEntity<Map> state = it.get(agentTok, base + "/password");
            assertThat(state.getStatusCode().value()).as(String.valueOf(state.getBody())).isEqualTo(200);
            assertThat(state.getBody()).containsEntry("eligible", true).containsEntry("username", matric).containsEntry("has_account", false).containsEntry("mayReset", true);
            assertThat(String.valueOf(state.getBody())).doesNotContain("$2a$").doesNotContain("password_hash");

            // TEST 8 · a posting without the capability, another office; TEST 9 · a student outside the posting's scope
            assertThat(it.get(viewerTok, base + "/password").getBody()).containsEntry("mayReset", false);
            ResponseEntity<Map> noCap = reset(viewerTok, student, body("Student forgot portal password"));
            assertThat(noCap.getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
            assertThat(reset(TestTokens.token(UUID.randomUUID(), List.of("bursar")), student, body("Student forgot portal password")).getStatusCode().value()).isEqualTo(403);
            assertThat(reset(agentTok, outside, body("Student forgot portal password")).getStatusCode().value()).isEqualTo(404);
            // TEST 10 · no matriculation number, no reset to it; TEST 13 · a reason, in words
            ResponseEntity<Map> noMatric = reset(agentTok, unmatriculated, body("Student forgot portal password"));
            assertThat(noMatric.getBody().get("code")).isEqualTo("RESET_NO_MATRIC");
            assertThat(String.valueOf(noMatric.getBody().get("detail"))).startsWith("THIS STUDENT DOES NOT HAVE A VALID MATRICULATION NUMBER");
            assertThat(reset(agentTok, student, body("forgot")).getBody().get("code")).isEqualTo("SUPPORT_REASON_SHORT");
            assertThat(reset(agentTok, student, body("  ")).getStatusCode().value()).isEqualTo(400);

            // TEST 2, 12 · the reset, on the student's ticket
            ResponseEntity<Map> raised = it.call(agentTok, HttpMethod.POST, base + "/tickets",
                    Map.of("category", "LOGIN", "subject", "Cannot sign in", "description", "The student cannot log into the portal", "details",
                           Map.of("account_type", "Student portal", "username", matric, "error", "Wrong password")));
            assertThat(raised.getStatusCode().value()).as(String.valueOf(raised.getBody())).isEqualTo(200);
            String ticket = String.valueOf(raised.getBody().get("id"));
            ResponseEntity<Map> done = reset(agentTok, student, body("Student forgot portal password", "ticket", ticket));
            assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
            assertThat(done.getBody()).containsEntry("method", "DEFAULT_CREDENTIAL").containsEntry("alreadyDone", false);
            // TEST 14 · no password in the answer, the account, the ledger or the ticket
            assertThat(String.valueOf(done.getBody()).toUpperCase()).doesNotContain(matric);
            Map<String, Object> acc = jdbc.sql("""
                    SELECT must_change, temp_expires_at IS NULL AS no_temp, support_reset_at IS NOT NULL AS by_support,
                           password_hash = crypt(:m, password_hash) AS hash_is_number, password_hash = crypt(lower(:m), password_hash) AS hash_is_lower
                      FROM iam.student_account WHERE student_id = :s
                    """).param("s", student).param("m", matric).query().singleRow();
            assertThat(acc).containsEntry("must_change", true).containsEntry("no_temp", true).containsEntry("by_support", true)
                    .containsEntry("hash_is_number", false).containsEntry("hash_is_lower", false);
            List<Map<String, Object>> ledger = jdbc.sql("""
                    SELECT action, method, old_value, new_value, ticket_id::text AS ticket, agent_office, reason FROM helpdesk.support_action
                     WHERE student_id = :s ORDER BY at
                    """).param("s", student).query().listOfRows();
            assertThat(ledger).extracting(r -> r.get("action")).containsExactly("TICKET_CREATED", "PASSWORD_RESET");
            assertThat(ledger.get(1)).containsEntry("method", "DEFAULT_CREDENTIAL").containsEntry("ticket", ticket).containsEntry("agent_office", "ictagent")
                    .containsEntry("reason", "Student forgot portal password");
            assertThat(ledger.get(1).get("old_value")).isNull();
            assertThat(ledger.get(1).get("new_value")).isNull();
            assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = CAST(:t AS uuid) AND action = 'SUPPORT_PASSWORD_RESET'")
                    .param("t", ticket).query(Long.class).single()).isEqualTo(1L);
            assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = CAST(:t AS uuid) AND upper(coalesce(detail, '')) LIKE '%' || :m || '%'")
                    .param("t", ticket).param("m", matric).query(Long.class).single()).isZero();
            // TEST 11 · a second click is the same reset
            ResponseEntity<Map> again = reset(agentTok, student, body("Student forgot portal password", "ticket", ticket));
            assertThat(again.getBody()).containsEntry("alreadyDone", true);
            assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND action = 'PASSWORD_RESET'").param("s", student).query(Long.class).single()).isEqualTo(1L);

            // TEST 3 · the student signs in with the matriculation number as both; TEST 4 · nothing opens but the change
            ResponseEntity<Map> signIn = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", matric));
            assertThat(signIn.getStatusCode().value()).as(String.valueOf(signIn.getBody())).isEqualTo(200);
            assertThat(signIn.getBody().get("mustChange")).isEqualTo(true);
            String t1 = String.valueOf(signIn.getBody().get("token"));
            ResponseEntity<Map> gated = it.get(t1, "/api/v1/me");
            assertThat(gated.getStatusCode().value()).isEqualTo(403);
            assertThat(gated.getBody().get("code")).isEqualTo("PASSWORD_CHANGE_REQUIRED");
            assertThat(gated.getHeaders().getFirst("X-Password-Change")).isEqualTo("REQUIRED");
            assertThat(it.get(t1, "/api/v1/student-auth/password-status").getBody()).containsEntry("mustChange", true).containsEntry("resetBySupport", true);
            assertThat(it.get(t1, "/api/v1/iam/session").getStatusCode().is2xxSuccessful()).isTrue();

            // TEST 5 · the change, under the student's own rule: never the number, or the number inside
            assertThat(it.call(t1, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", matric, "next", matric + "!x")).getBody().get("code"))
                    .isEqualTo("AUTH_PASSWORD_IS_NUMBER");
            ResponseEntity<Map> changed = it.call(t1, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", matric, "next", "Zebra-Lamp-4471"));
            assertThat(changed.getStatusCode().value()).as(String.valueOf(changed.getBody())).isEqualTo(200);
            assertThat(it.get(t1, "/api/v1/me").getStatusCode().value()).isEqualTo(200);
            assertThat(it.get(t1, "/api/v1/student-auth/password-status").getBody()).containsEntry("mustChange", false).containsEntry("resetBySupport", false);

            // TEST 6 · the number opens nothing now; TEST 7 · the new password does, to the portal
            ResponseEntity<Map> old = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", matric));
            assertThat(old.getBody().get("code")).isEqualTo("AUTH_FIRST_PASSWORD_RETIRED");
            assertThat(String.valueOf(old.getBody())).doesNotContain("first password");
            ResponseEntity<Map> fresh = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "Zebra-Lamp-4471"));
            assertThat(fresh.getBody().get("mustChange")).isEqualTo(false);
            String t2 = String.valueOf(fresh.getBody().get("token"));
            assertThat(it.get(t2, "/api/v1/me").getStatusCode().value()).isEqualTo(200);

            // TEST 15 · a later reset ends the sessions the student holds; a locked account stays locked unless the agent unlocks it
            it.db(() -> jdbc.sql("UPDATE iam.student_account SET failed_attempts = 5, locked_until = now() + interval '15 minutes' WHERE student_id = :s")
                    .param("s", student).update());
            ResponseEntity<Map> kept = reset(agentTok, student, body("Account locked after failed sign-ins", "unlock", false));
            assertThat(kept.getBody()).containsEntry("wasLocked", true).containsEntry("unlocked", false);
            assertThat(((Number) kept.getBody().get("sessionsEnded")).intValue()).isGreaterThanOrEqualTo(2);
            assertThat(it.get(t2, "/api/v1/iam/session").getStatusCode().value()).isEqualTo(401);
            assertThat(jdbc.sql("SELECT locked_until > now() FROM iam.student_account WHERE student_id = :s").param("s", student).query(Boolean.class).single()).isTrue();
            it.db(() -> jdbc.sql("UPDATE iam.student_account SET support_reset_at = now() - interval '5 minutes' WHERE student_id = :s").param("s", student).update());
            ResponseEntity<Map> unlocked = reset(agentTok, student, body("Account locked after failed sign-ins", "unlock", true));
            assertThat(unlocked.getBody()).containsEntry("unlocked", true);
            assertThat(jdbc.sql("SELECT locked_until IS NULL AND failed_attempts = 0 FROM iam.student_account WHERE student_id = :s").param("s", student).query(Boolean.class).single()).isTrue();
            assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND action = 'ACCOUNT_UNLOCKED'").param("s", student).query(Long.class).single()).isEqualTo(1L);

            // the history: every reset and unlock, in Authentication, with its method — never a password
            ResponseEntity<Map> history = it.get(agentTok, "/api/v1/helpdesk/support/actions?module=AUTHENTICATION&size=200");
            List<Map<String, Object>> mine = ((List<Map<String, Object>>) history.getBody().get("rows")).stream()
                    .filter(r -> String.valueOf(student).equals(String.valueOf(r.get("student_id")))).toList();
            assertThat(mine).extracting(r -> r.get("action") + "/" + r.get("method"))
                    .contains("PASSWORD_RESET/DEFAULT_CREDENTIAL", "ACCOUNT_UNLOCKED/null");
            assertThat(String.valueOf(history.getBody())).doesNotContain("$2a$").doesNotContain("Zebra-Lamp-4471");

            // the policy: a ticket required, the hourly limit, the switch
            it.db(() -> jdbc.sql("UPDATE iam.student_account SET support_reset_at = now() - interval '5 minutes' WHERE student_id = :s").param("s", student).update());
            policy(head, true, "REQUIRED", 30);
            assertThat(reset(agentTok, student, body("Student forgot portal password")).getBody().get("code")).isEqualTo("SUPPORT_TICKET_REQUIRED");
            policy(head, true, "OPTIONAL", 1);
            assertThat(reset(agentTok, student, body("Student forgot portal password")).getBody().get("code")).isEqualTo("SUPPORT_RESET_RATE");
            policy(head, false, "OPTIONAL", 30);
            assertThat(it.get(agentTok, base + "/password").getBody()).containsEntry("refusal", "RESET_DISABLED");
            assertThat(reset(agentTok, student, body("Student forgot portal password")).getBody().get("code")).isEqualTo("RESET_DISABLED");
        } finally {
            policy(head, true, "OPTIONAL", 30);
        }
    }
}
