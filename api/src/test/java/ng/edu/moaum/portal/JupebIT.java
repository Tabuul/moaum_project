package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * The JUPEB programme (V339), application to result: the application is taken only while the Director of ICT has its window
 * open; the candidate signs in on the application number, continues the biodata, enters an O'Level that must hold five credits
 * with English and Mathematics in at most two sittings, uploads private documents and pays an application fee the server sets;
 * the JUPEB Office reviews, returns, finds eligible and admits in bulk after a preview; the Bursary's rule gives the school fee
 * by Science or other and indigene or not, 70% then 30%, frozen once charged; the first instalment activates the student, who
 * chooses a combination of their Science or Arts stream and registers its three subjects only; the Board's examination numbers are imported by application number, a
 * mismatched surname held for review and a correction needing its reason; results are imported and shown only once published;
 * the candidate's support ticket reaches the JUPEB queue. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class JupebIT {

    static final String WINDOW = "JUPEB_APPLICATION";
    static final byte[] PDF = "%PDF-1.4\n% a JUPEB test document\n%%EOF\n".getBytes();
    static final String CHECKING = "JUPEB_ADMISSION_STATUS_CHECKING";
    /** a real (tiny) PNG, so the passport converts to the JPEG the documents embed */
    static final byte[] PNG = png();

    private static byte[] png() {
        try {
            java.awt.image.BufferedImage img = new java.awt.image.BufferedImage(4, 5, java.awt.image.BufferedImage.TYPE_INT_ARGB);
            img.setRGB(1, 1, 0xFF336699);
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            javax.imageio.ImageIO.write(img, "png", out);
            return out.toByteArray();
        } catch (java.io.IOException e) {
            throw new IllegalStateException(e);
        }
    }

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String ict = ItSupport.token("ict");
    String office;
    String bursar;
    String session;
    String programme;
    String faculty;
    String priorCategory;
    String tag;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        office = TestTokens.token(it.person("ZZJUPEB-OFFICER", "ZZJUPEBOFFICER"), List.of("jupeb"));
        bursar = TestTokens.token(it.person("ZZJUPEB-BURSAR", "ZZJUPEBBURSAR"), List.of("bursar"));
        session = jdbc.sql("SELECT jupeb.current_session()").query(String.class).single();
        Map<String, Object> p = jdbc.sql("SELECT code, faculty_code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND NOT archived ORDER BY code LIMIT 1").query().singleRow();
        programme = String.valueOf(p.get("code"));
        faculty = String.valueOf(p.get("faculty_code"));
        priorCategory = jdbc.sql("SELECT category FROM jupeb.fee_category WHERE faculty_code = :f").param("f", faculty).query(String.class).optional().orElse(null);
        tag = UUID.randomUUID().toString().replace("-", "").substring(0, 6).toUpperCase();
        clean();
    }

    @AfterEach
    void tearDown() {
        clean();
    }

    /** the session as every other run expects it: the JUPEB window closed (its default), no session fee rule, results unpublished, the faculty's category as it was */
    private void clean() {
        it.db(() -> {
            jdbc.sql("DELETE FROM policy.portal_window_event WHERE window_type IN (:t, :c) AND session = :s").param("t", WINDOW).param("c", CHECKING).param("s", session).update();
            jdbc.sql("DELETE FROM policy.portal_window WHERE window_type IN (:t, :c) AND session = :s").param("t", WINDOW).param("c", CHECKING).param("s", session).update();
            jdbc.sql("DELETE FROM jupeb.school_fee WHERE session = :s").param("s", session).update();
            jdbc.sql("DELETE FROM jupeb.fee_setting WHERE session = :s").param("s", session).update();
            jdbc.sql("DELETE FROM jupeb.setting WHERE session = :s").param("s", session).update();
            if (priorCategory == null) {
                jdbc.sql("DELETE FROM jupeb.fee_category WHERE faculty_code = :f").param("f", faculty).update();
            } else {
                jdbc.sql("UPDATE jupeb.fee_category SET category = :c WHERE faculty_code = :f").param("c", priorCategory).param("f", faculty).update();
            }
            return null;
        });
    }

    private static int status(ResponseEntity<?> r) {
        return r.getStatusCode().value();
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        return String.valueOf(r.getBody().get("code"));
    }

    private Map<String, Object> form(String email, String combination) {
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("surname", "Zzjupeb");
        f.put("firstName", "Candidate");
        f.put("middleName", "Test");
        f.put("sex", "F");
        f.put("dob", "2007-03-14");
        f.put("nin", "1" + String.format("%010d", Math.abs(email.hashCode()) % 1_000_000_000L));
        f.put("email", email);
        f.put("phone", "08031234567");
        f.put("password", "Jupeb2026!x");
        f.put("stream", "Science");
        return f;
    }

    private Map<String, Object> doc(String name, String type, byte[] bytes) {
        return Map.of("filename", name, "contentType", type, "base64", Base64.getEncoder().encodeToString(bytes));
    }

    @Test
    void applicationToResult() {
        // ── the office's subjects and an approved combination of three ──
        for (String s : List.of("M", "P", "C")) {
            assertThat(status(it.callList(office, HttpMethod.POST, "/api/v1/jupeb/office/subjects", Map.of("code", "ZZ" + s + tag, "title", "ZZ Subject " + s + " " + tag)))).isEqualTo(200);
        }
        String comb = "ZZ" + tag;
        Map<String, Object> saved = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/combinations",
                Map.of("code", comb, "name", "ZZ Test Combination " + tag, "subject1", "ZZM" + tag, "subject2", "ZZP" + tag, "subject3", "ZZC" + tag, "area", "Science")));
        assertThat(saved.get("new")).isEqualTo(1);
        // a combination is three different subjects
        assertThat(String.valueOf(ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/combinations/import",
                Map.of("rows", List.of(Map.of("row", 2, "code", "ZY" + tag, "name", "Twice", "subject1", "ZZM" + tag, "subject2", "ZZM" + tag, "subject3", "ZZC" + tag)), "commit", false)))
                .get("invalid"))).isEqualTo("1");

        // ── the Bursary's rule for the session; the JUPEB Office reads it but may not set it ──
        Map<String, Object> rule = new LinkedHashMap<>();
        rule.put("session", session);
        rule.put("applicationFee", 15000);
        rule.put("checkingFee", 1000);
        rule.put("acceptanceFee", 15000);
        rule.put("firstPercent", 70);
        rule.put("allowFull", true);
        rule.put("activation", "FIRST_INSTALMENT");
        rule.put("indigeneState", "Benue");
        rule.put("schoolFees", List.of(Map.of("category", "OTHER", "indigene", true, "amount", 180000), Map.of("category", "SCIENCE", "indigene", true, "amount", 195000),
                Map.of("category", "OTHER", "indigene", false, "amount", 200000), Map.of("category", "SCIENCE", "indigene", false, "amount", 215000)));
        assertThat(status(it.call(office, HttpMethod.PUT, "/api/v1/jupeb/fees", rule))).isEqualTo(403);
        ok(it.call(bursar, HttpMethod.PUT, "/api/v1/jupeb/fees", rule));
        assertThat(ok(it.get(office, ub -> ub.path("/api/v1/jupeb/fees").queryParam("session", session).build())).get("own")).isEqualTo(true);

        // ── closed until the Director of ICT opens it ──
        String email = "zzjupeb." + tag.toLowerCase() + "@example.com";
        assertThat(code(it.anon(HttpMethod.POST, "/api/v1/jupeb/apply", form(email, comb)))).isEqualTo("APPLICATION_CLOSED");
        ok(it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/" + WINDOW, Map.of("session", session, "action", "OPEN")));
        Map<String, Object> options = ok(it.anon(HttpMethod.GET, "/api/v1/jupeb/options", null));
        assertThat(((Map<String, Object>) options.get("window")).get("open")).isEqualTo(true);

        Map<String, Object> applied = ok(it.anon(HttpMethod.POST, "/api/v1/jupeb/apply", form(email, comb)));
        String number = String.valueOf(applied.get("application_no"));
        assertThat(number).matches("^JUPEB/APP/" + session.substring(0, 4) + "/\\d{6}$");
        assertThat(new BigDecimal(String.valueOf(applied.get("amount")))).isEqualByComparingTo("15000");
        // the reference carries the session's year: the count restarts each session and must not collide (V342)
        assertThat(String.valueOf(applied.get("reference"))).startsWith("MOAUM-JUPEBAPP-" + session.substring(0, 4) + "-");
        assertThat(code(it.anon(HttpMethod.POST, "/api/v1/jupeb/apply", form(email, comb)))).isEqualTo("JUPEB_APP_EXISTS");

        // ── signed in on the application number; the token reaches this candidate's record only ──
        Map<String, Object> signed = ok(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", number, "password", "Jupeb2026!x")));
        String me = String.valueOf(signed.get("token"));
        UUID app = UUID.fromString(String.valueOf(signed.get("applicationId")));
        assertThat(status(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", email, "password", "wrong-password")))).isEqualTo(422);
        assertThat(status(it.get(ItSupport.token("applicant"), "/api/v1/jupeb/me"))).isEqualTo(404);
        assertThat(status(it.get(ItSupport.token("student"), "/api/v1/jupeb/me"))).isEqualTo(403);
        assertThat(status(it.get(ItSupport.token("bursar"), "/api/v1/jupeb/office/applications/" + app))).isEqualTo(403);

        Map<String, Object> mine = ok(it.get(me, "/api/v1/jupeb/me"));
        assertThat(mine.get("state")).isEqualTo("DRAFT");
        assertThat((List<String>) mine.get("missing")).anyMatch(m -> m.contains("application fee"));
        // the guided application starts on the first incomplete step
        assertThat(((Map<String, Object>) mine.get("steps")).get("current")).isEqualTo("PERSONAL");
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/submit", null))).isEqualTo("JUPEB_INCOMPLETE");

        // the application fee: the same live reference, confirmed by the Bursar from the teller — never by the JUPEB Office
        Map<String, Object> ref = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=APPLICATION", null));
        assertThat(ref.get("reference")).isEqualTo(applied.get("reference"));
        Map<String, Object> teller = Map.of("channel", "Bank teller", "reason", "Teller 0001 seen at the Bursary");
        assertThat(status(it.call(office, HttpMethod.POST, "/api/v1/jupeb/fees/payments/" + ref.get("reference") + "/confirm", teller))).isEqualTo(403);
        assertThat(ok(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/fees/payments/" + ref.get("reference") + "/confirm", teller)).get("outcome")).isEqualTo("confirmed");
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=APPLICATION", null))).isEqualTo("JUPEB_FEE_PAID");
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=SCHOOL_FIRST", null))).isEqualTo("JUPEB_FEES_NOT_YET");

        // ── the biodata continued on the dashboard ──
        Map<String, Object> bio = new LinkedHashMap<>();
        bio.put("middleName", "Test");
        bio.put("nationality", "Nigerian");
        bio.put("stateOfOrigin", "Benue");
        bio.put("lga", "Makurdi");
        bio.put("contactAddress", "No. 1 Test Road, Makurdi");
        bio.put("homeTown", "Makurdi");
        bio.put("nextOfKinName", "Zz Parent");
        bio.put("nextOfKinPhone", "08039876543");
        bio.put("nextOfKinRelationship", "Mother");
        ok(it.call(me, HttpMethod.PUT, "/api/v1/jupeb/me/biodata", bio));

        // ── the O'Level: five credits with English and Mathematics, in the sittings declared (at most two) ──
        List<Map<String, Object>> four = List.of(grade(1, "English Language", "C5"), grade(1, "Mathematics", "B3"), grade(1, "Physics", "C6"),
                grade(1, "Chemistry", "C4"), grade(1, "Biology", "D7"));
        Map<String, Object> check = (Map<String, Object>) ok(it.call(me, HttpMethod.PUT, "/api/v1/jupeb/me/olevel", Map.of("sittings", 1, "grades", four))).get("olevelCheck");
        assertThat(check.get("ok")).isEqualTo(false);
        List<Map<String, Object>> five = new java.util.ArrayList<>(four);
        five.add(grade(2, "Biology", "B2"));
        // a second sitting's results under one declared sitting are refused; two declared, the combined result holds
        assertThat(code(it.call(me, HttpMethod.PUT, "/api/v1/jupeb/me/olevel", Map.of("sittings", 1, "grades", five)))).isEqualTo("JUPEB_OLEVEL_SITTINGS");
        mine = ok(it.call(me, HttpMethod.PUT, "/api/v1/jupeb/me/olevel", Map.of("sittings", 2, "grades", five)));
        check = (Map<String, Object>) mine.get("olevelCheck");
        assertThat(check.get("ok")).isEqualTo(true);
        assertThat(((Number) check.get("credits")).intValue()).isEqualTo(5);
        assertThat(((Number) check.get("sittings")).intValue()).isEqualTo(2);

        // ── the programme and a subject combination the University offers for it (V342) ──
        assertThat((List<String>) mine.get("missing")).anyMatch(m -> m.contains("subject combination"));
        assertThat(code(it.call(me, HttpMethod.PUT, "/api/v1/jupeb/me/choice", Map.of("stream", "SCIENCE", "combination", "SC-001")))).isEqualTo("JUPEB_COMBINATION_STREAM");
        // the JUPEB Office stops offering a combination: nobody chooses it; it comes back when reactivated — nothing is deleted
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/office/combinations/offered", Map.of("codes", List.of(comb), "offered", false)))).isEqualTo(403);
        Map<String, Object> off = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/combinations/offered", Map.of("codes", List.of(comb), "offered", false, "reason", "Not this session")));
        assertThat(((Number) off.get("changed")).intValue()).isEqualTo(1);
        assertThat((List<Map<String, Object>>) off.get("combinations")).anySatisfy(c -> {
            assertThat(c.get("code")).isEqualTo(comb);
            assertThat(c.get("offered")).isEqualTo(false);
        });
        assertThat((List<Map<String, Object>>) ok(it.get(me, "/api/v1/jupeb/me")).get("combinations")).noneMatch(c -> comb.equals(c.get("code")));
        assertThat(code(it.call(me, HttpMethod.PUT, "/api/v1/jupeb/me/choice", Map.of("stream", "SCIENCE", "combination", comb)))).isEqualTo("JUPEB_COMBINATION");
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/combinations/offered", Map.of("codes", List.of("ZZNOSUCH" + tag), "offered", true))))
                .isEqualTo("JUPEB_UNKNOWN_COMBINATION");
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/combinations/offered", Map.of("codes", List.of(comb), "offered", true)));
        mine = ok(it.call(me, HttpMethod.PUT, "/api/v1/jupeb/me/choice", Map.of("stream", "SCIENCE", "combination", comb)));
        assertThat(mine.get("combination_code")).isEqualTo(comb);
        assertThat((List<String>) mine.get("missing")).noneMatch(m -> m.contains("subject combination"));
        // a subject not offered withdraws every combination holding it; the candidate who chose one is told, and must choose again
        off = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/subjects/offered", Map.of("codes", List.of("ZZP" + tag), "offered", false)));
        assertThat(((Number) off.get("told")).intValue()).isEqualTo(1);
        assertThat((List<String>) ok(it.get(me, "/api/v1/jupeb/me")).get("missing")).anyMatch(m -> m.contains(comb + " is no longer offered"));
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/subjects/offered", Map.of("codes", List.of("ZZP" + tag), "offered", true)));
        assertThat((List<String>) ok(it.get(me, "/api/v1/jupeb/me")).get("missing")).noneMatch(m -> m.contains("no longer offered"));

        // ── the documents: what a file claims to be is checked; each is read back only by its owner and the office ──
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/documents/NIN", doc("nin.pdf", "application/pdf", "not a pdf".getBytes()))))
                .isEqualTo("JUPEB_DOC_TYPE");
        for (String k : List.of("OLEVEL_RESULT", "NIN", "BIRTH_CERTIFICATE", "STATE_OF_ORIGIN")) {
            ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/documents/" + k, doc(k.toLowerCase() + ".pdf", "application/pdf", PDF)));
        }
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/documents/PASSPORT", doc("passport.pdf", "application/pdf", PDF)))).isEqualTo("JUPEB_DOC_TYPE");
        mine = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/documents/PASSPORT", doc("passport.png", "image/png", PNG)));
        // two sittings declared: the second sitting's own result is still missing, and is a document of its own
        assertThat((List<String>) mine.get("missing")).anyMatch(m -> m.contains("second sitting"));
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/documents/OLEVEL_RESULT?sitting=3", doc("x.pdf", "application/pdf", PDF)))).isEqualTo("JUPEB_DOC_SITTING");
        byte[] secondSitting = "%PDF-1.4\n% the second sitting\n%%EOF\n".getBytes();
        mine = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/documents/OLEVEL_RESULT?sitting=2", doc("neco.pdf", "application/pdf", secondSitting)));
        assertThat((List<String>) mine.get("missing")).isEmpty();
        assertThat(((Map<String, Object>) mine.get("steps")).get("current")).isEqualTo("REVIEW");
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.document WHERE application_id = :a AND kind = 'OLEVEL_RESULT'").param("a", app).query(Integer.class).single()).isEqualTo(2);
        assertThat(it.getBytes(me, "/api/v1/jupeb/me/documents/OLEVEL_RESULT/content?sitting=2").getBody()).isEqualTo(secondSitting);
        // the passport, as the JPEG the documents embed
        byte[] jpeg = it.getBytes(me, "/api/v1/jupeb/me/documents/PASSPORT/content?format=jpeg").getBody();
        assertThat(jpeg).isNotNull();
        assertThat(jpeg[0] & 0xFF).isEqualTo(0xFF);
        assertThat(jpeg[1] & 0xFF).isEqualTo(0xD8);
        assertThat(it.getBytes(me, "/api/v1/jupeb/me/documents/NIN/content").getBody()).isEqualTo(PDF);
        assertThat(it.getBytes(office, "/api/v1/jupeb/office/applications/" + app + "/documents/NIN/content").getBody()).isEqualTo(PDF);

        assertThat(ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/submit", null)).get("state")).isEqualTo("SUBMITTED");
        assertThat(code(it.call(me, HttpMethod.PUT, "/api/v1/jupeb/me/biodata", bio))).isEqualTo("JUPEB_NOT_EDITABLE");

        // ── V343: the acknowledgement carries a code the public verifier reads back; the same paper keeps its code ──
        String ack = String.valueOf(ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/papers", Map.of("kind", "ACKNOWLEDGEMENT"))).get("code"));
        assertThat(ack).matches("^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$");
        assertThat(ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/papers", Map.of("kind", "ACKNOWLEDGEMENT"))).get("code")).isEqualTo(ack);
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/papers", Map.of("kind", "REGISTRATION_SLIP")))).isEqualTo("JUPEB_PAPER_NOT_ISSUABLE");
        Map<String, Object> verified = ok(it.anon(HttpMethod.GET, "/api/v1/verify/jupeb/" + ack.toLowerCase().replace("-", ""), null));
        assertThat(verified.get("genuine")).isEqualTo(true);
        assertThat(verified.get("current")).isEqualTo(true);
        assertThat(((Map<String, Object>) verified.get("facts")).get("applicationNo")).isEqualTo(number);
        assertThat(((Map<String, Object>) verified.get("facts"))).doesNotContainKeys("nin", "email", "phone", "dateOfBirth");
        assertThat(ok(it.anon(HttpMethod.GET, "/api/v1/verify/jupeb/AAAA-BBBB-CCCC", null)).get("genuine")).isEqualTo(false);

        // ── V343: after submission a change is asked for, one at a time, and the JUPEB Office decides it (declining says why) ──
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/requests", Map.of("kind", "CHANGE_COMBINATION", "combination", "SC-031", "reason", "short"))))
                .isEqualTo("JUPEB_CHANGE_REASON");
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/requests", Map.of("kind", "DEFER", "reason", "Family reasons this session"))))
                .isEqualTo("JUPEB_DEFER_STATE");
        mine = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/requests", Map.of("kind", "CHANGE_COMBINATION", "combination", "SC-031", "reason", "I would rather take Biology")));
        Map<String, Object> asked = ((List<Map<String, Object>>) mine.get("requests")).get(0);
        assertThat(asked.get("state")).isEqualTo("PENDING");
        assertThat(String.valueOf(asked.get("words"))).contains("to SC-031");
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/requests", Map.of("kind", "WITHDRAW", "reason", "Changed my mind entirely"))))
                .isEqualTo("JUPEB_CHANGE_PENDING");
        assertThat(status(it.call(me, HttpMethod.POST, "/api/v1/jupeb/office/requests/" + asked.get("id") + "/decide", Map.of("approve", false, "note", "x")))).isEqualTo(403);
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/requests/" + asked.get("id") + "/decide", Map.of("approve", false))))
                .isEqualTo("JUPEB_CHANGE_NOTE");
        assertThat(it.getList(office, "/api/v1/jupeb/office/requests").getBody()).anyMatch(r -> asked.get("id").equals(((Map) r).get("id")));
        Map<String, Object> declined = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/requests/" + asked.get("id") + "/decide",
                Map.of("approve", false, "note", "The class for SC-031 is full")));
        assertThat(((List<Map<String, Object>>) declined.get("requests")).get(0).get("state")).isEqualTo("DECLINED");
        assertThat(declined.get("combination_code")).isEqualTo(comb);
        mine = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/requests", Map.of("kind", "WITHDRAW", "reason", "Thinking of withdrawing")));
        mine = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/requests/" + ((List<Map<String, Object>>) mine.get("requests")).get(0).get("id") + "/cancel", null));
        assertThat(((List<Map<String, Object>>) mine.get("requests")).get(0).get("state")).isEqualTo("CANCELLED");
        assertThat(mine.get("state")).isEqualTo("SUBMITTED");

        // ── the office: a document to replace needs its reason; the candidate replaces it; a return and a resubmission ──
        Map<String, Object> list = ok(it.get(office, ub -> ub.path("/api/v1/jupeb/office/applications").queryParam("session", session).queryParam("q", number).build()));
        assertThat(((Number) list.get("total")).intValue()).isEqualTo(1);
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/documents/OLEVEL_RESULT/review", Map.of("status", "REPLACEMENT_REQUIRED"))))
                .isEqualTo("JUPEB_REASON");
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/documents/OLEVEL_RESULT/review",
                Map.of("status", "REPLACEMENT_REQUIRED", "note", "The scan is unreadable.")));
        ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/documents/OLEVEL_RESULT", doc("olevel2.pdf", "application/pdf", PDF)));
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/return", Map.of("note", "Add your home town.")));
        ok(it.call(me, HttpMethod.PUT, "/api/v1/jupeb/me/biodata", bio));
        assertThat(ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/submit", null)).get("state")).isEqualTo("SUBMITTED");

        // ── admission: eligibility first, then in bulk after a preview ──
        Map<String, Object> bulk = Map.of("ids", List.of(app), "decision", "ADMITTED", "note", "Welcome", "commit", false);
        Map<String, Object> preview = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/admission/bulk", bulk));
        assertThat(((Number) preview.get("ok")).intValue()).isZero();
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/eligibility", Map.of("eligible", false)))).isEqualTo("JUPEB_REASON");
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/eligibility", Map.of("eligible", true)));
        assertThat(((Number) ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/admission/bulk", bulk)).get("ok")).intValue()).isEqualTo(1);
        Map<String, Object> commit = new LinkedHashMap<>(bulk);
        commit.put("commit", true);
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/admission/bulk", commit));

        // ── admission status checking: the decision is not shown until the checking fee is paid while checking is open ──
        mine = ok(it.get(me, "/api/v1/jupeb/me"));
        assertThat(mine.get("state")).isEqualTo("UNDER_REVIEW");
        assertThat(mine.get("admission_ref")).isNull();
        assertThat(mine).doesNotContainKey("fees");
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=STATUS_CHECKING", null))).isEqualTo("JUPEB_CHECKING_CLOSED");
        ok(it.call(ict, HttpMethod.POST, "/api/v1/portal-windows/" + CHECKING, Map.of("session", session, "action", "OPEN")));
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=ACCEPTANCE", null))).isEqualTo("JUPEB_ACCEPTANCE_NOT_YET");
        Map<String, Object> chk = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=STATUS_CHECKING", null));
        assertThat(new BigDecimal(String.valueOf(chk.get("amount")))).isEqualByComparingTo("1000");
        ok(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/fees/payments/" + chk.get("reference") + "/confirm", teller));
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=STATUS_CHECKING", null))).isEqualTo("JUPEB_FEE_PAID");
        mine = ok(it.get(me, "/api/v1/jupeb/me"));
        assertThat(mine.get("state")).isEqualTo("ADMITTED");
        assertThat(((Map<String, Object>) mine.get("statusChecking")).get("status")).isEqualTo("ADMITTED");
        assertThat(String.valueOf(mine.get("admission_ref"))).startsWith("JUPEB/ADM/");

        // ── acceptance: ₦15,000, before the school fees; then the acceptance can no longer be withdrawn ──
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=SCHOOL_FIRST", null))).isEqualTo("JUPEB_ACCEPTANCE_FIRST");
        Map<String, Object> acc = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=ACCEPTANCE", null));
        assertThat(new BigDecimal(String.valueOf(acc.get("amount")))).isEqualByComparingTo("15000");
        ok(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/fees/payments/" + acc.get("reference") + "/confirm", teller));
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/admission", Map.of("decision", "NOT_ADMITTED"))))
                .isEqualTo("JUPEB_ADMISSION_PAID");
        mine = ok(it.get(me, "/api/v1/jupeb/me"));
        assertThat(mine.get("accepted_at")).isNotNull();

        // ── the school fee: Science (the Bursary's faculty), indigene (Benue): ₦195,000, 70% then 30% ──
        Map<String, Object> fees = (Map<String, Object>) mine.get("fees");
        assertThat(fees.get("category")).isEqualTo("SCIENCE");
        assertThat(fees.get("indigene")).isEqualTo(true);
        assertThat(new BigDecimal(String.valueOf(fees.get("total")))).isEqualByComparingTo("195000");
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=SCHOOL_SECOND", null))).isEqualTo("JUPEB_FEE_ORDER");
        Map<String, Object> first = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=SCHOOL_FIRST", null));
        assertThat(new BigDecimal(String.valueOf(first.get("amount")))).isEqualByComparingTo("136500");
        // a later change by the Bursary does not rewrite a fee already charged
        Map<String, Object> raised = new LinkedHashMap<>(rule);
        raised.put("schoolFees", List.of(Map.of("category", "OTHER", "indigene", true, "amount", 180000), Map.of("category", "SCIENCE", "indigene", true, "amount", 300000),
                Map.of("category", "OTHER", "indigene", false, "amount", 200000), Map.of("category", "SCIENCE", "indigene", false, "amount", 215000)));
        ok(it.call(bursar, HttpMethod.PUT, "/api/v1/jupeb/fees", raised));
        ok(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/fees/payments/" + first.get("reference") + "/confirm", teller));
        mine = ok(it.get(me, "/api/v1/jupeb/me"));
        assertThat(mine.get("state")).isEqualTo("STUDENT");
        fees = (Map<String, Object>) mine.get("fees");
        assertThat(new BigDecimal(String.valueOf(fees.get("total")))).isEqualByComparingTo("195000");
        assertThat(new BigDecimal(String.valueOf(fees.get("outstanding")))).isEqualByComparingTo("58500");
        assertThat(fees.get("status")).isEqualTo("PARTIALLY_PAID");
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=SCHOOL_FULL", null))).isEqualTo("JUPEB_FEE_ORDER");
        Map<String, Object> second = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=SCHOOL_SECOND", null));
        assertThat(new BigDecimal(String.valueOf(second.get("amount")))).isEqualByComparingTo("58500");

        // ── the student registers the combination chosen on the application — or another offered one of their stream (V341, V342) ──
        UUID nonScience = jdbc.sql("SELECT id FROM jupeb.combination WHERE code = 'SC-001'").query(UUID.class).single();
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/register-subjects", Map.of("combination", nonScience)))).isEqualTo("JUPEB_COMBINATION_STREAM");
        assertThat((List<Map<String, Object>>) mine.get("combinations")).anySatisfy(c -> assertThat(c.get("code")).isEqualTo(comb));
        mine = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/register-subjects", null));
        assertThat((List<Map<String, Object>>) mine.get("registered")).extracting(r -> r.get("code"))
                .containsExactlyInAnyOrder("ZZM" + tag, "ZZP" + tag, "ZZC" + tag);
        ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/register-subjects", null));
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.subject_registration WHERE application_id = :a").param("a", app).query(Integer.class).single()).isEqualTo(3);

        // ── the Board's examination numbers: by application number; a surname that disagrees is held for review; invalid stops the commit ──
        String examNo = "ZZJ" + tag + "01";
        Map<String, Object> rows = Map.of("rows", List.of(Map.of("row", 2, "applicationNo", number, "examNo", examNo, "surname", "Somebody"),
                Map.of("row", 3, "applicationNo", "JUPEB/APP/1999/999999", "examNo", examNo + "X")), "commit", true, "fileName", "numbers.xlsx");
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/exam-numbers/import", rows))).isEqualTo("JUPEB_IMPORT_INVALID");
        Map<String, Object> review = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/exam-numbers/import",
                Map.of("rows", List.of(Map.of("row", 2, "applicationNo", number, "examNo", examNo, "surname", "Somebody")), "commit", true)));
        assertThat(((Number) review.get("review")).intValue()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT exam_no FROM jupeb.application WHERE id = :a").param("a", app).query(String.class).optional().orElse(null)).isNull();
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/exam-numbers/import",
                Map.of("rows", List.of(Map.of("row", 2, "applicationNo", number, "examNo", examNo, "surname", "ZZJUPEB")), "commit", true)));
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/exam-no", Map.of("examNo", examNo + "B"))))
                .isEqualTo("JUPEB_EXAM_NO_REASON");
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/exam-no", Map.of("examNo", examNo + "B", "reason", "The Board corrected the number")));
        Map<String, Object> detail = ok(it.get(office, "/api/v1/jupeb/office/applications/" + app));
        assertThat((List<Map<String, Object>>) detail.get("examNoHistory")).extracting(h -> h.get("new_no")).containsExactly(examNo, examNo + "B");
        String held = examNo + "B";

        // ── the list for the Board: students whose subjects are registered, those without a number by default (V345) ──
        Map<String, Object> boardAll = ok(it.get(office, ub -> ub.path("/api/v1/jupeb/office/exam-number-list").queryParam("session", session).queryParam("which", "all").build()));
        assertThat((List<Map<String, Object>>) boardAll.get("rows")).anySatisfy(r -> {
            assertThat(r.get("application_no")).isEqualTo(number);
            assertThat((List<String>) r.get("subject_codes")).containsExactlyInAnyOrder("ZZM" + tag, "ZZP" + tag, "ZZC" + tag);
        });
        Map<String, Object> boardPending = ok(it.get(office, ub -> ub.path("/api/v1/jupeb/office/exam-number-list").queryParam("session", session).build()));
        assertThat((List<Map<String, Object>>) boardPending.get("rows")).noneMatch(r -> number.equals(r.get("application_no")));
        assertThat(status(it.get(bursar, "/api/v1/jupeb/office/exam-number-list"))).isEqualTo(403);

        // ── results: imported whole, shown to the candidate only once published ──
        Map<String, Object> grades = Map.of("rows", List.of(Map.of("row", 2, "examNo", held, "subject", "ZZM" + tag, "grade", "A"),
                Map.of("row", 3, "examNo", held, "subject", "ZZP" + tag, "grade", "B"), Map.of("row", 4, "examNo", held, "subject", "ZZC" + tag, "grade", "C")), "commit", true);
        assertThat(((Number) ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/results/import", grades)).get("applied")).intValue()).isEqualTo(3);
        assertThat(((List<Map<String, Object>>) ok(it.get(me, "/api/v1/jupeb/me")).get("registered"))).allMatch(r -> !r.containsKey("grade"));
        Map<String, Object> fix = Map.of("rows", List.of(Map.of("row", 2, "examNo", held, "subject", "ZZM" + tag, "grade", "B")), "commit", true);
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/results/import", fix))).isEqualTo("JUPEB_IMPORT_INVALID");
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/results/publish", Map.of("session", session)));
        mine = ok(it.get(me, "/api/v1/jupeb/me"));
        assertThat(mine.get("state")).isEqualTo("COMPLETED");
        assertThat((List<Map<String, Object>>) mine.get("registered")).extracting(r -> r.get("grade")).containsExactlyInAnyOrder("A", "B", "C");

        // ── V343: the published statement of result verifies; a later correction marks it superseded; a revoked paper no longer verifies ──
        String statement = String.valueOf(ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/papers", Map.of("kind", "RESULT"))).get("code"));
        assertThat(ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/papers", Map.of("kind", "RESULT"))).get("code")).isEqualTo(statement);
        verified = ok(it.anon(HttpMethod.GET, "/api/v1/verify/jupeb/" + statement, null));
        assertThat(verified.get("current")).isEqualTo(true);
        assertThat(((Map<String, Object>) verified.get("facts")).get("gradePoint")).isEqualTo("13/16");
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/results/import", Map.of("rows",
                List.of(Map.of("row", 2, "examNo", held, "subject", "ZZM" + tag, "grade", "B", "reason", "The Board corrected the grade")), "commit", true)));
        verified = ok(it.anon(HttpMethod.GET, "/api/v1/verify/jupeb/" + statement, null));
        assertThat(verified.get("genuine")).isEqualTo(true);
        assertThat(verified.get("current")).isEqualTo(false);
        assertThat(((Map<String, Object>) verified.get("currentFacts")).get("gradePoint")).isEqualTo("12/16");
        String slip = String.valueOf(ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/papers", Map.of("kind", "REGISTRATION_SLIP"))).get("code"));
        assertThat(status(it.call(me, HttpMethod.POST, "/api/v1/jupeb/office/papers/" + slip + "/revoke", Map.of("reason", "Issued in error")))).isEqualTo(403);
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/papers/" + slip + "/revoke", Map.of("reason", "no")))).isEqualTo("JUPEB_PAPER_REASON");
        Map<String, Object> afterRevoke = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/papers/" + slip + "/revoke", Map.of("reason", "Printed before the correction")));
        assertThat((List<Map<String, Object>>) afterRevoke.get("papers")).anySatisfy(pp -> {
            assertThat(pp.get("code")).isEqualTo(slip);
            assertThat(pp.get("revoked_at")).isNotNull();
        });
        verified = ok(it.anon(HttpMethod.GET, "/api/v1/verify/jupeb/" + slip, null));
        assertThat(verified.get("genuine")).isEqualTo(false);
        assertThat(verified.get("revoked")).isEqualTo(true);
        // a completed candidate asks for no change
        assertThat(code(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/requests", Map.of("kind", "WITHDRAW", "reason", "I want to withdraw now")))).isEqualTo("JUPEB_CHANGE_CLOSED");

        // ── V343: reminders — the JUPEB Office's rules, who is due, sending now; nobody else sets them ──
        Map<String, Object> reminders = ok(it.get(office, "/api/v1/jupeb/office/reminders"));
        assertThat((List<Map<String, Object>>) reminders.get("rules")).extracting(r -> r.get("kind"))
                .containsExactly("FEE_UNPAID", "SUBMIT_PENDING", "PASSPORT_MISSING", "CHECKING_OPEN", "ACCEPTANCE_UNPAID", "SCHOOL_FEE_UNPAID", "ATTENDANCE_LOW");
        Map<String, Object> reminderRule = Map.of("enabled", true, "firstAfterDays", 2, "everyDays", 3, "maxCount", 3, "sms", false);
        assertThat(status(it.call(bursar, HttpMethod.PUT, "/api/v1/jupeb/office/reminders/FEE_UNPAID", reminderRule))).isEqualTo(403);
        assertThat(status(it.call(office, HttpMethod.PUT, "/api/v1/jupeb/office/reminders/NO_SUCH", reminderRule))).isEqualTo(404);
        ok(it.call(office, HttpMethod.PUT, "/api/v1/jupeb/office/reminders/FEE_UNPAID", reminderRule));
        assertThat(it.getList(office, "/api/v1/jupeb/office/reminders/due").getStatusCode().value()).isEqualTo(200);
        assertThat(String.valueOf(ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/reminders/run", null)).get("result"))).contains("\"sent\"");

        // ── support: the candidate's ticket reaches the JUPEB queue; the category is not offered to students and staff ──
        Map<String, Object> ticket = ok(it.call(me, HttpMethod.POST, "/api/v1/jupeb/me/support",
                Map.of("category", "JUPEB", "subject", "My result", "description", "Please confirm my result.", "details", Map.of("jupeb_issue", "Results"))));
        assertThat(jdbc.sql("SELECT queue_code FROM helpdesk.ticket WHERE id = :t").param("t", UUID.fromString(String.valueOf(ticket.get("id")))).query(String.class).single())
                .isEqualTo("JUPEB_SUPPORT");
        assertThat((List<Map<String, Object>>) ok(it.get(me, "/api/v1/jupeb/me/support")).get("tickets")).hasSize(1);
        assertThat(it.getList(ItSupport.token("student"), "/api/v1/helpdesk/categories").getBody()).noneMatch(c -> "JUPEB".equals(((Map) c).get("code")));

        // ── the trail: every step on the candidate's own timeline, and each told by email ──
        assertThat((List<Map<String, Object>>) detail.get("events")).extracting(e -> e.get("kind"))
                .contains("CREATED", "APPLICATION_FEE_CONFIRMED", "SUBMITTED", "RETURNED", "ELIGIBLE", "ADMITTED", "STATUS_CHECKING_CONFIRMED", "ACCEPTANCE_CONFIRMED",
                          "SCHOOL_FEE_CONFIRMED", "STUDENT", "SUBJECTS_REGISTERED", "EXAM_NO_ASSIGNED");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :a AND channel = 'EMAIL'").param("a", app).query(Integer.class).single()).isGreaterThanOrEqualTo(8);
    }

    /** V345: the old portal's registered students, uploaded with logins: judged first, the App No as the username, a temporary password changed at first sign-in */
    @Test
    @SuppressWarnings("unchecked")
    void oldPortalStudentsAreUploadedWithLogins() {
        String app1 = "S0" + tag + "000001", app2 = "S0" + tag + "000002";
        String mail = "zzold." + tag.toLowerCase() + "@example.com";
        List<Map<String, Object>> rows = List.of(
                oldRow(2, "appNo", app1, "firstName", "IWANGER", "middleName", "JOY", "surname", "UVA", "sex", "Female", "lga", "Ukum", "phone", "7052428202",
                        "state", "Benue", "dob", "9/1/2004", "nin", "13181803004", "email", "zzbroken." + tag.toLowerCase() + "@gmail."),
                oldRow(3, "appNo", app2, "firstName", "Paul", "middleName", "Shater", "surname", "Kegh", "sex", "Male", "lga", "Gboko", "phone", "8089894004",
                        "state", "Benue", "dob", "21/10/2006", "nin", "1171459604", "email", mail));
        Map<String, Object> in = new LinkedHashMap<>();
        in.put("rows", rows);
        in.put("session", session);
        in.put("dayFirst", true);
        in.put("commit", false);
        in.put("fileName", "old-portal.xlsx");
        in.put("emailLinks", true);
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in))).isEqualTo(403);
        Map<String, Object> preview = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in));
        List<Map<String, Object>> judged = (List<Map<String, Object>>) preview.get("rows");
        assertThat(judged.get(0).get("status")).isEqualTo("INVALID");
        assertThat(String.valueOf(judged.get(0).get("message"))).contains("is not valid");
        assertThat(judged.get(1).get("status")).isEqualTo("REVIEW");   // the NIN of ten digits is left out and said
        assertThat(judged.get(1).get("phone")).isEqualTo("08089894004");
        assertThat(judged.get(1).get("dob")).isEqualTo("2006-10-21");
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.application WHERE application_no = :n").param("n", app2).query(Integer.class).single()).isZero();

        in.put("commit", true);
        Map<String, Object> done = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in));
        assertThat(((Number) done.get("applied")).intValue()).isEqualTo(1);
        List<Map<String, Object>> creds = (List<Map<String, Object>>) done.get("credentials");
        assertThat(creds).hasSize(1);
        String temporary = String.valueOf(creds.get(0).get("password"));
        assertThat(creds.get(0).get("applicationNo")).isEqualTo(app2);
        assertThat(temporary).hasSize(10);
        UUID created = jdbc.sql("SELECT id FROM jupeb.application WHERE application_no = :n").param("n", app2).query(UUID.class).single();
        assertThat(jdbc.sql("SELECT state || '/' || legacy_source || '/' || (nin IS NULL) FROM jupeb.application WHERE id = :a").param("a", created).query(String.class).single())
                .isEqualTo("STUDENT/OLD_PORTAL/true");
        // the temporary password is not kept readable; the student was emailed a link, not the password
        assertThat(jdbc.sql("SELECT password_hash FROM jupeb.account acc JOIN jupeb.application a ON a.account_id = acc.id WHERE a.id = :a").param("a", created)
                .query(String.class).single()).startsWith("$2").doesNotContain(temporary);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :a AND channel = 'EMAIL' AND body LIKE '%/jupeb/reset?token=%' AND body NOT LIKE '%' || :p || '%'")
                .param("a", created).param("p", temporary).query(Integer.class).single()).isEqualTo(1);

        // the student signs in on the old App No with the temporary password, and must choose their own first
        Map<String, Object> signed = ok(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", app2.toLowerCase(), "password", temporary)));
        String token = String.valueOf(signed.get("token"));
        Map<String, Object> mine = ok(it.get(token, "/api/v1/jupeb/me"));
        assertThat(mine.get("must_change_password")).isEqualTo(true);
        assertThat(mine.get("legacy_ref")).isEqualTo(app2);
        assertThat(code(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/password", Map.of("currentPassword", "wrong-password", "newPassword", "MyOwnPass2026"))))
                .isEqualTo("JUPEB_PASSWORD_CURRENT");
        mine = ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/password", Map.of("currentPassword", temporary, "newPassword", "MyOwnPass2026")));
        assertThat(mine.get("must_change_password")).isEqualTo(false);
        assertThat(status(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", app2, "password", temporary)))).isEqualTo(422);
        assertThat(status(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", mail, "password", "MyOwnPass2026")))).isEqualTo(200);

        // the same file again adds nothing twice; no fee reminder goes to a student from the old portal
        in.put("commit", false);
        List<Map<String, Object>> again = (List<Map<String, Object>>) ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in)).get("rows");
        assertThat(again.get(1).get("status")).isEqualTo("EXISTS");
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.due_reminders(now() + interval '60 days') d WHERE d.application_id = :a AND d.kind = 'SCHOOL_FEE_UNPAID'")
                .param("a", created).query(Integer.class).single()).isZero();
    }

    /** V347: ICT Support on JUPEB records, the old portal's payments, the student's own contact details and corrections, the timetable, practice tests, the reports */
    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void supportOldPaymentsSelfServiceTimetablePracticeAndReports() {
        // a student from the old portal, signed in with their own password
        String appNo = "S7" + tag + "03";
        Map<String, Object> in = new LinkedHashMap<>();
        in.put("rows", List.of(oldRow(2, "appNo", appNo, "firstName", "Ngozi", "surname", "Terkimbi", "sex", "Female", "phone", "08055556666", "dob", "3/4/2006",
                "email", "zzv347." + tag.toLowerCase() + "@example.com")));
        in.put("session", session);
        in.put("dayFirst", true);
        in.put("commit", true);
        in.put("fileName", "old.xlsx");
        in.put("emailLinks", false);
        Map<String, Object> done = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in));
        String temporary = String.valueOf(((List<Map<String, Object>>) done.get("credentials")).get(0).get("password"));
        UUID app = jdbc.sql("SELECT id FROM jupeb.application WHERE application_no = :n").param("n", appNo).query(UUID.class).single();
        String token = String.valueOf(ok(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", appNo, "password", temporary))).get("token"));
        ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/password", Map.of("currentPassword", temporary, "newPassword", "Practice2026!")));
        it.db(() -> jdbc.sql("SELECT jupeb.register_subjects(:a, :a, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'))").param("a", app).query(Integer.class).single());

        // the student keeps their own contact details, never without a phone; a correction of identity waits for the office
        Map<String, Object> contact = new LinkedHashMap<>(Map.of("phone", "08077778888", "contactAddress", "No. 3 Hostel Road, Makurdi", "nextOfKinName", "Mrs Terkimbi"));
        Map<String, Object> mine = ok(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/contact", contact));
        assertThat(mine.get("phone")).isEqualTo("08077778888");
        assertThat(code(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/contact", Map.of("contactAddress", "Nowhere")))).isEqualTo("JUPEB_PHONE_REQUIRED");
        mine = ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/corrections", Map.of("changes", Map.of("surname", "Terkimbi-Ade", "nin", "12345678901"),
                "reason", "My surname changed by marriage; the NIN was never entered")));
        assertThat(String.valueOf(mine.get("surname"))).isEqualTo("TERKIMBI");
        Map<String, Object> pending = ((List<Map<String, Object>>) mine.get("requests")).get(0);
        assertThat(pending.get("kind")).isEqualTo("CORRECT_DETAILS");
        assertThat(String.valueOf(pending.get("words"))).contains("surname").contains("TERKIMBI-ADE");
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/requests/" + pending.get("id") + "/decide", Map.of("approve", true, "note", "Marriage certificate sighted")));
        assertThat(jdbc.sql("SELECT surname || '/' || nin FROM jupeb.application WHERE id = :a").param("a", app).query(String.class).single()).isEqualTo("TERKIMBI-ADE/12345678901");

        // the old portal's payments: the Bursary does not post them; a preview writes nothing; posted once as a confirmed fee
        Map<String, Object> pay = new LinkedHashMap<>();
        pay.put("rows", List.of(oldRow(2, "appNo", appNo, "reference", "OLD-" + tag + "-1", "purpose", "School Fees 1st Instalment", "amount", "75000", "date", "12/11/2024", "status", "Success"),
                oldRow(3, "appNo", appNo, "reference", "OLD-" + tag + "-2", "purpose", "School Fees 2nd Instalment", "amount", "50000", "date", "12/02/2025", "status", "Pending"),
                oldRow(4, "appNo", appNo, "reference", "OLD-" + tag + "-3", "purpose", "School Fees", "amount", "30000", "date", "14/02/2025", "status", "Success")));
        pay.put("dayFirst", true);
        pay.put("commit", false);
        pay.put("fileName", "payments.xlsx");
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-payments/import", pay))).isEqualTo(403);
        Map<String, Object> previewed = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-payments/import", pay));
        assertThat(((Number) previewed.get("valid")).intValue()).isEqualTo(1);
        assertThat(((Number) previewed.get("invalid")).intValue()).isEqualTo(1);
        // "school fees" naming no instalment, and short of the full fee, is asked about, never posted as the full fee
        assertThat(((Number) previewed.get("review")).intValue()).isEqualTo(1);
        pay.put("commit", true);
        assertThat(((Number) ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-payments/import", pay)).get("applied")).intValue()).isEqualTo(1);
        assertThat(((Number) ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-payments/import", pay)).get("applied")).intValue()).isZero();
        List<Map<String, Object>> refs = (List<Map<String, Object>>) ok(it.get(token, "/api/v1/jupeb/me")).get("references");
        assertThat(refs).extracting(r -> r.get("kind") + "/" + r.get("channel") + "/" + (r.get("confirmed_at") != null)).containsExactly("SCHOOL_FIRST/Old portal/true");
        // the old portal's first instalment (75,000) differs from the share now set: the second instalment is the balance, nothing left unpayable
        Map<String, Object> rule = new LinkedHashMap<>();
        rule.put("session", session);
        rule.put("applicationFee", 15000);
        rule.put("checkingFee", 1000);
        rule.put("acceptanceFee", 15000);
        rule.put("firstPercent", 70);
        rule.put("allowFull", true);
        rule.put("activation", "FIRST_INSTALMENT");
        rule.put("indigeneState", "Benue");
        rule.put("schoolFees", List.of(Map.of("category", "OTHER", "indigene", true, "amount", 180000), Map.of("category", "SCIENCE", "indigene", true, "amount", 195000),
                Map.of("category", "OTHER", "indigene", false, "amount", 200000), Map.of("category", "SCIENCE", "indigene", false, "amount", 215000)));
        ok(it.call(bursar, HttpMethod.PUT, "/api/v1/jupeb/fees", rule));
        Map<String, Object> owed = (Map<String, Object>) ok(it.get(token, "/api/v1/jupeb/me")).get("fees");
        BigDecimal balance = new BigDecimal(String.valueOf(owed.get("total"))).subtract(new BigDecimal("75000"));
        assertThat(new BigDecimal(String.valueOf(owed.get("outstanding")))).isEqualByComparingTo(balance);
        assertThat(new BigDecimal(String.valueOf(owed.get("second_amount")))).isNotEqualByComparingTo(balance);
        Map<String, Object> second = ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/fee-reference?kind=SCHOOL_SECOND", null));
        assertThat(new BigDecimal(String.valueOf(second.get("amount")))).isEqualByComparingTo(balance);

        // the timetable: a room is never double-booked; the student sees their subjects' slots (V354: the room is on the list)
        assertThat(status(it.callList(office, HttpMethod.POST, "/api/v1/jupeb/office/rooms", Map.of("code", "JUPEB Hall " + tag)))).isEqualTo(200);
        UUID subject = jdbc.sql("SELECT sr.subject_id FROM jupeb.subject_registration sr JOIN jupeb.subject s ON s.id = sr.subject_id WHERE sr.application_id = :a ORDER BY s.code LIMIT 1")
                .param("a", app).query(UUID.class).single();
        Map<String, Object> slot = new LinkedHashMap<>(Map.of("session", session, "semester", 1, "subjectId", subject.toString(), "weekday", 3, "startsAt", "08:00", "endsAt", "10:00", "venue", "JUPEB Hall " + tag));
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", slot));
        slot.put("startsAt", "09:00");
        slot.put("endsAt", "11:00");
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", slot))).isEqualTo("JUPEB_SLOT_CLASH");
        Map<String, Object> week = ok(it.get(token, "/api/v1/jupeb/me/timetable"));
        List<Map<String, Object>> slots = (List<Map<String, Object>>) week.get("slots");
        assertThat(slots).extracting(x -> x.get("venue")).contains("JUPEBHALL" + tag);
        // V351: the programme's day comes from the whole timetable, so the hour of this lecture is never a break
        Map<String, Object> frame = ((List<Map<String, Object>>) week.get("frames")).stream().filter(f -> Integer.valueOf(1).equals(f.get("semester"))).findFirst().orElseThrow();
        assertThat((List<Integer>) frame.get("breaks")).doesNotContain(8, 9);

        // a practice test: opened only with questions; the answer key never sent before submission; scored by the server; attempts limited
        Map<String, Object> test = new LinkedHashMap<>(Map.of("subjectId", subject.toString(), "title", "Practice " + tag, "durationMinutes", 10, "questionsPerAttempt", 2,
                "attemptsAllowed", 1, "showAnswers", true, "open", false));
        String testId = String.valueOf(ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/practice-tests", test)).get("id"));
        test.put("open", true);
        assertThat(code(it.call(office, HttpMethod.PUT, "/api/v1/jupeb/office/practice-tests/" + testId, test))).isEqualTo("JUPEB_PRACTICE_EMPTY");
        Map<String, Object> upload = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/practice-tests/" + testId + "/questions", Map.of("replace", false, "rows", List.of(
                Map.of("row", 2, "question", "The unit of force?", "a", "Newton", "b", "Joule", "c", "Watt", "answer", "A", "explanation", "F = ma, in newtons"),
                Map.of("row", 3, "question", "The unit of energy?", "a", "Newton", "b", "Joule", "answer", "B"),
                Map.of("row", 4, "question", "Broken", "a", "x", "b", "y", "answer", "E")))));
        assertThat(((Number) upload.get("added")).intValue()).isEqualTo(2);
        assertThat((List<?>) upload.get("refused")).hasSize(1);
        ok(it.call(office, HttpMethod.PUT, "/api/v1/jupeb/office/practice-tests/" + testId, test));
        Map<String, Object> paper = ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/practice/" + testId + "/start", Map.of()));
        List<Map<String, Object>> questions = (List<Map<String, Object>>) paper.get("questions");
        assertThat(questions).hasSize(2).allSatisfy(q -> assertThat(q).doesNotContainKeys("answer", "explanation", "correct"));
        String attempt = String.valueOf(((Map<String, Object>) paper.get("attempt")).get("id"));
        for (Map<String, Object> q : questions) {
            String right = String.valueOf(q.get("stem")).contains("force") ? "A" : "B";
            ok(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/practice/attempts/" + attempt + "/answers/" + q.get("id"), Map.of("choice", right)));
        }
        Map<String, Object> scored = ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/practice/attempts/" + attempt + "/submit", Map.of()));
        assertThat(((Number) ((Map<String, Object>) scored.get("attempt")).get("score")).intValue()).isEqualTo(2);
        assertThat((List<Map<String, Object>>) scored.get("questions")).allSatisfy(q -> assertThat(q).containsKeys("answer", "correct"));
        assertThat(code(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/practice/" + testId + "/start", Map.of()))).isEqualTo("JUPEB_PRACTICE_ATTEMPTS");
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.result WHERE application_id = :a").param("a", app).query(Integer.class).single()).isZero();

        // the office's report reads the session; the Bursary does not read it
        Map<String, Object> report = ok(it.get(office, "/api/v1/jupeb/office/reports?session=" + session));
        assertThat(((Number) ((Map<String, Object>) ((Map<String, Object>) report.get("enrolment")).get("totals")).get("fromOldPortal")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(report).containsKeys("fees", "attendance", "results", "practice");
        assertThat(status(it.get(bursar, "/api/v1/jupeb/office/reports?session=" + session))).isEqualTo(403);

        // ICT Support on the JUPEB record: reached only through a posting that reaches JUPEB; its acts on the ledger, on the candidate's own ticket
        UUID agentId = it.person("ZZ-JUPEB-CPO-" + tag, "ZZJUPEBCPO" + tag);
        UUID faculty = it.person("ZZ-FAC-CPO-" + tag, "ZZFACCPO" + tag);
        it.db(() -> {
            jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'JUPEB_SUPPORT', 'GLOBAL', NULL, ARRAY['VIEW_STUDENT','EDIT_CONTACT','RESET_PASSWORD','VIEW_PAYMENTS'])")
                    .param("p", agentId).update();
            return jdbc.sql("INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (:p, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['VIEW_STUDENT','RESET_PASSWORD'])")
                    .param("p", faculty).update();
        });
        String cpo = TestTokens.token(agentId, List.of("ictagent"));
        String outsider = TestTokens.token(faculty, List.of("ictagent"));
        assertThat(status(it.get(outsider, "/api/v1/helpdesk/support/jupeb/" + app))).isEqualTo(404);
        assertThat(code(it.get(outsider, "/api/v1/helpdesk/support/jupeb?q=" + appNo))).isEqualTo("SUPPORT_JUPEB_SCOPE");
        assertThat((List<Map>) ok(it.get(cpo, "/api/v1/helpdesk/support/jupeb?q=" + appNo)).get("rows")).extracting(r -> String.valueOf(r.get("id"))).containsExactly(app.toString());
        Map<String, Object> rec = ok(it.get(cpo, "/api/v1/helpdesk/support/jupeb/" + app));
        assertThat(rec).containsKeys("record", "payments", "tickets", "actions", "account");
        Map<String, Object> fix = new LinkedHashMap<>(Map.of("phone", "08099990000", "contactAddress", "No. 3 Hostel Road, Makurdi", "nextOfKinName", "Mrs Terkimbi", "reason", "The candidate's new line, confirmed by call"));
        ok(it.call(cpo, HttpMethod.PUT, "/api/v1/helpdesk/support/jupeb/" + app + "/contact", fix));
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE jupeb_application_id = :a AND action = 'CONTACT_EDITED' AND student_id IS NULL").param("a", app).query(Integer.class).single()).isEqualTo(1);
        assertThat(code(it.call(cpo, HttpMethod.POST, "/api/v1/helpdesk/support/jupeb/" + app + "/tickets", Map.of("subject", "x", "description", "y")))).isEqualTo("SUPPORT_CAPABILITY");
        assertThat(code(it.call(cpo, HttpMethod.POST, "/api/v1/helpdesk/support/jupeb/" + app + "/password", Map.of("method", "TEMPORARY", "reason", "At the desk")))).isEqualTo("SUPPORT_TICKET_REQUIRED");
        String ticket = String.valueOf(ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/support", Map.of("category", "JUPEB", "subject", "I cannot sign in",
                "description", "My password stopped working", "details", Map.of("jupeb_issue", "Other")))).get("id"));
        Map<String, Object> reset = ok(it.call(cpo, HttpMethod.POST, "/api/v1/helpdesk/support/jupeb/" + app + "/password", Map.of("method", "TEMPORARY", "reason", "Identity checked at the desk", "ticket", ticket)));
        String tempPw = String.valueOf(reset.get("temporaryPassword"));
        assertThat(tempPw).hasSize(12);
        assertThat(status(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", appNo, "password", "Practice2026!")))).isNotEqualTo(200);
        Map<String, Object> once = ok(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", appNo, "password", tempPw)));
        assertThat(once).containsKey("token");
        assertThat(code(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", appNo, "password", tempPw)))).isEqualTo("AUTH_TEMP_PASSWORD_SPENT");
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.support_action WHERE jupeb_application_id = :a AND action = 'PASSWORD_RESET' AND method = 'TEMPORARY_PASSWORD' AND new_value IS NULL AND ticket_id = :t")
                .param("a", app).param("t", UUID.fromString(ticket)).query(Integer.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM helpdesk.ticket_event WHERE ticket_id = :t AND action = 'SUPPORT_PASSWORD_RESET'").param("t", UUID.fromString(ticket)).query(Integer.class).single()).isEqualTo(1);
    }

    /** V349: the office's announcements, a practice question with a formula and an image, the identity card */
    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void announcementsPracticeImagesAndIdentityCard() {
        String appNo = "S9" + tag + "04";
        Map<String, Object> in = new LinkedHashMap<>();
        in.put("rows", List.of(oldRow(2, "appNo", appNo, "firstName", "Aondo", "surname", "Iorkyaa", "sex", "Male", "phone", "08066667777", "dob", "3/4/2006",
                "email", "zzv349." + tag.toLowerCase() + "@example.com")));
        in.put("session", session);
        in.put("dayFirst", true);
        in.put("commit", true);
        in.put("fileName", "old.xlsx");
        in.put("emailLinks", false);
        Map<String, Object> done = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in));
        String temporary = String.valueOf(((List<Map<String, Object>>) done.get("credentials")).get(0).get("password"));
        UUID app = jdbc.sql("SELECT id FROM jupeb.application WHERE application_no = :n").param("n", appNo).query(UUID.class).single();
        String token = String.valueOf(ok(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", appNo, "password", temporary))).get("token"));
        ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/password", Map.of("currentPassword", temporary, "newPassword", "Announce2026!")));
        it.db(() -> jdbc.sql("SELECT jupeb.register_subjects(:a, :a, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'))").param("a", app).query(Integer.class).single());
        UUID otherClass = it.db(() -> jdbc.sql("INSERT INTO jupeb.class (session, name) VALUES (:s, :n) RETURNING id").param("s", session).param("n", "ZZ Class " + tag).query(UUID.class).single());

        // announcements: the Bursary does not publish; the reach is told first; a class the student is not in does not reach them
        Map<String, Object> notice = new LinkedHashMap<>(Map.of("session", session, "audience", "STUDENTS", "title", "Mid-semester test " + tag,
                "body", "The mid-semester test holds on Friday at 9 a.m. in the JUPEB Hall.", "email", true, "pinned", true));
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/office/announcements", notice))).isEqualTo(403);
        int reach = ((Number) ok(it.get(office, "/api/v1/jupeb/office/announcements/reach?session=" + session + "&audience=STUDENTS")).get("count")).intValue();
        assertThat(reach).isGreaterThanOrEqualTo(1);
        Map<String, Object> published = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/announcements", notice));
        assertThat(((Number) published.get("reach")).intValue()).isEqualTo(reach);
        assertThat(((Number) published.get("notified")).intValue()).isEqualTo(reach);
        String noticeId = String.valueOf(published.get("id"));
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/announcements", Map.of("session", session, "audience", "CLASS", "audienceRef", otherClass.toString(),
                "title", "For another class " + tag, "body", "Only that class reads this.")));
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/announcements", Map.of("session", session, "audience", "CLASS", "audienceRef", UUID.randomUUID().toString(),
                "title", "No such class", "body", "Refused.")))).isEqualTo("JUPEB_ANNOUNCE_AUDIENCE");
        List<Map<String, Object>> mine = (List<Map<String, Object>>) ok(it.get(token, "/api/v1/jupeb/me/announcements")).get("announcements");
        assertThat(mine).extracting(a -> String.valueOf(a.get("title"))).contains("Mid-semester test " + tag).doesNotContain("For another class " + tag);
        assertThat(((Number) ok(it.get(token, "/api/v1/jupeb/me")).get("unreadAnnouncements")).intValue()).isGreaterThanOrEqualTo(1);
        int before = ((Number) ok(it.get(token, "/api/v1/jupeb/me")).get("unreadAnnouncements")).intValue();
        ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/announcements/" + noticeId + "/read", Map.of()));
        assertThat(((Number) ok(it.get(token, "/api/v1/jupeb/me")).get("unreadAnnouncements")).intValue()).isEqualTo(before - 1);
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/announcements/" + noticeId + "/withdraw", Map.of("reason", "The test moved to Monday")));
        mine = (List<Map<String, Object>>) ok(it.get(token, "/api/v1/jupeb/me/announcements")).get("announcements");
        assertThat(mine).extracting(a -> String.valueOf(a.get("title"))).doesNotContain("Mid-semester test " + tag);

        // a practice question typed with a formula and an image; seen by a student only inside an attempt that drew it; an answered question is versioned, never rewritten
        UUID subject = jdbc.sql("SELECT sr.subject_id FROM jupeb.subject_registration sr JOIN jupeb.subject s ON s.id = sr.subject_id WHERE sr.application_id = :a ORDER BY s.code LIMIT 1")
                .param("a", app).query(UUID.class).single();
        Map<String, Object> test = new LinkedHashMap<>(Map.of("subjectId", subject.toString(), "title", "Energy " + tag, "durationMinutes", 10, "questionsPerAttempt", 1,
                "attemptsAllowed", 2, "showAnswers", true, "open", false));
        String testId = String.valueOf(ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/practice-tests", test)).get("id"));
        String base = "/api/v1/jupeb/office/practice-tests/" + testId + "/questions";
        String q1 = String.valueOf(ok(it.call(office, HttpMethod.POST, base + "/add", Map.of("row", Map.of("question", "The kinetic energy of a body is",
                "a", "$mv$", "b", "$\\frac{1}{2}mv^2$", "answer", "B")))).get("id"));
        assertThat(code(it.call(office, HttpMethod.POST, base + "/add", Map.of("row", Map.of("question", "Broken", "a", "x", "b", "y", "answer", "D"))))).isEqualTo("JUPEB_PRACTICE_QUESTION");
        byte[] png = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 'I', 'H', 'D', 'R'};
        assertThat(code(it.call(office, HttpMethod.POST, base + "/" + q1 + "/image", Map.of("filename", "d.png", "contentType", "image/png",
                "base64", java.util.Base64.getEncoder().encodeToString("not a png".getBytes()))))).isEqualTo("JUPEB_DOC_TYPE");
        ok(it.call(office, HttpMethod.POST, base + "/" + q1 + "/image", Map.of("filename", "diagram.png", "contentType", "image/png", "base64", java.util.Base64.getEncoder().encodeToString(png))));
        assertThat(it.getBytes(office, base + "/" + q1 + "/image").getBody()).isEqualTo(png);
        test.put("open", true);
        ok(it.call(office, HttpMethod.PUT, "/api/v1/jupeb/office/practice-tests/" + testId, test));
        Map<String, Object> paper = ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/practice/" + testId + "/start", Map.of()));
        String attempt = String.valueOf(((Map<String, Object>) paper.get("attempt")).get("id"));
        Map<String, Object> q = ((List<Map<String, Object>>) paper.get("questions")).get(0);
        assertThat(q.get("image")).isEqualTo(true);
        assertThat(String.valueOf(q.get("stem"))).isEqualTo("The kinetic energy of a body is");
        assertThat(it.getBytes(token, "/api/v1/jupeb/me/practice/attempts/" + attempt + "/questions/" + q1 + "/image").getBody()).isEqualTo(png);
        assertThat(status(it.get(token, "/api/v1/jupeb/me/practice/attempts/" + UUID.randomUUID() + "/questions/" + q1 + "/image"))).isEqualTo(404);
        ok(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/practice/attempts/" + attempt + "/answers/" + q1, Map.of("choice", "B")));
        ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/practice/attempts/" + attempt + "/submit", Map.of()));
        Map<String, Object> edited = ok(it.call(office, HttpMethod.PUT, base + "/" + q1, Map.of("row", Map.of("question", "The kinetic energy of a moving body is",
                "a", "$mv$", "b", "$\\frac{1}{2}mv^2$", "c", "$mgh$", "answer", "B"))));
        assertThat(edited.get("newVersion")).isEqualTo(true);
        String q2 = String.valueOf(edited.get("id"));
        assertThat(it.getBytes(office, base + "/" + q2 + "/image").getBody()).isEqualTo(png);
        Map<String, Object> review = ok(it.get(token, "/api/v1/jupeb/me/practice/attempts/" + attempt));
        assertThat(String.valueOf(((List<Map<String, Object>>) review.get("questions")).get(0).get("stem"))).isEqualTo("The kinetic energy of a body is");
        assertThat(((Number) ((Map<String, Object>) review.get("attempt")).get("score")).intValue()).isEqualTo(1);

        // the identity card: an active student with a passport photograph; verifiable; replaced when lost, the old code then refused
        assertThat(code(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/id-card", Map.of()))).isEqualTo("JUPEB_ID_CARD_PHOTO");
        it.db(() -> {
            UUID doc = jdbc.sql("INSERT INTO jupeb.document (application_id, kind, filename, content_type, size_bytes) VALUES (:a, 'PASSPORT', 'p.png', 'image/png', 16) RETURNING id")
                    .param("a", app).query(UUID.class).single();
            return jdbc.sql("INSERT INTO jupeb.document_blob (document_id, bytes) VALUES (:d, :b)").param("d", doc).param("b", png).update();
        });
        String card = String.valueOf(ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/id-card", Map.of())).get("code"));
        assertThat(ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/id-card", Map.of())).get("code")).isEqualTo(card);
        Map<String, Object> verified = ok(it.anon(HttpMethod.GET, "/api/v1/verify/jupeb/" + card, null));
        assertThat(verified.get("genuine")).isEqualTo(true);
        assertThat(verified.get("kind")).isEqualTo("ID_CARD");
        assertThat(((Map<String, Object>) verified.get("facts")).get("validFor")).isEqualTo(session);
        assertThat((Map<String, Object>) verified.get("facts")).doesNotContainKeys("nin", "dateOfBirth", "phone", "email");
        assertThat(status(it.get(bursar, "/api/v1/jupeb/office/id-cards?session=" + session))).isEqualTo(403);
        List<Map<String, Object>> students = (List<Map<String, Object>>) ok(it.get(office, "/api/v1/jupeb/office/id-cards?session=" + session)).get("students");
        assertThat(students).filteredOn(r -> app.toString().equals(String.valueOf(r.get("id")))).extracting(r -> r.get("card_code")).containsExactly(card);
        Map<String, Object> issued = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/id-cards/issue", Map.of("ids", List.of(app.toString(), UUID.randomUUID().toString()))));
        assertThat((List<Map<String, Object>>) issued.get("cards")).extracting(c -> c.get("code")).containsExactly(card);
        assertThat((List<?>) issued.get("skipped")).hasSize(1);
        String fresh = String.valueOf(ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/id-cards/" + app + "/replace", Map.of("reason", "Lost at the hostel"))).get("code"));
        assertThat(fresh).isNotEqualTo(card);
        Map<String, Object> old = ok(it.anon(HttpMethod.GET, "/api/v1/verify/jupeb/" + card, null));
        assertThat(old.get("genuine")).isEqualTo(false);
        assertThat(old.get("revoked")).isEqualTo(true);
        assertThat(ok(it.anon(HttpMethod.GET, "/api/v1/verify/jupeb/" + fresh, null)).get("genuine")).isEqualTo(true);
    }

    /** V351: the JUPEB programme's own current session; the timetable's course codes and practicals, lectures in other rooms side by side */
    @Test
    @SuppressWarnings("unchecked")
    void ownCurrentSessionAndTheBoardsTimetable() {
        String named = jdbc.sql("SELECT current_session FROM jupeb.setting WHERE session = '*'").query(String.class).optional().orElse(null);
        String university = jdbc.sql("SELECT policy.application_session('POST_UTME_REGISTRATION')").query(String.class).single();
        String path = "/api/v1/jupeb/office/settings/current-session";
        try {
            Map<String, Object> s = ok(it.get(office, "/api/v1/jupeb/office/settings"));
            assertThat(s.get("currentSession")).isEqualTo(named == null ? university : named);
            assertThat(s.get("universitySession")).isEqualTo(university);
            // only the JUPEB Office names it, a session as 2031/2032; the University's stays as it is
            assertThat(status(it.call(bursar, HttpMethod.PUT, path, Map.of("session", "2031/2032")))).isEqualTo(403);
            assertThat(code(it.call(office, HttpMethod.PUT, path, Map.of("session", "2031/2033")))).isEqualTo("JUPEB_SESSION");
            s = ok(it.call(office, HttpMethod.PUT, path, Map.of("session", "2031/2032")));
            assertThat(s.get("currentSession")).isEqualTo("2031/2032");
            assertThat(s.get("namedSession")).isEqualTo("2031/2032");
            assertThat(jdbc.sql("SELECT policy.application_session('JUPEB_APPLICATION')").query(String.class).single()).isEqualTo("2031/2032");
            assertThat(jdbc.sql("SELECT policy.application_session('POST_UTME_REGISTRATION')").query(String.class).single()).isEqualTo(university);
            Map<String, Object> none = new LinkedHashMap<>();
            none.put("session", null);
            s = ok(it.call(office, HttpMethod.PUT, path, none));
            assertThat(s.get("currentSession")).isEqualTo(university);
            assertThat(s.get("namedSession")).isNull();

            // the course as the Board prints it; a practical in another room at the same hour; the same room refused
            assertThat(status(it.callList(office, HttpMethod.POST, "/api/v1/jupeb/office/rooms", Map.of("code", "ZZ" + tag)))).isEqualTo(200);
            assertThat(status(it.callList(office, HttpMethod.POST, "/api/v1/jupeb/office/rooms", Map.of("code", "ZZ" + tag + "LAB", "kind", "LAB")))).isEqualTo(200);
            List<UUID> subjects = jdbc.sql("SELECT id FROM jupeb.subject WHERE code IN ('GEO', 'AGR') ORDER BY (code = 'GEO') DESC").query(UUID.class).list();
            Map<String, Object> slot = new LinkedHashMap<>(Map.of("session", "2031/2032", "semester", 1, "subjectId", subjects.get(0).toString(), "weekday", 1,
                    "startsAt", "08:00", "endsAt", "09:00", "venue", "ZZ" + tag, "courseCode", "gry001"));
            ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", slot));
            Map<String, Object> practical = new LinkedHashMap<>(Map.of("session", "2031/2032", "semester", 1, "subjectId", subjects.get(1).toString(), "weekday", 1,
                    "startsAt", "08:00", "endsAt", "10:00", "venue", "ZZ" + tag + "LAB", "practical", true));
            ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", practical));
            practical.put("venue", "zz " + tag.toLowerCase());
            assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", practical))).isEqualTo("JUPEB_SLOT_CLASH");
            List<Map<String, Object>> slots = (List<Map<String, Object>>) ok(it.get(office, "/api/v1/jupeb/office/timetable?session=2031/2032&semester=1")).get("slots");
            assertThat(slots).extracting(x -> x.get("course_code")).containsExactlyInAnyOrder("GRY 001", null);
            assertThat(slots).extracting(x -> x.get("practical")).containsExactlyInAnyOrder(false, true);
        } finally {
            it.db(() -> {
                jdbc.sql("DELETE FROM jupeb.timetable_slot WHERE session = '2031/2032'").update();
                jdbc.sql("UPDATE jupeb.setting SET current_session = :c WHERE session = '*'").param("c", named, java.sql.Types.VARCHAR).update();
                return null;
            });
        }
    }

    /** V353: the Board's syllabus — each subject's courses, a combination's (MAT 004A or 004B by its area), a course's syllabus; the
     *  option of an either/or subject chosen by the student until the examination number, then by the office with a reason; a
     *  student reads only their own courses' syllabus; a timetable course is one of the subject's units */
    @Test
    @SuppressWarnings("unchecked")
    void syllabusCoursesAndTheOptionOfAnEitherOrSubject() {
        Map<String, Object> syl = ok(it.get(office, "/api/v1/jupeb/office/syllabus"));
        assertThat((List<Map<String, Object>>) syl.get("boardSubjects")).hasSize(19);
        List<Map<String, Object>> units = (List<Map<String, Object>>) syl.get("units");
        assertThat(units).extracting(u -> u.get("code")).contains("BIO 001", "ECN 001", "GRY 004", "MAT 004A", "MAT 004B", "CRS 001", "ISS 001");
        assertThat(status(it.get(bursar, "/api/v1/jupeb/office/syllabus"))).isEqualTo(403);
        List<Map<String, Object>> sc024 = (List<Map<String, Object>>) (List<?>) it.callList(office, HttpMethod.GET, "/api/v1/jupeb/office/combinations/SC-024/units", null).getBody();
        assertThat(sc024).extracting(u -> u.get("code")).contains("MAT 004B", "BUS 001", "ECN 004").doesNotContain("MAT 004A");
        String botany = units.stream().filter(u -> "BIO 002".equals(u.get("code"))).findFirst().orElseThrow().get("id").toString();
        Map<String, Object> bio = ok(it.get(office, "/api/v1/jupeb/office/units/" + botany + "/syllabus"));
        assertThat(bio.get("title")).isEqualTo("Botany");
        assertThat((List<?>) bio.get("topics")).isNotEmpty();

        // a student of SC-001 (Christian / Islamic Religious Studies, Government, Literature in English)
        String appNo = "S9" + tag + "06";
        Map<String, Object> in = new LinkedHashMap<>();
        in.put("rows", List.of(oldRow(2, "appNo", appNo, "firstName", "Aisha", "surname", "Terkura", "sex", "Female", "phone", "08066667777", "dob", "3/4/2006",
                "email", "zzv353." + tag.toLowerCase() + "@example.com")));
        in.put("session", session);
        in.put("dayFirst", true);
        in.put("commit", true);
        in.put("fileName", "old.xlsx");
        in.put("emailLinks", false);
        Map<String, Object> done = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in));
        String temporary = String.valueOf(((List<Map<String, Object>>) done.get("credentials")).get(0).get("password"));
        UUID app = jdbc.sql("SELECT id FROM jupeb.application WHERE application_no = :n").param("n", appNo).query(UUID.class).single();
        String token = String.valueOf(ok(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", appNo, "password", temporary))).get("token"));
        ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/password", Map.of("currentPassword", temporary, "newPassword", "Syllabus2026!")));
        it.db(() -> jdbc.sql("SELECT jupeb.register_subjects(:a, :a, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'))").param("a", app).query(Integer.class).single());

        // both options until chosen; then the one chosen only; another's course is not theirs to open
        List<Map<String, Object>> mine = (List<Map<String, Object>>) ok(it.get(token, "/api/v1/jupeb/me/units")).get("units");
        assertThat(mine).extracting(u -> u.get("code")).contains("CRS 001", "ISS 001", "GOV 001", "LIT 004");
        UUID religion = jdbc.sql("SELECT id FROM jupeb.subject WHERE code = 'CRS/ISS'").query(UUID.class).single();
        UUID iss = jdbc.sql("SELECT id FROM jupeb.board_subject WHERE prefix = 'ISS'").query(UUID.class).single();
        UUID crs = jdbc.sql("SELECT id FROM jupeb.board_subject WHERE prefix = 'CRS'").query(UUID.class).single();
        UUID yor = jdbc.sql("SELECT id FROM jupeb.board_subject WHERE prefix = 'YOR'").query(UUID.class).single();
        assertThat(code(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/subject-option", Map.of("subjectId", religion.toString(), "boardSubjectId", yor.toString())))).isEqualTo("JUPEB_OPTION");
        Map<String, Object> me = ok(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/subject-option", Map.of("subjectId", religion.toString(), "boardSubjectId", iss.toString())));
        assertThat((List<Map<String, Object>>) me.get("registered")).anySatisfy(r -> assertThat(r.get("option_title")).isEqualTo("Islamic Studies (ISS)"));
        mine = (List<Map<String, Object>>) ok(it.get(token, "/api/v1/jupeb/me/units")).get("units");
        assertThat(mine).extracting(u -> u.get("code")).contains("ISS 001").doesNotContain("CRS 001");
        assertThat(mine).hasSize(12);
        String iss001 = mine.stream().filter(u -> "ISS 001".equals(u.get("code"))).findFirst().orElseThrow().get("unit_id").toString();
        assertThat(ok(it.get(token, "/api/v1/jupeb/me/units/" + iss001 + "/syllabus")).get("code")).isEqualTo("ISS 001");
        assertThat(status(it.get(token, "/api/v1/jupeb/me/units/" + botany + "/syllabus"))).isEqualTo(404);

        // the examination number closes the student's choice; the office changes it, with a reason
        it.db(() -> jdbc.sql("UPDATE jupeb.application SET exam_no = :x WHERE id = :a").param("x", "ZZ" + tag + "353").param("a", app).update());
        assertThat(code(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/subject-option", Map.of("subjectId", religion.toString(), "boardSubjectId", crs.toString())))).isEqualTo("JUPEB_OPTION_LOCKED");
        Map<String, Object> change = new LinkedHashMap<>(Map.of("subjectId", religion.toString(), "boardSubjectId", crs.toString()));
        assertThat(code(it.call(office, HttpMethod.PUT, "/api/v1/jupeb/office/applications/" + app + "/subject-option", change))).isEqualTo("JUPEB_OPTION_REASON");
        change.put("reason", "The candidate sits Christian Religious Studies");
        Map<String, Object> c = ok(it.call(office, HttpMethod.PUT, "/api/v1/jupeb/office/applications/" + app + "/subject-option", change));
        assertThat((List<Map<String, Object>>) c.get("registered")).anySatisfy(r -> assertThat(r.get("option_title")).isEqualTo("Christian Religious Studies (CRS)"));

        // a timetable course is one of the subject's units
        UUID biology = jdbc.sql("SELECT id FROM jupeb.subject WHERE code = 'BIO'").query(UUID.class).single();
        Map<String, Object> slot = new LinkedHashMap<>(Map.of("session", "2031/2032", "semester", 1, "subjectId", biology.toString(), "weekday", 6,
                "startsAt", "08:00", "endsAt", "09:00", "venue", "ZZ" + tag, "courseCode", "BIO 009"));
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", slot))).isEqualTo("JUPEB_SLOT_COURSE");
    }

    /** V354: the session calendar kept and planned forward; rooms from the list; a semester copied into the next; the students of a subject
     *  told of a timetable change; the clearance for the examination, and the students told what is outstanding; the checks before the
     *  current session changes */
    @Test
    @SuppressWarnings("unchecked")
    void calendarRoomsCopyNoticesClearanceAndSessionChecks() {
        String far = "2091/2092";
        String next = "2092/2093";
        List<String> slotIds = new java.util.ArrayList<>();
        try {
            // the Board's 2026/2027 calendar is on the record; an event added and its mark kept to one event; the Bursary refused
            Map<String, Object> cal = ok(it.get(office, "/api/v1/jupeb/office/calendar?session=2026/2027"));
            assertThat((List<Map<String, Object>>) cal.get("events")).extracting(e -> e.get("marker")).contains("TEACHING_STARTS", "BOARD_REGISTRATION", "EXAMINATIONS", "RESULTS");
            Map<String, Object> event = new LinkedHashMap<>(Map.of("session", far, "startsOn", "2091-09-25", "title", "Teaching commences", "marker", "TEACHING_STARTS", "forStudents", true));
            ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/calendar", event));
            event.put("title", "Teaching commences again");
            assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/calendar", event))).isEqualTo("JUPEB_CALENDAR_MARKER");
            assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/office/calendar", event))).isEqualTo(403);
            Map<String, Object> planned = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/calendar/copy", Map.of("from", far, "to", next)));
            List<Map<String, Object>> nextEvents = (List<Map<String, Object>>) planned.get("events");
            assertThat(nextEvents).hasSize(1);
            assertThat(nextEvents.get(0).get("starts_on")).isEqualTo("2092-09-25");
            assertThat(nextEvents.get(0).get("planned")).isEqualTo(true);
            assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/calendar/copy", Map.of("from", far, "to", next)))).isEqualTo("JUPEB_CALENDAR_EXISTS");
            Map<String, Object> confirmed = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/calendar/confirm", Map.of("session", next)));
            assertThat(((List<Map<String, Object>>) confirmed.get("events")).get(0).get("planned")).isEqualTo(false);

            // the rooms: one code a room, however written
            List<Map<String, Object>> rooms = (List<Map<String, Object>>) (List<?>) it.callList(office, HttpMethod.POST, "/api/v1/jupeb/office/rooms", Map.of("code", "zz rm " + tag, "capacity", 40)).getBody();
            assertThat(rooms).extracting(r -> r.get("code")).contains("ZZRM" + tag);
            assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/rooms", Map.of("code", "ZZRM" + tag)))).isEqualTo("JUPEB_ROOM_EXISTS");
            String room = rooms.stream().filter(r -> ("ZZRM" + tag).equals(r.get("code"))).findFirst().orElseThrow().get("id").toString();
            UUID geo = jdbc.sql("SELECT id FROM jupeb.subject WHERE code = 'GEO'").query(UUID.class).single();
            Map<String, Object> slot = new LinkedHashMap<>(Map.of("session", far, "semester", 1, "subjectId", geo.toString(), "weekday", 2,
                    "startsAt", "08:00", "endsAt", "09:00", "roomId", room, "courseCode", "GRY 001"));
            slotIds.add(ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", slot)).get("id").toString());
            slot.remove("roomId");
            slot.put("venue", "Nowhere " + tag);
            slot.put("weekday", 3);
            assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", slot))).isEqualTo("JUPEB_ROOM_UNKNOWN");

            // the first semester copied into the second: GRY 001 moves on to GRY 003; never into a semester with lectures
            Map<String, Object> copied = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable/copy", Map.of("session", far, "semester", 1, "toSession", far, "toSemester", 2)));
            assertThat(copied.get("copied")).isEqualTo(1);
            List<Map<String, Object>> second = (List<Map<String, Object>>) ok(it.get(office, "/api/v1/jupeb/office/timetable?session=" + far + "&semester=2")).get("slots");
            assertThat(second).extracting(x -> x.get("course_code")).containsExactly("GRY 003");
            second.forEach(x -> slotIds.add(x.get("id").toString()));
            assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable/copy", Map.of("session", far, "semester", 1, "toSession", far, "toSemester", 2)))).isEqualTo("JUPEB_TIMETABLE_NOT_EMPTY");

            // a student of SC-001; a Government lecture added on their timetable, and they are told
            String appNo = "SA" + tag + "07";
            Map<String, Object> in = new LinkedHashMap<>();
            in.put("rows", List.of(oldRow(2, "appNo", appNo, "firstName", "Ene", "surname", "Ogbole", "sex", "Female", "phone", "08066668888", "dob", "3/4/2006",
                    "email", "zzv354." + tag.toLowerCase() + "@example.com")));
            in.put("session", session);
            in.put("dayFirst", true);
            in.put("commit", true);
            in.put("fileName", "old.xlsx");
            in.put("emailLinks", false);
            Map<String, Object> done = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in));
            String temporary = String.valueOf(((List<Map<String, Object>>) done.get("credentials")).get(0).get("password"));
            UUID app = jdbc.sql("SELECT id FROM jupeb.application WHERE application_no = :n").param("n", appNo).query(UUID.class).single();
            String token = String.valueOf(ok(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", appNo, "password", temporary))).get("token"));
            ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/password", Map.of("currentPassword", temporary, "newPassword", "Calendar2026!")));
            it.db(() -> jdbc.sql("SELECT jupeb.register_subjects(:a, :a, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'))").param("a", app).query(Integer.class).single());
            UUID gov = jdbc.sql("SELECT id FROM jupeb.subject WHERE code = 'GOV'").query(UUID.class).single();
            Map<String, Object> lecture = new LinkedHashMap<>(Map.of("session", session, "semester", 1, "subjectId", gov.toString(), "weekday", 6,
                    "startsAt", "07:00", "endsAt", "08:00", "roomId", room, "courseCode", "GOV 001", "tell", true));
            Map<String, Object> added = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/timetable", lecture));
            slotIds.add(added.get("id").toString());
            assertThat(((Number) added.get("told")).intValue()).isGreaterThanOrEqualTo(1);
            List<Map<String, Object>> notices = (List<Map<String, Object>>) ok(it.get(token, "/api/v1/jupeb/me/announcements")).get("announcements");
            assertThat(notices).extracting(n -> n.get("title")).contains("Timetable: GOV 001 added");

            // the clearance: what is outstanding, said to the student and by the office
            Map<String, Object> mine = ok(it.get(token, "/api/v1/jupeb/me/clearance"));
            assertThat(mine.get("cleared")).isEqualTo(false);
            assertThat((List<Map<String, Object>>) mine.get("checks")).anySatisfy(c -> {
                assertThat(c.get("key")).isEqualTo("OPTION");
                assertThat(c.get("ok")).isEqualTo(false);
            });
            Map<String, Object> clear = ok(it.get(office, "/api/v1/jupeb/office/clearance?session=" + session));
            Map<String, Object> row = ((List<Map<String, Object>>) clear.get("rows")).stream().filter(r -> app.toString().equals(String.valueOf(r.get("application_id")))).findFirst().orElseThrow();
            assertThat((List<String>) row.get("outstanding")).contains("No examination number from the Board yet");
            assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/office/clearance/tell", Map.of("session", session)))).isEqualTo(403);
            assertThat(((Number) ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/clearance/tell", Map.of("session", session))).get("told")).intValue()).isGreaterThanOrEqualTo(1);
            notices = (List<Map<String, Object>>) ok(it.get(token, "/api/v1/jupeb/me/announcements")).get("announcements");
            assertThat(notices).extracting(n -> n.get("title")).contains("Before the examination: what is outstanding");

            // the student's dates; the checks before the current session changes
            assertThat(ok(it.get(token, "/api/v1/jupeb/me/calendar")).get("session")).isEqualTo(session);
            Map<String, Object> check = ok(it.get(office, "/api/v1/jupeb/office/settings/session-check?to=" + next));
            assertThat(check.get("from")).isEqualTo(session);
            assertThat((List<Map<String, Object>>) check.get("items")).extracting(x -> x.get("session")).contains(session, next);
        } finally {
            it.db(() -> {
                for (String id : slotIds) jdbc.sql("DELETE FROM jupeb.timetable_slot WHERE id = :id::uuid").param("id", id).update();
                jdbc.sql("DELETE FROM jupeb.calendar_event WHERE session IN ('2091/2092', '2092/2093')").update();
                jdbc.sql("DELETE FROM jupeb.room WHERE code = :c").param("c", "ZZRM" + tag).update();
                return null;
            });
        }
    }

    /** V350: a withdrawal opens a refund claim the Bursary decides through its own maker–checker refunds; practice results and advice */
    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void withdrawalRefundsThroughTheBursaryAndPracticeResults() {
        String appNo = "S8" + tag + "05";
        Map<String, Object> in = new LinkedHashMap<>();
        in.put("rows", List.of(oldRow(2, "appNo", appNo, "firstName", "Mnena", "surname", "Ityavyar", "sex", "Female", "phone", "08077776666", "dob", "3/4/2006",
                "email", "zzv350." + tag.toLowerCase() + "@example.com")));
        in.put("session", session);
        in.put("dayFirst", true);
        in.put("commit", true);
        in.put("fileName", "old.xlsx");
        in.put("emailLinks", false);
        Map<String, Object> done = ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-students/import", in));
        String temporary = String.valueOf(((List<Map<String, Object>>) done.get("credentials")).get(0).get("password"));
        UUID app = jdbc.sql("SELECT id FROM jupeb.application WHERE application_no = :n").param("n", appNo).query(UUID.class).single();
        String token = String.valueOf(ok(it.anon(HttpMethod.POST, "/api/v1/jupeb/sign-in", Map.of("identifier", appNo, "password", temporary))).get("token"));
        ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/password", Map.of("currentPassword", temporary, "newPassword", "Refund2026!")));
        it.db(() -> jdbc.sql("SELECT jupeb.register_subjects(:a, :a, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'))").param("a", app).query(Integer.class).single());
        Map<String, Object> pay = new LinkedHashMap<>();
        pay.put("rows", List.of(oldRow(2, "appNo", appNo, "reference", "OLD-" + tag + "-R1", "purpose", "School Fees 1st Instalment", "amount", "75000", "date", "12/11/2024", "status", "Success")));
        pay.put("dayFirst", true);
        pay.put("commit", true);
        pay.put("fileName", "payments.xlsx");
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/old-portal-payments/import", pay));
        String paid = jdbc.sql("SELECT reference FROM jupeb.fee_reference WHERE application_id = :a AND confirmed_at IS NOT NULL").param("a", app).query(String.class).single();

        // practice results, weakest first, and the office's advice to one student
        UUID subject = jdbc.sql("SELECT sr.subject_id FROM jupeb.subject_registration sr JOIN jupeb.subject s ON s.id = sr.subject_id WHERE sr.application_id = :a ORDER BY s.code LIMIT 1")
                .param("a", app).query(UUID.class).single();
        String testId = String.valueOf(ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/practice-tests", Map.of("subjectId", subject.toString(), "title", "Weak " + tag,
                "durationMinutes", 10, "questionsPerAttempt", 2, "attemptsAllowed", 1, "showAnswers", true, "open", false))).get("id"));
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/practice-tests/" + testId + "/questions", Map.of("replace", false, "rows", List.of(
                Map.of("row", 2, "question", "One?", "a", "1", "b", "2", "answer", "A"), Map.of("row", 3, "question", "Two?", "a", "1", "b", "2", "answer", "B")))));
        ok(it.call(office, HttpMethod.PUT, "/api/v1/jupeb/office/practice-tests/" + testId, Map.of("subjectId", subject.toString(), "title", "Weak " + tag,
                "durationMinutes", 10, "questionsPerAttempt", 2, "attemptsAllowed", 1, "showAnswers", true, "open", true)));
        Map<String, Object> paper = ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/practice/" + testId + "/start", Map.of()));
        String attempt = String.valueOf(((Map<String, Object>) paper.get("attempt")).get("id"));
        for (Map<String, Object> q : (List<Map<String, Object>>) paper.get("questions")) {
            ok(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/practice/attempts/" + attempt + "/answers/" + q.get("id"), Map.of("choice", "A")));
        }
        ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/practice/attempts/" + attempt + "/submit", Map.of()));
        List<Map<String, Object>> results = (List<Map<String, Object>>) ok(it.get(office, "/api/v1/jupeb/office/practice-results?session=" + session)).get("students");
        Map<String, Object> mine = results.stream().filter(r -> app.toString().equals(String.valueOf(r.get("application_id")))).findFirst().orElseThrow();
        assertThat(new BigDecimal(String.valueOf(mine.get("average")))).isEqualByComparingTo("50");
        assertThat((List<Map<String, Object>>) mine.get("subjects")).hasSize(1);
        assertThat(status(it.get(bursar, "/api/v1/jupeb/office/practice-results?session=" + session))).isEqualTo(403);
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/advise", Map.of("title", "Study", "body", "Study harder")))).isEqualTo(403);
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/applications/" + app + "/advise", Map.of("title", "Your practice tests " + tag,
                "body", "Your average is 50%. Read your notes daily.", "email", true)));
        assertThat((List<Map<String, Object>>) ok(it.get(token, "/api/v1/jupeb/me/announcements")).get("announcements"))
                .extracting(a -> String.valueOf(a.get("title"))).contains("Your practice tests " + tag);
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.application a WHERE a.id <> :a AND jupeb.audience_reaches(:s, 'STUDENT', :r, a)")
                .param("a", app).param("s", session).param("r", app.toString()).query(Integer.class).single()).isZero();
        Map<String, Object> view = ok(it.get(office, "/api/v1/jupeb/office/applications/" + app));
        assertThat((List<?>) view.get("practice")).hasSize(1);
        assertThat(((List<Map<String, Object>>) ok(it.get(office, "/api/v1/jupeb/office/practice-results?session=" + session)).get("students")).stream()
                .filter(r -> app.toString().equals(String.valueOf(r.get("application_id")))).findFirst().orElseThrow().get("advised_at")).isNotNull();

        // the withdrawal opens the claim; nothing is raised without the account; the account is the candidate's to give
        ok(it.call(token, HttpMethod.POST, "/api/v1/jupeb/me/requests", Map.of("kind", "WITHDRAW", "reason", "I have gained admission elsewhere this year")));
        String request = String.valueOf(((List<Map<String, Object>>) ok(it.get(token, "/api/v1/jupeb/me")).get("requests")).get(0).get("id"));
        ok(it.call(office, HttpMethod.POST, "/api/v1/jupeb/office/requests/" + request + "/decide", Map.of("approve", true, "note", "Withdrawn as asked")));
        Map<String, Object> claim = (Map<String, Object>) ok(it.get(token, "/api/v1/jupeb/me")).get("refundClaim");
        assertThat(((Map<String, Object>) claim.get("state")).get("status")).isEqualTo("AWAITING_DETAILS");
        assertThat((List<Map<String, Object>>) claim.get("payments")).extracting(x -> x.get("reference")).containsExactly(paid);
        String claimId = String.valueOf(claim.get("id"));
        assertThat(code(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/fees/refund-claims/" + claimId + "/refunds",
                Map.of("reference", paid, "amount", 50000, "reason", "Withdrawal before lectures")))).isEqualTo("JUPEB_REFUND_DETAILS");
        assertThat(status(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/refund-details", Map.of("bankName", "First Bank", "accountName", "Mnena Ityavyar", "accountNumber", "12345")))).isEqualTo(400);
        claim = (Map<String, Object>) ok(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/refund-details",
                Map.of("bankName", "First Bank", "accountName", "Mnena Ityavyar", "accountNumber", "3012345678"))).get("refundClaim");
        assertThat(claim.get("account_number")).isEqualTo("••••••5678");
        assertThat(((Map<String, Object>) claim.get("state")).get("status")).isEqualTo("WITH_BURSARY");
        Map<String, Object> asBursary = ((List<Map<String, Object>>) it.callList(bursar, HttpMethod.GET, "/api/v1/jupeb/fees/refund-claims", null).getBody()).stream()
                .filter(c -> claimId.equals(String.valueOf(c.get("id")))).findFirst().orElseThrow();
        assertThat(asBursary.get("account_number")).isEqualTo("3012345678");
        Map<String, Object> asOffice = ((List<Map<String, Object>>) it.callList(office, HttpMethod.GET, "/api/v1/jupeb/fees/refund-claims", null).getBody()).stream()
                .filter(c -> claimId.equals(String.valueOf(c.get("id")))).findFirst().orElseThrow();
        assertThat(asOffice.get("account_number")).isEqualTo("••••••5678");
        assertThat(status(it.call(office, HttpMethod.POST, "/api/v1/jupeb/fees/refund-claims/" + claimId + "/refunds", Map.of("reference", paid, "amount", 1000, "reason", "Not the office's")))).isEqualTo(403);

        // the Bursary raises a refund through its own workflow: never beyond what was paid on the payment; maker and checker differ
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/fees/refund-claims/" + claimId + "/refunds",
                Map.of("reference", paid, "amount", 80000, "reason", "Withdrawal before lectures")))).isEqualTo(422);
        Map<String, Object> raised = ok(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/fees/refund-claims/" + claimId + "/refunds",
                Map.of("reference", paid, "amount", 50000, "reason", "Withdrawal before lectures")));
        String refundId = String.valueOf(raised.get("id"));
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/fees/refund-claims/" + claimId + "/refunds",
                Map.of("reference", paid, "amount", 30000, "reason", "The rest")))).isEqualTo(422);
        assertThat(code(it.call(bursar, HttpMethod.POST, "/api/v1/jupeb/fees/refund-claims/" + claimId + "/decline", Map.of("reason", "Not refundable")))).isEqualTo("JUPEB_REFUND_RAISED");
        assertThat(code(it.call(token, HttpMethod.PUT, "/api/v1/jupeb/me/refund-details", Map.of("bankName", "Other Bank", "accountName", "Mnena Ityavyar", "accountNumber", "3099999999"))))
                .isEqualTo("JUPEB_REFUND_LOCKED");
        assertThat(status(it.call(bursar, HttpMethod.POST, "/api/v1/finance/refunds/" + refundId + "/approve", Map.of()))).isEqualTo(422);
        String checker = TestTokens.token(it.person("ZZJUPEB-BURSAR2-" + tag, "ZZJUPEBBURSARTWO" + tag), List.of("bursar"));
        ok(it.call(checker, HttpMethod.POST, "/api/v1/finance/refunds/" + refundId + "/approve", Map.of()));
        ok(it.call(checker, HttpMethod.POST, "/api/v1/finance/refunds/" + refundId + "/pay", Map.of()));
        claim = (Map<String, Object>) ok(it.get(token, "/api/v1/jupeb/me")).get("refundClaim");
        assertThat(((Map<String, Object>) claim.get("state")).get("status")).isEqualTo("REFUND_PAID");
        assertThat(new BigDecimal(String.valueOf(((Map<String, Object>) claim.get("state")).get("paid")))).isEqualByComparingTo("50000");
        assertThat(jdbc.sql("SELECT count(*) FROM jupeb.application_event WHERE application_id = :a AND kind IN ('REFUND_CLAIM_OPENED', 'REFUND_PROPOSED', 'REFUND_PAID')")
                .param("a", app).query(Integer.class).single()).isEqualTo(3);
        List<Map<String, Object>> refunds = (List<Map<String, Object>>) it.callList(bursar, HttpMethod.GET, "/api/v1/finance/refunds", null).getBody();
        assertThat(refunds).filteredOn(r -> refundId.equals(String.valueOf(r.get("id")))).extracting(r -> r.get("number")).containsExactly(appNo);
    }

    private static Map<String, Object> oldRow(int row, String... pairs) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("row", row);
        for (int i = 0; i + 1 < pairs.length; i += 2) m.put(pairs[i], pairs[i + 1]);
        return m;
    }

    private static Map<String, Object> grade(int sitting, String subject, String grade) {
        return Map.of("sitting", sitting, "examType", sitting == 1 ? "WAEC" : "NECO", "examNumber", sitting == 1 ? "4251234001" : "1012345678", "examYear", 2024,
                "subject", subject, "grade", grade);
    }
}
