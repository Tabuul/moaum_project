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
 * V500: every ICT support agent in service manages a student's academic level and resets the password at the desk. The level is
 * read with its evidence, progressed to the next of the programme's levels or corrected to another of them, with a reason and the
 * student's ticket; a level outside the programme, a short reason, a stale screen and a student not in study are refused; a second
 * click does nothing; the session's registration, the results and the graduation status are left as they were; every change is on
 * the level history, the support ledger and the ticket. An agent off the desk reaches nobody, another office is refused. The level
 * and reset histories are read with their own capability; the ticket carries the student's phone for the desk, not for the student.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentLevelSupportIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private UUID agent(ItSupport it, String tag) {
        UUID p = it.person("ZZ-LEVEL-" + tag, "ZZLEVEL" + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'ictagent', 'platform', NULL, 'integration test', :p, current_date)
                """).param("p", p).update());
        return p;
    }

    private ResponseEntity<Map> change(ItSupport it, String tok, UUID student, Map<String, Object> body) {
        return it.call(tok, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + student + "/level", body);
    }

    @Test
    void everyAgentInServiceProgressesAndCorrectsALevelAndResetsThePasswordAndTheTicketCarriesThePhone() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String tag = UUID.randomUUID().toString().substring(0, 4).toUpperCase().replaceAll("[^A-Z0-9]", "Q");
        int n = 1000 + Math.abs(tag.hashCode() % 8999);
        // an undergraduate programme four levels long, as the register states it
        String programme = jdbc.sql("""
                SELECT code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND NOT coalesce(archived, false) AND finance.final_level(code) = 400 ORDER BY code LIMIT 1
                """).query(String.class).single();
        String matric = "MOAUM/ITL/26/" + n;
        UUID student = it.student("ZZLEVEL" + tag, programme, "MOAUM/ADM/26/50" + n, matric, 100);
        UUID withdrawn = it.student("ZZLEVELW" + tag, programme, "MOAUM/ADM/26/51" + n, "MOAUM/ITW/26/" + n, 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET status = 'WITHDRAWN' WHERE id = :s").param("s", withdrawn).update();
            return jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email) VALUES (:s, :ph, :e) ON CONFLICT (student_id) DO UPDATE SET phone = :ph, email = :e")
                    .param("s", student).param("ph", "0803" + n + "555").param("e", "zzlevel" + n + "@example.edu").update();
        });
        UUID agentId = agent(it, "A" + tag);
        String agent = TestTokens.token(agentId, List.of("ictagent"));
        String offDesk = TestTokens.token(it.person("ZZ-LEVEL-OFF" + tag, "ZZLEVELOFF" + tag), List.of("ictagent"));
        String base = "/api/v1/helpdesk/support/students/" + student + "/level";

        // the level read with the programme's levels and the evidence; the agent may progress and correct
        ResponseEntity<Map> read = it.get(agent, base);
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        Map<String, Object> options = (Map<String, Object>) read.getBody().get("options");
        assertThat(options.get("levels")).isEqualTo(List.of(100, 200, 300, 400));
        assertThat(options).containsEntry("currentLevel", 100).containsEntry("nextLevel", 200).containsEntry("finalLevel", 400);
        assertThat(read.getBody()).containsEntry("mayProgress", true).containsEntry("mayCorrect", true);
        assertThat(((Map) read.getBody().get("student"))).containsEntry("matric_no", matric);
        String session = String.valueOf(read.getBody().get("session"));

        // 16-17: an agent taken off the desk reaches nobody; another office is refused at the door
        assertThat(it.get(offDesk, base).getStatusCode().value()).isEqualTo(404);
        assertThat(change(it, offDesk, student, Map.of("action", "PROGRESS", "expected", 100, "reason", "Student says the level is wrong")).getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(TestTokens.token(UUID.randomUUID(), List.of("registrar")), base).getStatusCode().value()).isEqualTo(403);

        // 8: the reason is required, in words
        ResponseEntity<Map> shortReason = change(it, agent, student, Map.of("action", "PROGRESS", "expected", 100, "reason", "wrong"));
        assertThat(shortReason.getStatusCode().value()).isEqualTo(422);
        assertThat(shortReason.getBody().get("code")).isEqualTo("LEVEL_REASON");

        // 13, 15: a registration for the session is named first, and left as it was
        it.session(session, Integer.parseInt(session.substring(0, 4)));   // the session the desk names, on the register
        UUID reg = it.db(() -> jdbc.sql("""
                INSERT INTO registration.course_registration (id, student_id, session, semester, level, status) VALUES (gen_random_uuid(), :s, :ses, 1, 100, 'DRAFT') RETURNING id
                """).param("s", student).param("ses", session).query(UUID.class).single());
        ResponseEntity<Map> unacknowledged = change(it, agent, student, Map.of("action", "PROGRESS", "expected", 100, "reason", "Left at 100 Level after the session's promotion"));
        assertThat(unacknowledged.getStatusCode().value()).isEqualTo(422);
        assertThat(unacknowledged.getBody().get("code")).isEqualTo("LEVEL_REGISTRATION_ACK");

        // a student's own ticket, the act linked to it (10)
        String studentTok = TestTokens.token(student, List.of("student"));
        ResponseEntity<Map> made = it.call(studentTok, HttpMethod.POST, "/api/v1/helpdesk/my/tickets", Map.of(
                "category", "PAYMENT", "subject", "My level is wrong", "description", "The portal shows 100 Level but I should be at 200 Level now.",
                "email", "zzlevel" + n + "@example.edu", "details", Map.of("payment_reference", "RRR-500" + n, "payment_date", "2026-09-01", "payment_type", "School fees", "amount", "1000")));
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        UUID ticket = UUID.fromString(String.valueOf(made.getBody().get("id")));

        // 4: progressed to the next level, once; 18: a second click does nothing
        Map<String, Object> progress = Map.of("action", "PROGRESS", "expected", 100, "reason", "Left at 100 Level after the session's promotion",
                "ticket", ticket.toString(), "acknowledgeRegistration", true);
        ResponseEntity<Map> progressed = change(it, agent, student, progress);
        assertThat(progressed.getStatusCode().value()).as(String.valueOf(progressed.getBody())).isEqualTo(200);
        assertThat(progressed.getBody()).containsEntry("previousLevel", 100).containsEntry("newLevel", 200).containsEntry("alreadyDone", false).containsEntry("registrationKept", true);
        ResponseEntity<Map> again = change(it, agent, student, progress);
        assertThat(again.getStatusCode().value()).isEqualTo(200);
        assertThat(again.getBody()).containsEntry("alreadyDone", true);
        assertThat(jdbc.sql("SELECT current_level FROM people.student WHERE id = :s").param("s", student).query(Integer.class).single()).isEqualTo(200);
        assertThat(jdbc.sql("SELECT level || '/' || status FROM registration.course_registration WHERE id = :r").param("r", reg).query(String.class).single()).isEqualTo("100/DRAFT");

        // 6-7: a level outside the programme, and a stale screen, are refused
        ResponseEntity<Map> outside = change(it, agent, student, Map.of("action", "CORRECTION", "level", 700, "expected", 200, "reason", "Uploaded at the wrong level", "acknowledgeRegistration", true));
        assertThat(outside.getBody().get("code")).isEqualTo("LEVEL_NOT_IN_PROGRAMME");
        ResponseEntity<Map> stale = change(it, agent, student, Map.of("action", "CORRECTION", "level", 300, "expected", 100, "reason", "Uploaded at the wrong level", "acknowledgeRegistration", true));
        assertThat(stale.getBody().get("code")).isEqualTo("LEVEL_CHANGED");
        // 5: corrected to another of the programme's levels
        ResponseEntity<Map> corrected = change(it, agent, student, Map.of("action", "CORRECTION", "level", 300, "expected", 200, "reason", "Direct entry student recorded at the wrong level",
                "ticket", ticket.toString(), "acknowledgeRegistration", true));
        assertThat(corrected.getStatusCode().value()).as(String.valueOf(corrected.getBody())).isEqualTo(200);
        assertThat(corrected.getBody()).containsEntry("newLevel", 300).containsEntry("action", "LEVEL_CORRECTION");

        // 9-10: on the level history (rule, ticket), the support ledger and the ticket's timeline; 14: the status is the same
        assertThat(jdbc.sql("SELECT string_agg(previous_level || '>' || new_level || ':' || rule || ':' || (ticket_id = :t), ',' ORDER BY decided_at) FROM people.cohort_decision WHERE student_id = :s")
                .param("s", student).param("t", ticket).query(String.class).single()).isEqualTo("100>200:LEVEL_PROGRESS:true,200>300:LEVEL_CORRECTION:true");
        assertThat(jdbc.sql("SELECT string_agg(action || ':' || old_value || '>' || new_value, ',' ORDER BY at) FROM helpdesk.support_action WHERE student_id = :s AND helpdesk.support_module(action) = 'ACADEMIC_LEVEL'")
                .param("s", student).query(String.class).single()).isEqualTo("LEVEL_PROGRESSED:100>200,LEVEL_CORRECTED:200>300");
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = :t AND action IN ('SUPPORT_LEVEL_PROGRESSED', 'SUPPORT_LEVEL_CORRECTED')")
                .param("t", ticket).query(Long.class).single()).isEqualTo(2L);
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo("ACTIVE");
        // 11-12: the level's history read back at the desk; a student not in study is not moved
        Map<String, Object> history = it.get(agent, "/api/v1/helpdesk/support/levels/history?q=ZZLEVEL" + tag).getBody();
        assertThat((List<Map>) history.get("rows")).extracting(r -> r.get("rule")).contains("LEVEL_PROGRESS", "LEVEL_CORRECTION");
        ResponseEntity<Map> notInStudy = change(it, agent, withdrawn, Map.of("action", "PROGRESS", "expected", 100, "reason", "Student says the level is wrong"));
        assertThat(String.valueOf(notInStudy.getBody().get("code"))).isEqualTo("LEVEL_STATUS");

        // the password reset to the default credential by the same agent, without a posting (V500's baseline)
        ResponseEntity<Map> reset = it.call(agent, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + student + "/password",
                Map.of("method", "DEFAULT", "reason", "Student forgot the portal password; identity checked"));
        assertThat(reset.getStatusCode().value()).as(String.valueOf(reset.getBody())).isEqualTo(200);
        assertThat(String.valueOf(reset.getBody())).doesNotContain(matric).doesNotContain("$2a$");
        assertThat(it.call(offDesk, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + student + "/password",
                Map.of("method", "DEFAULT", "reason", "Student forgot the portal password; identity checked")).getStatusCode().value()).isEqualTo(404);
        // the reset history is read with its own capability; the whole support audit is not
        assertThat(it.get(agent, "/api/v1/helpdesk/support/actions?module=AUTHENTICATION").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(agent, "/api/v1/helpdesk/support/actions").getBody().get("code")).isEqualTo("SUPPORT_CAPABILITY");

        // the ticket carries the student's phone from the record for the desk, and the desk finds the ticket by it; the student's
        // own view of the ticket does not carry it
        Map<String, Object> deskTicket = it.get(agent, "/api/v1/helpdesk/tickets/" + ticket).getBody();
        assertThat(deskTicket).containsEntry("student_phone", "0803" + n + "555");
        Map<String, Object> found = it.get(agent, "/api/v1/helpdesk/tickets?q=0803" + n).getBody();
        assertThat(String.valueOf(found)).contains(ticket.toString());
        assertThat(it.get(studentTok, "/api/v1/helpdesk/my/tickets/" + ticket).getBody()).doesNotContainKey("student_phone");
    }
}
