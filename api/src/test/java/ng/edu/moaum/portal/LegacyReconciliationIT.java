package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
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
 * V625 through the API: the old portal's outstanding fees of a session classified — a student who paid less owes the University (a
 * liability, never wallet money; a credit request for them is refused), one who paid more holds a credit. The Students Account
 * Officer confirms the credit (never above the excess; a lower amount with its reason, marked adjusted; the explicit confirmation
 * required) and the Bursar is told; the officer cannot approve their own request; a Bursar officer returns it, the officer corrects
 * and resubmits, another Bursar officer approves: the wallet is credited once, the overpayment is decided so it is never carried as
 * well, the student is told; a second approval is refused; the student applies the credit to the next session's fees through the
 * wallet that exists, and cannot apply more than it holds; the full record shows the request; the figures and the reports agree.
 * V631: the old portal's OUTSTANDING FEES payments verified by the officer and credited to the wallet by another Bursar officer.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class LegacyReconciliationIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String tag;
    String a;
    String b;
    String prog;
    UUID officerId;
    UUID bursarId;
    UUID otherBursarId;
    String officer;
    String bursar;
    String otherBursar;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("MOAUM/ADM/62/" + k + "51", "MOAUM/ADM/62/" + k + "52", "MOAUM/LRC/62/" + k + "1", "MOAUM/LRC/62/" + k + "2", "ZZLRC" + k, "ZZLRO" + k)));
        int year = it.freeYear(3100, 3190, 0, 1);
        a = year + "/" + (year + 1);
        b = (year + 1) + "/" + (year + 2);
        it.session(a, year);
        it.session(b, year + 1);
        prog = "C00023";
        officerId = it.person("ZZLRC-SAO-" + tag, "ZZLRCSAO");
        bursarId = it.person("ZZLRC-BUR-" + tag, "ZZLRCBUR");
        otherBursarId = it.person("ZZLRC-BU2-" + tag, "ZZLRCBU2");
        officer = TestTokens.token(officerId, List.of("studentaccounts"));
        bursar = TestTokens.token(bursarId, List.of("bursar"));
        otherBursar = TestTokens.token(otherBursarId, List.of("bursar"));
        it.db(() -> {
            for (String s : new String[] {a, b}) {
                jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, NULL, :p)").param("s", s).param("p", prog).update();
            }
            // the Bursar holds the office today, so the desk's notices reach someone
            jdbc.sql("""
                    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from, valid_to)
                    VALUES (gen_random_uuid(), :p, 'bursar', 'institution', NULL, 'LegacyReconciliationIT', gen_random_uuid(), current_date - 1, NULL)
                    """).param("p", bursarId).update();
            return null;
        });
    }

    @AfterEach
    void putBack() {
        if (it != null) it.db(() -> {
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session IN (:a, :b)").param("a", a).param("b", b).update();
            jdbc.sql("DELETE FROM iam.office_assignment WHERE instrument = 'LegacyReconciliationIT' AND person_id = :p").param("p", bursarId).update();
            return null;
        });
    }

    private UUID legacyStudent(String suffix, String number, long... amounts) {
        UUID student = it.student("ZZLR" + suffix + tag, prog, "MOAUM/ADM/62/" + tag + ("C".equals(suffix) ? "51" : "52"), number, 200);
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        String key = "MOAUM-LEG-" + matric.replaceAll("[^0-9A-Z]", "") + "-" + a.replace("/", "-");
        for (int i = 0; i < amounts.length; i++) {
            String ref = key + "-S" + (i + 1);
            long amount = amounts[i];
            int sem = i + 1;
            it.db(() -> jdbc.sql("""
                    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                    VALUES (:s, :ses, :r, :p, :a, now(), now() - interval '20 days', :by, 'Legacy', 'LEG-' || :r, 'Imported from the old portal')
                    ON CONFLICT (reference) DO NOTHING
                    """).param("s", student).param("ses", a).param("r", ref).param("p", "School fees (legacy) · semester " + sem).param("a", amount)
                    .param("by", UUID.randomUUID()).update());
        }
        return student;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> rowOf(String token, UUID student) {
        List<Map<String, Object>> rows = (List<Map<String, Object>>) (List<?>) it.getList(token, "/api/v1/finance/legacy-reconciliation/outstanding?session=" + a).getBody();
        return rows.stream().filter(r -> student.toString().equals(r.get("student_id"))).findFirst().orElse(null);
    }

    private BigDecimal walletBalance(UUID student) {
        return jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", student).query(BigDecimal.class).single();
    }

    @SuppressWarnings("unchecked")
    @Test
    void anOverpaymentReachesTheWalletOnlyByTheOfficersConfirmationAndAnotherBursarsApprovalAndALiabilityNever() {
        UUID credit = legacyStudent("C", "MOAUM/LRC/62/" + tag + "1", 80000, 50000);   // paid 130,000 against 100,000
        UUID owes = legacyStudent("O", "MOAUM/LRC/62/" + tag + "2", 60000);            // paid 60,000 against 100,000
        String student = TestTokens.token(credit, List.of("student"));

        // the desk: the credit and the liability, kept apart; the figures count them apart
        Map<String, Object> rc = rowOf(officer, credit);
        assertThat(rc).isNotNull();
        assertThat(rc).containsEntry("state", "CREDIT");
        assertThat(((Number) rc.get("excess")).intValue()).isEqualTo(30000);
        Map<String, Object> ro = rowOf(officer, owes);
        assertThat(ro).containsEntry("state", "OWES");
        assertThat(((Number) ro.get("owed")).intValue()).isEqualTo(40000);
        Map<String, Object> fig = ok(it.get(officer, "/api/v1/finance/legacy-reconciliation/figures?session=" + a));
        assertThat(((Number) ((Map<String, Object>) fig.get("outstanding")).get("owes")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) ((Map<String, Object>) fig.get("outstanding")).get("credit")).intValue()).isGreaterThanOrEqualTo(1);
        // a student cannot read the desk
        assertThat(it.get(student, "/api/v1/finance/legacy-reconciliation/figures").getStatusCode().value()).isEqualTo(403);

        // the officer's request: refused for the student who owes, above the excess, for a lower amount without its reason, and without the confirmation
        String base = "/api/v1/finance/legacy-reconciliation/requests";
        ResponseEntity<Map> liability = it.call(officer, HttpMethod.POST, base, Map.of("student", owes, "session", a, "reason", "the old portal shows a balance", "evidence", "export row", "confirmed", true));
        assertThat(liability.getStatusCode().value()).isEqualTo(422);
        assertThat(liability.getBody().get("code")).isEqualTo("LEGACY_CREDIT_NOT_OVERPAID");
        assertThat(it.call(officer, HttpMethod.POST, base, Map.of("student", credit, "session", a, "amount", 50000, "reason", "the old portal shows a balance", "evidence", "export rows", "confirmed", true))
                .getBody().get("code")).isEqualTo("LEGACY_CREDIT_AMOUNT");
        assertThat(it.call(officer, HttpMethod.POST, base, Map.of("student", credit, "session", a, "amount", 20000, "reason", "the old portal shows a balance", "evidence", "export rows", "confirmed", true))
                .getBody().get("code")).isEqualTo("LEGACY_CREDIT_ADJUSTMENT_REASON");
        assertThat(it.call(officer, HttpMethod.POST, base, Map.of("student", credit, "session", a, "reason", "the old portal shows a balance", "evidence", "export rows", "confirmed", false))
                .getBody().get("code")).isEqualTo("LEGACY_CREDIT_CONFIRM");
        // the request, at a lower amount with its reason: adjusted, pending the Bursar, nothing credited; the Bursar told
        Map<String, Object> req = ok(it.call(officer, HttpMethod.POST, base, Map.of("student", credit, "session", a, "amount", 20000,
                "reason", "the old portal shows a balance of 20,000 after a part refund", "evidence", "export rows S1 and S2; the old portal's statement", "adjustmentReason", "the old portal refunded 10,000 in cash", "confirmed", true)));
        String id = String.valueOf(req.get("id"));
        assertThat(req).containsEntry("status", "PENDING_BURSAR_APPROVAL").containsEntry("adjusted", true);
        assertThat(String.valueOf(req.get("ref"))).matches("LOR/[0-9]{4}/[0-9]{6}");
        assertThat(walletBalance(credit)).isEqualByComparingTo("0");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'person' AND about_id = :p AND template_key = 'LEGACY_CREDIT_WAITING'").param("p", bursarId).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        // a second request while one stands is refused; the row shows the request
        assertThat(it.call(officer, HttpMethod.POST, base, Map.of("student", credit, "session", a, "reason", "the old portal shows a balance", "evidence", "export rows", "confirmed", true))
                .getBody().get("code")).isEqualTo("LEGACY_CREDIT_OPEN");
        assertThat(rowOf(officer, credit)).containsEntry("request_status", "PENDING_BURSAR_APPROVAL");

        // the officer cannot decide it, even acting as Bursar; the student cannot
        String officerAsBursar = TestTokens.token(officerId, List.of("bursar"));
        ResponseEntity<Map> self = it.call(officerAsBursar, HttpMethod.POST, base + "/" + id + "/decide", Map.of("action", "APPROVE"));
        assertThat(self.getStatusCode().value()).isEqualTo(422);
        assertThat(self.getBody().get("code")).isEqualTo("LEGACY_CREDIT_SAME_OFFICER");
        assertThat(it.call(officer, HttpMethod.POST, base + "/" + id + "/decide", Map.of("action", "APPROVE")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(student, HttpMethod.POST, base + "/" + id + "/decide", Map.of("action", "APPROVE")).getStatusCode().value()).isEqualTo(403);
        // the Bursar returns it for correction (a note required); the officer corrects and resubmits at the full excess
        assertThat(it.call(bursar, HttpMethod.POST, base + "/" + id + "/decide", Map.of("action", "RETURN", "note", "short")).getBody().get("code")).isEqualTo("LEGACY_CREDIT_NOTE");
        Map<String, Object> returned = ok(it.call(bursar, HttpMethod.POST, base + "/" + id + "/decide", Map.of("action", "RETURN", "note", "the refund is not on the statement; confirm the full excess")));
        assertThat(returned).containsEntry("status", "RETURNED_FOR_CORRECTION");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'person' AND about_id = :p AND template_key = 'LEGACY_CREDIT_DECIDED'").param("p", officerId).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        Map<String, Object> resub = ok(it.call(officer, HttpMethod.POST, base + "/" + id + "/resubmit", Map.of("reason", "the old portal shows the full 30,000 overpaid; no refund was made", "evidence", "export rows S1 and S2; the receipts", "confirmed", true)));
        assertThat(resub).containsEntry("status", "PENDING_BURSAR_APPROVAL").containsEntry("adjusted", false).containsEntry("resubmissions", 1);
        assertThat(((Number) resub.get("confirmed_amount")).intValue()).isEqualTo(30000);
        // another Bursar officer approves: the wallet credited once, the overpayment decided WALLET, the student told
        Map<String, Object> done = ok(it.call(otherBursar, HttpMethod.POST, base + "/" + id + "/decide", Map.of("action", "APPROVE")));
        assertThat(done).containsEntry("status", "CREDITED");
        assertThat(String.valueOf(done.get("wallet_reference"))).isEqualTo(String.valueOf(req.get("ref")));
        assertThat(((Number) done.get("balance_after")).intValue()).isEqualTo(30000);
        assertThat(walletBalance(credit)).isEqualByComparingTo("30000");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.wallet_entry WHERE student_id = :s AND kind = 'CREDIT' AND source_code = 'OVERPAID'").param("s", credit).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT decision FROM finance.overpayment_decision WHERE student_id = :s AND session = :a AND superseded_at IS NULL").param("s", credit).param("a", a).query(String.class).single()).isEqualTo("WALLET");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND template_key = 'LEGACY_CREDIT_POSTED'").param("s", credit).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        // never twice: a second approval is refused, the overpayment is not carried as well, the desk shows it decided
        ResponseEntity<Map> again = it.call(bursar, HttpMethod.POST, base + "/" + id + "/decide", Map.of("action", "APPROVE"));
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody().get("code")).isEqualTo("LEGACY_CREDIT_STATE");
        Map<String, Object> carry = ok(it.call(bursar, HttpMethod.POST, "/api/v1/finance/legacy-fees/overpaid/decide", Map.of("session", a, "decision", "CARRY", "students", List.of(credit), "reason", "carry the excess into the next session")));
        assertThat(carry).containsEntry("carried", 0);
        assertThat(walletBalance(credit)).isEqualByComparingTo("30000");
        assertThat(rowOf(officer, credit)).containsEntry("state", "CREDIT_DECIDED").containsEntry("decision", "WALLET");
        // the history and the full record carry it; the student's wallet statement shows the credit
        List<Map<String, Object>> history = (List<Map<String, Object>>) (List<?>) it.getList(bursar, base + "?status=CREDITED&q=" + tag).getBody();
        assertThat(history).anySatisfy(r -> assertThat(r).containsEntry("id", id));
        Map<String, Object> picture = ok(it.get(officer, "/api/v1/finance/legacy-reconciliation/students/" + credit));
        assertThat((List<Map<String, Object>>) picture.get("requests")).hasSize(1);
        assertThat(((Number) picture.get("walletBalance")).intValue()).isEqualTo(30000);
        // the credit is usable: applied to the next session's fees through the wallet that exists; never more than it holds
        Map<String, Object> applied = ok(it.call(student, HttpMethod.POST, "/api/v1/me/wallet/apply", Map.of("session", b)));
        assertThat(String.valueOf(applied)).contains("reference");
        assertThat(jdbc.sql("SELECT paid FROM finance.position(:s, :b)").param("s", credit).param("b", b).query(BigDecimal.class).single()).isEqualByComparingTo("30000");
        assertThat(walletBalance(credit)).isEqualByComparingTo("0");
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/wallet/apply", Map.of("session", b)).getStatusCode().value()).isEqualTo(422);
        // the student who owes still owes; nothing reached their wallet
        assertThat(walletBalance(owes)).isEqualByComparingTo("0");
        assertThat(rowOf(officer, owes)).containsEntry("state", "OWES");
    }

    /** V631: the old portal's OUTSTANDING FEES payments — kept apart from school fees, verified by the Students Account Officer, credited to
     *  the wallet by a Bursar officer other than the verifier, once; the student applies the credit to the session's fees */
    @SuppressWarnings("unchecked")
    @Test
    void anOldPortalOutstandingFeesPaymentReachesTheWalletByTheOfficersVerificationAndAnotherBursarsCredit() {
        UUID owes = legacyStudent("C", "MOAUM/LRC/62/" + tag + "1", 80000);   // school fees 80,000 against 100,000
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", owes).query(String.class).single();
        String ref = "MOAUM-LEG-" + matric.replaceAll("[^0-9A-Z]", "") + "-" + a.replace("/", "-") + "-S2-OUTSTANDINGFEES";
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:s, :ses, :r, 'OUTSTANDING FEES (legacy) · semester 2', 20000, now(), now() - interval '10 days', :by, 'Legacy', 'LEG-' || :r,
                        'Imported from the old portal · Interswitch · old ref PR' || :t)
                """).param("s", owes).param("ses", a).param("r", ref).param("by", UUID.randomUUID()).param("t", tag).update());
        UUID paymentId = jdbc.sql("SELECT id FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(UUID.class).single();
        String student = TestTokens.token(owes, List.of("student"));
        String base = "/api/v1/finance/legacy-reconciliation/outstanding-payments";

        // listed apart, waiting; the school-fees payment is not on this list and the outstanding fees payment is not school fees
        List<Map<String, Object>> rows = (List<Map<String, Object>>) (List<?>) it.getList(officer, base + "?student=" + owes).getBody();
        assertThat(rows).hasSize(1);
        assertThat(rows.get(0)).containsEntry("reference", ref).containsEntry("status", "WAITING").containsEntry("method", "Interswitch").containsEntry("semester", 2);
        assertThat(((Number) rows.get(0).get("amount")).intValue()).isEqualTo(20000);
        assertThat(((Number) rows.get(0).get("owed")).intValue()).isEqualTo(20000);
        assertThat(jdbc.sql("SELECT paid FROM finance.position(:s, :a)").param("s", owes).param("a", a).query(BigDecimal.class).single()).isEqualByComparingTo("80000");
        assertThat(it.get(student, base + "?student=" + owes).getStatusCode().value()).isEqualTo(403);

        // the officer verifies: the confirmation is required; once only; the Bursar told; nothing credited yet
        assertThat(it.call(officer, HttpMethod.POST, base + "/verify", Map.of("ids", List.of(paymentId), "confirmed", false)).getBody().get("code")).isEqualTo("LEGACY_OUTSTANDING_CONFIRM");
        Map<String, Object> v = ok(it.call(officer, HttpMethod.POST, base + "/verify", Map.of("ids", List.of(paymentId), "note", "checked against the old portal's statement", "confirmed", true)));
        assertThat(((Number) v.get("verified")).intValue()).isEqualTo(1);
        assertThat(((Number) ok(it.call(officer, HttpMethod.POST, base + "/verify", Map.of("ids", List.of(paymentId), "confirmed", true))).get("verified")).intValue()).isZero();
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'person' AND about_id = :p AND template_key = 'LEGACY_OUTSTANDING_WAITING'").param("p", bursarId).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        assertThat(walletBalance(owes)).isEqualByComparingTo("0");

        // the officer does not credit — not as the officer, not as the Bursar; a Bursar officer returns it (a reason required) and the officer is told
        assertThat(it.call(officer, HttpMethod.POST, base + "/credit", Map.of("ids", List.of(paymentId))).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> self = ok(it.call(TestTokens.token(officerId, List.of("bursar")), HttpMethod.POST, base + "/credit", Map.of("ids", List.of(paymentId))));
        assertThat(((Number) self.get("credited")).intValue()).isZero();
        assertThat(String.valueOf(self.get("skipped_why"))).contains("verified by you");
        assertThat(it.call(bursar, HttpMethod.POST, base + "/" + paymentId + "/decide", Map.of("action", "RETURN", "reason", "short")).getBody().get("code")).isEqualTo("LEGACY_OUTSTANDING_REASON");
        Map<String, Object> returned = ok(it.call(bursar, HttpMethod.POST, base + "/" + paymentId + "/decide", Map.of("action", "RETURN", "reason", "check the old payment number against the bank")));
        assertThat(returned).containsEntry("status", "RETURNED");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'person' AND about_id = :p AND template_key = 'LEGACY_OUTSTANDING_DECIDED'").param("p", officerId).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        assertThat(((Number) ok(it.call(officer, HttpMethod.POST, base + "/verify", Map.of("ids", List.of(paymentId), "note", "the bank shows it", "confirmed", true))).get("verified")).intValue()).isEqualTo(1);

        // another Bursar officer credits it: once, its own amount, source LEGACY_OUTSTANDING, under a batch; the student told
        Map<String, Object> credited = ok(it.call(otherBursar, HttpMethod.POST, base + "/credit", Map.of("ids", List.of(paymentId), "note", "LegacyReconciliationIT")));
        assertThat(((Number) credited.get("credited")).intValue()).isEqualTo(1);
        assertThat(String.valueOf(credited.get("batch_ref"))).matches("LEGACY-OUTSTANDING/[0-9]{4}/[0-9]{6}");
        assertThat(walletBalance(owes)).isEqualByComparingTo("20000");
        assertThat(jdbc.sql("SELECT count(*) FROM finance.wallet_entry WHERE student_id = :s AND kind = 'CREDIT' AND source_code = 'LEGACY_OUTSTANDING'").param("s", owes).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND template_key = 'LEGACY_OUTSTANDING_CREDITED'").param("s", owes).query(Long.class).single()).isGreaterThanOrEqualTo(1L);
        assertThat(((Number) ok(it.call(bursar, HttpMethod.POST, base + "/credit", Map.of("ids", List.of(paymentId)))).get("credited")).intValue()).isZero();
        ResponseEntity<Map> reject = it.call(bursar, HttpMethod.POST, base + "/" + paymentId + "/decide", Map.of("action", "REJECT", "reason", "not to be credited after all"));
        assertThat(reject.getStatusCode().value()).isEqualTo(422);
        assertThat(reject.getBody().get("code")).isEqualTo("LEGACY_OUTSTANDING_CREDITED");
        rows = (List<Map<String, Object>>) (List<?>) it.getList(bursar, base + "?status=CREDITED&q=" + ref).getBody();
        assertThat(rows).singleElement().satisfies(r -> assertThat(r).containsEntry("batch_ref", credited.get("batch_ref")));
        Map<String, Object> fig = ok(it.get(bursar, "/api/v1/finance/legacy-reconciliation/figures"));
        assertThat(((Number) ((Map<String, Object>) fig.get("outstandingPayments")).get("credited")).intValue()).isGreaterThanOrEqualTo(1);

        // the student applies it to the session's school fees from the wallet: the session is paid in full
        ok(it.call(student, HttpMethod.POST, "/api/v1/me/wallet/apply", Map.of("session", a)));
        assertThat(jdbc.sql("SELECT balance FROM finance.position(:s, :a)").param("s", owes).param("a", a).query(BigDecimal.class).single()).isEqualByComparingTo("0");
        assertThat(walletBalance(owes)).isEqualByComparingTo("0");
    }
}
