package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Random;

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
 * The applicant's journey end to end (V021): registration from the CAPS list,
 * the fee confirmed by the Bursary, the form and its documents, the seat, the
 * result, the Board's offer, the acceptance — and, at every step, that the
 * applicant sees only what is released and never the O'Level score.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class ApplicantIT {

    static final String SESSION = "2093/2094";
    static final String PATH = "/api/v1/admissions/sessions/2093/2094";

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
    String registrar = ItSupport.token("registrar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    @Test
    @SuppressWarnings("unchecked")
    void fromTheJambNumberToAnAcceptedOffer() {
        String jamb = "2026" + String.format("%08d", new Random().nextInt(100_000_000)) + "AP";

        // nobody is verified while no list is loaded
        assertThat(post("/api/v1/applicant/lookup", Map.of("session", SESSION, "jambKey", jamb)).getBody().get("state")).isEqualTo("nolist");

        // the Academic Office loads the Direct Entry list JAMB sent (no settings are needed for a DE list)
        ResponseEntity<Map> loaded = it.call(academic, HttpMethod.POST, "/api/v1/admissions/caps-batches", Map.of(
                "session", SESSION, "source", "CAPS_DOWNLOAD", "filename", "CAPS-DE-it.xlsx",
                "fileSha256", String.format("%064x", new Random().nextLong() & Long.MAX_VALUE), "listKind", "DIRECT_ENTRY",
                "downloadedOn", "2026-09-01",
                "rows", List.of(Map.of("jambRegNo", jamb, "surname", "ITAPPLICANT", "otherNames", "Invented Person", "jambCode", "C00061",
                        "entryMode", "DIRECT_ENTRY", "sex", "F", "stateOfOrigin", "Benue", "lga", "Gwer West", "raw", Map.of()))));
        assertThat(loaded.getStatusCode().value()).as(String.valueOf(loaded.getBody())).isEqualTo(201);

        // found: the name is read from the list, never typed
        Map<String, Object> found = post("/api/v1/applicant/lookup", Map.of("session", SESSION, "jambKey", jamb.toLowerCase())).getBody();
        assertThat(found.get("state")).isEqualTo("found");
        assertThat(found.get("name")).isEqualTo("ITAPPLICANT, Invented Person");
        assertThat(found.get("list")).isEqualTo("de");

        // registering: the phone is read from the +234 form; a token comes back
        ResponseEntity<Map> registered = post("/api/v1/applicant/register", Map.of("session", SESSION, "jambKey", jamb,
                "email", jamb.toLowerCase() + "@example.com", "phone", "+234 803 411 7725", "password", "a long enough password"));
        assertThat(registered.getStatusCode().value()).as(String.valueOf(registered.getBody())).isEqualTo(200);
        String token = String.valueOf(registered.getBody().get("token"));
        String appNo = String.valueOf(registered.getBody().get("applicationNo"));
        assertThat(appNo).matches("APP/93/\\d{6}");
        assertThat(post("/api/v1/applicant/lookup", Map.of("session", SESSION, "jambKey", jamb)).getBody().get("state")).isEqualTo("registered");

        // a second account for the same number is refused as a conflict: one already exists
        assertThat(post("/api/v1/applicant/register", Map.of("session", SESSION, "jambKey", jamb, "email", "other" + jamb + "@example.com",
                "phone", "08034117725", "password", "a long enough password")).getStatusCode().value()).isEqualTo(409);

        // the applicant's own view: stage 0, biodata from JAMB, no result, no decision
        Map<String, Object> me = it.get(token, "/api/v1/applicant/me").getBody();
        assertThat(me.get("stage")).isEqualTo(0);
        assertThat(((Map<String, Object>) me.get("biodata")).get("stateOfOrigin")).isEqualTo("Benue");
        assertThat(me.get("result")).isNull();
        assertThat(me.get("decision")).isNull();

        // the form is closed until the fee is confirmed
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/submit", Map.of("declaration", true)).getStatusCode().value()).isEqualTo(422);

        // a reference this portal generated, confirmed by the Bursary against the bank's record
        Map<String, Object> withRef = it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")).getBody();
        String reference = String.valueOf(withRef.get("reference"));
        assertThat(reference).startsWith("MOAUM-APP-");
        ResponseEntity<Map> confirmed = it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + reference + "/confirm", Map.of("channel", "Bank transfer"));
        assertThat(confirmed.getStatusCode().value()).as(String.valueOf(confirmed.getBody())).isEqualTo(200);
        assertThat(it.get(token, "/api/v1/applicant/me").getBody().get("stage")).isEqualTo(1);

        // next of kin, five documents, the declaration
        it.call(token, HttpMethod.PUT, "/api/v1/applicant/me/next-of-kin", Map.of("nextOfKin", "ITAPPLICANT, Terhemba · 0806 552 1180"));
        String pdf = Base64.getEncoder().encodeToString("%PDF-1.4 invented".getBytes());
        for (String kind : List.of("OLEVEL_STATEMENT", "BIRTH_CERT", "LGA_ID", "JAMB_SLIP", "PASSPORT")) {
            ResponseEntity<Map> up = it.call(token, HttpMethod.POST, "/api/v1/applicant/me/documents",
                    Map.of("kind", kind, "filename", kind.toLowerCase() + ".pdf", "contentType", "application/pdf", "contentBase64", pdf));
            assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        }
        ResponseEntity<Map> submitted = it.call(token, HttpMethod.POST, "/api/v1/applicant/me/submit", Map.of("declaration", true));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("stage")).isEqualTo(2);
        // and not edited afterwards — except the passport photograph, which comes whenever the applicant has one (V022)
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/documents",
                Map.of("kind", "JAMB_SLIP", "filename", "slip2.pdf", "contentType", "application/pdf", "contentBase64", pdf)).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/documents",
                Map.of("kind", "PASSPORT", "filename", "passport2.pdf", "contentType", "application/pdf", "contentBase64", pdf)).getStatusCode().value()).isEqualTo(200);

        // the Academic Office sees the application on its desk, with the document to review
        Map<String, Object> desk = it.get(academic, PATH + "/applicants").getBody();
        List<Map<String, Object>> apps = (List<Map<String, Object>>) desk.get("applications");
        Map<String, Object> mine = apps.stream().filter(a -> appNo.equals(a.get("application_no"))).findFirst().orElseThrow();
        assertThat(((Number) mine.get("documents_pending")).intValue()).isEqualTo(5);
        String appId = String.valueOf(mine.get("id"));

        // a screening batch, seated over the submitted applications
        ResponseEntity<List> batches = it.call(academic, HttpMethod.POST, PATH + "/screening-batches",
                Map.of("label", "C", "heldOn", "2026-09-22", "startsAt", "11:00", "endsAt", "12:00", "venue", "CBT Hall B, ICT Directorate", "capacity", 120))
                .getStatusCode().is2xxSuccessful() ? it.getList(academic, PATH + "/screening-batches") : null;
        assertThat(batches).isNotNull();
        String batchId = String.valueOf(((Map<?, ?>) batches.getBody().stream().filter(b -> "C".equals(((Map<?, ?>) b).get("label"))).findFirst().orElseThrow()).get("id"));
        ResponseEntity<Map> seated = it.call(academic, HttpMethod.POST, PATH + "/screening-batches/" + batchId + "/assign", Map.of());
        assertThat(((Number) seated.getBody().get("seated")).intValue()).isGreaterThanOrEqualTo(1);
        Map<String, Object> slip = (Map<String, Object>) it.get(token, "/api/v1/applicant/me").getBody().get("screeningSlip");
        assertThat(slip).isNotNull();
        assertThat(String.valueOf(slip.get("seat"))).startsWith("C-");

        // the CBT score is entered and released together; the applicant sees it only then
        ResponseEntity<Map> scored = it.call(academic, HttpMethod.PUT, PATH + "/applications/" + appId + "/screening-score", Map.of("score", 68.5));
        assertThat(scored.getStatusCode().value()).as(String.valueOf(scored.getBody())).isEqualTo(200);
        assertThat(it.get(token, "/api/v1/applicant/me").getBody().get("result")).isNull();
        it.call(academic, HttpMethod.POST, PATH + "/screening-scores/release", Map.of());
        Map<String, Object> result = (Map<String, Object>) it.get(token, "/api/v1/applicant/me").getBody().get("result");
        assertThat(result).isNotNull();
        assertThat(String.valueOf(result.get("screening"))).startsWith("68.5");
        assertThat(result.get("screeningSource")).isEqualTo("CBT");

        // the Board offers; released, the candidate is ADMITTED — the same candidate the register is built from
        ResponseEntity<Map> decided = it.call(academic, HttpMethod.PUT, PATH + "/applications/" + appId + "/decision", Map.of("decision", "OFFERED", "note", "NM"));
        assertThat(decided.getStatusCode().value()).as(String.valueOf(decided.getBody())).isEqualTo(200);
        assertThat(it.get(token, "/api/v1/applicant/me").getBody().get("decision")).isNull();
        it.call(academic, HttpMethod.POST, PATH + "/decisions/release", Map.of());
        Map<String, Object> offered = it.get(token, "/api/v1/applicant/me").getBody();
        assertThat(offered.get("decision")).isEqualTo("OFFERED");
        assertThat(offered.get("offerState")).isEqualTo("ADMITTED");
        assertThat(offered.get("stage")).isEqualTo(5);

        // accepting: the undertaking, then the acceptance fee confirmed
        ResponseEntity<Map> undertaken = it.call(token, HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true));
        assertThat(undertaken.getStatusCode().value()).as(String.valueOf(undertaken.getBody())).isEqualTo(200);
        assertThat(undertaken.getBody().get("acceptedAt")).isNull();
        String acceptance = String.valueOf(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE")).getBody().get("reference"));
        assertThat(acceptance).startsWith("MOAUM-ACC-");
        it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + acceptance + "/confirm", Map.of("channel", "Card"));
        Map<String, Object> accepted = it.get(token, "/api/v1/applicant/me").getBody();
        assertThat(accepted.get("acceptedAt")).isNotNull();
        assertThat(accepted.get("offerState")).isEqualTo("ACCEPTED");
        assertThat(accepted.get("stage")).isEqualTo(6);

        // the Registry clears the six documents, one act each
        for (String item : List.of("OLEVEL_ORIGINAL", "BIRTH_CERT", "LGA_ID", "JAMB_LETTER", "MEDICAL", "PHOTOGRAPHS")) {
            ResponseEntity<Map> cleared = it.call(registrar, HttpMethod.PUT, PATH + "/applications/" + appId + "/clearance/" + item, Map.of("state", "VERIFIED"));
            assertThat(cleared.getStatusCode().value()).as(String.valueOf(cleared.getBody())).isEqualTo(200);
        }
        assertThat(it.get(token, "/api/v1/applicant/me").getBody().get("stage")).isEqualTo(7);

        // the applicant's token reaches nothing of the office's
        assertThat(it.get(token, PATH + "/applicants").getStatusCode().value()).isEqualTo(403);
    }
}
