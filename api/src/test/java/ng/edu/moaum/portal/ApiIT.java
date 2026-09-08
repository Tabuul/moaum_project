package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.security.SecureRandom;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClient;

/**
 * The request path end to end, against a real database: token in, office
 * chosen, rule refused with a remedy, row written with an audit trail.
 *
 * <p>Needs a database the migrations have been applied to: set DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class ApiIT {

    static final String SESSION = "2026/2027";

    @Value("${local.server.port}")
    int port;

    RestClient client;
    UUID registrar = UUID.randomUUID();
    String registrarToken = TestTokens.token(registrar, List.of("registrar", "academic"));

    @BeforeEach
    void client() {
        client = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { })
                .build();
    }

    @Test
    void statusIsPublicAndReportsTheDatabase() {
        ResponseEntity<Map> r = client.get().uri("/api/v1/platform/status").retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).isEqualTo(200);
        Map<?, ?> db = (Map<?, ?>) r.getBody().get("database");
        assertThat(db.get("reachable")).isEqualTo(true);
        assertThat(((Number) db.get("migrationsApplied")).intValue()).isGreaterThanOrEqualTo(10);
        assertThat(r.getHeaders().getFirst("X-Correlation-Id")).isNotBlank();
    }

    @Test
    void everythingElseNeedsAToken() {
        ResponseEntity<String> r = client.get().uri("/api/v1/iam/me").retrieve().toEntity(String.class);
        assertThat(r.getStatusCode().value()).isEqualTo(401);
    }

    @Test
    void meSaysWhoIsActingAsWhat() {
        ResponseEntity<Map> r = client.get().uri("/api/v1/iam/me")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).isEqualTo(200);
        assertThat(r.getBody().get("actorId")).isEqualTo(registrar.toString());
        assertThat(r.getBody().get("activeOffice")).isEqualTo("academic");
        assertThat(r.getBody().get("offices")).isEqualTo(List.of("registrar", "academic"));
        /* the menu counts: a map of item id to what waits there, every value a count or the "!" mark */
        assertThat(r.getBody().get("waiting")).isInstanceOf(Map.class);
        Map<?, ?> waiting = (Map<?, ?>) r.getBody().get("waiting");
        waiting.forEach((item, value) -> {
            assertThat(String.valueOf(item)).startsWith("t/");
            assertThat(String.valueOf(value)).matches("[1-9][0-9]*|!");
        });
        /* the registrar exists without an account, so at least one person waits on Users & roles */
        assertThat(waiting.keySet().stream().map(String::valueOf)).contains("t/users");
    }

    @Test
    void anOfficeTheTokenDoesNotCarryIsRefusedBeforeAnyServiceRuns() {
        ResponseEntity<Map> r = client.get().uri("/api/v1/iam/me")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "dean")
                .retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).isEqualTo(403);
        assertThat(String.valueOf(r.getBody().get("detail"))).contains("dean");
    }

    @Test
    void aPersonIsCreatedThenGrantedAnOfficeUnderAnInstrument() {
        ResponseEntity<Map> created = client.post().uri("/api/v1/iam/persons")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("surname", "Ochefu", "givenNames", "Daniel Ejembi"))
                .retrieve().toEntity(Map.class);
        assertThat(created.getStatusCode().value()).isEqualTo(201);
        String id = String.valueOf(created.getBody().get("id"));
        assertThat(created.getHeaders().getLocation().toString()).endsWith(id);

        ResponseEntity<Map> refused = client.post().uri("/api/v1/iam/persons/" + id + "/office-assignments")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("officeCode", "academic", "scopeKind", "institution", "instrument", " "))
                .retrieve().toEntity(Map.class);
        assertThat(refused.getStatusCode().value()).isEqualTo(400);

        ResponseEntity<Map> granted = client.post().uri("/api/v1/iam/persons/" + id + "/office-assignments")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("officeCode", "academic", "scopeKind", "institution",
                        "instrument", "Letter REG/ADM/2026/014 of 1 September 2026"))
                .retrieve().toEntity(Map.class);
        assertThat(granted.getStatusCode().value()).isEqualTo(201);
        assertThat(granted.getBody().get("grantedBy")).isEqualTo(registrar.toString());

        ResponseEntity<Map> read = client.get().uri("/api/v1/iam/persons/" + id)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .retrieve().toEntity(Map.class);
        assertThat(read.getStatusCode().value()).isEqualTo(200);
        assertThat((List<?>) read.getBody().get("officeAssignments")).hasSize(1);
    }

    @Test
    void anOfficeWithoutTheRightIsRefusedByMethodSecurity() {
        String lecturer = TestTokens.token(UUID.randomUUID(), List.of("lecturer"));
        ResponseEntity<Map> r = client.post().uri("/api/v1/iam/persons")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + lecturer)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("surname", "X", "givenNames", "Y"))
                .retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void aUtmeListIsRefusedWhileNoSettingsAreInForce() {
        ResponseEntity<Map> r = client.post().uri("/api/v1/admissions/caps-batches")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .contentType(MediaType.APPLICATION_JSON)
                .body(batch("UTME", List.of(row("UTME", 312, "C00061"))))
                .retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo("ADM_SETTINGS_NOT_IN_FORCE");
        assertThat(String.valueOf(r.getBody().get("detail"))).contains(SESSION);
    }

    @Test
    void aCapsListLoadsWholeAndReconciles() {
        Map<String, Object> batch = batch("DIRECT_ENTRY", List.of(
                row("DIRECT_ENTRY", null, "C00061"), row("DIRECT_ENTRY", null, "C00061")));
        ResponseEntity<Map> loaded = client.post().uri("/api/v1/admissions/caps-batches")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .contentType(MediaType.APPLICATION_JSON)
                .body(batch)
                .retrieve().toEntity(Map.class);
        assertThat(loaded.getStatusCode().value()).as(String.valueOf(loaded.getBody())).isEqualTo(201);
        assertThat(loaded.getBody().get("rowsLoaded")).isEqualTo(2);
        Map<?, ?> created = (Map<?, ?>) loaded.getBody().get("batch");
        assertThat(created.get("rowsRead")).isEqualTo(2);
        assertThat(created.get("uploadedOffice")).isEqualTo("academic");
        assertThat(created.get("uploadedBy")).isEqualTo(registrar.toString());
        String id = String.valueOf(created.get("id"));

        ResponseEntity<List> findings = client.get().uri("/api/v1/admissions/sessions/2026/2027/reconciliation")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .retrieve().toEntity(List.class);
        assertThat(findings.getStatusCode().value()).isEqualTo(200);
        assertThat(findings.getBody()).isNotEmpty();

        ResponseEntity<Map> commit = client.post().uri("/api/v1/admissions/caps-batches/" + id + "/commit")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .retrieve().toEntity(Map.class);
        // either the list reconciles and is committed, or the database says — with a remedy — why not
        assertThat(commit.getStatusCode().value()).isIn(200, 422);
        if (commit.getStatusCode().value() == 422) {
            assertThat(commit.getBody().get("code")).isEqualTo("DATABASE_RULE_REFUSED");
            assertThat(commit.getBody().get("remedy")).isNotNull();
        } else {
            assertThat(commit.getBody().get("outcome")).isEqualTo("committed");
        }
    }

    @Test
    void aRowThatContradictsTheDeclaredListKindIsRefusedWholeByTheDatabase() {
        Map<String, Object> batch = batch("DIRECT_ENTRY", List.of(
                row("DIRECT_ENTRY", null, "C00061"), row("UTME", 301, "C00061")));
        ResponseEntity<Map> r = client.post().uri("/api/v1/admissions/caps-batches")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .contentType(MediaType.APPLICATION_JSON)
                .body(batch)
                .retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo("DATABASE_RULE_REFUSED");
        assertThat(String.valueOf(r.getBody().get("detail"))).contains("UTME row in a batch declared DIRECT_ENTRY");
        assertThat(((Map<?, ?>) r.getBody().get("remedy")).get("message").toString()).contains("declared before the file is read");

        // and nothing of it was kept: the batch is not there to be listed
        ResponseEntity<List> list = client.get().uri("/api/v1/admissions/caps-batches?session=" + SESSION)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .retrieve().toEntity(List.class);
        assertThat(list.getBody().stream().map(b -> ((Map<?, ?>) b).get("fileSha256")))
                .doesNotContain(batch.get("fileSha256"));
    }

    @Test
    void theWrongOfficeCannotLoadTheList() {
        String dean = TestTokens.token(UUID.randomUUID(), List.of("dean"));
        ResponseEntity<Map> r = client.post().uri("/api/v1/admissions/caps-batches")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + dean)
                .contentType(MediaType.APPLICATION_JSON)
                .body(batch("DIRECT_ENTRY", List.of(row("DIRECT_ENTRY", null, "C00061"))))
                .retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void theNumberIsReadOutOfJambsFilename() {
        ResponseEntity<Map> r = client.get().uri("/api/v1/admissions/reg-no?in=Copy%20of%20202699168863AH_Face%20(1).jpg")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).isEqualTo(200);
        assertThat(r.getBody().get("regNo")).isEqualTo("202699168863AH");
    }

    @Test
    void theProgrammesCarryTheirJambNames() {
        ResponseEntity<List> r = client.get().uri("/api/v1/admissions/programmes")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .retrieve().toEntity(List.class);
        assertThat(r.getStatusCode().value()).isEqualTo(200);
        assertThat(r.getBody().size()).isGreaterThanOrEqualTo(90);
        Map<?, ?> mbbs = (Map<?, ?>) r.getBody().stream()
                .filter(p -> "C00061".equals(((Map<?, ?>) p).get("code"))).findFirst().orElseThrow();
        assertThat(mbbs.get("name")).isEqualTo("MBBS");
        assertThat(mbbs.get("jambName")).isEqualTo("Medicine & Surgery");
        assertThat(mbbs.get("facultyName")).isEqualTo("Basic and Applied Medical Sciences");
    }

    @Test
    void whatJambCallsAProgrammeIsRecordedOncePerCodeAndNeverTwice() {
        // JAMB's own words for Broadcasting, as the 2026 download had them (V012)
        ResponseEntity<Map> set = client.put().uri("/api/v1/admissions/programmes/C60514/jamb-alias")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("jambName", "Broadcasting"))
                .retrieve().toEntity(Map.class);
        assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
        assertThat(set.getBody().get("jambName")).isEqualTo("Broadcasting");
        assertThat(set.getBody().get("name")).isEqualTo("B.Sc. BROADCASTING");

        // the same name cannot mean a second programme
        ResponseEntity<Map> twice = client.put().uri("/api/v1/admissions/programmes/C62073/jamb-alias")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("jambName", "broadcasting"))
                .retrieve().toEntity(Map.class);
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody().get("code")).isEqualTo("ADM_ALIAS_TAKEN");

        // a Dean may not rename JAMB's courses
        String dean = TestTokens.token(UUID.randomUUID(), List.of("dean"));
        ResponseEntity<Map> refused = client.put().uri("/api/v1/admissions/programmes/C60514/jamb-alias")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + dean)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("jambName", "Broadcasting"))
                .retrieve().toEntity(Map.class);
        assertThat(refused.getStatusCode().value()).isEqualTo(403);
    }

    @Test
    @SuppressWarnings("unchecked")
    void aProgrammeIsRenamedInTheUniversitysOwnWordsAndKeepsItsCode() {
        ResponseEntity<List> all = client.get().uri("/api/v1/admissions/programmes")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .retrieve().toEntity(List.class);
        Map<?, ?> before = ((List<Map<?, ?>>) all.getBody()).stream()
                .filter(p -> "C62073".equals(p.get("code"))).findFirst().orElseThrow();
        Map<String, Object> words = new java.util.HashMap<>();
        words.put("name", before.get("name") + " (renamed)");
        words.put("deptCode", before.get("deptCode"));
        words.put("category", before.get("category"));
        words.put("archived", false);

        ResponseEntity<Map> renamed = client.put().uri("/api/v1/admissions/programmes/C62073")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .contentType(MediaType.APPLICATION_JSON)
                .body(words)
                .retrieve().toEntity(Map.class);
        assertThat(renamed.getStatusCode().value()).as(String.valueOf(renamed.getBody())).isEqualTo(200);
        assertThat(renamed.getBody().get("name")).isEqualTo(before.get("name") + " (renamed)");
        assertThat(renamed.getBody().get("code")).isEqualTo("C62073");
        assertThat(renamed.getBody().get("facultyCode")).isEqualTo(before.get("facultyCode"));

        // a department the structure does not carry is refused with the remedy
        words.put("deptCode", "NOSUCH");
        ResponseEntity<Map> refused = client.put().uri("/api/v1/admissions/programmes/C62073")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .contentType(MediaType.APPLICATION_JSON)
                .body(words)
                .retrieve().toEntity(Map.class);
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("ADM_DEPARTMENT_UNKNOWN");

        // put the words back, so the seed reads as the seed for every other test
        words.put("deptCode", before.get("deptCode"));
        words.put("name", before.get("name"));
        ResponseEntity<Map> restored = client.put().uri("/api/v1/admissions/programmes/C62073")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + registrarToken)
                .header("X-Active-Office", "academic")
                .contentType(MediaType.APPLICATION_JSON)
                .body(words)
                .retrieve().toEntity(Map.class);
        assertThat(restored.getBody().get("name")).isEqualTo(before.get("name"));
    }

    // ── helpers ─────────────────────────────────────────────────────────

    static final java.security.SecureRandom RANDOM = new SecureRandom();

    static String regNo() {
        StringBuilder sb = new StringBuilder("2026");
        for (int i = 0; i < 8; i++) {
            sb.append(RANDOM.nextInt(10));
        }
        return sb.append("ZZ").toString();
    }

    static String sha256Hex() {
        byte[] b = new byte[32];
        RANDOM.nextBytes(b);
        return java.util.HexFormat.of().formatHex(b);
    }

    static Map<String, Object> row(String entryMode, Integer aggregate, String code) {
        Map<String, Object> row = new HashMap<>();
        row.put("jambRegNo", regNo());
        row.put("surname", "Ugba");
        row.put("otherNames", "Nguveren Esther");
        row.put("jambCode", code);
        row.put("aggregate", aggregate);
        row.put("sex", "F");
        row.put("stateOfOrigin", "Benue");
        row.put("lga", "Gwer-East");
        row.put("entryMode", entryMode);
        row.put("raw", Map.of("RG_NUM", row.get("jambRegNo"), "RG_SURNAME", "UGBA"));
        return row;
    }

    static Map<String, Object> batch(String listKind, List<Map<String, Object>> rows) {
        Map<String, Object> batch = new HashMap<>();
        batch.put("session", SESSION);
        batch.put("source", "CAPS_DOWNLOAD");
        batch.put("filename", "downloaded list from jamb format.xlsx");
        batch.put("fileSha256", sha256Hex());
        batch.put("listKind", listKind);
        batch.put("downloadedOn", "2026-08-27");
        batch.put("rows", rows);
        return batch;
    }
}
