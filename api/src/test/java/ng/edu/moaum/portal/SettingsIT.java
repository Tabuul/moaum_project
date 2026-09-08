package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClient;

/**
 * The Committee's guidelines become settings, session by session, through
 * the API: a draft is created, its quota distributed, its cut-offs set and
 * its rules stated; the database refuses to put it in force until nothing
 * is outstanding, then does; and once in force it is not edited.
 *
 * <p>Needs a database the migrations have been applied to: set DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class SettingsIT {

    /** Sessions of the test's own. Re-runs on the same database find them in force and skip the setup. */
    static final String SESSION = "2097/2098";
    static final String NEXT = "2096/2097";

    @Value("${local.server.port}")
    int port;

    RestClient client;
    String academic = TestTokens.token(UUID.randomUUID(), List.of("academic"));

    @BeforeEach
    void client() {
        client = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { })
                .build();
    }

    ResponseEntity<Map> call(HttpMethod method, String path, Object body) {
        RestClient.RequestBodySpec spec = client.method(method).uri(path)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + academic)
                .contentType(MediaType.APPLICATION_JSON);
        return (body == null ? spec : spec.body(body)).retrieve().toEntity(Map.class);
    }

    ResponseEntity<Map> get(String path) {
        return client.get().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + academic).retrieve().toEntity(Map.class);
    }

    static Map<String, Object> settings(int quota) {
        return Map.ofEntries(Map.entry("nucQuota", quota), Map.entry("weightUtme", 70), Map.entry("weightPutme", 30),
                Map.entry("ratioUtme", 80), Map.entry("ratioDe", 20), Map.entry("ratioScience", 60), Map.entry("ratioArts", 40),
                Map.entry("elgCapPct", 50), Map.entry("deptSharePct", 80), Map.entry("indexPrelimPlaces", 6),
                Map.entry("indexPerZone", 2), Map.entry("mpfOnly", true), Map.entry("screeningRequired", true));
    }

    @Test
    void fromADraftToInForceAndNotEditedAfter() {
        ResponseEntity<Map> existing = get("/api/v1/admissions/sessions/2097/2098/policy");
        if (existing.getStatusCode().value() == 200 && Boolean.TRUE.equals(existing.getBody().get("inForce"))) {
            return; // a previous run on this database already took the whole journey
        }

        // 1 · a draft, with a weighting that does not add up, is refused with its reason
        ResponseEntity<Map> bad = call(HttpMethod.PUT, "/api/v1/admissions/sessions/2097/2098/policy",
                Map.ofEntries(Map.entry("nucQuota", 1200), Map.entry("weightUtme", 70), Map.entry("weightPutme", 40),
                        Map.entry("ratioUtme", 80), Map.entry("ratioDe", 20), Map.entry("ratioScience", 60), Map.entry("ratioArts", 40),
                        Map.entry("elgCapPct", 50), Map.entry("deptSharePct", 80), Map.entry("indexPrelimPlaces", 6),
                        Map.entry("indexPerZone", 2), Map.entry("mpfOnly", true), Map.entry("screeningRequired", true)));
        assertThat(bad.getStatusCode().value()).isEqualTo(422);
        assertThat(bad.getBody().get("code")).isEqualTo("ADM_WEIGHTS");

        ResponseEntity<Map> draft = call(HttpMethod.PUT, "/api/v1/admissions/sessions/2097/2098/policy", settings(1200));
        assertThat(draft.getStatusCode().value()).as(String.valueOf(draft.getBody())).isEqualTo(200);
        assertThat(draft.getBody().get("state")).isEqualTo("DRAFT");
        assertThat((List<?>) draft.getBody().get("findings")).isNotEmpty();

        // 2 · the four criteria
        ResponseEntity<Map> crit = call(HttpMethod.PUT, "/api/v1/admissions/sessions/2097/2098/policy/criteria",
                Map.of("NATIONAL_MERIT", 10, "STATE_MERIT", 35, "ELG", 30, "LOCALITY", 25));
        assertThat(crit.getStatusCode().value()).isEqualTo(200);
        assertThat((List<?>) crit.getBody().get("criteria")).hasSize(4);

        // 3 · every faculty: 100 places each and a cut-off of 150
        List<?> faculties = (List<?>) get("/api/v1/admissions/programmes").getBody(); // any authenticated read to warm up
        assertThat(faculties).isNotNull();
        for (String f : List.of("AC", "AR", "BAMS", "CM", "ED", "ES", "LW", "MS", "PS", "SC", "SS", "TI")) {
            ResponseEntity<Map> r = call(HttpMethod.PUT, "/api/v1/admissions/sessions/2097/2098/policy/faculties/" + f,
                    Map.of("quota", 100, "cutoff", 150));
            assertThat(r.getStatusCode().value()).as(f + ": " + r.getBody()).isEqualTo(200);
        }

        // 4 · a rule for every programme; MBBS with a cut-off of its own
        ResponseEntity<Map> after = get("/api/v1/admissions/sessions/2097/2098/policy");
        for (Object p : (List<?>) after.getBody().get("programmes")) {
            String code = String.valueOf(((Map<?, ?>) p).get("code"));
            Map<String, Object> rule = "C00061".equals(code)
                    ? Map.of("cutoff", 200, "olevelText", "Five credits (test)", "utmeText", "Physics, Chemistry and Biology (test)", "deText", "A-Level (test)")
                    : Map.of("olevelText", "Five credits (test)", "utmeText", "Any three (test)", "deText", "A-Level (test)");
            ResponseEntity<Map> r = call(HttpMethod.PUT, "/api/v1/admissions/sessions/2097/2098/policy/programmes/" + code, rule);
            assertThat(r.getStatusCode().value()).as(code + ": " + r.getBody()).isEqualTo(200);
        }

        // 5 · nothing outstanding; without a minute it is still refused
        ResponseEntity<Map> complete = get("/api/v1/admissions/sessions/2097/2098/policy");
        assertThat((List<?>) complete.getBody().get("findings")).as(String.valueOf(complete.getBody().get("findings"))).isEmpty();
        ResponseEntity<Map> noMinute = call(HttpMethod.POST, "/api/v1/admissions/sessions/2097/2098/policy/put-in-force",
                Map.of("instrument", " "));
        assertThat(noMinute.getStatusCode().value()).isEqualTo(400);

        // 6 · in force under the minute
        ResponseEntity<Map> inForce = call(HttpMethod.POST, "/api/v1/admissions/sessions/2097/2098/policy/put-in-force",
                Map.of("instrument", "CAC minute SettingsIT/1"));
        assertThat(inForce.getStatusCode().value()).as(String.valueOf(inForce.getBody())).isEqualTo(200);
        assertThat(inForce.getBody().get("inForce")).isEqualTo(true);
        assertThat(inForce.getBody().get("instrument")).isEqualTo("CAC minute SettingsIT/1");
        List<?> own = (List<?>) inForce.getBody().get("programmeCutoffs");
        assertThat(own).hasSize(1);
        assertThat(((Map<?, ?>) own.get(0)).get("cutoff")).isEqualTo(200);

        // 7 · and not edited after
        ResponseEntity<Map> edit = call(HttpMethod.PUT, "/api/v1/admissions/sessions/2097/2098/policy/faculties/SC",
                Map.of("quota", 100, "cutoff", 170));
        assertThat(edit.getStatusCode().value()).isEqualTo(422);
        assertThat(edit.getBody().get("code")).isEqualTo("ADM_SETTINGS_IN_FORCE");

        // 8 · the next session begins from this one, as a draft carrying everything it states
        ResponseEntity<Map> nextExisting = get("/api/v1/admissions/sessions/2096/2097/policy");
        if (nextExisting.getStatusCode().value() == 404) {
            ResponseEntity<Map> copy = call(HttpMethod.POST, "/api/v1/admissions/sessions/2096/2097/policy/start-from/2097/2098", null);
            assertThat(copy.getStatusCode().value()).as(String.valueOf(copy.getBody())).isEqualTo(200);
            assertThat(copy.getBody().get("state")).isEqualTo("DRAFT");
            assertThat((List<?>) copy.getBody().get("facultyCutoffs")).hasSize(12);
            assertThat((List<?>) copy.getBody().get("findings")).isEmpty();
        }

        // 9 · the register of sessions lists both
        ResponseEntity<List> all = client.get().uri("/api/v1/admissions/policies")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + academic).retrieve().toEntity(List.class);
        assertThat(all.getBody().stream().map(s -> ((Map<?, ?>) s).get("session"))).contains(SESSION, NEXT);
    }

    @Test
    void aDeanReadsTheSettingsAndMayNotWriteThem() {
        String dean = TestTokens.token(UUID.randomUUID(), List.of("dean"));
        ResponseEntity<Map> read = client.get().uri("/api/v1/admissions/sessions/2025/2026/policy")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + dean).retrieve().toEntity(Map.class);
        assertThat(read.getStatusCode().value()).isEqualTo(200);
        assertThat(read.getBody().get("state")).isIn("DRAFT", "IN_FORCE");
        ResponseEntity<Map> write = client.put().uri("/api/v1/admissions/sessions/2025/2026/policy/faculties/SC")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + dean)
                .contentType(MediaType.APPLICATION_JSON).body(Map.of("quota", 1, "cutoff", 150))
                .retrieve().toEntity(Map.class);
        assertThat(write.getStatusCode().value()).isEqualTo(403);
    }
}
