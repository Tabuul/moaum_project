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
 * ICT Support opens a student's portal as the student, read-only (V521): every agent in service opens it from the support record
 * with a reason — no password — and reads what the student reads (the student's own forced password change does not stand in the
 * way); every change made with the view is refused, before it reaches a service; the opening is on the support ledger and the
 * view's log; an agent off the desk reaches nobody and another office is refused; another agent cannot end the view; the agent
 * leaves and the portal session ends with it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentPortalViewIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private UUID agent(ItSupport it, String tag) {
        UUID p = it.person("ZZ-VIEW-" + tag, "ZZVIEW" + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'ictagent', 'platform', NULL, 'integration test', :p, current_date)
                """).param("p", p).update());
        return p;
    }

    @Test
    void anAgentOpensTheStudentsPortalReadOnlyAndLeavesIt() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String tag = UUID.randomUUID().toString().substring(0, 4).toUpperCase().replaceAll("[^A-Z0-9]", "Q");
        int n = it.freeDraw(1000, 9999, k -> List.of("MOAUM/ITV/26/" + k, "MOAUM/ADM/26/52" + k));
        String matric = "MOAUM/ITV/26/" + n;
        UUID student = it.student("ZZVIEW" + tag, "C00023", "MOAUM/ADM/26/52" + n, matric, 100);
        // the Registry opens the student's account with a first password the student must change: the agent who only looks is not
        // stopped by it, and never learns or needs it
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 5210"))
                .getStatusCode().value()).isEqualTo(200);
        String agent = TestTokens.token(agent(it, "A" + tag), List.of("ictagent"));
        String other = TestTokens.token(agent(it, "B" + tag), List.of("ictagent"));
        String offDesk = TestTokens.token(it.person("ZZ-VIEW-OFF" + tag, "ZZVIEWOFF" + tag), List.of("ictagent"));
        String path = "/api/v1/helpdesk/support/students/" + student + "/portal-view";

        // the action is offered on the support record
        Map<String, Object> record = it.get(agent, "/api/v1/helpdesk/support/students/" + student).getBody();
        assertThat(String.valueOf(record.get("center"))).contains("OPEN_PORTAL");

        // another office is refused; an agent off the desk reaches nobody; a reason is required
        assertThat(it.call(TestTokens.token(UUID.randomUUID(), List.of("bursar")), HttpMethod.POST, path, Map.of("reason", "Checking the student's portal")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(offDesk, HttpMethod.POST, path, Map.of("reason", "Checking the student's portal")).getStatusCode().value()).isEqualTo(404);
        assertThat(it.call(agent, HttpMethod.POST, path, Map.of("reason", "short")).getStatusCode().value()).isEqualTo(400);

        // opened: the student's own portal, read as the student
        ResponseEntity<Map> opened = it.call(agent, HttpMethod.POST, path, Map.of("reason", "The student says the registration page shows no courses"));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        String view = String.valueOf(opened.getBody().get("token"));
        String viewId = String.valueOf(opened.getBody().get("viewId"));
        assertThat(opened.getBody()).containsEntry("matricNo", matric);
        ResponseEntity<Map> me = it.get(view, "/api/v1/me");
        assertThat(me.getStatusCode().value()).as(String.valueOf(me.getBody())).isEqualTo(200);
        assertThat(me.getBody()).containsEntry("matricNo", matric);
        assertThat(it.get(view, "/api/v1/me/registration").getStatusCode().value()).isEqualTo(200);

        // every change made with the view is refused before it reaches a service
        ResponseEntity<Map> save = it.call(view, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", "2025/2026", "semester", 1, "offerings", List.of()));
        assertThat(save.getStatusCode().value()).isEqualTo(403);
        assertThat(save.getBody()).containsEntry("code", "SUPPORT_VIEW_READ_ONLY");
        assertThat(it.call(view, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "x", "next", "Another-Password-521")).getBody())
                .containsEntry("code", "SUPPORT_VIEW_READ_ONLY");
        assertThat(it.call(view, HttpMethod.PUT, "/api/v1/me/contact", Map.of("phone", "08000000000")).getStatusCode().value()).isEqualTo(403);
        // nor is the view a way onto another office's door
        assertThat(it.get(view, "/api/v1/helpdesk/support/students/" + student).getStatusCode().value()).isEqualTo(403);

        // on the support ledger and the view's log, with the reason
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND action = 'STUDENT_PORTAL_VIEWED' AND reason LIKE '%no courses%'")
                .param("s", student).query(Long.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.portal_view WHERE student_id = :s AND ended_at IS NULL").param("s", student).query(Long.class).single()).isEqualTo(1);

        // another agent does not end it; the agent who opened it does, and the portal session ends with it
        assertThat(it.call(other, HttpMethod.POST, "/api/v1/helpdesk/support/portal-views/" + viewId + "/end", null).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> ended = it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/support/portal-views/" + viewId + "/end", null);
        assertThat(ended.getStatusCode().value()).as(String.valueOf(ended.getBody())).isEqualTo(200);
        assertThat(ended.getBody()).containsEntry("ended", true);
        ResponseEntity<Map> after = it.get(view, "/api/v1/me");
        assertThat(after.getStatusCode().value()).isEqualTo(401);
        assertThat(after.getBody()).containsEntry("code", "SESSION_ENDED");
    }
}
