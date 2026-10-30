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
        int y = it.freeYear(3100, 3800);
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

    /** V660: one of the old portal's OUTSTANDING FEES payments credited to A is found, checked (B has no school fees stated, and need
     *  not), initiated and approved, and moves with the outstanding-fees payments — A's down and B's up by the amount — and no school-fee
     *  flag; the swap says what it moved */
    @Test
    void anOldPortalOutstandingFeesPaymentIsSwappedToItsOwnerOnItsOwnFigures() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(3100, 3800);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        UUID a = it.student(it.freeSurname("ZZSWAPOA"), "C00023", it.freeNumber("MOAUM/ADM/26/8", 5), it.freeNumber("MOAU/SC/CSC/26/8", 5), 100);
        UUID b = it.student(it.freeSurname("ZZSWAPOB"), "C00023", it.freeNumber("MOAUM/ADM/26/8", 5), it.freeNumber("MOAU/SC/CSC/26/8", 5), 100);
        String ref = "MOAUM-LEG-ZZIT660-" + y + "-S2-OUTSTANDINGFEES";
        UUID officer = it.person(it.freeNumber("ZZ-SWAPO-", 6), "ZZSWAPOSAO");
        UUID payment = it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:a, :s, :r, 'OUTSTANDING FEES (legacy) · semester 2', 6709, now(), now(), :by, 'Legacy', :r, 'IT V660 old ref')
                RETURNING id
                """).param("a", a).param("s", session).param("r", ref).param("by", officer).query(UUID.class).single());
        String sao = TestTokens.token(officer, List.of("studentaccounts"));
        String bur = TestTokens.token(it.person(it.freeNumber("ZZ-SWAPO-", 6), "ZZSWAPOBURSAR"), List.of("bursar"));
        try {
            // found as an outstanding-fees payment and free to swap
            List<Map> found = it.getList(sao, BASE + "/payments?q=" + ref).getBody();
            assertThat(found).singleElement().satisfies(p -> {
                assertThat(p).containsEntry("kind", "OUTSTANDING_FEES").containsEntry("eligible", true);
            });
            ResponseEntity<Map> check = it.get(sao, BASE + "/check?payment=" + payment + "&to=" + b);
            assertThat(check.getBody()).as(String.valueOf(check.getBody())).containsEntry("ok", true);
            assertThat((Map) check.getBody().get("payment")).containsEntry("kind", "OUTSTANDING_FEES").containsEntry("outstandingStatus", "WAITING");
            assertThat(((Number) ((Map) check.getBody().get("fromAccount")).get("outstandingPaid")).doubleValue()).isEqualTo(6709);
            assertThat(((Number) ((Map) check.getBody().get("toAccount")).get("outstandingPaid")).doubleValue()).isEqualTo(0);

            // initiated by the Students Account Officer, approved by a Bursar officer: it moves whole, on its own figures
            Map swap = (Map) it.call(sao, HttpMethod.POST, BASE, Map.of("payment", payment, "to", b,
                    "reason", "The outstanding fees were paid on A's number for B; the old portal statement shows it", "confirmed", true)).getBody().get("swap");
            assertThat(swap).as(String.valueOf(swap)).containsEntry("status", "PENDING_APPROVAL");
            ResponseEntity<Map> done = it.call(bur, HttpMethod.POST, BASE + "/" + swap.get("id") + "/decide", Map.of("approve", true, "confirmed", true, "note", "Checked"));
            assertThat((Map) done.getBody().get("result")).as(String.valueOf(done.getBody())).containsEntry("status", "COMPLETED").containsEntry("kind", "OUTSTANDING_FEES");
            assertThat(jdbc.sql("SELECT student_id FROM finance.payment_reference WHERE id = :p").param("p", payment).query(UUID.class).single()).isEqualTo(b);
            assertThat(jdbc.sql("SELECT finance.payment_swap_outstanding(:s, :ses)").param("s", a).param("ses", session).query(Double.class).single()).isZero();
            assertThat(jdbc.sql("SELECT finance.payment_swap_outstanding(:s, :ses)").param("s", b).param("ses", session).query(Double.class).single()).isEqualTo(6709);
            assertThat(jdbc.sql("SELECT cardinality(flags) FROM finance.payment_swap WHERE id = :w").param("w", UUID.fromString(String.valueOf(swap.get("id"))))
                    .query(Integer.class).single()).isZero();
        } finally {
            it.db(() -> {
                jdbc.sql("DELETE FROM finance.payment_swap WHERE payment_id = :p").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.payment_reference WHERE id = :p").param("p", payment).update();
                return null;
            });
        }
    }

    /** V708: an OUTSTANDING FEES payment the Bursary already credited to A's wallet (V631) is free to swap, with its wallet credit: the
     *  check shows both wallets, and once a Bursar officer approves, the same wallet entry stands on B's wallet — A's wallet down and
     *  B's up by the amount — its desk record on B, and the swap says it moved the credit */
    @Test
    void anOutstandingFeesPaymentCreditedToTheWalletIsSwappedWithItsWalletCredit() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(3100, 3800);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        UUID a = it.student(it.freeSurname("ZZSWAPWA"), "C00023", it.freeNumber("MOAUM/ADM/26/9", 5), it.freeNumber("MOAU/SC/CSC/26/9", 5), 100);
        UUID b = it.student(it.freeSurname("ZZSWAPWB"), "C00023", it.freeNumber("MOAUM/ADM/26/9", 5), it.freeNumber("MOAU/SC/CSC/26/9", 5), 100);
        String ref = "MOAUM-LEG-ZZIT708-" + y + "-S1-OUTSTANDINGFEES";
        UUID officer = it.person(it.freeNumber("ZZ-SWAPW-", 6), "ZZSWAPWSAO");
        UUID crediter = it.person(it.freeNumber("ZZ-SWAPW-", 6), "ZZSWAPWCREDIT");
        UUID payment = it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:a, :s, :r, 'OUTSTANDING FEES (legacy) · semester 1', 4000, now(), now(), :by, 'Legacy', :r, 'IT V708 old ref')
                RETURNING id
                """).param("a", a).param("s", session).param("r", ref).param("by", officer).query(UUID.class).single());
        // the wallet desk (V631): verified by the Students Account Officer, credited to A's wallet by a Bursar officer
        it.db(() -> {
            jdbc.sql("SELECT set_config('moaum.actor_id', :p, true), set_config('moaum.actor_office', 'studentaccounts', true)").param("p", officer.toString()).query().singleRow();
            jdbc.sql("SELECT finance.legacy_outstanding_payment_verify(ARRAY[:p]::uuid[], 'checked against the old portal statement')").param("p", payment).query().listOfRows();
            jdbc.sql("SELECT set_config('moaum.actor_id', :p, true), set_config('moaum.actor_office', 'bursar', true)").param("p", crediter.toString()).query().singleRow();
            jdbc.sql("SELECT * FROM finance.legacy_outstanding_payment_credit(ARRAY[:p]::uuid[], 'IT V708')").param("p", payment).query().listOfRows();
            return null;
        });
        UUID entry = jdbc.sql("SELECT wallet_entry_id FROM finance.legacy_outstanding_payment WHERE payment_id = :p").param("p", payment).query(UUID.class).single();
        String sao = TestTokens.token(officer, List.of("studentaccounts"));
        String bur = TestTokens.token(it.person(it.freeNumber("ZZ-SWAPW-", 6), "ZZSWAPWBURSAR"), List.of("bursar"));
        try {
            List<Map> found = it.getList(sao, BASE + "/payments?q=" + ref).getBody();
            assertThat(found).singleElement().satisfies(p -> assertThat(p).as(String.valueOf(p)).containsEntry("eligible", true));
            ResponseEntity<Map> check = it.get(sao, BASE + "/check?payment=" + payment + "&to=" + b);
            assertThat(check.getBody()).as(String.valueOf(check.getBody())).containsEntry("ok", true);
            Map paid = (Map) check.getBody().get("payment");
            assertThat(paid).containsEntry("outstandingStatus", "CREDITED");
            assertThat(((Number) ((Map) paid.get("walletCredit")).get("walletBalance")).doubleValue()).isEqualTo(4000);
            assertThat(((Number) ((Map) check.getBody().get("fromAccount")).get("wallet")).doubleValue()).isEqualTo(4000);
            assertThat(((Number) ((Map) check.getBody().get("toAccount")).get("wallet")).doubleValue()).isEqualTo(0);

            Map swap = (Map) it.call(sao, HttpMethod.POST, BASE, Map.of("payment", payment, "to", b,
                    "reason", "Credited to A's wallet in error: the old portal statement names B", "confirmed", true)).getBody().get("swap");
            assertThat(swap).as(String.valueOf(swap)).containsEntry("status", "PENDING_APPROVAL");
            ResponseEntity<Map> done = it.call(bur, HttpMethod.POST, BASE + "/" + swap.get("id") + "/decide", Map.of("approve", true, "confirmed", true, "note", "Checked"));
            assertThat((Map) done.getBody().get("result")).as(String.valueOf(done.getBody())).containsEntry("status", "COMPLETED").containsEntry("walletMoved", true);
            assertThat(jdbc.sql("SELECT student_id FROM finance.wallet_entry WHERE id = :e").param("e", entry).query(UUID.class).single()).as("the same entry, on B").isEqualTo(b);
            assertThat(jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", a).query(Double.class).single()).isZero();
            assertThat(jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", b).query(Double.class).single()).isEqualTo(4000);
            assertThat(jdbc.sql("SELECT status || '/' || (student_id = :b) FROM finance.legacy_outstanding_payment WHERE payment_id = :p")
                    .param("b", b).param("p", payment).query(String.class).single()).isEqualTo("CREDITED/true");
            List<Map> events = (List<Map>) it.get(bur, BASE + "/" + swap.get("id")).getBody().get("events");
            assertThat(events).extracting(e -> e.get("action")).contains("PAYMENT_WALLET_CREDIT_MOVED");
        } finally {
            it.db(() -> {
                jdbc.sql("SELECT set_config('moaum.maintenance', 'on', true)").query().singleRow();
                jdbc.sql("DELETE FROM finance.payment_swap WHERE payment_id = :p").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.wallet_entry WHERE id = :e").param("e", entry).update();
                jdbc.sql("DELETE FROM finance.payment_reference WHERE id = :p").param("p", payment).update();
                return null;
            });
        }
    }

    /** V710: a payment the Bursary credited to A's wallet, 1,000 of it used, is swapped whole to B: A's wallet owes 1,000, the swap is
     *  flagged and says so, A is on the Bursary's list of wallets owing with the swap; the check says what A will owe */
    @Test
    void aCreditedPaymentAlreadyUsedIsSwappedWholeAndTheWalletOwes() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(3100, 3800);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String aMatric = it.freeNumber("MOAU/SC/CSC/26/6", 5);
        UUID a = it.student(it.freeSurname("ZZSWAPDA"), "C00023", it.freeNumber("MOAUM/ADM/26/6", 5), aMatric, 100);
        UUID b = it.student(it.freeSurname("ZZSWAPDB"), "C00023", it.freeNumber("MOAUM/ADM/26/6", 5), it.freeNumber("MOAU/SC/CSC/26/6", 5), 100);
        String ref = "MOAUM-LEG-ZZIT710-" + y + "-S1-OUTSTANDINGFEES";
        UUID officer = it.person(it.freeNumber("ZZ-SWAPD-", 6), "ZZSWAPDSAO");
        UUID crediter = it.person(it.freeNumber("ZZ-SWAPD-", 6), "ZZSWAPDCREDIT");
        UUID payment = it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:a, :s, :r, 'OUTSTANDING FEES (legacy) · semester 1', 4000, now(), now(), :by, 'Legacy', :r, 'IT V710 old ref')
                RETURNING id
                """).param("a", a).param("s", session).param("r", ref).param("by", officer).query(UUID.class).single());
        it.db(() -> {
            jdbc.sql("SELECT set_config('moaum.actor_id', :p, true), set_config('moaum.actor_office', 'studentaccounts', true)").param("p", officer.toString()).query().singleRow();
            jdbc.sql("SELECT finance.legacy_outstanding_payment_verify(ARRAY[:p]::uuid[], 'checked against the old portal statement')").param("p", payment).query().listOfRows();
            jdbc.sql("SELECT set_config('moaum.actor_id', :p, true), set_config('moaum.actor_office', 'bursar', true)").param("p", crediter.toString()).query().singleRow();
            jdbc.sql("SELECT * FROM finance.legacy_outstanding_payment_credit(ARRAY[:p]::uuid[], 'IT V710')").param("p", payment).query().listOfRows();
            // 1,000 of it used from A's wallet
            jdbc.sql("INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code) VALUES (:a, :s, 'APPLIED', 1000, :r, 'IT V710: used', 'LEGACY_OUTSTANDING')")
                    .param("a", a).param("s", session).param("r", "ZZIT710-APPLIED-" + y).update();
            return null;
        });
        UUID entry = jdbc.sql("SELECT wallet_entry_id FROM finance.legacy_outstanding_payment WHERE payment_id = :p").param("p", payment).query(UUID.class).single();
        String sao = TestTokens.token(officer, List.of("studentaccounts"));
        String bur = TestTokens.token(it.person(it.freeNumber("ZZ-SWAPD-", 6), "ZZSWAPDBURSAR"), List.of("bursar"));
        try {
            ResponseEntity<Map> check = it.get(sao, BASE + "/check?payment=" + payment + "&to=" + b);
            assertThat(check.getBody()).as(String.valueOf(check.getBody())).containsEntry("ok", true);
            assertThat(((Number) ((Map) ((Map) check.getBody().get("payment")).get("walletCredit")).get("owesAfter")).doubleValue()).isEqualTo(1000);
            Map swap = (Map) it.call(sao, HttpMethod.POST, BASE, Map.of("payment", payment, "to", b,
                    "reason", "Credited to A's wallet in error and partly used: the statement names B", "confirmed", true)).getBody().get("swap");
            ResponseEntity<Map> done = it.call(bur, HttpMethod.POST, BASE + "/" + swap.get("id") + "/decide", Map.of("approve", true, "confirmed", true, "note", "Checked"));
            Map result = (Map) done.getBody().get("result");
            assertThat(result).as(String.valueOf(done.getBody())).containsEntry("status", "COMPLETED").containsEntry("walletMoved", true);
            assertThat(((Number) result.get("walletOwes")).doubleValue()).isEqualTo(1000);
            assertThat(jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", a).query(Double.class).single()).isEqualTo(-1000);
            assertThat(jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", b).query(Double.class).single()).isEqualTo(4000);
            assertThat(jdbc.sql("SELECT 'FROM_WALLET_OWES' = ANY (flags) FROM finance.payment_swap WHERE id = :w").param("w", UUID.fromString(String.valueOf(swap.get("id"))))
                    .query(Boolean.class).single()).isTrue();
            // on the Bursary's list, found by the matriculation number
            ResponseEntity<Map> debts = it.get(bur, BASE + "/wallet-debts?q=" + aMatric);
            assertThat(debts.getStatusCode().value()).as(String.valueOf(debts.getBody())).isEqualTo(200);
            assertThat((List<Map>) debts.getBody().get("rows")).singleElement().satisfies(r -> {
                assertThat(((Number) r.get("owed")).doubleValue()).isEqualTo(1000);
                assertThat(r.get("swap_ref")).isEqualTo(swap.get("swap_ref"));
            });
            assertThat(it.get(ItSupport.token("registrar"), BASE + "/wallet-debts").getStatusCode().value()).isEqualTo(403);

            // V714: A sees what the wallet owes and pays it — a reference for the 1,000, credited to the wallet once confirmed
            String student = TestTokens.token(a, List.of("student"));
            Map owed = (Map) it.get(student, "/api/v1/me/wallet").getBody().get("owed");
            assertThat(((Number) owed.get("owed")).doubleValue()).isEqualTo(1000);
            assertThat(owed.get("swap_ref")).isEqualTo(swap.get("swap_ref"));
            ResponseEntity<Map> owedReference = it.call(student, HttpMethod.POST, "/api/v1/me/wallet/owed-reference", Map.of());
            assertThat(owedReference.getStatusCode().value()).as(String.valueOf(owedReference.getBody())).isEqualTo(200);
            assertThat(((Number) owedReference.getBody().get("amount")).doubleValue()).isEqualTo(1000);
            String owedRef = String.valueOf(owedReference.getBody().get("reference"));
            it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'Card', 'IT V714: what the wallet owes, paid')").param("r", owedRef).query().listOfRows());
            assertThat(jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", a).query(Double.class).single()).isZero();
            assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/wallet/owed-reference", Map.of()).getBody().get("code")).isEqualTo("WALLET_NOTHING_OWED");
            it.db(() -> jdbc.sql("DELETE FROM finance.wallet_entry WHERE reference = :r").param("r", owedRef).update());
        } finally {
            it.db(() -> {
                jdbc.sql("SELECT set_config('moaum.maintenance', 'on', true)").query().singleRow();
                jdbc.sql("DELETE FROM finance.payment_swap WHERE payment_id = :p").param("p", payment).update();
                jdbc.sql("DELETE FROM finance.wallet_entry WHERE id = :e OR reference = :r").param("e", entry).param("r", "ZZIT710-APPLIED-" + y).update();
                jdbc.sql("DELETE FROM finance.payment_reference WHERE id = :p").param("p", payment).update();
                return null;
            });
        }
    }
}
