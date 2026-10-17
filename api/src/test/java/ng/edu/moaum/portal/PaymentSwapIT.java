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
 * School fees payment swap (V527): a verified school-fees payment credited to student A is moved to student B, who it belongs to.
 * The Students Account Officer checks and initiates it with a reason, evidence and the confirmation — never "wrong", never
 * unconfirmed, never twice at once; Internal Audit reads and does nothing; the initiator never decides, nor the Students Account
 * Officer; a Bursar officer approves it with the ownership confirmation and it is executed at once: the payment's student changes
 * and nothing else (reference, amount, confirmation and the ledger untouched), A's paid down and B's up by the amount, the
 * timeline in order; the payment is not swapped again; a reversal by the Bursar, decided by another Bursar officer, takes it back
 * and marks the swap REVERSED; both accounts carry the corrections, the student's without the other student's number. Its own
 * session; it undoes its writes. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PaymentSwapIT {

    static final String BASE = "/api/v1/finance/payment-swaps";
    static final String PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void aVerifiedSchoolFeesPaymentIsSwappedToItsOwnerUnderApprovalAndReversedTheSameWay() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = 3100 + new java.util.Random().nextInt(700);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        UUID a = it.student(it.freeSurname("ZZSWAPA"), "C00023", it.freeNumber("MOAUM/ADM/26/7", 5), it.freeNumber("MOAU/SC/CSC/26/7", 5), 100);
        UUID b = it.student(it.freeSurname("ZZSWAPB"), "C00023", it.freeNumber("MOAUM/ADM/26/7", 5), it.freeNumber("MOAU/SC/CSC/26/7", 5), 100);
        String ref = it.db(() -> {
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees (IT V527)', 300000, 100, 'C00023')")
                    .param("s", session).update();
            String r = jdbc.sql("SELECT finance.new_purpose_reference(:a, :s, 200000, 'School fees ' || :s)").param("a", a).param("s", session).query(String.class).single();
            jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for IT V527')").param("r", r).query().listOfRows();
            return r;
        });
        UUID payment = jdbc.sql("SELECT id FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(UUID.class).single();
        UUID officer = it.person(it.freeNumber("ZZ-SWAP-", 6), "ZZSWAPSAO");
        UUID bursar = it.person(it.freeNumber("ZZ-SWAP-", 6), "ZZSWAPBURSAR");
        UUID deputy = it.person(it.freeNumber("ZZ-SWAP-", 6), "ZZSWAPDEPUTY");
        String sao = TestTokens.token(officer, List.of("studentaccounts"));
        String bur = TestTokens.token(bursar, List.of("bursar"));
        String dep = TestTokens.token(deputy, List.of("bursar"));
        String audit = TestTokens.token(UUID.randomUUID(), List.of("audit"));
        long journals = jdbc.sql("SELECT count(*) FROM finance.gl_journal WHERE source_ref = :r").param("r", ref).query(Long.class).single();
        try {
            // found and checked: both accounts as the server reads them
            ResponseEntity<Map> check = it.get(sao, BASE + "/check?payment=" + payment + "&to=" + b);
            assertThat(check.getStatusCode().value()).as(String.valueOf(check.getBody())).isEqualTo(200);
            assertThat(check.getBody()).containsEntry("ok", true);
            assertThat(((Number) ((Map) check.getBody().get("fromAccount")).get("paid")).doubleValue()).isEqualTo(200000);
            assertThat(((Number) ((Map) check.getBody().get("toAccount")).get("paid")).doubleValue()).isEqualTo(0);
            assertThat(String.valueOf(it.get(sao, BASE + "/check?payment=" + payment + "&to=" + a).getBody().get("refusals"))).contains("SWAP_SAME_STUDENT");

            // initiated only with a reason that says why and the confirmation; Internal Audit reads and does not initiate
            Map<String, Object> body = Map.of("payment", payment, "to", b, "reason", "The parent paid B's fees on A's matriculation number", "evidence", "Teller 0042", "confirmed", true);
            assertThat(it.call(audit, HttpMethod.POST, BASE, body).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(sao, HttpMethod.POST, BASE, Map.of("payment", payment, "to", b, "reason", "wrong", "confirmed", true)).getBody()).containsEntry("code", "SWAP_REASON");
            assertThat(it.call(sao, HttpMethod.POST, BASE, Map.of("payment", payment, "to", b, "reason", "The parent paid B's fees on A's number", "confirmed", false)).getBody())
                    .containsEntry("code", "SWAP_CONFIRM");
            ResponseEntity<Map> made = it.call(sao, HttpMethod.POST, BASE, body);
            assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
            Map swap = (Map) made.getBody().get("swap");
            String id = String.valueOf(swap.get("id"));
            assertThat(swap).containsEntry("status", "PENDING_APPROVAL").containsEntry("initiated_office", "studentaccounts");
            assertThat(String.valueOf(swap.get("swap_ref"))).matches("SWAP/\\d{4}/\\d{6}");
            assertThat(it.call(sao, HttpMethod.POST, BASE, body).getBody()).containsEntry("code", "SWAP_OPEN");

            // evidence: a PNG is kept, a Word file is not
            assertThat(it.call(sao, HttpMethod.POST, BASE + "/" + id + "/evidence", Map.of("filename", "letter.doc", "dataUrl", "data:application/msword;base64,AAAA")).getBody())
                    .containsEntry("code", "SWAP_EVIDENCE_TYPE");
            ResponseEntity<Map> withFile = it.call(sao, HttpMethod.POST, BASE + "/" + id + "/evidence", Map.of("filename", "teller.png", "dataUrl", PNG));
            assertThat(withFile.getStatusCode().value()).as(String.valueOf(withFile.getBody())).isEqualTo(200);
            assertThat((List) withFile.getBody().get("evidence")).hasSize(1);

            // never decided by the Students Account Officer, nor by the officer who initiated it in another office
            assertThat(it.call(sao, HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("approve", true, "confirmed", true)).getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> self = it.call(TestTokens.token(officer, List.of("bursar")), HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("approve", true, "confirmed", true));
            assertThat(self.getStatusCode().value()).isEqualTo(403);
            assertThat(self.getBody()).containsEntry("code", "SWAP_SAME_OFFICER");

            // approved by the Bursar with the confirmation: executed at once, the credit moved and nothing else
            assertThat(it.call(bur, HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("approve", true, "confirmed", false)).getBody()).containsEntry("code", "SWAP_CONFIRM");
            ResponseEntity<Map> done = it.call(bur, HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("approve", true, "note", "Teller seen", "confirmed", true));
            assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
            assertThat((Map) done.getBody().get("result")).containsEntry("status", "COMPLETED");
            Map<String, Object> now = jdbc.sql("SELECT student_id, reference, amount, confirmed_at IS NOT NULL AS confirmed FROM finance.payment_reference WHERE id = :p")
                    .param("p", payment).query().singleRow();
            assertThat(now.get("student_id")).isEqualTo(b);
            assertThat(now).containsEntry("reference", ref).containsEntry("confirmed", true);
            assertThat(((Number) now.get("amount")).doubleValue()).isEqualTo(200000);
            assertThat(jdbc.sql("SELECT (finance.position(:s, :ses)).paid").param("s", a).param("ses", session).query(Double.class).single()).isEqualTo(0);
            assertThat(jdbc.sql("SELECT (finance.position(:s, :ses)).paid").param("s", b).param("ses", session).query(Double.class).single()).isEqualTo(200000);
            assertThat(jdbc.sql("SELECT count(*) FROM finance.gl_journal WHERE source_ref = :r").param("r", ref).query(Long.class).single()).isEqualTo(journals);
            List<Map> events = (List<Map>) done.getBody().get("events");
            assertThat(events.stream().map(e -> e.get("action")).toList()).containsExactly("PAYMENT_SWAP_INITIATED", "PAYMENT_SWAP_EVIDENCE_ADDED", "PAYMENT_SWAP_APPROVED",
                    "PAYMENT_SWAP_EXECUTION_STARTED", "PAYMENT_ALLOCATION_REMOVED", "PAYMENT_ALLOCATION_CREATED", "PAYMENT_SWAP_COMPLETED");
            assertThat(jdbc.sql("""
                    SELECT count(DISTINCT template_key) FROM platform.notice
                     WHERE template_key IN ('FEE_PAYMENT_REALLOCATED_AWAY', 'FEE_PAYMENT_REALLOCATED_TO') AND event_key LIKE '%' || :id || '%'
                    """).param("id", id).query(Long.class).single()).isEqualTo(2);

            // not swapped again; Internal Audit finds it and does not reverse it
            assertThat(it.call(sao, HttpMethod.POST, BASE, Map.of("payment", payment, "to", a, "reason", "Swapping the same payment again to see it refused", "confirmed", true)).getBody())
                    .containsEntry("code", "SWAP_ALREADY_SWAPPED");
            Map listed = it.get(audit, BASE + "?q=" + java.net.URLEncoder.encode(ref, java.nio.charset.StandardCharsets.UTF_8)).getBody();
            assertThat(((Number) listed.get("total")).intValue()).isEqualTo(1);
            assertThat(it.call(audit, HttpMethod.POST, BASE + "/" + id + "/reverse", Map.of("reason", "Audit tries to reverse the swap here", "confirmed", true)).getStatusCode().value())
                    .isEqualTo(403);

            // reversed by the Bursar, decided by another Bursar officer: back with A, the first swap REVERSED
            ResponseEntity<Map> rv = it.call(bur, HttpMethod.POST, BASE + "/" + id + "/reverse", Map.of("reason", "The first swap was made on the wrong student; taken back", "confirmed", true));
            assertThat(rv.getStatusCode().value()).as(String.valueOf(rv.getBody())).isEqualTo(200);
            String rid = String.valueOf(((Map) rv.getBody().get("swap")).get("id"));
            assertThat((Map) rv.getBody().get("swap")).containsEntry("kind", "REVERSAL").containsEntry("status", "PENDING_APPROVAL");
            assertThat(it.call(bur, HttpMethod.POST, BASE + "/" + rid + "/decide", Map.of("approve", true, "confirmed", true)).getBody()).containsEntry("code", "SWAP_SAME_OFFICER");
            ResponseEntity<Map> back = it.call(dep, HttpMethod.POST, BASE + "/" + rid + "/decide", Map.of("approve", true, "confirmed", true));
            assertThat((Map) back.getBody().get("result")).as(String.valueOf(back.getBody())).containsEntry("status", "COMPLETED");
            assertThat(jdbc.sql("SELECT student_id FROM finance.payment_reference WHERE id = :p").param("p", payment).query(UUID.class).single()).isEqualTo(a);
            assertThat((Map) it.get(audit, BASE + "/" + id).getBody().get("swap")).containsEntry("status", "REVERSED");

            // both accounts carry the corrections; the student's own list never names the other student
            assertThat(it.getList(bur, BASE + "/of/" + a).getBody()).hasSize(2);
            List<Map> mine = it.getList(TestTokens.token(a, List.of("student")), "/api/v1/me/payment-corrections").getBody();
            assertThat(mine).hasSize(2);
            assertThat(mine).allSatisfy(m -> assertThat(m).doesNotContainKey("other_matric"));
        } finally {
            it.db(() -> {
                jdbc.sql("DELETE FROM finance.payment_swap WHERE payment_id = :p AND kind = 'REVERSAL'").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.payment_swap WHERE payment_id = :p").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.payment_reference WHERE id = :p").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
                return null;
            });
        }
    }
}
