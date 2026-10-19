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
 * V559: bulk student password reset at the ICT Support Desk, end to end. A CPO over the Faculty of Science with the bulk
 * capability finds the students (the students with an open Login Issues ticket among them), sees which of those chosen may be
 * reset and why not, and resets them in one operation (BPR/…): each eligible student is put on the default credential by the one
 * reset service — signs in with the matriculation number and must change it — on the support ledger naming the operation and on
 * the student's login ticket; a student without a matriculation number and one outside the posting's scope fail with their reason
 * and leave the rest reset; the same request again is the same operation; another posting without the capability and another
 * office are refused; the Head reaches the University; no password or hash is sent; the history lists it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class BulkPasswordResetIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static final String BASE = "/api/v1/helpdesk/support/password-reset/bulk";

    private Map<String, Object> waitFor(ItSupport it, String token, String id) throws InterruptedException {
        Map<String, Object> op = null;
        for (int i = 0; i < 120; i++) {
            op = it.get(token, BASE + "/" + id).getBody();
            String status = String.valueOf(op.get("status"));
            if (!"PENDING".equals(status) && !"PROCESSING".equals(status)) return op;
            Thread.sleep(500);
        }
        return op;
    }

    @Test
    void ictSupportResetsManyStudentsAtOnceEachCheckedAndTheChangeForced() throws InterruptedException {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        String m1 = "MOAU/SC/BPR/26/" + n, m2 = "MOAU/SC/BPS/26/" + n;
        UUID s1 = it.student("ZZBPRA" + n, "C00023", "MOAUM/ADM/87/" + (100000 + n), m1, 200);
        UUID s2 = it.student("ZZBPRB" + n, "C00023", "MOAUM/ADM/87/" + (200000 + n), m2, 300);
        UUID noMatric = it.student("ZZBPRC" + n, "C00023", "MOAUM/ADM/87/" + (300000 + n), null, 100);
        UUID outside = it.student("ZZBPRD" + n, "C00001", "MOAUM/ADM/87/" + (400000 + n), "MOAU/ED/BPR/26/" + n, 200);
        UUID agent = it.person("ZZ-BPR-AG-" + n, "ZZBPRAG" + n);
        UUID plain = it.person("ZZ-BPR-PL-" + n, "ZZBPRPL" + n);
        String agentTok = TestTokens.token(agent, List.of("ictagent"));
        String plainTok = TestTokens.token(plain, List.of("ictagent"));
        String head = TestTokens.token(it.person("ZZ-BPR-HD-" + n, "ZZBPRHD" + n), List.of("helpdeskhead"));
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                    VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','RESET_PASSWORD','CREATE_TICKET','BULK_RESET_PASSWORD'])
                    """).param("p", agent).update();
            jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','RESET_PASSWORD'])")
                    .param("p", plain).update();
            jdbc.sql("""
                    INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08022225555', :e, now())
                    ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email
                    """).param("s", s2).param("e", "zzbpr" + n + "@example.com").update();
            return null;
        });
        // a login ticket for one of them, raised at the desk
        ResponseEntity<Map> raised = it.call(agentTok, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + s2 + "/tickets",
                Map.of("category", "LOGIN", "subject", "Cannot sign in", "description", "The student cannot log into the portal",
                       "details", Map.of("account_type", "Student portal", "username", m2, "error", "Wrong password")));
        assertThat(raised.getStatusCode().value()).as(String.valueOf(raised.getBody())).isEqualTo(200);
        String ticket = String.valueOf(raised.getBody().get("id"));

        // the capability, and the office
        assertThat(it.get(plainTok, BASE + "/candidates?q=ZZBPR").getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
        assertThat(it.call(TestTokens.token(UUID.randomUUID(), List.of("bursar")), HttpMethod.POST, BASE + "/preview", Map.of("studentIds", List.of(s1))).getStatusCode().value())
                .isEqualTo(403);

        // the students found within the posting's scope, the login issues among them
        Map<String, Object> found = it.get(agentTok, BASE + "/candidates?q=ZZBPR" + "&size=50").getBody();
        List<Map<String, Object>> rows = (List<Map<String, Object>>) found.get("rows");
        assertThat(rows).extracting(r -> r.get("id")).contains(s1.toString(), s2.toString(), noMatric.toString()).doesNotContain(outside.toString());
        Map<String, Object> logins = it.get(agentTok, BASE + "/candidates?login=true&q=ZZBPRB" + n).getBody();
        assertThat((List<Map<String, Object>>) logins.get("rows")).singleElement().satisfies(r -> {
            assertThat(r.get("id")).isEqualTo(s2.toString());
            assertThat(r.get("ticket_id")).isEqualTo(ticket);
        });
        Map<String, Object> every = it.get(agentTok, BASE + "/candidates?all=true&q=ZZBPR").getBody();
        assertThat((List<String>) every.get("ids")).contains(s1.toString(), s2.toString(), noMatric.toString());

        // the preview: who may be reset, and why not the others
        List<UUID> chosen = List.of(s1, s2, noMatric, outside);
        Map<String, Object> preview = it.call(agentTok, HttpMethod.POST, BASE + "/preview", Map.of("studentIds", chosen)).getBody();
        assertThat(preview).containsEntry("selected", 4).containsEntry("eligible", 2).containsEntry("notEligible", 2);
        Map<String, String> codes = new HashMap<>();
        ((List<Map<String, Object>>) preview.get("rows")).forEach(r -> codes.put(String.valueOf(r.get("student_id")), String.valueOf(r.get("code"))));
        assertThat(codes).containsEntry(s1.toString(), "ELIGIBLE").containsEntry(noMatric.toString(), "RESET_NO_MATRIC").containsEntry(outside.toString(), "OUT_OF_SCOPE");
        // the student outside the scope is never described
        assertThat(((List<Map<String, Object>>) preview.get("rows")).stream().filter(r -> outside.toString().equals(r.get("student_id"))).findFirst().orElseThrow().get("full_name")).isNull();

        // a reason, in words
        assertThat(it.call(agentTok, HttpMethod.POST, BASE, Map.of("studentIds", chosen, "reason", "login")).getBody().get("code")).isEqualTo("SUPPORT_REASON_SHORT");

        // the operation
        String key = "it-" + n;
        Map<String, Object> body = new HashMap<>(Map.of("studentIds", chosen, "reason", "Students reported login issues at the desk", "key", key,
                "tickets", Map.of(s2.toString(), ticket)));
        ResponseEntity<Map> started = it.call(agentTok, HttpMethod.POST, BASE, body);
        assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
        String id = String.valueOf(started.getBody().get("id"));
        assertThat(String.valueOf(started.getBody().get("reference"))).matches("BPR/\\d{4}/\\d{6}");
        Map<String, Object> op = waitFor(it, agentTok, id);
        assertThat(op).containsEntry("status", "COMPLETED_WITH_EXCEPTIONS").containsEntry("total", 4).containsEntry("succeeded", 2).containsEntry("failed", 2);
        Map<String, String> results = new HashMap<>();
        ((List<Map<String, Object>>) op.get("items")).forEach(r -> results.put(String.valueOf(r.get("student_id")), r.get("status") + ":" + r.get("failure_code")));
        assertThat(results).containsEntry(s1.toString(), "RESET:null").containsEntry(s2.toString(), "RESET:null")
                .containsEntry(noMatric.toString(), "FAILED:RESET_NO_MATRIC").containsEntry(outside.toString(), "FAILED:OUT_OF_SCOPE");
        assertThat(String.valueOf(op)).doesNotContain("$2a$").doesNotContain("password_hash");

        // the same request again is the same operation, nothing reset twice
        ResponseEntity<Map> again = it.call(agentTok, HttpMethod.POST, BASE, body);
        assertThat(again.getBody()).containsEntry("id", id).containsEntry("repeat", true);
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id IN (:a, :b) AND action = 'PASSWORD_RESET'")
                .param("a", s1).param("b", s2).query(Long.class).single()).isEqualTo(2L);

        // each reset as the single reset makes it: first password, must change, never the number's hash; on the ledger and the ticket
        Map<String, Object> acc = jdbc.sql("""
                SELECT must_change, support_reset_at IS NOT NULL AS by_support, password_hash = crypt(:m, password_hash) AS hash_is_number
                  FROM iam.student_account WHERE student_id = :s
                """).param("s", s1).param("m", m1).query().singleRow();
        assertThat(acc).containsEntry("must_change", true).containsEntry("by_support", true).containsEntry("hash_is_number", false);
        Map<String, Object> ledger = jdbc.sql("SELECT method, summary, ticket_id::text AS ticket, reason FROM helpdesk.support_action WHERE student_id = :s AND action = 'PASSWORD_RESET'")
                .param("s", s2).query().singleRow();
        assertThat(ledger).containsEntry("method", "DEFAULT_CREDENTIAL").containsEntry("ticket", ticket).containsEntry("reason", "Students reported login issues at the desk");
        assertThat(String.valueOf(ledger.get("summary"))).contains(String.valueOf(started.getBody().get("reference")));
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s").param("s", noMatric).query(Long.class).single()).isZero();
        ResponseEntity<Map> signIn = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", m1, "password", m1));
        assertThat(signIn.getStatusCode().value()).as(String.valueOf(signIn.getBody())).isEqualTo(200);
        assertThat(signIn.getBody().get("mustChange")).isEqualTo(true);
        assertThat(it.get(String.valueOf(signIn.getBody().get("token")), "/api/v1/me").getStatusCode().value()).isEqualTo(403);
        // nothing else of the student changed
        assertThat(jdbc.sql("SELECT matric_no || '|' || current_level || '|' || status FROM people.student WHERE id = :s").param("s", s1).query(String.class).single())
                .isEqualTo(m1 + "|200|ACTIVE");

        // the Head reaches the University; the history lists the operation
        Map<String, Object> headPreview = it.call(head, HttpMethod.POST, BASE + "/preview", Map.of("studentIds", List.of(outside))).getBody();
        assertThat(headPreview).containsEntry("eligible", 1);
        Map<String, Object> history = it.get(agentTok, BASE + "?q=ZZBPRAG" + n).getBody();
        assertThat((List<Map<String, Object>>) history.get("rows")).singleElement().satisfies(r -> {
            assertThat(r.get("id")).isEqualTo(id);
            assertThat(r.get("status")).isEqualTo("COMPLETED_WITH_EXCEPTIONS");
        });
        assertThat(it.get(agentTok, BASE + "/summary").getBody()).containsEntry("mayBulk", true);
    }

    /**
     * V563: the login ticket resolved with the reset; the reset link for the student without a matriculation number; the students
     * not reset tried again once the number is issued; an operation above the figure waits for a Head other than the one who asked,
     * approved (it runs) or declined (no one reset); the Head's counts keep the bulk resets apart.
     */
    @Test
    void ticketsResolvedLinksSentRetriedAndALargeOneApproved() throws InterruptedException {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        UUID s1 = it.student("ZZBPVA" + n, "C00023", "MOAUM/ADM/88/" + (100000 + n), "MOAU/SC/BPV/26/" + n, 200);
        UUID noMatric = it.student("ZZBPVB" + n, "C00023", "MOAUM/ADM/88/" + (200000 + n), null, 100);
        UUID s3 = it.student("ZZBPVC" + n, "C00023", "MOAUM/ADM/88/" + (300000 + n), "MOAU/SC/BPW/26/" + n, 200);
        UUID s4 = it.student("ZZBPVD" + n, "C00023", "MOAUM/ADM/88/" + (400000 + n), "MOAU/SC/BPX/26/" + n, 300);
        UUID s5 = it.student("ZZBPVE" + n, "C00023", "MOAUM/ADM/88/" + (500000 + n), "MOAU/SC/BPZ/26/" + n, 300);
        UUID s6 = it.student("ZZBPVF" + n, "C00023", "MOAUM/ADM/88/" + (600000 + n), "MOAU/SC/BQA/26/" + n, 400);
        UUID agent = it.person("ZZ-BPV-AG-" + n, "ZZBPVAG" + n);
        String agentTok = TestTokens.token(agent, List.of("ictagent"));
        String head = TestTokens.token(it.person("ZZ-BPV-HD-" + n, "ZZBPVHD" + n), List.of("helpdeskhead"));
        Integer before = jdbc.sql("SELECT bulk_reset_approval_over FROM helpdesk.setting WHERE row_no").query(Integer.class).optional().orElse(null);
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                    VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','RESET_PASSWORD','CREATE_TICKET','BULK_RESET_PASSWORD'])
                    """).param("p", agent).update();
            jdbc.sql("""
                    INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, NULL, :e, now())
                    ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email
                    """).param("s", noMatric).param("e", "zzbpv" + n + "@example.com").update();
            // the ticket's updates go to the student's e-mail
            jdbc.sql("""
                    INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08022226666', :e, now())
                    ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email
                    """).param("s", s1).param("e", "zzbpva" + n + "@example.com").update();
            jdbc.sql("UPDATE helpdesk.setting SET bulk_reset_approval_over = 3 WHERE row_no").update();
            return null;
        });
        try {
            ResponseEntity<Map> raised = it.call(agentTok, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + s1 + "/tickets",
                    Map.of("category", "LOGIN", "subject", "Cannot sign in", "description", "The student cannot log into the portal",
                           "details", Map.of("account_type", "Student portal", "username", "MOAU/SC/BPV/26/" + n, "error", "Wrong password")));
            assertThat(raised.getStatusCode().value()).as(String.valueOf(raised.getBody())).isEqualTo(200);
            String ticket = String.valueOf(raised.getBody().get("id"));

            // the login ticket resolved with the reset, in the words the students read
            String words = "Your portal password has been reset. Sign in with your matriculation number and choose your own password.";
            Map<String, Object> body = new HashMap<>(Map.of("studentIds", List.of(s1, noMatric), "reason", "Students reported login issues at the desk",
                    "key", "itv-" + n, "tickets", Map.of(s1.toString(), ticket), "resolveTickets", true, "resolution", words));
            ResponseEntity<Map> started = it.call(agentTok, HttpMethod.POST, BASE, body);
            assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
            String id = String.valueOf(started.getBody().get("id"));
            Map<String, Object> op = waitFor(it, agentTok, id);
            assertThat(op).containsEntry("status", "COMPLETED_WITH_EXCEPTIONS").containsEntry("resolve_tickets", true);
            Map<String, Object> t = jdbc.sql("SELECT status, resolution_details FROM helpdesk.ticket WHERE id = CAST(:t AS uuid)").param("t", ticket).query().singleRow();
            assertThat(t).containsEntry("status", "RESOLVED").containsEntry("resolution_details", words);
            // the student told of the resolution (by the ticket's e-mail), not by a second "password reset" message
            assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE recipient = :e AND subject LIKE 'Your ICT support ticket is resolved%'")
                    .param("e", "zzbpva" + n + "@example.com").query(Long.class).single()).isEqualTo(1L);
            assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :s AND subject = 'Your portal password was reset by ICT Support'")
                    .param("s", s1).query(Long.class).single()).isZero();
            assertThat(((List<Map<String, Object>>) op.get("items")).stream().filter(r -> s1.toString().equals(r.get("student_id"))).findFirst().orElseThrow().get("ticket_resolved_at")).isNotNull();
            // every act names the operation
            assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND bulk_id = CAST(:b AS uuid)").param("s", s1).param("b", id)
                    .query(Long.class).single()).isEqualTo(1L);

            // the reset link for the student without a matriculation number, once
            ResponseEntity<Map> links = it.call(agentTok, HttpMethod.POST, BASE + "/" + id + "/links", Map.of());
            assertThat(links.getStatusCode().value()).as(String.valueOf(links.getBody())).isEqualTo(200);
            assertThat(links.getBody()).containsEntry("sent", 1).containsEntry("notSent", 0);
            assertThat(String.valueOf(links.getBody())).doesNotContain("zzbpv" + n + "@example.com");   // masked
            assertThat(jdbc.sql("SELECT count(*) FROM iam.password_reset WHERE subject_kind = 'STUDENT' AND subject_id = :s").param("s", noMatric).query(Long.class).single()).isEqualTo(1L);
            assertThat(jdbc.sql("SELECT method FROM helpdesk.support_action WHERE student_id = :s AND bulk_id = CAST(:b AS uuid)").param("s", noMatric).param("b", id)
                    .query(String.class).single()).isEqualTo("RESET_LINK");
            assertThat(it.call(agentTok, HttpMethod.POST, BASE + "/" + id + "/links", Map.of()).getBody()).containsEntry("sent", 0);

            // the number issued, the student tried again as a new operation
            it.db(() -> jdbc.sql("UPDATE people.student SET matric_no = :m, status = 'ACTIVE', matriculated_at = now() WHERE id = :s").param("m", "MOAU/SC/BPY/26/" + n).param("s", noMatric).update());
            ResponseEntity<Map> retried = it.call(agentTok, HttpMethod.POST, BASE, Map.of("studentIds", List.of(noMatric), "reason", "Retry once the matriculation number was issued",
                    "key", "itv-retry-" + n, "retryOf", id));
            assertThat(retried.getStatusCode().value()).as(String.valueOf(retried.getBody())).isEqualTo(200);
            Map<String, Object> retry = waitFor(it, agentTok, String.valueOf(retried.getBody().get("id")));
            assertThat(retry).containsEntry("status", "COMPLETED").containsEntry("retry_of", id);
            assertThat((List<Map<String, Object>>) it.get(agentTok, BASE + "/" + id).getBody().get("retries")).singleElement()
                    .satisfies(r -> assertThat(r.get("id")).isEqualTo(retried.getBody().get("id")));

            // above the figure an operation waits for a Head other than the one who asked
            List<UUID> four = List.of(s3, s4, s5, s6);
            ResponseEntity<Map> large = it.call(agentTok, HttpMethod.POST, BASE, Map.of("studentIds", four, "reason", "A class could not sign in after the move", "key", "itv-large-" + n));
            String largeId = String.valueOf(large.getBody().get("id"));
            assertThat(large.getBody()).containsEntry("status", "AWAITING_APPROVAL").containsEntry("approval_over", 3);
            Thread.sleep(1500);
            assertThat(it.get(agentTok, BASE + "/" + largeId).getBody()).containsEntry("status", "AWAITING_APPROVAL").containsEntry("mayDecide", false);
            assertThat(it.call(agentTok, HttpMethod.POST, BASE + "/" + largeId + "/approve", Map.of()).getBody().get("code")).isEqualTo("BULK_APPROVAL_HEAD");
            assertThat(it.get(head, BASE + "/" + largeId).getBody()).containsEntry("mayDecide", true);
            assertThat(it.call(head, HttpMethod.POST, BASE + "/" + largeId + "/approve", Map.of("note", "Identities checked by the CPO")).getBody())
                    .containsEntry("status", "PENDING").containsEntry("decision_note", "Identities checked by the CPO");
            assertThat(waitFor(it, agentTok, largeId)).containsEntry("status", "COMPLETED").containsEntry("succeeded", 4);
            // declined on a reason: nobody reset
            ResponseEntity<Map> declined = it.call(agentTok, HttpMethod.POST, BASE, Map.of("studentIds", four, "reason", "A class could not sign in after the move", "key", "itv-no-" + n));
            String noId = String.valueOf(declined.getBody().get("id"));
            assertThat(it.call(head, HttpMethod.POST, BASE + "/" + noId + "/reject", Map.of()).getBody().get("code")).isEqualTo("SUPPORT_REASON_SHORT");
            assertThat(it.call(head, HttpMethod.POST, BASE + "/" + noId + "/reject", Map.of("note", "Not every identity was checked")).getBody())
                    .containsEntry("status", "REJECTED").containsEntry("succeeded", 0).containsEntry("failed", 4);
            assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE bulk_id = CAST(:b AS uuid)").param("b", noId).query(Long.class).single()).isZero();

            // the Head's counts: these resets in bulk, apart from the single ones the alert counts
            Map<String, Object> mine = ((List<Map<String, Object>>) it.get(head, "/api/v1/helpdesk/admin/password-resets/by-agent").getBody().get("agents")).stream()
                    .filter(r -> agent.toString().equals(r.get("agent_id"))).findFirst().orElseThrow();
            assertThat(mine).containsEntry("today", 0).containsEntry("bulk_ops_today", 3);
            // one reset and one link in the first, one retried, four approved
            assertThat(((Number) mine.get("bulk_today")).intValue()).isEqualTo(7);
        } finally {
            it.db(() -> jdbc.sql("UPDATE helpdesk.setting SET bulk_reset_approval_over = :v WHERE row_no").param("v", before, java.sql.Types.INTEGER).update());
        }
    }
}
