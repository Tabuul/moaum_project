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
 * V647: school-fees history, JAMB number to matriculation number, through the API. The Bursary loads an old-portal file whose
 * "matriculation number" is a made-up student's JAMB number (paid before matriculation) beside one under the matriculation number: both
 * are the student's, the JAMB one with the number kept, shown on the full record, and the student is found by the JAMB number. A row
 * whose number names no student is held; once the student is on the register, the Students Account Officer initiates the batch, the
 * Bursar decides it (the initiating office is refused the decision), and the payment is the student's. The Registrar reads none of it.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class FeeHistoryReconciliationIT {

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

    private UUID student(int n, String jamb) {
        UUID id = UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level,
                                            current_level, status, matriculated_at, jamb_reg_no)
                VALUES (:id, :adm, :m, 'ZZJAMBPAY', 'Invented Payer', 'C00023', 'UTME', '9999/0000', 100, 200, 'ACTIVE', now(), :j)
                """).param("id", id).param("adm", String.format("MOAUM/ADM/99/%06d", n)).param("m", "MOAUM/JPY/99/" + n).param("j", jamb).update());
        return id;
    }

    private static Map<String, Object> row(String matno, String session, String amount, String payref) {
        return Map.of("matric", matno, "session", session, "semester", "First", "amount", amount, "purpose", "SCHOOL FEES", "receiptNo", payref, "paidOn", "2025-01-15");
    }

    @Test
    void aJambNamedPaymentIsTheStudentsAndAHeldOneIsReconciledByTwoOffices() {
        int n = ThreadLocalRandom.current().nextInt(100_000, 999_999);
        String jamb = "9964" + n + "11ZQ";
        String later = "9965" + n + "22ZQ";
        String session = String.format("%04d/%04d", 9600 + n % 90, 9601 + n % 90);
        UUID a = student(n, jamb);
        String bursar = ItSupport.token("bursar");

        ResponseEntity<Map> load = it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", List.of(
                row(jamb, session, "50000", "ITJP" + n + "A"),
                row("MOAUM/JPY/99/" + n, session, "30000", "ITJP" + n + "B"),
                row(later, session, "45000", "ITJP" + n + "C"))));
        assertThat(load.getStatusCode().value()).as(String.valueOf(load.getBody())).isEqualTo(200);

        // both payments are the student's; the JAMB one keeps its number, shown on the full record
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND channel = 'Legacy'").param("s", a).query(Long.class).single()).isEqualTo(2L);
        Map<String, Object> finance = it.get(bursar, "/api/v1/student/students/" + a + "/full/finance").getBody();
        List<Map<String, Object>> payments = (List<Map<String, Object>>) finance.get("payments");
        assertThat(payments).anySatisfy(p -> {
            assertThat(p.get("original_identifier")).isEqualTo(jamb);
            assertThat(p.get("original_identifier_type")).isEqualTo("JAMB_NUMBER");
        });
        // found by the JAMB number
        ResponseEntity<Map> found = it.get(ItSupport.token("academic"), "/api/v1/student/students?q=" + jamb);
        assertThat(String.valueOf(found.getBody())).contains(a.toString());

        // the unknown number is held; the student comes onto the register; matched now
        String path = "/api/v1/finance/fee-history-reconciliation";
        Map<String, Object> held = it.get(bursar, path + "/held?q=" + later).getBody();
        assertThat(((List<Map<String, Object>>) held.get("rows")).get(0)).containsEntry("category", "NO_MATCH");
        UUID d = student(n + 1, later);
        held = it.get(bursar, path + "/held?q=" + later).getBody();
        assertThat(((List<Map<String, Object>>) held.get("rows")).get(0)).containsEntry("category", "MATCHED");
        assertThat(it.get(ItSupport.token("registrar"), path + "/held").getStatusCode().value()).isEqualTo(403);

        // the Students Account Officer initiates; the decision is the Bursar's
        String sao = ItSupport.token("studentaccounts");
        ResponseEntity<Map> initiated = it.call(sao, HttpMethod.POST, path + "/batches", Map.of("allMatched", true, "q", later, "reason", "Paid before matriculation under the JAMB number"));
        assertThat(initiated.getStatusCode().value()).as(String.valueOf(initiated.getBody())).isEqualTo(200);
        String ref = String.valueOf(initiated.getBody().get("ref"));
        assertThat(ref).matches("PAY-RECON/\\d{4}/\\d{6}");
        String bp = path + "/batches/" + ref.substring("PAY-RECON/".length());
        assertThat(it.call(sao, HttpMethod.POST, bp + "/decide", Map.of("approve", true)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> decided = it.call(bursar, HttpMethod.POST, bp + "/decide", Map.of("approve", true, "note", "Checked against the old portal statement"));
        assertThat(decided.getStatusCode().value()).as(String.valueOf(decided.getBody())).isEqualTo(200);
        assertThat(decided.getBody()).containsEntry("state", "APPROVED").containsEntry("reconciled", 1);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND channel = 'Legacy' AND amount = 45000").param("s", d).query(Long.class).single()).isEqualTo(1L);
    }
}
