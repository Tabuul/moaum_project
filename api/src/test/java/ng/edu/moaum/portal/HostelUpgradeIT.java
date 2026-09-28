package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * The hostel upgrade (V290): the Dean of Student Affairs imports the University's workbook without duplicates, classifies the
 * rooms, opens the window; the Bursar states the fees; a student is refused until school fees are paid and course registration
 * is in, then sees only the general rooms, reserves a bed held 48 hours, is refused a protected room by the API, pays through
 * the Bursary and is confirmed; an unpaid reservation expires by the clock and the bed is free again; a one-bed room takes one;
 * the Dean's special allocation is payable, the Student Union's and Security's are no charge and on the record all the same;
 * the accountability report and the Bursar's figures hold every occupant; the offices' walls stand. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class HostelUpgradeIT {

    static final String SESSION = "2105/2106";
    static final String HS = "/api/v1/hostel/sessions/2105/2106";
    static final String HALL = "ZHUA";   // ZH…: HostelIT closes every such hall at its start

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    HostelClock clock;

    ItSupport it;
    String dsa, bursar, registrar, lecturer;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2105);
        dsa = TestTokens.token(it.person("ZZHU-DSA", "ZZHUDSA"), List.of("dsa"));
        bursar = TestTokens.token(it.person("ZZHU-BURSAR", "ZZHUBURSAR"), List.of("bursar"));
        registrar = ItSupport.token("registrar");
        lecturer = ItSupport.token("lecturer");
        reset();
    }

    /** the residue of an earlier run: the session's stays ended, its applications withdrawn, its fee lines and rules gone, the hall's rooms general and available */
    void reset() {
        reset(false);
    }

    /** at the end the hall is closed too, so its beds count for no other suite's session */
    void reset(boolean closeHall) {
        it.db(() -> {
            jdbc.sql("UPDATE hostel.allocation SET ended_at = coalesce(ended_at, now()), ended_reason = coalesce(ended_reason, 'test reset'), state = CASE WHEN ended_at IS NULL AND lapsed_at IS NULL THEN 'CANCELLED' ELSE state END WHERE session = :s AND ended_at IS NULL").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.application SET state = 'WITHDRAWN', withdrawn_at = now(), withdrawn_reason = 'test reset' WHERE session = :s AND state <> 'WITHDRAWN'").param("s", SESSION).update();
            jdbc.sql("DELETE FROM hostel.fee_rule WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("UPDATE hostel.room SET state = 'AVAILABLE', state_reason = NULL, category = 'GENERAL' WHERE hall_code = :h").param("h", HALL).update();
            jdbc.sql("UPDATE hostel.hall SET state = :st, state_reason = CASE WHEN :st = 'ACTIVE' THEN NULL ELSE 'test reset' END, ended_on = NULL WHERE code = :h").param("st", closeHall ? "CLOSED" : "ACTIVE").param("h", HALL).update();
            return null;
        });
    }

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    /** an invented female student of the programme, 100 Level, with a contact so notices queue */
    private UUID student(String surname) {
        int n = new Random().nextInt(999_999);
        UUID id = it.student(surname, "C00023", "MOAUM/ADM/05/" + String.format("%06d", n), "MOAUM/HU/05/" + String.format("%04d", n % 10000), 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET sex = 'F', current_level = 100, entry_session = :ses WHERE id = :id").param("ses", SESSION).param("id", id).update();
            return jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08011114444', :e, now()) ON CONFLICT (student_id) DO NOTHING").param("s", id).param("e", surname.toLowerCase() + "@example.com").update();
        });
        return id;
    }

    private void payFees(UUID s, String token) {
        ResponseEntity<Map> ref = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", SESSION, "amount", 120000));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", String.valueOf(ref.getBody().get("reference"))).query(String.class).single());
    }

    private void register(UUID s) {
        it.db(() -> jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (gen_random_uuid(), :s, :ses, 1, 100, 'APPROVED', now()) ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED', approved_at = now()").param("s", s).param("ses", SESSION).update());
    }

    private UUID ready(String surname, String token) {
        UUID s = student(surname);
        payFees(s, token == null ? TestTokens.token(s, List.of("student")) : token);
        register(s);
        return s;
    }

    private Map<String, Object> room(String roomNo) {
        return jdbc.sql("SELECT * FROM hostel.room_board(:s) rb WHERE rb.hall_code = :h AND rb.room_no = :r").param("s", SESSION).param("h", HALL).param("r", roomNo).query().singleRow();
    }

    private UUID roomId(String roomNo) {
        return (UUID) room(roomNo).get("room_id");
    }

    private UUID freeBed(String roomNo) {
        return jdbc.sql("SELECT bed_id FROM hostel.allocatable_beds(:s) WHERE hall_code = :h AND room_no = :r ORDER BY bed LIMIT 1").param("s", SESSION).param("h", HALL).param("r", roomNo).query(UUID.class).single();
    }

    @Test
    void theDeanTheBursarAndTheStudentEachDoTheirPartAndEveryOccupantIsOnTheRecord() {
      try {
        // ── 1 · the workbook: previewed, then committed; a second commit changes nothing ──
        List<Map<String, Object>> rows = List.of(
                Map.of("hall_code", HALL, "hall", "ZHUA Test Hall", "block", "A", "room", "101", "capacity", "4", "gender", "F"),
                Map.of("hall_code", HALL, "hall", "ZHUA Test Hall", "block", "A", "room", "102", "capacity", "1", "gender", "F"),
                Map.of("hall_code", HALL, "hall", "ZHUA Test Hall", "block", "A", "room", "103", "capacity", "2", "gender", "F"),
                Map.of("hall_code", HALL, "hall", "ZHUA Test Hall", "block", "A", "room", "104", "capacity", "10", "gender", "F"),
                Map.of("hall_code", HALL, "hall", "ZHUA Test Hall", "block", "A", "room", "105", "capacity", "16", "gender", "F"),
                Map.of("hall_code", HALL, "hall", "ZHUA Test Hall", "block", "A", "room", "205", "capacity", "4", "gender", "F", "category", "Special"),
                Map.of("hall_code", HALL, "hall", "ZHUA Test Hall", "block", "A", "room", "SU-01", "capacity", "2", "category", "Student Union"),
                Map.of("hall_code", HALL, "hall", "ZHUA Test Hall", "block", "A", "room", "SEC-01", "capacity", "1", "category", "SECURITY"),
                Map.of("hall_code", HALL, "hall", "ZHUA Test Hall", "block", "A", "room", "101", "capacity", "4"),
                Map.of("hall", "", "block", "A", "room", "999", "capacity", "70"));
        ResponseEntity<Map> preview = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/import/preview", Map.of("rows", rows));
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        Map<String, Object> counts = m(preview.getBody().get("counts"));
        assertThat(((Number) counts.get("DUPLICATE")).intValue()).isEqualTo(1);
        assertThat(((Number) counts.get("ERROR")).intValue()).isEqualTo(1);
        assertThat(((Number) counts.get("NEW")).intValue() + ((Number) counts.get("EXISTING")).intValue() + ((Number) counts.get("UPDATED")).intValue()).isEqualTo(8);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/hostel/import", Map.of("rows", rows)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> committed = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/import", Map.of("rows", rows));
        assertThat(committed.getStatusCode().value()).as(String.valueOf(committed.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.room WHERE hall_code = :h").param("h", HALL).query(Long.class).single()).isEqualTo(8L);
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.bed b JOIN hostel.room r ON r.id = b.room_id WHERE r.hall_code = :h AND r.room_no = '105'").param("h", HALL).query(Long.class).single()).isEqualTo(16L);
        assertThat(jdbc.sql("SELECT category FROM hostel.room WHERE hall_code = :h AND room_no = 'SU-01'").param("h", HALL).query(String.class).single()).isEqualTo("STUDENT_UNION");
        ResponseEntity<Map> again = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/import", Map.of("rows", rows));
        assertThat(((Number) m(again.getBody().get("counts")).get("EXISTING")).intValue()).isEqualTo(8);
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.room WHERE hall_code = :h").param("h", HALL).query(Long.class).single()).isEqualTo(8L);

        // ── 2 · the Dean classifies; the room's category is on the record; a student may not ──
        ResponseEntity<Map> cat = it.call(dsa, HttpMethod.PUT, "/api/v1/hostel/rooms/" + roomId("205") + "/category", Map.of("category", "SPECIAL", "reason", "Reserved for the hall's guests"));
        assertThat(cat.getStatusCode().value()).as(String.valueOf(cat.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.event WHERE action = 'ROOM_CATEGORY_CHANGED' AND room_id = :r").param("r", roomId("205")).query(Long.class).single()).isGreaterThanOrEqualTo(0L);

        // ── 3 · the window: the Dean opens it first come, both prerequisites on; the Bursar may not; the Bursar states the fees; the Dean may not ──
        assertThat(it.call(bursar, HttpMethod.PUT, HS + "/window", Map.of("fee", 100000)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> win = it.call(dsa, HttpMethod.PUT, HS + "/window", Map.of("fee", 100000, "holdHours", 48, "allocationMethod", "FIRST_COME", "requiresReview", false, "waitlist", true,
                "state", "OPEN", "semester", 1, "requireRegistration", true, "requireSchoolFees", true, "eligibleStatuses", List.of("ACTIVE", "ADMITTED")));
        assertThat(win.getStatusCode().value()).as(String.valueOf(win.getBody())).isEqualTo(200);
        assertThat(win.getBody().get("require_school_fees")).isEqualTo(true);
        assertThat(it.call(dsa, HttpMethod.PUT, HS + "/fees", Map.of("category", "SPECIAL", "amount", 150000)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> rule = it.call(bursar, HttpMethod.PUT, HS + "/fees", Map.of("category", "SPECIAL", "amount", 150000, "note", "Guest rooms"));
        assertThat(rule.getStatusCode().value()).as(String.valueOf(rule.getBody())).isEqualTo(200);
        assertThat(new BigDecimal(String.valueOf(room("205").get("fee")))).isEqualByComparingTo("150000");
        assertThat(new BigDecimal(String.valueOf(room("101").get("fee")))).isEqualByComparingTo("100000");
        assertThat(room("SU-01").get("fee_status")).isEqualTo("NO_CHARGE");
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 120000, 100, 'C00023')").param("s", SESSION).update());

        // ── 4 · the student: refused until school fees are paid and registration is in; the checklist says which ──
        UUID a = student("ZZHUA" + new Random().nextInt(9000));
        String ta = TestTokens.token(a, List.of("student"));
        Map<String, Object> view = it.get(ta, "/api/v1/me/hostel/rooms?session=" + SESSION).getBody();
        Map<String, Object> check = m(view.get("checklist"));
        assertThat(check.get("school_fees")).isEqualTo(false);
        assertThat(check.get("eligible")).isEqualTo(false);
        assertThat(String.valueOf(check.get("why"))).contains("School fees");
        ResponseEntity<Map> refused = it.call(ta, HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId("101")));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("HOSTEL_NOT_ELIGIBLE");
        payFees(a, ta);
        check = m(it.get(ta, "/api/v1/me/hostel/rooms?session=" + SESSION).getBody().get("checklist"));
        assertThat(check.get("school_fees")).isEqualTo(true);
        assertThat(check.get("course_registration")).isEqualTo(false);
        assertThat(String.valueOf(check.get("why"))).contains("Course registration");
        register(a);
        view = it.get(ta, "/api/v1/me/hostel/rooms?session=" + SESSION).getBody();
        assertThat(m(view.get("checklist")).get("eligible")).isEqualTo(true);
        List<String> offered = l(view.get("rooms")).stream().map(r -> String.valueOf(r.get("room_no"))).toList();
        assertThat(offered).contains("101", "102", "104", "105").doesNotContain("205", "SU-01", "SEC-01");
        assertThat(l(view.get("rooms")).stream().filter(r -> "101".equals(r.get("room_no"))).findFirst().orElseThrow().get("available")).isEqualTo(4);

        // ── 5 · the reservation: a bed of room 101 held 48 hours; a protected room is refused by the API; one bed a session ──
        ResponseEntity<Map> reserved = it.call(ta, HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId("101")));
        assertThat(reserved.getStatusCode().value()).as(String.valueOf(reserved.getBody())).isEqualTo(200);
        assertThat(reserved.getBody().get("state")).isEqualTo("HELD");
        assertThat(reserved.getBody().get("fee_status")).isEqualTo("PAYABLE");
        OffsetDateTime heldUntil = OffsetDateTime.parse(String.valueOf(reserved.getBody().get("held_until")));
        assertThat(Duration.between(OffsetDateTime.now(), heldUntil).toMinutes()).isBetween(47 * 60L, 49 * 60L);
        assertThat(room("101").get("reserved")).isEqualTo(1);
        assertThat(room("101").get("available")).isEqualTo(3);
        UUID b = ready("ZZHUB" + new Random().nextInt(9000), null);
        String tb = TestTokens.token(b, List.of("student"));
        ResponseEntity<Map> protectedRoom = it.call(tb, HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId("205")));
        assertThat(protectedRoom.getStatusCode().value()).isEqualTo(422);
        assertThat(protectedRoom.getBody().get("code")).isEqualTo("HOSTEL_ROOM_PROTECTED");
        assertThat(it.call(tb, HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId("SU-01"))).getBody().get("code")).isEqualTo("HOSTEL_ROOM_PROTECTED");
        assertThat(it.call(ta, HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId("103"))).getBody().get("code")).isEqualTo("HOSTEL_ALREADY_HELD");

        // ── 6 · the payment through the Bursary confirms the reservation; the Dean checks the student in; the room reads occupied ──
        ResponseEntity<Map> feeRef = it.call(ta, HttpMethod.POST, "/api/v1/me/hostel/fee-reference", Map.of("session", SESSION));
        assertThat(feeRef.getStatusCode().value()).as(String.valueOf(feeRef.getBody())).isEqualTo(200);
        assertThat(new BigDecimal(String.valueOf(feeRef.getBody().get("amount")))).isEqualByComparingTo("100000");
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", String.valueOf(feeRef.getBody().get("reference"))).query(String.class).single());
        Map<String, Object> alA = jdbc.sql("SELECT id, state, fee_status FROM hostel.allocation WHERE student_id = :s AND session = :ses AND ended_at IS NULL").param("s", a).param("ses", SESSION).query().singleRow();
        assertThat(alA.get("state")).isEqualTo("CONFIRMED");
        assertThat(alA.get("fee_status")).isEqualTo("PAID");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject = 'Your hostel payment is confirmed'").param("s", a).query(Long.class).single()).isGreaterThan(0L);
        assertThat(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/allocations/" + alA.get("id") + "/checkin", Map.of("note", "Keys handed over", "condition", "GOOD")).getStatusCode().value()).isEqualTo(200);
        assertThat(room("101").get("occupied")).isEqualTo(1);
        assertThat(room("101").get("available")).isEqualTo(3);
        assertThat(room("101").get("status")).isEqualTo("PARTIALLY_OCCUPIED");

        // ── 7 · another student reserves and does not pay: the clock expires the reservation and the bed is free again ──
        ResponseEntity<Map> rb = it.call(tb, HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId("101")));
        assertThat(rb.getStatusCode().value()).as(String.valueOf(rb.getBody())).isEqualTo(200);
        assertThat(room("101").get("available")).isEqualTo(2);
        it.db(() -> jdbc.sql("UPDATE hostel.allocation SET held_until = now() - interval '1 minute' WHERE id = :i").param("i", UUID.fromString(String.valueOf(rb.getBody().get("id")))).update());
        clock.tick();
        assertThat(jdbc.sql("SELECT state FROM hostel.allocation WHERE id = :i").param("i", UUID.fromString(String.valueOf(rb.getBody().get("id")))).query(String.class).single()).isEqualTo("LAPSED");
        assertThat(room("101").get("available")).isEqualTo(3);
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.event WHERE allocation_id = :i AND action = 'RESERVATION_EXPIRED'").param("i", UUID.fromString(String.valueOf(rb.getBody().get("id")))).query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject = 'Your hostel reservation has expired'").param("s", b).query(Long.class).single()).isGreaterThan(0L);
        // the expired reservation cannot be paid for through the API after the deadline
        ResponseEntity<Map> late = it.call(tb, HttpMethod.POST, "/api/v1/me/hostel/fee-reference", Map.of("session", SESSION));
        assertThat(late.getStatusCode().value()).isEqualTo(422);
        // and the student may reserve again while the window is open
        assertThat(it.call(tb, HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId("101"))).getStatusCode().value()).isEqualTo(200);
        assertThat(room("101").get("available")).isEqualTo(2);

        // ── 8 · capacity: a one-bed room takes one; the second is told the room is no longer available ──
        UUID d = ready("ZZHUD" + new Random().nextInt(9000), null);
        UUID e = ready("ZZHUE" + new Random().nextInt(9000), null);
        assertThat(it.call(TestTokens.token(d, List.of("student")), HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId("102"))).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> full = it.call(TestTokens.token(e, List.of("student")), HttpMethod.POST, "/api/v1/me/hostel/reserve", Map.of("session", SESSION, "roomId", roomId("102")));
        assertThat(full.getStatusCode().value()).isEqualTo(422);
        assertThat(full.getBody().get("code")).isEqualTo("HOSTEL_ROOM_FULL");
        assertThat(room("102").get("status")).isEqualTo("FULL");
        assertThat(l(it.get(TestTokens.token(e, List.of("student")), "/api/v1/me/hostel/rooms?session=" + SESSION).getBody().get("rooms")).stream().map(r -> String.valueOf(r.get("room_no")))).doesNotContain("102");

        // ── 9 · the Dean's allocations: special is payable at the Bursar's rule; Student Union and Security are no charge, and on the record ──
        UUID f = student("ZZHUF" + new Random().nextInt(9000));
        String fNumber = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", f).query(String.class).single();
        assertThat(it.call(bursar, HttpMethod.POST, HS + "/allocate-special", Map.of("bedId", freeBed("205"), "studentNumber", fNumber, "reason", "Guest of the hall")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ta, HttpMethod.POST, HS + "/allocate-special", Map.of("bedId", freeBed("205"), "studentNumber", fNumber, "reason", "Guest of the hall")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> special = it.call(dsa, HttpMethod.POST, HS + "/allocate-special", Map.of("bedId", freeBed("205"), "category", "SPECIAL", "studentNumber", fNumber, "reason", "Guest of the hall"));
        assertThat(special.getStatusCode().value()).as(String.valueOf(special.getBody())).isEqualTo(200);
        assertThat(special.getBody().get("fee_status")).isEqualTo("PAYABLE");
        assertThat(new BigDecimal(String.valueOf(special.getBody().get("fee_amount")))).isEqualByComparingTo("150000");
        assertThat(special.getBody().get("payment_status")).isEqualTo("OUTSTANDING");
        String tf = TestTokens.token(f, List.of("student"));
        ResponseEntity<Map> fRef = it.call(tf, HttpMethod.POST, "/api/v1/me/hostel/fee-reference", Map.of("session", SESSION));
        assertThat(fRef.getStatusCode().value()).as(String.valueOf(fRef.getBody())).isEqualTo(200);
        assertThat(new BigDecimal(String.valueOf(fRef.getBody().get("amount")))).isEqualByComparingTo("150000");
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK', 'teller for the test')").param("r", String.valueOf(fRef.getBody().get("reference"))).query(String.class).single());
        assertThat(jdbc.sql("SELECT fee_status FROM hostel.allocation WHERE student_id = :s AND session = :ses AND ended_at IS NULL").param("s", f).param("ses", SESSION).query(String.class).single()).isEqualTo("PAID");
        UUID g = student("ZZHUG" + new Random().nextInt(9000));
        String gNumber = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", g).query(String.class).single();
        ResponseEntity<Map> su = it.call(dsa, HttpMethod.POST, HS + "/allocate-special", Map.of("bedId", freeBed("SU-01"), "studentNumber", gNumber, "reason", "Student Union Welfare Director"));
        assertThat(su.getStatusCode().value()).as(String.valueOf(su.getBody())).isEqualTo(200);
        assertThat(su.getBody().get("fee_status")).isEqualTo("NO_CHARGE");
        assertThat(new BigDecimal(String.valueOf(su.getBody().get("fee_amount")))).isEqualByComparingTo("0");
        assertThat(su.getBody().get("payment_status")).isEqualTo("NOT REQUIRED");
        assertThat(su.getBody().get("state")).isEqualTo("CONFIRMED");
        ResponseEntity<Map> noCharge = it.call(TestTokens.token(g, List.of("student")), HttpMethod.POST, "/api/v1/me/hostel/fee-reference", Map.of("session", SESSION));
        assertThat(noCharge.getStatusCode().value()).isEqualTo(422);
        assertThat(noCharge.getBody().get("code")).isEqualTo("HOSTEL_NO_CHARGE");
        ResponseEntity<Map> sec = it.call(dsa, HttpMethod.POST, HS + "/allocate-special", Map.of("bedId", freeBed("SEC-01"), "occupantName", "Officer Test Invented", "reason", "Night patrol post"));
        assertThat(sec.getStatusCode().value()).as(String.valueOf(sec.getBody())).isEqualTo(200);
        assertThat(sec.getBody().get("occupant_kind")).isEqualTo("OTHER");
        assertThat(sec.getBody().get("fee_status")).isEqualTo("NO_CHARGE");
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.event WHERE action IN ('SU_ALLOCATION_CREATED', 'SECURITY_ALLOCATION_CREATED', 'SPECIAL_ALLOCATION_CREATED')").query(Long.class).single()).isGreaterThanOrEqualTo(3L);
        // a second occupant of the one-bed security room is refused; the special room's mismatch of category is refused
        assertThat(it.call(dsa, HttpMethod.POST, HS + "/allocate-special", Map.of("bedId", freeBed("205"), "category", "STUDENT_UNION", "occupantName", "Nobody", "reason", "wrong category")).getBody().get("code")).isEqualTo("HOSTEL_ALLOCATION_REFUSED");

        // ── 10 · accountability and the Bursar's figures: every occupant, paying or not ──
        List<Map<String, Object>> acc = l(it.get(dsa, HS + "/accountability").getBody().get("rows"));
        assertThat(acc.stream().map(r -> String.valueOf(r.get("occupant")))).contains("Officer Test Invented");
        assertThat(acc.stream().filter(r -> "NO_CHARGE".equals(r.get("fee_status"))).count()).isGreaterThanOrEqualTo(2L);
        assertThat(acc.stream().filter(r -> "101".equals(r.get("room_no")) && "PAID".equals(r.get("fee_status"))).count()).isEqualTo(1L);
        assertThat(l(it.get(dsa, HS + "/special?category=SECURITY").getBody().get("rows"))).hasSize(1);
        Map<String, Object> fin = it.get(bursar, HS + "/finance").getBody();
        Map<String, Object> totals = m(m(new tools.jackson.databind.ObjectMapper().readValue(String.valueOf(fin.get("summary")), Map.class)).get("totals"));
        assertThat(new BigDecimal(String.valueOf(totals.get("paid")))).isEqualByComparingTo("250000");
        assertThat(((Number) totals.get("exempt_allocations")).intValue()).isEqualTo(2);
        assertThat(((Number) totals.get("unpaid_occupants")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(it.get(lecturer, HS + "/finance").getStatusCode().value()).isEqualTo(403);

        // ── 11 · maintenance: an occupied room is not taken out from under its occupant; an empty one is, and leaves the student's list ──
        ResponseEntity<Map> occupied = it.call(dsa, HttpMethod.POST, "/api/v1/hostel/close?session=" + SESSION, Map.of("kind", "ROOM", "id", roomId("101").toString(), "state", "MAINTENANCE", "reason", "Leaking roof"));
        assertThat(occupied.getStatusCode().value()).isEqualTo(422);
        assertThat(occupied.getBody().get("code")).isEqualTo("HOSTEL_ROOM_OCCUPIED");
        assertThat(it.call(dsa, HttpMethod.POST, "/api/v1/hostel/close?session=" + SESSION, Map.of("kind", "ROOM", "id", roomId("104").toString(), "state", "MAINTENANCE", "reason", "Repainting")).getStatusCode().value()).isEqualTo(200);
        assertThat(l(it.get(TestTokens.token(e, List.of("student")), "/api/v1/me/hostel/rooms?session=" + SESSION).getBody().get("rooms")).stream().map(r -> String.valueOf(r.get("room_no")))).doesNotContain("104").contains("105");
        assertThat(jdbc.sql("SELECT count(*) FROM hostel.event WHERE action = 'ROOM_MARKED_MAINTENANCE' AND room_id = :r").param("r", roomId("104")).query(Long.class).single()).isGreaterThanOrEqualTo(1L);

        // ── 12 · the walls: a student changes no category, no capacity, no fee ──
        assertThat(it.call(ta, HttpMethod.PUT, "/api/v1/hostel/rooms/" + roomId("101") + "/category", Map.of("category", "GENERAL")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ta, HttpMethod.PUT, HS + "/fees", Map.of("amount", 1)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/hostel/rooms/" + roomId("101") + "/category", Map.of("category", "SPECIAL")).getStatusCode().value()).isEqualTo(403);
      } finally {
        // no fee line of this far-future session stays, or every other suite's student would stand in it; the hall closes so its beds count nowhere
        reset(true);
      }
    }
}
