package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.util.Base64;
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

/**
 * V622: the identity cards' signatory and the blood group. The Directorate of ICT names the Chief Security Officer and uploads the
 * signature (a PNG, kept with a JPEG for the card's PDF), which the Security Unit reads for the print and the Registrar does not;
 * the Security Unit may not set it; ICT removes it. The card desk sets a made-up student's blood group ("o positive" read as O+),
 * which the desk's view of the student then carries, and a made-up member of staff's; a value that is no blood group is refused,
 * and the Registrar may not set one. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CardSignatoryIT {

    @Value("${local.server.port}")
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

    private static String signaturePng() throws Exception {
        BufferedImage img = new BufferedImage(300, 100, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setColor(new Color(20, 30, 90));
        g.setStroke(new BasicStroke(5));
        g.drawPolyline(new int[] {20, 60, 100, 140, 180, 220, 280}, new int[] {70, 20, 80, 30, 75, 40, 60}, 7);
        g.dispose();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(img, "png", out);
        return Base64.getEncoder().encodeToString(out.toByteArray());
    }

    @Test
    void theDirectorateOfIctSignsForTheCardsAndTheDeskSetsTheBloodGroup() throws Exception {
        String ict = ItSupport.token("ict");
        String security = ItSupport.token("security");
        String registrar = ItSupport.token("registrar");
        String base = "/api/v1/credentials/identity-cards/signatory";

        // the Security Unit may not set it; the Directorate of ICT names the officer and uploads the signature
        assertThat(it.call(security, HttpMethod.PUT, base, Map.of("name", "Not the desk's")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> named = it.call(ict, HttpMethod.PUT, base, Map.of("name", "Terver A. Iorkyaa"));
        assertThat(named.getStatusCode().value()).as(String.valueOf(named.getBody())).isEqualTo(200);
        assertThat(named.getBody()).containsEntry("name", "Terver A. Iorkyaa").containsEntry("title", "Chief Security Officer");
        ResponseEntity<Map> up = it.call(ict, HttpMethod.PUT, base, Map.of("filename", "signature.png", "contentBase64", signaturePng()));
        assertThat(up.getStatusCode().value()).as(String.valueOf(up.getBody())).isEqualTo(200);
        assertThat(up.getBody()).containsEntry("has_signature", true).containsEntry("name", "Terver A. Iorkyaa");
        assertThat(it.call(ict, HttpMethod.PUT, base, Map.of("filename", "x.txt", "contentBase64", Base64.getEncoder().encodeToString("not an image".getBytes())))
                .getBody()).containsEntry("code", "CARD_SIGNATURE_FORMAT");

        // the Security Unit reads it for the print (the JPEG the PDF embeds); the Registrar does not
        assertThat(it.get(security, base).getBody()).containsEntry("has_signature", true);
        ResponseEntity<byte[]> jpeg = it.getBytes(security, base + "/signature?format=jpeg");
        assertThat(jpeg.getStatusCode().value()).isEqualTo(200);
        assertThat(jpeg.getHeaders().getContentType().toString()).isEqualTo("image/jpeg");
        assertThat(jpeg.getBody()[0] & 0xFF).isEqualTo(0xFF);
        assertThat(it.get(registrar, base).getStatusCode().value()).isEqualTo(403);

        // the blood group: a made-up student's at the desk, read back on the desk's view; a made-up member of staff's
        String tag = it.freeSurname("ZZCARDBG");
        UUID student = it.student(tag, "C00023", it.freeNumber("MOAUM/ADM/26/", 6), it.freeNumber("MOAUM/CBG/26/", 5), 100);
        String ids = "/api/v1/credentials/identity-cards";
        assertThat(it.call(registrar, HttpMethod.PUT, ids + "/students/" + student + "/blood-group", Map.of("bloodGroup", "O+")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> set = it.call(security, HttpMethod.PUT, ids + "/students/" + student + "/blood-group", Map.of("bloodGroup", "o positive"));
        assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
        assertThat(set.getBody()).containsEntry("bloodGroup", "O+");
        assertThat((Map<String, Object>) it.get(security, ids + "/students/" + student).getBody().get("student")).containsEntry("blood_group", "O+");
        assertThat(it.call(security, HttpMethod.PUT, ids + "/students/" + student + "/blood-group", Map.of("bloodGroup", "Z")).getBody())
                .containsEntry("code", "CARD_BLOOD_GROUP");
        UUID person = it.person("ZZ-CBG-" + tag.substring(8), tag);
        ResponseEntity<Map> staff = it.call(security, HttpMethod.PUT, ids + "/staff/" + person + "/blood-group", Map.of("bloodGroup", "B-"));
        assertThat(staff.getStatusCode().value()).as(String.valueOf(staff.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT credentials.staff_blood_group(:p)").param("p", person).query(String.class).single()).isEqualTo("B-");

        // ICT removes the signature: the cards print the line alone
        ResponseEntity<Map> removed = it.call(ict, HttpMethod.DELETE, base + "/signature", null);
        assertThat(removed.getStatusCode().value()).isEqualTo(200);
        assertThat(removed.getBody()).containsEntry("has_signature", false);
        assertThat(it.getBytes(security, base + "/signature?format=jpeg").getStatusCode().value()).isEqualTo(404);
    }
}
