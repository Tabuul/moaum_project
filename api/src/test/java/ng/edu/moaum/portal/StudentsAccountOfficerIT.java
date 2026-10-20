package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * V520: the Students Account Officer, a Bursary sub-office, through the doors. It reads the payment reports with amounts and
 * transactions, the Bursary's view, the hanging payments desk, NELFUND, Student Query and the unpaid registrations; it states the
 * session's school fees (a line added, the same line refused twice, ended) and reads the fee history; it acts on the hanging payments
 * desk; and it is refused everything else of the Bursar's: the clearance scheme, confirming a payment, refunds, bank credits, the
 * collections import, a test checkout, NELFUND credits and the transfer fee. V591: it holds the Old Fees History desk's import (not
 * the go-live reset or the ledger) and the level desk (finds any student, progresses the level, reads the history) and no other door
 * of the ICT Support Desk. A lecturer does not read the payments. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudentsAccountOfficerIT {

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

    @AfterEach
    void clean() {
        if (session != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update());
    }

    private int status(String token, HttpMethod method, String path, Object body) {
        return it.call(token, method, path, body).getStatusCode().value();
    }

    @Test
    void theStudentsAccountOfficerReadsReportsStatesSchoolFeesWorksTheHangingDeskAndHoldsNoneOfTheBursarsOtherPowers() {
        assertThat(jdbc.sql("SELECT label FROM ref.office WHERE code = 'studentaccounts'").query(String.class).optional()).isPresent();
        String sao = ItSupport.token("studentaccounts");
        int y = 6000 + new Random().nextInt(300);
        session = y + "/" + (y + 1);
        it.session(session, y);
        String path = "/api/v1/finance/sessions/" + y + "/" + (y + 1);

        // the reports: amounts and transactions, University-wide
        ResponseEntity<Map> summary = it.get(sao, "/api/v1/analytics/finance/summary?session=" + session + "&compare=false");
        assertThat(summary.getStatusCode().value()).as(String.valueOf(summary.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) summary.getBody().get("scope")).containsEntry("money", true).containsEntry("kind", "UNIVERSITY");
        assertThat(it.get(sao, "/api/v1/analytics/finance/transactions?session=" + session).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(ItSupport.token("lecturer"), "/api/v1/analytics/finance/transactions?session=" + session).getStatusCode().value()).isEqualTo(403);
        for (String read : List.of("/api/v1/finance/bursary?session=" + session, "/api/v1/payments/bursary", "/api/v1/payments/claims",
                "/api/v1/nelfund/figures?session=" + session, "/api/v1/nelfund/legacy/summary", "/api/v1/stats/students/query",
                "/api/v1/finance/registrations-without-fees?session=" + session, "/api/v1/finance/payments", path + "/schedule", path + "/schedule/history")) {
            assertThat(it.getBytes(sao, read).getStatusCode().value()).as(read).isEqualTo(200);
        }

        // the school fees: a line stated, the same line refused twice, ended; the history shows it
        Map<String, Object> line = new HashMap<>(Map.of("item", "School fees (SAO test)", "amount", 45000, "level", 100, "programmeCode", "C00061"));
        ResponseEntity<Map> added = it.call(sao, HttpMethod.POST, path + "/schedule", line);
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
        ResponseEntity<Map> twice = it.call(sao, HttpMethod.POST, path + "/schedule", line);
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody()).containsEntry("code", "FEE_LINE_DUPLICATE");
        UUID id = jdbc.sql("SELECT id FROM finance.fee_schedule WHERE session = :s AND item = 'School fees (SAO test)' AND ended_at IS NULL").param("s", session).query(UUID.class).single();
        assertThat(status(sao, HttpMethod.POST, path + "/schedule/" + id + "/end", Map.of())).isEqualTo(200);
        List<Map<String, Object>> history = (List<Map<String, Object>>) (List) it.getList(sao, path + "/schedule/history").getBody();
        assertThat(history).anySatisfy(h -> { assertThat(h.get("item")).isEqualTo("School fees (SAO test)"); assertThat(h.get("office")).isEqualTo("studentaccounts"); });

        // the hanging payments desk acts (an unknown event is not found, never forbidden)
        assertThat(status(sao, HttpMethod.POST, "/api/v1/payments/events/" + UUID.randomUUID() + "/resolve", Map.of("resolution", "Integration test: checked with the gateway")))
                .isNotEqualTo(403);
        // and asks the gateway about a payer's reference, as the Bursar does — a lecturer is answered as a payer, for whom it is not theirs
        UUID payer = it.student(it.freeSurname("ZZSAOPAYER"), "C00061", it.freeNumber("MOAUM/ADM/60/", 6), null, 100);
        String ref = "MOAUM-FEE-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        it.db(() -> jdbc.sql("INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at) VALUES (:s, :ses, :r, 'School fees (SAO test)', 45000, now() + interval '1 day')")
                .param("s", payer).param("ses", session).param("r", ref).update());
        assertThat(status(sao, HttpMethod.POST, "/api/v1/payments/verify", Map.of("reference", ref))).isEqualTo(200);
        assertThat(status(ItSupport.token("lecturer"), HttpMethod.POST, "/api/v1/payments/verify", Map.of("reference", ref))).isEqualTo(404);

        // none of the Bursar's other powers (each with a body that passes validation, so the answer is the office's, not the form's)
        assertThat(status(sao, HttpMethod.POST, "/api/v1/finance/clearance-scheme", Map.of("instrument", "Integration test scheme"))).isEqualTo(403);
        assertThat(status(sao, HttpMethod.POST, "/api/v1/finance/references/MOAUM-NOPE/confirm", Map.of("channel", "BANK_BRANCH", "note", "integration test"))).isEqualTo(403);
        assertThat(status(sao, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("payer", "Integration test", "reason", "Integration test refund", "amount", 1000))).isEqualTo(403);
        assertThat(status(sao, HttpMethod.POST, "/api/v1/finance/bank-credits", Map.of("bank", "Test Bank", "instrument", "Teller 1", "amount", 1000))).isEqualTo(403);
        assertThat(status(sao, HttpMethod.POST, "/api/v1/payments/paydirect/import", Map.of("rows", List.of()))).isEqualTo(403);
        assertThat(status(sao, HttpMethod.POST, "/api/v1/payments/test-checkout", Map.of("number", "MOAUM/TEST/1"))).isEqualTo(403);
        assertThat(status(sao, HttpMethod.POST, "/api/v1/nelfund/credit", Map.of("number", "MOAUM/TEST/1", "reason", "Integration test credit"))).isEqualTo(403);
        assertThat(status(sao, HttpMethod.PUT, "/api/v1/finance/transfer-fee", Map.of("amount", 1000))).isEqualTo(403);

        // V591: the Old Fees History desk's import is the officer's (a body that passes the office and fails the form: FEE_ROWS, never
        // 403), as is what is loaded; the go-live reset and the ledger stay the Bursar's
        ResponseEntity<Map> oldFees = it.call(sao, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", List.of()));
        assertThat(oldFees.getStatusCode().value()).as(String.valueOf(oldFees.getBody())).isEqualTo(422);
        assertThat(oldFees.getBody()).containsEntry("code", "FEE_ROWS");
        assertThat(it.get(sao, "/api/v1/finance/legacy-fees/loaded").getStatusCode().value()).isEqualTo(200);
        assertThat(status(sao, HttpMethod.POST, "/api/v1/finance/legacy-fees/reset", Map.of("session", "", "confirm", "RESET"))).isEqualTo(403);
        assertThat(status(sao, HttpMethod.POST, "/api/v1/finance/accounting/sync?limit=1", Map.of())).isEqualTo(403);
        // V591: Old GST Payments too — the figures read, a run staged (an empty file refused by the form, never by the office), a student found
        assertThat(it.get(sao, "/api/v1/finance/legacy-gst/summary").getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> oldGst = it.call(sao, HttpMethod.POST, "/api/v1/finance/legacy-gst/imports", Map.of("rows", List.of(), "dryRun", true));
        assertThat(oldGst.getStatusCode().value()).as(String.valueOf(oldGst.getBody())).isEqualTo(422);
        assertThat(oldGst.getBody()).containsEntry("code", "LEGACY_ROWS_REQUIRED");
        assertThat(it.getBytes(sao, "/api/v1/finance/legacy-gst/students?q=zzsao").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(ItSupport.token("lecturer"), "/api/v1/finance/legacy-gst/summary").getStatusCode().value()).isEqualTo(403);

        // V591: the level desk — the officer finds any student, reads the level with both acts offered, progresses it, and the history
        // lists the change under the office; the rest of the ICT Support Desk stays closed to the office, and the level desk to the Bursar
        String lvName = it.freeSurname("ZZSAOLEVEL");
        UUID lv = it.student(lvName, "C00061", it.freeNumber("MOAUM/ADM/60/", 6), null, 100);
        // the officer is a person on the register (the support ledger names the person who acts), as every office holder is
        String officer = TestTokens.token(it.person("ZZ-SAO-" + lvName, "ZZSAOOFFICER"), List.of("studentaccounts"));
        ResponseEntity<Map> found = it.get(officer, "/api/v1/helpdesk/support/students?q=" + lvName);
        assertThat(found.getStatusCode().value()).as(String.valueOf(found.getBody())).isEqualTo(200);
        assertThat(String.valueOf(found.getBody())).contains(lv.toString());
        ResponseEntity<Map> level = it.get(officer, "/api/v1/helpdesk/support/students/" + lv + "/level");
        assertThat(level.getStatusCode().value()).as(String.valueOf(level.getBody())).isEqualTo(200);
        assertThat(level.getBody()).containsEntry("mayProgress", true).containsEntry("mayCorrect", true).containsEntry("scope", "The University");
        ResponseEntity<Map> progressed = it.call(officer, HttpMethod.POST, "/api/v1/helpdesk/support/students/" + lv + "/level",
                Map.of("action", "PROGRESS", "expected", 100, "reason", "Integration test: progressed by the Students Account Officer"));
        assertThat(progressed.getStatusCode().value()).as(String.valueOf(progressed.getBody())).isEqualTo(200);
        int newLevel = ((Number) progressed.getBody().get("newLevel")).intValue();
        assertThat(newLevel).isGreaterThan(100);
        assertThat(jdbc.sql("SELECT current_level FROM people.student WHERE id = :s").param("s", lv).query(Integer.class).single()).isEqualTo(newLevel);
        assertThat(jdbc.sql("SELECT actor_office FROM people.cohort_decision WHERE student_id = :s AND rule = 'LEVEL_PROGRESS' ORDER BY decided_at DESC LIMIT 1")
                .param("s", lv).query(String.class).single()).isEqualTo("studentaccounts");
        ResponseEntity<Map> changes = it.get(officer, "/api/v1/helpdesk/support/levels/history?q=" + lvName);
        assertThat(changes.getStatusCode().value()).as(String.valueOf(changes.getBody())).isEqualTo(200);
        assertThat(((Number) changes.getBody().get("total")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(it.get(sao, "/api/v1/helpdesk/support/students/" + lv).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(sao, "/api/v1/helpdesk/support/students/" + lv + "/tickets").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("bursar"), "/api/v1/helpdesk/support/students/" + lv + "/level").getStatusCode().value()).isEqualTo(403);
    }
}
