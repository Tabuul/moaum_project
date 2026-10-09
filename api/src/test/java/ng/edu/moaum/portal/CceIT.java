package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HexFormat;
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
 * CCE — the Centre for Continuing Education (V379), through the API: the Academic Office sets the CCE session and offers a
 * programme, loads JAMB's CCE list in a preview and commits it; only a listed JAMB number with its date of birth registers, while
 * the window is open; the applicant completes the form (biodata, two O'Level sittings, the documents), pays the CCE fee and
 * submits; the Centre reviews, verifies the documents and recommends; the same officer cannot approve; the Academic Office
 * approves and publishes (the Centre cannot publish, a lecturer reads nothing); the applicant reads the outcome without a checking
 * fee, accepts, pays the CCE acceptance fee and comes onto the register CCE and part-time in the CCE session, which the student
 * portal shows with the Centre and the expected completion. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CceIT {

    static final String SESSION = "2113/2114";
    static final String PROGRAMME = "C00023";
    static final String PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";
    static final String PDF = java.util.Base64.getEncoder().encodeToString("%PDF-1.4\n% a result slip\n%%EOF\n".getBytes());

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String centre = ItSupport.token("cce");
    final String bursar = ItSupport.token("bursar");
    final String lecturer = ItSupport.token("lecturer");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2113);
    }

    @AfterEach
    void tearDown() {
        // the CCE session follows undergraduate again, as it does by default
        it.call(academic, HttpMethod.PUT, "/api/v1/cce/session-mapping", Map.of("offset", -1, "reason", "integration test: back to one session behind"));
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    @Test
    void aListedCandidateAppliesIsReviewedAdmittedAndComesOntoTheRegisterPartTimeInTheCceSession() {
        String n = String.valueOf(Math.abs(UUID.randomUUID().getMostSignificantBits() % 1_000_000_000L));
        String jamb = "2113" + "0".repeat(9 - n.length()) + n + "CC";
        String email = "cce" + n + "@example.com";
        // a name of its own each run: the list flags the same name and date of birth under another number
        String tag = n.chars().mapToObj(c -> String.valueOf((char) ('a' + (c - '0')))).collect(java.util.stream.Collectors.joining());

        // (1) the Academic Office: the CCE session named, the programme offered; the Centre cannot set either
        assertThat(it.call(centre, HttpMethod.PUT, "/api/v1/cce/session-mapping", Map.of("offset", -1, "override", SESSION, "reason", "no")).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> mapping = ok(it.call(academic, HttpMethod.PUT, "/api/v1/cce/session-mapping",
                Map.of("offset", -1, "override", SESSION, "reason", "integration test: the CCE list for " + SESSION)));
        assertThat(((Map) mapping.get("mapping")).get("route_session")).isEqualTo(SESSION);
        ok(it.call(academic, HttpMethod.PUT, "/api/v1/cce/programmes/" + PROGRAMME, Map.of("active", true)));
        ok(it.call(bursar, HttpMethod.PUT, "/api/v1/cce/fees", Map.of("session", SESSION, "applicationFee", 6000, "portalCharge", 500, "acceptanceFee", 25000)));
        assertThat(it.get(lecturer, "/api/v1/cce/overview").getStatusCode().value()).isEqualTo(403);

        // (2) the list: previewed (one row new, one without a date of birth), committed; the Centre does not load lists
        List<Map<String, String>> rows = List.of(
                Map.of("jamb_reg_no", jamb, "surname", "Iorliam" + tag, "first_name", "Doosuur", "date_of_birth", "1988-02-14", "sex", "F",
                       "phone", "08061234567", "programme_code", PROGRAMME, "study_mode", "PART TIME", "admission_route", "CCE"),
                Map.of("jamb_reg_no", jamb.replace("CC", "CD"), "surname", "Agbo", "first_name", "Ene", "programme_code", PROGRAMME));
        Map<String, Object> body = Map.of("session", SESSION, "filename", "cce-" + n + ".xlsx", "sha256", HexFormat.of().formatHex(sha().digest(n.getBytes())), "rows", rows);
        assertThat(it.call(centre, HttpMethod.POST, "/api/v1/cce/batches", body).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> batch = ok(it.call(academic, HttpMethod.POST, "/api/v1/cce/batches", body));
        assertThat(((Map) batch.get("counts")).get("NEW")).isEqualTo(1);
        assertThat(((Map) batch.get("counts")).get("INVALID")).isEqualTo(1);
        Map<String, Object> committed = ok(it.call(academic, HttpMethod.POST, "/api/v1/cce/batches/" + batch.get("id") + "/commit", null));
        assertThat(committed.get("state")).isEqualTo("COMMITTED");
        assertThat(((Map) committed.get("applied")).get("added")).isEqualTo(1);

        // (3) the applicant: the number with another date of birth is not listed; registration waits for the window
        assertThat(ok(it.anon(HttpMethod.POST, "/api/v1/applicant/cce/lookup", Map.of("jambKey", jamb, "dateOfBirth", "1988-02-15"))).get("state")).isEqualTo("nomatch");
        assertThat(ok(it.anon(HttpMethod.POST, "/api/v1/applicant/cce/lookup", Map.of("jambKey", jamb, "dateOfBirth", "1988-02-14"))).get("state")).isEqualTo("found");
        Map<String, Object> register = Map.of("jambKey", jamb, "dateOfBirth", "1988-02-14", "email", email, "phone", "08061234567", "password", "a long password " + n);
        assertThat(code(it.anon(HttpMethod.POST, "/api/v1/applicant/cce/register", register))).isEqualTo("APPLICATION_CLOSED");
        it.db(() -> jdbc.sql("SELECT policy.window_act('CCE_APPLICATION', :s, NULL, 'OPEN', NULL, NULL, NULL, false, 'integration test', gen_random_uuid(), 'ict')")
                .param("s", SESSION).query().listOfRows());
        assertThat(code(it.anon(HttpMethod.POST, "/api/v1/applicant/cce/register", Map.of("jambKey", jamb, "dateOfBirth", "1990-01-01", "email", "x" + email,
                "phone", "08061234567", "password", "a long password " + n)))).isEqualTo("CCE_NOT_LISTED");
        Map<String, Object> signed = ok(it.anon(HttpMethod.POST, "/api/v1/applicant/cce/register", register));
        String applicant = String.valueOf(signed.get("token"));
        assertThat(code(it.anon(HttpMethod.POST, "/api/v1/applicant/cce/register", register))).isEqualTo("CCE_REGISTERED");

        // (4) the form, the fee and the documents; then submitted
        Map<String, Object> view = ok(it.get(applicant, "/api/v1/applicant/me/cce"));
        assertThat(view.get("route")).isEqualTo("CCE");
        assertThat(((Map) ((Map) view.get("cce")).get("listed")).get("session")).isEqualTo(SESSION);
        assertThat(((Map) view.get("fees")).get("checkingFee")).isEqualTo(0);
        ok(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/cce/biodata", Map.of("fields", Map.of("date_of_birth", "1988-02-14", "home_address", "4 Railway Road, Makurdi",
                "state_of_origin", "Benue", "lga", "Gboko", "nationality", "Nigeria", "mobile", "08061234567", "kin_name", "Terhemba Iorliam", "kin_relationship", "Husband",
                "kin_mobile", "08069876543"))));
        ok(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/cce/olevel", Map.of("sittings", List.of(
                Map.of("sitting", 1, "exam_body", "WAEC", "exam_number", "4251201001", "exam_year", "2006",
                       "subjects", List.of(Map.of("subject", "English Language", "grade", "C6"), Map.of("subject", "Biology", "grade", "C5"), Map.of("subject", "Government", "grade", "B3"))),
                Map.of("sitting", 2, "exam_body", "NECO", "exam_number", "1007300222", "exam_year", "2007",
                       "subjects", List.of(Map.of("subject", "Mathematics", "grade", "C4"), Map.of("subject", "Physics", "grade", "C5")))))));
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/cce/programme", null));
        assertThat(code(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/submit", Map.of("declaration", true)))).isEqualTo("CCE_INCOMPLETE");
        Map<String, Object> withRef = ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")));
        String ref = String.valueOf(withRef.get("reference"));
        assertThat(jdbc.sql("SELECT amount FROM admissions.fee_reference WHERE reference = :r").param("r", ref).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("6500");
        assertThat(code(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "CHECKING")))).isEqualTo("CCE_NO_CHECKING_FEE");
        confirm(ref);
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", "PASSPORT", "filename", "me.png", "contentType", "image/png", "contentBase64", PIXEL)));
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", "OLEVEL_STATEMENT", "filename", "waec.pdf", "contentType", "application/pdf", "contentBase64", PDF)));
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", "OLEVEL_STATEMENT_2", "filename", "neco.pdf", "contentType", "application/pdf", "contentBase64", PDF)));
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/submit", Map.of("declaration", true)));
        assertThat(code(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", "PASSPORT", "filename", "other.png", "contentType", "image/png", "contentBase64", PIXEL))))
                .isEqualTo("CCE_NOT_EDITABLE");

        // (5) the Centre reviews; the recommender does not approve; the Academic Office approves and publishes
        Map<String, Object> list = ok(it.get(centre, "/api/v1/cce/applications?session=" + SESSION + "&q=" + jamb));
        assertThat(((Number) list.get("total")).intValue()).isEqualTo(1);
        String app = String.valueOf(((Map) ((List) list.get("rows")).get(0)).get("id"));
        assertThat(it.get(centre, "/api/v1/cce/applications/" + UUID.randomUUID()).getStatusCode().value()).isEqualTo(404);
        ok(it.call(centre, HttpMethod.POST, "/api/v1/cce/applications/" + app + "/act", Map.of("action", "START")));
        Map<String, Object> detail = ok(it.get(centre, "/api/v1/cce/applications/" + app));
        for (Object d : (List) detail.get("documents")) {
            assertThat(it.getBytes(centre, "/api/v1/cce/applications/" + app + "/documents/" + ((Map) d).get("id")).getStatusCode().value()).isEqualTo(200);
            ok(it.call(centre, HttpMethod.POST, "/api/v1/cce/applications/" + app + "/documents/" + ((Map) d).get("id") + "/review", Map.of("status", "ACCEPTED")));
        }
        ok(it.call(centre, HttpMethod.POST, "/api/v1/cce/applications/" + app + "/act", Map.of("action", "RECOMMEND", "note", "Credits in English and Mathematics")));
        assertThat(code(it.call(centre, HttpMethod.POST, "/api/v1/cce/applications/" + app + "/act", Map.of("action", "APPROVE")))).isEqualTo("CCE_APPROVE_OWN");
        ok(it.call(academic, HttpMethod.POST, "/api/v1/cce/applications/" + app + "/act", Map.of("action", "APPROVE")));
        assertThat(it.call(centre, HttpMethod.POST, "/api/v1/cce/publish", Map.of("session", SESSION)).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> published = ok(it.call(academic, HttpMethod.POST, "/api/v1/cce/publish", Map.of("session", SESSION, "applicationIds", List.of(app))));
        assertThat(((Map) published.get("published")).get("admitted")).isEqualTo(1);

        // (6) the applicant reads the offer (no window, no checking fee), accepts, pays the CCE acceptance fee: on the register
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/admission/checked", null));
        Map<String, Object> me = ok(it.get(applicant, "/api/v1/applicant/me"));
        assertThat(me.get("decision")).isEqualTo("OFFERED");
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true)));
        String acc = String.valueOf(ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE"))).get("reference"));
        assertThat(jdbc.sql("SELECT amount FROM admissions.fee_reference WHERE reference = :r").param("r", acc).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("25000");
        confirm(acc);
        Map<String, Object> student = jdbc.sql("SELECT s.id, s.entry_mode, s.study_mode, s.entry_session FROM people.student s JOIN admissions.candidate c ON c.id = s.candidate_id WHERE c.jamb_reg_no = :j")
                .param("j", jamb).query().singleRow();
        assertThat(student.get("entry_mode")).isEqualTo("CCE");
        assertThat(student.get("study_mode")).isEqualTo("PART_TIME");
        assertThat(student.get("entry_session")).isEqualTo(SESSION);
        Map<String, Object> letter = ok(it.get(applicant, "/api/v1/applicant/me/letter"));
        assertThat(String.valueOf(letter)).contains("PART-TIME").contains("Centre for Continuing Education");

        // (7) the student portal: the CCE session, part-time, the Centre, expected completion six sessions on
        String st = TestTokens.token((UUID) student.get("id"), List.of("student"));
        Map<String, Object> academicView = (Map<String, Object>) ok(it.get(st, "/api/v1/me")).get("academic");
        assertThat(academicView.get("session")).isEqualTo(SESSION);
        assertThat(academicView.get("studyMode")).isEqualTo("PART_TIME");
        assertThat(academicView.get("centre")).isEqualTo("Centre for Continuing Education");
        assertThat(academicView.get("expectedCompletion")).isEqualTo("2118/2119");
        Map<String, Object> students = ok(it.get(academic, "/api/v1/cce/students?session=" + SESSION));
        assertThat(((Number) students.get("total")).intValue()).isGreaterThanOrEqualTo(1);
    }

    private static java.security.MessageDigest sha() {
        try {
            return java.security.MessageDigest.getInstance("SHA-256");
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** the Bursary's confirmation of a reference paid at the bank, as a person */
    private void confirm(String reference) {
        it.db(() -> jdbc.sql("SELECT admissions.confirm_fee(:r, 'BANK', 'integration test')").param("r", reference).query(String.class).single());
    }
}
