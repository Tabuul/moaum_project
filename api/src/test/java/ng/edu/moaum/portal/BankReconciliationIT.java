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
 * V557: the bank reconciliation statement of the fees collection account for a month of its own (a March of the last century no
 * earlier run took). Two payments are confirmed and posted; the collections statement shows one of them, the bank's charges and an
 * inflow no one found. Internal Audit reads the reconciliation: the payment not in the bank, the charges and the inflow are its
 * items; a student may not read it. The Bursary accounts for the charges with a journal (Internal Audit may not), prepares it with
 * the statement's closing balance, and another officer signs it — not its preparer, not Internal Audit; it is then kept as signed
 * and the period is not prepared again. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class BankReconciliationIT {

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

    /** a year of the last century whose March no reconciliation of 1010 and no journal holds */
    private int freeYear() {
        for (int i = 0; i < 200; i++) {
            int y = java.util.concurrent.ThreadLocalRandom.current().nextInt(1901, 2000);
            boolean taken = jdbc.sql("""
                    SELECT EXISTS (SELECT 1 FROM finance.bank_reconciliation WHERE account = '1010' AND period_to >= make_date(:y, 3, 1) AND period_from <= make_date(:y, 3, 31))
                        OR EXISTS (SELECT 1 FROM finance.gl_journal WHERE entry_date BETWEEN make_date(:y, 3, 1) AND make_date(:y, 3, 31))
                    """).param("y", y).query(Boolean.class).single();
            if (!taken) {
                return y;
            }
        }
        throw new IllegalStateException("no free year");
    }

    private static String kindsOf(List<Map> items, String tag) {
        return String.join(",", items.stream().filter(i -> String.valueOf(i.get("reference")).contains(tag) || String.valueOf(i.get("description")).contains(tag))
                .map(i -> i.get("kind") + ":" + new BigDecimal(String.valueOf(i.get("effect"))).intValue()).sorted().toList());
    }

    @Test
    void theCollectionsAccountIsReconciledForAMonthPreparedByTheBursaryAndSignedByAnotherOfficer() {
        int y = freeYear();
        String tag = "IT557" + y;
        String from = y + "-03-01", to = y + "-03-31";
        String audit = ItSupport.token("audit");
        String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String checker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String student = TestTokens.token(UUID.randomUUID(), List.of("student"));
        String session = "9959/9960";
        it.session(session, 9959);
        UUID s = it.student(it.freeSurname("ZZBANKREC"), "C00023", null, it.freeNumber("MOAUM/MTC/59/", 4), 100);
        String seen = "MOAUM-FEE-" + y + "57-0001", unseen = "MOAUM-FEE-" + y + "57-0002";
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
                SELECT :s, :ses, x.ref, 'School fees ' || :ses, x.amount, x.at - interval '1 day', x.at + interval '7 days', x.at, gen_random_uuid(), 'Bank transfer', 'RCT-' || x.ref, 'V557 IT'
                  FROM (VALUES (:seen, 5000, make_timestamptz(:y, 3, 10, 10, 0, 0, 'Africa/Lagos')),
                               (:unseen, 700, make_timestamptz(:y, 3, 12, 10, 0, 0, 'Africa/Lagos'))) x (ref, amount, at)
                """).param("s", s).param("ses", session).param("seen", seen).param("unseen", unseen).param("y", y).update());
        // the ledger posts what waits (the sync runs batch after batch, as the screen does)
        for (int i = 0; i < 100; i++) {
            ResponseEntity<Map> sync = it.call(maker, HttpMethod.POST, "/api/v1/finance/accounting/sync?limit=10000", Map.of());
            assertThat(sync.getStatusCode().value()).as(String.valueOf(sync.getBody())).isEqualTo(200);
            if (((Number) sync.getBody().get("remaining")).longValue() == 0) break;
        }
        ResponseEntity<Map> st = it.call(audit, HttpMethod.POST, "/api/v1/finance/collections/statements", Map.of("label", "IT V557 " + tag, "fileName", "c.csv", "rows", List.of(
                Map.of("date", from, "description", tag + " CHARGES", "debit", "25"),
                Map.of("date", y + "-03-10", "reference", seen, "description", "Transfer", "credit", "5000"),
                Map.of("date", to, "description", tag + " INFLOW", "credit", "400"))));
        assertThat(st.getStatusCode().value()).as(String.valueOf(st.getBody())).isEqualTo(200);
        UUID charges = UUID.fromString(String.valueOf(((List<Map>) st.getBody().get("lines")).get(0).get("id")));

        // Internal Audit reads it; a student may not
        String path = "/api/v1/finance/bank-reconciliation?account=1010&from=" + from + "&to=" + to + "&closing=1000";
        assertThat(it.get(student, path).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> read = it.get(audit, path);
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        List<Map> items = (List<Map>) read.getBody().get("items");
        assertThat(kindsOf(items, tag) + "|" + kindsOf(items, unseen) + "|" + kindsOf(items, seen))
                .isEqualTo("BANK_CREDIT_NOT_IN_LEDGER:-400,BANK_DEBIT_NOT_IN_LEDGER:25|RECEIPT_NOT_IN_BANK:700|");
        Map figures = (Map) read.getBody().get("figures");
        assertThat(new BigDecimal(String.valueOf(figures.get("difference"))))
                .isEqualByComparingTo(new BigDecimal(String.valueOf(figures.get("ledger_balance"))).subtract(new BigDecimal("1000")).subtract(new BigDecimal(String.valueOf(figures.get("items_effect")))));
        assertThat(figures.get("missing_days")).isEqualTo(0);

        // the Bursary accounts for the charges with a journal; Internal Audit may not
        ResponseEntity<Map> posted = it.call(maker, HttpMethod.POST, "/api/v1/finance/accounting/journals", Map.of("date", y + "-03-15", "memo", tag + " bank charges",
                "lines", List.of(Map.of("account", "5210", "debit", 25, "narration", tag), Map.of("account", "1010", "credit", 25, "narration", tag))));
        assertThat(posted.getStatusCode().value()).as(String.valueOf(posted.getBody())).isEqualTo(200);
        long journalNo = jdbc.sql("SELECT journal_no FROM finance.gl_journal WHERE id = :id").param("id", UUID.fromString(String.valueOf(posted.getBody().get("id")))).query(Long.class).single();
        String book = "/api/v1/finance/bank-reconciliation/lines/" + charges + "/journal";
        assertThat(it.call(audit, HttpMethod.POST, book, Map.of("journalNo", journalNo, "note", "charges")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> booked = it.call(maker, HttpMethod.POST, book, Map.of("journalNo", journalNo, "note", "The bank's charges for March"));
        assertThat(booked.getStatusCode().value()).as(String.valueOf(booked.getBody())).isEqualTo(200);
        ResponseEntity<Map> after = it.get(audit, path);
        assertThat(kindsOf((List<Map>) after.getBody().get("items"), tag)).isEqualTo("BANK_CREDIT_NOT_IN_LEDGER:-400");
        assertThat((List<Map>) after.getBody().get("booked")).anyMatch(b -> charges.toString().equals(String.valueOf(b.get("id"))) && Long.valueOf(journalNo).equals(((Number) b.get("journal_no")).longValue()));

        // prepared by the Bursary with the closing balance that leaves nothing unexplained; signed by another officer only
        Map f = (Map) after.getBody().get("figures");
        BigDecimal closing = new BigDecimal(String.valueOf(f.get("ledger_balance"))).subtract(new BigDecimal(String.valueOf(f.get("items_effect"))));
        Map<String, Object> prepare = Map.of("account", "1010", "from", from, "to", to, "closing", closing);
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/bank-reconciliation", prepare).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> prepared = it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation", prepare);
        assertThat(prepared.getStatusCode().value()).as(String.valueOf(prepared.getBody())).isEqualTo(200);
        Map saved = (Map) prepared.getBody().get("saved");
        assertThat(saved.get("state") + ":" + new BigDecimal(String.valueOf(saved.get("difference"))).intValue()).isEqualTo("DRAFT:0");
        String sign = "/api/v1/finance/bank-reconciliation/" + saved.get("id") + "/sign";
        assertThat(it.call(audit, HttpMethod.POST, sign, Map.of()).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> self = it.call(maker, HttpMethod.POST, sign, Map.of());
        assertThat(self.getStatusCode().value()).isEqualTo(422);
        assertThat(self.getBody()).containsEntry("code", "RECON_SAME_OFFICER");
        ResponseEntity<Map> signed = it.call(checker, HttpMethod.POST, sign, Map.of());
        assertThat(signed.getStatusCode().value()).as(String.valueOf(signed.getBody())).isEqualTo(200);
        assertThat(((Map) signed.getBody().get("saved")).get("state")).isEqualTo("SIGNED");
        assertThat(kindsOf((List<Map>) it.get(audit, path).getBody().get("items"), tag)).as("kept as signed").isEqualTo("BANK_CREDIT_NOT_IN_LEDGER:-400");
        assertThat((List<Map>) it.getList(audit, "/api/v1/finance/bank-reconciliation/saved").getBody()).anyMatch(r -> String.valueOf(saved.get("id")).equals(String.valueOf(r.get("id"))));
        ResponseEntity<Map> again = it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation", prepare);
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody()).containsEntry("code", "RECON_PERIOD_TAKEN");
    }

    /** V562: a March after every reconciliation an earlier run left (only the latest signed month of an account is reopened) */
    private int laterYear() {
        int y = jdbc.sql("""
                SELECT coalesce(max(extract(year FROM period_to))::int, 1900) + 1 FROM finance.bank_reconciliation WHERE period_to < date '2000-01-01'
                """).query(Integer.class).single();
        while (jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.gl_journal WHERE entry_date BETWEEN make_date(:y, 3, 1) AND make_date(:y, 3, 31))")
                .param("y", y).query(Boolean.class).single()) {
            y++;
        }
        assertThat(y).as("a March of the last century left for the test").isLessThan(2000);
        return y;
    }

    /**
     * V562: the transfer between the bank accounts, the charges and the interest booked in one press each; the disbursement
     * account's month signed is closed on the ledger (a journal by hand dated in it refused); reopened only on a reason asked by one
     * officer and approved by another, after which the journal is taken.
     */
    @Test
    void aSignedMonthIsClosedOnTheLedgerUntilAnotherOfficerApprovesReopeningItAndLinesAreBookedInOnePress() {
        int y = laterYear();
        String tag = "IT562" + y;
        String from = y + "-03-01", to = y + "-03-31";
        String audit = ItSupport.token("audit");
        String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String checker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        ResponseEntity<Map> cs = it.call(audit, HttpMethod.POST, "/api/v1/finance/collections/statements", Map.of("label", "IT V562 collections " + tag, "fileName", "c.csv", "rows", List.of(
                Map.of("date", from, "description", tag + " CHARGES", "debit", "40"),
                Map.of("date", y + "-03-05", "description", tag + " TRANSFER OUT", "debit", "10000"),
                Map.of("date", to, "description", tag + " INTEREST", "credit", "15"))));
        assertThat(cs.getStatusCode().value()).as(String.valueOf(cs.getBody())).isEqualTo(200);
        ResponseEntity<Map> ds = it.call(audit, HttpMethod.POST, "/api/v1/finance/refunds/bank-statements", Map.of("label", "IT V562 disbursements " + tag, "fileName", "d.csv", "rows", List.of(
                Map.of("date", from, "description", tag + " COT", "debit", "5"),
                Map.of("date", y + "-03-06", "description", tag + " TRANSFER IN", "credit", "10000"),
                Map.of("date", to, "description", tag + " SMS", "debit", "2"))));
        assertThat(ds.getStatusCode().value()).as(String.valueOf(ds.getBody())).isEqualTo(200);
        List<Map> cl = (List<Map>) cs.getBody().get("lines");
        String charges = String.valueOf(cl.get(0).get("id")), out = String.valueOf(cl.get(1).get("id")), interest = String.valueOf(cl.get(2).get("id"));
        UUID disbursements = UUID.fromString(String.valueOf(ds.getBody().get("id")));
        List<String> dl = jdbc.sql("SELECT l.id::text FROM finance.bank_statement_line l WHERE l.statement_id = :s ORDER BY l.line_no")
                .param("s", disbursements).query(String.class).list();
        String cot = dl.get(0), in = dl.get(1), sms = dl.get(2);

        // the transfer offered and booked from its two lines; the charges, the interest and the disbursement account's charges in one press
        assertThat((List<Map>) it.getList(audit, "/api/v1/finance/bank-reconciliation/transfers?from=" + from + "&to=" + to).getBody())
                .anyMatch(t -> out.equals(String.valueOf(t.get("out_line"))) && in.equals(String.valueOf(t.get("in_line"))));
        Map<String, Object> transfer = Map.of("outLine", out, "inLine", in, "note", "Funding the disbursement account");
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/bank-reconciliation/transfers", transfer).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> booked = it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation/transfers", transfer);
        assertThat(booked.getStatusCode().value()).as(String.valueOf(booked.getBody())).isEqualTo(200);
        for (String[] b : List.of(new String[] {charges, "5250"}, new String[] {interest, "4090"}, new String[] {cot, "5250"}, new String[] {sms, "5250"})) {
            ResponseEntity<Map> r = it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation/lines/" + b[0] + "/book", Map.of("account", b[1], "note", tag + " booked"));
            assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        }
        ResponseEntity<Map> bank = it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation/lines/" + charges + "/book", Map.of("account", "1010", "note", "x"));
        assertThat(bank.getStatusCode().value()).isEqualTo(422);

        // the disbursement account's March signed: closed on the ledger
        String path = "/api/v1/finance/bank-reconciliation?account=1020&from=" + from + "&to=" + to;
        Map f = (Map) it.get(audit, path).getBody().get("figures");
        BigDecimal closing = new BigDecimal(String.valueOf(f.get("ledger_balance"))).subtract(new BigDecimal(String.valueOf(f.get("items_effect"))));
        ResponseEntity<Map> prepared = it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation", Map.of("account", "1020", "from", from, "to", to, "closing", closing));
        assertThat(prepared.getStatusCode().value()).as(String.valueOf(prepared.getBody())).isEqualTo(200);
        String id = String.valueOf(((Map) prepared.getBody().get("saved")).get("id"));
        ResponseEntity<Map> signed = it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation/" + id + "/sign", Map.of());
        assertThat(signed.getStatusCode().value()).as(String.valueOf(signed.getBody())).isEqualTo(200);
        Map<String, Object> journal = Map.of("date", y + "-03-15", "memo", tag + " a charge found later",
                "lines", List.of(Map.of("account", "5250", "debit", 3, "narration", tag), Map.of("account", "1020", "credit", 3, "narration", tag)));
        ResponseEntity<Map> refused = it.call(maker, HttpMethod.POST, "/api/v1/finance/accounting/journals", journal);
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody()).containsEntry("code", "LEDGER_MONTH_CLOSED");
        assertThat((List<Map>) it.get(audit, "/api/v1/finance/bank-reconciliation/closed").getBody().get("months"))
                .anyMatch(m -> id.equals(String.valueOf(m.get("id"))) && Boolean.TRUE.equals(m.get("latest")));

        // reopened: asked by one officer on a reason, not decided by them, approved by another
        assertThat(it.call(audit, HttpMethod.POST, "/api/v1/finance/bank-reconciliation/" + id + "/reopen", Map.of("reason", "x")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> asked = it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation/" + id + "/reopen", Map.of("reason", "A charge of March was found later"));
        assertThat(asked.getStatusCode().value()).as(String.valueOf(asked.getBody())).isEqualTo(200);
        String request = ((List<Map>) asked.getBody().get("requests")).stream().filter(q -> "REQUESTED".equals(q.get("state")) && from.equals(q.get("period_from")))
                .map(q -> String.valueOf(q.get("id"))).findFirst().orElseThrow();
        ResponseEntity<Map> own = it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation/reopen/" + request + "/decide", Map.of("approve", true));
        assertThat(own.getStatusCode().value()).isEqualTo(422);
        assertThat(own.getBody()).containsEntry("code", "RECON_REOPEN_SAME_OFFICER");
        ResponseEntity<Map> approved = it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-reconciliation/reopen/" + request + "/decide", Map.of("approve", true, "note", "Agreed"));
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat(((Map) it.get(audit, path).getBody().get("saved")).get("state")).isEqualTo("DRAFT");
        assertThat(it.call(maker, HttpMethod.POST, "/api/v1/finance/accounting/journals", journal).getStatusCode().value()).as("open again").isEqualTo(200);
    }

    /** V569: the morning alerts on the bank matching, as they read now — Internal Audit reads them and cannot change them; the Bursary
     *  sets the days, a day past the 28th refused; the morning job's function answers what it found and told */
    @Test
    @SuppressWarnings({ "unchecked", "rawtypes" })
    void theBankMatchingAlertsAreReadByAuditAndSetByTheBursary() {
        String bursar = ItSupport.token("bursar");
        String audit = ItSupport.token("audit");
        String path = "/api/v1/finance/bank-reconciliation/watch";
        ResponseEntity<Map> read = it.get(audit, path);
        assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(200);
        assertThat(read.getBody()).containsKeys("setting", "overdue", "credits", "missing");
        Map<String, Object> was = (Map<String, Object>) read.getBody().get("setting");
        Map<String, Object> body = Map.of("enabled", true, "reconDay", 12, "creditHours", 48, "missingDays", 5);
        assertThat(it.call(audit, HttpMethod.PUT, path, body).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.PUT, path, Map.of("enabled", true, "reconDay", 30, "creditHours", 48, "missingDays", 5)).getStatusCode().value()).isEqualTo(400);
        try {
            ResponseEntity<Map> set = it.call(bursar, HttpMethod.PUT, path, body);
            assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
            assertThat((Map<String, Object>) set.getBody().get("setting")).containsEntry("recon_day", 12).containsEntry("credit_hours", 48).containsEntry("missing_days", 5);
            String said = it.db(() -> jdbc.sql("SELECT finance.watch_bank_matching()::text").query(String.class).single());
            assertThat(said).contains("\"told\"", "\"overdue\"", "\"credits\"", "\"missing\"");
        } finally {
            it.call(bursar, HttpMethod.PUT, path, Map.of("enabled", was.get("enabled"), "reconDay", was.get("recon_day"), "creditHours", was.get("credit_hours"),
                    "missingDays", was.get("missing_days")));
        }
    }
}
