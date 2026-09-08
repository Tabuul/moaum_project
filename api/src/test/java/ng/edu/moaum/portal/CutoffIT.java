package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.client.RestClient;

/**
 * The cut-off comes from the session's admission settings and nowhere else.
 *
 * <p>A session with no settings in force loads nothing. A session whose
 * settings are in force loads every candidate at or above the cut-off that
 * applies to them — the programme's own where it has one, else the
 * faculty's — and holds back, on record, every candidate under it.
 *
 * <p>Needs a database the migrations have been applied to: set DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class CutoffIT {

    /** A session of the test's own, whose settings it completes and puts in force. */
    static final String SESSION = "2099/2100";
    static final UUID POLICY = UUID.fromString("a0000000-0000-0000-0000-000000002099");

    @Value("${local.server.port}")
    int port;

    @Autowired
    JdbcClient jdbc;

    @Autowired
    PlatformTransactionManager transactions;

    RestClient client;
    UUID academic = UUID.randomUUID();
    String token = TestTokens.token(academic, List.of("academic"));

    @BeforeEach
    void setUp() {
        client = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { })
                .build();
        settingsInForce();
    }

    /**
     * Complete settings: the four criteria totalling 100, every faculty with a
     * quota (100 each, 1200 in all) and a cut-off of 150, a rule for every
     * programme, and MBBS with its own cut-off of 200. Then in force, citing
     * a minute. Idempotent, so the test can run again on the same database.
     */
    void settingsInForce() {
        TransactionTemplate tx = new TransactionTemplate(transactions);
        AuditContext context = new AuditContext(academic, "academic", "CutoffIT: settings for " + SESSION, null, null);
        AuditContextHolder.with(context, () -> tx.execute(status -> {
            long inForce = jdbc.sql("SELECT count(*) FROM admissions.session_policy WHERE session = :s AND state = 'IN_FORCE'")
                    .param("s", SESSION).query(Long.class).single();
            if (inForce > 0) {
                return null;
            }
            jdbc.sql("""
                    INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme, state)
                    VALUES (:id, :s, 1200, 70, 30, 'DRAFT') ON CONFLICT DO NOTHING
                    """).param("id", POLICY).param("s", SESSION).update();
            for (String[] c : new String[][] {{"NATIONAL_MERIT", "10"}, {"STATE_MERIT", "35"}, {"ELG", "30"}, {"LOCALITY", "25"}}) {
                jdbc.sql("INSERT INTO admissions.selection_criterion (policy_id, criterion, percent) VALUES (:id, :c, :p) ON CONFLICT DO NOTHING")
                        .param("id", POLICY).param("c", c[0]).param("p", Integer.parseInt(c[1])).update();
            }
            jdbc.sql("""
                    INSERT INTO admissions.faculty_quota (policy_id, faculty_code, quota, cutoff)
                    SELECT :id, code, 100, 150 FROM ref.faculty ON CONFLICT DO NOTHING
                    """).param("id", POLICY).update();
            jdbc.sql("""
                    INSERT INTO admissions.programme_rule (policy_id, programme_code, cutoff, olevel_text, utme_text, de_text)
                    SELECT :id, code, CASE WHEN code = 'C00061' THEN 200 END,
                           'Five credits (test)', 'Any three (test)', 'A-Level (test)'
                      FROM ref.programme ON CONFLICT DO NOTHING
                    """).param("id", POLICY).update();
            jdbc.sql("SELECT admissions.put_in_force(:s, 'CAC minute CutoffIT/1')").param("s", SESSION).query().singleRow();
            return null;
        }));
    }

    @Test
    void theSettingsAreReadBackWithTheirCutoffs() {
        ResponseEntity<Map> r = client.get().uri("/api/v1/admissions/sessions/2099/2100/policy")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        assertThat(r.getBody().get("inForce")).isEqualTo(true);
        assertThat(r.getBody().get("state")).isEqualTo("IN_FORCE");
        assertThat((List<?>) r.getBody().get("facultyCutoffs")).hasSize(12);
        List<?> programme = (List<?>) r.getBody().get("programmeCutoffs");
        assertThat(programme).hasSize(1);
        assertThat(((Map<?, ?>) programme.get(0)).get("code")).isEqualTo("C00061");
        assertThat(((Map<?, ?>) programme.get(0)).get("cutoff")).isEqualTo(200);
        assertThat((List<?>) r.getBody().get("findings")).isEmpty();
    }

    @Test
    void aSessionWithNoSettingsInForceLoadsNothing() {
        ResponseEntity<Map> r = load("2098/2099", row("UTME", 350, "C00061"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        assertThat(r.getBody().get("code")).isEqualTo("ADM_SETTINGS_NOT_IN_FORCE");
        assertThat(((Map<?, ?>) r.getBody().get("remedy")).get("office")).isEqualTo("Academic Office");
    }

    @Test
    void theCutOffThatAppliesIsTheProgrammesElseTheFacultys() {
        ResponseEntity<Map> r = load(SESSION,
                row("UTME", 312, "C00061"),   // MBBS: cut-off 200, loaded
                row("UTME", 190, "C00061"),   // MBBS: under 200, held back
                row("UTME", 160, "C00019"),   // Accounting: faculty cut-off 150, loaded
                row("UTME", 140, "C00019"));  // Accounting: under 150, held back
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(201);
        assertThat(r.getBody().get("rowsLoaded")).isEqualTo(2);
        List<?> excluded = (List<?>) r.getBody().get("excluded");
        assertThat(excluded).hasSize(2);
        Map<?, ?> mbbs = (Map<?, ?>) excluded.get(0);
        assertThat(mbbs.get("aggregate")).isEqualTo(190);
        assertThat(mbbs.get("cutoff")).isEqualTo(200);
        assertThat(mbbs.get("programme")).isEqualTo("MBBS");
        assertThat(mbbs.get("reason")).isEqualTo("BELOW_CUTOFF");
        Map<?, ?> acc = (Map<?, ?>) excluded.get(1);
        assertThat(acc.get("aggregate")).isEqualTo(140);
        assertThat(acc.get("cutoff")).isEqualTo(150);
        Map<?, ?> batch = (Map<?, ?>) r.getBody().get("batch");
        assertThat(batch.get("rowsRead")).isEqualTo(4);

        // the held-back rows are on record, beside the batch
        long kept = jdbc.sql("SELECT count(*) FROM admissions.caps_row_excluded WHERE batch_id = CAST(:id AS uuid)")
                .param("id", String.valueOf(batch.get("id"))).query(Long.class).single();
        assertThat(kept).isEqualTo(2);
    }

    @Test
    void aDirectEntryListCarriesNoAggregateAndNoCutOffApplies() {
        Map<String, Object> batch = batch("2098/2099", "DIRECT_ENTRY", List.of(row("DIRECT_ENTRY", null, "C00061")));
        ResponseEntity<Map> r = client.post().uri("/api/v1/admissions/caps-batches")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).body(batch)
                .retrieve().toEntity(Map.class);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(201);
        assertThat(r.getBody().get("rowsLoaded")).isEqualTo(1);
    }

    // ── helpers ─────────────────────────────────────────────────────────

    ResponseEntity<Map> load(String session, Map<String, Object>... rows) {
        return client.post().uri("/api/v1/admissions/caps-batches")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .body(batch(session, "UTME", List.of(rows)))
                .retrieve().toEntity(Map.class);
    }

    static Map<String, Object> row(String entryMode, Integer aggregate, String code) {
        Map<String, Object> row = new HashMap<>();
        row.put("jambRegNo", ApiIT.regNo());
        row.put("surname", "Ikwue");
        row.put("otherNames", "Amuche Rita");
        row.put("jambCode", code);
        row.put("aggregate", aggregate);
        row.put("sex", "F");
        row.put("stateOfOrigin", "Benue");
        row.put("lga", "Otukpo");
        row.put("entryMode", entryMode);
        row.put("raw", Map.of("RG_NUM", row.get("jambRegNo")));
        return row;
    }

    static Map<String, Object> batch(String session, String listKind, List<Map<String, Object>> rows) {
        Map<String, Object> batch = new HashMap<>();
        batch.put("session", session);
        batch.put("source", "CAPS_DOWNLOAD");
        batch.put("filename", "CutoffIT.xlsx");
        batch.put("fileSha256", ApiIT.sha256Hex());
        batch.put("listKind", listKind);
        batch.put("downloadedOn", "2026-08-27");
        batch.put("rows", rows);
        return batch;
    }
}
