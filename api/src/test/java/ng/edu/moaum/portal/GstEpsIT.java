package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
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
 * GST & EPS (V314): the Bursar alone states the GST fee; an unpaid student is refused a GST course and an EPS course at the
 * API and in the database, and not another course; the reference is paid on the one ledger and, confirmed, lifts the gate
 * for both, with the student told; the GST office's dashboard counts them and the EPS office reads its own desk and not
 * the other's; each office manages its own courses and reaches only its own score sheets. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class GstEpsIT {

    static final String SESSION = "2110/2111";
    static final String PROGRAMME = "C00023";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String bursar = ItSupport.token("bursar");
    String gst = ItSupport.token("gst");
    String eps = ItSupport.token("eps");
    String registrar = ItSupport.token("registrar");
    UUID s;
    String student;
    String gstCode;
    String entCode;
    UUID gstOffering;
    UUID entOffering;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2110);
        int n = new Random().nextInt(9000) + 1000;
        s = it.student("ZZGST" + n, PROGRAMME, "MOAUM/ADM/10/" + String.format("%06d", n), "MOAUM/GST/10/" + n, 100);
        student = TestTokens.token(s, List.of("student"));
        gstCode = "GST " + (700 + n % 299);
        entCode = "ENT " + (700 + n % 299);
        gstOffering = UUID.randomUUID();
        entOffering = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :ses WHERE id = :id").param("ses", SESSION).param("id", s).update();
            jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08055550314', :e, now()) ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email")
                    .param("s", s).param("e", "zzgst" + n + "@example.com").update();
            // the fee of an earlier run withdrawn, so the session starts with none stated
            jdbc.sql("UPDATE finance.gst_fee SET superseded_at = now() WHERE session = :ses AND superseded_at IS NULL").param("ses", SESSION).update();
            jdbc.sql("UPDATE finance.gst_setting SET required_for_gst_eps = true, required_for_all = false, covers_eps = true WHERE id = 1").update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROGRAMME).query(String.class).single();
            for (String code : List.of(gstCode, entCode)) {
                jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, :t, 2, 1, 100, :d, 'GST', 'LIVE') ON CONFLICT (code) DO NOTHING")
                        .param("c", code).param("t", code.startsWith("ENT") ? "Venture Creation " + n : "General Studies " + n).param("d", dept).update();
                jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :p, 100, 'GST') ON CONFLICT DO NOTHING").param("c", code).param("p", PROGRAMME).update();
            }
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:id, :c, :s, 1) ON CONFLICT (course_code, session, semester, stream) DO NOTHING")
                    .param("id", gstOffering).param("c", gstCode).param("s", SESSION).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:id, :c, :s, 1) ON CONFLICT (course_code, session, semester, stream) DO NOTHING")
                    .param("id", entOffering).param("c", entCode).param("s", SESSION).update();
            return null;
        });
        gstOffering = jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = 1").param("c", gstCode).param("s", SESSION).query(UUID.class).single();
        entOffering = jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = 1").param("c", entCode).param("s", SESSION).query(UUID.class).single();
    }

    private ResponseEntity<Map> register(UUID... offerings) {
        return it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(offerings)));
    }

    private Map<String, Object> myGst() {
        ResponseEntity<Map> r = it.get(student, "/api/v1/me/gst?session=" + SESSION);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @Test
    void theBursarStatesTheFeeAndTheOfficesDoNot() {
        Map<String, Object> fee = Map.of("session", SESSION, "amount", 10000);
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/gst/fee", fee).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(eps, HttpMethod.PUT, "/api/v1/gst/fee", fee).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/gst/setting", Map.of("requiredForAll", true)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> stated = it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", fee);
        assertThat(stated.getStatusCode().value()).as(String.valueOf(stated.getBody())).isEqualTo(200);
        assertThat(l(stated.getBody().get("rules"))).anySatisfy(r -> assertThat(new BigDecimal(String.valueOf(r.get("amount")))).isEqualByComparingTo("10000"));
        // the offices read it; a new statement supersedes the old and keeps it in the history
        assertThat(it.get(gst, "/api/v1/gst/fee?session=" + SESSION).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> again = it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", SESSION, "amount", 12000));
        assertThat(l(again.getBody().get("rules"))).hasSize(1);
        assertThat(l(again.getBody().get("history"))).anySatisfy(r -> assertThat(new BigDecimal(String.valueOf(r.get("amount")))).isEqualByComparingTo("10000"));
        assertThat(it.anon(HttpMethod.GET, "/api/v1/gst/GST/dashboard?session=" + SESSION, null).getStatusCode().value()).isEqualTo(401);
    }

    @Test
    void anUnpaidStudentIsHeldAtGstAndEpsAndFreedByTheOneConfirmedPayment() {
        // nothing stated: nothing to pay, the GST course registers
        assertThat(m(myGst().get("entitlement")).get("state")).isEqualTo("NOT_STATED");
        ResponseEntity<Map> free = register(gstOffering);
        assertThat(free.getStatusCode().value()).as(String.valueOf(free.getBody())).isEqualTo(200);
        assertThat(register().getStatusCode().value()).isEqualTo(200);

        // the Bursar states the fee: the GST and the EPS course are refused, with the business code; the menu says so
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", SESSION, "amount", 10000)).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> ent = m(myGst().get("entitlement"));
        assertThat(ent.get("state")).isEqualTo("NOT_PAID");
        assertThat(ent.get("required")).isEqualTo(true);
        assertThat(new BigDecimal(String.valueOf(ent.get("fee")))).isEqualByComparingTo("10000");
        ResponseEntity<Map> held = register(gstOffering);
        assertThat(held.getStatusCode().value()).isEqualTo(422);
        assertThat(held.getBody().get("code")).isEqualTo("GST_PAYMENT_REQUIRED");
        assertThat(String.valueOf(held.getBody().get("detail"))).contains("GST payment covers both GST and EPS");
        assertThat(register(entOffering).getBody().get("code")).isEqualTo("GST_PAYMENT_REQUIRED");
        Map<String, Object> view = it.get(student, "/api/v1/me/registration?session=" + SESSION + "&semester=1").getBody();
        assertThat(l(view.get("menu")).stream().filter(x -> gstCode.equals(x.get("course_code"))).findFirst().orElseThrow().get("gstLocked")).isEqualTo(true);
        assertThat(m(view.get("gst")).get("state")).isEqualTo("NOT_PAID");
        // straight against the database, the registration function refuses too
        String direct = it.db(() -> {
            try {
                UUID reg = jdbc.sql("SELECT registration.student_draft(:s, :ses, 1)").param("s", s).param("ses", SESSION).query(UUID.class).single();
                jdbc.sql("SELECT registration.student_choose(:r, :o)").param("r", reg).param("o", new UUID[]{gstOffering}).query().listOfRows();
                return "allowed";
            } catch (RuntimeException e) {
                return e.getMessage();
            }
        });
        assertThat(direct).contains("GST_PAYMENT_REQUIRED");

        // the reference: the stated fee, once; opened twice it is the same reference
        ResponseEntity<Map> ref = it.call(student, HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", SESSION));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        String reference = String.valueOf(ref.getBody().get("reference"));
        assertThat(reference).startsWith("MOAUM-FEE-");
        assertThat(String.valueOf(it.call(student, HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", SESSION)).getBody().get("reference"))).isEqualTo(reference);
        assertThat(m(myGst().get("entitlement")).get("state")).isEqualTo("PENDING");
        assertThat(register(gstOffering).getBody().get("code")).isEqualTo("GST_PAYMENT_REQUIRED");

        // confirmed on the ledger, as the gateway or the Bursary confirms every payment: entitled, both courses register, the student is told
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", reference).query(String.class).single());
        Map<String, Object> paid = m(myGst().get("entitlement"));
        assertThat(paid.get("state")).isEqualTo("PAID");
        assertThat(paid.get("entitled")).isEqualTo(true);
        assertThat(paid.get("covers_eps")).isEqualTo(true);
        assertThat(paid.get("receipt_no")).isNotNull();
        ResponseEntity<Map> both = register(gstOffering, entOffering);
        assertThat(both.getStatusCode().value()).as(String.valueOf(both.getBody())).isEqualTo(200);
        assertThat(l(m(both.getBody().get("registration")).get("entries"))).hasSize(2);
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", SESSION)).getBody().get("code")).isEqualTo("GST_ALREADY_PAID");
        long told = jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject ILIKE 'GST fee%'").param("s", s).query(Long.class).single();
        assertThat(told).isGreaterThanOrEqualTo(1);

        // the GST office counts it; the EPS office reads its own desk and not the other's; the Bursar and the Registrar read both
        Map<String, Object> dash = it.get(gst, "/api/v1/gst/GST/dashboard?session=" + SESSION + "&prog=" + PROGRAMME).getBody();
        assertThat(((Number) m(dash.get("totals")).get("paid")).longValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) m(dash.get("totals")).get("registered")).longValue()).isGreaterThanOrEqualTo(1);
        assertThat(l(dash.get("courses"))).anySatisfy(c -> { assertThat(c.get("course_code")).isEqualTo(gstCode); assertThat(((Number) c.get("registered")).longValue()).isEqualTo(1); });
        assertThat(l(dash.get("courses"))).noneSatisfy(c -> assertThat(c.get("course_code")).isEqualTo(entCode));
        assertThat(it.get(gst, "/api/v1/gst/EPS/dashboard?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> epsDash = it.get(eps, "/api/v1/gst/EPS/dashboard?session=" + SESSION + "&prog=" + PROGRAMME).getBody();
        assertThat(((Number) m(epsDash.get("totals")).get("registered")).longValue()).isGreaterThanOrEqualTo(1);
        assertThat(l(epsDash.get("courses"))).anySatisfy(c -> assertThat(c.get("course_code")).isEqualTo(entCode));
        assertThat(it.get(bursar, "/api/v1/gst/EPS/dashboard?session=" + SESSION).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(registrar, "/api/v1/gst/GST/dashboard?session=" + SESSION).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> list = it.get(gst, "/api/v1/gst/GST/students?session=" + SESSION + "&q=ZZGST&payment=PAID&registration=REGISTERED").getBody();
        assertThat(l(list.get("rows"))).anySatisfy(r -> { assertThat(r.get("student_id")).isEqualTo(s.toString()); assertThat(r.get("pay_state")).isEqualTo("PAID"); assertThat(String.valueOf(r.get("registered_courses"))).contains(gstCode); });
        assertThat(it.get(gst, "/api/v1/gst/GST/students/" + s + "?session=" + SESSION).getStatusCode().value()).isEqualTo(200);
    }

    @Test
    void eachOfficeManagesItsOwnCoursesAndReachesOnlyItsOwnSheets() {
        // courses: the GST office edits a GST course, not an EPS one; the EPS office the reverse
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/gst/GST/courses/" + entCode.replace(" ", "_"), Map.of("title", "Not mine", "units", 2, "level", 100, "semester", 1)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(eps, HttpMethod.PUT, "/api/v1/gst/GST/courses/" + gstCode.replace(" ", "_"), Map.of("title", "Not mine", "units", 2, "level", 100, "semester", 1)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> edited = it.call(gst, HttpMethod.PUT, "/api/v1/gst/GST/courses/" + gstCode.replace(" ", "_"), Map.of("title", "General Studies, renamed", "units", 2, "level", 100, "semester", 1));
        assertThat(edited.getStatusCode().value()).as(String.valueOf(edited.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT title FROM catalogue.course WHERE code = :c").param("c", gstCode).query(String.class).single()).isEqualTo("General Studies, renamed");
        assertThat(it.call(eps, HttpMethod.PUT, "/api/v1/gst/EPS/courses/" + entCode.replace(" ", "_") + "/offers", Map.of("programmes", List.of(PROGRAMME), "level", 100)).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> courses = it.get(eps, "/api/v1/gst/EPS/courses?session=" + SESSION).getBody();
        assertThat(l(courses.get("catalogue"))).anySatisfy(c -> assertThat(c.get("code")).isEqualTo(entCode));
        assertThat(l(courses.get("catalogue"))).noneSatisfy(c -> assertThat(c.get("code")).isEqualTo(gstCode));

        // sheets: a registered, approved candidate; each office sees and enters its own course's sheet alone
        UUID gstSheet = UUID.randomUUID();
        UUID entSheet = UUID.randomUUID();
        it.db(() -> {
            UUID reg = jdbc.sql("SELECT registration.student_draft(:s, :ses, 1)").param("s", s).param("ses", SESSION).query(UUID.class).single();
            jdbc.sql("SELECT registration.student_choose(:r, :o)").param("r", reg).param("o", new UUID[]{gstOffering, entOffering}).query().listOfRows();
            jdbc.sql("UPDATE registration.course_registration SET status = 'APPROVED', submitted_at = now(), approved_at = now() WHERE id = :r").param("r", reg).update();
            jdbc.sql("UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = :r").param("r", reg).update();
            jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id) SELECT :id, :o WHERE NOT EXISTS (SELECT 1 FROM assessment.score_sheet WHERE offering_id = :o)").param("id", gstSheet).param("o", gstOffering).update();
            jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id) SELECT :id, :o WHERE NOT EXISTS (SELECT 1 FROM assessment.score_sheet WHERE offering_id = :o)").param("id", entSheet).param("o", entOffering).update();
            return null;
        });
        UUID gstSheetId = jdbc.sql("SELECT id FROM assessment.score_sheet WHERE offering_id = :o ORDER BY stage LIMIT 1").param("o", gstOffering).query(UUID.class).single();
        UUID entSheetId = jdbc.sql("SELECT id FROM assessment.score_sheet WHERE offering_id = :o ORDER BY stage LIMIT 1").param("o", entOffering).query(UUID.class).single();
        List<Map<String, Object>> gstSheets = l(it.get(gst, "/api/v1/results/sheets?session=" + SESSION).getBody().get("sheets"));
        assertThat(gstSheets).anySatisfy(x -> assertThat(x.get("courseCode")).isEqualTo(gstCode));
        assertThat(gstSheets).noneSatisfy(x -> assertThat(x.get("courseCode")).isEqualTo(entCode));
        List<Map<String, Object>> epsSheets = l(it.get(eps, "/api/v1/results/sheets?session=" + SESSION).getBody().get("sheets"));
        assertThat(epsSheets).anySatisfy(x -> assertThat(x.get("courseCode")).isEqualTo(entCode));
        assertThat(epsSheets).noneSatisfy(x -> assertThat(x.get("courseCode")).isEqualTo(gstCode));
        Map<String, Object> scores = Map.of("scores", List.of(Map.of("studentId", s.toString(), "ca", 30, "exam", 50)));
        assertThat(it.call(eps, HttpMethod.PUT, "/api/v1/results/sheets/" + gstSheetId + "/scores", scores).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(gst, HttpMethod.PUT, "/api/v1/results/sheets/" + entSheetId + "/scores", scores).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> entered = it.call(gst, HttpMethod.PUT, "/api/v1/results/sheets/" + gstSheetId + "/scores", scores);
        assertThat(entered.getStatusCode().value()).as(String.valueOf(entered.getBody())).isEqualTo(200);
        assertThat(((Number) entered.getBody().get("written")).intValue()).isEqualTo(1);
        ResponseEntity<Map> epsEntered = it.call(eps, HttpMethod.PUT, "/api/v1/results/sheets/" + entSheetId + "/scores", scores);
        assertThat(epsEntered.getStatusCode().value()).as(String.valueOf(epsEntered.getBody())).isEqualTo(200);
    }
}
