package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * Financial analytics (V279): four students in one session — one who paid in full, one who paid in two
 * transactions (one payer), one of the College who paid, one who did not — and a transcript fee. The totals
 * distinguish transactions from unique payers; the breakdowns by category, gender and faculty agree with the
 * rows; the date window, the payment types and the dimensions filter together; a category the Bursary states
 * takes the payments its pattern matches at once; the College sees only its own, the School only postgraduates,
 * a Head of Department only their department, whatever the request names; the Academic Office reads the summary
 * but not the transactions; an office outside the readers is refused. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class FinancialAnalyticsIT {

    /** a session no other test files anything under (DefermentIT dates its students' entry 2094/2095) */
    static final String SESSION = "2081/2082";

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
        it.session(SESSION, 2081);
    }

    @Test
    void theRevenueItsPayersAndItsBreakdownsAgreeAndTheScopesHold() {
        int n = new Random().nextInt(8000) + 1000;
        String tag = "ZZFA" + n;
        it.db(() -> {
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 100000, 100, 'C00023'), (:s, 'School fees', 150000, 100, 'C00061')").param("s", SESSION).update();
            return null;
        });
        // the charge and the payments of this session are removed in the finally: another test's student must not
        // find this session as "the latest with charges" (StudentPortalService.session() falls back to it)
        try {
        UUID a = it.student(tag + "A", "C00023", "MOAUM/ADM/94/" + (100000 + n * 6), "MOAUM/MTC/94/" + n, 100);
        UUID b = it.student(tag + "B", "C00023", "MOAUM/ADM/94/" + (100000 + n * 6 + 1), "MOAUM/MTC/94/" + (n + 1), 100);
        UUID c = it.student(tag + "C", "C00061", "MOAUM/ADM/94/" + (100000 + n * 6 + 2), "MOAUM/MED/94/" + n, 100);
        UUID d = it.student(tag + "D", "C00023", "MOAUM/ADM/94/" + (100000 + n * 6 + 3), "MOAUM/MTC/94/" + (n + 3), 100);
        it.db(() -> {
            for (var e : Map.of(a, "F", b, "M", c, "F", d, "M").entrySet()) {
                jdbc.sql("UPDATE people.student SET sex = :x, entry_session = :s, current_level = 100 WHERE id = :id").param("x", e.getValue()).param("s", SESSION).param("id", e.getKey()).update();
            }
            return null;
        });
        String refA = pay(a, 100000, null), refB1 = pay(b, 60000, null), refB2 = pay(b, 40000, null), refC = pay(c, 150000, null);
        String refT = pay(a, 5000, "Transcript TRN-" + tag);
        assertThat(List.of(refA, refB1, refB2, refC, refT)).doesNotHaveDuplicates();

        // the University's figures over these students: five transactions, three payers, 355,000
        Map<String, Object> s = summary(bursar, "session=" + SESSION + "&q=" + tag);
        Map<String, Object> t = (Map<String, Object>) s.get("totals");
        assertThat(((Number) t.get("transactions")).intValue()).isEqualTo(5);
        assertThat(((Number) t.get("payers")).intValue()).isEqualTo(3);
        assertThat(((Number) t.get("revenue")).doubleValue()).isEqualTo(355000.0);
        Map<String, Object> fees = row((List<Map<String, Object>>) s.get("byCategory"), "code", "SCHOOL_FEES");
        assertThat(((Number) fees.get("amount")).doubleValue()).isEqualTo(350000.0);
        assertThat(((Number) fees.get("transactions")).intValue()).isEqualTo(4);
        assertThat(((Number) fees.get("payers")).intValue()).isEqualTo(3);
        assertThat(((Number) row((List<Map<String, Object>>) s.get("byCategory"), "code", "TRANSCRIPT").get("amount")).doubleValue()).isEqualTo(5000.0);
        // by gender: the women paid 255,000 in two payers; the man 100,000 in one payer over two transactions
        Map<String, Object> f = row((List<Map<String, Object>>) s.get("byGender"), "sex", "F"), m = row((List<Map<String, Object>>) s.get("byGender"), "sex", "M");
        assertThat(((Number) f.get("amount")).doubleValue()).isEqualTo(255000.0);
        assertThat(((Number) f.get("payers")).intValue()).isEqualTo(2);
        assertThat(((Number) m.get("amount")).doubleValue()).isEqualTo(100000.0);
        assertThat(((Number) m.get("payers")).intValue()).isEqualTo(1);
        assertThat(((Number) m.get("transactions")).intValue()).isEqualTo(2);
        // by level: everyone paid at 100 Level of the session
        assertThat(((Number) row((List<Map<String, Object>>) s.get("byLevel"), "level", 100).get("amount")).doubleValue()).isEqualTo(355000.0);
        // the trend has today's bucket with everything in it
        assertThat(((List<Map<String, Object>>) s.get("trend"))).hasSize(1);

        // the filters work together: school fees, women → 250,000 from two payers; the Faculty of Science → 205,000 from two
        Map<String, Object> fw = (Map<String, Object>) summary(bursar, "session=" + SESSION + "&q=" + tag + "&types=SCHOOL_FEES&sex=F").get("totals");
        assertThat(((Number) fw.get("revenue")).doubleValue()).isEqualTo(250000.0);
        assertThat(((Number) fw.get("payers")).intValue()).isEqualTo(2);
        String science = jdbc.sql("SELECT faculty_code FROM ref.programme WHERE code = 'C00023'").query(String.class).single();
        Map<String, Object> sc = (Map<String, Object>) summary(bursar, "session=" + SESSION + "&q=" + tag + "&fac=" + science).get("totals");
        assertThat(((Number) sc.get("revenue")).doubleValue()).isEqualTo(205000.0);
        assertThat(((Number) sc.get("payers")).intValue()).isEqualTo(2);
        // the date window: today holds everything, a day in the past nothing, and the period before is offered for comparison
        String today = java.time.LocalDate.now().toString();
        Map<String, Object> td = summary(bursar, "q=" + tag + "&from=" + today + "&to=" + today);
        assertThat(((Number) ((Map<String, Object>) td.get("totals")).get("revenue")).doubleValue()).isEqualTo(355000.0);
        assertThat(td.get("compare")).isNotNull();
        assertThat(((Number) ((Map<String, Object>) summary(bursar, "q=" + tag + "&from=2000-01-01&to=2000-01-02").get("totals")).get("revenue")).doubleValue()).isEqualTo(0.0);
        // several payment types at once
        Map<String, Object> two = (Map<String, Object>) summary(bursar, "session=" + SESSION + "&q=" + tag + "&types=SCHOOL_FEES,TRANSCRIPT").get("totals");
        assertThat(((Number) two.get("revenue")).doubleValue()).isEqualTo(355000.0);
        assertThat(((Number) ((Map<String, Object>) summary(bursar, "session=" + SESSION + "&q=" + tag + "&types=TRANSCRIPT").get("totals")).get("transactions")).intValue()).isEqualTo(1);

        // the transactions behind the figures: five rows newest first, one by reference, two for the student who paid twice
        Map<String, Object> tx = it.get(bursar, "/api/v1/analytics/finance/transactions?session=" + SESSION + "&q=" + tag).getBody();
        assertThat(((Number) tx.get("total")).intValue()).isEqualTo(5);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) tx.get("rows");
        assertThat(rows).hasSize(5);
        assertThat(rows.get(0).get("reference")).isEqualTo(refT);
        assertThat(rows).allSatisfy(r -> { assertThat(r).containsKeys("reference", "number", "surname", "sex", "faculty", "department", "programme", "level", "entry_mode", "session", "category", "amount", "confirmed_at", "status", "channel"); assertThat(r).doesNotContainKey("payment_id"); });
        // a search by reference reaches across every session, whatever the current one is
        assertThat(((Number) it.get(bursar, "/api/v1/analytics/finance/transactions?q=" + refB1).getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) it.get(bursar, "/api/v1/analytics/finance/transactions?session=" + SESSION + "&q=" + refB1).getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) it.get(bursar, "/api/v1/analytics/finance/transactions?session=" + SESSION + "&studentId=" + b).getBody().get("total")).intValue()).isEqualTo(2);

        // a category the Bursary states takes the payments its pattern matches, at once
        ResponseEntity<Map> stated = it.call(bursar, HttpMethod.PUT, "/api/v1/analytics/finance/categories/GST_" + n, Map.of("label", "GST levy " + n, "pattern", "^gst levy " + n, "ord", 65, "revenue", true, "active", true));
        assertThat(stated.getStatusCode().value()).as(String.valueOf(stated.getBody())).isEqualTo(200);
        pay(a, 2000, "GST levy " + n + " for the session");
        Map<String, Object> gst = row((List<Map<String, Object>>) summary(bursar, "session=" + SESSION + "&q=" + tag).get("byCategory"), "code", "GST_" + n);
        assertThat(((Number) gst.get("amount")).doubleValue()).isEqualTo(2000.0);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/analytics/finance/categories/bad code", Map.of("label", "x")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(ItSupport.token("academic"), HttpMethod.PUT, "/api/v1/analytics/finance/categories/GST_X" + n, Map.of("label", "x")).getStatusCode().value()).isEqualTo(403);

        // the scopes: the College sees its own only, whatever faculty is named; the School sees no undergraduate money
        Map<String, Object> chs = summary(ItSupport.token("provost"), "session=" + SESSION + "&q=" + tag);
        assertThat(((Map<String, Object>) chs.get("scope")).get("kind")).isEqualTo("COLLEGE");
        assertThat(((Number) ((Map<String, Object>) chs.get("totals")).get("revenue")).doubleValue()).isEqualTo(150000.0);
        assertThat(((Number) ((Map<String, Object>) summary(ItSupport.token("provost"), "session=" + SESSION + "&q=" + tag + "&fac=" + science).get("totals")).get("revenue")).doubleValue()).isEqualTo(0.0);
        assertThat(((Number) ((Map<String, Object>) summary(ItSupport.token("pgschool"), "session=" + SESSION + "&q=" + tag).get("totals")).get("revenue")).doubleValue()).isEqualTo(0.0);
        // the Head of Department and the Academic Office no longer read the finance figures at all (Oct 2026); a lecturer never did
        String hod = it.officer("hod", "department", "MTC");
        assertThat(it.get(hod, "/api/v1/analytics/finance/summary?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(hod, "/api/v1/analytics/finance/transactions?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("academic"), "/api/v1/analytics/finance/summary?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("academic"), "/api/v1/analytics/finance/transactions?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("lecturer"), "/api/v1/analytics/finance/summary").getStatusCode().value()).isEqualTo(403);
        // a malformed date is refused, not swallowed
        assertThat(it.get(bursar, "/api/v1/analytics/finance/summary?from=yesterday").getStatusCode().value()).isEqualTo(422);

        // the admission funnel answers for the session within the scope: the University's stages, the School's own stages
        ResponseEntity<Map> funnel = it.get(bursar, "/api/v1/analytics/admissions/funnel?session=" + SESSION);
        assertThat(funnel.getStatusCode().value()).as(String.valueOf(funnel.getBody())).isEqualTo(200);
        List<Map<String, Object>> stages = (List<Map<String, Object>>) funnel.getBody().get("stages");
        assertThat(stages).extracting(x -> x.get("key")).contains("applied", "fee_paid", "admitted", "accepted", "screening_ok", "on_register", "fees_paid", "registered", "matriculated");
        ResponseEntity<Map> pgFunnel = it.get(ItSupport.token("pgschool"), "/api/v1/analytics/admissions/funnel?session=" + SESSION);
        assertThat(((Map<String, Object>) pgFunnel.getBody().get("scope")).get("pg")).isEqualTo(true);
        assertThat(((List<Map<String, Object>>) pgFunnel.getBody().get("stages"))).extracting(x -> x.get("key")).contains("submitted", "dept_decided");
        ResponseEntity<Map> stageRows = it.get(hod, "/api/v1/analytics/admissions/funnel/rows?session=" + SESSION + "&stage=on_register");
        assertThat(stageRows.getStatusCode().value()).isEqualTo(200);
        assertThat(stageRows.getBody().get("stage")).isEqualTo("on_register");
        assertThat(it.get(ItSupport.token("lecturer"), "/api/v1/analytics/admissions/funnel").getStatusCode().value()).isEqualTo(403);
        } finally {
            // the charge first, on its own, so it never outlives the test; then this test's own payments, never another test's
            it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update());
            it.db(() -> {
                jdbc.sql("DELETE FROM finance.payment_reference WHERE session = :s AND student_id IN (SELECT id FROM people.student WHERE surname LIKE :t)")
                        .param("s", SESSION).param("t", tag + "%").update();
                jdbc.sql("UPDATE finance.payment_category SET active = false WHERE code LIKE 'GST\\_%' AND code <> 'GST'").update();
                return null;
            });
        }
    }

    private Map<String, Object> summary(String token, String query) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/analytics/finance/summary?" + query);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static Map<String, Object> row(List<Map<String, Object>> rows, String key, Object value) {
        return rows.stream().filter(r -> String.valueOf(value).equals(String.valueOf(r.get(key)))).findFirst().orElseThrow(() -> new AssertionError("no row with " + key + " = " + value + " in " + rows));
    }

    /** a payment generated on the register and confirmed by the Bursary: school fees against the charge, or any other purpose */
    private String pay(UUID student, int amount, String purpose) {
        String ref = it.db(() -> purpose == null
                ? jdbc.sql("SELECT finance.new_reference(:s, :ses, :a, 'School fees')").param("s", student).param("ses", SESSION).param("a", amount).query(String.class).single()
                : jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, :a, :p)").param("s", student).param("ses", SESSION).param("a", amount).param("p", purpose).query(String.class).single());
        ResponseEntity<Map> r = it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref + "/confirm", Map.of("channel", "bank", "note", "test"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return ref;
    }
}
