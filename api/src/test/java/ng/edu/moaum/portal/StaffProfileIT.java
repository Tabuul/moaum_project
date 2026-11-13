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
 * begin, a saved one that reads back, a photograph on record served. V749: the
 * e-mail sent with a profile is not read — the profile is saved with the address on
 * record (verified by a code at My identity), so a page opened before the address
 * changed saves the rest — and the old raw photograph upload retired.
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

    /** the e-mail the profile itself holds (hrm.staff_profile), '-' for none */
    private String profileEmail(UUID person) {
        return jdbc.sql("SELECT coalesce(email, '-') FROM hrm.staff_profile WHERE person_id = :p").param("p", person).query(String.class).single();
    }

    /** the e-mail on the person's record (iam.person), '-' for none */
    private String recordEmail(UUID person) {
        return jdbc.sql("SELECT coalesce(email, '-') FROM iam.person WHERE id = :p").param("p", person).query(String.class).single();
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

        // V749: an e-mail sent with the profile is not read (an address is verified by a code at My identity): the rest is saved, with
        // the address on record — none yet
        ResponseEntity<Map> newEmail = it.call(token, HttpMethod.PUT, "/api/v1/staff/profile", Map.of("email", "prof" + n + "@example.com", "department", "Mathematics"));
        assertThat(newEmail.getStatusCode().value()).as(String.valueOf(newEmail.getBody())).isEqualTo(200);
        assertThat(newEmail.getBody()).containsEntry("department", "Mathematics");
        assertThat(newEmail.getBody().get("email")).isNull();
        assertThat(profileEmail(person)).isEqualTo("-");
        assertThat(it.db(() -> jdbc.sql("SELECT coalesce(email, '-') FROM iam.person WHERE id = :p").param("p", person).query(String.class).single())).isEqualTo("-");
        // the address on record is the one the profile shows, and the one it saves with
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", "prof" + n + "@example.com").param("p", person).update());
        assertThat(it.get(token, "/api/v1/staff/profile").getBody().get("email")).isEqualTo("prof" + n + "@example.com");

        // save a profile — scalars and list sections
        Map<String, Object> body = Map.ofEntries(
                Map.entry("email", "PROF" + n + "@example.com"),
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
        // with no e-mail in it, the address on record stands
        assertThat(String.valueOf(partial.get("email"))).isEqualToIgnoringCase("prof" + n + "@example.com");
        assertThat(it.db(() -> jdbc.sql("SELECT email FROM iam.person WHERE id = :p").param("p", person).query(String.class).single()))
                .isEqualToIgnoringCase("prof" + n + "@example.com");
        assertThat(profileEmail(person)).isEqualTo("prof" + n + "@example.com");

        // a page opened before the address changed (an office's correction, or one verified at My identity in another tab) saves the
        // rest: the address it still holds is not read, and the profile takes the record's
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", " Prof" + n + ".New@example.com ").param("p", person).update());
        ResponseEntity<Map> stale = it.call(token, HttpMethod.PUT, "/api/v1/staff/profile",
                Map.of("email", "prof" + n + "@example.com", "department", "Pure Mathematics"));
        assertThat(stale.getStatusCode().value()).as(String.valueOf(stale.getBody())).isEqualTo(200);
        assertThat(stale.getBody()).containsEntry("department", "Pure Mathematics");
        assertThat(profileEmail(person)).isEqualTo("Prof" + n + ".New@example.com");
        // the record keeps its address (the profile's copy, written back to it as V425 does, only trims the spaces)
        assertThat(it.db(() -> jdbc.sql("SELECT email FROM iam.person WHERE id = :p").param("p", person).query(String.class).single()))
                .isEqualTo("Prof" + n + ".New@example.com");
        // an address on record the profile cannot hold (not one, to the profile's rule) is left out of it, and the rest saved
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", "prof" + n + " at example").param("p", person).update());
        ResponseEntity<Map> odd = it.call(token, HttpMethod.PUT, "/api/v1/staff/profile", Map.of("department", "Statistics"));
        assertThat(odd.getStatusCode().value()).as(String.valueOf(odd.getBody())).isEqualTo(200);
        assertThat(odd.getBody()).containsEntry("department", "Statistics");
        assertThat(profileEmail(person)).isEqualTo("-");
        assertThat(it.db(() -> jdbc.sql("SELECT email FROM iam.person WHERE id = :p").param("p", person).query(String.class).single()))
                .isEqualTo("prof" + n + " at example");

        // a profile whose address never reached the record (saved before V425 copied it back), the record holding none: the save keeps
        // the profile's address rather than losing it — whatever the page sends — and V425's copy puts it on the record
        String kept = "kept" + n + "@example.com";
        it.db(() -> jdbc.sql("UPDATE hrm.staff_profile SET email = :e WHERE person_id = :p").param("e", kept).param("p", person).update());
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = NULL WHERE id = :p").param("p", person).update());
        assertThat(profileEmail(person)).isEqualTo(kept);
        ResponseEntity<Map> keep = it.call(token, HttpMethod.PUT, "/api/v1/staff/profile", Map.of("email", "someone" + n + "@example.com", "department", "Algebra"));
        assertThat(keep.getStatusCode().value()).as(String.valueOf(keep.getBody())).isEqualTo(200);
        assertThat(keep.getBody()).containsEntry("department", "Algebra").containsEntry("email", kept);
        assertThat(profileEmail(person)).isEqualTo(kept);
        assertThat(recordEmail(person)).isEqualTo(kept);
        // one another record holds is not kept (it would be that record's): the profile's copy goes, the record stays without one, and
        // the rest is saved
        String held = "held" + n + "@example.com";
        UUID other = it.person("MOAUM/ITP/PROFH/" + n, "ITPROFILEH" + n);
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", held.toUpperCase()).param("p", other).update());
        it.db(() -> jdbc.sql("UPDATE hrm.staff_profile SET email = :e WHERE person_id = :p").param("e", held).param("p", person).update());
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = NULL WHERE id = :p").param("p", person).update());
        ResponseEntity<Map> heldSave = it.call(token, HttpMethod.PUT, "/api/v1/staff/profile", Map.of("department", "Geometry"));
        assertThat(heldSave.getStatusCode().value()).as(String.valueOf(heldSave.getBody())).isEqualTo(200);
        assertThat(heldSave.getBody()).containsEntry("department", "Geometry");
        assertThat(profileEmail(person)).isEqualTo("-");
        assertThat(recordEmail(person)).isEqualTo("-");
        assertThat(recordEmail(other)).isEqualTo(held.toUpperCase());
        // an office's correction is the profile's too: the address it clears is cleared from the profile, so a later save of the page
        // never brings it back
        it.db(() -> jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", kept).param("p", person).update());
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/staff/profile", Map.of("department", "Topology")).getStatusCode().value()).isEqualTo(200);
        assertThat(profileEmail(person)).isEqualTo(kept);
        String hr = TestTokens.token(it.person("MOAUM/ITP/PROFHR", "ITPROFILEHR"), List.of("hrm"));
        ResponseEntity<Map> cleared = it.call(hr, HttpMethod.PUT, "/api/v1/iam/persons/" + person + "/contact", Map.of("email", "", "phone", "08031234567"));
        assertThat(cleared.getStatusCode().value()).as(String.valueOf(cleared.getBody())).isEqualTo(200);
        assertThat(recordEmail(person)).isEqualTo("-");
        assertThat(profileEmail(person)).isEqualTo("-");
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/staff/profile", Map.of("email", kept, "department", "Analysis")).getStatusCode().value()).isEqualTo(200);
        assertThat(recordEmail(person)).isEqualTo("-");
        assertThat(profileEmail(person)).isEqualTo("-");

        // V749: the old raw upload is retired — the photograph is uploaded, enhanced and accepted at My identity — and changes nothing
        ResponseEntity<Map> raw = it.call(token, HttpMethod.PUT, "/api/v1/staff/profile/photo", Map.of("contentType", "image/png", "dataBase64", PNG_1PX));
        assertThat(raw.getStatusCode().value()).isEqualTo(422);
        assertThat(raw.getBody()).containsEntry("code", "STAFF_PHOTO_USE_IDENTITY");
        assertThat(it.get(token, "/api/v1/staff/profile").getBody().get("photo")).isEqualTo(false);

        // a photograph on record (set before V749) is served
        it.db(() -> jdbc.sql("INSERT INTO hrm.staff_photo (person_id, content_type, bytes, content, updated_at) VALUES (:p, 'image/png', :n, :c, now())")
                .param("p", person).param("n", (long) java.util.Base64.getDecoder().decode(PNG_1PX).length)
                .param("c", java.util.Base64.getDecoder().decode(PNG_1PX)).update());
        Map<String, Object> photo = it.get(token, "/api/v1/staff/profile/photo").getBody();
        assertThat(photo.get("contentType")).isEqualTo("image/png");
        assertThat(String.valueOf(photo.get("dataBase64"))).isEqualTo(PNG_1PX);
        assertThat(it.get(token, "/api/v1/staff/profile").getBody().get("photo")).isEqualTo(true);
    }
}
