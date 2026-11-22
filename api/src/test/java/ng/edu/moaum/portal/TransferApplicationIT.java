package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.ByteArrayOutputStream;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

import ng.edu.moaum.portal.payments.PaymentsService;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
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
 * V766: an inter-university transfer applied for online, through the API. The Academic Office opens a session's window only with a
 * programme taking transfers and the Bursar's fee published; a student of another university applies at the public door (a programme
 * not opened, a second live application under one JAMB number, an e-mail already used and a robot refused; the door throttled), signs
 * in, pays (confirmed by hand by the Bursar), uploads (a file whose bytes are not its type and one over 5 MB refused; nothing before the
 * fee) and submits with the required documents; the acknowledgement's code verifies. The Registry checks each document and returns the
 * application, sends it to the Head of Department of the programme applied for (told), who alone recommends it at a level the window
 * opens; the Registry approves it once the university is on the list — a batch of one (source APPLICATION) that the approver cannot
 * decide; another officer's approval admits the student (TRANSFER, ADMITTED, the level recommended), who signs in at the student door
 * with the application's password. A transfer rejected there returns the application to the Registry untold; the Registry's own
 * rejection is told. A zero fee is settled at registration; a closed window refuses a new application and lets a started one submit;
 * places filled are refused. No other applicant's token reaches the transfer applicant's pages. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET, "moaum.payments.paystack-secret=" + TransferApplicationIT.PAYSTACK_SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class TransferApplicationIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient plain;

    static final String PUBLIC = "/api/v1/public/inter-university-transfer";
    static final String APPLY = "/api/v1/transfer-applications/apply";
    static final String SIGN_IN = "/api/v1/transfer-applications/sign-in";
    static final String ME = "/api/v1/transfer-applications/me";
    static final String OFFICE = "/api/v1/transfer-applications/office";
    static final String FEES = "/api/v1/finance/transfer-applications";
    static final String IUT = "/api/v1/transfers/inter-university";
    static final String PASSWORD = "a good password 2026";
    static final List<String> REQUIRED = List.of("TRANSCRIPT", "RELEASE_LETTER", "JAMB_ADMISSION_LETTER", "OLEVEL_RESULT");
    /** the Paystack key a card payment's notice is signed with here (round 4: a card payment made online, confirmed as the gateway confirms it) */
    static final String PAYSTACK_SECRET = "sk_test_only_for_the_transfer_it";
    /** one message for every window this test sets: a refusal at the closed door names the latest window's message, whichever run left it */
    static final String CLOSED_MESSAGE = "Transfer applications are closed; the next window is announced on the University's website.";

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        plain = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(status -> true, (request, response) -> { }).build();
    }

    /* ── the world of one test: its own session, a programme in a department outside any College, the offices ── */

    record World(String session, int year, String programme, String dept, String faculty, String otherDept, String academic, String registrar,
                 String hod, String otherHod, String dean, String bursar) {
    }

    World world() {
        return world(1600, 1890);
    }

    /** a year above every session holding transfer applications (whatever other tests and runs left): the desks' default session, the
     *  latest with applications on their hands (round 5: v4v-2), is then read off this test's own */
    World latestWorld() {
        int floor = Math.max(1891, jdbc.sql("SELECT coalesce(max(left(session, 4)::int), 0) FROM admissions.iut_application").query(Integer.class).single() + 1);
        return world(floor, floor + 100);
    }

    World world(int min, int bound) {
        int y = it.freeYear(min, bound);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        // a window another run left open would take the public door's applications: only this test's is open
        it.db(() -> jdbc.sql("UPDATE admissions.iut_window SET state = 'CLOSED' WHERE state = 'OPEN' AND session <> :s").param("s", session).update());
        Map<String, Object> p = jdbc.sql("""
                SELECT p.code, p.dept_code, p.faculty_code FROM ref.programme p CROSS JOIN LATERAL people.transfer_unit(p.code) u
                 WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false) AND u.college_code IS NULL AND p.dept_code IS NOT NULL
                   AND 200 = ANY (people.programme_levels(p.code)) AND 300 = ANY (people.programme_levels(p.code))
                 ORDER BY p.code LIMIT 1
                """).query().singleRow();
        String dept = String.valueOf(p.get("dept_code"));
        String other = jdbc.sql("""
                SELECT p.dept_code FROM ref.programme p WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false) AND p.dept_code IS NOT NULL
                   AND p.dept_code <> :d ORDER BY p.code LIMIT 1
                """).param("d", dept).query(String.class).single();
        int n = it.freeDraw(10000, 99999, k -> List.of("ZZ-IUA-AC-" + k, "ZZ-IUA-RG-" + k, "ZZIUAAC" + k, "ZZIUARG" + k));
        String academic = TestTokens.token(it.person("ZZ-IUA-AC-" + n, "ZZIUAAC" + n), List.of("academic"));
        String registrar = TestTokens.token(it.person("ZZ-IUA-RG-" + n, "ZZIUARG" + n), List.of("registrar"));
        String hod = it.officer("hod", "department", dept);
        String otherHod = it.officer("hod", "department", other);
        String dean = it.officer("dean", "faculty", String.valueOf(p.get("faculty_code")));
        // the Head of Department is reached by e-mail when an application comes to the desk
        String tag = dept.replaceAll("[^A-Za-z0-9]", "");
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :e WHERE staff_number = :n AND email IS NULL")
                .param("e", "zz-hod-" + tag.toLowerCase() + "@example.com").param("n", "ZZ-HOD-" + tag).update());
        return new World(session, y, String.valueOf(p.get("code")), dept, String.valueOf(p.get("faculty_code")), other, academic, registrar, hod, otherHod, dean,
                ItSupport.token("bursar"));
    }

    static LocalDate today() {
        return LocalDate.now(ZoneId.of("Africa/Lagos"));
    }

    private Map<String, Object> windowBody(World w, String state) {
        Map<String, Object> b = new HashMap<>(Map.of("session", w.session(), "state", state, "opensOn", today().toString(), "closesOn", today().plusDays(30).toString()));
        b.put("message", CLOSED_MESSAGE);
        return b;
    }

    /** the window opened as the Academic Office opens it: a line at 200 Level (places as given), the fee stated and published */
    private void open(World w, int fee, Integer places) {
        Map<String, Object> line = new HashMap<>(Map.of("session", w.session(), "programme", w.programme(), "levels", List.of(200)));
        if (places != null) line.put("places", places);
        ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/lines", line));
        ok(it.call(w.bursar(), HttpMethod.PUT, FEES + "/fee", Map.of("session", w.session(), "amount", fee)));
        ok(it.call(w.bursar(), HttpMethod.POST, FEES + "/fee/publish", Map.of("session", w.session())));
        assertThat(ok(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "OPEN")))).containsEntry("status", "OPEN");
    }

    /* ── the applicant ── */

    record Applicant(String token, UUID account, UUID app, String no, String jamb, String email) {
    }

    static String letters(int n) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < n; i++) b.append((char) ('a' + ThreadLocalRandom.current().nextInt(26)));
        return b.toString();
    }

    static String jamb() {
        return String.format("%012d", ThreadLocalRandom.current().nextLong(100_000_000_000L, 1_000_000_000_000L)) + "IU";
    }

    Map<String, Object> form(World w, String jamb, String email, int level) {
        Map<String, Object> f = new HashMap<>();
        f.put("surname", "Zzaudu" + letters(5));
        f.put("otherNames", "Grace Ene");
        f.put("sex", "F");
        f.put("dateOfBirth", "2004-03-09");
        f.put("email", email);
        f.put("phone", "080" + String.format("%08d", ThreadLocalRandom.current().nextInt(100_000_000)));
        f.put("jambRegNo", jamb);
        f.put("password", PASSWORD);
        f.put("universityCode", "UNIJOS");
        f.put("otherMatricNo", "uj/" + (w.year() - 2) + "/sc/0042");
        f.put("otherProgramme", "B.Sc. Biochemistry");
        f.put("otherLevel", 300);
        f.put("otherEntrySession", (w.year() - 2) + "/" + (w.year() - 1));
        f.put("otherCgpa", "3.85");
        f.put("otherCgpaScale", 5);
        f.put("programme", w.programme());
        f.put("level", level);
        f.put("reason", "I wish to continue my studies nearer my family, in a programme my present university does not offer.");
        return f;
    }

    static String email() {
        return "zziut-" + UUID.randomUUID().toString().substring(0, 12) + "@example.com";
    }

    Applicant applied(Map<String, Object> f) {
        ResponseEntity<Map> r = it.anon(HttpMethod.POST, APPLY, f);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        String token = String.valueOf(r.getBody().get("token"));
        Map<String, Object> me = ok(it.get(token, ME));
        return new Applicant(token, UUID.fromString(String.valueOf(r.getBody().get("accountId"))), UUID.fromString(String.valueOf(me.get("id"))),
                String.valueOf(r.getBody().get("applicationNo")), String.valueOf(f.get("jambRegNo")), String.valueOf(f.get("email")));
    }

    Applicant apply(World w) {
        return applied(form(w, jamb(), email(), 200));
    }

    /** the fee drawn and confirmed by hand by the Bursar; the reference */
    String pay(World w, Applicant a) {
        String ref = String.valueOf(ok(it.call(a.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        assertThat(ok(it.call(w.bursar(), HttpMethod.POST, FEES + "/payments/" + ref + "/confirm", Map.of("note", "Teller 0042 at the bank")))).containsEntry("outcome", "confirmed");
        return ref;
    }

    static byte[] pdf() {
        try (PDDocument d = new PDDocument(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            d.addPage(new PDPage());
            d.save(out);
            return out.toByteArray();
        } catch (java.io.IOException e) {
            throw new IllegalStateException(e);
        }
    }

    static byte[] png() {
        try (ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            javax.imageio.ImageIO.write(new java.awt.image.BufferedImage(8, 8, java.awt.image.BufferedImage.TYPE_INT_RGB), "png", out);
            return out.toByteArray();
        } catch (java.io.IOException e) {
            throw new IllegalStateException(e);
        }
    }

    static String dataUrl(String type, byte[] bytes) {
        return "data:" + type + ";base64," + Base64.getEncoder().encodeToString(bytes);
    }

    ResponseEntity<Map> upload(Applicant a, String kind, String type, byte[] bytes) {
        return it.call(a.token(), HttpMethod.POST, ME + "/documents", Map.of("kind", kind, "filename", kind.toLowerCase() + (type.endsWith("pdf") ? ".pdf" : ".png"),
                "dataUrl", dataUrl(type, bytes)));
    }

    void uploadAll(Applicant a) {
        for (String k : REQUIRED) ok(upload(a, k, "application/pdf", pdf()));
    }

    void submit(Applicant a) {
        assertThat(ok(it.call(a.token(), HttpMethod.POST, ME + "/submit", Map.of("declaration", true)))).containsEntry("state", "SUBMITTED");
    }

    Map<String, Object> detail(String token, Applicant a) {
        return ok(it.get(token, OFFICE + "/applications/" + a.app()));
    }

    void acceptAll(World w, Applicant a) {
        acceptAll(w, a, null);
    }

    /** every current document not yet accepted accepted, but the kind named */
    void acceptAll(World w, Applicant a, String except) {
        for (Map<String, Object> d : (List<Map<String, Object>>) detail(w.academic(), a).get("documents")) {
            if (!"ACCEPTED".equals(d.get("status")) && !String.valueOf(d.get("kind")).equals(except)) {
                ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/documents/" + d.get("id") + "/review", Map.of("verdict", "ACCEPTED")));
            }
        }
    }

    Map<String, Object> act(String token, Applicant a, String action, String note) {
        Map<String, Object> b = new HashMap<>(Map.of("action", action));
        if (note != null) b.put("note", note);
        return ok(it.call(token, HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/act", b));
    }

    /** applied, paid, uploaded, submitted, checked and sent to the Head of Department */
    Applicant withHod(World w, boolean paid) {
        Applicant a = apply(w);
        if (paid) pay(w, a);
        uploadAll(a);
        submit(a);
        acceptAll(w, a);
        assertThat(act(w.academic(), a, "SEND_TO_HOD", null)).containsEntry("state", "WITH_HOD");
        return a;
    }

    Applicant recommended(World w, boolean paid) {
        Applicant a = withHod(w, paid);
        assertThat(ok(it.call(w.hod(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/recommend", Map.of("accept", true, "level", 200,
                "note", "A good transcript; credit for the first-year courses")))).containsEntry("state", "RECOMMENDED");
        return a;
    }

    String xml(String path, String body) {
        return plain.post().uri(path).contentType(MediaType.TEXT_XML).body(body).retrieve().body(String.class);
    }

    static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    static void refused(ResponseEntity<Map> r, int status, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(status);
        assertThat(r.getBody()).as(String.valueOf(r.getBody())).containsEntry("code", code);
    }

    static double num(Object o) {
        return ((Number) o).doubleValue();
    }

    long notices(UUID app, String template) {
        return jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'iut_application' AND about_id = :a AND template_key = :t")
                .param("a", app).param("t", template).query(Long.class).single();
    }

    /* ── 1 · the public door, paying, uploading, submitting ── */

    @Test
    void aStudentOfAnotherUniversityAppliesOnlinePaysUploadsAndSubmits() {
        World w = world();
        // the window opens only with a programme taking transfers and the fee published (a draft is not published)
        refused(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "OPEN")), 422, "IUT_WINDOW_NO_PROGRAMMES");
        ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/lines", Map.of("session", w.session(), "programme", w.programme(), "levels", List.of(200))));
        refused(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "OPEN")), 422, "IUT_WINDOW_FEE_UNPUBLISHED");
        assertThat(ok(it.call(w.bursar(), HttpMethod.PUT, FEES + "/fee", Map.of("session", w.session(), "amount", 5000)))).containsEntry("state", "DRAFT");
        refused(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "OPEN")), 422, "IUT_WINDOW_FEE_UNPUBLISHED");
        assertThat(it.call(w.academic(), HttpMethod.PUT, FEES + "/fee", Map.of("session", w.session(), "amount", 5000)).getStatusCode().value()).isEqualTo(403);
        assertThat(ok(it.call(w.bursar(), HttpMethod.POST, FEES + "/fee/publish", Map.of("session", w.session())))).containsEntry("state", "PUBLISHED");
        Map<String, Object> opened = ok(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "OPEN")));
        assertThat(opened).containsEntry("status", "OPEN");
        assertThat((List<Map<String, Object>>) opened.get("lines")).extracting(l -> l.get("programme") + ":" + l.get("level")).containsExactly(w.programme() + ":200");
        assertThat(it.call(w.bursar(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "OPEN")).getStatusCode().value()).isEqualTo(403);

        // the public options: the line, its levels, no places; the website's feed has the window open
        Map<String, Object> options = ok(it.anon(HttpMethod.GET, PUBLIC + "?session=" + w.session(), null));
        assertThat((Map<String, Object>) options.get("window")).containsEntry("open", true).containsEntry("type", "INTER_UNIVERSITY_TRANSFER_APPLICATION")
                .containsEntry("applicationPath", "/transfer/apply").containsEntry("session", w.session());
        List<Map<String, Object>> programmes = (List<Map<String, Object>>) options.get("programmes");
        assertThat(programmes).extracting(p -> p.get("code") + ":" + p.get("levels")).containsExactly(w.programme() + ":[200]");
        assertThat(String.valueOf(options)).doesNotContain("places");
        assertThat(num(((Map<String, Object>) options.get("fee")).get("amount"))).isEqualTo(5000.0);
        assertThat((List<Map<String, Object>>) options.get("documents")).extracting(d -> d.get("code")).containsAll(REQUIRED);
        Map<String, Object> feed = (Map<String, Object>) ok(it.anon(HttpMethod.GET, "/api/v1/public/application-windows", null)).get("interUniversityTransfer");
        assertThat(feed).containsEntry("open", true).containsEntry("session", w.session()).containsEntry("label", "Inter-university transfer application");

        // applying: a level not opened refused; then made, signed in at once, the fee due
        refused(it.anon(HttpMethod.POST, APPLY, form(w, jamb(), email(), 300)), 422, "IUT_PROGRAMME_NOT_OPEN");
        Map<String, Object> f1 = form(w, jamb(), email(), 200);
        ResponseEntity<Map> made = it.anon(HttpMethod.POST, APPLY, f1);
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        assertThat(String.valueOf(made.getBody().get("applicationNo"))).matches("IUT/APP/" + w.year() + "/\\d{6}");
        Applicant a = new Applicant(String.valueOf(made.getBody().get("token")), UUID.fromString(String.valueOf(made.getBody().get("accountId"))), null,
                String.valueOf(made.getBody().get("applicationNo")), String.valueOf(f1.get("jambRegNo")), String.valueOf(f1.get("email")));
        Map<String, Object> me = ok(it.get(a.token(), ME));
        a = new Applicant(a.token(), a.account(), UUID.fromString(String.valueOf(me.get("id"))), a.no(), a.jamb(), a.email());
        assertThat(me).containsEntry("state", "DRAFT").containsEntry("applicationNo", a.no()).containsEntry("canApplyAgain", false);
        assertThat(num(((Map<String, Object>) me.get("fee")).get("due"))).isEqualTo(5000.0);
        assertThat((Map<String, Object>) me.get("account")).containsEntry("email", a.email());
        assertThat(notices(a.app(), "IUT_APPLICATION:CREATED")).isPositive();
        // one live application under a JAMB number; one account an e-mail; a robot refused
        refused(it.anon(HttpMethod.POST, APPLY, form(w, a.jamb(), email(), 200)), 422, "IUT_JAMB_TAKEN");
        refused(it.anon(HttpMethod.POST, APPLY, form(w, jamb(), a.email(), 200)), 422, "IUT_EMAIL_TAKEN");
        Map<String, Object> robot = form(w, jamb(), email(), 200);
        robot.put("website2", "http://spam.example.com");
        refused(it.anon(HttpMethod.POST, APPLY, robot), 422, "IUT_APPLY_REFUSED");
        Map<String, Object> ownNumber = form(w, jamb(), email(), 200);
        ownNumber.put("password", ownNumber.get("jambRegNo"));
        refused(it.anon(HttpMethod.POST, APPLY, ownNumber), 422, "IUT_PASSWORD");

        // no other applicant's token reaches the transfer applicant's pages; the Bursary has none of the desk
        String otherApplicant = TestTokens.token(UUID.randomUUID(), List.of("applicant"));
        assertThat(it.get(otherApplicant, ME).getStatusCode().value()).isEqualTo(404);
        assertThat(it.call(otherApplicant, HttpMethod.POST, ME + "/fee-reference", Map.of()).getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(w.bursar(), OFFICE + "/applications?session=" + w.session()).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(a.token(), OFFICE + "/applications?session=" + w.session()).getStatusCode().value()).isEqualTo(403);
        // nor does the transfer applicant's token reach another applicant's pages
        assertThat(it.get(a.token(), "/api/v1/pg/me").getStatusCode().is2xxSuccessful()).isFalse();
        assertThat(it.get(a.token(), "/api/v1/applicant/me").getStatusCode().is2xxSuccessful()).isFalse();
        assertThat(it.get(a.token(), "/api/v1/jupeb/me").getStatusCode().is2xxSuccessful()).isFalse();

        // nothing uploaded before the fee; the reference drawn twice is one; another applicant's checkout of it is not found
        refused(upload(a, "TRANSCRIPT", "application/pdf", pdf()), 422, "IUT_FEE_UNPAID");
        String ref = String.valueOf(ok(it.call(a.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        assertThat(ref).matches("MOAUM-IUTAPP-" + w.year() + "-\\d{6}");
        assertThat(ok(it.call(a.token(), HttpMethod.POST, ME + "/fee-reference", Map.of()))).containsEntry("reference", ref).containsEntry("settled", false);
        Applicant b = apply(w);
        assertThat(it.call(b.token(), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", ref, "gateway", "quickteller")).getStatusCode().value()).isEqualTo(404);
        ResponseEntity<Map> own = it.call(a.token(), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", ref, "gateway", "quickteller"));
        assertThat(own.getStatusCode().value()).as(String.valueOf(own.getBody())).isIn(200, 422);
        assertThat(own.getBody()).doesNotContainEntry("code", "IUT_REFERENCE_STALE");
        assertThat(ok(it.get(w.bursar(), "/api/v1/payments/state?reference=" + ref))).containsEntry("confirmed", false);

        // the Bursar confirms it by hand against the bank's record: a receipt in the University's series, verified by its code
        assertThat(it.call(ItSupport.token("studentaccounts"), HttpMethod.POST, FEES + "/payments/" + ref + "/confirm", Map.of("note", "Teller 0042 at the bank"))
                .getStatusCode().value()).isEqualTo(403);
        Map<String, Object> confirmed = ok(it.call(w.bursar(), HttpMethod.POST, FEES + "/payments/" + ref + "/confirm", Map.of("note", "Teller 0042 at the bank")));
        assertThat(confirmed).containsEntry("outcome", "confirmed").containsEntry("settles", true);
        assertThat(String.valueOf(confirmed.get("receiptNo"))).matches("RCT-" + w.year() + "-\\d{5}");
        refused(it.call(a.token(), HttpMethod.POST, ME + "/fee-reference", Map.of()), 422, "IUT_FEE_SETTLED");
        Map<String, Object> receipt = ok(it.get(a.token(), ME + "/receipts/" + ref));
        assertThat(receipt).containsEntry("receiptNo", confirmed.get("receiptNo")).containsEntry("applicationNo", a.no())
                .containsEntry("purpose", "Inter-university transfer application fee");
        assertThat(it.get(b.token(), ME + "/receipts/" + ref).getStatusCode().value()).isEqualTo(404);
        Map<String, Object> genuine = ok(it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + ref + "?c=" + receipt.get("checkCode"), null));
        // named by its own kind: the page words IUT_APPLICATION as the transfer application fee, never the Post-UTME one
        assertThat(genuine).containsEntry("genuine", true).containsEntry("holder", "APPLICANT").containsEntry("applicationNo", a.no()).containsEntry("route", "TRANSFER")
                .containsEntry("feeKind", "IUT_APPLICATION");
        assertThat(ok(it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + ref + "?c=000000000000", null))).containsEntry("genuine", false);
        assertThat(notices(a.app(), "IUT_APPLICATION:PAYMENT_RECEIVED")).isPositive();
        assertThat((List<?>) ok(it.get(w.bursar(), FEES + "/payments?session=" + w.session() + "&state=PAID")).get("rows")).hasSize(1);
        assertThat(ok(it.call(a.token(), HttpMethod.POST, "/api/v1/payments/verify", Map.of("reference", ref)))).containsEntry("outcome", "already confirmed");
        assertThat(it.call(b.token(), HttpMethod.POST, "/api/v1/payments/verify", Map.of("reference", ref)).getStatusCode().value()).isEqualTo(404);
        Map<String, Object> fee = ok(it.get(w.academic(), FEES + "/fee?session=" + w.session()));
        assertThat(fee).containsEntry("state", "PUBLISHED");
        assertThat((List<Map<String, Object>>) fee.get("history")).extracting(x -> x.get("action")).containsExactly("PUBLISHED", "STATED");

        // a payment Interswitch reports (PAYDirect): the reference asked about, then settled through the gateways' own lane
        ok(it.call(ItSupport.token("ict"), HttpMethod.PUT, "/api/v1/payments/gateways/paydirect/key",
                Map.of("secret", "{\"serviceUsername\":\"moaum-it-notify\",\"servicePassword\":\"an-invented-password\"}")));
        String bRef = String.valueOf(ok(it.call(b.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        String ask = "<CustomerInformationRequest><CustReference>" + bRef + "</CustReference></CustomerInformationRequest>";
        assertThat(xml("/api/v1/payments/paydirect/validate", ask)).contains("<Status>0</Status>");
        String logId = String.valueOf(ThreadLocalRandom.current().nextLong(1_000_000_000L, 9_999_999_999L));
        assertThat(xml("/api/v1/payments/paydirect/notify", PaymentsIT.notification("moaum-it-notify", "an-invented-password", bRef, logId, "5000.00", false, false)))
                .contains("<Status>0</Status>");
        assertThat((Map<String, Object>) ok(it.get(b.token(), ME)).get("fee")).containsEntry("settled", true).containsEntry("basis", "PAID");
        assertThat(xml("/api/v1/payments/paydirect/validate", ask)).contains("<Status>1</Status>");
        assertThat(jdbc.sql("SELECT receipt_no FROM admissions.iut_fee_reference WHERE reference = :r").param("r", bRef).query(String.class).single()).startsWith("RCT-");
        // the notice's own words and every identifier it gave the payment (its Payment Log Id, then its payment reference) kept on the
        // reference: a bank credit for it is told to be this payment or another (round 5: v4v-1; round 6: v5v-2, all of them)
        assertThat(jdbc.sql("SELECT channel || '|' || array_to_string(gateway_refs, ',') || '|' || note FROM admissions.iut_fee_reference WHERE reference = :r").param("r", bRef)
                .query(String.class).single()).isEqualTo("Quickteller · WEB|" + logId + ",QT|WEB|" + logId + "|paydirect " + logId + " · 5000.00");

        // a file whose bytes are not its type, and one over 5 MB, refused
        refused(upload(a, "TRANSCRIPT", "application/pdf", png()), 422, "IUT_DOCUMENT_TYPE");
        byte[] big = new byte[5 * 1024 * 1024 + 1];
        System.arraycopy("%PDF-1.4\n".getBytes(), 0, big, 0, 9);
        refused(upload(a, "TRANSCRIPT", "application/pdf", big), 422, "IUT_DOCUMENT_SIZE");

        // submitted only with the required documents; then the acknowledgement, verified by its code
        for (String k : REQUIRED.subList(0, 3)) ok(upload(a, k, "application/pdf", pdf()));
        ok(upload(a, "STUDENT_ID_CARD", "image/png", png()));
        // a document taken off is kept, superseded; uploaded again
        String card = String.valueOf(((List<Map<String, Object>>) ok(it.get(a.token(), ME)).get("documents")).stream()
                .filter(d -> "STUDENT_ID_CARD".equals(d.get("kind"))).findFirst().orElseThrow().get("id"));
        assertThat((List<Map<String, Object>>) ok(it.call(a.token(), HttpMethod.DELETE, ME + "/documents/" + card, null)).get("documents"))
                .extracting(d -> d.get("kind")).doesNotContain("STUDENT_ID_CARD");
        assertThat(it.getBytes(a.token(), ME + "/documents/" + card).getStatusCode().value()).isEqualTo(200);
        ok(upload(a, "STUDENT_ID_CARD", "image/png", png()));
        refused(it.call(a.token(), HttpMethod.POST, ME + "/submit", Map.of("declaration", false)), 422, "IUT_DECLARATION");
        ResponseEntity<Map> missing = it.call(a.token(), HttpMethod.POST, ME + "/submit", Map.of("declaration", true));
        refused(missing, 422, "IUT_DOCUMENTS_MISSING");
        assertThat(String.valueOf(missing.getBody().get("detail"))).contains("O'Level");
        refused(it.get(a.token(), ME + "/acknowledgement"), 422, "IUT_STATE");
        ok(upload(a, "OLEVEL_RESULT", "application/pdf", pdf()));
        String docId = String.valueOf(((List<Map<String, Object>>) ok(it.get(a.token(), ME)).get("documents")).get(0).get("id"));
        ResponseEntity<byte[]> file = it.getBytes(a.token(), ME + "/documents/" + docId);
        assertThat(file.getStatusCode().value()).isEqualTo(200);
        assertThat(new String(file.getBody(), 0, 5)).isEqualTo("%PDF-");
        assertThat(file.getHeaders().getFirst("Content-Security-Policy")).isEqualTo("sandbox");
        assertThat(it.getBytes(b.token(), ME + "/documents/" + docId).getStatusCode().value()).isEqualTo(404);
        submit(a);
        assertThat(notices(a.app(), "IUT_APPLICATION:SUBMITTED")).isPositive();
        Map<String, Object> ack = ok(it.get(a.token(), ME + "/acknowledgement"));
        assertThat(ack).containsEntry("applicationNo", a.no()).containsEntry("session", w.session());
        assertThat((List<?>) ack.get("documents")).hasSize(5);
        // the QR's page carries the number in its query (an encoded slash in a path is refused by the firewall) and asks the API so:
        // the very request the verification page sends, the number's slashes encoded in the query
        assertThat(String.valueOf(ack.get("verifyPath"))).startsWith("/verify/transfer-application?no=IUT%2FAPP%2F").endsWith("&t=" + ack.get("checkCode"));
        ResponseEntity<Map> asThePageAsks = plain.get().uri(java.net.URI.create("http://localhost:" + port + "/api/v1/verify/transfer-application?no="
                + java.net.URLEncoder.encode(a.no(), java.nio.charset.StandardCharsets.UTF_8) + "&t=" + ack.get("checkCode"))).retrieve().toEntity(Map.class);
        assertThat(ok(asThePageAsks)).containsEntry("genuine", true).containsEntry("application_no", a.no());
        Map<String, Object> attested = ok(it.anon(HttpMethod.GET, "/api/v1/verify/transfer-application/" + a.no() + "?t=" + ack.get("checkCode"), null));
        assertThat(attested).containsEntry("genuine", true).containsEntry("application_no", a.no()).containsEntry("level", 200).doesNotContainKey("state");
        assertThat(ok(it.anon(HttpMethod.GET, "/api/v1/verify/transfer-application?no=" + a.no() + "&t=" + ack.get("checkCode"), null))).containsEntry("genuine", true);
        assertThat(ok(it.anon(HttpMethod.GET, "/api/v1/verify/transfer-application/" + a.no() + "?t=ABCDEF012345", null))).containsEntry("genuine", false);
        // the Registry's desk lists it, with the documents to check
        Map<String, Object> list = ok(it.get(w.academic(), OFFICE + "/applications?session=" + w.session() + "&state=SUBMITTED"));
        assertThat((List<Map<String, Object>>) list.get("rows")).extracting(r -> r.get("applicationNo")).containsExactly(a.no());
        assertThat((Map<String, Object>) list.get("counts")).containsEntry("SUBMITTED", 1).containsEntry("DRAFT", 1);

        // signing in by the application number and by the e-mail; the fifth wrong password locks the account
        assertThat(ok(it.anon(HttpMethod.POST, SIGN_IN, Map.of("identifier", a.no().toLowerCase(), "password", PASSWORD)))).containsEntry("applicationNo", a.no());
        assertThat(ok(it.anon(HttpMethod.POST, SIGN_IN, Map.of("identifier", a.email().toUpperCase(), "password", PASSWORD))).get("token")).isNotNull();
        refused(it.anon(HttpMethod.POST, SIGN_IN, Map.of("identifier", "nobody-" + UUID.randomUUID() + "@example.com", "password", PASSWORD)), 422, "AUTH_BAD_CREDENTIALS");
        for (int i = 0; i < 5; i++) refused(it.anon(HttpMethod.POST, SIGN_IN, Map.of("identifier", b.email(), "password", "not the password " + i)), 422, "AUTH_BAD_CREDENTIALS");
        refused(it.anon(HttpMethod.POST, SIGN_IN, Map.of("identifier", b.email(), "password", PASSWORD)), 422, "AUTH_LOCKED");

        // the password changed: the current one first, never the applicant's own number
        refused(it.call(a.token(), HttpMethod.POST, ME + "/password", Map.of("current", "not it at all", "next", "another good password")), 422, "AUTH_BAD_CREDENTIALS");
        refused(it.call(a.token(), HttpMethod.POST, ME + "/password", Map.of("current", PASSWORD, "next", a.no())), 422, "IUT_PASSWORD");
        // changed: every other session of the account ends with the old password (V687's rule), the one making the change goes on
        String s1 = String.valueOf(ok(it.anon(HttpMethod.POST, SIGN_IN, Map.of("identifier", a.email(), "password", PASSWORD))).get("token"));
        String s2 = String.valueOf(ok(it.anon(HttpMethod.POST, SIGN_IN, Map.of("identifier", a.no(), "password", PASSWORD))).get("token"));
        assertThat(ok(it.call(s1, HttpMethod.POST, ME + "/password", Map.of("current", PASSWORD, "next", "a changed password of 2026")))).containsEntry("changed", true);
        assertThat(it.get(s1, ME).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(s2, ME).getStatusCode().value()).isEqualTo(401);
        assertThat(it.get(a.token(), ME).getStatusCode().value()).isEqualTo(401);

        // the public door is throttled by connection: thirty applications, then 429
        String from = "203.0.113." + (ThreadLocalRandom.current().nextInt(250) + 1);
        for (int i = 0; i < 30; i++) {
            ResponseEntity<Map> r = plain.post().uri(APPLY).contentType(MediaType.APPLICATION_JSON).header("X-Forwarded-For", from).body(robot).retrieve().toEntity(Map.class);
            assertThat(r.getStatusCode().value()).as("application " + i).isEqualTo(422);
        }
        ResponseEntity<Map> throttled = plain.post().uri(APPLY).contentType(MediaType.APPLICATION_JSON).header("X-Forwarded-For", from).body(form(w, jamb(), email(), 200))
                .retrieve().toEntity(Map.class);
        refused(throttled, 429, "APP_THROTTLED");

        // a forgotten password: the link goes to the account's e-mail, found by the application number; never one of the numbers
        assertThat(it.anon(HttpMethod.POST, "/api/v1/auth/forgot", Map.of("identifier", a.no())).getStatusCode().value()).isEqualTo(202);
        assertThat(jdbc.sql("SELECT count(*) FROM iam.password_reset WHERE subject_kind = 'IUTAPPLICANT' AND subject_id = :a").param("a", a.account())
                .query(Long.class).single()).isEqualTo(1L);
        assertThat(jdbc.sql("SELECT recipient FROM platform.notice WHERE about_kind = 'iutapplicant' AND about_id = :a AND channel = 'EMAIL'").param("a", a.account())
                .query(String.class).list()).containsExactly(a.email());
        String token = "it-iut-reset-" + UUID.randomUUID();
        UUID account = a.account();
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.password_reset (subject_kind, subject_id, token_hash, expires_at)
                VALUES ('IUTAPPLICANT', :s, encode(sha256(convert_to(:t, 'UTF8')), 'hex'), now() + interval '1 hour')
                """).param("s", account).param("t", token).update());
        refused(it.anon(HttpMethod.POST, "/api/v1/auth/reset", Map.of("token", token, "password", a.jamb().toLowerCase())), 422, "AUTH_PASSWORD_IS_NUMBER");
        ok(it.anon(HttpMethod.POST, "/api/v1/auth/reset", Map.of("token", token, "password", "a new password of mine")));
        refused(it.anon(HttpMethod.POST, SIGN_IN, Map.of("identifier", a.email(), "password", PASSWORD)), 422, "AUTH_BAD_CREDENTIALS");
        assertThat(ok(it.anon(HttpMethod.POST, SIGN_IN, Map.of("identifier", a.email(), "password", "a new password of mine")))).containsEntry("accountId", a.account().toString());
    }

    /* ── 2 · the Registry, the Head of Department, the approval and another officer's decision ── */

    @Test
    void theRegistryChecksTheHeadRecommendsAndAnotherOfficerDecides() {
        World w = world();
        open(w, 5000, null);
        String named = "Invented University of " + letters(6);
        Map<String, Object> f = form(w, jamb(), email(), 200);
        f.remove("universityCode");
        f.put("universityNamed", named);
        Applicant a = applied(f);
        pay(w, a);
        uploadAll(a);
        submit(a);

        // V763's own check of the transfer it would register, shown while submitted: the university is not on the list
        Map<String, Object> seen = detail(w.academic(), a);
        assertThat(((List<Map<String, Object>>) ((Map<String, Object>) seen.get("transferCheck")).get("problems"))).extracting(p -> p.get("code")).contains("UNIVERSITY_MISSING");
        assertThat(ok(it.get(ItSupport.token("records"), OFFICE + "/applications/" + a.app()))).containsEntry("state", "SUBMITTED");
        assertThat(it.call(ItSupport.token("records"), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/act", Map.of("action", "RETURN", "note", "Replace the transcript please"))
                .getStatusCode().value()).isEqualTo(403);

        // the Registry rejects a document (a note the applicant reads) and returns the application
        List<Map<String, Object>> docs = (List<Map<String, Object>>) seen.get("documents");
        String transcript = String.valueOf(docs.stream().filter(d -> "TRANSCRIPT".equals(d.get("kind"))).findFirst().orElseThrow().get("id"));
        refused(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/documents/" + transcript + "/review", Map.of("verdict", "REJECTED")), 422, "IUT_REVIEW_NOTE");
        ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/documents/" + transcript + "/review",
                Map.of("verdict", "REJECTED", "note", "The transcript is not legible; scan it again")));
        acceptAll(w, a, "TRANSCRIPT");
        refused(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/act", Map.of("action", "SEND_TO_HOD")), 422, "IUT_DOCUMENTS_UNCHECKED");
        refused(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/act", Map.of("action", "RETURN", "note", "Replace it", "expectedState", "WITH_HOD")),
                422, "IUT_STATE_MOVED");
        assertThat(act(w.academic(), a, "RETURN", "Replace the transcript marked, then submit again")).containsEntry("state", "CORRECTION_REQUIRED");
        Map<String, Object> mine = ok(it.get(a.token(), ME));
        assertThat((Map<String, Object>) mine.get("notice")).containsEntry("kind", "CORRECTION").containsEntry("note", "Replace the transcript marked, then submit again");
        assertThat(mine).doesNotContainKeys("hod", "registry", "transfer", "superseded");
        assertThat(notices(a.app(), "IUT_APPLICATION:CORRECTION_REQUIRED")).isPositive();

        // the applicant cannot replace an accepted document; replaces the rejected one and submits again
        refused(upload(a, "RELEASE_LETTER", "application/pdf", pdf()), 422, "IUT_DOCUMENT_ACCEPTED");
        ok(upload(a, "TRANSCRIPT", "application/pdf", pdf()));
        submit(a);

        // to the Head of Department only once every document is accepted; the HOD is told
        refused(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/act", Map.of("action", "SEND_TO_HOD")), 422, "IUT_DOCUMENTS_UNCHECKED");
        assertThat(it.get(w.hod(), OFFICE + "/applications/" + a.app()).getStatusCode().value()).isEqualTo(403);   // not yet at the desk
        acceptAll(w, a);
        assertThat(act(w.academic(), a, "SEND_TO_HOD", "Look closely at the second-year results")).containsEntry("state", "WITH_HOD");
        assertThat(notices(a.app(), "IUT_DESK:WITH_HOD")).isPositive();
        // the Registry's note to the department is not the applicant's to read (round 2: screens-brief2-5)
        assertThat((List<Map<String, Object>>) ok(it.get(a.token(), ME)).get("history")).filteredOn(h -> "SENT_TO_HOD".equals(h.get("action"))).hasSize(1)
                .allSatisfy(h -> assertThat(h).doesNotContainKey("note"));
        assertThat(notices(a.app(), "IUT_APPLICATION:WITH_HOD")).isPositive();

        // only the Head of the department of the programme applied for; a Dean of a faculty in no College reads nothing
        assertThat(it.get(w.otherHod(), OFFICE + "/applications/" + a.app()).getStatusCode().value()).isEqualTo(403);
        refused(it.call(w.otherHod(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/recommend", Map.of("accept", true, "level", 200)), 403, "IUT_HOD_OTHER_DEPARTMENT");
        assertThat(it.get(w.dean(), OFFICE + "/applications/" + a.app()).getStatusCode().value()).isEqualTo(403);
        List<Map<String, Object>> desk = (List<Map<String, Object>>) ok(it.get(w.hod(), OFFICE + "/applications?session=" + w.session())).get("rows");
        assertThat(desk).extracting(r -> r.get("applicationNo")).contains(a.no());
        assertThat(desk).allSatisfy(r -> assertThat(r.get("dept")).isEqualTo(w.dept()));
        assertThat((List<Map<String, Object>>) ok(it.get(w.otherHod(), OFFICE + "/applications?session=" + w.session())).get("rows")).isEmpty();
        Map<String, Object> hodView = ok(it.get(w.hod(), OFFICE + "/applications/" + a.app()));
        assertThat((Map<String, Object>) hodView.get("applicant")).doesNotContainKeys("email", "phone");
        assertThat(hodView).doesNotContainKeys("fee", "transfer", "registry", "notice");
        // its history: no fee step, the return listed without the Registry's words to the applicant
        List<Map<String, Object>> hodSteps = (List<Map<String, Object>>) hodView.get("history");
        assertThat(hodSteps).extracting(h -> h.get("action")).doesNotContain("FEE_PAID", "FEE_NONE_DUE", "FEE_PAID_AGAIN").contains("RETURNED", "SENT_TO_HOD");
        assertThat(hodSteps).filteredOn(h -> "RETURNED".equals(h.get("action"))).allSatisfy(h -> assertThat(h).doesNotContainKey("note"));
        assertThat(String.valueOf(hodView)).doesNotContain("Replace the transcript marked").doesNotContain("MOAUM-IUTAPP-").doesNotContain("RCT-")
                .doesNotContain("The transcript is not legible");
        // the rejected transcript named in its history, without the words; the Registry's note to the department kept
        assertThat(hodSteps).filteredOn(h -> "DOCUMENT_REJECTED".equals(h.get("action"))).isNotEmpty()
                .allSatisfy(h -> assertThat(String.valueOf(h.get("note"))).doesNotContain(":"));
        assertThat(hodSteps).filteredOn(h -> "SENT_TO_HOD".equals(h.get("action"))).allSatisfy(h -> assertThat(h).containsEntry("note", "Look closely at the second-year results"));
        assertThat((List<Map<String, Object>>) hodView.get("superseded")).isNotEmpty().allSatisfy(d -> assertThat(d).doesNotContainKey("note"));
        String one = String.valueOf(((List<Map<String, Object>>) hodView.get("documents")).get(0).get("id"));
        ResponseEntity<byte[]> single = it.getBytes(w.hod(), OFFICE + "/applications/" + a.app() + "/documents/" + one);
        assertThat(single.getStatusCode().value()).isEqualTo(200);
        assertThat(single.getHeaders().getFirst("X-Content-Type-Options")).isEqualTo("nosniff");
        assertThat(it.getBytes(w.otherHod(), OFFICE + "/applications/" + a.app() + "/documents/" + one).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<byte[]> all = it.getBytes(w.hod(), OFFICE + "/applications/" + a.app() + "/documents.pdf");
        assertThat(all.getStatusCode().value()).isEqualTo(200);
        assertThat(new String(all.getBody(), 0, 5)).isEqualTo("%PDF-");

        // the recommendation: a level the window opens, by the department; the HOD does not approve
        refused(it.call(w.hod(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/recommend", Map.of("accept", true, "level", 300)), 422, "IUT_LEVEL_NOT_OPEN");
        assertThat(ok(it.call(w.hod(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/recommend",
                Map.of("accept", true, "level", 200, "note", "Strong in the sciences", "expectedState", "WITH_HOD")))).containsEntry("state", "RECOMMENDED");
        assertThat(it.call(w.hod(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/approve", Map.of()).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> waiting = ok(it.get(a.token(), ME));
        assertThat(waiting).doesNotContainKey("hod");
        ResponseEntity<Map> early = it.call(a.token(), HttpMethod.POST, ME + "/withdraw", Map.of());
        refused(early, 422, "IUT_STATE");
        assertThat(String.valueOf(early.getBody())).contains("with the Registry for a decision").contains("Write to the Registry to withdraw it");
        assertThat((List<Map<String, Object>>) waiting.get("history")).extracting(h -> h.get("action")).doesNotContain("RECOMMENDED");

        // not approved while the university is not on the list: the Registry adds it and sets it
        refused(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/approve", Map.of()), 422, "IUT_UNIVERSITY_NOT_LISTED");
        String code = "ZQV" + ThreadLocalRandom.current().nextInt(10000, 99999);
        ok(it.call(w.registrar(), HttpMethod.POST, IUT + "/universities", Map.of("code", code, "name", named)));
        assertThat((Map<String, Object>) ok(it.call(w.registrar(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/university", Map.of("code", code))).get("previous"))
                .containsEntry("universityCode", code).containsEntry("universityNamed", named);

        // approved: a batch of one, source APPLICATION, prepared by the approver, who does not decide it
        Map<String, Object> approved = ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/approve",
                Map.of("approvalRef", "SEN/IUT/" + w.year(), "note", "Approved by the Senate", "expectedState", "RECOMMENDED")));
        assertThat(approved).containsEntry("state", "APPROVED");
        String batch = String.valueOf(approved.get("batchId"));
        String transfer = String.valueOf(approved.get("transferId"));
        assertThat(String.valueOf(approved.get("batchRef"))).matches("IUT/\\d{4}/\\d{6}");
        UUID academicId = jdbc.sql("SELECT prepared_by FROM people.university_transfer WHERE id = :t").param("t", UUID.fromString(transfer)).query(UUID.class).single();
        assertThat(jdbc.sql("SELECT source FROM people.university_transfer_batch WHERE id = :b").param("b", UUID.fromString(batch)).query(String.class).single()).isEqualTo("APPLICATION");
        assertThat(jdbc.sql("SELECT staff_number FROM iam.person WHERE id = :p").param("p", academicId).query(String.class).single()).startsWith("ZZ-IUA-AC-");
        assertThat((List<Map<String, Object>>) ok(it.get(a.token(), ME)).get("history")).extracting(h -> h.get("action")).doesNotContain("APPROVED");
        refused(it.call(w.academic(), HttpMethod.POST, IUT + "/transfers/" + transfer + "/decide", Map.of("approve", true)), 403, "UNIVERSITY_TRANSFER_SAME_OFFICER");
        String newEmail = "moved." + letters(8).toLowerCase() + "@example.com";
        ok(it.call(a.token(), HttpMethod.PUT, ME, Map.of("email", newEmail, "phone", "08099990766")));

        // another officer approves the transfer: the student is on the register, and the application follows
        assertThat(ok(it.call(w.registrar(), HttpMethod.POST, IUT + "/transfers/" + transfer + "/decide", Map.of("approve", true)))).containsEntry("status", "COMPLETED");
        Map<String, Object> admitted = ok(it.get(a.token(), ME));
        assertThat(admitted).containsEntry("state", "ADMITTED");
        String admissionNo = String.valueOf(((Map<String, Object>) admitted.get("student")).get("admissionNo"));
        assertThat(admissionNo).startsWith("MOAUM/ADM/");
        assertThat(jdbc.sql("SELECT s.entry_mode || '|' || s.status || '|' || s.current_level || '|' || coalesce(s.matric_no, '-') || '|' || s.programme_code FROM people.student s WHERE s.admission_no = :n")
                .param("n", admissionNo).query(String.class).single()).isEqualTo("TRANSFER|ADMITTED|200|-|" + w.programme());
        assertThat(jdbc.sql("SELECT student_id IS NOT NULL FROM admissions.iut_application WHERE id = :a").param("a", a.app()).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT c.email || ' ' || c.phone FROM people.student_contact c JOIN people.student s ON s.id = c.student_id WHERE s.admission_no = :n")
                .param("n", admissionNo).query(String.class).single()).isEqualTo(newEmail + " 08099990766");
        assertThat(notices(a.app(), "IUT_APPLICATION:ADMITTED")).isPositive();
        refused(it.call(a.token(), HttpMethod.PUT, ME, Map.of("phone", "08011112222")), 422, "IUT_NOT_EDITABLE");

        // the student signs in at the student door with the admission number and the application's password: the account carried over
        assertThat((Map<String, Object>) admitted.get("student")).containsEntry("portalOpened", false);
        ResponseEntity<Map> student = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", admissionNo, "password", PASSWORD));
        assertThat(student.getStatusCode().value()).as(String.valueOf(student.getBody())).isEqualTo(200);
        assertThat(student.getBody().get("token")).isNotNull();
        assertThat(jdbc.sql("SELECT count(*) FROM iam.student_account sa JOIN people.student s ON s.id = sa.student_id WHERE s.admission_no = :n")
                .param("n", admissionNo).query(Long.class).single()).isEqualTo(1L);
        // from then on the student portal keeps its own password: the applicant's page says so (round 3: screens-brief3-3)
        assertThat((Map<String, Object>) ok(it.get(a.token(), ME)).get("student")).containsEntry("portalOpened", true);

        // the Inter-University Transfer page's batch names the application
        Map<String, Object> onPage = ok(it.get(w.registrar(), IUT + "/" + batch));
        assertThat(onPage).containsEntry("source", "APPLICATION");
        assertThat((Map<String, Object>) ((List<Map<String, Object>>) onPage.get("transfers")).get(0).get("application")).containsEntry("applicationNo", a.no())
                .containsEntry("id", a.app().toString());
        // the office's view: the transfer, the history with names
        Map<String, Object> office = detail(w.registrar(), a);
        assertThat((Map<String, Object>) office.get("transfer")).containsEntry("status", "COMPLETED");
        assertThat((List<Map<String, Object>>) office.get("history")).extracting(h -> h.get("action")).contains("RETURNED", "RESUBMITTED", "SENT_TO_HOD", "RECOMMENDED",
                "UNIVERSITY_SET", "APPROVED", "ADMITTED");
        assertThat(office).doesNotContainKey("transferCheck");
    }

    /* ── 3 · a transfer rejected by the second officer, the Registry's rejection, withdrawals, money owed back ── */

    @Test
    void aTransferRejectedThereReturnsToTheRegistryAndTheRegistrysRejectionIsTold() {
        World w = world();
        open(w, 5000, null);
        Applicant c = recommended(w, true);

        // approved, then rejected by another officer: back at the Registry's desk, the applicant told nothing
        Map<String, Object> approved = ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + c.app() + "/approve", Map.of()));
        String batch = String.valueOf(approved.get("batchId"));
        String transfer = String.valueOf(approved.get("transferId"));
        assertThat(ok(it.call(w.registrar(), HttpMethod.POST, IUT + "/transfers/" + transfer + "/decide",
                Map.of("approve", false, "note", "The university on the transfer is the wrong one")))).containsEntry("status", "REJECTED");
        Map<String, Object> back = detail(w.academic(), c);
        assertThat(back).containsEntry("state", "RECOMMENDED");
        assertThat(back.get("transfer")).isNull();
        assertThat(jdbc.sql("SELECT transfer_id IS NULL FROM admissions.iut_application WHERE id = :a").param("a", c.app()).query(Boolean.class).single()).isTrue();
        assertThat(notices(c.app(), "IUT_APPLICATION:REJECTED")).isZero();
        assertThat((List<Map<String, Object>>) ok(it.get(c.token(), ME)).get("history")).extracting(h -> h.get("action")).doesNotContain("APPROVED", "TRANSFER_REJECTED");
        // the rejected transfer still names its application on the Inter-University Transfer page, through the history
        assertThat((Map<String, Object>) ((List<Map<String, Object>>) ok(it.get(w.registrar(), IUT + "/" + batch)).get("transfers")).get(0).get("application"))
                .containsEntry("applicationNo", c.no());

        // approved again (a new batch of one): no longer withdrawn by the applicant
        Map<String, Object> again = ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + c.app() + "/approve", Map.of()));
        assertThat(again.get("batchId")).isNotEqualTo(batch);
        refused(it.call(c.token(), HttpMethod.POST, ME + "/withdraw", Map.of("reason", "I changed my mind")), 422, "IUT_STATE");
        ok(it.call(w.registrar(), HttpMethod.POST, IUT + "/transfers/" + again.get("transferId") + "/decide", Map.of("approve", false, "note", "The record is to be checked again")));

        // the Registry's own rejection is told, with its reason
        refused(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + c.app() + "/act", Map.of("action", "REJECT", "note", "short")), 422, "IUT_NOTE");
        assertThat(act(w.academic(), c, "REJECT", "The CGPA is below what the department admits")).containsEntry("state", "REJECTED");
        assertThat(notices(c.app(), "IUT_APPLICATION:REJECTED")).isPositive();
        Map<String, Object> told = ok(it.get(c.token(), ME));
        assertThat((Map<String, Object>) told.get("notice")).containsEntry("kind", "REJECTED").containsEntry("note", "The CGPA is below what the department admits");
        // the Head of Department reads that it was rejected, never the Registry's reason (written for the applicant)
        Map<String, Object> atDesk = ok(it.get(w.hod(), OFFICE + "/applications/" + c.app()));
        assertThat(atDesk).containsEntry("state", "REJECTED").doesNotContainKeys("notice", "registry");
        assertThat((List<Map<String, Object>>) atDesk.get("history")).filteredOn(h -> "REJECTED".equals(h.get("action"))).hasSize(1)
                .allSatisfy(h -> assertThat(h).doesNotContainKey("note"));
        assertThat(String.valueOf(atDesk)).doesNotContain("The CGPA is below what the department admits");
        assertThat(told).containsEntry("canApplyAgain", false);   // the window open now is the session already applied in
        Map<String, Object> again2 = form(w, c.jamb(), c.email(), 200);
        again2.remove("email");
        again2.remove("phone");
        again2.remove("password");
        refused(it.call(c.token(), HttpMethod.POST, ME + "/applications", again2), 422, "IUT_ALREADY_APPLIED");

        // a withdrawal while with the department; a second payment of one application is owed back
        Applicant d = apply(w);
        String first = String.valueOf(ok(it.call(d.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        it.db(() -> jdbc.sql("UPDATE admissions.iut_fee_reference SET expires_at = now() - interval '1 minute' WHERE reference = :r").param("r", first).update());
        String second = pay(w, d);
        assertThat(second).isNotEqualTo(first);
        assertThat(ok(it.call(w.bursar(), HttpMethod.POST, FEES + "/payments/" + first + "/confirm", Map.of("note", "Teller 0043, paid late")))).containsEntry("settles", false);
        uploadAll(d);
        submit(d);
        acceptAll(w, d);
        act(w.academic(), d, "SEND_TO_HOD", null);
        Map<String, Object> withdrawn = ok(it.call(d.token(), HttpMethod.POST, ME + "/withdraw", Map.of("reason", "I have accepted another offer")));
        assertThat(withdrawn).containsEntry("state", "WITHDRAWN");
        assertThat(notices(d.app(), "IUT_APPLICATION:WITHDRAWN")).isPositive();

        // a reference of a withdrawn application is not taken to a gateway; paid anyway, it is owed back
        Applicant e = apply(w);
        String stale = String.valueOf(ok(it.call(e.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        ok(it.call(e.token(), HttpMethod.POST, ME + "/withdraw", Map.of()));
        refused(it.call(e.token(), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", stale, "gateway", "quickteller")), 422, "IUT_REFERENCE_STALE");
        assertThat(ok(it.call(w.bursar(), HttpMethod.POST, FEES + "/payments/" + stale + "/confirm", Map.of("note", "Teller 0044, after the withdrawal")))).containsEntry("settles", false);

        Map<String, Object> owed = ok(it.get(w.bursar(), FEES + "/payments?session=" + w.session() + "&state=owed_back"));
        assertThat((List<Map<String, Object>>) owed.get("rows")).extracting(r -> r.get("reference") + ":" + r.get("owedBack")).containsExactlyInAnyOrder(first + ":true", stale + ":true");
        assertThat(num(((Map<String, Object>) owed.get("totals")).get("owedBackAmount"))).isEqualTo(10000.0);
        Map<String, Object> every = ok(it.get(ItSupport.token("audit"), FEES + "/payments?session=" + w.session()));
        assertThat(((Map<String, Object>) every.get("totals")).get("paid")).isEqualTo(4);
        assertThat(((Map<String, Object>) every.get("totals")).get("refunded")).isEqualTo(0);
        assertThat(it.get(w.academic(), FEES + "/payments?session=" + w.session()).getStatusCode().value()).isEqualTo(403);
        // the refund desk finds the payer of a payment owed back by its reference
        Map<String, Object> onDesk = ok(it.get(w.bursar(), "/api/v1/finance/refunds/transaction?reference=" + first));
        assertThat(onDesk).containsEntry("number", d.no());
        assertThat(String.valueOf(onDesk.get("payer"))).startsWith("ZZAUDU");
        // the application fee itself is not refunded: the payment that settled the application is refused at the refund desk
        String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar")), checker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        refused(it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("payer", String.valueOf(onDesk.get("payer")),
                "reason", "TransferApplicationIT: the application fee asked back", "amount", 5000, "source", second)), 422, "REFUND_IUT_SETTLES");
        // the payment owed back is given back: raised by one officer, approved by another; it leaves the list owed back
        Map<String, Object> raised = ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/refunds", Map.of("payer", String.valueOf(onDesk.get("payer")),
                "reason", "TransferApplicationIT: the second payment given back", "amount", 5000, "source", first)));
        UUID refundId = jdbc.sql("SELECT id FROM finance.refund WHERE reference = :r").param("r", String.valueOf(raised.get("reference"))).query(UUID.class).single();
        // the refund desk's list names the applicant by the application number, as it names a JUPEB applicant (round 4: api-screens4-5)
        List<Map<String, Object>> refunds = (List<Map<String, Object>>) it.callList(maker, HttpMethod.GET, "/api/v1/finance/refunds", null).getBody();
        assertThat(refunds).filteredOn(r -> refundId.toString().equals(String.valueOf(r.get("id")))).extracting(r -> r.get("number")).containsExactly(d.no());
        ok(it.call(checker, HttpMethod.POST, "/api/v1/finance/refunds/" + refundId + "/approve", Map.of()));
        Map<String, Object> stillOwed = ok(it.get(w.bursar(), FEES + "/payments?session=" + w.session() + "&state=owed_back"));
        assertThat((List<Map<String, Object>>) stillOwed.get("rows")).extracting(r -> r.get("reference")).containsExactly(stale);
        assertThat((Map<String, Object>) stillOwed.get("totals")).containsEntry("owedBack", 1);
        assertThat(num(((Map<String, Object>) stillOwed.get("totals")).get("owedBackAmount"))).isEqualTo(5000.0);
        Map<String, Object> givenBack = ((List<Map<String, Object>>) ok(it.get(w.bursar(), FEES + "/payments?session=" + w.session() + "&q=" + first)).get("rows")).get(0);
        assertThat(givenBack).containsEntry("owedBack", false);
        assertThat(num(givenBack.get("refunded"))).isEqualTo(5000.0);
        // the applicant's page and the Registry's desk read it given back too, never still owed (round 3: screens-brief3-2)
        for (Map<String, Object> view : List.of(ok(it.get(d.token(), ME)), detail(w.academic(), d))) {
            List<Map<String, Object>> refs = (List<Map<String, Object>>) ((Map<String, Object>) view.get("fee")).get("references");
            assertThat(refs).filteredOn(r -> first.equals(r.get("reference"))).extracting(r -> num(r.get("refunded"))).containsExactly(5000.0);
            assertThat(refs).filteredOn(r -> second.equals(r.get("reference"))).extracting(r -> num(r.get("refunded"))).containsExactly(0.0);
        }
        // the payments view carries the transfer applicant's payments for the ledger and the reports
        assertThat(jdbc.sql("SELECT count(*) FROM reporting.payments WHERE source = 'IUT' AND iut_application_id = :a AND confirmed_at IS NOT NULL").param("a", d.app())
                .query(Long.class).single()).isEqualTo(2L);
    }

    /* ── 4 · a fee of nothing, a closed window, places filled, a window in use ── */

    @Test
    void aZeroFeeAClosedWindowAndFilledPlaces() {
        World w = world();
        open(w, 0, 1);
        assertThat(it.callList(w.academic(), HttpMethod.PUT, OFFICE + "/document-kinds", Map.of("code", "OTHER", "hint", "A letter of recommendation, for example"))
                .getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(w.bursar(), HttpMethod.PUT, OFFICE + "/document-kinds", Map.of("code", "OTHER", "hint", "Not the Bursary's"))
                .getStatusCode().value()).isEqualTo(403);

        // nothing due: settled at registration, uploads open at once
        Applicant g = apply(w);
        Map<String, Object> me = ok(it.get(g.token(), ME));
        assertThat((Map<String, Object>) me.get("fee")).containsEntry("settled", true).containsEntry("basis", "NONE_DUE");
        assertThat(ok(it.call(g.token(), HttpMethod.POST, ME + "/fee-reference", Map.of()))).containsEntry("settled", true).containsEntry("due", 0);
        uploadAll(g);
        Applicant h = apply(w);    // a draft made before the window closes
        Applicant i = apply(w);
        // the applicant changes a particular and the level while the window is open
        Map<String, Object> edited = ok(it.call(h.token(), HttpMethod.PUT, ME, Map.of("otherNames", "Grace Ene Ojonugwa")));
        assertThat((Map<String, Object>) edited.get("applicant")).containsEntry("otherNames", "Grace Ene Ojonugwa");
        refused(it.call(h.token(), HttpMethod.PUT, ME, Map.of("level", 300)), 422, "IUT_PROGRAMME_NOT_OPEN");

        // one place: G admitted, I refused at approval
        submit(g);
        acceptAll(w, g);
        act(w.academic(), g, "SEND_TO_HOD", null);
        ok(it.call(w.hod(), HttpMethod.POST, OFFICE + "/applications/" + g.app() + "/recommend", Map.of("accept", true, "level", 200)));
        String transfer = String.valueOf(ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + g.app() + "/approve", Map.of())).get("transferId"));
        ok(it.call(w.registrar(), HttpMethod.POST, IUT + "/transfers/" + transfer + "/decide", Map.of("approve", true)));
        assertThat(ok(it.get(g.token(), ME))).containsEntry("state", "ADMITTED");
        uploadAll(i);
        submit(i);
        acceptAll(w, i);
        act(w.academic(), i, "SEND_TO_HOD", null);
        ok(it.call(w.hod(), HttpMethod.POST, OFFICE + "/applications/" + i.app() + "/recommend", Map.of("accept", true, "level", 200)));
        refused(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + i.app() + "/approve", Map.of()), 422, "IUT_PLACES_FILLED");
        // the open window's only line is not closed to new applications: the window would offer nothing (round 2: screens-brief2-3)
        refused(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/lines",
                Map.of("session", w.session(), "programme", w.programme(), "level", 200, "places", 1, "accepting", false)), 422, "IUT_WINDOW_NO_PROGRAMMES");
        // with another line taking transfers, the line closed to new applications, then opened again; the counts by the level recommended
        ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/lines", Map.of("session", w.session(), "programme", w.programme(), "levels", List.of(300))));
        assertThat((List<Map<String, Object>>) ok(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/lines",
                Map.of("session", w.session(), "programme", w.programme(), "level", 200, "places", 1, "accepting", false))).get("lines"))
                .extracting(l -> l.get("level") + ":" + l.get("accepting")).containsExactly("200:false", "300:true");
        refused(it.anon(HttpMethod.POST, APPLY, form(w, jamb(), email(), 200)), 422, "IUT_PROGRAMME_NOT_OPEN");
        Map<String, Object> lines = ok(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/lines",
                Map.of("session", w.session(), "programme", w.programme(), "level", 200, "places", 1, "accepting", true)));
        assertThat((List<Map<String, Object>>) lines.get("lines")).filteredOn(l -> Integer.valueOf(200).equals(l.get("level")))
                .extracting(l -> l.get("applications") + ":" + l.get("admitted") + ":" + l.get("places")).containsExactly("3:1:1");
        // the line at 300, never applied on, is removed again (another line takes transfers)
        ok(it.call(w.academic(), HttpMethod.DELETE, OFFICE + "/lines?session=" + w.session() + "&programme=" + w.programme() + "&level=300", null));

        // closed: a new application refused with the window's message; a draft made before still uploads and submits, its level fixed
        Map<String, Object> closed = ok(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "CLOSED")));
        assertThat(closed).containsEntry("status", "CLOSED");
        ResponseEntity<Map> late = it.anon(HttpMethod.POST, APPLY, form(w, jamb(), email(), 200));
        refused(late, 422, "IUT_WINDOW_CLOSED");
        assertThat((Map<String, Object>) late.getBody().get("remedy")).containsEntry("message", CLOSED_MESSAGE);
        Map<String, Object> shut = (Map<String, Object>) ok(it.anon(HttpMethod.GET, PUBLIC + "?session=" + w.session(), null)).get("window");
        assertThat(shut).containsEntry("open", false).containsEntry("message", CLOSED_MESSAGE);
        refused(it.call(h.token(), HttpMethod.PUT, ME, Map.of("programme", w.programme(), "level", 300)), 422, "IUT_WINDOW_CLOSED");
        uploadAll(h);
        submit(h);

        // a window with applications is not taken back to draft; a line applied on is not removed
        refused(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "DRAFT")), 422, "IUT_WINDOW_IN_USE");
        refused(it.call(w.academic(), HttpMethod.DELETE, OFFICE + "/lines?session=" + w.session() + "&programme=" + w.programme() + "&level=200", null), 422, "IUT_LINE_IN_USE");
        assertThat(it.call(w.registrar(), HttpMethod.DELETE, OFFICE + "/lines?session=" + w.session() + "&programme=" + w.programme() + "&level=200", null)
                .getStatusCode().value()).isEqualTo(422);
        List<Map<String, Object>> programmes = (List<Map<String, Object>>) (List<?>) it.getList(w.academic(), OFFICE + "/programmes").getBody();
        assertThat(programmes).anySatisfy(p -> assertThat(p.get("code")).isEqualTo(w.programme()));
        List<Map<String, Object>> kinds = (List<Map<String, Object>>) (List<?>) it.getList(w.academic(), OFFICE + "/document-kinds").getBody();
        assertThat(kinds).filteredOn(k -> "OTHER".equals(k.get("code"))).extracting(k -> k.get("hint")).containsExactly("A letter of recommendation, for example");
        assertThat((Map<String, Object>) ok(it.get(w.academic(), OFFICE + "/summary?session=" + w.session())).get("counts"))
                .containsEntry("ADMITTED", 1).containsEntry("RECOMMENDED", 1).containsEntry("SUBMITTED", 1);
        // nothing was charged: no reference drawn in the session
        assertThat(((Map<String, Object>) ok(it.get(w.bursar(), FEES + "/payments?session=" + w.session())).get("totals")).get("drawn")).isEqualTo(0);
    }

    /* ── 5 · the review: the applicant reads no verdict before the decision (D11); a student already here is never admitted online ── */

    @Test
    void theApplicantReadsNoVerdictAndAStudentAlreadyHereIsNeverAdmittedOnline() {
        World w = world();
        open(w, 5000, null);

        // declined by the Head: the applicant reads WITH_REGISTRY, in the view and in the list of applications, never the verdict
        Applicant a = withHod(w, true);
        ok(it.call(w.hod(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/recommend", Map.of("accept", false, "note", "The CGPA is below what the department admits")));
        Map<String, Object> me = ok(it.get(a.token(), ME));
        assertThat(me).containsEntry("state", "WITH_REGISTRY");
        assertThat((List<Map<String, Object>>) me.get("applications")).extracting(x -> x.get("state")).containsExactly("WITH_REGISTRY");
        assertThat(String.valueOf(me)).doesNotContain("RECOMMENDED");
        // sent back, recommended, approved: still WITH_REGISTRY, and a withdrawal refused in words that never name the approval
        act(w.academic(), a, "SEND_BACK_TO_HOD", "Look again at the second-year results please");
        ok(it.call(w.hod(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/recommend", Map.of("accept", true, "level", 200)));
        assertThat(ok(it.get(a.token(), ME))).containsEntry("state", "WITH_REGISTRY");
        String transfer = String.valueOf(ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + a.app() + "/approve", Map.of())).get("transferId"));
        me = ok(it.get(a.token(), ME));
        assertThat(me).containsEntry("state", "WITH_REGISTRY");
        assertThat(String.valueOf(me)).doesNotContain("RECOMMENDED").doesNotContain("APPROVED");
        ResponseEntity<Map> withdraw = it.call(a.token(), HttpMethod.POST, ME + "/withdraw", Map.of());
        refused(withdraw, 422, "IUT_STATE");
        assertThat(String.valueOf(withdraw.getBody()).toLowerCase()).doesNotContain("approv").doesNotContain("deciding");
        // the Head of Department's history: no fee step, no transfer, no note of the approval
        Map<String, Object> hodView = ok(it.get(w.hod(), OFFICE + "/applications/" + a.app()));
        List<Map<String, Object>> hodHistory = (List<Map<String, Object>>) hodView.get("history");
        assertThat(hodHistory).extracting(h -> h.get("action")).doesNotContain("FEE_PAID").contains("APPROVED");
        assertThat(hodHistory).allSatisfy(h -> assertThat(h).doesNotContainKey("transferId"));
        assertThat(hodHistory).filteredOn(h -> "APPROVED".equals(h.get("action"))).allSatisfy(h -> assertThat(h.get("note")).isNull());
        assertThat(String.valueOf(hodHistory)).doesNotContain("MOAUM-IUTAPP-").doesNotContain("RCT-");
        // admitted: the applicant reads ADMITTED and the level admitted at
        ok(it.call(w.registrar(), HttpMethod.POST, IUT + "/transfers/" + transfer + "/decide", Map.of("approve", true)));
        me = ok(it.get(a.token(), ME));
        assertThat(me).containsEntry("state", "ADMITTED");
        assertThat((Map<String, Object>) me.get("student")).containsEntry("level", 200);

        // a student already on the register under the JAMB number, at the placement recommended: the desk sees V763's own reading, the
        // approval is refused
        Applicant b = recommended(w, true);
        String surname = it.freeSurname("ZZIUTHERE");
        String matric = it.freeNumber("MOAUM/ZZ/26/", 5);
        UUID here = it.student(surname, w.programme(), it.freeNumber("MOAUM/ADM/26/9", 5), matric, 200);
        it.db(() -> jdbc.sql("UPDATE people.student SET jamb_reg_no = :j WHERE id = :s").param("j", b.jamb()).param("s", here).update());
        assertThat((Map<String, Object>) detail(w.academic(), b).get("transferCheck")).containsEntry("action", "RECORD_ON_EXISTING");
        refused(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + b.app() + "/approve", Map.of()), 422, "IUT_STUDENT_EXISTS");
        assertThat(ok(it.get(b.token(), ME))).containsEntry("state", "WITH_REGISTRY");
        // and an application ever put ADMITTED on such a record (by hand) carries no password to the student door: the record's own
        // student is not opened with the applicant's password
        it.db(() -> jdbc.sql("UPDATE admissions.iut_application SET state = 'ADMITTED', student_id = :s WHERE id = :a").param("s", here).param("a", b.app()).update());
        ResponseEntity<Map> door = it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", PASSWORD));
        assertThat(door.getStatusCode().value()).as(String.valueOf(door.getBody())).isNotEqualTo(200);
        assertThat(jdbc.sql("SELECT count(*) FROM iam.student_account WHERE student_id = :s").param("s", here).query(Long.class).single()).isZero();
    }

    /* ── 6 · the third review: a draft under another person's JAMB number ended by the Registry; the fourth: money at the bank for a
     *       reference confirmed from the bank's record meanwhile posted as that money, for one paid by card online meanwhile not posted;
     *       the round-4 verification: posted as that money only on evidence (the teller named, the Payment Log Id the notice kept), a
     *       second payment through PAYDirect never posted as nothing; the round-5 verification: every identifier the notice gave kept
     *       (a row by its payment reference alone is that payment), a hand note naming the teller of another bank's credit is not
     *       evidence, and one payment takes one credit; round 7: a reference confirmed by hand takes no bank credit at all ── */

    @Test
    void theRegistryEndsADraftUnderAnotherPersonsNumberAndABankCreditOnAReferencePaidByCardOnlineIsNotPosted() {
        World w = world();
        open(w, 5000, null);

        // a stranger registers under someone's JAMB number, draws a reference and never pays: the number's owner is refused
        Applicant stranger = apply(w);
        String drawn = String.valueOf(ok(it.call(stranger.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        refused(it.anon(HttpMethod.POST, APPLY, form(w, stranger.jamb(), email(), 200)), 422, "IUT_JAMB_TAKEN");
        // the Registry finds the draft by the number and ends it (the department cannot); the account that made it is told why
        Map<String, Object> found = ok(it.get(w.academic(), OFFICE + "/applications?session=" + w.session() + "&q=" + stranger.jamb()));
        assertThat((List<Map<String, Object>>) found.get("rows")).extracting(r -> r.get("state")).containsExactly("DRAFT");
        String why = "Made under another person's JAMB number; its owner asked the Registry";
        assertThat(it.call(w.hod(), HttpMethod.POST, OFFICE + "/applications/" + stranger.app() + "/act", Map.of("action", "REJECT", "note", why))
                .getStatusCode().value()).isEqualTo(403);
        refused(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + stranger.app() + "/act", Map.of("action", "RETURN", "note", why)), 422, "IUT_STATE");
        assertThat(ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/applications/" + stranger.app() + "/act",
                Map.of("action", "REJECT", "note", why, "expectedState", "DRAFT")))).containsEntry("state", "REJECTED");
        assertThat(notices(stranger.app(), "IUT_APPLICATION:REJECTED")).isPositive();
        Map<String, Object> told = ok(it.get(stranger.token(), ME));
        assertThat((Map<String, Object>) told.get("notice")).containsEntry("kind", "REJECTED").containsEntry("note", why);
        assertThat(told).doesNotContainKey("submittedAt");
        // its reference is no longer taken to a gateway; the number's owner applies under it
        refused(it.call(stranger.token(), HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", drawn, "gateway", "quickteller")), 422, "IUT_REFERENCE_STALE");
        Applicant owner = applied(form(w, stranger.jamb(), email(), 200));
        assertThat(ok(it.get(owner.token(), ME))).containsEntry("state", "DRAFT");

        // money at the bank (a teller) proposed against the owner's reference; the Bursar then confirms the reference by hand from that
        // same teller on the bank's record, naming it. A reference confirmed by hand takes no bank credit (round 7: a note is free text,
        // and no reading of it tells this teller from a second payment it also names, or the same number at another branch): the
        // approval is refused with the hand confirmation's words — its date, receipt and note — and the officer is told to check the
        // bank's record and reject the proposal; the bank shows the one payment, the proposal is rejected and nothing is owed back
        String ref = String.valueOf(ok(it.call(owner.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        String maker = TestTokens.token(UUID.randomUUID(), List.of("bursar")), checker = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String teller = "Teller " + ThreadLocalRandom.current().nextInt(100_000_000, 1_000_000_000);
        String credit = String.valueOf(ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits",
                Map.of("receivedOn", today().toString(), "bank", "First Bank", "instrument", teller, "amount", 5000, "payer", "ZZAUDU GRACE"))).get("id"));
        ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit + "/propose", Map.of("reference", ref, "why", "The teller names the transfer application reference")));
        String byHand = "First Bank " + teller + ", from the bank's record";
        Map<String, Object> handConfirmed = ok(it.call(w.bursar(), HttpMethod.POST, FEES + "/payments/" + ref + "/confirm", Map.of("note", byHand)));
        assertThat(handConfirmed).containsEntry("settles", true);
        ResponseEntity<Map> onHand = it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit + "/approve", Map.of());
        refused(onHand, 422, "IUT_FEE_ALREADY_PAID");
        assertThat(String.valueOf(onHand.getBody().get("detail")))
                .contains("was confirmed by hand by the Bursar on ").contains("(receipt " + handConfirmed.get("receiptNo") + ", \"" + byHand + "\")")
                .contains("a reference confirmed by hand takes no bank credit, so this bank credit (First Bank · " + teller + ") is not posted to it");
        assertThat(String.valueOf(((Map<String, Object>) onHand.getBody().get("remedy")).get("message")))
                .startsWith("Reject this proposal once the bank's record is checked. The money is owed back only if the record shows it twice");
        assertThat(jdbc.sql("SELECT state || ':' || (posted_reference IS NULL) FROM finance.bank_credit WHERE id = :c").param("c", UUID.fromString(credit))
                .query(String.class).single()).isEqualTo("PROPOSED:true");
        ok(it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit + "/reject", Map.of("why", "The bank shows the one payment, confirmed by hand")));
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.iut_fee_reference WHERE reference = :r AND confirmed_at IS NOT NULL").param("r", ref).query(Long.class).single())
                .isEqualTo(1L);
        Map<String, Object> once = ok(it.get(w.bursar(), FEES + "/payments?session=" + w.session() + "&q=" + ref));
        assertThat((Map<String, Object>) once.get("totals")).containsEntry("paid", 1).containsEntry("owedBack", 0);

        // another applicant's teller proposed; the applicant then pays by card online (Paystack's signed notice): two payments. The
        // approval refuses to post the bank's money onto the reference, naming the card payment and telling the officer to check the
        // bank's record before anything is refunded; the credit stays proposed, for rejection
        Applicant card = apply(w);
        String cardRef = String.valueOf(ok(it.call(card.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        String credit2 = String.valueOf(ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits",
                Map.of("receivedOn", today().toString(), "bank", "First Bank", "instrument", "Teller " + letters(6), "amount", 5000, "payer", "ZZAUDU GRACE"))).get("id"));
        ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit2 + "/propose", Map.of("reference", cardRef, "why", "The teller names the transfer application reference")));
        String body = "{\"event\":\"charge.success\",\"data\":{\"reference\":\"" + cardRef + "\",\"amount\":500000,\"status\":\"success\",\"id\":"
                + ThreadLocalRandom.current().nextInt(1_000_000, 9_999_999) + "}}";
        ResponseEntity<Map> paystack = plain.post().uri("/api/v1/payments/webhook/paystack").contentType(MediaType.APPLICATION_JSON)
                .header("x-paystack-signature", PaymentsService.hmacSha512Hex(PAYSTACK_SECRET, body)).body(body).retrieve().toEntity(Map.class);
        assertThat(ok(paystack)).containsEntry("outcome", "confirmed");
        assertThat(jdbc.sql("SELECT channel || ':' || settles FROM admissions.iut_fee_reference WHERE reference = :r").param("r", cardRef).query(String.class).single())
                .isEqualTo("Card · Paystack:true");
        ResponseEntity<Map> posted = it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit2 + "/approve", Map.of());
        refused(posted, 422, "IUT_FEE_ALREADY_PAID");
        assertThat(String.valueOf(posted.getBody().get("detail"))).contains("paid by card online").contains("Card · Paystack");
        assertThat(String.valueOf(((Map<String, Object>) posted.getBody().get("remedy")).get("message")))
                .startsWith("Reject the proposal either way, once the bank's record is checked").contains("If it shows the money twice");
        assertThat(jdbc.sql("SELECT state || ':' || (posted_reference IS NULL) FROM finance.bank_credit WHERE id = :c").param("c", UUID.fromString(credit2))
                .query(String.class).single()).isEqualTo("PROPOSED:true");
        ok(it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit2 + "/reject", Map.of("why", "Paid by card online meanwhile; the bank shows a second payment")));
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.iut_fee_reference WHERE reference = :r AND confirmed_at IS NOT NULL").param("r", cardRef).query(Long.class).single())
                .isEqualTo(1L);

        // Interswitch's settlement report holds a payment the portal was never told of: its row goes to the bank credits. Interswitch's
        // notice of that same payment then confirms the reference, its Payment Log Id kept: the approval knows the credit is that payment
        // and posts it, nothing owed back (round 5: v4v-1)
        ok(it.call(ItSupport.token("ict"), HttpMethod.PUT, "/api/v1/payments/gateways/paydirect/key",
                Map.of("secret", "{\"serviceUsername\":\"moaum-it-notify\",\"servicePassword\":\"an-invented-password\"}")));
        Applicant reported = apply(w);
        String reportedRef = String.valueOf(ok(it.call(reported.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        String log = String.valueOf(ThreadLocalRandom.current().nextLong(1_000_000_000L, 9_999_999_999L));
        ResponseEntity<Map> report = it.call(ItSupport.token("audit"), HttpMethod.POST, "/api/v1/finance/settlements", Map.of("label", "IT V766 " + log, "fileName", "settlement.csv",
                "rows", List.of(Map.of("settledOn", today().toString(), "paidOn", today().toString(), "reference", reportedRef, "logId", log, "amount", "5000", "fee", "0",
                        "channel", "Bank Branch", "payer", "ZZAUDU GRACE"))));
        assertThat(report.getStatusCode().value()).as(String.valueOf(report.getBody())).isEqualTo(200);
        String item = ((List<Map<String, Object>>) report.getBody().get("items")).stream().filter(i -> "NOT_CONFIRMED".equals(i.get("state")))
                .map(i -> String.valueOf(i.get("id"))).findFirst().orElseThrow();
        String credit3 = String.valueOf(ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/settlements/items/" + item + "/bank-credit", Map.of())).get("bankCredit"));
        assertThat(xml("/api/v1/payments/paydirect/notify", PaymentsIT.notification("moaum-it-notify", "an-invented-password", reportedRef, log, "5000.00", false, false)))
                .contains("<Status>0</Status>");
        assertThat(jdbc.sql("SELECT array_to_string(gateway_refs, ',') FROM admissions.iut_fee_reference WHERE reference = :r").param("r", reportedRef)
                .query(String.class).single()).isEqualTo(log + ",QT|WEB|" + log);
        assertThat(ok(it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit3 + "/approve", Map.of()))).containsEntry("outcome", "already confirmed");
        assertThat(jdbc.sql("SELECT state || ':' || coalesce(posted_reference, '-') FROM finance.bank_credit WHERE id = :c").param("c", UUID.fromString(credit3))
                .query(String.class).single()).isEqualTo("POSTED:" + reportedRef);
        assertThat((Map<String, Object>) ok(it.get(w.bursar(), FEES + "/payments?session=" + w.session() + "&q=" + reportedRef)).get("totals"))
                .containsEntry("paid", 1).containsEntry("owedBack", 0);

        // the same, Interswitch's report giving the payment by its payment reference alone (no Log Id): PAYDirect's notice keeps every
        // identifier it gave the payment — the Log Id and the payment reference — so the row is known to be it, and posted as that money
        // (round 6: v5v-2; round 5 kept the Log Id only, and the row was refused as a payment nothing showed it to be)
        Applicant byRef = apply(w);
        String byRefRef = String.valueOf(ok(it.call(byRef.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        String log5 = String.valueOf(ThreadLocalRandom.current().nextLong(1_000_000_000L, 9_999_999_999L));
        ResponseEntity<Map> report5 = it.call(ItSupport.token("audit"), HttpMethod.POST, "/api/v1/finance/settlements", Map.of("label", "IT V766 " + log5, "fileName", "settlement5.csv",
                "rows", List.of(Map.of("settledOn", today().toString(), "paidOn", today().toString(), "reference", byRefRef, "paymentRef", "QT|WEB|" + log5, "amount", "5000",
                        "fee", "0", "channel", "WEB", "payer", "ZZAUDU GRACE"))));
        assertThat(report5.getStatusCode().value()).as(String.valueOf(report5.getBody())).isEqualTo(200);
        String item5 = ((List<Map<String, Object>>) report5.getBody().get("items")).stream().filter(i -> "NOT_CONFIRMED".equals(i.get("state")))
                .map(i -> String.valueOf(i.get("id"))).findFirst().orElseThrow();
        String credit5 = String.valueOf(ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/settlements/items/" + item5 + "/bank-credit", Map.of())).get("bankCredit"));
        assertThat(xml("/api/v1/payments/paydirect/notify", PaymentsIT.notification("moaum-it-notify", "an-invented-password", byRefRef, log5, "5000.00", false, false)))
                .contains("<Status>0</Status>");
        assertThat(ok(it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit5 + "/approve", Map.of()))).containsEntry("outcome", "already confirmed");
        assertThat(jdbc.sql("SELECT state || ':' || coalesce(posted_reference, '-') FROM finance.bank_credit WHERE id = :c").param("c", UUID.fromString(credit5))
                .query(String.class).single()).isEqualTo("POSTED:" + byRefRef);
        assertThat((Map<String, Object>) ok(it.get(w.bursar(), FEES + "/payments?session=" + w.session() + "&q=" + byRefRef)).get("totals"))
                .containsEntry("paid", 1).containsEntry("owedBack", 0);

        // one teller number at two banks, both proposed against one reference (two deposits); the Bursar confirms the reference by hand
        // from First Bank's record, naming First Bank's teller. Neither credit is posted (round 7: a reference confirmed by hand takes no
        // bank credit; round 6 read the note and posted First Bank's, round 5 posted both): each refused with the hand confirmation's
        // check-first words, for the officer to check the bank's record — GTBank's deposit is the money received twice
        Applicant twoBanks = apply(w);
        String tbRef = String.valueOf(ok(it.call(twoBanks.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        String number = "Teller " + ThreadLocalRandom.current().nextInt(100_000_000, 1_000_000_000);
        String fb = String.valueOf(ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits",
                Map.of("receivedOn", today().toString(), "bank", "First Bank", "instrument", number, "amount", 5000, "payer", "ZZAUDU GRACE"))).get("id"));
        String gt = String.valueOf(ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits",
                Map.of("receivedOn", today().toString(), "bank", "GTBank", "instrument", number, "amount", 5000, "payer", "ZZAUDU GRACE"))).get("id"));
        ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + fb + "/propose", Map.of("reference", tbRef, "why", "The teller names the transfer application reference")));
        ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + gt + "/propose", Map.of("reference", tbRef, "why", "The teller names the transfer application reference")));
        assertThat(ok(it.call(w.bursar(), HttpMethod.POST, FEES + "/payments/" + tbRef + "/confirm", Map.of("note", "First Bank " + number + ", from the bank's record"))))
                .containsEntry("settles", true);
        ResponseEntity<Map> second = it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + gt + "/approve", Map.of());
        refused(second, 422, "IUT_FEE_ALREADY_PAID");
        assertThat(String.valueOf(second.getBody().get("detail"))).contains("was confirmed by hand by the Bursar on ")
                .contains("so this bank credit (GTBank · " + number + ") is not posted to it");
        assertThat(String.valueOf(((Map<String, Object>) second.getBody().get("remedy")).get("message")))
                .startsWith("Reject this proposal once the bank's record is checked").contains("owed back only if the record shows it twice");
        ResponseEntity<Map> named = it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + fb + "/approve", Map.of());
        refused(named, 422, "IUT_FEE_ALREADY_PAID");
        assertThat(String.valueOf(named.getBody().get("detail"))).contains("a reference confirmed by hand takes no bank credit, so this bank credit (First Bank · "
                + number + ") is not posted to it");
        assertThat(jdbc.sql("SELECT string_agg(bank || ':' || state, ',' ORDER BY bank) FROM finance.bank_credit WHERE id IN (:a, :b)")
                .param("a", UUID.fromString(fb)).param("b", UUID.fromString(gt)).query(String.class).single()).isEqualTo("First Bank:PROPOSED,GTBank:PROPOSED");
        assertThat((Map<String, Object>) ok(it.get(w.bursar(), FEES + "/payments?session=" + w.session() + "&q=" + tbRef)).get("totals"))
                .containsEntry("paid", 1).containsEntry("owedBack", 0);

        // a teller proposed; PAYDirect still takes the reference, and the applicant pays again on Quickteller (Interswitch's notice of
        // another payment): two payments. The approval is refused, worded by the notice and its Log Id, the officer told to check the
        // bank's record first; the credit stays proposed (round 5: v4v-1 P1b, P2a)
        Applicant twice = apply(w);
        String twiceRef = String.valueOf(ok(it.call(twice.token(), HttpMethod.POST, ME + "/fee-reference", Map.of())).get("reference"));
        String credit4 = String.valueOf(ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits",
                Map.of("receivedOn", today().toString(), "bank", "First Bank", "instrument", "Teller " + ThreadLocalRandom.current().nextInt(100_000_000, 1_000_000_000),
                        "amount", 5000, "payer", "ZZAUDU GRACE"))).get("id"));
        ok(it.call(maker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit4 + "/propose", Map.of("reference", twiceRef, "why", "The teller names the transfer application reference")));
        String log2 = String.valueOf(ThreadLocalRandom.current().nextLong(1_000_000_000L, 9_999_999_999L));
        assertThat(xml("/api/v1/payments/paydirect/notify", PaymentsIT.notification("moaum-it-notify", "an-invented-password", twiceRef, log2, "5000.00", false, false)))
                .contains("<Status>0</Status>");
        ResponseEntity<Map> again = it.call(checker, HttpMethod.POST, "/api/v1/finance/bank-credits/" + credit4 + "/approve", Map.of());
        refused(again, 422, "IUT_FEE_ALREADY_PAID");
        assertThat(String.valueOf(again.getBody().get("detail"))).contains("PAYDirect's notice from Interswitch (Quickteller · WEB, Payment Log Id " + log2 + ")");
        assertThat(String.valueOf(((Map<String, Object>) again.getBody().get("remedy")).get("message")))
                .startsWith("Reject the proposal either way, once the bank's record is checked").contains("If it shows the money twice");
        assertThat(jdbc.sql("SELECT state || ':' || (posted_reference IS NULL) FROM finance.bank_credit WHERE id = :c").param("c", UUID.fromString(credit4))
                .query(String.class).single()).isEqualTo("PROPOSED:true");
    }

    /* ── 7 · the third review: a programme archived while the window is open offers nothing; a window offering none reads closed. The
     *       fourth: the Registry's desk, asked for no session, opens on that window still, and on it once it is closed (round 5: the
     *       latest session with applications on the desks' hands, before a window merely set open) ── */

    @Test
    void aProgrammeArchivedWhileTheWindowIsOpenOffersNothingAndTheWindowReadsClosed() {
        World w = latestWorld();
        open(w, 5000, null);
        // submitted: on the desks' hands
        Applicant a = apply(w);
        pay(w, a);
        uploadAll(a);
        submit(a);
        String other = jdbc.sql("""
                SELECT p.code FROM ref.programme p WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false) AND p.code <> :c
                   AND 200 = ANY (people.programme_levels(p.code)) ORDER BY p.code LIMIT 1
                """).param("c", w.programme()).query(String.class).single();
        ok(it.call(w.academic(), HttpMethod.POST, OFFICE + "/lines", Map.of("session", w.session(), "programme", other, "levels", List.of(200))));
        // the window's own programme closed to new applications while the other takes them
        ok(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/lines", Map.of("session", w.session(), "programme", w.programme(), "level", 200, "accepting", false)));
        try {
            it.db(() -> jdbc.sql("UPDATE ref.programme SET archived = true WHERE code = :c").param("c", other).update());
            // offering nothing: the public link, the website's feed and the door read it closed
            Map<String, Object> pub = ok(it.anon(HttpMethod.GET, PUBLIC + "?session=" + w.session(), null));
            assertThat((Map<String, Object>) pub.get("window")).containsEntry("status", "CLOSED").containsEntry("open", false);
            assertThat((List<?>) pub.get("programmes")).isEmpty();
            assertThat((Map<String, Object>) ok(it.anon(HttpMethod.GET, "/api/v1/public/application-windows", null)).get("interUniversityTransfer"))
                    .containsEntry("open", false);
            refused(it.anon(HttpMethod.POST, APPLY, form(w, jamb(), email(), 200)), 422, "IUT_WINDOW_CLOSED");
            // the desk reads it set open and offering none, the archived programme's line marked; that line closes, and the window is not
            // set open again on it alone
            Map<String, Object> window = ok(it.get(w.academic(), OFFICE + "/window?session=" + w.session()));
            assertThat(window).containsEntry("state", "OPEN").containsEntry("status", "CLOSED").containsEntry("offered", 0);
            assertThat((List<Map<String, Object>>) window.get("lines")).filteredOn(l -> other.equals(l.get("programme")))
                    .extracting(l -> l.get("accepting") + ":" + l.get("programmeInUse") + ":" + l.get("offered")).containsExactly("true:false:false");
            refused(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "OPEN")), 422, "IUT_WINDOW_NO_PROGRAMMES");
            // asked for no session, the desk opens on this window (set open, offering nothing: the alert's case), the latest with an
            // application on the desks' hands, never the University's current session, and lists its application (round 4:
            // api-screens4-2; round 5: v4v-2)
            assertThat(ok(it.get(w.academic(), OFFICE + "/window"))).containsEntry("session", w.session()).containsEntry("state", "OPEN").containsEntry("offered", 0);
            assertThat((List<Map<String, Object>>) ok(it.get(w.academic(), OFFICE + "/applications?session=" + w.session())).get("rows"))
                    .extracting(r -> r.get("id")).containsExactly(a.app().toString());
            ok(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/lines", Map.of("session", w.session(), "programme", other, "level", 200, "accepting", false)));
        } finally {
            it.db(() -> jdbc.sql("UPDATE ref.programme SET archived = false WHERE code = :c").param("c", other).update());
        }
        // the window's own programme taking applications again: open again
        ok(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/lines", Map.of("session", w.session(), "programme", w.programme(), "level", 200, "accepting", true)));
        assertThat((Map<String, Object>) ok(it.anon(HttpMethod.GET, PUBLIC + "?session=" + w.session(), null)).get("window")).containsEntry("status", "OPEN");
        // closed: the desk's work on it goes on (D5), and the desk still opens on it when no session is asked
        ok(it.call(w.academic(), HttpMethod.PUT, OFFICE + "/window", windowBody(w, "CLOSED")));
        assertThat(ok(it.get(w.academic(), OFFICE + "/window"))).containsEntry("session", w.session()).containsEntry("state", "CLOSED");
        assertThat(((Map<String, Object>) ok(it.get(w.academic(), OFFICE + "/window")).get("counts"))).containsEntry("SUBMITTED", 1);
    }
}
