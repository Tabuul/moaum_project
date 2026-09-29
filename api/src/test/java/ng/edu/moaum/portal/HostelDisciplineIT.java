package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
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
 * Hostel discipline and swaps (V291): two students swap beds only when both agree and the Dean approves, and both beds move
 * at once with the fee each paid; an incident is reported, answered, sanctioned with a fine that bars the next bed until the
 * Bursary confirms it; loss of accommodation gives a student checked in notice to vacate and bars them; the appeal quashes it
 * and the notice is withdrawn; an incident is dismissed with its reason; the housing desk reports but does not sanction; a
 * student sees their own record and not the witnesses. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class HostelDisciplineIT {

    static final String SESSION = "2107/2108";
    static final String HS = "/api/v1/hostel/sessions/2107/2108";
    static final String HALL = "ZHDS";   // ZH…: HostelIT closes every such hall at its start

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String dsa, housing;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2107);
        dsa = TestTokens.token(it.person("ZZHD-DSA", "ZZHDDSA"), List.of("dsa"));
        housing = TestTokens.token(it.person("ZZHD-HOUSING", "ZZHDHOUSING"), List.of("housing"));
        reset(false);
    }

    void reset(boolean closeHall) {
        it.db(() -> {
            jdbc.sql("UPDATE hostel.swap_request SET state = 'CANCELLED' WHERE session = :s AND state IN ('PROPOSED', 'AGREED')").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.allocation SET ended_at = coalesce(ended_at, now()), ended_reason = coalesce(ended_reason, 'test reset'), state = CASE WHEN ended_at IS NULL AND lapsed_at IS NULL THEN 'CANCELLED' ELSE state END WHERE session = :s AND ended_at IS NULL").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.application SET state = 'WITHDRAWN', withdrawn_at = now(), withdrawn_reason = 'test reset' WHERE session = :s AND state <> 'WITHDRAWN'").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.room SET state = 'AVAILABLE', state_reason = NULL, category = 'GENERAL' WHERE hall_code = :h").param("h", HALL).update();
            jdbc.sql("UPDATE hostel.hall SET state = :st, state_reason = CASE WHEN :st = 'ACTIVE' THEN NULL ELSE 'test reset' END, ended_on = NULL WHERE code = :h").param("st", closeHall ? "CLOSED" : "ACTIVE").param("h", HALL).update();
            return null;
        });
    }

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    /** an invented female student with a contact, so notices queue */
    private UUID student(String surname) {
        int n = new Random().nextInt(999_999);
        UUID id = it.student(surname, "C00023", "MOAUM/ADM/07/" + String.format("%06d", n), "MOAUM/HU/07/" + String.format("%04d", n % 10000), 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET sex = 'F', current_level = 100 WHERE id = :id").param("id", id).update();
            return jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08011115555', :e, now()) ON CONFLICT (student_id) DO NOTHING").param("s", id).param("e", surname.toLowerCase() + "@example.com").update();
        });
        return id;
    }

    private String number(UUID s) {
        return jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", s).query(String.class).single();
    }

    private UUID roomId(String roomNo) {
        return jdbc.sql("SELECT id FROM hostel.room WHERE hall_code = :h AND room_no = :r").param("h", HALL).param("r", roomNo).query(UUID.class).single();
    }

    private Map<String, Object> live(UUID s) {
        return jdbc.sql("SELECT a.id, a.state, a.fee_status, a.fee_amount, a.checkout_on, r.room_no FROM hostel.allocation a JOIN hostel.room r ON r.id = a.room_id WHERE a.student_id = :s AND a.session = :ses AND a.ended_at IS NULL AND a.lapsed_at IS NULL")
                .param("s", s).param("ses", SESSION).query().singleRow();
    }

    /** reserved in the room, paid through the Bursary, and checked in when asked */
    private UUID housed(String surname, String roomNo, boolean checkIn) {
        UUID s = student(surname + new Random().nextInt(9000));
        String t = TestTokens.token(s, List.of("student"));
        ResponseEntity<Map> r = it.call(t, HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId(roomNo)));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        ResponseEntity<Map> ref = it.call(t, HttpMethod.POST, "/api/v1/me/hostel/fee-reference", Map.of("session", SESSION));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", String.valueOf(ref.getBody().get("reference"))).query(String.class).single());
        if (checkIn) {
            assertThat(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/allocations/" + live(s).get("id") + "/checkin", Map.of("note", "Keys handed over", "condition", "GOOD")).getStatusCode().value()).isEqualTo(200);
        }
        return s;
    }

    @Test
    void swapsNeedBothStudentsAndTheDeanAndSanctionsActAndAreAppealed() {
      try {
        List<Map<String, Object>> rows = List.of(
                Map.of("hall_code", HALL, "hall", "ZHDS Test Hall", "block", "A", "room", "101", "capacity", "2", "gender", "F"),
                Map.of("hall_code", HALL, "hall", "ZHDS Test Hall", "block", "A", "room", "102", "capacity", "2", "gender", "F"),
                Map.of("hall_code", HALL, "hall", "ZHDS Test Hall", "block", "A", "room", "103", "capacity", "2", "gender", "F"));
        assertThat(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/import", Map.of("rows", rows)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> win = it.call(dsa, HttpMethod.PUT, HS + "/window", Map.of("fee", 40000, "holdHours", 48, "allocationMethod", "FIRST_COME", "requiresReview", false, "waitlist", false,
                "state", "OPEN", "requireRegistration", false, "requireSchoolFees", false, "refuseHostelDebt", true, "eligibleStatuses", List.of("ACTIVE", "ADMITTED")));
        assertThat(win.getStatusCode().value()).as(String.valueOf(win.getBody())).isEqualTo(200);

        UUID a = housed("ZZHDA", "101", true), b = housed("ZZHDB", "102", true), c = housed("ZZHDC", "101", false);
        String ta = TestTokens.token(a, List.of("student")), tb = TestTokens.token(b, List.of("student")), tc = TestTokens.token(c, List.of("student"));

        // ── 1 · the swap: A proposes to B; the Dean may not approve until B agrees; approved, both beds move with the fee each paid ──
        ResponseEntity<Map> same = it.call(tc, HttpMethod.POST, "/api/v1/me/hostel/swaps", Map.of("session", SESSION, "partnerNumber", number(a), "reason", "Same room"));
        assertThat(same.getStatusCode().value()).isEqualTo(422);
        assertThat(same.getBody().get("code")).isEqualTo("HOSTEL_SWAP");
        ResponseEntity<Map> proposed = it.call(ta, HttpMethod.POST, "/api/v1/me/hostel/swaps", Map.of("session", SESSION, "partnerNumber", number(b), "reason", "Nearer my course mates"));
        assertThat(proposed.getStatusCode().value()).as(String.valueOf(proposed.getBody())).isEqualTo(200);
        String swap = String.valueOf(proposed.getBody().get("id"));
        assertThat(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/swaps/" + swap + "/decide", Map.of("decision", "APPROVED")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(ta, HttpMethod.POST, "/api/v1/me/hostel/swaps/" + swap + "/answer", Map.of("agree", true)).getStatusCode().value()).isIn(404, 409);
        List<Map<String, Object>> bSwaps = l(it.get(tb, "/api/v1/me/hostel/conduct?session=" + SESSION).getBody().get("swaps"));
        assertThat(bSwaps).hasSize(1);
        assertThat(bSwaps.get(0).get("role")).isEqualTo("PARTNER");
        assertThat(it.call(tb, HttpMethod.POST, "/api/v1/me/hostel/swaps/" + swap + "/answer", Map.of("agree", true, "note", "Happy to")).getBody().get("state")).isEqualTo("AGREED");
        assertThat(it.call(ta, HttpMethod.POST, "/api/v1/hostel/swaps/" + swap + "/decide", Map.of("decision", "APPROVED")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> approved = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/swaps/" + swap + "/decide", Map.of("decision", "APPROVED", "note", "Both agree"));
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat(approved.getBody().get("state")).isEqualTo("COMPLETED");
        assertThat(live(a).get("room_no")).isEqualTo("102");
        assertThat(live(b).get("room_no")).isEqualTo("101");
        assertThat(live(a).get("state")).isEqualTo("CHECKED_IN");
        assertThat(live(a).get("fee_status")).isEqualTo("PAID");
        assertThat(it.get(dsa, HS + "/discipline").getStatusCode().value()).isEqualTo(200);
        assertThat(jdbc.sql("SELECT state FROM hostel.swaps(:s) WHERE id = :i").param("s", SESSION).param("i", UUID.fromString(swap)).query(String.class).single()).isEqualTo("COMPLETED");

        // ── 2 · an incident against C: the housing desk reports it but may not sanction; C answers; the Dean fines; the fine bars the next bed until paid ──
        ResponseEntity<Map> inc = it.call(housing, HttpMethod.POST, HS + "/incidents", Map.of("studentNumber", number(c), "kind", "NOISE", "occurredAt", LocalDate.now().minusDays(1) + "T23:40",
                "place", "Room 101", "description", "Loud music after midnight", "witnesses", "The porter on duty"));
        assertThat(inc.getStatusCode().value()).as(String.valueOf(inc.getBody())).isEqualTo(200);
        String incident = String.valueOf(inc.getBody().get("id"));
        assertThat(it.call(housing, HttpMethod.POST, "/api/v1/hostel/incidents/" + incident + "/sanction", Map.of("kind", "WARNING", "reason", "x")).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> cConduct = it.get(tc, "/api/v1/me/hostel/conduct?session=" + SESSION).getBody();
        assertThat(l(cConduct.get("incidents"))).hasSize(1);
        assertThat(l(cConduct.get("incidents")).get(0)).doesNotContainKey("witnesses");
        assertThat(it.call(tc, HttpMethod.POST, "/api/v1/me/hostel/incidents/" + incident + "/answer", Map.of("statement", "A birthday; I apologise")).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> fine = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/incidents/" + incident + "/sanction", Map.of("kind", "FINE", "amount", 5000, "reason", "Second noise complaint"));
        assertThat(fine.getStatusCode().value()).as(String.valueOf(fine.getBody())).isEqualTo(200);
        assertThat(fine.getBody().get("payment_ref")).isNotNull();
        assertThat(jdbc.sql("SELECT why FROM hostel.eligibility(:s, :ses)").param("s", c).param("ses", SESSION).query(String.class).single()).contains("unpaid hostel fine");
        ResponseEntity<Map> pay = it.call(tc, HttpMethod.POST, "/api/v1/me/hostel/sanctions/" + fine.getBody().get("id") + "/pay", Map.of());
        assertThat(pay.getStatusCode().value()).as(String.valueOf(pay.getBody())).isEqualTo(200);
        assertThat(it.call(ta, HttpMethod.POST, "/api/v1/me/hostel/sanctions/" + fine.getBody().get("id") + "/pay", Map.of()).getStatusCode().value()).isEqualTo(404);
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", String.valueOf(pay.getBody().get("reference"))).query(String.class).single());
        assertThat(jdbc.sql("SELECT settled_at IS NOT NULL FROM hostel.sanction WHERE id = :i").param("i", UUID.fromString(String.valueOf(fine.getBody().get("id")))).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT ok FROM hostel.eligibility(:s, :ses)").param("s", c).param("ses", SESSION).query(Boolean.class).single()).isTrue();

        // ── 3 · loss of accommodation: A, checked in, is given notice to vacate and barred; A appeals once; the Dean quashes; the notice is withdrawn ──
        String incA = String.valueOf(it.call(dsa, HttpMethod.POST, HS + "/incidents", Map.of("studentNumber", number(a), "kind", "FIGHTING", "description", "Fight in the common room")).getBody().get("id"));
        ResponseEntity<Map> evict = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/incidents/" + incA + "/sanction", Map.of("kind", "EVICTION", "vacateBy", LocalDate.now().plusDays(3).toString(), "reason", "Assault on a resident"));
        assertThat(evict.getStatusCode().value()).as(String.valueOf(evict.getBody())).isEqualTo(200);
        assertThat(String.valueOf(live(a).get("checkout_on"))).isEqualTo(LocalDate.now().plusDays(3).toString());
        assertThat(String.valueOf(it.get(ta, "/api/v1/me/hostel/conduct?session=" + SESSION).getBody().get("bar"))).startsWith("Barred from hostel accommodation until");
        String evictId = String.valueOf(evict.getBody().get("id"));
        assertThat(it.call(ta, HttpMethod.POST, "/api/v1/me/hostel/sanctions/" + evictId + "/appeal", Map.of("ground", "I was defending myself")).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> again = it.call(ta, HttpMethod.POST, "/api/v1/me/hostel/sanctions/" + evictId + "/appeal", Map.of("ground", "again"));
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody().get("code")).isEqualTo("HOSTEL_APPEAL");
        ResponseEntity<Map> quashed = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/sanctions/" + evictId + "/appeal-decision", Map.of("decision", "QUASHED", "note", "Provocation confirmed"));
        assertThat(quashed.getStatusCode().value()).as(String.valueOf(quashed.getBody())).isEqualTo(200);
        assertThat(quashed.getBody().get("state")).isEqualTo("QUASHED");
        assertThat(live(a).get("checkout_on")).isNull();
        assertThat(it.get(ta, "/api/v1/me/hostel/conduct?session=" + SESSION).getBody().get("bar")).isNull();

        // ── 4 · a dismissal carries its reason; the register holds every incident with its sanctions ──
        String incB = String.valueOf(it.call(housing, HttpMethod.POST, HS + "/incidents", Map.of("studentNumber", number(b), "kind", "COOKING", "description", "Hot plate in room")).getBody().get("id"));
        assertThat(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/incidents/" + incB + "/dismiss", Map.of("note", " ")).getStatusCode().value()).isIn(400, 422);
        assertThat(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/incidents/" + incB + "/dismiss", Map.of("note", "An electric kettle, which is allowed")).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> reg = it.get(dsa, HS + "/discipline").getBody();
        List<Map<String, Object>> incidents = l(reg.get("incidents"));
        assertThat((List<?>) incidents.stream().filter(i -> incident.equals(String.valueOf(i.get("incident_id")))).findFirst().orElseThrow().get("sanctions")).hasSize(1);
        assertThat(incidents.stream().filter(i -> incB.equals(String.valueOf(i.get("incident_id")))).findFirst().orElseThrow().get("state")).isEqualTo("DISMISSED");
        assertThat(((Number) m(reg.get("counts")).get("dismissed")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(it.get(tc, HS + "/discipline").getStatusCode().value()).isEqualTo(403);
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.event WHERE action IN ('SWAPPED_IN', 'SANCTION_IMPOSED', 'APPEAL_QUASHED', 'INCIDENT_DISMISSED', 'FINE_PAID') AND student_id IN (:a, :b, :c)")
                .param("a", a).param("b", b).param("c", c).query(Long.class).single()).isGreaterThanOrEqualTo(6L);
      } finally {
        reset(true);
      }
    }
}
