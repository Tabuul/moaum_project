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
 * The staff profile (V107): a member of staff reads and writes their own, and no
 * other. The record is keyed on the token's subject, so a token is minted for a
 * person and the endpoints are exercised as that person — an empty profile to
 * begin, a saved one that reads back, a photograph that is stored and served,
 * and a non-image that is refused.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class StaffProfileIT {

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

    // a valid 1x1 PNG, base64 — the endpoint checks type and size, not the pixels
    static final String PNG_1PX =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

    @Test
    @SuppressWarnings("unchecked")
    void aMemberOfStaffKeepsTheirOwnProfileAndPhotograph() {
        int n = new Random().nextInt(9000) + 1000;
        UUID person = it.person("MOAUM/ITP/PROF/" + n, "ITPROFILE" + n);
        String token = TestTokens.token(person, List.of("lecturer"));

        // to begin: an honest empty profile, not a 404
        Map<String, Object> before = it.get(token, "/api/v1/staff/profile").getBody();
        assertThat(((Number) before.get("phdGraduated")).intValue()).isEqualTo(0);
        assertThat((List<?>) before.get("publications")).isEmpty();
        assertThat(before.get("photo")).isEqualTo(false);

        // save a profile — scalars and list sections
        Map<String, Object> body = Map.ofEntries(
                Map.entry("email", "prof@example.com"),
                Map.entry("department", "Mathematics"),
                Map.entry("faculty", "Science"),
                Map.entry("responsibility", "Examinations Officer"),
                Map.entry("scholarUrl", "https://scholar.google.com/citations?user=IT"),
                Map.entry("researchInterests", "Numerical analysis"),
                Map.entry("mastersGraduated", 5),
                Map.entry("phdGraduated", 2),
                Map.entry("publications", List.of("A first paper, 2023", "A second paper, 2024")),
                Map.entry("grants", List.of("TETFund IBR 2024")));
        ResponseEntity<Map> saved = it.call(token, HttpMethod.PUT, "/api/v1/staff/profile", body);
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        Map<String, Object> after = saved.getBody();
        assertThat(after.get("department")).isEqualTo("Mathematics");
        assertThat(((Number) after.get("phdGraduated")).intValue()).isEqualTo(2);
        assertThat((List<String>) after.get("publications")).containsExactly("A first paper, 2023", "A second paper, 2024");

        // it reads back on a fresh request
        Map<String, Object> reread = it.get(token, "/api/v1/staff/profile").getBody();
        assertThat(reread.get("responsibility")).isEqualTo("Examinations Officer");
        assertThat((List<?>) reread.get("grants")).hasSize(1);

        // a partial save replaces the record whole (a missing list becomes empty)
        Map<String, Object> partial = it.call(token, HttpMethod.PUT, "/api/v1/staff/profile",
                Map.of("department", "Applied Mathematics", "phdGraduated", 3)).getBody();
        assertThat(partial.get("department")).isEqualTo("Applied Mathematics");
        assertThat(((Number) partial.get("phdGraduated")).intValue()).isEqualTo(3);
        assertThat((List<?>) partial.get("publications")).isEmpty();

        // a photograph is stored and served
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/staff/profile/photo",
                Map.of("contentType", "image/png", "dataBase64", PNG_1PX)).getStatusCode().value()).isEqualTo(200);
        Map<String, Object> photo = it.get(token, "/api/v1/staff/profile/photo").getBody();
        assertThat(photo.get("contentType")).isEqualTo("image/png");
        assertThat(String.valueOf(photo.get("dataBase64"))).isNotEmpty();
        assertThat(it.get(token, "/api/v1/staff/profile").getBody().get("photo")).isEqualTo(true);

        // a non-image is refused
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/staff/profile/photo",
                Map.of("contentType", "application/pdf", "dataBase64", PNG_1PX)).getStatusCode().value()).isEqualTo(422);
    }
}
