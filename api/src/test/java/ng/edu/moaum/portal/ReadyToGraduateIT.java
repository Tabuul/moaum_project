package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * V668 through the API: a made-up graduand of a session of their own, the award approved, every office but the Bursary cleared and
 * the session's fees paid. The Bursar's queue lists them ready; the student reads the final clearance waiting only on the Bursary
 * with nothing owed; the Registry's general change of status refuses GRADUATED and the certificate is not printed before the
 * graduation; the Students Account Officer reads the queue but does not confirm; the Bursar confirms and the student is graduated,
 * leaving the queue and reading the graduation. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ReadyToGraduateIT {

    private static final String Q = "/api/v1/clearance/ready-to-graduate";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    /** the line the test states is taken away (FeeLineLeakGuard) */
    @AfterEach
    void takeAwayFeeLines() {
        if (it != null && session != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update());
    }

    @Test
    void theBursarsQueueListsTheReadyGraduandAndTheConfirmationGraduatesThem() {
        int y = it.freeYear(7800, 7990, 0, 1);
        session = y + "/" + (y + 1);
        it.session(session, y);
        String surname = it.freeSurname("ZZREADYGRAD");
        UUID st = it.student(surname, "C00023", it.freeNumber("MOAUM/ADM/78/", 6), it.freeNumber("MOAUM/RTG/78/", 6), 400);
        UUID process = it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :e, entry_level = 400 WHERE id = :s").param("e", session).param("s", st).update();
            jdbc.sql("INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :s, :a, 400)").param("s", st).param("a", session).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, semester) VALUES (:a, 'V668 IT fees', 80000, 400, 'C00023', NULL)")
                    .param("a", session).update();
            jdbc.sql("""
                    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                    VALUES (:s, :a, :r, 'School fees ' || :a, 80000, now(), now(), gen_random_uuid(), 'Bank branch', :r)
                    """).param("s", st).param("a", session).param("r", "MOAUM-FEE-RTG-" + y).update();
            jdbc.sql("INSERT INTO records.graduand (id, student_id, session, cgpa, award, unmet) VALUES (gen_random_uuid(), :s, :a, 3.40, 'B.Sc.', NULL)")
                    .param("s", st).param("a", session).update();
            jdbc.sql("SELECT records.graduate_one(:s, :a, 'SEN/IT/668', NULL, 'V668 IT: the award', gen_random_uuid(), 'academic')").param("s", st).param("a", session)
                    .query().listOfRows();
            UUID p = jdbc.sql("SELECT id FROM clearance.process WHERE workflow = 'FINAL' AND student_id = :s AND cancelled_at IS NULL").param("s", st).query(UUID.class).single();
            jdbc.sql("""
                    SELECT count(clearance.decide(:p, r.unit, 'CLEARED', 'IT: cleared by the Registry', NULL, NULL, true, gen_random_uuid(), 'registrar'))
                      FROM clearance.stage_rows('CONVOCATION', :a, ARRAY[CAST(:s AS uuid)]) r WHERE r.unit <> 'BURSARY' AND r.applies AND r.required
                    """).param("p", p).param("a", session).param("s", st).query(Long.class).single();
            return p;
        });
        String bursar = ItSupport.token("bursar");
        String officer = ItSupport.token("studentaccounts");
        String student = TestTokens.token(st, List.of("student"));

        // the Bursar's queue: the graduand ready
        Map<String, Object> queue = it.get(bursar, Q + "?q=" + surname).getBody();
        assertThat(queue).containsEntry("total", 1).containsEntry("canConfirm", true);
        assertThat((List<Map<String, Object>>) queue.get("rows")).singleElement().satisfies(r -> {
            assertThat(r).containsEntry("process_id", process.toString()).containsEntry("ready", true).containsEntry("basis", "SENATE");
            assertThat(((Number) r.get("outstanding")).intValue()).isZero();
        });
        // the student reads the final clearance waiting only on the Bursary, nothing owed
        Map<String, Object> mine = (Map<String, Object>) it.get(student, "/api/v1/me/clearance").getBody().get("final");
        assertThat(mine).containsEntry("awaiting", true).containsEntry("graduated", false).containsEntry("bursaryState", "PENDING");
        assertThat((List<?>) mine.get("othersPending")).isEmpty();
        assertThat(((Number) mine.get("outstanding")).intValue()).isZero();

        // the Registry's general change of status refuses GRADUATED; the certificate waits for the graduation
        ResponseEntity<Map> byHand = it.call(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/student/students/" + st + "/status",
                Map.of("to", "GRADUATED", "instrument", "SEN/IT/668", "reason", "Looks finished to the officer"));
        assertThat(byHand.getStatusCode().value()).isEqualTo(422);
        assertThat(byHand.getBody()).containsEntry("code", "STU_STATUS_GRADUATION");
        ResponseEntity<Map> early = it.call(ItSupport.token("academic"), HttpMethod.POST, "/api/v1/credentials/certificates", Map.of("studentId", st));
        assertThat(early.getStatusCode().value()).isEqualTo(422);
        assertThat(early.getBody()).containsEntry("code", "CRED_NOT_CLEARED");   // the Bursary has not cleared: the certificate waits

        // the Students Account Officer reads the queue but does not confirm; the Bursar confirms and the student is graduated
        assertThat(it.get(officer, Q + "?q=" + surname).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(officer, HttpMethod.POST, Q + "/confirm", Map.of("processes", List.of(process))).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> done = it.call(bursar, HttpMethod.POST, Q + "/confirm", Map.of("processes", List.of(process)));
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody()).containsEntry("graduated", 1).containsEntry("cleared", 1);
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", st).query(String.class).single()).isEqualTo("GRADUATED");
        assertThat(it.get(bursar, Q + "?q=" + surname).getBody()).containsEntry("total", 0);
        assertThat((Map<String, Object>) it.get(student, "/api/v1/me/clearance").getBody().get("final")).containsEntry("graduated", true).containsEntry("awaiting", false);
    }
}
