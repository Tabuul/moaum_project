package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * V642: the Academic Office student edit page through the API. The Academic Office reads a made-up student's page — the record,
 * the version it reads, its grants, the level options, the lists; the Bursary holds no grant and is refused. An edit on an older
 * reading is refused (STU_EDIT_STALE); one on the reading the page gave is saved under its STU-EDIT reference and the version moves
 * on; Records reads the history and may not edit; GRADUATED is graduation's, not a status set from the page; the student is found by
 * the matriculation number. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentEditIT {

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

    /** a made-up active student, matriculated, on B.Sc. Computer Science at 200 */
    private Map<String, String> student() {
        int n = ThreadLocalRandom.current().nextInt(100_000, 999_999);
        UUID id = UUID.randomUUID();
        String matric = "MOAUM/EDT/99/" + n;
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level,
                                            current_level, status, matriculated_at, jamb_reg_no)
                VALUES (:id, :adm, :m, 'ZZEDITIT', 'Invented Record', 'C00023', 'UTME', '9999/0000', 100, 200, 'ACTIVE', now(), :j)
                """).param("id", id).param("adm", String.format("MOAUM/ADM/99/%06d", n)).param("m", matric).param("j", "9964" + n + "0ZQ").update());
        return Map.of("id", id.toString(), "matric", matric);
    }

    @Test
    void theAcademicOfficeEditsOnTheReadingItMadeAndTheRestAreRefused() {
        String academic = ItSupport.token("academic");
        Map<String, String> s = student();
        String path = "/api/v1/student/students/" + s.get("id") + "/edit";

        ResponseEntity<Map> page = it.get(academic, path);
        assertThat(page.getStatusCode().value()).as(String.valueOf(page.getBody())).isEqualTo(200);
        assertThat(page.getBody()).containsKeys("student", "version", "permissions", "levelOptions", "lists", "position", "carryovers", "registrations");
        assertThat((List<String>) page.getBody().get("permissions")).contains("EDIT_STUDENT_ACADEMIC_RECORD", "EDIT_STUDENT_ADMISSION", "OVERRIDE_STUDENT_REGISTRATION");
        String version = String.valueOf(page.getBody().get("version"));

        // the Bursary holds no grant on the page
        assertThat(it.get(ItSupport.token("bursar"), path).getStatusCode().value()).isEqualTo(403);

        // an older reading is refused, nothing written
        ResponseEntity<Map> stale = it.call(academic, HttpMethod.PUT, path, Map.of("changes", Map.of("study_mode", "PART_TIME"),
                "reason", "Corrected from the admission letter on the student's file", "version", "an-older-reading"));
        assertThat(stale.getStatusCode().value()).isEqualTo(422);
        assertThat(stale.getBody()).containsEntry("code", "STU_EDIT_STALE");

        // on the reading the page gave: saved under its reference, and the version moves on
        ResponseEntity<Map> saved = it.call(academic, HttpMethod.PUT, path, Map.of("changes", Map.of("study_mode", "PART_TIME"),
                "reason", "Corrected from the admission letter on the student's file", "version", version));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat(saved.getBody()).containsEntry("changed", 1);
        assertThat(String.valueOf(((List<Map<String, Object>>) saved.getBody().get("edits")).get(0).get("reference"))).matches("STU-EDIT/\\d{4}/\\d{6}");
        assertThat(saved.getBody().get("version")).isNotEqualTo(version);
        assertThat(jdbc.sql("SELECT study_mode FROM people.student WHERE id = CAST(:s AS uuid)").param("s", s.get("id")).query(String.class).single()).isEqualTo("PART_TIME");

        // Records reads the history and may not edit
        String records = ItSupport.token("records");
        ResponseEntity<Map> history = it.get(records, path + "/history?field=study");
        assertThat(history.getStatusCode().value()).as(String.valueOf(history.getBody())).isEqualTo(200);
        assertThat(((Number) history.getBody().get("total")).intValue()).isEqualTo(1);
        ResponseEntity<Map> refused = it.call(records, HttpMethod.PUT, path, Map.of("changes", Map.of("study_mode", "FULL_TIME"),
                "reason", "Corrected from the admission letter on the student's file", "version", String.valueOf(saved.getBody().get("version"))));
        assertThat(refused.getStatusCode().value()).isEqualTo(403);

        // graduation is graduation's own
        ResponseEntity<Map> graduated = it.call(academic, HttpMethod.POST, path + "/status", Map.of("to", "GRADUATED", "instrument", "Senate minute 9/99",
                "reason", "Graduated on the official graduation list of the session", "confirmCritical", true, "version", String.valueOf(saved.getBody().get("version"))));
        assertThat(graduated.getStatusCode().value()).isEqualTo(422);
        assertThat(graduated.getBody()).containsEntry("code", "STU_EDIT_GRADUATION");

        // found by the matriculation number, on the server
        ResponseEntity<List> found = it.callList(academic, HttpMethod.GET, "/api/v1/student/edit/search?q=" + s.get("matric"), null);
        assertThat(found.getStatusCode().value()).isEqualTo(200);
        assertThat(found.getBody()).anySatisfy(h -> assertThat(((Map<String, Object>) h).get("id")).isEqualTo(s.get("id")));
    }
}
