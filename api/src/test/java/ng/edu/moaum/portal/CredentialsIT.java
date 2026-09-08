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
 * A transcript is not produced unpaid or held, is produced by one officer
 * and signed by another; a certificate is printed only against a
 * Senate-approved, cleared graduand, on a serial off the batch, and a lost
 * one is reissued as a duplicate with the original kept. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class CredentialsIT {

    static final String SESSION = "2095/2096";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic = ItSupport.token("academic");
    String registrar = ItSupport.token("registrar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2095);
    }

    @Test
    void aTranscriptIsProducedByOneOfficerAndSignedByAnother() {
        UUID student = it.student("ZZCTRANSCRIPT", "C00023", null, "MOAUM/MTC/95/9001", 400);

        ResponseEntity<Map> req = it.call(academic, HttpMethod.POST, "/api/v1/credentials/transcript-requests",
                Map.of("studentId", student.toString(), "destination", "EMPLOYER", "destinationName", "An invented employer", "mode", "DIGITAL", "copies", 1, "paid", false));
        assertThat(req.getStatusCode().value()).as(String.valueOf(req.getBody())).isEqualTo(200);
        Map<?, ?> row = (Map<?, ?>) req.getBody().get("row");
        String id = String.valueOf(row.get("id"));
        assertThat(row.get("stage")).isEqualTo("AWAITING_PAYMENT");
        assertThat(String.valueOf(row.get("ref"))).matches("TRN-\\d{4}-\\d{5}");

        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/credentials/transcript-requests/" + id + "/produce", null).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> paid = it.call(registrar, HttpMethod.POST, "/api/v1/credentials/transcript-requests/" + id + "/mark-paid", null);
        assertThat(((Map<?, ?>) paid.getBody().get("row")).get("stage")).isEqualTo("HELD_AT_CLEARANCE");
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/credentials/transcript-requests/" + id + "/produce", null).getStatusCode().value()).isEqualTo(422);

        for (String unit : List.of("BURSARY", "LIBRARY", "DEPARTMENT")) {
            ResponseEntity<Map> c = it.call(registrar, HttpMethod.POST, "/api/v1/clearance/students/" + student + "/" + unit + "/clear",
                    Map.of("purpose", "TRANSCRIPT", "note", "test"));
            assertThat(c.getStatusCode().value()).as(unit + ": " + c.getBody()).isEqualTo(200);
        }
        // the transcript is held only by these three; the other units clear it too, so the whole record is clear
        for (String unit : List.of("FACULTY", "HEALTH", "HOSTEL", "WORKS", "ALUMNI")) {
            it.call(registrar, HttpMethod.POST, "/api/v1/clearance/students/" + student + "/" + unit + "/clear", Map.of("purpose", "TRANSCRIPT"));
        }
        ResponseEntity<Map> produced = it.call(academic, HttpMethod.POST, "/api/v1/credentials/transcript-requests/" + id + "/produce", null);
        assertThat(produced.getStatusCode().value()).as(String.valueOf(produced.getBody())).isEqualTo(200);
        assertThat(((Map<?, ?>) produced.getBody().get("row")).get("stage")).isEqualTo("VERIFIED");

        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/credentials/transcript-requests/" + id + "/release", null).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> released = it.call(registrar, HttpMethod.POST, "/api/v1/credentials/transcript-requests/" + id + "/release", null);
        assertThat(released.getStatusCode().value()).as(String.valueOf(released.getBody())).isEqualTo(200);
        assertThat(((Map<?, ?>) released.getBody().get("row")).get("stage")).isEqualTo("RELEASED");

        ResponseEntity<Map> queue = it.get(academic, "/api/v1/credentials/transcript-requests");
        assertThat(queue.getStatusCode().value()).isEqualTo(200);
        assertThat((List<?>) queue.getBody().get("requests")).isNotEmpty();
    }

    @Test
    void aCertificateIsPrintedOnlyAgainstAnApprovedClearedGraduand() {
        UUID student = it.student("ZZCCERTIFICATE", "C00023", null, "MOAUM/MTC/95/9002", 400);

        ResponseEntity<Map> refused = it.call(academic, HttpMethod.POST, "/api/v1/credentials/certificates", Map.of("studentId", student.toString()));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("CRED_NOT_GRADUATED");

        it.db(() -> jdbc.sql("""
                INSERT INTO records.graduand (id, student_id, session, cgpa, award, senate_state, senate_minute)
                VALUES (gen_random_uuid(), :s, :sess, 4.62, 'B.Sc. COMPUTER SCIENCE', 'APPROVED', 'SEN/2096/01')
                ON CONFLICT (student_id, session) DO NOTHING
                """).param("s", student).param("sess", SESSION).update());
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/credentials/certificates", Map.of("studentId", student.toString()))
                .getBody().get("code")).isEqualTo("CRED_NOT_CLEARED");

        for (String unit : List.of("BURSARY", "DEPARTMENT", "FACULTY", "LIBRARY", "HEALTH", "HOSTEL", "WORKS", "ALUMNI")) {
            it.call(registrar, HttpMethod.POST, "/api/v1/clearance/students/" + student + "/" + unit + "/clear", Map.of("purpose", "CONVOCATION"));
        }
        String batchName = "ZZB-" + UUID.randomUUID().toString().substring(0, 8);
        ResponseEntity<Map> batch = it.call(academic, HttpMethod.POST, "/api/v1/credentials/stationery",
                Map.of("batch", batchName, "serialFrom", 1, "serialTo", 50, "receivedOn", "2095-09-01"));
        assertThat(batch.getStatusCode().value()).as(String.valueOf(batch.getBody())).isEqualTo(200);

        ResponseEntity<Map> printed = it.call(academic, HttpMethod.POST, "/api/v1/credentials/certificates",
                Map.of("studentId", student.toString(), "batchId", String.valueOf(batch.getBody().get("id"))));
        assertThat(printed.getStatusCode().value()).as(String.valueOf(printed.getBody())).isEqualTo(200);
        assertThat(String.valueOf(printed.getBody().get("number"))).matches("MOAUM/C/\\d{2}/\\d{5}");
        assertThat(printed.getBody().get("classOfDegree")).isEqualTo("First Class Honours");
        String id = String.valueOf(printed.getBody().get("id"));

        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/credentials/certificates/" + id + "/collect", Map.of("note", "test")).getBody().get("status"))
                .isEqualTo("COLLECTED");
        ResponseEntity<Map> dup = it.call(registrar, HttpMethod.POST, "/api/v1/credentials/certificates/" + id + "/reissue",
                Map.of("reason", "affidavit and police report, test"));
        assertThat(dup.getStatusCode().value()).as(String.valueOf(dup.getBody())).isEqualTo(200);
        assertThat(dup.getBody().get("number")).isNotEqualTo(printed.getBody().get("number"));
        assertThat(String.valueOf(dup.getBody().get("duplicateOf"))).isEqualTo(id);

        ResponseEntity<Map> register = it.get(academic, "/api/v1/credentials/certificates");
        assertThat(register.getStatusCode().value()).isEqualTo(200);
        List<?> certs = (List<?>) register.getBody().get("certificates");
        assertThat(certs.stream().map(c -> String.valueOf(((Map<?, ?>) c).get("status")))).contains("REISSUED", "PRINTED");
    }
}
