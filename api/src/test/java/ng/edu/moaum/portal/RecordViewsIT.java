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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V530: who opened a student's record, through the doors. The Registrar opens a student's record twice: one view, for the
 * Registrar's person and office; a failed opening is none; the student sees the office and when, never who; Internal Audit finds
 * the view by the student, and the Registrar does not read the log. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class RecordViewsIT {

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

    @Test
    void anOfficeOpeningAStudentsRecordIsRecordedOnceAndTheStudentSeesWhichOffice() {
        UUID student = it.student(it.freeSurname("ZZVIEWED"), "C00061", it.freeNumber("MOAUM/ADM/66/", 6), it.freeNumber("MOAUM/RVW/66/", 6), 100);
        UUID registrarPerson = UUID.randomUUID();
        String registrar = TestTokens.token(registrarPerson, List.of("registrar"));

        assertThat(it.get(registrar, "/api/v1/student/students/" + student).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(registrar, "/api/v1/student/students/" + student).getStatusCode().value()).isEqualTo(200);   // within ten minutes: the same view
        assertThat(it.get(registrar, "/api/v1/student/students/" + UUID.randomUUID()).getStatusCode().value()).isNotEqualTo(200);   // nobody's record: no view
        List<Map<String, Object>> rows = jdbc.sql("SELECT viewer_id, office, record FROM people.record_view WHERE student_id = :s").param("s", student).query().listOfRows();
        assertThat(rows).hasSize(1);
        assertThat(rows.getFirst()).containsEntry("viewer_id", registrarPerson).containsEntry("office", "registrar").containsEntry("record", "STUDENT_RECORD");

        // the student: which office, and when — never who
        String me = TestTokens.token(student, List.of("student"));
        ResponseEntity<List> mine = it.getList(me, "/api/v1/me/record-views");
        assertThat(mine.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> seen = (List<Map<String, Object>>) (List) mine.getBody();
        assertThat(seen).hasSize(1);
        assertThat(seen.getFirst()).containsEntry("office", "registrar").containsKey("office_label").doesNotContainKeys("viewer_id", "viewer");
        assertThat(it.get(registrar, "/api/v1/me/record-views").getStatusCode().value()).isEqualTo(403);

        // Internal Audit finds it by the student; the Registrar does not read the log
        ResponseEntity<Map> audit = it.get(ItSupport.token("audit"), "/api/v1/audit/record-views?student=" + student);
        assertThat(audit.getStatusCode().value()).as(String.valueOf(audit.getBody())).isEqualTo(200);
        assertThat(((Number) audit.getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((List<Map<String, Object>>) audit.getBody().get("rows")).getFirst()).containsEntry("office", "registrar").containsEntry("record", "STUDENT_RECORD");
        assertThat(it.get(registrar, "/api/v1/audit/record-views").getStatusCode().value()).isEqualTo(403);
    }
}
