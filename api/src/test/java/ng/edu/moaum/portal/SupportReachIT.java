package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
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
 * V565, end to end: the desk raises a ticket for a student the record holds no e-mail or phone for — refused without a contact, then
 * with the phone the student gives, saved to the record (the ticket told by SMS); an agent without contact editing cannot save it;
 * the student was on the list of those the University cannot reach, and is off it once saved; the reset policy keeps what a save
 * does not name; the reset history reads single and bulk resets apart; a bulk reset of more than 1,000 is opened in parts and read
 * as a whole. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SupportReachIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static final String SUPPORT = "/api/v1/helpdesk/support";
    private static final String BULK = SUPPORT + "/password-reset/bulk";

    @Test
    void theDeskReachesStudentsWithNoContactAndResetsInPartsAndKeepsThePolicy() throws InterruptedException {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        UUID none = it.student("ZZRCHA" + n, "C00023", "MOAUM/ADM/89/" + (100000 + n), "MOAU/SC/RCH/26/" + n, 200);
        UUID other = it.student("ZZRCHB" + n, "C00023", "MOAUM/ADM/89/" + (200000 + n), "MOAU/SC/RCI/26/" + n, 300);
        UUID agent = it.person("ZZ-RCH-AG-" + n, "ZZRCHAG" + n);
        UUID plain = it.person("ZZ-RCH-PL-" + n, "ZZRCHPL" + n);
        String agentTok = TestTokens.token(agent, List.of("ictagent"));
        String plainTok = TestTokens.token(plain, List.of("ictagent"));
        String head = TestTokens.token(it.person("ZZ-RCH-HD-" + n, "ZZRCHHD" + n), List.of("helpdeskhead"));
        Map<String, Object> policyBefore = (Map<String, Object>) it.get(head, "/api/v1/helpdesk/admin/settings").getBody().get("passwordReset");
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                    VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','CREATE_TICKET','EDIT_CONTACT','RESET_PASSWORD','BULK_RESET_PASSWORD'])
                    """).param("p", agent).update();
            jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','CREATE_TICKET'])")
                    .param("p", plain).update();
            return null;
        });
        try {
            // on the list of the students the University cannot reach
            Map<String, Object> reach = it.get(agentTok, SUPPORT + "/reach?q=ZZRCHA" + n).getBody();
            assertThat(reach).containsEntry("kind", "NEITHER").containsEntry("total", 1).containsEntry("mayEditContact", true);
            assertThat((List<Map<String, Object>>) reach.get("byFaculty")).anySatisfy(f -> assertThat(f.get("faculty_code")).isEqualTo("SC"));
            assertThat(it.get(agentTok, SUPPORT + "/reach?export=true").getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");

            // no contact: refused; an agent without contact editing cannot save one; with the phone the student gives, raised and saved
            Map<String, Object> ticket = new HashMap<>(Map.of("category", "LOGIN", "subject", "Cannot sign in", "description", "The student cannot log into the portal",
                    "details", Map.of("account_type", "Student portal", "username", "MOAU/SC/RCH/26/" + n, "error", "Wrong password")));
            assertThat(it.call(agentTok, HttpMethod.POST, SUPPORT + "/students/" + none + "/tickets", ticket).getBody().get("code")).isEqualTo("SUPPORT_TICKET_CONTACT");
            ticket.put("phone", "0803 565 " + String.format("%04d", n % 10000));
            ticket.put("saveContact", true);
            assertThat(it.call(plainTok, HttpMethod.POST, SUPPORT + "/students/" + none + "/tickets", ticket).getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
            ResponseEntity<Map> raised = it.call(agentTok, HttpMethod.POST, SUPPORT + "/students/" + none + "/tickets", ticket);
            assertThat(raised.getStatusCode().value()).as(String.valueOf(raised.getBody())).isEqualTo(200);
            String phone = "0803565" + String.format("%04d", n % 10000);
            Map<String, Object> t = jdbc.sql("SELECT requester_email, requester_phone FROM helpdesk.ticket WHERE id = CAST(:t AS uuid)").param("t", String.valueOf(raised.getBody().get("id")))
                    .query().singleRow();
            assertThat(t.get("requester_email")).isNull();
            assertThat(t.get("requester_phone")).isEqualTo(phone);
            assertThat(jdbc.sql("SELECT phone FROM people.student_contact WHERE student_id = :s").param("s", none).query(String.class).single()).isEqualTo(phone);
            assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE channel = 'SMS' AND recipient = :p AND body LIKE 'MOAUM ICT Support:%'").param("p", phone)
                    .query(Long.class).single()).isPositive();
            // off the list of those with neither, on the list of those with no e-mail
            assertThat(it.get(agentTok, SUPPORT + "/reach?q=ZZRCHA" + n).getBody()).containsEntry("total", 0);
            assertThat(it.get(agentTok, SUPPORT + "/reach?kind=NO_EMAIL&q=ZZRCHA" + n).getBody()).containsEntry("total", 1);

            // the reset policy keeps what a save does not name, and clears a figure named empty
            it.db(() -> jdbc.sql("UPDATE helpdesk.setting SET bulk_reset_approval_over = 250 WHERE row_no").update());
            ResponseEntity<Map> saved = it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/settings/password-reset", Map.of("alertDaily", 7));
            assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
            Map<String, Object> kept = (Map<String, Object>) saved.getBody().get("passwordReset");
            assertThat(kept).containsEntry("alert_daily", 7).containsEntry("bulk_approval_over", 250).containsEntry("ticket", policyBefore.get("ticket"));
            Map<String, Object> cleared = new HashMap<>();
            cleared.put("bulkApprovalOver", null);
            assertThat((Map<String, Object>) it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/settings/password-reset", cleared).getBody().get("passwordReset"))
                    .doesNotContainKey("bulk_approval_over").containsEntry("alert_daily", 7);
            assertThat(it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/settings/password-reset", Map.of("bulkApprovalOver", 20000)).getBody().get("code"))
                    .isEqualTo("HELPDESK_BULK_APPROVAL");

            // a single reset and a bulk reset, read apart in the history
            assertThat(it.call(agentTok, HttpMethod.POST, SUPPORT + "/students/" + other + "/password",
                    Map.of("method", "DEFAULT", "reason", "Forgot the portal password; identity checked")).getStatusCode().value()).isEqualTo(200);
            // more than 1,000 chosen: opened in parts, read as a whole (ids that name no one are counted as failed)
            List<UUID> chosen = new ArrayList<>(List.of(none));
            for (int i = 0; i < 1499; i++) chosen.add(UUID.randomUUID());
            ResponseEntity<Map> started = it.call(agentTok, HttpMethod.POST, BULK, Map.of("studentIds", chosen, "reason", "A class could not sign in after the move", "key", "rch-" + n));
            assertThat(started.getStatusCode().value()).as(String.valueOf(started.getBody())).isEqualTo(200);
            List<Map<String, Object>> series = (List<Map<String, Object>>) started.getBody().get("series");
            assertThat(series).hasSize(2).extracting(p -> p.get("total")).containsExactly(1000, 500);
            String first = String.valueOf(started.getBody().get("id"));
            Map<String, Object> op = null;
            for (int i = 0; i < 120; i++) {
                op = it.get(agentTok, BULK + "/" + first).getBody();
                boolean ended = ((List<Map<String, Object>>) op.get("series")).stream().noneMatch(p -> List.of("PENDING", "PROCESSING").contains(p.get("status")));
                if (ended) break;
                Thread.sleep(500);
            }
            assertThat(op).containsEntry("part", 1).containsEntry("parts", 2);
            assertThat((List<Map<String, Object>>) op.get("series")).extracting(p -> p.get("status") + ":" + p.get("succeeded") + "/" + p.get("failed"))
                    .containsExactly("COMPLETED_WITH_EXCEPTIONS:1/999", "FAILED:0/500");
            Map<String, Object> single = it.get(head, SUPPORT + "/actions?module=AUTHENTICATION&kind=SINGLE&size=200").getBody();
            assertThat((List<Map<String, Object>>) single.get("rows")).anySatisfy(r -> assertThat(r.get("student_id")).isEqualTo(other.toString()))
                    .noneSatisfy(r -> assertThat(r.get("student_id")).isEqualTo(none.toString()));
            Map<String, Object> bulk = it.get(head, SUPPORT + "/actions?module=AUTHENTICATION&kind=BULK&size=200").getBody();
            assertThat((List<Map<String, Object>>) bulk.get("rows")).anySatisfy(r -> {
                assertThat(r.get("student_id")).isEqualTo(none.toString());
                assertThat(r.get("bulk_reference")).isEqualTo(series.get(0).get("reference"));
            });
        } finally {
            Map<String, Object> back = new HashMap<>();
            back.put("alertDaily", policyBefore.get("alert_daily"));
            back.put("bulkApprovalOver", policyBefore.get("bulk_approval_over"));
            it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/settings/password-reset", back);
        }
    }
}
