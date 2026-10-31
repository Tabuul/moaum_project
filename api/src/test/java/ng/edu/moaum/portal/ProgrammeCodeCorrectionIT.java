package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * V716: a programme's code corrected by the Director of ICT and the ICT Support Desk. A made-up programme with two students and what
 * JAMB calls it: the Registry is refused the desk; the check reads the impact; an agent without the capability is refused, one posted
 * over another faculty is out of scope, one posted over the programme's faculty corrects it on a ticket — the students on the new code,
 * the old code archived and an alias (a student written with it lands on the new), the change on the ticket and on the trail; a stale
 * version is refused; the Head of the ICT Support Desk undoes it from the record — the students back, the old code in use. Needs
 * DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ProgrammeCodeCorrectionIT {

    static final String BASE = "/api/v1/catalogue";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    /** a C-code no programme holds */
    private String freeCode() {
        for (int i = 0; i < 50; i++) {
            String c = "C9" + String.format("%04d", ThreadLocalRandom.current().nextInt(1000, 9999));
            if (jdbc.sql("SELECT count(*) FROM ref.programme WHERE code = :c").param("c", c).query(Long.class).single() == 0L) return c;
        }
        throw new IllegalStateException("no free programme code");
    }

    @Test
    void theCodeIsCorrectedWithinReachOnATicketAndUndoneFromTheRecord() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(3100, 3800);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String old = freeCode();
        String fresh = freeCode();
        Map<String, Object> dept = jdbc.sql("SELECT d.code, d.faculty_code FROM ref.department d WHERE d.faculty_code IS NOT NULL ORDER BY d.code LIMIT 1").query().singleRow();
        String faculty = (String) dept.get("faculty_code");
        String otherFaculty = jdbc.sql("SELECT code FROM ref.faculty WHERE code <> :f ORDER BY code LIMIT 1").param("f", faculty).query(String.class).single();
        it.db(() -> {
            jdbc.sql("INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, matric_code) VALUES (:c, 'B.Sc. IT Correction Studies', :d, :f, 0, false, 'UNDER GRADUATE', 'ITC')")
                    .param("c", old).param("d", dept.get("code")).param("f", faculty).update();
            jdbc.sql("INSERT INTO ref.jamb_alias (code, jamb_name) VALUES (:c, :n)").param("c", old).param("n", "IT CORRECTION STUDIES " + old).update();
            return null;
        });
        UUID a = it.student(it.freeSurname("ZZPCCA"), old, it.freeNumber("MOAUM/ADM/26/5", 5), it.freeNumber("MOAU/SC/ITC/26/5", 5), 100);
        UUID b = it.student(it.freeSurname("ZZPCCB"), old, it.freeNumber("MOAUM/ADM/26/5", 5), it.freeNumber("MOAU/SC/ITC/26/5", 5), 200);
        String ict = ItSupport.token("ict");
        String head = ItSupport.token("helpdeskhead");
        String registrar = ItSupport.token("registrar");

        // the Registry neither checks nor corrects; the Director of ICT reads the impact
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/programmes/" + old + "/code-correction/check", Map.of("newCode", fresh)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> check = it.call(ict, HttpMethod.POST, BASE + "/programmes/" + old + "/code-correction/check", Map.of("newCode", fresh.toLowerCase()));
        assertThat(check.getStatusCode().value()).as(String.valueOf(check.getBody())).isEqualTo(200);
        assertThat(check.getBody()).containsEntry("newCode", fresh).containsEntry("may", true);
        assertThat(check.getBody().get("refusal")).as("no refusal").isNull();
        assertThat(((Map) check.getBody().get("impact")).get("students")).isEqualTo(2);
        String version = String.valueOf(check.getBody().get("version"));
        assertThat(((Map) it.call(ict, HttpMethod.POST, BASE + "/programmes/" + old + "/code-correction/check", Map.of("newCode", "C00023")).getBody().get("refusal")).get("code"))
                .isEqualTo("PROGRAMME_CODE_TAKEN");

        // an agent: without the capability, then posted over another faculty, then over the programme's — on a ticket
        UUID agent = it.person(it.freeNumber("ZZ-PCC-", 6), "ZZPCCAGENT");
        String tok = TestTokens.token(agent, List.of("ictagent"));
        Map<String, Object> body = Map.of("newCode", fresh, "reasonKind", "ICT_SUPPORT_CORRECTION", "remarks", "JAMB lists the programme under the new code", "version", version);
        assertThat(it.call(tok, HttpMethod.POST, BASE + "/programmes/" + old + "/code-correction", body).getBody().get("code")).isEqualTo("STRUCTURE_CAPABILITY");
        it.db(() -> jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'FACULTY', :f, ARRAY['EDIT_PROGRAMME_CODE'])")
                .param("p", agent).param("f", otherFaculty).update());
        assertThat(it.call(tok, HttpMethod.POST, BASE + "/programmes/" + old + "/code-correction", body).getBody().get("code")).isEqualTo("STRUCTURE_SCOPE");
        assertThat(it.call(tok, HttpMethod.POST, BASE + "/programmes/" + old + "/code-correction/check", Map.of("newCode", fresh)).getBody().get("may")).isEqualTo(false);
        it.db(() -> jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'FACULTY', :f, ARRAY['EDIT_PROGRAMME_CODE'])")
                .param("p", agent).param("f", faculty).update());
        String number = "TICK-7160-" + ThreadLocalRandom.current().nextInt(10000, 99999);
        UUID ticket = it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.ticket (number, category_id, subject, description, requester_kind, requester_id, requester_name, queue_code, faculty_code, department_code, assigned_to)
                SELECT :n, c.id, 'Programme code wrong', 'The programme is listed by JAMB under another code', 'STAFF', :a, 'ZZPCC', 'COURSE_REGISTRATION_SUPPORT', NULL, NULL, :a
                  FROM helpdesk.category c WHERE c.code = 'REGISTRATION'
                RETURNING id
                """).param("n", number).param("a", agent).query(UUID.class).single());
        // a stale version is refused; the correction goes through on the version read
        assertThat(it.call(tok, HttpMethod.POST, BASE + "/programmes/" + old + "/code-correction", Map.of("newCode", fresh, "reasonKind", "ICT_SUPPORT_CORRECTION", "version", "stale"))
                .getBody().get("code")).isEqualTo("PROGRAMME_CHANGED_SINCE");
        ResponseEntity<Map> done = it.call(tok, HttpMethod.POST, BASE + "/programmes/" + old + "/code-correction?ticket=" + number, body);
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("code", fresh).containsEntry("was", old).containsEntry("students", 2);
        assertThat(jdbc.sql("SELECT count(*) FROM people.student WHERE id IN (:a, :b) AND programme_code = :c").param("a", a).param("b", b).param("c", fresh).query(Long.class).single()).isEqualTo(2L);
        assertThat(jdbc.sql("SELECT archived FROM ref.programme WHERE code = :c").param("c", old).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT ref.programme_now(:c)").param("c", old).query(String.class).single()).isEqualTo(fresh);
        assertThat(jdbc.sql("SELECT count(*) FROM ref.jamb_alias WHERE code = :c").param("c", fresh).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = :t AND to_value LIKE 'Corrected programme code %'").param("t", ticket).query(Long.class).single()).isEqualTo(1L);
        // a student written with the old code lands on the new
        UUID c = it.student(it.freeSurname("ZZPCCC"), old, it.freeNumber("MOAUM/ADM/26/5", 5), it.freeNumber("MOAU/SC/ITC/26/5", 5), 100);
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", c).query(String.class).single()).isEqualTo(fresh);
        it.db(() -> jdbc.sql("DELETE FROM people.student WHERE id = :s").param("s", c).update());
        // on the trail, read by the Registry too, who may not undo
        ResponseEntity<Map> list = it.get(registrar, BASE + "/programme-code-changes?q=" + fresh);
        assertThat(list.getStatusCode().value()).isEqualTo(200);
        assertThat(list.getBody()).containsEntry("may", false);
        Map row = ((List<Map>) list.getBody().get("rows")).stream().filter(r -> fresh.equals(r.get("new_code"))).findFirst().orElseThrow();
        assertThat(row).containsEntry("old_code", old).containsEntry("ticket", number).containsEntry("changed_office", "ictagent");
        assertThat(row.get("undone_at")).isNull();
        String id = String.valueOf(row.get("id"));
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/programme-code-changes/" + id + "/undo", Map.of("reason", "The Registry may not undo it")).getStatusCode().value()).isEqualTo(403);

        // the Head of the ICT Support Desk undoes it from the record
        ResponseEntity<Map> undone = it.call(head, HttpMethod.POST, BASE + "/programme-code-changes/" + id + "/undo", Map.of("reason", "The code was right after all"));
        assertThat(undone.getStatusCode().value()).as(String.valueOf(undone.getBody())).isEqualTo(200);
        assertThat(undone.getBody()).containsEntry("code", old).containsEntry("newCodeNamed", false);
        assertThat(jdbc.sql("SELECT count(*) FROM people.student WHERE id IN (:a, :b) AND programme_code = :c").param("a", a).param("b", b).param("c", old).query(Long.class).single()).isEqualTo(2L);
        assertThat(jdbc.sql("SELECT archived FROM ref.programme WHERE code = :c").param("c", old).query(Boolean.class).single()).isFalse();
        assertThat(jdbc.sql("SELECT archived FROM ref.programme WHERE code = :c").param("c", fresh).query(Boolean.class).single()).isTrue();
        Map after = ((List<Map>) it.get(ict, BASE + "/programme-code-changes?q=" + fresh).getBody().get("rows")).stream().filter(r -> id.equals(String.valueOf(r.get("id")))).findFirst().orElseThrow();
        assertThat(after.get("undone_at")).isNotNull();
        assertThat(after).containsEntry("undone_office", "helpdeskhead");
    }
}
