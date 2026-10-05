package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
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
 * V327 — the funding wallet over the API: the student reads their wallet by source and the top-up decision; a top-up above the
 * shortfall and a top-up when nothing is short are refused by the server whatever the screen says; a scholarship cannot be
 * refunded as NELFUND; a student cannot credit a wallet nor read another's; the old portal's NELFUND payments are posted once.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class NelfundWalletIT {

    private static final String SESSION = "2091/2092";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    ItSupport it;
    String bursar = ItSupport.token("bursar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2091);
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.fee_schedule (id, session, item, amount, level, ord)
                SELECT gen_random_uuid(), :s, 'School fees', 100000, 200, 1
                 WHERE NOT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = :s AND f.item = 'School fees' AND f.level = 200 AND f.ended_at IS NULL)
                """).param("s", SESSION).update());
    }

    /** an invented student whose numbers fit the register's shapes; at 200 level: within the programme, and no earlier session's schedule on the shared test database prices it, so nothing reads as arrears */
    private UUID student() {
        String tag = String.format("%06d", java.util.concurrent.ThreadLocalRandom.current().nextInt(1_000_000));
        return it.db(() -> {
            UUID id = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
                    VALUES (:id, :adm, :mat, :sn, 'Invented', 'C00023', 'UTME', :s, 100, 200, 'ACTIVE', now())
                    """).param("id", id).param("adm", "MOAUM/ADM/91/" + tag).param("mat", "MOAUM/NEL/91/" + tag).param("sn", "ZZNELFUND" + tag.toUpperCase()).param("s", SESSION).update();
            return id;
        });
    }

    @SuppressWarnings("rawtypes")
    private ResponseEntity<Map> as(String token, String office, HttpMethod method, String path, Object body) {
        return it.callWith(token, method, path, body, Map.of("X-Active-Office", office));
    }

    @Test
    @SuppressWarnings({"rawtypes", "unchecked"})
    void theTopUpIsForTheShortfallTheServerWorksOutAndNothingMore() {
        UUID s = student();
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :id").param("id", s).query(String.class).single();
        String me = TestTokens.token(s, List.of("student"));
        // the Fund remits 60,000 against a charge of 100,000
        ResponseEntity<Map> credit = as(bursar, "bursar", HttpMethod.POST, "/api/v1/nelfund/credit",
                Map.of("number", matric, "session", SESSION, "amount", 60000, "reason", "NELFUND remittance NLF/2091/1", "source", "NELFUND"));
        assertThat(credit.getStatusCode().value()).as(String.valueOf(credit.getBody())).isEqualTo(200);
        ResponseEntity<Map> w = as(me, "student", HttpMethod.GET, "/api/v1/me/wallet?session=" + SESSION, null);
        assertThat(w.getStatusCode().value()).as(String.valueOf(w.getBody())).isEqualTo(200);
        Map<String, Object> topup = (Map<String, Object>) w.getBody().get("topup");
        assertThat(topup.get("allowed")).isEqualTo(true);
        assertThat(new BigDecimal(String.valueOf(topup.get("shortfall")))).isEqualByComparingTo("40000");
        assertThat(new BigDecimal(String.valueOf(topup.get("max_topup")))).isEqualByComparingTo("40000");
        List<Map<String, Object>> balances = (List<Map<String, Object>>) w.getBody().get("balances");
        assertThat(balances).anySatisfy(b -> { assertThat(b.get("source_code")).isEqualTo("NELFUND"); assertThat(new BigDecimal(String.valueOf(b.get("available")))).isEqualByComparingTo("60000"); });
        // above the shortfall: refused by the server
        ResponseEntity<Map> above = as(me, "student", HttpMethod.POST, "/api/v1/me/wallet/topup-reference", Map.of("session", SESSION, "amount", 50000));
        assertThat(above.getStatusCode().value()).as(String.valueOf(above.getBody())).isEqualTo(422);
        assertThat(above.getBody().get("code")).isEqualTo("WALLET_TOPUP_ABOVE_SHORTFALL");
        // exactly the shortfall: a reference, with the reasoning on it
        ResponseEntity<Map> ok = as(me, "student", HttpMethod.POST, "/api/v1/me/wallet/topup-reference", Map.of("session", SESSION, "amount", 40000));
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
        String ref = String.valueOf(ok.getBody().get("reference"));
        assertThat(jdbc.sql("SELECT note FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(String.class).single()).startsWith("Shortfall top-up: fees 100000");
        // the gateway confirms it: the wallet now covers the charge, so a further top-up is not required
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'WebPAY', 'NelfundWalletIT')").param("r", ref).query(String.class).single());
        ResponseEntity<Map> none = as(me, "student", HttpMethod.POST, "/api/v1/me/wallet/topup-reference", Map.of("session", SESSION, "amount", 1000));
        assertThat(none.getStatusCode().value()).as(String.valueOf(none.getBody())).isEqualTo(422);
        assertThat(none.getBody().get("code")).isEqualTo("WALLET_TOPUP_NOT_REQUIRED");
        // applied: loan first, then the student's own money, each on its own entry; the student's money is never the Fund's
        ResponseEntity<Map> applied = as(me, "student", HttpMethod.POST, "/api/v1/me/wallet/apply", Map.of("session", SESSION));
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT coalesce(sum(amount), 0) FROM finance.wallet_entry WHERE student_id = :s AND kind = 'APPLIED' AND source_code = 'NELFUND'").param("s", s).query(BigDecimal.class).single()).isEqualByComparingTo("60000");
        assertThat(jdbc.sql("SELECT coalesce(sum(amount), 0) FROM finance.wallet_entry WHERE student_id = :s AND kind = 'APPLIED' AND source_code = 'SELF'").param("s", s).query(BigDecimal.class).single()).isEqualByComparingTo("40000");
        // a student cannot credit a wallet, nor read the Bursary's desk
        assertThat(as(me, "student", HttpMethod.POST, "/api/v1/nelfund/credit", Map.of("number", "x", "session", SESSION, "amount", 1, "reason", "me", "source", "NELFUND")).getStatusCode().value()).isEqualTo(403);
        assertThat(as(me, "student", HttpMethod.GET, "/api/v1/nelfund/student/statement?number=x", null).getStatusCode().value()).isEqualTo(403);
    }

    @Test
    @SuppressWarnings({"rawtypes", "unchecked"})
    void aRefundIsOfTheFundsMoneyThatArrivedAfterTheFeesWerePaidAndNeverOfAScholarship() {
        UUID s = student();
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :id").param("id", s).query(String.class).single();
        String me = TestTokens.token(s, List.of("student"));
        // the student pays the whole charge personally; then the Fund's money lands, and a scholarship with it
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(finance.new_reference(:s, :n, 100000, NULL), 'WebPAY', 'paid personally')").param("s", s).param("n", SESSION).query(String.class).single());
        assertThat(as(bursar, "bursar", HttpMethod.POST, "/api/v1/nelfund/credit", Map.of("number", matric, "session", SESSION, "amount", 100000, "reason", "NELFUND remittance NLF/2091/2", "source", "NELFUND")).getStatusCode().value()).isEqualTo(200);
        assertThat(as(bursar, "bursar", HttpMethod.POST, "/api/v1/nelfund/credit", Map.of("number", matric, "session", SESSION, "amount", 20000, "reason", "State scholarship", "source", "SCHOLARSHIP")).getStatusCode().value()).isEqualTo(200);
        // a credit of no source is refused
        ResponseEntity<Map> noSource = as(bursar, "bursar", HttpMethod.POST, "/api/v1/nelfund/credit", Map.of("number", matric, "session", SESSION, "amount", 5000, "reason", "from nowhere"));
        assertThat(noSource.getStatusCode().value()).as(String.valueOf(noSource.getBody())).isEqualTo(422);
        assertThat(noSource.getBody().get("code")).isEqualTo("WALLET_SOURCE_REQUIRED");
        ResponseEntity<Map> w = as(me, "student", HttpMethod.GET, "/api/v1/me/wallet?session=" + SESSION, null);
        Map<String, Object> elig = (Map<String, Object>) w.getBody().get("eligibility");
        assertThat(elig.get("eligible")).isEqualTo(true);
        assertThat(new BigDecimal(String.valueOf(elig.get("nelfund_refundable")))).isEqualByComparingTo("100000");
        assertThat(new BigDecimal(String.valueOf(elig.get("grant_held")))).isEqualByComparingTo("20000");
        assertThat(elig.get("nelfund_after_settlement")).isEqualTo(true);
        assertThat(((Map<String, Object>) w.getBody().get("topup")).get("reason")).isEqualTo("FEES_SETTLED");
        // the scholarship cannot be refunded as NELFUND, nor more than the Fund's money
        ResponseEntity<Map> grant = as(me, "student", HttpMethod.POST, "/api/v1/me/wallet/withdrawal",
                Map.of("session", SESSION, "amount", 20000, "bank", "Check Bank", "accountNo", "0123456789", "accountName", "ZZNELFUND", "source", "SCHOLARSHIP"));
        assertThat(grant.getStatusCode().value()).as(String.valueOf(grant.getBody())).isEqualTo(422);
        assertThat(grant.getBody().get("code")).isEqualTo("WALLET_REFUND_SOURCE");
        ResponseEntity<Map> over = as(me, "student", HttpMethod.POST, "/api/v1/me/wallet/withdrawal",
                Map.of("session", SESSION, "amount", 120000, "bank", "Check Bank", "accountNo", "0123456789", "accountName", "ZZNELFUND", "source", "NELFUND"));
        assertThat(over.getStatusCode().value()).as(String.valueOf(over.getBody())).isEqualTo(422);
        assertThat(over.getBody().get("code")).isEqualTo("WALLET_REFUND_ABOVE_REFUNDABLE");
        ResponseEntity<Map> req = as(me, "student", HttpMethod.POST, "/api/v1/me/wallet/withdrawal",
                Map.of("session", SESSION, "bank", "Check Bank", "accountNo", "0123456789", "accountName", "ZZNELFUND"));
        assertThat(req.getStatusCode().value()).as(String.valueOf(req.getBody())).isEqualTo(200);
        assertThat(req.getBody().get("source_code")).isEqualTo("NELFUND");
        assertThat(new BigDecimal(String.valueOf(req.getBody().get("amount")))).isEqualByComparingTo("100000");
        // a second request while one is pending is refused
        assertThat(as(me, "student", HttpMethod.POST, "/api/v1/me/wallet/withdrawal", Map.of("session", SESSION, "bank", "B", "accountNo", "1", "accountName", "N")).getStatusCode().value()).isEqualTo(422);
        // the Bursary approves (another person) and a third pays: the Fund's money leaves, the scholarship stays
        String id = String.valueOf(req.getBody().get("id"));
        assertThat(as(ItSupport.token("bursar"), "bursar", HttpMethod.POST, "/api/v1/funding/withdrawals/" + id + "/approve", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(as(ItSupport.token("bursar"), "bursar", HttpMethod.POST, "/api/v1/funding/withdrawals/" + id + "/pay", Map.of("ref", "TRF-IT-327")).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> after = as(me, "student", HttpMethod.GET, "/api/v1/me/wallet?session=" + SESSION, null);
        List<Map<String, Object>> balances = (List<Map<String, Object>>) after.getBody().get("balances");
        assertThat(balances).anySatisfy(b -> { assertThat(b.get("source_code")).isEqualTo("NELFUND"); assertThat(new BigDecimal(String.valueOf(b.get("available")))).isEqualByComparingTo("0"); assertThat(new BigDecimal(String.valueOf(b.get("refunded")))).isEqualByComparingTo("100000"); });
        assertThat(balances).anySatisfy(b -> { assertThat(b.get("source_code")).isEqualTo("SCHOLARSHIP"); assertThat(new BigDecimal(String.valueOf(b.get("available")))).isEqualByComparingTo("20000"); });
        // the desk answers the Bursary's questions
        ResponseEntity<Map> fig = as(bursar, "bursar", HttpMethod.GET, "/api/v1/nelfund/figures?session=" + SESSION, null);
        assertThat(fig.getStatusCode().value()).as(String.valueOf(fig.getBody())).isEqualTo(200);
        assertThat(((Map<String, Object>) fig.getBody().get("figures")).get("refunds_paid")).isNotNull();
        ResponseEntity<Map> rows = as(bursar, "bursar", HttpMethod.GET, "/api/v1/nelfund/students?session=" + SESSION + "&filter=PAID_BEFORE_FUND&q=" + matric, null);
        assertThat(rows.getStatusCode().value()).isEqualTo(200);
    }

    @Test
    @SuppressWarnings({"rawtypes", "unchecked"})
    void theOldPortalsNelfundPaymentsArePostedOnceForTheSessionTheyName() {
        UUID s = student();
        String matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :id").param("id", s).query(String.class).single();
        String ref = "NEL-IT-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        List<Map<String, Object>> rows = List.of(
                Map.of("reference", ref, "matric", matric, "amount", "150000", "paidAt", "2092-02-01", "session", SESSION, "status", "SUCCESS"),
                Map.of("reference", ref + "-F", "matric", matric, "amount", "50000", "paidAt", "2092-02-02", "session", SESSION, "status", "FAILED"),
                Map.of("reference", ref + "-N", "name", "Nobody At All", "amount", "70000", "paidAt", "2092-02-03", "session", SESSION, "status", "SUCCESS"));
        // a dry run writes nothing
        ResponseEntity<Map> dry = as(bursar, "bursar", HttpMethod.POST, "/api/v1/nelfund/legacy/imports", Map.of("rows", rows, "fileName", "nelfund-old.xlsx", "dryRun", true));
        assertThat(dry.getStatusCode().value()).as(String.valueOf(dry.getBody())).isEqualTo(200);
        assertThat(((Map<String, Object>) dry.getBody().get("summary")).get("matched")).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM finance.legacy_nelfund_payment WHERE source_reference = :r").param("r", ref).query(Long.class).single()).isZero();
        // staged, then posted; the student's wallet carries it for that session, once
        ResponseEntity<Map> staged = as(bursar, "bursar", HttpMethod.POST, "/api/v1/nelfund/legacy/imports", Map.of("rows", rows, "fileName", "nelfund-old.xlsx", "dryRun", false));
        assertThat(staged.getStatusCode().value()).as(String.valueOf(staged.getBody())).isEqualTo(200);
        String importId = String.valueOf(((Map<String, Object>) staged.getBody().get("import")).get("id"));
        ResponseEntity<Map> applied = as(bursar, "bursar", HttpMethod.POST, "/api/v1/nelfund/legacy/imports/" + importId + "/apply", Map.of());
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        assertThat(((Map<String, Object>) applied.getBody().get("applied")).get("posted")).isEqualTo(1);
        assertThat(as(bursar, "bursar", HttpMethod.POST, "/api/v1/nelfund/legacy/imports/" + importId + "/apply", Map.of()).getBody().toString()).contains("posted=0");
        // the same file again stages nothing
        ResponseEntity<Map> again = as(bursar, "bursar", HttpMethod.POST, "/api/v1/nelfund/legacy/imports", Map.of("rows", rows, "fileName", "nelfund-old.xlsx", "dryRun", false));
        assertThat(((Map<String, Object>) again.getBody().get("staging")).get("already_staged")).isEqualTo(3);
        String me = TestTokens.token(s, List.of("student"));
        ResponseEntity<Map> w = as(me, "student", HttpMethod.GET, "/api/v1/me/wallet?session=" + SESSION, null);
        List<Map<String, Object>> statement = (List<Map<String, Object>>) w.getBody().get("statement");
        assertThat(statement).anySatisfy(e -> { assertThat(e.get("origin")).isEqualTo("OLD_PORTAL"); assertThat(e.get("legacy_reference")).isEqualTo(ref); assertThat(e.get("session")).isEqualTo(SESSION); });
        assertThat(jdbc.sql("SELECT count(*) FROM finance.wallet_entry WHERE student_id = :s AND source_code = 'NELFUND' AND kind = 'CREDIT'").param("s", s).query(Long.class).single()).isEqualTo(1L);
        // the queue holds the name-only row; a student may not read it
        assertThat(as(me, "student", HttpMethod.GET, "/api/v1/nelfund/legacy/rows?status=OPEN", null).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> queue = as(bursar, "bursar", HttpMethod.GET, "/api/v1/nelfund/legacy/rows?status=OPEN&q=" + ref + "-N", null);
        assertThat(queue.getStatusCode().value()).isEqualTo(200);
        assertThat(((List<?>) queue.getBody().get("rows"))).hasSize(1);
    }
}
