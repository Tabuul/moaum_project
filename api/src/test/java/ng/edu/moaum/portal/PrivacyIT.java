package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V441: the Privacy Policy is drafted and published by ICT (never the Bursary) once every review point is confirmed; the
 * public reads it with the University's names and the privacy contact filled in; a student is asked to accept the published
 * version once, by their own act, never again for the same version; a privacy request filed by the student lands on the
 * governance request log under its reference; a new draft is withdrawn without touching the published version. Runs again on
 * the same database. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class PrivacyIT {

    @LocalServerPort
    int port;

    @Autowired
    JdbcClient jdbc;

    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().is2xxSuccessful()).as(String.valueOf(r.getBody())).isTrue();
        return r.getBody();
    }

    private static void refused(ResponseEntity<Map> r, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo(code);
    }

    @Test
    void thePolicyIsPublishedOnceReviewedAcceptedOncePerVersionAndRequestsReachTheLog() {
        int n = it.freeDraw(1000, 9000, k -> List.of("MOAUM/ADM/88/7" + k + "0", "MOAUM/PRV/88/" + k, "ITPRIVACY" + k));
        String ict = ItSupport.token("ict");
        String bursar = ItSupport.token("bursar");
        String registrar = ItSupport.token("registrar");
        String admin = "/api/v1/privacy/admin/documents";

        // the administrator's list: the draft open (the seeded version 1, or a new one on a database that published it before)
        List<Map<String, Object>> rows = (List<Map<String, Object>>) ok(it.get(ict, admin)).get("rows");
        int publishedBefore = rows.stream().filter(r -> "PRIVACY_POLICY".equals(r.get("kind")) && "PUBLISHED".equals(r.get("status")))
                .mapToInt(r -> ((Number) r.get("version")).intValue()).max().orElse(0);
        String id = rows.stream().filter(r -> "PRIVACY_POLICY".equals(r.get("kind")) && "DRAFT".equals(r.get("status"))).map(r -> String.valueOf(r.get("id"))).findFirst()
                .orElseGet(() -> String.valueOf(ok(it.call(ict, HttpMethod.POST, admin + "/draft", Map.of("kind", "PRIVACY_POLICY"))).get("id")));
        assertThat(it.call(bursar, HttpMethod.POST, admin + "/draft", Map.of("kind", "PRIVACY_POLICY")).getStatusCode().value()).isEqualTo(403);
        refused(it.call(ict, HttpMethod.POST, admin + "/draft", Map.of("kind", "PRIVACY_POLICY")), "LEGAL_DRAFT_EXISTS");

        // the draft: its sections, its review points unconfirmed — not published until they are; a bad edit refused, a good one kept
        Map<String, Object> doc = ok(it.get(ict, admin + "/" + id));
        List<Map<String, Object>> sections = (List<Map<String, Object>>) doc.get("sections");
        List<Map<String, Object>> points = (List<Map<String, Object>>) doc.get("review_points");
        assertThat(sections.size()).isGreaterThanOrEqualTo(1);
        assertThat(points.size()).isEqualTo(8);
        refused(it.call(ict, HttpMethod.POST, admin + "/" + id + "/publish", Map.of()), "LEGAL_REVIEW_PENDING");
        refused(it.call(ict, HttpMethod.PUT, admin + "/" + id, Map.of("title", "Privacy Policy", "sections", List.of(Map.of("heading", "x")))), "LEGAL_SECTIONS");
        Map<String, Object> edit = Map.of("title", "Privacy Policy", "summary", String.valueOf(doc.get("summary") == null ? "" : doc.get("summary")),
                "sections", sections, "requiresAcceptance", true);
        assertThat(((List<?>) ok(it.call(ict, HttpMethod.PUT, admin + "/" + id, edit)).get("sections")).size()).isEqualTo(sections.size());

        // the privacy contact: not the Bursary's to set; the Registrar's
        Map<String, Object> contact = Map.of("name", "Dr Invented DPO " + n, "title", "Data Protection Officer", "office", "Registry",
                "email", "dpo" + n + "@example.edu", "phone", "0800", "address", "Makurdi", "requestDays", 30);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/privacy/admin/contact", contact).getStatusCode().value()).isEqualTo(403);
        assertThat(ok(it.call(registrar, HttpMethod.PUT, "/api/v1/privacy/admin/contact", contact)).get("dpo_email")).isEqualTo("dpo" + n + "@example.edu");

        // every point confirmed, published with today's date; the preview and the public page read the same, tokens filled
        for (Map<String, Object> p : points) {
            ok(it.call(ict, HttpMethod.POST, admin + "/" + id + "/review", Map.of("key", String.valueOf(p.get("key")), "confirmed", true)));
        }
        Map<String, Object> published = ok(it.call(ict, HttpMethod.POST, admin + "/" + id + "/publish", Map.of("effectiveOn", LocalDate.now().toString())));
        assertThat(published.get("status")).isEqualTo("PUBLISHED");
        int version = ((Number) published.get("version")).intValue();
        assertThat(version).isGreaterThan(publishedBefore);
        Map<String, Object> page = ok(it.anon(HttpMethod.GET, "/api/v1/public/legal/privacy-policy", null));
        assertThat(((Number) page.get("version")).intValue()).isEqualTo(version);
        assertThat(((List<?>) page.get("sections")).size()).isEqualTo(sections.size());
        String text = String.valueOf(page);
        assertThat(text).doesNotContain("{{").contains("dpo" + n + "@example.edu");
        assertThat(String.valueOf(ok(it.anon(HttpMethod.GET, "/api/v1/public/legal", null)).get("documents"))).contains("privacy-policy");
        assertThat(it.anon(HttpMethod.GET, "/api/v1/public/legal/terms-of-use", null).getStatusCode().value()).isEqualTo(404);

        // a student is asked once: the prompt on iam/me, the acceptance recorded by their own act, then never again for this version
        UUID student = it.student("ITPRIVACY" + n, "C00061", "MOAUM/ADM/88/7" + n + "0", "MOAUM/PRV/88/" + n, 100);
        String st = TestTokens.token(student, List.of("student"));
        assertThat(((List<?>) ok(it.get(st, "/api/v1/privacy/acceptance")).get("needed")).size()).isEqualTo(1);
        assertThat(ok(it.get(st, "/api/v1/iam/me")).get("privacyPrompt")).isNotNull();
        assertThat(ok(it.call(st, HttpMethod.POST, "/api/v1/privacy/acceptance", Map.of("documentId", id))).get("recorded")).isEqualTo(true);
        assertThat(((List<?>) ok(it.get(st, "/api/v1/privacy/acceptance")).get("needed"))).isEmpty();
        assertThat(ok(it.get(st, "/api/v1/iam/me")).get("privacyPrompt")).isNull();
        assertThat(ok(it.call(st, HttpMethod.POST, "/api/v1/privacy/acceptance", Map.of("documentId", id))).get("recorded")).isEqualTo(false);
        List<Map<String, Object>> after = (List<Map<String, Object>>) ok(it.get(ict, admin)).get("rows");
        List<Map<String, Object>> summary = after.stream().filter(r -> id.equals(String.valueOf(r.get("id")))).findFirst()
                .map(r -> (List<Map<String, Object>>) r.get("acceptance")).orElse(List.of());
        assertThat(summary.stream().filter(s -> "STUDENT".equals(s.get("subject_kind"))).mapToLong(s -> ((Number) s.get("accepted")).longValue()).sum()).isGreaterThanOrEqualTo(1);

        // a privacy request by the student: a reference, listed as theirs, on the governance log as filed through the portal
        Map<String, Object> filed = ok(it.call(st, HttpMethod.POST, "/api/v1/privacy/requests",
                Map.of("kind", "COMPLAINT", "contact", "me" + n + "@example.com", "detail", "The record shows a wrong state of origin for me.")));
        String reference = String.valueOf(filed.get("reference"));
        assertThat(reference).startsWith("DSR-");
        refused(it.call(st, HttpMethod.POST, "/api/v1/privacy/requests", Map.of("kind", "ACCESS", "detail", "short")), "DSR_DETAIL");
        assertThat(((List<?>) ok(it.get(st, "/api/v1/privacy/requests")).get("rows")).size()).isGreaterThanOrEqualTo(1);
        List<Map<String, Object>> log = (List<Map<String, Object>>) ok(it.get(ict, "/api/v1/governance/dsr")).get("rows");
        Map<String, Object> logged = log.stream().filter(d -> reference.equals(d.get("reference"))).findFirst().orElseThrow();
        assertThat(logged.get("filed_via")).isEqualTo("PORTAL");
        assertThat(logged.get("kind")).isEqualTo("COMPLAINT");
        assertThat(String.valueOf(logged.get("requester"))).contains("ITPRIVACY" + n);

        // a new draft is the next version; withdrawn, it is kept as archived and the published version stands
        Map<String, Object> draft = ok(it.call(ict, HttpMethod.POST, admin + "/draft", Map.of("kind", "PRIVACY_POLICY")));
        Map<String, Object> next = ok(it.get(ict, admin + "/" + draft.get("id")));
        assertThat(((Number) next.get("version")).intValue()).isEqualTo(version + 1);
        assertThat(((Number) next.get("review_pending")).intValue()).isEqualTo(8);
        assertThat(ok(it.call(ict, HttpMethod.POST, admin + "/" + draft.get("id") + "/withdraw", Map.of())).get("status")).isEqualTo("ARCHIVED");
        assertThat(((Number) ok(it.anon(HttpMethod.GET, "/api/v1/public/legal/privacy-policy", null)).get("version")).intValue()).isEqualTo(version);
        assertThat(((List<?>) ok(it.get(ict, "/api/v1/privacy/admin/history")).get("rows")).size()).isGreaterThanOrEqualTo(1);
    }
}
