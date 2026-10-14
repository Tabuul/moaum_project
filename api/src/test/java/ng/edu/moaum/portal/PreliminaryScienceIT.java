package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
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
 * V446 — Preliminary Science through the API: the public page reads the programme, its targets and its fee; a candidate with no
 * JAMB number starts an application online and is signed in with an ordinary application number; the fee is paid before the form
 * opens; an awaiting result is refused and the eligibility is the backend's; only a configured target is accepted; the documents
 * and the submission go through the ordinary applicant endpoints; the desk is the Preliminary Science Office's and the Academic
 * Office's (a lecturer, the Bursary and the applicant are refused, a Head of Department reads only their department's targets and
 * never the applicant's contacts); the Office recommends, someone else approves, the Academic Office publishes; the applicant
 * reads the admission into Preliminary Science and prints the letter; another applicant cannot reach the first's documents.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PreliminaryScienceIT {

    static final String TARGET = "C00023";
    static final String PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";
    static final String PDF = java.util.Base64.getEncoder().encodeToString("%PDF-1.4\n% a result\n%%EOF\n".getBytes());

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String office = ItSupport.token("prelim");
    final String bursar = ItSupport.token("bursar");
    final String lecturer = ItSupport.token("lecturer");
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        session = it.db(() -> jdbc.sql("SELECT policy.route_session('PRELIMINARY_SCIENCE')").query(String.class).single());
        // the window open for the test, as the Director of ICT opens it, whatever an earlier run left
        it.db(() -> jdbc.sql("""
                SELECT CASE WHEN (SELECT w.state FROM policy.window_state('PRELIMINARY_SCIENCE_APPLICATION', :s, NULL) w) = 'OPEN' THEN NULL
                            ELSE policy.window_act('PRELIMINARY_SCIENCE_APPLICATION', :s, NULL, 'OPEN', NULL, NULL, NULL, false,
                                                   'integration test: Preliminary Science applications open', gen_random_uuid(), 'ict') END
                """).param("s", session).query().listOfRows());
        // the test's target: Computer Science, an existing undergraduate programme, offered under Preliminary Science
        ResponseEntity<Map> added = it.call(academic, HttpMethod.POST, "/api/v1/admissions/preliminary/config/targets",
                Map.of("programmeCode", TARGET, "group", "Science / Technology", "ord", 120, "reason", "integration test: Computer Science as a target"));
        assertThat(added.getStatusCode().value() == 200 || "PRELIM_TARGET_DUPLICATE".equals(code(added))).as(String.valueOf(added.getBody())).isTrue();
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    private void confirm(String reference) {
        it.db(() -> jdbc.sql("SELECT admissions.confirm_fee(:r, 'WEBPAY', 'integration test')").param("r", reference).query(String.class).single());
    }

    private Map<String, Object> register(String tag, String sex) {
        return ok(it.anon(HttpMethod.POST, "/api/v1/applicant/preliminary/register", Map.of("surname", "Prelim" + tag, "firstName", "Ada" + tag, "middleName", "Ene",
                "sex", sex, "dateOfBirth", "2007-03-01", "email", "prelim" + tag + "@example.com", "phone", "0803" + tag.substring(0, 7), "password", "a-long-password-" + tag)));
    }

    private Map<String, Object> prelim(String token) {
        return (Map<String, Object>) ok(it.get(token, "/api/v1/applicant/me/preliminary")).get("preliminary");
    }

    @Test
    void aCandidateAppliesOnlineIsReviewedAndAdmittedIntoPreliminaryScienceNeverIntoTheTarget() {
        String tag = String.valueOf(Math.abs(UUID.randomUUID().getMostSignificantBits() % 9_000_000_000L) + 1_000_000_000L);

        // (1) the public page: the programme, its targets (existing programmes), the fee the Bursary stated, the window
        Map<String, Object> pub = ok(it.anon(HttpMethod.GET, "/api/v1/public/preliminary-science", null));
        assertThat(pub.get("name")).isEqualTo("Preliminary Science");
        assertThat((List<Map<String, Object>>) pub.get("targets")).extracting(t -> t.get("programmeCode")).contains(TARGET);
        assertThat(((Map) pub.get("rules")).get("awaitingAccepted")).isEqualTo(false);
        assertThat(((Map) pub.get("window")).get("state")).isEqualTo("OPEN");

        // (2) started online: no JAMB number, an ordinary application number, signed in at once; the form waits for the fee
        Map<String, Object> signed = register(tag, "F");
        String applicant = String.valueOf(signed.get("token"));
        assertThat(String.valueOf(signed.get("applicationNo"))).matches("APP/[0-9]{2}/[0-9]{6}");
        Map<String, Object> me = ok(it.get(applicant, "/api/v1/applicant/me/preliminary"));
        assertThat(me.get("route")).isEqualTo("PRELIMINARY_SCIENCE");
        Map<String, Object> p = (Map<String, Object>) me.get("preliminary");
        assertThat(p.get("state")).isEqualTo("DRAFT");
        assertThat(p.get("feeSettled")).isEqualTo(false);
        assertThat(code(it.anon(HttpMethod.POST, "/api/v1/applicant/preliminary/register", Map.of("surname", "Prelim" + tag, "firstName", "Ada" + tag,
                "sex", "F", "dateOfBirth", "2007-03-01", "email", "other" + tag + "@example.com", "phone", "0805" + tag.substring(0, 7), "password", "a-long-password")))).isEqualTo("PRELIM_DUPLICATE");
        assertThat(code(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", "PASSPORT", "filename", "me.png", "contentType", "image/png", "contentBase64", PIXEL))))
                .isEqualTo("PRELIM_FEE_FIRST");

        // (3) the fee: the route's application fee; nothing else is charged
        Map<String, Object> withRef = ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")));
        String ref = String.valueOf(withRef.get("reference"));
        assertThat(code(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE")))).isEqualTo("PRELIM_FEE_NOT_CONFIGURED");
        confirm(ref);
        assertThat(prelim(applicant).get("feeSettled")).isEqualTo(true);

        // (4) the O'Level: an awaiting result refused; four credits, three of the core — eligible, Physics to be made up
        assertThat(code(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/olevel", Map.of("sittings", List.of(
                Map.of("sitting", 1, "exam_body", "WAEC", "exam_number", "4250101001", "exam_year", "2025", "awaiting", true, "subjects", List.of(Map.of("subject", "Physics", "grade", "C5")))))))).isEqualTo("PRELIM_AWAITING_RESULT");
        Map<String, Object> olevel = ok(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/olevel", Map.of("sittings", List.of(
                Map.of("sitting", 1, "exam_body", "WAEC", "exam_type", "SSCE", "exam_number", "4250101001", "exam_year", "2024", "subjects", List.of(
                        Map.of("subject", "English Language", "grade", "C6"), Map.of("subject", "Mathematics", "grade", "C5"), Map.of("subject", "Chemistry", "grade", "C6"),
                        Map.of("subject", "Physics", "grade", "D7"), Map.of("subject", "Biology", "grade", "C5")))))));
        Map<String, Object> elig = (Map<String, Object>) ((Map) olevel.get("preliminary")).get("eligibility");
        assertThat(elig.get("status")).isEqualTo("ELIGIBLE_WITH_REMEDIATION");
        assertThat(((Map) ((Map) olevel.get("preliminary")).get("remediation")).get("subjects")).isEqualTo(List.of("Physics"));

        // (5) the target: only a configured one; the biodata; the documents
        assertThat(code(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/target", Map.of("programmeCode", "C00019")))).isEqualTo("PRELIM_TARGET_NOT_OFFERED");
        ok(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/target", Map.of("programmeCode", TARGET)));
        ok(it.call(applicant, HttpMethod.PUT, "/api/v1/applicant/me/preliminary/biodata", Map.of("sex", "F", "fields", Map.of("home_address", "1 Test Road, Makurdi",
                "state_of_origin", "Benue", "lga", "Makurdi", "nationality", "Nigerian", "kin_name", "Ene Prelim", "kin_relationship", "Mother", "kin_mobile", "08031230000"))));
        assertThat(code(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/submit", Map.of("declaration", true)))).isEqualTo("PRELIM_INCOMPLETE");
        assertThat(code(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", "JAMB_SLIP", "filename", "x.pdf", "contentType", "application/pdf", "contentBase64", PDF))))
                .isEqualTo("APP_DOCUMENT_KIND");
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", "PASSPORT", "filename", "me.png", "contentType", "image/png", "contentBase64", PIXEL)));
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", "PASSPORT_2", "filename", "me2.png", "contentType", "image/png", "contentBase64", PIXEL)));
        for (String kind : List.of("OLEVEL_STATEMENT", "LGA_ID", "BIRTH_CERT")) {
            ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", kind, "filename", kind.toLowerCase() + ".pdf", "contentType", "application/pdf", "contentBase64", PDF)));
        }
        ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/submit", Map.of("declaration", true)));
        assertThat(prelim(applicant).get("state")).isEqualTo("SUBMITTED");
        UUID app = UUID.fromString(String.valueOf(ok(it.get(applicant, "/api/v1/applicant/me")).get("id")));

        // (6) the desk: refused to a lecturer, the Bursary and the applicant; a Head of Department reads only their department's targets
        assertThat(it.get(lecturer, "/api/v1/admissions/preliminary/summary").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(applicant, "/api/v1/admissions/preliminary/applications").getStatusCode().value()).isEqualTo(403);
        Map<String, Object> list = ok(it.get(office, "/api/v1/admissions/preliminary/applications?view=pendingReview&size=500&q=" + tag));
        assertThat((List<Map<String, Object>>) list.get("rows")).extracting(r -> String.valueOf(r.get("id"))).contains(app.toString());
        String hodMtc = it.officer("hod", "department", "MTC");
        List<Map<String, Object>> hodRows = (List<Map<String, Object>>) ok(it.get(hodMtc, "/api/v1/admissions/preliminary/applications?size=500&q=" + tag)).get("rows");
        assertThat(hodRows).extracting(r -> String.valueOf(r.get("id"))).contains(app.toString());
        assertThat(hodRows.get(0)).doesNotContainKeys("email", "phone");
        String hodAcc = it.officer("hod", "department", "ACC");
        assertThat((List<Map<String, Object>>) ok(it.get(hodAcc, "/api/v1/admissions/preliminary/applications?size=500&q=" + tag)).get("rows")).isEmpty();
        assertThat(it.get(hodAcc, "/api/v1/admissions/preliminary/applications/" + app).getStatusCode().value()).isEqualTo(404);
        assertThat(it.call(hodMtc, HttpMethod.POST, "/api/v1/admissions/preliminary/applications/" + app + "/act", Map.of("action", "START")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/admissions/preliminary/applications/" + app + "/act", Map.of("action", "START")).getStatusCode().value()).isEqualTo(403);

        // (7) the review: taken up, documents accepted, the O'Level verified, recommended; the recommender does not approve
        ok(it.call(office, HttpMethod.POST, "/api/v1/admissions/preliminary/applications/" + app + "/act", Map.of("action", "START")));
        Map<String, Object> detail = ok(it.get(office, "/api/v1/admissions/preliminary/applications/" + app));
        List<Map<String, Object>> docs = (List<Map<String, Object>>) detail.get("documents");
        assertThat(docs).hasSize(5);
        assertThat(it.getBytes(office, "/api/v1/admissions/preliminary/applications/" + app + "/documents/" + docs.get(0).get("id") + "/content").getStatusCode().value()).isEqualTo(200);
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/admissions/preliminary/applications/" + app + "/act", Map.of("action", "RECOMMEND")))).isEqualTo("PRELIM_DOCUMENTS_UNVERIFIED");
        for (Map<String, Object> d : docs) {
            ok(it.call(office, HttpMethod.POST, "/api/v1/admissions/preliminary/applications/" + app + "/documents/" + d.get("id") + "/review", Map.of("status", "ACCEPTED")));
        }
        assertThat(code(it.call(office, HttpMethod.POST, "/api/v1/admissions/preliminary/applications/" + app + "/act", Map.of("action", "RECOMMEND")))).isEqualTo("PRELIM_OLEVEL_UNVERIFIED");
        ok(it.call(office, HttpMethod.POST, "/api/v1/admissions/preliminary/applications/" + app + "/verify-olevel", Map.of("outcome", "VERIFIED")));
        ok(it.call(office, HttpMethod.POST, "/api/v1/admissions/preliminary/applications/" + app + "/act", Map.of("action", "RECOMMEND", "note", "meets the requirement")));
        // the applicant reads no unpublished step
        assertThat(prelim(applicant).get("state")).isEqualTo("UNDER_REVIEW");
        assertThat(it.call(office, HttpMethod.POST, "/api/v1/admissions/preliminary/publish", Map.of("session", session)).getStatusCode().value()).isEqualTo(403);
        ok(it.call(academic, HttpMethod.POST, "/api/v1/admissions/preliminary/applications/" + app + "/act", Map.of("action", "APPROVE")));
        Map<String, Object> pub2 = ok(it.call(academic, HttpMethod.POST, "/api/v1/admissions/preliminary/publish", Map.of("session", session, "applicationIds", List.of(app))));
        assertThat(pub2.get("admitted")).isEqualTo(1);

        // (8) the applicant: admitted into Preliminary Science, the target an intended progression, the letter printed
        Map<String, Object> after = ok(it.get(applicant, "/api/v1/applicant/me"));
        assertThat(after.get("decision")).isEqualTo("OFFERED");
        assertThat(after.get("programme")).isEqualTo("Preliminary Science");
        assertThat(prelim(applicant).get("state")).isEqualTo("ADMITTED");
        Map<String, Object> letter = ok(it.get(applicant, "/api/v1/applicant/me/letter"));
        assertThat(String.valueOf(letter.get("statement"))).contains("PRELIMINARY_SCIENCE").contains("does not constitute admission");

        // (9) another applicant: never the first's documents
        String other = String.valueOf(register(String.valueOf(Long.parseLong(tag) + 1), "M").get("token"));
        assertThat(it.getBytes(other, "/api/v1/applicant/me/documents/" + docs.get(0).get("id") + "/content").getStatusCode().value()).isEqualTo(404);

        // (10) the configuration: the Academic Office's, with a reason; the Bursary states the fee
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/admissions/preliminary/config/rules", Map.of("settings", Map.of("min_credits", 4), "reason", "no")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/admissions/preliminary/config/rules", Map.of("settings", Map.of("min_credits", 4))).getStatusCode().value()).isEqualTo(400);
        Map<String, Object> cfg = ok(it.call(academic, HttpMethod.PUT, "/api/v1/admissions/preliminary/config/rules",
                Map.of("settings", Map.of("min_credits", 4), "reason", "integration test: the rule restated")));
        assertThat(((Map) cfg.get("programme")).get("min_credits")).isEqualTo(4);
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/admissions/preliminary/config/fee", Map.of("applicationFee", 5000)).getStatusCode().value()).isEqualTo(403);
    }
}
