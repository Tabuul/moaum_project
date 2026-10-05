package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * Student record support from the ICT Support Desk (V334), over the API: an agent posted on a faculty finds and reads that
 * faculty's students and not another's; edits an open contact field with a reason, which lands on the record, in the
 * contact the University reaches them at and on the support ledger; raises a Registry change for a sensitive field
 * rather than writing it; is refused a JAMB-read field and any capability the posting does not carry; reaches the
 * registration only through the engine, which refuses what it would refuse the student; a student token is refused;
 * the Head reaches every student. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SupportStudentsIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;
    UUID agent, posting, inside, outside;
    String agentTok, headTok;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        agent = it.person("ZZ-SUPPORT-1", "ZZSUPPORTAGENT");
        agentTok = TestTokens.token(agent, List.of("ictagent"));
        headTok = ItSupport.token("helpdeskhead");
        inside = it.student("ZZSUPIN", "C00023", null, "MOAUM/MTC/95/9831", 200);    // Mathematics and Computer Science · Science
        outside = it.student("ZZSUPOUT", "C00001", null, "MOAUM/ASS/95/9832", 200);  // Arts and Social Sciences Education · Education
        it.db(() -> {
            jdbc.sql("DELETE FROM helpdesk.support_action WHERE agent_id = :p").param("p", agent).update();
            jdbc.sql("DELETE FROM helpdesk.agent_assignment WHERE person_id = :p").param("p", agent).update();
            jdbc.sql("DELETE FROM people.biodata_change WHERE student_id = :s").param("s", inside).update();
            jdbc.sql("DELETE FROM people.biodata WHERE student_id = :s").param("s", inside).update();
            return null;
        });
        posting = it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','EDIT_CONTACT','REQUEST_CHANGE']) RETURNING id
                """).param("p", agent).query(UUID.class).single());
    }

    private static List<Map> rows(ResponseEntity<Map> r) {
        return (List<Map>) r.getBody().get("rows");
    }

    @Test
    void anAgentReachesTheirScopeAndDoesOnlyWhatThePostingCarries() {
        // the search finds the faculty's student and not the other faculty's
        ResponseEntity<Map> found = it.get(agentTok, "/api/v1/helpdesk/support/students?q=ZZSUP&size=20");
        assertThat(found.getStatusCode().value()).as(String.valueOf(found.getBody())).isEqualTo(200);
        assertThat(rows(found)).extracting(r -> String.valueOf(r.get("id"))).contains(inside.toString()).doesNotContain(outside.toString());
        assertThat(String.valueOf(found.getBody().get("scope"))).contains("Science");
        assertThat(it.get(agentTok, "/api/v1/helpdesk/support/students?q=ZZSUP&export=true").getStatusCode().value()).isEqualTo(422);
        // the profile is read within reach; outside it, the student is not found
        ResponseEntity<Map> profile = it.get(agentTok, "/api/v1/helpdesk/support/students/" + inside);
        assertThat(profile.getStatusCode().value()).as(String.valueOf(profile.getBody())).isEqualTo(200);
        assertThat(profile.getBody()).containsKeys("record", "portal", "contact", "capabilities", "actions", "tickets", "history");
        assertThat(((Map) profile.getBody().get("portal")).containsKey("fees")).as("payments are not shown without the capability").isFalse();
        assertThat(it.get(agentTok, "/api/v1/helpdesk/support/students/" + outside).getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(headTok, "/api/v1/helpdesk/support/students/" + outside).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(TestTokens.token(inside, List.of("student")), "/api/v1/helpdesk/support/students?q=ZZSUP").getStatusCode().value()).isEqualTo(403);
        // an open contact field is written with a reason: on the record, where the University reaches them, and on the ledger
        ResponseEntity<Map> edited = it.call(agentTok, HttpMethod.PUT, "/api/v1/helpdesk/support/students/" + inside + "/biodata/mobile",
                Map.of("value", "08031234567", "reason", "The student reported a wrong number at the desk"));
        assertThat(edited.getStatusCode().value()).as(String.valueOf(edited.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT value FROM people.biodata WHERE student_id = :s AND field = 'mobile'").param("s", inside).query(String.class).single()).isEqualTo("08031234567");
        assertThat(jdbc.sql("SELECT phone FROM people.student_contact WHERE student_id = :s").param("s", inside).query(String.class).single()).isEqualTo("08031234567");
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND agent_id = :p AND action = 'CONTACT_EDITED' AND new_value = '08031234567'")
                .param("s", inside).param("p", agent).query(Long.class).single()).isEqualTo(1L);
        assertThat(it.call(agentTok, HttpMethod.PUT, "/api/v1/helpdesk/support/students/" + inside + "/biodata/mobile", Map.of("value", "0803", "reason", "typo")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(agentTok, HttpMethod.PUT, "/api/v1/helpdesk/support/students/" + inside + "/biodata/mobile", Map.of("value", "08031234568", "reason", "")).getStatusCode().value()).isIn(400, 422);
        // a sensitive field is requested of the Registry, not written; a JAMB-read field is refused; a capability not carried is refused
        ResponseEntity<Map> asked = it.call(agentTok, HttpMethod.PUT, "/api/v1/helpdesk/support/students/" + inside + "/biodata/state_of_origin",
                Map.of("value", "Benue", "reason", "LGA identification sighted at the desk"));
        assertThat(asked.getStatusCode().value()).as(String.valueOf(asked.getBody())).isEqualTo(200);
        assertThat(asked.getBody().get("pending")).isEqualTo(true);
        assertThat(jdbc.sql("SELECT count(*) FROM people.biodata_change WHERE student_id = :s AND field = 'state_of_origin' AND state = 'PENDING'").param("s", inside).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM people.biodata WHERE student_id = :s AND field = 'state_of_origin'").param("s", inside).query(Long.class).single()).isEqualTo(0L);
        ResponseEntity<Map> locked = it.call(agentTok, HttpMethod.PUT, "/api/v1/helpdesk/support/students/" + inside + "/biodata/university_email", Map.of("value", "x@moaum.edu.ng", "reason", "asked"));
        assertThat(locked.getStatusCode().value()).isEqualTo(422);
        assertThat(locked.getBody().get("code")).isEqualTo("STU_FIELD_LOCKED");
        ResponseEntity<Map> family = it.call(agentTok, HttpMethod.PUT, "/api/v1/helpdesk/support/students/" + inside + "/biodata/father_name", Map.of("value", "Mr Test", "reason", "asked"));
        assertThat(family.getStatusCode().value()).isEqualTo(422);
        assertThat(family.getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
        // the registration is read; it is not managed until the posting carries it; then only through the engine
        ResponseEntity<Map> reg = it.get(agentTok, "/api/v1/helpdesk/support/students/" + inside + "/registration?semester=1");
        assertThat(reg.getStatusCode().value()).as(String.valueOf(reg.getBody())).isEqualTo(200);
        assertThat(reg.getBody().get("manage")).isEqualTo(false);
        Map<String, Object> add = Map.of("session", String.valueOf(((Map) reg.getBody().get("view")).get("session")), "semester", 1, "offering", UUID.randomUUID().toString(), "reason", "Portal error at registration");
        ResponseEntity<Map> refused = it.call(agentTok, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + inside + "/registration/add", add);
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");
        ResponseEntity<Map> granted = it.call(headTok, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + posting, Map.of("capabilities", List.of("VIEW_STUDENT", "EDIT_CONTACT", "MANAGE_REGISTRATION")));
        assertThat(granted.getStatusCode().value()).as(String.valueOf(granted.getBody())).isEqualTo(200);
        ResponseEntity<Map> engine = it.call(agentTok, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + inside + "/registration/add", add);
        assertThat(engine.getStatusCode().value()).isEqualTo(422);
        assertThat(engine.getBody().get("code")).as("the registration engine's own refusal, not the desk's").isNotEqualTo("SUPPORT_CAPABILITY");
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE student_id = :s AND action = 'COURSE_ADDED'").param("s", inside).query(Long.class).single()).isEqualTo(0L);
        // the posting carries only known capabilities
        assertThat(it.call(headTok, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + posting, Map.of("capabilities", List.of("EDIT_RESULTS"))).getStatusCode().value()).isIn(400, 422);
    }
}
