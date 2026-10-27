package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * A transcript asked for without a portal account (V668), through the API. A graduate with a date of birth and a contact on record:
 * a wrong date of birth refused, the code sent to the contact (masked on the answer), a wrong code refused and the right one giving a
 * pass, the request made with it and followed by its private link (a made-up link is not found). An institution's request, the
 * graduate's consent given at their own link and shown on the status page. A graduate without the contact: a renamed executable
 * refused as the identity document, a real PNG accepted; the desk lists it for review, opens the document (a student cannot), accepts
 * it, and the request's detail carries its public side and the cover letter. A filled honeypot is refused. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class TranscriptPublicIT {

    static final String PUB = "/api/v1/public/transcripts";
    static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 'I', 'H', 'D', 'R'};

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    private ResponseEntity<Map> pub(HttpMethod method, String path, Object body) {
        var spec = open.method(method).uri(path);
        if (body != null) spec = spec.contentType(MediaType.APPLICATION_JSON).body(body);
        return spec.retrieve().toEntity(Map.class);
    }

    private static int status(ResponseEntity<?> r) {
        return r.getStatusCode().value();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static Map<String, Object> parse(Object json) {
        return new tools.jackson.databind.ObjectMapper().readValue(String.valueOf(json), Map.class);
    }

    private static String token(Map<String, Object> made) {
        String path = String.valueOf(made.get("statusPath"));
        return path.substring(path.lastIndexOf('/') + 1);
    }

    /** a made-up graduate with a date of birth and, when asked, a contact on record */
    private UUID graduate(String tag, String matric, boolean contact) {
        UUID s = it.student("ZZTRN-" + tag, "C00023", "MOAUM/ADM/17/" + tag, matric, 400);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET date_of_birth = DATE '1994-06-06', sex = 'F' WHERE id = :s").param("s", s).update();
            if (contact) {
                jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08030006680', :e, now()) ON CONFLICT (student_id) DO NOTHING")
                        .param("s", s).param("e", "zztrn." + tag + "@example.com").update();
            }
            return null;
        });
        return s;
    }

    private static Map<String, Object> order(String destination, String name, String email) {
        Map<String, Object> o = new LinkedHashMap<>();
        o.put("kind", "TRANSCRIPT"); o.put("destination", destination); o.put("destinationName", name); o.put("recipient", name == null ? null : "The Registrar");
        o.put("recipientEmail", email); o.put("purpose", "Postgraduate admission"); o.put("delivery", "DIGITAL"); o.put("express", false); o.put("international", false);
        o.put("copies", 1);
        return o;
    }

    @Test
    void aGraduateAnInstitutionAndAnIdentityDocumentEachAskWithoutAnAccount() {
        String tag = Integer.toString(ThreadLocalRandom.current().nextInt(100000, 999999));
        String matric = "BSU/ZZ/TRN/17/" + tag;
        graduate(tag, matric, true);
        String tag2 = Integer.toString(ThreadLocalRandom.current().nextInt(100000, 999999));
        String matric2 = "BSU/ZZ/TRN/18/" + tag2;
        graduate(tag2, matric2, false);

        // ── the form's options: the transcript policies and the identity document's size ──
        Map<String, Object> options = ok(pub(HttpMethod.GET, PUB + "/options", null));
        assertThat((List<?>) options.get("policies")).isNotEmpty();
        assertThat(options.get("maxIdMb")).isEqualTo(5);

        // ── a graduate: a wrong date of birth is refused, the right one sends a code to the contact on record ──
        ResponseEntity<Map> wrong = pub(HttpMethod.POST, PUB + "/code", Map.of("matricNo", matric, "dateOfBirth", "1994-06-07"));
        assertThat(status(wrong)).isEqualTo(422);
        assertThat(code(wrong)).isEqualTo("TRN_NOT_MATCHED");
        assertThat(code(pub(HttpMethod.POST, PUB + "/code", Map.of("matricNo", matric, "dateOfBirth", "1994-06-06", "website2", "x")))).isEqualTo("TRN_REFUSED");
        Map<String, Object> sent = ok(pub(HttpMethod.POST, PUB + "/code", Map.of("matricNo", " " + matric.toLowerCase() + " ", "dateOfBirth", "1994-06-06")));
        assertThat(String.valueOf(sent.get("email"))).doesNotContain("zztrn." + tag).contains("@");
        String code = jdbc.sql("""
                SELECT substring(n.subject FROM '([0-9]{6})$') FROM platform.notice n WHERE n.channel = 'EMAIL' AND n.recipient = :e
                   AND n.subject LIKE 'Your transcript request code:%' ORDER BY n.created_at DESC LIMIT 1
                """).param("e", "zztrn." + tag + "@example.com").query(String.class).single();
        String challenge = String.valueOf(sent.get("challenge"));
        ResponseEntity<Map> bad = pub(HttpMethod.POST, PUB + "/code/check", Map.of("challenge", challenge, "code", "000000".equals(code) ? "111111" : "000000"));
        assertThat(code(bad)).isEqualTo("TRN_CODE_WRONG");
        Map<String, Object> checked = ok(pub(HttpMethod.POST, PUB + "/code/check", Map.of("challenge", challenge, "code", code)));
        assertThat(((Map<String, Object>) checked.get("graduate")).get("matric_no")).isEqualTo(matric);

        // ── the request made with the pass, and followed by its private link ──
        Map<String, Object> g = ok(pub(HttpMethod.POST, PUB + "/requests/graduate",
                Map.of("pass", checked.get("pass"), "order", order("SELF", null, null))));
        assertThat(String.valueOf(g.get("ref"))).matches("TRN-\\d{4}-\\d{5}");
        Map<String, Object> st = ok(pub(HttpMethod.GET, PUB + "/status/" + token(g), null));
        Map<String, Object> req = parse(st.get("request"));
        assertThat(req.get("ref")).isEqualTo(g.get("ref"));
        assertThat(req.get("identityState")).isEqualTo("CONFIRMED");
        assertThat(String.valueOf(st.get("request"))).doesNotContain("student_id").doesNotContain("status_hash");
        assertThat(code(pub(HttpMethod.GET, PUB + "/status/not-a-real-link-at-all-" + tag, null))).isEqualTo("TRN_NOT_FOUND");

        // ── an institution names the graduate; the graduate consents at their own link ──
        Map<String, Object> inst = ok(pub(HttpMethod.POST, PUB + "/requests/institution", Map.of("matricNo", matric, "surname", "zztrn-" + tag,
                "organisation", "Invented University", "name", "Admissions Officer", "email", "admissions." + tag + "@example.org",
                "order", order("INSTITUTION", "Invented University", "admissions." + tag + "@example.org"))));
        assertThat(parse(ok(pub(HttpMethod.GET, PUB + "/status/" + token(inst), null)).get("request")).get("consentState")).isEqualTo("AWAITING");
        String consentLink = jdbc.sql("""
                SELECT substring(n.body FROM '/transcripts/consent/([A-Za-z0-9_-]+)') FROM platform.notice n WHERE n.channel = 'EMAIL' AND n.recipient = :e
                   AND n.body LIKE '%/transcripts/consent/%' ORDER BY n.created_at DESC LIMIT 1
                """).param("e", "zztrn." + tag + "@example.com").query(String.class).single();
        assertThat(String.valueOf(ok(pub(HttpMethod.GET, PUB + "/consent/" + consentLink, null)).get("consent"))).contains("Invented University");
        assertThat(ok(pub(HttpMethod.POST, PUB + "/consent/" + consentLink, Map.of("give", true))).get("consent")).isEqualTo("GIVEN");
        assertThat(parse(ok(pub(HttpMethod.GET, PUB + "/status/" + token(inst), null)).get("request")).get("consentState")).isEqualTo("GIVEN");

        // ── a graduate without the contact: a renamed executable is refused, a real image is taken for the desk ──
        Map<String, Object> doc = new LinkedHashMap<>();
        doc.put("matricNo", matric2); doc.put("dateOfBirth", "1994-06-06"); doc.put("name", "Invented Graduate"); doc.put("email", "zztrn.new." + tag2 + "@example.com");
        doc.put("idFilename", "passport.png"); doc.put("idDataUrl", "data:image/png;base64," + Base64.getEncoder().encodeToString("MZ\u0090\u0000not an image".getBytes()));
        doc.put("order", order("SELF", null, null));
        assertThat(code(pub(HttpMethod.POST, PUB + "/requests/with-document", doc))).isEqualTo("TRN_ID_FILE");
        doc.put("idDataUrl", "data:image/png;base64," + Base64.getEncoder().encodeToString(PNG));
        Map<String, Object> d = ok(pub(HttpMethod.POST, PUB + "/requests/with-document", doc));
        assertThat(parse(ok(pub(HttpMethod.GET, PUB + "/status/" + token(d), null)).get("request")).get("identityState")).isEqualTo("AWAITING_REVIEW");

        // ── the desk: the review list, the document (a student cannot open it), the acceptance, the request's public side ──
        String records = TestTokens.token(it.person("ZZTRN-REC", "ZZTRNRECORDS"), List.of("records"));
        List<Map<String, Object>> reviews = (List<Map<String, Object>>) (List<?>) open.get().uri("/api/v1/documents/identity-reviews")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + records).retrieve().toEntity(List.class).getBody();
        Map<String, Object> row = reviews.stream().filter(r -> d.get("ref").equals(r.get("ref"))).findFirst().orElseThrow();
        String id = String.valueOf(row.get("id"));
        ResponseEntity<byte[]> file = open.get().uri("/api/v1/documents/requests/" + id + "/identity").header(HttpHeaders.AUTHORIZATION, "Bearer " + records)
                .retrieve().toEntity(byte[].class);
        assertThat(status(file)).isEqualTo(200);
        assertThat(file.getHeaders().getContentType()).hasToString("image/png");
        assertThat(file.getBody()).isEqualTo(PNG);
        UUID other = graduate(Integer.toString(ThreadLocalRandom.current().nextInt(100000, 999999)), null, false);
        assertThat(status(open.get().uri("/api/v1/documents/requests/" + id + "/identity")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + TestTokens.token(other, List.of("student"))).retrieve().toEntity(byte[].class))).isEqualTo(403);
        assertThat(code(it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + id + "/identity", Map.of("accept", false)))).isNotNull();
        assertThat(ok(it.call(records, HttpMethod.POST, "/api/v1/documents/requests/" + id + "/identity", Map.of("accept", true, "note", "passport matches"))).get("identityState"))
                .isEqualTo("ACCEPTED");
        Map<String, Object> detail = ok(it.get(records, "/api/v1/documents/requests/" + id));
        assertThat(parse(detail.get("publicSide")).get("identityState")).isEqualTo("ACCEPTED");
        assertThat(detail.get("coverLetter")).isNull();

        String instId = jdbc.sql("SELECT id::text FROM credentials.transcript_request WHERE ref = :r").param("r", inst.get("ref")).query(String.class).single();
        Map<String, Object> instDetail = ok(it.get(records, "/api/v1/documents/requests/" + instId));
        assertThat(String.valueOf(parse(instDetail.get("coverLetter")).get("body"))).contains(matric).contains("Postgraduate admission");
    }
}
