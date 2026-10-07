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
