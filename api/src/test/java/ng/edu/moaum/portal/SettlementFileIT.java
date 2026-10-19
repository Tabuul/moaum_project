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
 * V570: Interswitch's settlement report. Internal Audit uploads it and every row is matched to the portal — a paid reference
 * (MATCHED), one never confirmed (NOT_CONFIRMED), one not the portal's (UNKNOWN). The day is tied to the collections credit of its
 * net by the Bursary (not by Internal Audit), Interswitch's fees booked against 5250 Bank charges in the same press, and its payments
 * are no longer "not received"; the tie is taken back. The never-confirmed row goes to the bank credits once. A student may do none
 * of it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class SettlementFileIT {

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

    /** six digits no portal reference of this shape uses yet */
    private String freeTag() {
        for (int i = 0; i < 500; i++) {
            String tag = String.valueOf(java.util.concurrent.ThreadLocalRandom.current().nextInt(100_000, 1_000_000));
            if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference LIKE 'MOAUM-FEE-' || :t || '-%')")
                    .param("t", tag).query(Boolean.class).single()) {
                return tag;
            }
        }
        throw new IllegalStateException("no free reference tag");
    }

    @Test
    void theSettlementReportIsMatchedEachDayTiedToItsCreditAndTheChargesBooked() {
        String tag = freeTag();
        String audit = ItSupport.token("audit");
        String bursar = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String student = TestTokens.token(UUID.randomUUID(), List.of("student"));
        String session = "9963/9964";
        it.session(session, 9963);
        UUID s = it.student(it.freeSurname("ZZSETTLE"), "C00023", null, it.freeNumber("MOAUM/MTC/63/", 4), 100);
        // the day and its payments are the session's own, far ahead, so no other test's credits or payments share them
        String day = "9963-10-15", next = "9963-10-16";
        String paid = "MOAUM-FEE-" + tag + "-0001", open = "MOAUM-FEE-" + tag + "-0002";
        // kobo of the test's own, so no other test's credit is a candidate
        int kobo = java.util.concurrent.ThreadLocalRandom.current().nextInt(1, 99);
        BigDecimal amount = new BigDecimal("8000." + String.format("%02d", kobo));
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                VALUES (:s, :ses, :paid, 'School fees ' || :ses, :amt, :day::timestamp AT TIME ZONE 'Africa/Lagos', now() + interval '7 days',
                        (:day::timestamp + interval '9 hours') AT TIME ZONE 'Africa/Lagos', gen_random_uuid(), 'Quickteller · WEB', 'RCT-IT-' || :paid, 'V570 IT'),
                       (:s, :ses, :open, 'School fees ' || :ses, 1500, :day::timestamp AT TIME ZONE 'Africa/Lagos', now() + interval '7 days', NULL, NULL, NULL, NULL, 'V570 IT')
                """).param("s", s).param("ses", session).param("paid", paid).param("open", open).param("amt", amount).param("day", day).update());
        // the collections statement: the day's net credited the day after
        BigDecimal net = amount.add(new BigDecimal("1500")).add(new BigDecimal("700")).subtract(new BigDecimal("102"));
        ResponseEntity<Map> st = it.call(audit, HttpMethod.POST, "/api/v1/finance/collections/statements", Map.of("label", "IT V570 " + tag, "fileName", "c.csv",
                "rows", List.of(Map.of("date", next, "description", "ISW SETTLEMENT " + tag, "credit", net.toPlainString()))));
        assertThat(st.getStatusCode().value()).as(String.valueOf(st.getBody())).isEqualTo(200);
        String line = String.valueOf(((List<Map>) st.getBody().get("lines")).get(0).get("id"));
        String statement = String.valueOf(st.getBody().get("id"));

        List<Map<String, Object>> rows = List.of(
                Map.of("settledOn", day, "reference", paid.replace("-", ""), "logId", "LOG" + tag + "1", "amount", amount.toPlainString(), "fee", "80"),
                Map.of("settledOn", day, "reference", open.toLowerCase(), "logId", "LOG" + tag + "2", "amount", "1500", "fee", "15"),
                Map.of("settledOn", day, "reference", "NOTTHEPORTALS" + tag, "logId", "LOG" + tag + "3", "amount", "700", "net", "693"));
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/finance/settlements", Map.of("label", "x", "rows", rows)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> up = it.call(audit, HttpMethod.POST, "/api/v1/finance/settlements", Map.of("label", "IT V570 " + tag, "fileName", "settlement.xlsx", "rows", rows));
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        String file = String.valueOf(((Map) up.getBody().get("file")).get("id"));
        assertThat((List<Map>) up.getBody().get("items")).extracting(i -> i.get("row_no") + ":" + i.get("state"))
                .containsExactlyInAnyOrder("1:MATCHED", "2:NOT_CONFIRMED", "3:UNKNOWN");
        Map d = ((List<Map>) up.getBody().get("days")).get(0);
        assertThat(new BigDecimal(String.valueOf(d.get("net")))).isEqualByComparingTo(net);
        assertThat(new BigDecimal(String.valueOf(d.get("fees")))).isEqualByComparingTo("102");
        assertThat((List<Map>) up.getBody().get("candidates")).extracting(c -> String.valueOf(c.get("line_id"))).containsExactly(line);
        assertThat((List<Map>) it.getList(audit, "/api/v1/finance/settlements").getBody()).anyMatch(f -> file.equals(String.valueOf(f.get("id"))));

        // tied by the Bursary, not by Internal Audit: the charges booked, the paid reference no longer "not received"
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/settlements/" + file + "/tie-all", Map.of()).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> tied = it.call(bursar, HttpMethod.POST, "/api/v1/finance/settlements/" + file + "/tie-all", Map.of());
        assertThat(tied.getStatusCode().value()).as(String.valueOf(tied.getBody())).isEqualTo(200);
        assertThat(tied.getBody()).containsEntry("tied", 1);
        Map tiedDay = ((List<Map>) tied.getBody().get("days")).get(0);
        assertThat(String.valueOf(tiedDay.get("line_id"))).isEqualTo(line);
        assertThat(tiedDay.get("journal_no")).isNotNull();
        assertThat(jdbc.sql("""
                SELECT string_agg(p.account || ':' || p.debit::int || ':' || p.credit::int, ',' ORDER BY p.account)
                  FROM finance.gl_posting p JOIN finance.gl_journal j ON j.id = p.journal_id WHERE j.journal_no = :n
                """).param("n", ((Number) tiedDay.get("journal_no")).longValue()).query(String.class).single()).isEqualTo("1010:0:102,5250:102:0");
        assertThat((List<Map>) it.get(audit, "/api/v1/finance/collections/statements/" + statement).getBody().get("notReceived"))
                .noneMatch(n -> paid.equals(n.get("reference")));

        // taken back: the line unmatched again and the paid reference "not received" again
        ResponseEntity<Map> untied = it.call(bursar, HttpMethod.POST, "/api/v1/finance/settlements/" + file + "/days/" + day + "/untie", Map.of());
        assertThat(untied.getStatusCode().value()).as(String.valueOf(untied.getBody())).isEqualTo(200);
        assertThat(((List<Map>) untied.getBody().get("days")).get(0).get("line_id")).isNull();
        assertThat((List<Map>) untied.getBody().get("candidates")).extracting(c -> String.valueOf(c.get("line_id"))).containsExactly(line);

        // the row Interswitch settled for a reference never confirmed: proposed to the bank credits once, by the Bursary
        String item = ((List<Map>) untied.getBody().get("items")).stream().filter(i -> "NOT_CONFIRMED".equals(i.get("state")))
                .map(i -> String.valueOf(i.get("id"))).findFirst().orElseThrow();
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/settlements/items/" + item + "/bank-credit", Map.of()).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> sent = it.call(bursar, HttpMethod.POST, "/api/v1/finance/settlements/items/" + item + "/bank-credit", Map.of());
        assertThat(sent.getStatusCode().value()).as(String.valueOf(sent.getBody())).isEqualTo(200);
        ResponseEntity<Map> twice = it.call(bursar, HttpMethod.POST, "/api/v1/finance/settlements/items/" + item + "/bank-credit", Map.of());
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody()).containsEntry("code", "SETTLEMENT_ITEM_SENT");
        assertThat(jdbc.sql("SELECT state || ':' || proposed_reference FROM finance.bank_credit WHERE id = :c").param("c", UUID.fromString(String.valueOf(sent.getBody().get("bankCredit"))))
                .query(String.class).single()).isEqualTo("PROPOSED:" + open);
    }
}
