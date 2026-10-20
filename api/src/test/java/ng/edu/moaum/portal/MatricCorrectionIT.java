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
 * V579 — a matriculation number corrected over the API: the Academic Office finds the student, sees the number the configuration
 * proposes and that another student's number is refused (MATRICULATION NUMBER ALREADY ASSIGNED), prepares the correction with
 * evidence; the officer who prepared it, the Director of ICT (not a legacy migration) and the Bursary may not decide it, ICT
 * Support reads and changes nothing; the Registry approves it: the number changes and nothing else, the old number finds the
 * student in the register and the search, the sign-in door and the sign-in help say it was corrected, the record's
 * matriculation panel reads the correction; a correction is rejected with a reason, and one is cancelled. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class MatricCorrectionIT {

    static final String BASE = "/api/v1/matriculation/corrections";
    static final String PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";

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

    /** a programme whose matriculation configuration is complete, so the configuration proposes a number */
    private String configuredProgramme() {
        return jdbc.sql("""
                SELECT p.code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false) AND coalesce(p.matric_faculty_code, f.matric_code) IS NOT NULL
                   AND (NOT p.matric_uses_code OR p.matric_code IS NOT NULL)
                   AND EXISTS (SELECT 1 FROM people.matric_series ms WHERE ms.code = coalesce(p.matric_series, f.matric_series, 'GENERAL') AND ms.active)
                 ORDER BY p.code LIMIT 1
                """).query(String.class).single();
    }

    /** a made-up old-portal number of the test's own, free on the register and among former numbers */
    private String freeOldNumber() {
        for (int i = 0; i < 50; i++) {
            String n = "MOAU/ZQ/ZQ/86/" + (1_000_000 + java.util.concurrent.ThreadLocalRandom.current().nextInt(8_999_999));
            Boolean taken = jdbc.sql("""
                    SELECT EXISTS (SELECT 1 FROM people.student WHERE matric_no = :n) OR EXISTS (SELECT 1 FROM people.matric_alias WHERE old_no = :n)
                        OR EXISTS (SELECT 1 FROM people.matric_history WHERE matric_no = :n)
                    """).param("n", n).query(Boolean.class).single();
            if (!Boolean.TRUE.equals(taken)) {
                return n;
            }
        }
        throw new IllegalStateException("no free made-up number");
    }

    private UUID student(String surname, String programme, String matric) {
        UUID id = UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
                VALUES (:id, :m, :s, 'Invented', :p, 'UTME', '2020/2021', 100, 300, 'ACTIVE', now())
                """).param("id", id).param("m", matric).param("s", surname).param("p", programme).update());
        return id;
    }

    private String numberOf(UUID student) {
        return jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
    }

    @Test
    void theAcademicOfficePreparesTheRegistryDecidesAndTheOldNumberStillFindsTheStudent() {
        String programme = configuredProgramme();
        String surname = it.freeSurname("ZZMCR");
        String oldA = freeOldNumber(), numberB = freeOldNumber();
        UUID a = student(surname, programme, oldA), b = student(surname, programme, numberB);
        UUID preparer = UUID.randomUUID();
        String academic = TestTokens.token(preparer, List.of("academic"));

        // the student found by the number, and the number the configuration proposes
        ResponseEntity<List> found = it.callList(academic, HttpMethod.GET, BASE + "/search?q=" + oldA, null);
        assertThat(found.getStatusCode().value()).as(String.valueOf(found.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) found.getBody()).extracting(r -> r.get("student_id")).containsExactly(a.toString());
        ResponseEntity<Map> one = it.get(academic, BASE + "/students/" + a);
        assertThat(one.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> suggestions = (List<Map<String, Object>>) one.getBody().get("suggestions");
        String corrected = String.valueOf(suggestions.get(0).get("matric_no"));
        assertThat(corrected).endsWith(oldA.substring(oldA.lastIndexOf("/86/"))).isNotEqualTo(oldA);

        // another student's number is refused by name
        ResponseEntity<Map> taken = it.call(academic, HttpMethod.POST, BASE + "/check", Map.of("student", a, "newNo", numberB));
        assertThat(taken.getStatusCode().value()).isEqualTo(200);
        assertThat((Boolean) taken.getBody().get("ok")).isFalse();
        assertThat(String.valueOf(((List<Map<String, Object>>) taken.getBody().get("problems")).get(0).get("message"))).startsWith("MATRICULATION NUMBER ALREADY ASSIGNED");
        ResponseEntity<Map> refused = it.call(academic, HttpMethod.POST, BASE, Map.of("student", a, "newNo", numberB, "kind", "DATA_ENTRY", "reason", "the other student's number"));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody()).containsEntry("code", "MATRIC_CORRECTION_TAKEN");

        // the Bursary does not prepare one; ICT Support reads and does not prepare
        Map<String, Object> body = Map.of("student", a, "newNo", corrected, "kind", "PROGRAMME_CODE", "reason", "The programme code was imported wrongly from the old portal",
                "approvalRef", "REG/MEMO/86/1");
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, BASE, body).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("ictagent"), HttpMethod.POST, BASE, body).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("ictagent"), BASE + "/students/" + a).getStatusCode().value()).isEqualTo(200);

        // prepared, with evidence; nothing reaches the student yet
        ResponseEntity<Map> prepared = it.call(academic, HttpMethod.POST, BASE, body);
        assertThat(prepared.getStatusCode().value()).as(String.valueOf(prepared.getBody())).isEqualTo(200);
        assertThat(prepared.getBody()).containsEntry("state", "PENDING_REVIEW").containsEntry("mayDecide", false);
        assertThat(String.valueOf(prepared.getBody().get("ref"))).startsWith("MCR/");
        String id = String.valueOf(prepared.getBody().get("id"));
        ResponseEntity<Map> withFile = it.call(academic, HttpMethod.POST, BASE + "/" + id + "/evidence", Map.of("filename", "memo.png", "dataUrl", PNG));
        assertThat(withFile.getStatusCode().value()).as(String.valueOf(withFile.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) withFile.getBody().get("evidence")).hasSize(1);
        assertThat(numberOf(a)).isEqualTo(oldA);

        // not decided by the officer who prepared it, by the Director of ICT (not a legacy migration) or by the Bursary
        ResponseEntity<Map> same = it.call(academic, HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("approve", true));
        assertThat(same.getStatusCode().value()).isEqualTo(403);
        assertThat(same.getBody()).containsEntry("code", "MATRIC_CORRECTION_SAME_OFFICER");
        ResponseEntity<Map> ict = it.call(ItSupport.token("ict"), HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("approve", true));
        assertThat(ict.getStatusCode().value()).isEqualTo(403);
        assertThat(ict.getBody()).containsEntry("code", "MATRIC_CORRECTION_DECIDER");
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("approve", true)).getStatusCode().value()).isEqualTo(403);

        // the Registry approves it: the number changes and nothing else
        String registrar = ItSupport.token("registrar");
        ResponseEntity<Map> seen = it.get(registrar, BASE + "/" + id);
        assertThat(seen.getBody()).containsEntry("mayDecide", true);
        ResponseEntity<Map> done = it.call(registrar, HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("approve", true, "note", "Checked against the matriculation register"));
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("state", "COMPLETED");
        assertThat(numberOf(a)).isEqualTo(corrected);
        assertThat(jdbc.sql("SELECT surname || '|' || current_level || '|' || programme_code || '|' || status FROM people.student WHERE id = :s").param("s", a)
                .query(String.class).single()).isEqualTo(surname + "|300|" + programme + "|ACTIVE");

        // the old number still finds the student: the register, the search (saying it was corrected), the record's panel
        ResponseEntity<Map> register = it.get(registrar, "/api/v1/student/students?q=" + oldA);
        assertThat((List<Map<String, Object>>) register.getBody().get("rows")).extracting(r -> r.get("matricNo")).containsExactly(corrected);
        ResponseEntity<Map> search = it.get(registrar, "/api/v1/student/search?q=" + oldA);
        assertThat((List<Map<String, Object>>) search.getBody().get("hits")).filteredOn(h -> a.toString().equals(h.get("id"))).singleElement()
                .satisfies(h -> {
                    assertThat(h.get("identifier")).isEqualTo(corrected);
                    assertThat(String.valueOf(h.get("detail"))).contains("Matriculation number corrected from " + oldA);
                });
        ResponseEntity<Map> record = it.get(registrar, "/api/v1/matriculation/students/" + a + "/record");
        assertThat((List<Map<String, Object>>) record.getBody().get("corrections")).extracting(c -> c.get("state")).containsExactly("COMPLETED");
        assertThat((List<Map<String, Object>>) record.getBody().get("numberHistory")).extracting(h -> h.get("event")).contains("CORRECTED", "ON_THE_REGISTER");

        // the sign-in door and the sign-in help say the number was corrected, never the new one
        ResponseEntity<Map> door = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", oldA, "password", "anything at all"));
        assertThat(door.getBody()).containsEntry("code", "STUDENT_NUMBER_CORRECTED");
        assertThat(String.valueOf(door.getBody())).doesNotContain(corrected);
        ResponseEntity<Map> help = it.anon(HttpMethod.POST, "/api/v1/helpdesk/sign-in-help/check", Map.of("accountType", "Student portal", "number", oldA));
        assertThat(help.getBody()).containsEntry("found", true).containsEntry("corrected", true);

        // a correction rejected with its reason, and one cancelled by the officer who prepared it
        ResponseEntity<Map> second = it.call(academic, HttpMethod.POST, BASE, Map.of("student", b, "newNo", freeOldNumber(), "kind", "SEQUENCE",
                "reason", "The sequence was keyed with a slip"));
        assertThat(second.getStatusCode().value()).as(String.valueOf(second.getBody())).isEqualTo(200);
        String secondId = String.valueOf(second.getBody().get("id"));
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/" + secondId + "/decide", Map.of("approve", false)).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> rejected = it.call(registrar, HttpMethod.POST, BASE + "/" + secondId + "/decide", Map.of("approve", false, "note", "The register shows the number as issued"));
        assertThat(rejected.getBody()).containsEntry("state", "REJECTED");
        ResponseEntity<Map> third = it.call(academic, HttpMethod.POST, BASE, Map.of("student", b, "newNo", freeOldNumber(), "kind", "SEQUENCE",
                "reason", "The sequence was keyed with a slip"));
        ResponseEntity<Map> cancelled = it.call(academic, HttpMethod.POST, BASE + "/" + third.getBody().get("id") + "/cancel", Map.of("reason", "Prepared against the wrong student"));
        assertThat(cancelled.getBody()).containsEntry("state", "CANCELLED");
        assertThat(numberOf(b)).isEqualTo(numberB);
        ResponseEntity<List> pending = it.callList(registrar, HttpMethod.GET, BASE + "?state=PENDING_REVIEW&q=" + surname, null);
        assertThat((List<Map<String, Object>>) pending.getBody()).isEmpty();
    }
}
