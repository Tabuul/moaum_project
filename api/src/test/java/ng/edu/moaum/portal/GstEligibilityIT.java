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
 * V366: the GST fee is owed for a GST/EPS course the student must take — the programme's offering at their level, a carryover —
 * never because they are a student or of a level. At the API: a 300-level student of a programme without a GST or EPS course sees
 * nothing owed, cannot open a GST reference, and registers an ordinary course under the whole-registration rule; a 300-level
 * student carrying GST over owes it and is told why; a 300-level student of the programme that offers the EPS course owes the one
 * GST payment for it; the GST office counts the first as not applicable, never unpaid, and reads why for any student; the support
 * desk reads the same answer; a student reads only their own. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class GstEligibilityIT {

    static final String SESSION = "2116/2117";
    static final String EARLIER = "2115/2116";
    static final String PROG_A = "C00023";
    static final String PROG_B = "C00061";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String bursar = ItSupport.token("bursar");
    String gst = ItSupport.token("gst");
    String head = ItSupport.token("helpdeskhead");
    int n;
    String gstCode;
    String epsCode;
    String plainCode;
    UUID gstOffering;
    UUID epsOffering;
    UUID plainOffering;
    UUID a100;
    UUID b300;
    UUID b300carry;
    UUID a300;

    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(EARLIER, 2115);
        it.session(SESSION, 2116);
        n = new Random().nextInt(9000) + 1000;
        gstCode = "GST " + (500 + n % 199);
        epsCode = "EPS " + (500 + n % 199);
        plainCode = "ZZE " + (300 + n % 199);
        a100 = it.student("ZZELA" + n, PROG_A, "MOAUM/ADM/16/" + String.format("%06d", n), "MOAUM/ELA/16/" + n, 100);
        b300 = it.student("ZZELB" + n, PROG_B, "MOAUM/ADM/16/" + String.format("%06d", n + 1), "MOAUM/ELB/16/" + n, 300);
        b300carry = it.student("ZZELC" + n, PROG_B, "MOAUM/ADM/16/" + String.format("%06d", n + 2), "MOAUM/ELC/16/" + n, 300);
        a300 = it.student("ZZELD" + n, PROG_A, "MOAUM/ADM/16/" + String.format("%06d", n + 3), "MOAUM/ELD/16/" + n, 300);
        it.db(() -> {
            jdbc.sql("UPDATE finance.gst_fee SET superseded_at = now() WHERE session = :ses AND superseded_at IS NULL").param("ses", SESSION).update();
            jdbc.sql("UPDATE finance.gst_setting SET required_for_gst_eps = true, required_for_all = false, covers_eps = true WHERE id = 1").update();
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", PROG_B).query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, :t, 2, 1, 100, :d, 'GST', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", gstCode).param("t", "Use of English " + n).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, :t, 2, 1, 300, :d, 'GST', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", epsCode).param("t", "Venture Creation " + n).param("d", dept).update();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, :t, 3, 1, 300, :d, 'Core', 'LIVE') ON CONFLICT (code) DO NOTHING")
                    .param("c", plainCode).param("t", "Departmental Course " + n).param("d", dept).update();
            // GST at 100 for both programmes; the EPS course at 300 for programme A alone; an ordinary course at 300 for B
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :a, 100, 'GST'), (:c, :b, 100, 'GST') ON CONFLICT DO NOTHING")
                    .param("c", gstCode).param("a", PROG_A).param("b", PROG_B).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :a, 300, 'GST') ON CONFLICT DO NOTHING")
                    .param("c", epsCode).param("a", PROG_A).update();
            jdbc.sql("INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (:c, :b, 300, 'Core') ON CONFLICT DO NOTHING")
                    .param("c", plainCode).param("b", PROG_B).update();
            for (String code : List.of(gstCode, epsCode, plainCode)) {
                jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), :c, :s, 1) ON CONFLICT (course_code, session, semester) DO NOTHING")
                        .param("c", code).param("s", SESSION).update();
            }
            // last session: the 300-level student of B failed the GST course, published
            UUID earlier = UUID.randomUUID();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:id, :c, :s, 1) ON CONFLICT (course_code, session, semester) DO NOTHING")
                    .param("id", earlier).param("c", gstCode).param("s", EARLIER).update();
            earlier = jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = 1").param("c", gstCode).param("s", EARLIER).query(UUID.class).single();
            UUID reg = UUID.randomUUID();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (:id, :st, :s, 1, 200, 'APPROVED', now()) ON CONFLICT DO NOTHING")
                    .param("id", reg).param("st", b300carry).param("s", EARLIER).update();
            reg = jdbc.sql("SELECT id FROM registration.course_registration WHERE student_id = :st AND session = :s AND semester = 1").param("st", b300carry).param("s", EARLIER).query(UUID.class).single();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 2, 'APPROVED') ON CONFLICT DO NOTHING")
                    .param("r", reg).param("o", earlier).update();
            UUID sheet = jdbc.sql("SELECT id FROM assessment.score_sheet WHERE offering_id = :o").param("o", earlier).query(UUID.class).optional().orElse(null);
            if (sheet == null) {
                sheet = UUID.randomUUID();
                jdbc.sql("INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at, submitted_at) VALUES (:id, :o, 'PUBLISHED', 'SEN/2116/01', now(), now())")
                        .param("id", sheet).param("o", earlier).update();
            }
            jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) SELECT :sh, :st, 10, 15, 'GRADED' WHERE NOT EXISTS (SELECT 1 FROM assessment.score WHERE sheet_id = :sh AND student_id = :st)")
                    .param("sh", sheet).param("st", b300carry).update();
            return null;
        });
        gstOffering = offering(gstCode);
        epsOffering = offering(epsCode);
        plainOffering = offering(plainCode);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/gst/fee", Map.of("session", SESSION, "amount", 7000)).getStatusCode().value()).isEqualTo(200);
    }

    private UUID offering(String code) {
        return jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = 1").param("c", code).param("s", SESSION).query(UUID.class).single();
    }

    private Map<String, Object> myGst(String token) {
        ResponseEntity<Map> r = it.get(token, "/api/v1/me/gst?session=" + SESSION);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @Test
    void aStudentNoGstOrEpsCourseConcernsOwesNothingAndIsHeldByNothing() {
        String student = TestTokens.token(b300, List.of("student"));
        Map<String, Object> view = myGst(student);
        assertThat(m(view.get("entitlement")).get("state")).isEqualTo("NOT_REQUIRED");
        assertThat(m(view.get("entitlement")).get("required")).isEqualTo(false);
        assertThat(m(view.get("eligibility")).get("gst_reason")).isEqualTo("GST_NOT_APPLICABLE");
        assertThat(m(view.get("eligibility")).get("eps_reason")).isEqualTo("EPS_NOT_APPLICABLE");
        assertThat(l(view.get("courses"))).noneSatisfy(c -> assertThat(c.get("counts")).isEqualTo(true));
        // the backend refuses to open a GST fee for them, whatever the page shows
        ResponseEntity<Map> ref = it.call(student, HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", SESSION));
        assertThat(ref.getStatusCode().value()).isEqualTo(422);
        assertThat(ref.getBody().get("code")).isEqualTo("GST_NOT_REQUIRED");
        // the whole-registration rule holds only a student who owes the fee: this one registers an ordinary course
        it.db(() -> jdbc.sql("UPDATE finance.gst_setting SET required_for_all = true WHERE id = 1").update());
        try {
            ResponseEntity<Map> reg = it.call(student, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", SESSION, "semester", 1, "offerings", List.of(plainOffering)));
            assertThat(reg.getStatusCode().value()).as(String.valueOf(reg.getBody())).isEqualTo(200);
            // the 100-level student who owes it is held at the GST course
            ResponseEntity<Map> held = it.call(TestTokens.token(a100, List.of("student")), HttpMethod.PUT, "/api/v1/me/registration",
                    Map.of("session", SESSION, "semester", 1, "offerings", List.of(gstOffering)));
            assertThat(held.getBody().get("code")).isEqualTo("GST_PAYMENT_REQUIRED");
        } finally {
            it.db(() -> jdbc.sql("UPDATE finance.gst_setting SET required_for_all = false WHERE id = 1").update());
        }
        // the registration form offers the 300-level B student no GST or EPS course at all
        Map<String, Object> form = it.get(student, "/api/v1/me/registration?session=" + SESSION + "&semester=1").getBody();
        assertThat(l(form.get("menu"))).noneSatisfy(x -> assertThat(x.get("kind")).isEqualTo("GST"));
    }

    @Test
    void aCarryoverAtThreeHundredOwesTheFeeAndSaysWhy() {
        String student = TestTokens.token(b300carry, List.of("student"));
        Map<String, Object> view = myGst(student);
        assertThat(m(view.get("entitlement")).get("state")).isEqualTo("NOT_PAID");
        assertThat(m(view.get("eligibility")).get("gst_reason")).isEqualTo("GST_REQUIRED_CARRYOVER");
        assertThat(l(view.get("courses"))).anySatisfy(c -> {
            assertThat(c.get("code")).isEqualTo(gstCode);
            assertThat(c.get("source")).isEqualTo("CARRYOVER");
            assertThat(c.get("counts")).isEqualTo(true);
            assertThat(c.get("last_grade")).isEqualTo("F");
        });
        // the form carries it as a carryover, held until the fee is paid; the reference opens
        Map<String, Object> form = it.get(student, "/api/v1/me/registration?session=" + SESSION + "&semester=1").getBody();
        assertThat(l(form.get("menu"))).anySatisfy(x -> { assertThat(x.get("course_code")).isEqualTo(gstCode); assertThat(x.get("carryover")).isEqualTo(true); });
        ResponseEntity<Map> ref = it.call(student, HttpMethod.POST, "/api/v1/me/gst/reference", Map.of("session", SESSION));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        String reference = String.valueOf(ref.getBody().get("reference"));

        // the GST reference goes to the gateway like any student reference: named the GST fee there, and the payer returned to the GST page
        String ict = ItSupport.token("ict");
        org.springframework.web.client.RestClient open = org.springframework.web.client.RestClient.builder().baseUrl("http://localhost:" + port)
                .defaultStatusHandler(s -> true, (q, r) -> { }).build();
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/payments/gateways/quickteller/key", Map.of("secret", "{\"merchantCode\":\"MX000366\",\"payItemId\":\"101\",\"sandbox\":true}"))
                .getStatusCode().value()).isEqualTo(200);
        try {
            ResponseEntity<Map> checkout = it.call(student, HttpMethod.POST, "/api/v1/payments/checkout", Map.of("reference", reference, "gateway", "quickteller"));
            assertThat(checkout.getStatusCode().value()).as(String.valueOf(checkout.getBody())).isEqualTo(200);
            assertThat(String.valueOf(checkout.getBody().get("url"))).contains("/api/v1/payments/quickteller/start?reference=" + reference);
            String page = open.get().uri("/api/v1/payments/quickteller/start?reference=" + reference).retrieve().body(String.class);
            assertThat(page).contains("name=\"merchant_code\" value=\"MX000366\"").contains("name=\"pay_item_name\" value=\"MOAUM GST fee\"")
                    .contains("name=\"amount\" value=\"700000\"").contains("/api/v1/payments/quickteller/return?reference=" + reference);
            String returned = open.post().uri("/api/v1/payments/quickteller/return?reference=" + reference)
                    .contentType(org.springframework.http.MediaType.APPLICATION_FORM_URLENCODED).body("txnref=" + reference + "&resp=Z6&desc=Cancelled")
                    .retrieve().body(String.class);
            assertThat(returned).contains("/student/gst?paid=" + reference);
        } finally {
            it.call(ict, HttpMethod.POST, "/api/v1/payments/gateways/quickteller/clear-key", Map.of());
        }

        // the GST office reads why; the support desk reads the same answer
        Map<String, Object> drill = it.get(gst, "/api/v1/gst/GST/students/" + b300carry + "?session=" + SESSION).getBody();
        assertThat(m(m(drill.get("explain")).get("eligibility")).get("gst_reason")).isEqualTo("GST_REQUIRED_CARRYOVER");
        ResponseEntity<Map> desk = it.get(head, "/api/v1/helpdesk/support/students/" + b300carry + "/payments?session=" + SESSION);
        assertThat(desk.getStatusCode().value()).as(String.valueOf(desk.getBody())).isEqualTo(200);
        assertThat(m(m(desk.getBody().get("gstEps")).get("eligibility")).get("gst_carryovers")).isEqualTo(List.of(gstCode));
    }

    @Test
    void theEpsCourseOfferedToOneProgrammeAtThreeHundredIsOwedThereAlone() {
        Map<String, Object> a = myGst(TestTokens.token(a300, List.of("student")));
        assertThat(m(a.get("eligibility")).get("eps_reason")).isEqualTo("EPS_REQUIRED_COURSE_OFFERING");
        assertThat(m(a.get("eligibility")).get("gst_required")).isEqualTo(false);
        assertThat(m(a.get("entitlement")).get("required")).isEqualTo(true);
        assertThat(m(a.get("entitlement")).get("state")).isEqualTo("NOT_PAID");
        ResponseEntity<Map> held = it.call(TestTokens.token(a300, List.of("student")), HttpMethod.PUT, "/api/v1/me/registration",
                Map.of("session", SESSION, "semester", 1, "offerings", List.of(epsOffering)));
        assertThat(held.getBody().get("code")).isEqualTo("GST_PAYMENT_REQUIRED");
        Map<String, Object> b = myGst(TestTokens.token(b300, List.of("student")));
        assertThat(m(b.get("eligibility")).get("eps_required")).isEqualTo(false);
    }

    @Test
    void theOfficeCountsNotApplicableNeverUnpaidAndAStudentReadsOnlyTheirOwn() {
        Map<String, Object> dash = it.get(gst, "/api/v1/gst/GST/dashboard?session=" + SESSION + "&prog=" + PROG_B + "&level=300").getBody();
        Map<String, Object> totals = m(dash.get("totals"));
        assertThat(((Number) totals.get("not_applicable")).longValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) totals.get("carryover")).longValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) totals.get("population")).longValue())
                .isEqualTo(((Number) totals.get("total")).longValue() + ((Number) totals.get("not_applicable")).longValue());
        String surname = "ZZELB" + n;
        assertThat(l(it.get(gst, "/api/v1/gst/GST/students?session=" + SESSION + "&q=" + surname + "&eligibility=NOT_APPLICABLE").getBody().get("rows")))
                .anySatisfy(r -> assertThat(r.get("student_id")).isEqualTo(b300.toString()));
        assertThat(l(it.get(gst, "/api/v1/gst/GST/students?session=" + SESSION + "&q=" + surname).getBody().get("rows"))).isEmpty();
        assertThat(l(it.get(gst, "/api/v1/gst/GST/students?session=" + SESSION + "&q=" + surname + "&payment=NOT_PAID").getBody().get("rows"))).isEmpty();
        assertThat(l(it.get(gst, "/api/v1/gst/GST/students?session=" + SESSION + "&q=ZZELC" + n + "&eligibility=CARRYOVER").getBody().get("rows")))
                .anySatisfy(r -> assertThat(r.get("office_reason")).isEqualTo("GST_REQUIRED_CARRYOVER"));
        // the Bursary's standing separates the applicable from the not applicable
        Map<String, Object> standing = m(it.get(bursar, "/api/v1/gst/fee?session=" + SESSION).getBody().get("standing"));
        assertThat(((Number) standing.get("not_applicable")).longValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) standing.get("applicable")).longValue()).isGreaterThanOrEqualTo(3);
        // a student reads their own answer through /me alone; the office's door is not theirs
        String student = TestTokens.token(b300, List.of("student"));
        assertThat(it.get(student, "/api/v1/gst/GST/students/" + b300carry + "?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(student, "/api/v1/gst/fee/review?session=" + SESSION).getStatusCode().value()).isEqualTo(403);
    }
}
