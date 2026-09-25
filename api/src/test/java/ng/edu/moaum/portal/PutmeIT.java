package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.Base64;
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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * The Post-UTME CBT examination (V260), end to end: the programmes screened by examination make candidates eligible;
 * the paid and submitted are ready, the unpaid wait, a programme not screened is not eligible; the examination is
 * set up with a centre, a room of numbered workstations, a day and a slot; the batches are generated to the places,
 * validated and published — the candidates told, the slip carrying the centre, room, seat and a token the public
 * verify door answers; the door checks a candidate in once and refuses a second arrival; attendance is marked and
 * the eligibility reads "examination sat"; the examination reopened seats the one left over; a batch postponed
 * returns its candidates to scheduling and tells them; a move into a full batch is refused and into a free seat
 * accepted; a programme change flags the seating for review and the desk confirms it; the Bursary reads and cannot
 * change; a lecturer is refused; an applicant reads only their own record. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PutmeIT {

    static final String SESSION = "2097/2098";
    static final String PATH = "/api/v1/admissions/sessions/2097/2098";
    static final String PUTME = PATH + "/putme";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    String academic = ItSupport.token("academic");
    String bursar = ItSupport.token("bursar");
    String lecturer = ItSupport.token("lecturer");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2097);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
        // the programme screened by the examination this session — the admission settings name it
        it.db(() -> jdbc.sql("INSERT INTO admissions.screening_exam_programme (session, programme_code) VALUES (:s, 'C00061') ON CONFLICT DO NOTHING").param("s", SESSION).update());
        // an earlier run of this test on the same database (never in CI, which starts clean): its candidates withdrawn and
        // unseated, its batches cancelled, the examination back to configuring — so they do not compete for this run's seats
        it.db(() -> {
            jdbc.sql("SELECT set_config('moaum.putme_reason', 'earlier test run reset', true)").query().listOfRows();
            jdbc.sql("UPDATE admissions.application a SET screening_batch_id = NULL, seat = NULL WHERE a.session = :s AND a.screening_batch_id IS NOT NULL").param("s", SESSION).update();
            jdbc.sql("UPDATE admissions.candidate c SET offer_state = 'WITHDRAWN' WHERE c.surname LIKE 'ZZPUTME-%' AND c.offer_state IS DISTINCT FROM 'WITHDRAWN' AND EXISTS (SELECT 1 FROM admissions.application a WHERE a.candidate_id = c.id AND a.session = :s)").param("s", SESSION).update();
            jdbc.sql("UPDATE admissions.screening_batch SET state = 'CANCELLED' WHERE session = :s AND state IN ('DRAFT','PUBLISHED')").param("s", SESSION).update();
            return jdbc.sql("UPDATE admissions.putme_exam SET state = 'CONFIGURING', published_at = NULL WHERE session = :s").param("s", SESSION).update();
        });
    }

    ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    private static String jamb() {
        return "2097" + String.format("%08d", new Random().nextInt(100_000_000)) + "CB";
    }

    /** a registered applicant of the programme, paid and submitted when asked; returns [token, applicationNo, jamb] */
    private String[] applicant(String surname, String code, boolean pay, boolean submit) {
        String jamb = jamb();
        ResponseEntity<Map> loaded = it.call(academic, HttpMethod.POST, "/api/v1/admissions/caps-batches", Map.of(
                "session", SESSION, "source", "CAPS_DOWNLOAD", "filename", "CAPS-DE-putme-" + jamb + ".xlsx",
                "fileSha256", String.format("%064x", new Random().nextLong() & Long.MAX_VALUE), "listKind", "DIRECT_ENTRY", "downloadedOn", "2026-09-01",
                "rows", List.of(Map.of("jambRegNo", jamb, "surname", surname, "otherNames", "Invented", "jambCode", code, "entryMode", "DIRECT_ENTRY", "sex", "F", "stateOfOrigin", "Benue", "lga", "Gwer West", "raw", Map.of()))));
        assertThat(loaded.getStatusCode().value()).as(String.valueOf(loaded.getBody())).isEqualTo(201);
        ResponseEntity<Map> registered = post("/api/v1/applicant/register", Map.of("session", SESSION, "jambKey", jamb, "email", jamb.toLowerCase() + "@example.com", "phone", "0803" + jamb.substring(5, 12), "password", "a long enough password"));
        assertThat(registered.getStatusCode().value()).as(String.valueOf(registered.getBody())).isEqualTo(200);
        String token = String.valueOf(registered.getBody().get("token"));
        String appNo = String.valueOf(registered.getBody().get("applicationNo"));
        if (pay) {
            String reference = String.valueOf(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")).getBody().get("reference"));
            assertThat(it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + reference + "/confirm", Map.of("channel", "Bank transfer")).getStatusCode().value()).isEqualTo(200);
        }
        if (submit) {
            it.call(token, HttpMethod.PUT, "/api/v1/applicant/me/next-of-kin", Map.of("nextOfKin", surname + ", Terhemba · 0806 552 1180"));
            String pdf = Base64.getEncoder().encodeToString("%PDF-1.4 invented".getBytes());
            for (String kind : List.of("OLEVEL_STATEMENT", "BIRTH_CERT", "LGA_ID", "JAMB_SLIP", "PASSPORT")) {
                it.call(token, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", kind, "filename", kind.toLowerCase() + ".pdf", "contentType", "application/pdf", "contentBase64", pdf));
            }
            ResponseEntity<Map> submitted = it.call(token, HttpMethod.POST, "/api/v1/applicant/me/submit", Map.of("declaration", true));
            assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        }
        return new String[] {token, appNo, jamb};
    }

    private Map<String, Object> candidate(String appNo) {
        Map<String, Object> list = it.get(academic, PUTME + "/candidates?q=" + appNo).getBody();
        List<Map<String, Object>> rows = (List<Map<String, Object>>) list.get("rows");
        return rows.stream().filter(r -> appNo.equals(r.get("application_no"))).findFirst().orElseThrow();
    }

    private Map<String, Object> me(String token) {
        return it.get(token, "/api/v1/applicant/me").getBody();
    }

    private List<String> subjects(String token) {
        List<Map<String, Object>> notices = (List<Map<String, Object>>) me(token).get("notices");
        return notices.stream().map(n -> String.valueOf(n.get("subject"))).toList();
    }

    @Test
    void fromEligibilityToTheDoorAndBack() {
        String tag = String.format("%04d", new Random().nextInt(10_000));
        String[] a = applicant("ZZPUTME-A" + tag, "C00061", true, true);   // ready
        String[] b = applicant("ZZPUTME-B" + tag, "C00061", true, true);   // ready
        String[] c = applicant("ZZPUTME-C" + tag, "C00061", true, true);   // ready, no place at first
        String[] u = applicant("ZZPUTME-U" + tag, "C00061", false, false); // unpaid
        String[] n = applicant("ZZPUTME-N" + tag, "C00002", true, true);   // a programme not screened by examination

        // ── 1 · eligibility ──
        assertThat(candidate(a[1]).get("status")).isEqualTo("READY_FOR_SCHEDULING");
        assertThat(candidate(u[1]).get("status")).isEqualTo("PAYMENT_PENDING");
        assertThat(candidate(n[1]).get("status")).isEqualTo("NOT_ELIGIBLE");
        assertThat(String.valueOf(candidate(n[1]).get("why"))).contains("not screened by the Post-UTME examination");

        // ── 2 · the examination, its centre, room, day, slot ──
        ResponseEntity<Map> exam = it.call(academic, HttpMethod.PUT, PUTME + "/exam", Map.of("name", "Post-UTME CBT " + SESSION, "strategy", "PROGRAMME", "checkinMinutes", 45, "durationMinutes", 90, "bufferMinutes", 30,
                "instructions", "Bring your slip and a valid identification.", "contact", "admissions@moaum.edu.ng"));
        assertThat(exam.getStatusCode().value()).as(String.valueOf(exam.getBody())).isEqualTo(200);
        assertThat(((Map<String, Object>) exam.getBody().get("exam")).get("state")).isEqualTo("CONFIGURING");
        // generating before any place exists is refused with the remedy (an earlier run's days and centres are cleared first)
        assertThat(it.call(academic, HttpMethod.PUT, PUTME + "/exam/days", Map.of("dates", List.of())).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.PUT, PUTME + "/exam/centres", Map.of("ids", List.of())).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.POST, PUTME + "/generate", Map.of()).getStatusCode().value()).isEqualTo(422);

        String code = "ZZ" + tag.substring(0, 3);
        List<Map<String, Object>> centres = it.callList(academic, HttpMethod.POST, PUTME + "/centres", Map.of("code", code, "name", "ICT CBT Centre " + tag, "location", "Main campus", "address", "ICT Directorate, Makurdi")).getBody();
        Map<String, Object> centre = centres.stream().filter(x -> code.equals(x.get("code"))).findFirst().orElseThrow();
        String centreId = String.valueOf(centre.get("id"));
        centres = it.callList(academic, HttpMethod.POST, PUTME + "/centres/" + centreId + "/rooms", Map.of("code", "R1", "name", "Hall 1", "capacity", 2, "workstations", 2)).getBody();
        centre = centres.stream().filter(x -> code.equals(x.get("code"))).findFirst().orElseThrow();
        List<Map<String, Object>> rooms = (List<Map<String, Object>>) centre.get("rooms");
        assertThat(rooms).hasSize(1);
        assertThat(((Number) rooms.get(0).get("operational_workstations")).intValue()).isEqualTo(2);
        String roomId = String.valueOf(rooms.get(0).get("id"));
        List<Map<String, Object>> ws = it.getList(academic, PUTME + "/rooms/" + roomId + "/workstations").getBody();
        assertThat(ws).extracting(w -> w.get("label")).containsExactly("Computer 001", "Computer 002");

        LocalDate day = LocalDate.now().plusDays(7);
        assertThat(it.call(academic, HttpMethod.PUT, PUTME + "/exam/centres", Map.of("ids", List.of(centreId))).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.PUT, PUTME + "/exam/days", Map.of("dates", List.of(day.toString()))).getStatusCode().value()).isEqualTo(200);
        // a slot that ends before it starts is refused
        assertThat(it.call(academic, HttpMethod.PUT, PUTME + "/exam/slots", Map.of("slots", List.of(Map.of("code", "S1", "startsAt", "11:00", "endsAt", "09:00")))).getStatusCode().value()).isEqualTo(422);
        Map<String, Object> ov = it.call(academic, HttpMethod.PUT, PUTME + "/exam/slots", Map.of("slots", List.of(Map.of("code", "S1", "startsAt", "09:00", "endsAt", "10:30")))).getBody();
        Map<String, Object> preview = (Map<String, Object>) ov.get("preview");
        assertThat(((Number) preview.get("places")).intValue()).isEqualTo(1);
        assertThat(((Number) preview.get("capacity")).intValue()).isEqualTo(2);
        assertThat(((Number) preview.get("ready")).intValue()).isGreaterThanOrEqualTo(3);

        // ── 3 · generate: two seated by the programme strategy, one without a place; validation warns ──
        ResponseEntity<Map> gen = it.call(academic, HttpMethod.POST, PUTME + "/generate", Map.of());
        assertThat(gen.getStatusCode().value()).as(String.valueOf(gen.getBody())).isEqualTo(200);
        assertThat(((Number) gen.getBody().get("batches")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) gen.getBody().get("seated")).intValue()).isEqualTo(2);
        assertThat(((Number) gen.getBody().get("unseated")).intValue()).isGreaterThanOrEqualTo(1);
        List<Map<String, Object>> batches = it.getList(academic, PUTME + "/batches").getBody();
        Map<String, Object> b1 = batches.stream().filter(x -> "DRAFT".equals(x.get("state")) && ("ICT CBT Centre " + tag).equals(x.get("centre"))).findFirst().orElseThrow();
        String b1Id = String.valueOf(b1.get("id"));
        assertThat(b1.get("centre")).isEqualTo("ICT CBT Centre " + tag);
        assertThat(b1.get("room")).isEqualTo("Hall 1");
        assertThat(((Number) b1.get("assigned")).intValue()).isEqualTo(2);
        List<Map<String, Object>> findings = it.getList(academic, PUTME + "/validate").getBody();
        assertThat(findings).extracting(f -> f.get("code")).contains("UNSCHEDULED");
        assertThat(findings).extracting(f -> f.get("severity")).doesNotContain("ERROR");
        // seated A–Z by the strategy: A and B took the two seats; C waits
        assertThat(candidate(a[1]).get("status")).isEqualTo("SCHEDULED");
        assertThat(candidate(b[1]).get("status")).isEqualTo("SCHEDULED");
        assertThat(candidate(c[1]).get("status")).isEqualTo("READY_FOR_SCHEDULING");
        assertThat(candidate(a[1]).get("workstation")).isEqualTo("Computer 001");
        // a draft batch is not the applicant's to see: no slip, the stage stays at 2
        assertThat(me(a[0]).get("screeningSlip")).isNull();
        assertThat(me(a[0]).get("stage")).isEqualTo(2);

        // ── 4 · publish: the candidates told, the slip carries the placing and the token the public door answers ──
        ResponseEntity<Map> pub = it.call(academic, HttpMethod.POST, PUTME + "/publish", Map.of());
        assertThat(pub.getStatusCode().value()).as(String.valueOf(pub.getBody())).isEqualTo(200);
        assertThat(((Number) pub.getBody().get("told")).intValue()).isGreaterThanOrEqualTo(2);
        Map<String, Object> meA = me(a[0]);
        assertThat(meA.get("stage")).isEqualTo(3);
        Map<String, Object> slip = (Map<String, Object>) meA.get("screeningSlip");
        assertThat(slip).isNotNull();
        assertThat(slip.get("published")).isEqualTo(true);
        assertThat(slip.get("centre")).isEqualTo("ICT CBT Centre " + tag);
        assertThat(slip.get("room")).isEqualTo("Hall 1");
        assertThat(slip.get("workstation")).isEqualTo("Computer 001");
        assertThat(slip.get("checkinMinutes")).isEqualTo(45);
        assertThat(String.valueOf(slip.get("instructions"))).contains("Bring your slip");
        String token = String.valueOf(slip.get("token"));
        assertThat(token).hasSize(16);
        assertThat(subjects(a[0])).contains("Your Post-UTME examination schedule");
        assertThat(subjects(c[0])).doesNotContain("Your Post-UTME examination schedule");
        // the public verify door: genuine by the token, not by a made-up one; an applicant sees only their own record
        Map<String, Object> v = it.anon(HttpMethod.GET, "/api/v1/verify/putme/" + token, null).getBody();
        assertThat(v.get("genuine")).isEqualTo(true);
        assertThat(v.get("application_no")).isEqualTo(a[1]);
        assertThat(v.get("seat")).isEqualTo(slip.get("seat"));
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/putme/0000000000000000", null).getBody().get("genuine")).isEqualTo(false);
        assertThat(me(b[0]).get("applicationNo")).isEqualTo(b[1]);
        assertThat(it.get(a[0], PUTME + "/lookup?key=" + b[1]).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> ovAfter = it.get(academic, PUTME).getBody();
        assertThat(((Map<String, Object>) ovAfter.get("exam")).get("state")).isEqualTo("SCHEDULED");

        // ── 5 · the door: found by the token, checked in once, a second arrival refused; attendance marked ──
        Map<String, Object> found = it.get(academic, PUTME + "/lookup?key=" + token).getBody();
        assertThat(found.get("application_no")).isEqualTo(a[1]);
        ResponseEntity<Map> in = it.call(academic, HttpMethod.POST, PUTME + "/checkin", Map.of("key", a[1]));
        assertThat(in.getStatusCode().value()).as(String.valueOf(in.getBody())).isEqualTo(200);
        assertThat(in.getBody().get("result")).isEqualTo("checked in");
        assertThat(in.getBody().get("attendance")).isEqualTo("CHECKED_IN");
        assertThat(String.valueOf(it.call(academic, HttpMethod.POST, PUTME + "/checkin", Map.of("key", a[2])).getBody().get("result"))).startsWith("already checked in");
        // an unseated candidate cannot be checked in
        assertThat(it.call(academic, HttpMethod.POST, PUTME + "/checkin", Map.of("key", c[1])).getStatusCode().value()).isEqualTo(422);
        Map<String, Object> marked = it.call(academic, HttpMethod.POST, PUTME + "/attendance", Map.of("applicationId", candidate(a[1]).get("application_id"), "attendance", "PRESENT", "examStatus", "COMPLETED")).getBody();
        assertThat(marked.get("status")).isEqualTo("EXAM_COMPLETED");
        assertThat(((Map<String, Object>) me(a[0]).get("screeningSlip")).get("examStatus")).isEqualTo("COMPLETED");
        Map<String, Object> batchView = it.get(academic, PUTME + "/batches/" + b1Id).getBody();
        assertThat(((Number) batchView.get("checked_in")).intValue()).isEqualTo(1);
        assertThat((List<Map<String, Object>>) batchView.get("candidates")).hasSize(2);

        // ── 6 · reopened, a second room seats the one left over; published again tells only them ──
        assertThat(it.call(academic, HttpMethod.POST, PUTME + "/generate", Map.of()).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(academic, HttpMethod.POST, PUTME + "/exam/state", Map.of("state", "SCHEDULED")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(academic, HttpMethod.POST, PUTME + "/exam/state", Map.of("state", "OPEN_FOR_SCHEDULING", "note", "a second room")).getStatusCode().value()).isEqualTo(200);
        it.callList(academic, HttpMethod.POST, PUTME + "/centres/" + centreId + "/rooms", Map.of("code", "R2", "name", "Hall 2", "capacity", 2, "workstations", 0));
        ResponseEntity<Map> gen2 = it.call(academic, HttpMethod.POST, PUTME + "/generate", Map.of());
        assertThat(gen2.getStatusCode().value()).as(String.valueOf(gen2.getBody())).isEqualTo(200);
        assertThat(((Number) gen2.getBody().get("seated")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(candidate(c[1]).get("status")).isEqualTo("SCHEDULED");
        assertThat(candidate(c[1]).get("room")).isEqualTo("Hall 2");
        String b2Id = String.valueOf(candidate(c[1]).get("batch_id"));
        assertThat(b2Id).isNotEqualTo(b1Id);
        assertThat(candidate(a[1]).get("batch_id").toString()).isEqualTo(b1Id);
        assertThat(((Number) it.call(academic, HttpMethod.POST, PUTME + "/publish", Map.of()).getBody().get("told")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(subjects(c[0])).contains("Your Post-UTME examination schedule");

        // ── 7 · postponed: the batch's candidates return to scheduling with the reason, and are told ──
        assertThat(it.call(academic, HttpMethod.POST, PUTME + "/batches/" + b2Id + "/state", Map.of("state", "POSTPONED", "reason", "")).getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> post = it.call(academic, HttpMethod.POST, PUTME + "/batches/" + b2Id + "/state", Map.of("state", "POSTPONED", "reason", "Power failure at Hall 2"));
        assertThat(post.getStatusCode().value()).as(String.valueOf(post.getBody())).isEqualTo(200);
        assertThat(((Number) post.getBody().get("unseated")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(candidate(c[1]).get("status")).isEqualTo("RESCHEDULE_REQUIRED");
        assertThat(me(c[0]).get("screeningSlip")).isNull();
        assertThat(subjects(c[0])).contains("Your Post-UTME batch has been postponed");
        List<Map<String, Object>> seatings = it.getList(academic, PUTME + "/candidates/" + candidate(c[1]).get("application_id") + "/seatings").getBody();
        assertThat(seatings).extracting(s -> s.get("state")).contains("CANCELLED");

        // ── 8 · moved: into a full batch refused; a seat freed by unscheduling, then accepted ──
        String cId = String.valueOf(candidate(c[1]).get("application_id"));
        String bId = String.valueOf(candidate(b[1]).get("application_id"));
        ResponseEntity<Map> full = it.call(academic, HttpMethod.POST, PUTME + "/move", Map.of("applicationIds", List.of(cId), "batchId", b1Id, "reason", "Needs an earlier day"));
        assertThat(full.getStatusCode().value()).as(String.valueOf(full.getBody())).isEqualTo(422);
        assertThat(it.call(academic, HttpMethod.POST, PUTME + "/unschedule", Map.of("applicationIds", List.of(bId), "reason", "Asked to sit later")).getStatusCode().value()).isEqualTo(200);
        assertThat(candidate(b[1]).get("status")).isEqualTo("READY_FOR_SCHEDULING");
        assertThat(subjects(b[0])).contains("Your Post-UTME seating has been withdrawn");
        ResponseEntity<Map> moved = it.call(academic, HttpMethod.POST, PUTME + "/move", Map.of("applicationIds", List.of(cId), "batchId", b1Id, "reason", "Needs an earlier day"));
        assertThat(moved.getStatusCode().value()).as(String.valueOf(moved.getBody())).isEqualTo(200);
        assertThat(candidate(c[1]).get("status")).isEqualTo("RESCHEDULED");
        assertThat(candidate(c[1]).get("batch_id").toString()).isEqualTo(b1Id);
        assertThat(((Map<String, Object>) me(c[0]).get("screeningSlip")).get("room")).isEqualTo("Hall 1");
        // the trail names every step
        List<Map<String, Object>> events = it.getList(academic, PUTME + "/candidates/" + cId + "/events").getBody();
        assertThat(events).extracting(e -> e.get("action")).contains("SEATED");
        assertThat(it.getList(academic, PUTME + "/candidates/" + bId + "/events").getBody()).extracting(e -> ((Map<String, Object>) e).get("action")).contains("UNSCHEDULED");

        // ── 9 · a programme change flags the seating; the desk confirms it ──
        it.db(() -> jdbc.sql("UPDATE admissions.candidate SET programme = (SELECT name FROM ref.programme WHERE code = 'C00002') WHERE id = (SELECT candidate_id FROM admissions.application WHERE id = :a)").param("a", UUID.fromString(cId)).update());
        assertThat(candidate(c[1]).get("schedule_review")).isEqualTo(true);
        List<Map<String, Object>> review = it.getList(academic, PUTME + "/validate").getBody();
        assertThat(review).extracting(f -> f.get("code")).contains("REVIEW", "INELIGIBLE");
        assertThat(it.call(academic, HttpMethod.POST, PUTME + "/candidates/" + cId + "/confirm-schedule", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(candidate(c[1]).get("schedule_review")).isEqualTo(false);

        // ── 10 · who may: the Bursary reads and cannot change; a lecturer is refused; the batch list is exported from the candidates door ──
        assertThat(it.get(bursar, PUTME).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(bursar, HttpMethod.PUT, PUTME + "/exam", Map.of("name", "x")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.POST, PUTME + "/checkin", Map.of("key", a[1])).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(lecturer, PUTME).getStatusCode().value()).isEqualTo(403);
        // the batch holds A (examination sat) and C (rescheduled, now flagged by the programme change)
        Map<String, Object> scheduled = it.get(academic, PUTME + "/candidates?batch=" + b1Id).getBody();
        assertThat(((Number) scheduled.get("total")).intValue()).isEqualTo(2);
        Map<String, Object> byProg = it.get(academic, PUTME + "/candidates?prog=C00061&status=ELIGIBLE&q=ZZPUTME").getBody();
        assertThat(((Number) byProg.get("total")).intValue()).isGreaterThanOrEqualTo(3);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) byProg.get("rows");
        for (int i = 1; i < rows.size(); i++) assertThat(String.valueOf(rows.get(i).get("surname")).compareTo(String.valueOf(rows.get(i - 1).get("surname")))).isGreaterThanOrEqualTo(0);
    }
}
