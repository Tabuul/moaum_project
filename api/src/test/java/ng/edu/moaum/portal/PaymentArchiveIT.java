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
 * Payments archived for review (V670), at the API: NGN 100,000 of school fees stands on student A, who did not make it; the payer
 * is student B. The Students Account Officer finds the payment and archives it as on the wrong student — Internal Audit and the
 * student refused — and from then it counts nowhere: A's fees page shows the balance and the payment apart as under review, its
 * receipt is withheld, the full record lists it apart, the desk finds it by its reference and counts it. The officer records the
 * gateway's payer and proposes the reallocation to B (found by matriculation number); the officer never decides, nor does the
 * Students Account Officer; a Bursar officer approves, and it is executed at once through the payment swap: B's fees count it, A's
 * do not, both told by the swap, A's list no longer carries it and B's shows it verified; the archive is not decided twice. Its own
 * session; it undoes its writes. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PaymentArchiveIT {

    static final String BASE = "/api/v1/finance/payment-archive";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    @Test
    void aPaymentOnTheWrongStudentIsArchivedCountsNowhereAndIsReallocatedToItsOwnerOnTheBursarsApproval() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(2300, 2900);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String matricA = it.freeNumber("MOAU/SC/CSC/26/7", 5);
        String matricB = it.freeNumber("MOAU/SC/CSC/26/7", 5);
        UUID a = it.student(it.freeSurname("ZZARCHIVEA"), "C00023", it.freeNumber("MOAUM/ADM/26/7", 5), matricA, 100);
        UUID b = it.student(it.freeSurname("ZZARCHIVEB"), "C00023", it.freeNumber("MOAUM/ADM/26/7", 5), matricB, 100);
        String ref = it.db(() -> {
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees (IT V670)', 150000, 100, 'C00023')")
                    .param("s", session).update();
            String r = jdbc.sql("SELECT finance.new_purpose_reference(:a, :s, 100000, 'School fees ' || :s)").param("a", a).param("s", session).query(String.class).single();
            jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for IT V670')").param("r", r).query().listOfRows();
            return r;
        });
        UUID payment = jdbc.sql("SELECT id FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(UUID.class).single();
        Map<String, Object> was = jdbc.sql("SELECT reference, amount, confirmed_at, receipt_no, channel FROM finance.payment_reference WHERE id = :p")
                .param("p", payment).query().singleRow();
        UUID officer = it.person(it.freeNumber("ZZ-PAR-", 6), "ZZPARSAO");
        UUID bursar = it.person(it.freeNumber("ZZ-PAR-", 6), "ZZPARBURSAR");
        String sao = TestTokens.token(officer, List.of("studentaccounts"));
        String bur = TestTokens.token(bursar, List.of("bursar"));
        String audit = TestTokens.token(UUID.randomUUID(), List.of("audit"));
        String studentA = TestTokens.token(a, List.of("student"));
        String studentB = TestTokens.token(b, List.of("student"));
        String q = ref;   // ItSupport encodes the URL itself
        try {
            // found, and free to archive; the reasons and the kinds of evidence are the Bursary's list
            List<Map> found = it.getList(sao, BASE + "/payments?q=" + q).getBody();
            assertThat(found).singleElement().satisfies(p -> assertThat(p).containsEntry("reference", ref).containsEntry("eligible", true));
            Map catalogue = it.get(audit, BASE + "/catalogue").getBody();
            assertThat((List<Map>) catalogue.get("reasons")).anySatisfy(r -> assertThat(r).containsEntry("code", "WRONG_STUDENT"));
            assertThat((List<Map>) catalogue.get("evidenceKinds")).anySatisfy(r -> assertThat(r).containsEntry("code", "GATEWAY_PAYER").containsEntry("strength", "STRONG"));

            // archived by the Students Account Officer only, with a reason, a note and the confirmation
            Map<String, Object> body = Map.of("payment", payment, "reason", "WRONG_STUDENT",
                    "note", "The gateway's payer record names another student", "confirmed", true);
            assertThat(it.call(audit, HttpMethod.POST, BASE, body).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(studentA, HttpMethod.POST, BASE, body).getStatusCode().value()).isEqualTo(403);
            assertThat(it.get(studentA, BASE).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(sao, HttpMethod.POST, BASE, Map.of("payment", payment, "reason", "WRONG_STUDENT", "note", "wrong", "confirmed", true)).getBody())
                    .containsEntry("code", "PAR_NOTE");
            ResponseEntity<Map> made = it.call(sao, HttpMethod.POST, BASE, body);
            assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
            Map archive = (Map) made.getBody().get("archive");
            String id = String.valueOf(archive.get("id"));
            assertThat(String.valueOf(archive.get("archive_ref"))).matches("PAR/\\d{4}/\\d{6}");
            assertThat(archive).containsEntry("state", "ARCHIVED").containsEntry("reason_code", "WRONG_STUDENT").containsEntry("archived_office", "studentaccounts");
            assertThat(it.call(sao, HttpMethod.POST, BASE, body).getBody()).containsEntry("code", "PAR_ALREADY");

            // counted nowhere: A's fees show the whole fee owed, the payment apart and under review, its receipt withheld
            Map fees = it.get(studentA, "/api/v1/me/fees?session=" + session).getBody();
            assertThat(((Number) fees.get("balance")).doubleValue()).as(String.valueOf(fees)).isEqualTo(150000);
            assertThat((List<Map>) fees.get("references")).anySatisfy(r -> assertThat(r).containsEntry("reference", ref).containsEntry("archived", true));
            ResponseEntity<Map> receipt = it.get(studentA, "/api/v1/me/fees/receipts/" + ref);
            assertThat(receipt.getStatusCode().value()).isEqualTo(422);
            assertThat(receipt.getBody()).containsEntry("code", "PAYMENT_UNDER_REVIEW");
            List<Map> mine = it.getList(studentA, "/api/v1/me/payment-archives").getBody();
            assertThat(mine).singleElement().satisfies(m -> assertThat(m).containsEntry("reference", ref).containsEntry("state", "ARCHIVED").containsEntry("counts", false));
            assertThat(it.getList(studentB, "/api/v1/me/payment-archives").getBody()).isEmpty();
            Map record = it.get(bur, "/api/v1/student/students/" + a + "/full/finance").getBody();
            assertThat(String.valueOf(record)).contains("ARCHIVED").contains(String.valueOf(archive.get("archive_ref")));

            // the desk finds it by its reference and counts it under review
            Map listed = it.get(audit, BASE + "?q=" + q).getBody();
            assertThat(((Number) listed.get("total")).intValue()).isEqualTo(1);
            Map open = it.get(audit, BASE + "?state=OPEN&session=" + session).getBody();
            assertThat((List<Map>) open.get("rows")).anySatisfy(r -> assertThat(r).containsEntry("reference", ref));
            Map figures = it.get(audit, BASE + "/figures?session=" + session).getBody();
            assertThat(((Number) figures.get("archivedAmount")).doubleValue()).isEqualTo(100000);
            assertThat(((Number) figures.get("activeAmount")).doubleValue()).isZero();

            // the investigation recorded, the owner found, the reallocation proposed through the swap
            ResponseEntity<Map> inv = it.call(sao, HttpMethod.POST, BASE + "/" + id + "/investigation",
                    Map.of("note", "Interswitch's payer record read", "items", List.of(Map.of("kind", "GATEWAY_PAYER", "value", "Payer " + matricB))));
            assertThat(inv.getStatusCode().value()).as(String.valueOf(inv.getBody())).isEqualTo(200);
            assertThat((Map) inv.getBody().get("archive")).containsEntry("state", "UNDER_REVIEW");
            List<Map> owners = it.getList(sao, BASE + "/students?q=" + matricB).getBody();
            assertThat(owners).anySatisfy(s -> assertThat(s).containsEntry("matric_no", matricB));
            ResponseEntity<Map> proposed = it.call(sao, HttpMethod.POST, BASE + "/" + id + "/proposal",
                    Map.of("outcome", "REALLOCATE", "owner", b, "note", "The gateway's payer is the student it belongs to", "confirmed", true));
            assertThat(proposed.getStatusCode().value()).as(String.valueOf(proposed.getBody())).isEqualTo(200);
            assertThat((Map) proposed.getBody().get("archive")).containsEntry("state", "PENDING_BURSAR_APPROVAL").containsEntry("outcome", "REALLOCATE");
            assertThat((Map) proposed.getBody().get("swap")).containsEntry("status", "PENDING_APPROVAL");

            // never decided by the Students Account Officer, nor by the proposer in another office
            assertThat(it.call(sao, HttpMethod.POST, BASE + "/" + id + "/decision", Map.of("decision", "APPROVE", "confirmed", true)).getStatusCode().value()).isEqualTo(403);
            ResponseEntity<Map> self = it.call(TestTokens.token(officer, List.of("bursar")), HttpMethod.POST, BASE + "/" + id + "/decision",
                    Map.of("decision", "APPROVE", "confirmed", true));
            assertThat(self.getStatusCode().value()).isEqualTo(403);
            assertThat(self.getBody()).containsEntry("code", "PAR_SAME_OFFICER");

            // approved by a Bursar officer: executed at once through the swap
            ResponseEntity<Map> decided = it.call(bur, HttpMethod.POST, BASE + "/" + id + "/decision", Map.of("decision", "APPROVE", "note", "Payer record seen", "confirmed", true));
            assertThat(decided.getStatusCode().value()).as(String.valueOf(decided.getBody())).isEqualTo(200);
            assertThat((Map) decided.getBody().get("result")).containsEntry("state", "RECONCILED").containsEntry("outcome", "REALLOCATE");
            assertThat((Map) decided.getBody().get("swap")).containsEntry("status", "COMPLETED");
            Map<String, Object> now = jdbc.sql("SELECT reference, amount, confirmed_at, receipt_no, channel, student_id, archived_at FROM finance.payment_reference WHERE id = :p")
                    .param("p", payment).query().singleRow();
            for (String k : List.of("reference", "amount", "confirmed_at", "receipt_no", "channel")) {
                assertThat(now.get(k)).as(k).isEqualTo(was.get(k));
            }
            assertThat(now.get("student_id")).isEqualTo(b);
            assertThat(now.get("archived_at")).isNull();
            assertThat(((Number) it.get(studentB, "/api/v1/me/fees?session=" + session).getBody().get("balance")).doubleValue()).isEqualTo(50000);
            assertThat(((Number) it.get(studentA, "/api/v1/me/fees?session=" + session).getBody().get("balance")).doubleValue()).isEqualTo(150000);
            assertThat(it.getList(studentA, "/api/v1/me/payment-archives").getBody()).isEmpty();
            List<Map> bs = it.getList(studentB, "/api/v1/me/payment-archives").getBody();
            assertThat(bs).singleElement().satisfies(m -> assertThat(m).containsEntry("state", "RECONCILED").containsEntry("counts", true));
            assertThat(it.get(studentB, "/api/v1/me/fees/receipts/" + ref).getStatusCode().value()).isEqualTo(200);
            Map detail = it.get(audit, BASE + "/" + id).getBody();
            assertThat(((List<Map>) detail.get("events")).stream().map(e -> e.get("action")).toList())
                    .containsSubsequence("ARCHIVED", "INVESTIGATION_RECORDED", "PROPOSED", "APPROVED", "REALLOCATED");
            assertThat(it.call(bur, HttpMethod.POST, BASE + "/" + id + "/decision", Map.of("decision", "APPROVE", "confirmed", true)).getBody())
                    .containsEntry("code", "PAR_DECIDED");
        } finally {
            it.db(() -> {
                jdbc.sql("SELECT set_config('moaum.maintenance', 'on', true)").query().singleRow();
                jdbc.sql("DELETE FROM finance.payment_archive WHERE payment_id = :p").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.payment_swap WHERE payment_id = :p").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.payment_reference WHERE id = :p").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
                return null;
            });
        }
    }
}
