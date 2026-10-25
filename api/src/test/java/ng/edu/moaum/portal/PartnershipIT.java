package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HashMap;
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
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * Collaboration & partnerships (V658) through the API. The public form: the options, a draft made by its private link and saved,
 * its problems listed field by field until complete, a real PDF attached and a renamed executable refused, a filled honeypot refused,
 * submitted (PTN/YYYY/NNNNNN), the same link again the same reference, the status page by the link with nothing internal on it, a
 * new link asked for (the old one no longer opens anything). The desk: the Linkages office's figures and list, the proposal assigned
 * and accepted, a request for information answered through the link, a Dean of the faculty asked to review it sees it and another
 * faculty's Dean does not, an id that is no proposal refused, the documents read only by an office allowed (each look on the
 * timeline), the Linkages office refused the approval the Vice-Chancellor gives, the report and its workbook. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PartnershipIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    static final String PUB = "/api/v1/public/partnerships";
    static final String DESK = "/api/v1/partnerships";

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

    private static int status(ResponseEntity<Map> r) {
        return r.getStatusCode().value();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(status(r)).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String dataUrl(String type, byte[] bytes) {
        return "data:" + type + ";base64," + Base64.getEncoder().encodeToString(bytes);
    }

    /** a person holding the office over the University, with a token for it */
    private UUID holder(String office, String tag) {
        UUID p = it.person("ZZ-PTN-" + office.toUpperCase() + "-" + tag, "ZZPTN" + office.toUpperCase() + tag);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, :o, 'institution', NULL, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = :o AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                """).param("p", p).param("o", office).update());
        return p;
    }

    private static Map<String, Object> answers(String tag, String faculty, String dept) {
        Map<String, Object> a = new HashMap<>();
        a.put("firstName", "Ada"); a.put("lastName", "Invented"); a.put("orgName", "Invented Institute " + tag); a.put("orgType", "RESEARCH_INSTITUTE");
        a.put("email", "ada." + tag + "@example.org"); a.put("country", "Nigeria"); a.put("proposalKind", "NEW"); a.put("hasContact", false);
        a.put("collaboratedBefore", "NO"); a.put("category", "JOINT_RESEARCH"); a.put("title", "Invented joint research " + tag);
        a.put("summary", "A joint study of crop yields in the region."); a.put("description", "Two years of joint field work and shared data.");
        a.put("facultyCode", faculty); a.put("deptCode", dept); a.put("fundingStatus", "NONE_IDENTIFIED"); a.put("international", false);
        a.put("personalData", "NO"); a.put("ethics", "NOT_SURE");
        a.put("highRisk", Map.of("HUMAN_PARTICIPANTS", "NO", "ANIMALS", "NO", "CLINICAL", "NO", "HAZARDOUS", "NO", "CONTROLLED_TECHNOLOGY", "NO",
                "EXPORT_CONTROL", "NO", "SECURITY_SENSITIVE", "NO"));
        a.put("coi", "NO"); a.put("ownDueDiligence", "NO");
        a.put("declaredAccurate", true); a.put("declaredAuthorised", true); a.put("declaredNoCommitment", true); a.put("declaredPrivacy", true);
        a.put("consentContact", true);
        return a;
    }

    @Test
    void anEnquiryIsSubmittedFollowedByItsLinkAndWorkedByTheOfficesAllowed() {
        String tag = Integer.toString(ThreadLocalRandom.current().nextInt(100000, 999999));
        Map<String, Object> fd = jdbc.sql("""
                SELECT d.faculty_code AS fa, d.code AS da FROM ref.department d WHERE d.faculty_code IS NOT NULL AND d.ended_on IS NULL ORDER BY d.code LIMIT 1
                """).query().singleRow();
        String fa = String.valueOf(fd.get("fa"));
        String da = String.valueOf(fd.get("da"));
        String fb = jdbc.sql("SELECT code FROM ref.faculty WHERE code <> :f ORDER BY code LIMIT 1").param("f", fa).query(String.class).single();

        // the options the form offers
        Map<String, Object> options = ok(pub(HttpMethod.GET, PUB + "/options", null));
        assertThat((List<?>) options.get("categories")).isNotEmpty();
        assertThat((Map<String, Object>) options.get("settings")).containsKey("max_file_mb");

        // a draft by its private link: its problems until complete
        assertThat(code(pub(HttpMethod.POST, PUB + "/drafts", Map.of("answers", Map.of(), "website2", "http://spam.example")))).isEqualTo("PTN_REFUSED");
        Map<String, Object> made = ok(pub(HttpMethod.POST, PUB + "/drafts", Map.of("answers", Map.of("firstName", "Ada"))));
        String token = String.valueOf(made.get("token"));
        assertThat(token).hasSizeGreaterThanOrEqualTo(40);
        List<Map<String, Object>> problems = (List<Map<String, Object>>) ok(pub(HttpMethod.POST, PUB + "/drafts/" + token + "/check",
                Map.of("answers", Map.of("email", "not-an-address")))).get("problems");
        assertThat(problems).extracting(p -> p.get("field")).contains("lastName", "orgName", "email", "category", "declaredAccurate");
        assertThat(problems).filteredOn(p -> "email".equals(p.get("field"))).extracting(p -> p.get("message"))
                .containsExactly("Work email address: enter a valid email address for your organisation.");
        Map<String, Object> answers = answers(tag, fa, da);
        assertThat((List<?>) ok(pub(HttpMethod.POST, PUB + "/drafts/" + token + "/check", Map.of("answers", answers))).get("problems")).isEmpty();

        // a real PDF attached; an executable named .pdf refused; a document of a kind the form does not offer refused
        byte[] pdf = "%PDF-1.4\n1 0 obj << >> endobj\ntrailer << >>\n%%EOF".getBytes(StandardCharsets.US_ASCII);
        Map<String, Object> attached = ok(pub(HttpMethod.POST, PUB + "/drafts/" + token + "/attachments",
                Map.of("kind", "CONCEPT_NOTE", "filename", "concept note.pdf", "dataUrl", dataUrl("application/pdf", pdf))));
        assertThat((List<?>) attached.get("attachments")).hasSize(1);
        ResponseEntity<Map> exe = pub(HttpMethod.POST, PUB + "/drafts/" + token + "/attachments",
                Map.of("kind", "PROPOSAL", "filename", "proposal.pdf", "dataUrl", dataUrl("application/pdf", "MZ\u0090\u0000 not a pdf".getBytes(StandardCharsets.ISO_8859_1))));
        assertThat(code(exe)).isEqualTo("PTN_FILE_TYPE");
        assertThat(code(pub(HttpMethod.POST, PUB + "/drafts/" + token + "/attachments",
                Map.of("kind", "PROPOSAL", "filename", "run.exe", "dataUrl", dataUrl("application/octet-stream", pdf))))).isEqualTo("PTN_FILE_TYPE");

        // submitted: the reference, the same again through the same link
        Map<String, Object> sent = ok(pub(HttpMethod.POST, PUB + "/drafts/" + token + "/submit", Map.of("answers", answers)));
        String reference = String.valueOf(sent.get("reference"));
        assertThat(reference).matches("PTN/\\d{4}/\\d{6}");
        assertThat(sent).containsEntry("already", false).containsEntry("email", "ada." + tag + "@example.org");
        assertThat(ok(pub(HttpMethod.POST, PUB + "/drafts/" + token + "/submit", Map.of("answers", answers)))).containsEntry("reference", reference).containsEntry("already", true);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE event_key LIKE :k AND template_key = 'PARTNERSHIP_RECEIVED'")
                .param("k", "PTN:" + reference + ":RECEIVED%").query(Integer.class).single()).isEqualTo(1);
        UUID id = jdbc.sql("SELECT id FROM partnership.proposal WHERE reference = :r").param("r", reference).query(UUID.class).single();

        // the status page by the link: the status in words, nothing internal
        Map<String, Object> st = ok(pub(HttpMethod.GET, PUB + "/status/" + token, null));
        assertThat(st).containsEntry("reference", reference).containsEntry("status_words", "Received").doesNotContainKey("status");

        // the Linkages office: the desk, the list, the proposal assigned and accepted
        UUID officer = holder("linkages", tag);
        String lk = TestTokens.token(officer, List.of("linkages"));
        Map<String, Object> desk = ok(it.get(lk, DESK + "/desk"));
        assertThat((List<String>) desk.get("permissions")).contains("SCREEN_PARTNERSHIP", "ASSIGN_PARTNERSHIP").doesNotContain("APPROVE_PARTNERSHIP");
        Map<String, Object> listed = ok(it.get(lk, DESK + "?q=" + tag));
        assertThat((List<Map<String, Object>>) listed.get("rows")).extracting(r -> r.get("reference")).containsExactly(reference);
        assertThat(code(it.call(lk, HttpMethod.POST, DESK + "/" + id + "/act", Map.of("action", "ACCEPT")))).isEqualTo("PTN_OWNER_REQUIRED");
        ok(it.call(lk, HttpMethod.POST, DESK + "/" + id + "/act", Map.of("action", "ASSIGN", "data", Map.of("person", officer.toString()))));
        assertThat(ok(it.call(lk, HttpMethod.POST, DESK + "/" + id + "/act", Map.of("action", "ACCEPT")))).containsEntry("status", "UNDER_REVIEW");

        // a request answered through the link; an internal note stays internal
        ok(it.call(lk, HttpMethod.POST, DESK + "/" + id + "/act", Map.of("action", "REQUEST_INFORMATION",
                "data", Map.of("question", "Send your institute's registration certificate.", "reason", "internal: check the registry"))));
        ok(it.call(lk, HttpMethod.POST, DESK + "/" + id + "/notes", Map.of("kind", "INTERNAL_NOTE", "body", "Internal: the institute is known to us.")));
        Map<String, Object> asked = ok(pub(HttpMethod.GET, PUB + "/status/" + token, null));
        assertThat((Map<String, Object>) asked.get("request")).containsEntry("question", "Send your institute's registration certificate.").doesNotContainKey("reason");
        assertThat(String.valueOf(asked.get("messages"))).doesNotContain("Internal:");
        assertThat(ok(pub(HttpMethod.POST, PUB + "/status/" + token + "/reply", Map.of("answer", "The certificate is attached.")))).containsEntry("status", "UNDER_REVIEW");
        ok(pub(HttpMethod.POST, PUB + "/status/" + token + "/attachments",
                Map.of("kind", "REQUESTED_DOCUMENT", "filename", "certificate.pdf", "dataUrl", dataUrl("application/pdf", pdf))));

        // a Dean asked for the faculty sees it; another faculty's Dean, an id that is no proposal, the Registrar's documents: refused
        ok(it.call(lk, HttpMethod.POST, DESK + "/" + id + "/reviewers", Map.of("office", "dean", "scope", fa, "role", "Faculty review")));
        String deanA = it.officer("dean", "faculty", fa);
        String deanB = it.officer("dean", "faculty", fb);
        assertThat(ok(it.get(deanA, DESK + "/" + id))).containsKey("proposal");
        ok(it.call(deanA, HttpMethod.POST, DESK + "/" + id + "/review", Map.of("recommendation", "SUPPORT", "comment", "A good fit for the faculty.")));
        assertThat(status(it.get(deanB, DESK + "/" + id))).isEqualTo(403);
        assertThat(code(it.get(lk, DESK + "/" + UUID.randomUUID()))).isEqualTo("PTN_NOT_FOUND");
        String attachment = String.valueOf(((List<Map<String, Object>>) ok(it.get(lk, DESK + "/" + id)).get("attachments")).get(0).get("id"));
        assertThat(it.getBytesWith(lk, DESK + "/" + id + "/attachments/" + attachment, Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(it.getBytesWith(ItSupport.token("registrar"), DESK + "/" + id + "/attachments/" + attachment, Map.of()).getStatusCode().value()).isEqualTo(403);
        assertThat(jdbc.sql("SELECT count(*) FROM partnership.event WHERE proposal_id = :p AND action = 'DOCUMENT_OPENED'").param("p", id).query(Integer.class).single())
                .isEqualTo(1);

        // approval: never the Linkages office's; the Vice-Chancellor's
        ok(it.call(lk, HttpMethod.POST, DESK + "/" + id + "/act", Map.of("action", "SUBMIT_FOR_APPROVAL")));
        assertThat(status(it.call(lk, HttpMethod.POST, DESK + "/" + id + "/act", Map.of("action", "APPROVE")))).isEqualTo(403);
        assertThat(ok(it.call(ItSupport.token("vc"), HttpMethod.POST, DESK + "/" + id + "/act", Map.of("action", "APPROVE")))).containsEntry("status", "APPROVED_FOR_DEVELOPMENT");
        assertThat(ok(pub(HttpMethod.GET, PUB + "/status/" + token, null))).containsEntry("status_words", "Approved for development");

        // the report and its workbook; a new link replaces the old
        Map<String, Object> report = ok(it.get(lk, DESK + "/report?q=" + tag));
        assertThat((Map<String, Object>) report.get("totals")).containsEntry("approved", 1);
        ResponseEntity<byte[]> book = it.getBytesWith(lk, DESK + "/report/workbook?q=" + tag, Map.of());
        assertThat(book.getStatusCode().value()).isEqualTo(200);
        assertThat(book.getBody()).startsWith((byte) 'P', (byte) 'K');
        ok(pub(HttpMethod.POST, PUB + "/link", Map.of("reference", reference, "email", "ada." + tag + "@example.org")));
        assertThat(code(pub(HttpMethod.GET, PUB + "/status/" + token, null))).isEqualTo("PTN_NOT_FOUND");
        assertThat(ok(pub(HttpMethod.POST, PUB + "/link", Map.of("reference", reference, "email", "someone.else@example.org")))).containsEntry("sent", true);
    }
}
