package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.imageio.ImageIO;

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

import ng.edu.moaum.portal.platform.Branding;
import ng.edu.moaum.portal.shared.FileObjects;

/**
 * The institution profile (V320): read by anyone, changed by the keepers alone; the name the services use follows it;
 * a blank name and a malformed e-mail are refused; the logo is kept in the file store with a JPEG derivative and served,
 * or refused with a reason when there is no store; a document the portal issues is on the record. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class InstitutionIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    FileObjects files;
    @Autowired
    Branding branding;

    ItSupport it;
    String ict = ItSupport.token("ict");
    String lecturer = ItSupport.token("lecturer");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    private Map<String, Object> body(ResponseEntity<Map> r) {
        return (Map<String, Object>) r.getBody();
    }

    @Test
    void theProfileIsReadByAnyoneChangedByTheKeepersAndFollowedByTheServices() {
        ResponseEntity<Map> before = it.anon(HttpMethod.GET, "/api/v1/public/institution", null);
        assertThat(before.getStatusCode().value()).isEqualTo(200);
        assertThat(String.valueOf(body(before).get("name"))).isNotBlank();
        String originalName = String.valueOf(body(before).get("name"));
        String originalShort = String.valueOf(body(before).get("shortName"));

        Map<String, Object> change = Map.of("name", originalName, "shortName", originalShort, "motto", "Knowledge, Service and Integrity",
                "city", "Makurdi", "state", "Benue State", "country", "Nigeria", "phone", "+234 800 000 0000", "email", "info@example.edu.ng",
                "website", "https://www.example.edu.ng", "dateFormat", "SHORT");
        assertThat(it.call(lecturer, HttpMethod.PUT, "/api/v1/platform/institution", change).getStatusCode().value()).isEqualTo(403);

        ResponseEntity<Map> saved = it.call(ict, HttpMethod.PUT, "/api/v1/platform/institution", change);
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat(body(saved).get("motto")).isEqualTo("Knowledge, Service and Integrity");
        assertThat(body(saved).get("dateFormat")).isEqualTo("SHORT");
        assertThat(body(saved).get("logoUrl")).isNull();
        assertThat(it.anon(HttpMethod.GET, "/api/v1/public/institution", null).getBody().get("motto")).isEqualTo("Knowledge, Service and Integrity");
        assertThat(String.valueOf(branding.profile().get("name"))).isEqualTo(originalName);

        // a blank name and a malformed e-mail are refused; the change is audited on the row
        Map<String, Object> blank = new java.util.HashMap<>(change);
        blank.put("name", " ");
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/platform/institution", blank).getStatusCode().value()).isEqualTo(400);
        Map<String, Object> badMail = new java.util.HashMap<>(change);
        badMail.put("email", "not an address");
        ResponseEntity<Map> refused = it.call(ict, HttpMethod.PUT, "/api/v1/platform/institution", badMail);
        assertThat(refused.getStatusCode().value()).as(String.valueOf(refused.getBody())).isEqualTo(422);
        assertThat(String.valueOf(refused.getBody())).contains("INSTITUTION_EMAIL_INVALID");
        long audited = jdbc.sql("SELECT count(*) FROM audit.entries WHERE subject_type = 'platform.institution_profile' AND action = 'UPDATE'").query(Long.class).single();
        assertThat(audited).isGreaterThanOrEqualTo(1L);

        // the name the services use is the profile's: change it, and the branding follows
        Map<String, Object> renamed = new java.util.HashMap<>(change);
        renamed.put("name", "Example University, Makurdi");
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/platform/institution", renamed).getStatusCode().value()).isEqualTo(200);
        // the bean this context's service holds is invalidated by the change (a test JVM may hold several contexts' beans)
        assertThat(String.valueOf(branding.profile().get("name"))).isEqualTo("Example University, Makurdi");
        // and back, so the database is as it was
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/platform/institution", Map.of("name", originalName, "shortName", originalShort, "city", "Makurdi", "state", "Benue State", "country", "Nigeria")).getStatusCode().value()).isEqualTo(200);
        assertThat(String.valueOf(branding.profile().get("name"))).isEqualTo(originalName);
    }

    @Test
    void theLogoIsKeptInTheFileStoreWithAJpegForThePdfEngineOrRefusedWithAReason() throws Exception {
        BufferedImage img = new BufferedImage(96, 64, BufferedImage.TYPE_INT_ARGB);
        var g = img.createGraphics();
        g.setColor(new Color(10, 80, 50));
        g.fillOval(8, 8, 48, 48);
        g.dispose();
        ByteArrayOutputStream png = new ByteArrayOutputStream();
        ImageIO.write(img, "png", png);
        Map<String, Object> upload = Map.of("filename", "logo.png", "contentType", "image/png", "contentBase64", Base64.getEncoder().encodeToString(png.toByteArray()));

        assertThat(it.call(lecturer, HttpMethod.PUT, "/api/v1/platform/institution/logo", upload).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> r = it.call(ict, HttpMethod.PUT, "/api/v1/platform/institution/logo", upload);
        if (!files.enabled()) {
            assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
            assertThat(String.valueOf(r.getBody())).contains("FILES_NOT_CONFIGURED");
            assertThat(it.anon(HttpMethod.GET, "/api/v1/public/institution/logo", null).getStatusCode().value()).isEqualTo(404);
            return;
        }
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        assertThat(body(r).get("hasLogo")).isEqualTo(true);
        assertThat(String.valueOf(body(r).get("logoUrl"))).startsWith("/api/v1/public/institution/logo?v=");
        assertThat(String.valueOf(body(r).get("logoJpegUrl"))).contains("format=jpeg");
        ResponseEntity<byte[]> served = it.getBytes(lecturer, "/api/v1/public/institution/logo");
        assertThat(served.getStatusCode().value()).isEqualTo(200);
        assertThat(served.getHeaders().getContentType().toString()).isEqualTo("image/png");
        ResponseEntity<byte[]> jpeg = it.getBytes(lecturer, "/api/v1/public/institution/logo?format=jpeg");
        assertThat(jpeg.getStatusCode().value()).isEqualTo(200);
        assertThat(jpeg.getHeaders().getContentType().toString()).isEqualTo("image/jpeg");
        assertThat(jpeg.getBody()[0] & 0xFF).isEqualTo(0xFF);
        // not an image: refused
        assertThat(it.call(ict, HttpMethod.PUT, "/api/v1/platform/institution/logo", Map.of("filename", "x.png", "contentBase64", Base64.getEncoder().encodeToString("hello".getBytes()))).getStatusCode().value()).isEqualTo(422);
        // back to the crest
        ResponseEntity<Map> cleared = it.call(ict, HttpMethod.DELETE, "/api/v1/platform/institution/logo", null);
        assertThat(cleared.getStatusCode().value()).isEqualTo(200);
        assertThat(body(cleared).get("hasLogo")).isEqualTo(false);
    }

    @Test
    void aDocumentThePortalIssuesIsOnTheRecordInTheActorsName() {
        UUID student = UUID.randomUUID();
        String token = TestTokens.token(student, List.of("student"));
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, "/api/v1/documents/issued",
                Map.of("kind", "receipt_downloaded", "reference", "RCT/2026/000123", "subjectKind", "payment", "subjectId", "RCT/2026/000123", "detail", Map.of("format", "pdf")));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        Map<String, Object> row = jdbc.sql("SELECT kind, actor_id::text AS actor, actor_office, reference FROM platform.document_issue WHERE id = :id")
                .param("id", UUID.fromString(String.valueOf(r.getBody().get("id")))).query().singleRow();
        assertThat(row.get("kind")).isEqualTo("RECEIPT_DOWNLOADED");
        assertThat(row.get("actor")).isEqualTo(student.toString());
        assertThat(row.get("actor_office")).isEqualTo("student");
        assertThat(it.anon(HttpMethod.POST, "/api/v1/documents/issued", Map.of("kind", "X_Y")).getStatusCode().value()).isIn(401, 403);
    }
}
