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
 * V453: every ICT support agent in service opens any student in support mode, manages their course registration and works
 * Payment Support — never posted, or posted to a queue only; an agent the Head took off the desk does none of it; what a
 * posting adds beyond the baseline (editing the record, the support override) still comes only with the posting.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SupportBaselineIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private UUID agent(ItSupport it, String tag) {
        UUID p = it.person("ZZ-BASELINE-" + tag, "ZZBASELINE" + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'ictagent', 'platform', NULL, 'integration test', :p, current_date)
                """).param("p", p).update());
        return p;
    }

    @Test
    void everyAgentInServiceOpensTheStudentRegistrationAndPayments() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String tag = UUID.randomUUID().toString().substring(0, 6).toUpperCase();
        UUID student = it.student("ZZBASE" + tag, "C00001", null, null, 100);   // any faculty: the baseline is the University's

        // never posted: the student, the registration (managed) and Payment Support
        UUID fresh = agent(it, "A" + tag);
        String tok = TestTokens.token(fresh, List.of("ictagent"));
        ResponseEntity<Map> profile = it.get(tok, "/api/v1/helpdesk/support/students/" + student);
        assertThat(profile.getStatusCode().value()).as(String.valueOf(profile.getBody())).isEqualTo(200);
        assertThat((List<String>) profile.getBody().get("capabilities"))
                .contains("VIEW_STUDENT", "MANAGE_REGISTRATION", "VIEW_PAYMENTS", "INVESTIGATE_PAYMENT", "VERIFY_PAYMENT", "SYNC_ENTITLEMENT", "REGENERATE_RECEIPT")
                .doesNotContain("EDIT_CONTACT", "OVERRIDE_REGISTRATION", "RESET_PASSWORD");
        ResponseEntity<Map> reg = it.get(tok, "/api/v1/helpdesk/support/students/" + student + "/registration?semester=1");
        assertThat(reg.getStatusCode().value()).as(String.valueOf(reg.getBody())).isEqualTo(200);
        assertThat(reg.getBody().get("manage")).isEqualTo(true);
        assertThat(reg.getBody().get("override")).isEqualTo(false);
        ResponseEntity<Map> search = it.get(tok, "/api/v1/helpdesk/support/payments?q=ZZBASE" + tag);
        assertThat(search.getStatusCode().value()).as(String.valueOf(search.getBody())).isEqualTo(200);
        // editing the record is still a posting's to give
        ResponseEntity<Map> edit = it.call(tok, HttpMethod.PUT, "/api/v1/helpdesk/support/students/" + student + "/biodata/mobile",
                Map.of("value", "08031234567", "reason", "asked at the desk"));
        assertThat(edit.getStatusCode().value()).isEqualTo(422);
        assertThat(edit.getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");

        // posted to a queue only (an office scope, which reaches no student by itself): the baseline still holds
        UUID queued = agent(it, "B" + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                VALUES (:p, (SELECT code FROM helpdesk.queue WHERE active ORDER BY ordinal LIMIT 1), 'OFFICE', 'bursar', ARRAY['VIEW_STUDENT'])
                """).param("p", queued).update());
        assertThat(it.get(TestTokens.token(queued, List.of("ictagent")), "/api/v1/helpdesk/support/students/" + student).getStatusCode().value()).isEqualTo(200);

        // taken off the desk (every posting ended): none of it
        it.db(() -> jdbc.sql("UPDATE helpdesk.agent_assignment SET active = false, effective_to = current_date WHERE person_id = :p").param("p", queued).update());
        assertThat(it.get(TestTokens.token(queued, List.of("ictagent")), "/api/v1/helpdesk/support/students/" + student).getStatusCode().value()).isEqualTo(404);
    }
}
