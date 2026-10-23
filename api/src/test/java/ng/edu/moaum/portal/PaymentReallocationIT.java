package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

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
 * Bursary payment reallocation and correction (V649), at the API: a student meant to pay school fees of NGN 180,000 and paid
 * NGN 100,000 under inter-departmental transfer, beside NGN 50,000 of school fees already paid. The Students Account Officer finds
 * the payment, reads the purposes and the student's sessions, checks the move (the destination's fee, what is paid, the balance of
 * NGN 30,000), and initiates it — Internal Audit and the student refused, a reason that says nothing refused, never twice at once;
 * the initiator and the Students Account Officer never decide; two Bursar officers approving at the same moment execute it once;
 * executed, the payment counts as school fees and nothing else of it changed, the student's balance is NGN 30,000 on their own fees
 * page, the receipt says the payment was corrected, the student is told and pays the balance through the normal page; the payment
 * is not corrected twice; the student reads their own corrections and another student none of them. Its own session; it undoes its
 * writes. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PaymentReallocationIT {

    static final String BASE = "/api/v1/finance/payment-reallocations";
    static final String PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void aPaymentMadeUnderTheWrongPurposeCountsAsSchoolFeesOnceApprovedAndTheStudentPaysOnlyTheBalance() throws Exception {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(8000, 8400);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String matric = it.freeNumber("MOAU/SC/CSC/26/8", 5);
        UUID a = it.student(it.freeSurname("ZZREALLOCA"), "C00023", it.freeNumber("MOAUM/ADM/26/8", 5), matric, 100);
        UUID b = it.student(it.freeSurname("ZZREALLOCB"), "C00023", it.freeNumber("MOAUM/ADM/26/8", 5), it.freeNumber("MOAU/SC/CSC/26/8", 5), 100);
        String purpose = "Inter-departmental transfer to B.Sc. IT V649 " + y;
        String[] refs = it.db(() -> {
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees (IT V649)', 180000, 100, 'C00023')")
                    .param("s", session).update();
            String p0 = jdbc.sql("SELECT finance.new_purpose_reference(:a, :s, 50000, 'School fees ' || :s)").param("a", a).param("s", session).query(String.class).single();
            jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for IT V649')").param("r", p0).query().listOfRows();
            String t = jdbc.sql("SELECT finance.new_purpose_reference(:a, :s, 100000, :p)").param("a", a).param("s", session).param("p", purpose).query(String.class).single();
            jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for IT V649')").param("r", t).query().listOfRows();
            return new String[] { p0, t };
        });
        String ref = refs[1];
        UUID payment = jdbc.sql("SELECT id FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(UUID.class).single();
        Map<String, Object> was = jdbc.sql("SELECT reference, amount, confirmed_at, receipt_no, channel, student_id FROM finance.payment_reference WHERE id = :p")
                .param("p", payment).query().singleRow();
        UUID officer = it.person(it.freeNumber("ZZ-REA-", 6), "ZZREASAO");
        UUID bursar = it.person(it.freeNumber("ZZ-REA-", 6), "ZZREABURSAR");
        UUID deputy = it.person(it.freeNumber("ZZ-REA-", 6), "ZZREADEPUTY");
        String sao = TestTokens.token(officer, List.of("studentaccounts"));
        String bur = TestTokens.token(bursar, List.of("bursar"));
        String dep = TestTokens.token(deputy, List.of("bursar"));
        String audit = TestTokens.token(UUID.randomUUID(), List.of("audit"));
        String studentA = TestTokens.token(a, List.of("student"));
        String studentB = TestTokens.token(b, List.of("student"));
        String paid = null;
        try {
            // the purposes, the payment found, the student's sessions with their level
            List<Map> destinations = it.getList(sao, BASE + "/destinations").getBody();
            assertThat(destinations).anySatisfy(d -> assertThat(d).containsEntry("code", "SCHOOL_FEES").containsEntry("supported", true));
            assertThat(destinations).anySatisfy(d -> assertThat(d).containsEntry("code", "HOSTEL_FEE").containsEntry("supported", false));
            List<Map> found = it.getList(sao, BASE + "/payments?q=" + matric).getBody();
            assertThat(found).anySatisfy(p -> assertThat(p).containsEntry("reference", ref).containsEntry("eligible", true));
            List<Map> periods = it.getList(sao, BASE + "/periods?payment=" + payment).getBody();
            assertThat(periods).anySatisfy(p -> assertThat(p).containsEntry("session", session).containsEntry("level", 100).containsEntry("fees_stated", true));

            // the check: the destination's fee, what is already paid, the balance the move leaves
            ResponseEntity<Map> check = it.get(sao, BASE + "/check?payment=" + payment + "&purpose=SCHOOL_FEES&session=" + session);
            assertThat(check.getStatusCode().value()).as(String.valueOf(check.getBody())).isEqualTo(200);
            assertThat(check.getBody()).containsEntry("ok", true);
            Map dest = (Map) check.getBody().get("destination");
            assertThat(((Number) dest.get("fee")).doubleValue()).isEqualTo(180000);
            assertThat(((Number) dest.get("paidBefore")).doubleValue()).isEqualTo(50000);
            assertThat(((Number) dest.get("balance")).doubleValue()).isEqualTo(30000);
            assertThat(dest).containsEntry("outcome", "PART_PAID");

            // initiated only by the Bursary's officers, with what was wrong and a reason that says why
            Map<String, Object> body = Map.of("payment", payment, "purpose", "SCHOOL_FEES", "session", session, "reasonCode", "WRONG_PURPOSE",
                    "reason", "The student selected inter-departmental transfer instead of school fees", "evidence", "Student's letter", "confirmed", true);
            assertThat(it.call(audit, HttpMethod.POST, BASE, body).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(studentA, HttpMethod.POST, BASE, body).getStatusCode().value()).isEqualTo(403);
            assertThat(it.get(studentA, BASE + "/check?payment=" + payment).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(sao, HttpMethod.POST, BASE, Map.of("payment", payment, "purpose", "SCHOOL_FEES", "session", session, "reasonCode", "WRONG_PURPOSE",
                    "reason", "correction", "confirmed", true)).getBody()).containsEntry("code", "REALLOC_REASON");
            ResponseEntity<Map> made = it.call(sao, HttpMethod.POST, BASE, body);
            assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
            Map x = (Map) made.getBody().get("reallocation");
            String id = String.valueOf(x.get("id"));
            assertThat(x).containsEntry("status", "PENDING_APPROVAL").containsEntry("initiated_office", "studentaccounts").containsEntry("to_purpose", "School fees " + session);
            assertThat(String.valueOf(x.get("realloc_ref"))).matches("REA/\\d{4}/\\d{6}");
            assertThat(it.call(sao, HttpMethod.POST, BASE, body).getBody()).containsEntry("code", "REALLOC_OPEN");
            ResponseEntity<Map> withFile = it.call(sao, HttpMethod.POST, BASE + "/" + id + "/evidence", Map.of("filename", "letter.png", "dataUrl", PNG));
            assertThat((List) withFile.getBody().get("evidence")).hasSize(1);
            // the payment unchanged while it waits: no entitlement from a request
            assertThat(jdbc.sql("SELECT purpose FROM finance.payment_reference WHERE id = :p").param("p", payment).query(String.class).single()).isEqualTo(purpose);

            // never decided by the Students Account Officer, nor by the officer who initiated it in another office
            assertThat(it.call(sao, HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("decision", "APPROVE", "confirmed", true)).getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> self = it.call(TestTokens.token(officer, List.of("bursar")), HttpMethod.POST, BASE + "/" + id + "/decide", Map.of("decision", "APPROVE", "confirmed", true));
            assertThat(self.getStatusCode().value()).isEqualTo(403);
            assertThat(self.getBody()).containsEntry("code", "REALLOC_SAME_OFFICER");

            // two Bursar officers approve at the same moment: it is executed once, the other told it is decided
            CompletableFuture<ResponseEntity<Map>> one = CompletableFuture.supplyAsync(() -> it.call(bur, HttpMethod.POST, BASE + "/" + id + "/decide",
                    Map.of("decision", "APPROVE", "note", "Letter seen", "confirmed", true)));
            CompletableFuture<ResponseEntity<Map>> two = CompletableFuture.supplyAsync(() -> it.call(dep, HttpMethod.POST, BASE + "/" + id + "/decide",
                    Map.of("decision", "APPROVE", "note", "Letter seen", "confirmed", true)));
            List<ResponseEntity<Map>> both = List.of(one.get(), two.get());
            assertThat(both.stream().filter(r -> r.getStatusCode().value() == 200 && "COMPLETED".equals(((Map) r.getBody().get("result")).get("status"))).count())
                    .as(String.valueOf(both)).isEqualTo(1);
            assertThat(both.stream().filter(r -> r.getStatusCode().value() != 200).map(r -> r.getBody().get("code")).toList()).containsExactly("REALLOC_DECIDED");

            // executed: the payment counts as school fees and nothing else of it changed
            Map<String, Object> now = jdbc.sql("SELECT reference, amount, confirmed_at, receipt_no, channel, student_id, purpose, session FROM finance.payment_reference WHERE id = :p")
                    .param("p", payment).query().singleRow();
            for (String k : List.of("reference", "amount", "confirmed_at", "receipt_no", "channel", "student_id")) {
                assertThat(now.get(k)).as(k).isEqualTo(was.get(k));
            }
            assertThat(now).containsEntry("purpose", "School fees " + session).containsEntry("session", session);
            assertThat(jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(Long.class).single()).isEqualTo(1);
            Map detail = it.get(audit, BASE + "/" + id).getBody();
            assertThat((Map) detail.get("reallocation")).containsEntry("status", "COMPLETED");
            assertThat(((List<Map>) detail.get("events")).stream().map(e -> e.get("action")).toList()).startsWith("REALLOCATION_INITIATED", "REALLOCATION_EVIDENCE_ADDED",
                    "REALLOCATION_APPROVED", "REALLOCATION_EXECUTION_STARTED", "PAYMENT_ALLOCATION_REMOVED", "PAYMENT_ALLOCATION_CREATED").endsWith("REALLOCATION_COMPLETED");
            assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE template_key = 'FEE_PAYMENT_PURPOSE_CORRECTED' AND event_key LIKE '%' || :id || '%'")
                    .param("id", id).query(Long.class).single()).isGreaterThanOrEqualTo(1);

            // the student's own fees page: NGN 150,000 paid, NGN 30,000 to pay; the receipt says the payment was corrected
            Map fees = it.get(studentA, "/api/v1/me/fees?session=" + session).getBody();
            assertThat(String.valueOf(fees)).contains("30000");
            Map receipt = it.get(studentA, "/api/v1/me/fees/receipts/" + ref).getBody();
            assertThat(receipt).containsEntry("correction_ref", x.get("realloc_ref")).containsEntry("correction_from", purpose);

            // the student reads their own corrections; another student none of them
            List<Map> mine = it.getList(studentA, "/api/v1/me/payment-corrections").getBody();
            assertThat(mine).anySatisfy(m -> assertThat(m).containsEntry("direction", "PURPOSE").containsEntry("swap_ref", x.get("realloc_ref")));
            List<Map> others = it.getList(studentB, "/api/v1/me/payment-corrections").getBody();
            assertThat(others).noneSatisfy(m -> assertThat(m).containsEntry("reference", ref));
            List<Map> onRecord = it.getList(bur, "/api/v1/finance/payment-swaps/of/" + a).getBody();
            assertThat(onRecord).anySatisfy(m -> assertThat(m).containsEntry("direction", "PURPOSE"));

            // not corrected twice; found on the list by its reference
            assertThat(it.call(sao, HttpMethod.POST, BASE, Map.of("payment", payment, "purpose", "SCHOOL_FEES", "session", session, "semester", 2, "reasonCode", "WRONG_SEMESTER",
                    "reason", "Moving the same payment a second time to see it refused", "confirmed", true)).getBody()).containsEntry("code", "REALLOC_ALREADY");
            Map listed = it.get(audit, BASE + "?q=" + java.net.URLEncoder.encode(ref, java.nio.charset.StandardCharsets.UTF_8)).getBody();
            assertThat(((Number) listed.get("total")).intValue()).isEqualTo(1);

            // the student pays the balance through the normal payment page: NGN 30,000, and the session's school fees are paid
            ResponseEntity<Map> balanceRef = it.call(studentA, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session));
            assertThat(balanceRef.getStatusCode().value()).as(String.valueOf(balanceRef.getBody())).isEqualTo(200);
            paid = String.valueOf(balanceRef.getBody().get("reference"));
            assertThat(jdbc.sql("SELECT amount FROM finance.payment_reference WHERE reference = :r").param("r", paid).query(Double.class).single()).isEqualTo(30000);
            String balance = paid;
            it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'balance for IT V649')").param("r", balance).query().listOfRows());
            assertThat(jdbc.sql("SELECT (finance.position(:s, :ses)).balance").param("s", a).param("ses", session).query(Double.class).single()).isEqualTo(0);
        } finally {
            String balance = paid;
            it.db(() -> {
                jdbc.sql("DELETE FROM finance.payment_reallocation WHERE payment_id = :p AND kind = 'REVERSAL'").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.payment_reallocation WHERE payment_id = :p").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.payment_reference WHERE reference IN (:r)").param("r", balance == null ? List.of(refs[0], refs[1]) : List.of(refs[0], refs[1], balance)).update();
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
                return null;
            });
        }
    }
}
