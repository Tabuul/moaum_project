package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Duration;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.hostel.HostelClock;

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
 * The hostel follow-ups (V705): the University's own workbook — the old portal's export, a "Block" being the hostel, named by
 * its Block ID — imports with two hostels of one name kept apart by their location, "Room A1" saved as room A1, and found again
 * by its ID; a capacity is never cut below a held bed; a fee reference lasts no longer than its hold; a hold past its 48 hours
 * frees its bed for the next student at once, before the clock; money that arrives after the bed went to someone else is
 * recorded, never refused; a student who asked to be told of a free room is told once; the Dean's dashboard counts the rooms.
 * Every hostel and person is invented. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class HostelDeadlineAndWorkbookIT {

    static final String SESSION = "2107/2108";
    static final String HS = "/api/v1/hostel/sessions/2107/2108";
    // the old portal's IDs of two invented hostels of one name; their codes are ZH + the ID (HostelIT closes every ZH… hall at its start)
    static final String WEST = "ZH9701", EAST = "ZH9702";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    HostelClock clock;

    ItSupport it;
    String dsa, bursar;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2107);
        dsa = TestTokens.token(it.person("ZZHD-DSA", "ZZHDDSA"), List.of("dsa"));
        bursar = TestTokens.token(it.person("ZZHD-BURSAR", "ZZHDBURSAR"), List.of("bursar"));
        reset(false);
    }

    /** an earlier run's residue: the session's stays ended, applications withdrawn, alerts ended, fees gone; the halls open or, at the end, closed */
    void reset(boolean closeHalls) {
        it.db(() -> {
            jdbc.sql("UPDATE hostel.allocation SET ended_at = coalesce(ended_at, now()), ended_reason = coalesce(ended_reason, 'test reset'), state = CASE WHEN ended_at IS NULL AND lapsed_at IS NULL THEN 'CANCELLED' ELSE state END WHERE session = :s AND ended_at IS NULL").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.application SET state = 'WITHDRAWN', withdrawn_at = now(), withdrawn_reason = 'test reset' WHERE session = :s AND state <> 'WITHDRAWN'").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.room_watch SET ended_at = now(), ended_reason = 'test reset' WHERE session = :s AND ended_at IS NULL").param("s", SESSION).update();
            jdbc.sql("DELETE FROM hostel.fee_rule WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.room SET state = 'AVAILABLE', state_reason = NULL WHERE hall_code IN (:w, :e)").param("w", WEST).param("e", EAST).update();
            jdbc.sql("UPDATE hostel.hall SET state = :st, state_reason = CASE WHEN :st = 'ACTIVE' THEN NULL ELSE 'test reset' END, ended_on = NULL WHERE code IN (:w, :e)")
                    .param("st", closeHalls ? "CLOSED" : "ACTIVE").param("w", WEST).param("e", EAST).update();
            return null;
        });
    }

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    private UUID student(String surname) {
        UUID id = it.student(surname, "C00023", it.freeNumber("MOAUM/ADM/07/", 6), it.freeNumber("MOAUM/HD/07/", 4), 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET sex = 'F', current_level = 100, entry_session = :ses WHERE id = :id").param("ses", SESSION).param("id", id).update();
            return jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08011115555', :e, now()) ON CONFLICT (student_id) DO NOTHING").param("s", id).param("e", surname.toLowerCase() + "@example.com").update();
        });
        return id;
    }

    /** school fees paid and course registration in: eligible */
    private UUID ready(String prefix) {
        UUID s = student(it.freeSurname(prefix));
        String t = TestTokens.token(s, List.of("student"));
        ResponseEntity<Map> ref = it.call(t, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", SESSION, "amount", 120000));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", String.valueOf(ref.getBody().get("reference"))).query(String.class).single());
        it.db(() -> jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (gen_random_uuid(), :s, :ses, 1, 100, 'APPROVED', now()) ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED', approved_at = now()").param("s", s).param("ses", SESSION).update());
        return s;
    }

    private String tok(UUID s) {
        return TestTokens.token(s, List.of("student"));
    }

    private UUID roomId(String hall, String roomNo) {
        return jdbc.sql("SELECT id FROM hostel.room WHERE hall_code = :h AND room_no = :r").param("h", hall).param("r", roomNo).query(UUID.class).single();
    }

    private Map<String, Object> board(String hall, String roomNo) {
        return jdbc.sql("SELECT * FROM hostel.room_board(:s) WHERE hall_code = :h AND room_no = :r").param("s", SESSION).param("h", hall).param("r", roomNo).query().singleRow();
    }

    private UUID live(UUID student) {
        return jdbc.sql("SELECT id FROM hostel.allocation WHERE student_id = :s AND session = :ses AND lapsed_at IS NULL AND ended_at IS NULL").param("s", student).param("ses", SESSION).query(UUID.class).single();
    }

    private long notices(UUID student, String subject) {
        return jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject = :t AND channel = 'EMAIL'").param("s", student).param("t", subject).query(Long.class).single();
    }

    private long events(UUID allocation, String action) {
        return jdbc.sql("SELECT count(*) FROM hostel.event WHERE allocation_id = :a AND action = :x").param("a", allocation).param("x", action).query(Long.class).single();
    }

    @Test
    void theWorkbookImportsAsItStandsTheDeadlineHoldsAndLateMoneyIsRecorded() {
      try {
        // ── 1 · the old portal's workbook as the screen sends it: the hostel by its Block ID, its gender from the Hostel Blocks sheet ──
        List<Map<String, Object>> rows = List.of(
                Map.of("hall", "Zhiva Hostel", "hall_ref", "9701", "location", "Western Wing", "room", "Room A1", "capacity", "1", "hall_sex", "Female"),
                Map.of("hall", "Zhiva Hostel", "hall_ref", "9701", "location", "Western Wing", "room", "Room A2", "capacity", "2", "hall_sex", "Female"),
                Map.of("hall", "Zhiva Hostel", "hall_ref", "9702", "location", "Eastern Wing(2nd Camp)", "room", "Room A1", "capacity", "1", "hall_sex", "Female"),
                Map.of("hall", "Zhiva Hostel", "hall_ref", "9702", "location", "Eastern Wing(2nd Camp)", "room", "S1", "capacity", "2", "hall_sex", "Female", "category", "Special"));
        ResponseEntity<Map> preview = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/import/preview", Map.of("rows", rows));
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        List<Map<String, Object>> pr = l(preview.getBody().get("rows"));
        assertThat(pr).extracting(r -> r.get("hall_code")).containsExactly(WEST, WEST, EAST, EAST);
        assertThat(pr).extracting(r -> r.get("room_no")).containsExactly("A1", "A2", "A1", "S1");
        assertThat(pr.get(2).get("hall_name")).isEqualTo("Zhiva Hostel, Eastern Wing (2nd Camp)");
        assertThat(pr).extracting(r -> r.get("outcome")).allMatch(o -> "NEW".equals(o) || "EXISTING".equals(o) || "UPDATED".equals(o));
        assertThat(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/import", Map.of("rows", rows)).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> again = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/import", Map.of("rows", rows)).getBody();
        assertThat(((Number) m(again.get("counts")).get("EXISTING")).intValue()).isEqualTo(4);
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.hall WHERE legacy_ref IN ('9701', '9702') AND sex = 'F' AND location IS NOT NULL").query(Long.class).single()).isEqualTo(2L);
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.room WHERE hall_code IN (:w, :e)").param("w", WEST).param("e", EAST).query(Long.class).single()).isEqualTo(4L);
        // a later workbook that renames the hostel finds it by its ID, and its room as "A1" or "Room A1"
        Map<String, Object> renamed = l(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/import/preview",
                Map.of("rows", List.of(Map.of("hall", "Zhiva Hall (renamed)", "hall_ref", "9701", "room", "A1", "capacity", "1")))).getBody().get("rows")).get(0);
        assertThat(renamed.get("hall_code")).isEqualTo(WEST);
        assertThat(renamed.get("outcome")).isEqualTo("EXISTING");

        // ── 2 · the window, first come; the Bursar's school fees line; closing on the Lagos day it is today ──
        Map<String, Object> window = new HashMap<>(Map.of("fee", 50000, "holdHours", 48, "allocationMethod", "FIRST_COME", "requiresReview", false, "waitlist", true,
                "state", "OPEN", "semester", 1, "requireRegistration", true, "requireSchoolFees", true, "eligibleStatuses", List.of("ACTIVE", "ADMITTED")));
        window.put("applicationsClose", LocalDate.now(ZoneId.of("Africa/Lagos")).toString());
        ResponseEntity<Map> win = it.call(dsa, HttpMethod.PUT, HS + "/window", window);
        assertThat(win.getStatusCode().value()).as(String.valueOf(win.getBody())).isEqualTo(200);
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 120000, 100, 'C00023')").param("s", SESSION).update());
        // the room the import made special is the Dean's; the other room of the west hostel is under repair
        assertThat(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/close?session=" + SESSION, Map.of("kind", "ROOM", "id", roomId(WEST, "A2").toString(), "state", "MAINTENANCE", "reason", "Repainting")).getStatusCode().value()).isEqualTo(200);

        // ── 3 · a capacity is never cut below a held bed ──
        UUID bed2 = jdbc.sql("SELECT b.id FROM hostel.bed b WHERE b.room_id = :r AND b.number = 2").param("r", roomId(EAST, "S1")).query(UUID.class).single();
        ResponseEntity<Map> guest = it.call(dsa, HttpMethod.POST, HS + "/allocate-special", Map.of("bedId", bed2, "occupantName", "Invented Guest Zhiva", "reason", "Visiting examiner"));
        assertThat(guest.getStatusCode().value()).as(String.valueOf(guest.getBody())).isEqualTo(200);
        Map<String, Object> cut = l(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/import/preview",
                Map.of("rows", List.of(Map.of("hall", "Zhiva Hostel", "hall_ref", "9702", "room", "S1", "capacity", "1", "category", "Special")))).getBody().get("rows")).get(0);
        assertThat(cut.get("outcome")).isEqualTo("ERROR");
        assertThat(String.valueOf(cut.get("message"))).contains("Bed 2 is held or occupied");
        assertThatThrownBy(() -> it.db(() -> jdbc.sql("UPDATE hostel.room SET beds = 1 WHERE id = :r").param("r", roomId(EAST, "S1")).update()))
                .hasMessageContaining("HOSTEL_CAPACITY_BELOW_OCCUPANCY");
        assertThat(board(EAST, "S1").get("capacity")).isEqualTo(2);

        // ── 4 · the fee reference lasts no longer than the hold ──
        UUID a = ready("ZZHDA");
        ResponseEntity<Map> ra = it.call(tok(a), HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId(WEST, "A1")));
        assertThat(ra.getStatusCode().value()).as(String.valueOf(ra.getBody())).isEqualTo(200);
        UUID allocA = live(a);
        it.db(() -> jdbc.sql("UPDATE hostel.allocation SET held_until = now() + interval '2 hours' WHERE id = :i").param("i", allocA).update());
        ResponseEntity<Map> refA = it.call(tok(a), HttpMethod.POST, "/api/v1/me/hostel/fee-reference", Map.of("session", SESSION));
        assertThat(refA.getStatusCode().value()).as(String.valueOf(refA.getBody())).isEqualTo(200);
        String referenceA = String.valueOf(refA.getBody().get("reference"));
        Map<String, Object> times = jdbc.sql("SELECT pr.expires_at, al.held_until FROM finance.payment_reference pr JOIN hostel.allocation al ON al.reference = pr.reference WHERE pr.reference = :r")
                .param("r", referenceA).query().singleRow();
        assertThat(times.get("expires_at")).isEqualTo(times.get("held_until"));
        assertThat(board(WEST, "A1").get("status")).isEqualTo("FULL");

        // ── 5 · past its deadline the hold frees the bed at once: the next student reserves it before the clock turns ──
        it.db(() -> jdbc.sql("UPDATE hostel.allocation SET held_until = now() - interval '1 minute' WHERE id = :i").param("i", allocA).update());
        assertThat(board(WEST, "A1").get("available")).isEqualTo(1);
        UUID b = ready("ZZHDB");
        assertThat(l(it.get(tok(b), "/api/v1/me/hostel/rooms?session=" + SESSION).getBody().get("rooms"))).extracting(r -> String.valueOf(r.get("room_id"))).contains(roomId(WEST, "A1").toString());
        ResponseEntity<Map> rb = it.call(tok(b), HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId(WEST, "A1")));
        assertThat(rb.getStatusCode().value()).as(String.valueOf(rb.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT state FROM hostel.allocation WHERE id = :i").param("i", allocA).query(String.class).single()).isEqualTo("LAPSED");
        assertThat(events(allocA, "RESERVATION_EXPIRED")).isEqualTo(1L);
        clock.tick();
        assertThat(events(allocA, "RESERVATION_EXPIRED")).isEqualTo(1L);
        assertThat(notices(a, "Your hostel reservation has expired")).isEqualTo(1L);

        // ── 6 · A's money arrives after the bed went to B: confirmed as money, the stay stays expired, everyone told ──
        String outcome = it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK', 'teller for the test')").param("r", referenceA).query(String.class).single());
        assertThat(outcome).isEqualTo("confirmed");
        assertThat(jdbc.sql("SELECT confirmed_at IS NOT NULL FROM finance.payment_reference WHERE reference = :r").param("r", referenceA).query(Boolean.class).single()).isTrue();
        Map<String, Object> alA = jdbc.sql("SELECT state, fee_status FROM hostel.allocation WHERE id = :i").param("i", allocA).query().singleRow();
        assertThat(alA.get("state")).isEqualTo("LAPSED");
        assertThat(alA.get("fee_status")).isNotEqualTo("PAID");
        assertThat(events(allocA, "PAYMENT_AFTER_EXPIRY")).isEqualTo(1L);
        assertThat(notices(a, "Your hostel payment arrived after your reservation expired")).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT state FROM hostel.allocation WHERE student_id = :s AND session = :ses AND ended_at IS NULL AND lapsed_at IS NULL").param("s", b).param("ses", SESSION).query(String.class).single()).isEqualTo("HELD");

        // ── 7 · "notify me when a room becomes available": told once, when a bed of the hostel asked for is free ──
        UUID d = ready("ZZHDD");
        assertThat(it.call(tok(d), HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId(EAST, "A1"))).getStatusCode().value()).isEqualTo(200);
        UUID allocD = live(d);
        UUID c = ready("ZZHDC");
        assertThat(it.call(tok(c), HttpMethod.POST, "/api/v1/me/hostel/watch", Map.of("session", SESSION, "hall", WEST)).getStatusCode().value()).isEqualTo(200);
        // a student with a bed sets no alert
        assertThat(it.call(tok(b), HttpMethod.POST, "/api/v1/me/hostel/watch", Map.of("session", SESSION)).getBody().get("code")).isEqualTo("HOSTEL_ALREADY_HELD");
        // a second alert replaces the first; it is cancelled, then set again for the east hostel
        assertThat(it.call(tok(c), HttpMethod.POST, "/api/v1/me/hostel/watch/cancel", Map.of("session", SESSION)).getBody().get("cancelled")).isEqualTo(1);
        assertThat(it.call(tok(c), HttpMethod.POST, "/api/v1/me/hostel/watch", Map.of("session", SESSION, "hall", EAST)).getStatusCode().value()).isEqualTo(200);
        assertThat(m(it.get(tok(c), "/api/v1/me/hostel/rooms?session=" + SESSION).getBody().get("watch")).get("hall_code")).isEqualTo(EAST);
        clock.tick();
        assertThat(notices(c, "A hostel room is available")).isZero();
        it.db(() -> jdbc.sql("UPDATE hostel.allocation SET held_until = now() - interval '1 minute' WHERE id = :i").param("i", allocD).update());
        clock.tick();
        clock.tick();
        assertThat(notices(c, "A hostel room is available")).isEqualTo(1L);
        Map<String, Object> watch = m(it.get(tok(c), "/api/v1/me/hostel/rooms?session=" + SESSION).getBody().get("watch"));
        assertThat(watch.get("told_at")).isNotNull();
        assertThat(watch.get("told_room_no")).isEqualTo("A1");
        assertThat(it.call(tok(c), HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId(EAST, "A1"))).getStatusCode().value()).isEqualTo(200);

        // ── 8 · the Dean's dashboard counts the rooms: full, special, reservations awaiting payment ──
        ResponseEntity<Map> dash = it.get(dsa, HS + "/dashboard");
        assertThat(dash.getStatusCode().value()).isEqualTo(200);
        Map<String, Object> rooms = m(new tools.jackson.databind.ObjectMapper().readValue(String.valueOf(dash.getBody().get("rooms")), Map.class));
        assertThat(((Number) rooms.get("full")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) rooms.get("maintenance")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) rooms.get("pending_reservations")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(l(rooms.get("byCategory")).stream().filter(x -> "SPECIAL".equals(x.get("category"))).findFirst().orElseThrow().get("rooms")).isNotEqualTo(0);
        // the reservation the student sees carries its deadline, 48 hours out
        OffsetDateTime held = jdbc.sql("SELECT held_until FROM hostel.allocation WHERE id = :i").param("i", live(c)).query(OffsetDateTime.class).single();
        assertThat(Duration.between(OffsetDateTime.now(), held).toMinutes()).isBetween(47 * 60L, 49 * 60L);
      } finally {
        reset(true);
      }
    }
}
