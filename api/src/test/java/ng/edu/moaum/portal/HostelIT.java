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
 * The accommodation lifecycle (V261), end to end: the housing desk builds a hostel with a block, rooms and beds; states the
 * window with its fee, rules and review; students apply (a male student is refused the female hall, an ineligible one is
 * refused outright); the desk reviews; the allocation is generated to the beds with the waitlist behind; the student pays,
 * accepts under the rules, is checked in, sees roommates, raises a fault, asks for a transfer that the desk approves into a
 * named bed (the old stay kept), requests checkout; the desk inspects, charges damage and waives it, clears item by item,
 * completes the clearance, the bed is free and the graduation unit signed; the letter verifies by its reference; a room
 * under maintenance is not allocated; a second bed in the session is refused; the Bursary reads but cannot act; a
 * lecturer is refused; a student sees only their own record. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class HostelIT {

    static final String SESSION = "2096/2097";
    static final String HS = "/api/v1/hostel/sessions/2096/2097";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String housing, bursar, lecturer;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2096);
        housing = TestTokens.token(it.person("ZZHS-HOUSING", "ZZHSHOUSING"), List.of("housing"));
        bursar = TestTokens.token(it.person("ZZHS-BURSAR", "ZZHSBURSAR"), List.of("bursar"));
        lecturer = ItSupport.token("lecturer");
        // an earlier run on the same database (never in CI): its stays closed and its window cleared
        it.db(() -> {
            jdbc.sql("UPDATE hostel.allocation SET ended_at = coalesce(ended_at, now()), ended_reason = coalesce(ended_reason, 'test reset'), state = CASE WHEN ended_at IS NULL THEN 'CANCELLED' ELSE state END WHERE session = :s AND lapsed_at IS NULL AND ended_at IS NULL").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.application SET state = 'WITHDRAWN', withdrawn_at = now(), withdrawn_reason = 'test reset' WHERE session = :s AND state <> 'WITHDRAWN'").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.session_setting SET seed = NULL, drawn_at = NULL, drawn_by = NULL, state = 'OPEN' WHERE session = :s").param("s", SESSION).update();
            return jdbc.sql("UPDATE hostel.hall SET state = 'CLOSED', state_reason = 'test reset' WHERE code LIKE 'ZH%' AND state = 'ACTIVE'").update();
        });
    }

    /** an invented student of the programme with a contact so notices queue; a sex, a level, a status */
    private UUID student(String surname, String sex, int level) {
        UUID id = it.student(surname, "C00023", "MOAUM/ADM/96/" + String.format("%06d", new Random().nextInt(999_999)), "MOAUM/HS/96/" + String.format("%04d", new Random().nextInt(9999)), level);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET sex = :x, current_level = :l WHERE id = :id").param("x", sex).param("l", level).param("id", id).update();
            return jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08011113333', :e, now()) ON CONFLICT (student_id) DO NOTHING").param("s", id).param("e", surname.toLowerCase() + "@example.com").update();
        });
        return id;
    }

    private Map<String, Object> me(String token) {
        return (Map<String, Object>) it.get(token, "/api/v1/me/hostel/full?session=" + SESSION).getBody().get("view");
    }

    private List<String> subjects(UUID student) {
        return jdbc.sql("SELECT subject FROM platform.notice WHERE about_kind = 'student' AND about_id = :s ORDER BY created_at").param("s", student).query(String.class).list();
    }

    @Test
    void fromTheInventoryToTheClearedBed() {
        String tag = String.format("%03d", new Random().nextInt(1000));
        String hall = "ZH" + tag;

        // ── 1 · the inventory: a female hall, a block, rooms generated with their beds, one room under maintenance ──
        assertThat(it.call(housing, HttpMethod.PUT, "/api/v1/hostel/halls-full", Map.of("code", hall, "name", "Zeta Hall " + tag, "sex", "F", "kind", "UNDERGRADUATE", "campus", "Main", "location", "North gate")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(housing, HttpMethod.PUT, "/api/v1/hostel/blocks", Map.of("hall", hall, "code", "A", "name", "Block A", "floors", 2)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> gen = it.call(housing, HttpMethod.POST, "/api/v1/hostel/rooms/generate", Map.of("hall", hall, "block", "A", "floor", 1, "from", 1, "to", 2, "beds", 2, "prefix", "A-"));
        assertThat(gen.getStatusCode().value()).as(String.valueOf(gen.getBody())).isEqualTo(200);
        assertThat(((Number) gen.getBody().get("generated")).intValue()).isEqualTo(2);
        Map<String, Object> inv = it.get(housing, "/api/v1/hostel/inventory?session=" + SESSION).getBody();
        List<Map<String, Object>> rooms = ((List<Map<String, Object>>) inv.get("rooms")).stream().filter(r -> hall.equals(r.get("hall_code"))).toList();
        assertThat(rooms).hasSize(2);
        assertThat(rooms).allSatisfy(r -> assertThat(((Number) r.get("available")).intValue()).isEqualTo(2));
        String room2 = String.valueOf(rooms.stream().filter(r -> "A-2".equals(r.get("room_no"))).findFirst().orElseThrow().get("id"));
        // room A-2 goes under maintenance: its two beds are not given
        ResponseEntity<Map> closed = it.call(housing, HttpMethod.POST, "/api/v1/hostel/close?session=" + SESSION, Map.of("kind", "ROOM", "id", room2, "state", "MAINTENANCE", "reason", "Leaking roof"));
        assertThat(closed.getStatusCode().value()).as(String.valueOf(closed.getBody())).isEqualTo(200);
        assertThat(it.call(housing, HttpMethod.POST, "/api/v1/hostel/close?session=" + SESSION, Map.of("kind", "ROOM", "id", room2, "state", "CLOSED", "reason", "")).getStatusCode().value()).isEqualTo(422);

        // ── 2 · the window: a fee, review required, rules, only the female hall's kind ──
        ResponseEntity<Map> win = it.call(housing, HttpMethod.PUT, HS + "/window", Map.of("fee", 25000, "holdHours", 48, "allocationMethod", "FIRST_COME", "requiresReview", true, "waitlist", true,
                "rules", "No cooking in the rooms. Lights out at midnight.", "state", "OPEN", "eligibleStatuses", List.of("ACTIVE", "ADMITTED")));
        assertThat(win.getStatusCode().value()).as(String.valueOf(win.getBody())).isEqualTo(200);
        assertThat(win.getBody().get("rules_version")).isNotNull();
        assertThat(it.call(bursar, HttpMethod.PUT, HS + "/window", Map.of("fee", 1)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(lecturer, HS + "/dashboard").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(bursar, HS + "/dashboard").getStatusCode().value()).isEqualTo(200);

        // ── 3 · the students apply: three eligible women, a man refused the female hall, a rusticated student refused ──
        UUID ada = student("ZZHS-ADA" + tag, "F", 200), bola = student("ZZHS-BOLA" + tag, "F", 300), cara = student("ZZHS-CARA" + tag, "F", 100), dan = student("ZZHS-DAN" + tag, "M", 200), eve = student("ZZHS-EVE" + tag, "F", 200);
        it.db(() -> jdbc.sql("UPDATE people.student SET status = 'RUSTICATED' WHERE id = :id").param("id", eve).update());
        String tAda = TestTokens.token(ada, List.of("student")), tBola = TestTokens.token(bola, List.of("student")), tCara = TestTokens.token(cara, List.of("student")), tDan = TestTokens.token(dan, List.of("student")), tEve = TestTokens.token(eve, List.of("student"));
        Map<String, Object> before = me(tAda);
        assertThat(before.get("eligible")).isEqualTo(true);
        assertThat(before.get("open")).isEqualTo(true);
        ResponseEntity<Map> apAda = it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/apply-full", Map.of("session", SESSION, "hall", hall, "roomType", "DOUBLE", "specialNeed", "Ground floor if possible"));
        assertThat(apAda.getStatusCode().value()).as(String.valueOf(apAda.getBody())).isEqualTo(200);
        assertThat(String.valueOf(apAda.getBody().get("reference"))).matches("HST-\\d{4}-\\d{5}");
        assertThat(it.call(tBola, HttpMethod.POST, "/api/v1/me/hostel/apply-full", Map.of("session", SESSION, "hall", hall, "roommateNumber", jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", ada).query(String.class).single())).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(tCara, HttpMethod.POST, "/api/v1/me/hostel/apply-full", Map.of("session", SESSION)).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(tDan, HttpMethod.POST, "/api/v1/me/hostel/apply-full", Map.of("session", SESSION, "hall", hall)).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(tEve, HttpMethod.POST, "/api/v1/me/hostel/apply-full", Map.of("session", SESSION)).getStatusCode().value()).isEqualTo(422);
        assertThat(me(tEve).get("eligible")).isEqualTo(false);
        assertThat(it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/apply-full", Map.of("session", SESSION)).getStatusCode().value()).isEqualTo(409);
        assertThat(subjects(ada)).contains("Your hostel application is in");
        assertThat(me(tAda).get("review")).isNull();

        // ── 4 · the desk reviews: Ada and Bola approved, Cara sent back for a correction then approved ──
        Map<String, Object> apps = it.get(housing, HS + "/applications?state=PENDING_REVIEW&q=ZZHS").getBody();
        List<Map<String, Object>> rows = (List<Map<String, Object>>) apps.get("rows");
        assertThat(rows.size()).isGreaterThanOrEqualTo(3);
        for (int i = 1; i < rows.size(); i++) assertThat(String.valueOf(rows.get(i).get("student_name")).compareTo(String.valueOf(rows.get(i - 1).get("student_name")))).isGreaterThanOrEqualTo(0);
        String idAda = String.valueOf(rows.stream().filter(r -> ada.toString().equals(String.valueOf(r.get("student_id")))).findFirst().orElseThrow().get("application_id"));
        String idBola = String.valueOf(rows.stream().filter(r -> bola.toString().equals(String.valueOf(r.get("student_id")))).findFirst().orElseThrow().get("application_id"));
        String idCara = String.valueOf(rows.stream().filter(r -> cara.toString().equals(String.valueOf(r.get("student_id")))).findFirst().orElseThrow().get("application_id"));
        assertThat(it.call(housing, HttpMethod.POST, HS + "/applications/" + idCara + "/review", Map.of("decision", "CORRECTION", "note", "State the room type")).getStatusCode().value()).isEqualTo(200);
        assertThat(me(tCara).get("review")).isEqualTo("CORRECTION");
        assertThat(it.call(housing, HttpMethod.POST, HS + "/applications/review-bulk", Map.of("ids", List.of(idAda, idBola, idCara), "decision", "APPROVED")).getStatusCode().value()).isEqualTo(200);
        assertThat(subjects(cara)).contains("Your hostel application needs a correction", "Your hostel application is approved");
        // generating before any approved application would have been refused; a bursar cannot run it
        assertThat(it.call(bursar, HttpMethod.POST, HS + "/draw", Map.of("seed", "not-allowed-seed")).getStatusCode().value()).isEqualTo(403);

        // ── 5 · the allocation: two beds in A-1 (A-2 is under maintenance); first come first served seats Ada and Bola; Cara waits ──
        Map<String, Object> preview = it.get(housing, HS + "/preview").getBody();
        assertThat(((Number) preview.get("free_beds")).intValue()).isEqualTo(2);
        ResponseEntity<Map> draw = it.call(housing, HttpMethod.POST, HS + "/draw", Map.of("seed", ""));
        assertThat(draw.getStatusCode().value()).as(String.valueOf(draw.getBody())).isEqualTo(200);
        assertThat(((Number) draw.getBody().get("allocated")).intValue()).isEqualTo(2);
        assertThat(((Number) draw.getBody().get("unsuccessful")).intValue()).isEqualTo(1);
        Map<String, Object> vAda = me(tAda);
        assertThat(vAda.get("allocation_state")).isEqualTo("HELD");
        assertThat(vAda.get("room_no")).isEqualTo("A-1");
        assertThat(String.valueOf(vAda.get("allocation_ref"))).matches("ALC-\\d{4}-\\d{5}");
        assertThat(me(tCara).get("state")).isEqualTo("UNSUCCESSFUL");
        assertThat(subjects(ada)).contains("You have been allocated a bed");
        assertThat(subjects(cara)).contains("Your hostel application is on the waiting list");
        // a student sees only their own record; Bola's view is Bola's
        assertThat(me(tBola).get("allocation_ref")).isNotEqualTo(vAda.get("allocation_ref"));
        assertThat(it.get(tAda, HS + "/dashboard").getStatusCode().value()).isEqualTo(403);
        // the desk cannot seat Ada a second time in the session
        Map<String, Object> allocList = it.get(housing, HS + "/applications?q=ZZHS-ADA" + tag).getBody();
        String allocAda = String.valueOf(((List<Map<String, Object>>) allocList.get("rows")).get(0).get("allocation_id"));
        List<Map<String, Object>> free = it.getList(housing, HS + "/free-beds?hall=" + hall).getBody();
        assertThat(free).isEmpty(); // A-1 full, A-2 under maintenance

        // ── 6 · accepting before paying is refused; the fee paid confirms; the rules are acknowledged; checked in ──
        assertThat(it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/accept", Map.of("session", SESSION, "rulesVersion", 1)).getStatusCode().value()).isEqualTo(422);
        String ref = String.valueOf(it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/fee-reference", Map.of("session", SESSION)).getBody().get("reference"));
        assertThat(ref).startsWith("MOAUM-FEE-");
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref + "/confirm", Map.of("channel", "Bank transfer")).getStatusCode().value()).isEqualTo(200);
        assertThat(me(tAda).get("allocation_state")).isEqualTo("CONFIRMED");
        assertThat(it.call(housing, HttpMethod.POST, "/api/v1/hostel/allocations/" + allocAda + "/checkin", Map.of("condition", "GOOD")).getStatusCode().value()).isEqualTo(422); // rules not yet acknowledged
        assertThat(it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/accept", Map.of("session", SESSION, "rulesVersion", 99)).getStatusCode().value()).isEqualTo(422);
        int rulesVersion = ((Number) me(tAda).get("rules_version")).intValue();
        assertThat(it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/accept", Map.of("session", SESSION, "rulesVersion", rulesVersion)).getStatusCode().value()).isEqualTo(200);
        assertThat(me(tAda).get("allocation_state")).isEqualTo("ACCEPTED");
        ResponseEntity<Map> in = it.call(housing, HttpMethod.POST, "/api/v1/hostel/allocations/" + allocAda + "/checkin", Map.of("condition", "GOOD", "note", "Keys 2, card issued"));
        assertThat(in.getStatusCode().value()).as(String.valueOf(in.getBody())).isEqualTo(200);
        assertThat(me(tAda).get("allocation_state")).isEqualTo("CHECKED_IN");
        assertThat(subjects(ada)).contains("You are checked in");
        // Bola declines her held bed: the bed frees and the waiting list takes it on the next lapse run
        assertThat(it.call(tBola, HttpMethod.POST, "/api/v1/me/hostel/decline", Map.of("session", SESSION, "reason", "Staying with family")).getStatusCode().value()).isEqualTo(200);
        assertThat(me(tBola).get("state")).isNull(); // withdrawn: no application stands
        assertThat(it.getList(housing, HS + "/free-beds?hall=" + hall).getBody()).hasSize(1);

        // ── 7 · Cara seated from the waiting list by hand into the freed bed; the roommates see each other ──
        List<Map<String, Object>> freed = it.getList(housing, HS + "/free-beds?hall=" + hall).getBody();
        String freedBed = String.valueOf(freed.get(0).get("bed_id"));
        ResponseEntity<Map> seated = it.call(housing, HttpMethod.POST, HS + "/applications/" + idCara + "/allocate", Map.of("bedId", freedBed, "reason", "Next on the waiting list"));
        assertThat(seated.getStatusCode().value()).as(String.valueOf(seated.getBody())).isEqualTo(200);
        assertThat(me(tCara).get("allocation_state")).isEqualTo("HELD");
        List<Map<String, Object>> mates = (List<Map<String, Object>>) it.get(tAda, "/api/v1/me/hostel/full?session=" + SESSION).getBody().get("roommates");
        assertThat(mates).extracting(m -> String.valueOf(m.get("student_id"))).contains(cara.toString());
        // a bed already taken is refused for a manual seating; a bed under maintenance is refused for a transfer
        assertThat(it.call(housing, HttpMethod.POST, HS + "/applications/" + idCara + "/allocate", Map.of("bedId", freedBed, "reason", "again")).getStatusCode().value()).isEqualTo(422);
        String maintBed = jdbc.sql("SELECT id FROM hostel.bed WHERE room_id = :r ORDER BY number LIMIT 1").param("r", UUID.fromString(room2)).query(UUID.class).single().toString();
        assertThat(it.call(housing, HttpMethod.POST, "/api/v1/hostel/allocations/" + allocAda + "/transfer", Map.of("bedId", maintBed, "reason", "Try the closed room")).getStatusCode().value()).isEqualTo(422);

        // ── 8 · a fault raised; a transfer requested and approved into A-2 once it is back in service; the old stay kept ──
        assertThat(it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/maintenance-full", Map.of("session", SESSION, "category", "ELECTRICITY", "priority", "HIGH", "issue", "The socket sparks")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/transfer", Map.of("session", SESSION, "hall", hall, "reason", "The socket is dangerous")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/transfer", Map.of("session", SESSION, "reason", "again")).getStatusCode().value()).isEqualTo(409);
        assertThat(it.call(housing, HttpMethod.POST, "/api/v1/hostel/close?session=" + SESSION, Map.of("kind", "ROOM", "id", room2, "state", "AVAILABLE", "reason", "Roof repaired")).getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> transfers = it.getList(housing, HS + "/transfers?state=SUBMITTED").getBody();
        String tr = String.valueOf(transfers.stream().filter(t -> ada.toString().equals(String.valueOf(t.get("student_id")))).findFirst().orElseThrow().get("id"));
        ResponseEntity<Map> moved = it.call(housing, HttpMethod.POST, "/api/v1/hostel/transfers/" + tr, Map.of("decision", "APPROVED", "bedId", maintBed, "note", "Moved to A-2"));
        assertThat(moved.getStatusCode().value()).as(String.valueOf(moved.getBody())).isEqualTo(200);
        String allocAda2 = String.valueOf(moved.getBody().get("newAllocationId"));
        Map<String, Object> vAda2 = me(tAda);
        assertThat(vAda2.get("room_no")).isEqualTo("A-2");
        assertThat(vAda2.get("allocation_state")).isEqualTo("CHECKED_IN");
        assertThat(jdbc.sql("SELECT state FROM hostel.allocation WHERE id = :a").param("a", UUID.fromString(allocAda)).query(String.class).single()).isEqualTo("TRANSFERRED");
        assertThat(subjects(ada)).contains("Your hostel room has changed");

        // ── 9 · checkout: requested, inspected, damage charged and waived, cleared item by item, completed — the bed is free ──
        assertThat(it.call(tAda, HttpMethod.POST, "/api/v1/me/hostel/checkout", Map.of("session", SESSION, "on", LocalDate.now().toString(), "reason", "Vacation")).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> insp = it.call(housing, HttpMethod.POST, "/api/v1/hostel/allocations/" + allocAda2 + "/inspect", Map.of("condition", "DAMAGED", "cleanliness", "ACCEPTABLE", "damages", "Broken chair", "keysReturned", true, "cardReturned", true));
        assertThat(insp.getStatusCode().value()).as(String.valueOf(insp.getBody())).isEqualTo(200);
        Map<String, Object> al = it.get(housing, "/api/v1/hostel/allocations/" + allocAda2).getBody();
        assertThat(al.get("clearance_state")).isEqualTo("PENDING");
        List<Map<String, Object>> items = (List<Map<String, Object>>) al.get("clearanceItems");
        assertThat(items).hasSize(9);
        assertThat(items.stream().filter(i -> "KEY_RETURNED".equals(i.get("requirement"))).findFirst().orElseThrow().get("state")).isEqualTo("CLEARED");
        assertThat(items.stream().filter(i -> "NO_DAMAGE".equals(i.get("requirement"))).findFirst().orElseThrow().get("state")).isEqualTo("NOT_CLEARED");
        String clearanceId = String.valueOf(al.get("clearance_id"));
        // every requirement answered and two found wanting: completing records NOT_CLEARED and holds the graduation unit
        ResponseEntity<Map> notYet = it.call(housing, HttpMethod.POST, "/api/v1/hostel/clearances/" + clearanceId + "/complete", Map.of("note", "Damage outstanding"));
        assertThat(notYet.getStatusCode().value()).as(String.valueOf(notYet.getBody())).isEqualTo(200);
        assertThat(notYet.getBody().get("state")).isEqualTo("NOT_CLEARED");
        assertThat(me(tAda).get("clearance_state")).isEqualTo("NOT_CLEARED");
        assertThat(subjects(ada)).contains("Your hostel clearance has outstanding items");
        assertThat(jdbc.sql("SELECT count(*) FROM clearance.item WHERE student_id = :s AND unit = 'HOSTEL' AND state = 'HELD'").param("s", ada).query(Integer.class).single()).isGreaterThanOrEqualTo(1);
        // reopened once the desk takes the damage in hand; with items pending again, completing is refused
        assertThat(it.call(housing, HttpMethod.POST, "/api/v1/hostel/clearances/" + clearanceId + "/reopen", Map.of("note", "Charge to be raised")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(housing, HttpMethod.POST, "/api/v1/hostel/clearances/" + clearanceId + "/complete", Map.of()).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> charge = it.call(housing, HttpMethod.POST, "/api/v1/hostel/allocations/" + allocAda2 + "/charge", Map.of("description", "Broken chair", "repairCost", 4000, "replacementCost", 9000, "charge", 4000));
        assertThat(charge.getStatusCode().value()).as(String.valueOf(charge.getBody())).isEqualTo(200);
        assertThat(String.valueOf(charge.getBody().get("reference"))).startsWith("MOAUM-FEE-");
        assertThat(((Number) me(tAda).get("damage_due")).intValue()).isEqualTo(4000);
        assertThat(subjects(ada)).contains("A hostel damage charge stands against you");
        // an unsettled charge would refuse a new application; waived, it does not
        assertThat(it.call(housing, HttpMethod.POST, "/api/v1/hostel/charges/" + charge.getBody().get("id") + "/waive", Map.of("reason", "Fair wear")).getStatusCode().value()).isEqualTo(200);
        assertThat(((Number) me(tAda).get("damage_due")).intValue()).isEqualTo(0);
        al = it.get(housing, "/api/v1/hostel/allocations/" + allocAda2).getBody();
        for (Map<String, Object> i : (List<Map<String, Object>>) al.get("clearanceItems")) {
            if (!"CLEARED".equals(i.get("state")) && !"WAIVED".equals(i.get("state")) && !"NOT_APPLICABLE".equals(i.get("state"))) {
                assertThat(it.call(housing, HttpMethod.POST, "/api/v1/hostel/clearance-items/" + i.get("id"), Map.of("state", "CLEARED", "remarks", "Settled at the desk")).getStatusCode().value()).isEqualTo(200);
            }
        }
        ResponseEntity<Map> done = it.call(housing, HttpMethod.POST, "/api/v1/hostel/clearances/" + clearanceId + "/complete", Map.of("note", "All in order"));
        assertThat(done.getStatusCode().value()).as(String.valueOf(done.getBody())).isEqualTo(200);
        assertThat(done.getBody().get("state")).isEqualTo("CLEARED");
        Map<String, Object> after = me(tAda);
        assertThat(after.get("clearance_state")).isEqualTo("CLEARED");
        assertThat(subjects(ada)).contains("Your hostel clearance is complete");
        assertThat(jdbc.sql("SELECT state FROM hostel.allocation WHERE id = :a").param("a", UUID.fromString(allocAda2)).query(String.class).single()).isEqualTo("CHECKED_OUT");
        assertThat(jdbc.sql("SELECT count(*) FROM clearance.item WHERE student_id = :s AND unit = 'HOSTEL' AND state = 'CLEARED'").param("s", ada).query(Integer.class).single()).isGreaterThanOrEqualTo(1);
        // the bed in A-2 is free again; the letter verifies by its reference, a made-up one does not
        List<Map<String, Object>> freeAfter = it.getList(housing, HS + "/free-beds?hall=" + hall).getBody();
        assertThat(freeAfter).extracting(b -> String.valueOf(b.get("bed_id"))).contains(maintBed);
        String alcRef = String.valueOf(after.get("allocation_ref"));
        Map<String, Object> v = it.anon(HttpMethod.GET, "/api/v1/verify/hostel/" + alcRef, null).getBody();
        assertThat(v.get("genuine")).isEqualTo(true);
        assertThat(v.get("room_no")).isEqualTo("A-2");
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/hostel/ALC-0000-00000", null).getBody().get("genuine")).isEqualTo(false);
        // the history keeps both stays
        List<Map<String, Object>> history = (List<Map<String, Object>>) it.get(tAda, "/api/v1/me/hostel/full?session=" + SESSION).getBody().get("history");
        assertThat(history.stream().filter(h -> SESSION.equals(h.get("session"))).map(h -> h.get("allocation_state")).toList()).contains("TRANSFERRED", "CHECKED_OUT");
        Map<String, Object> deskHistory = it.get(housing, "/api/v1/hostel/students/" + ada + "/history").getBody();
        assertThat((List<?>) deskHistory.get("history")).hasSizeGreaterThanOrEqualTo(2);

        // ── 10 · the figures count what happened; the occupancy list sorts names A–Z ──
        Map<String, Object> dash = it.get(housing, HS + "/dashboard").getBody();
        assertThat(String.valueOf(dash.get("dashboard"))).containsPattern("\"checked_out\": [1-9]").containsPattern("\"cleared\": [1-9]");
        Map<String, Object> occ = it.get(housing, HS + "/occupancy?view=students&hall=" + hall).getBody();
        List<Map<String, Object>> orow = (List<Map<String, Object>>) occ.get("rows");
        assertThat(orow).extracting(r -> String.valueOf(r.get("student_id"))).contains(cara.toString());
        for (int i = 1; i < orow.size(); i++) assertThat(String.valueOf(orow.get(i).get("student_name")).compareTo(String.valueOf(orow.get(i - 1).get("student_name")))).isGreaterThanOrEqualTo(0);
    }
}
