package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

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
 * V629: the JAMB list upload merges with the list already held. A made-up Direct Entry list is loaded; the next week's download
 * repeats it — one candidate the same (skipped), one whose course JAMB changed (updated in place on the list it is on, the change
 * kept), one new (added) — and the upload says so, by count and by name. A date of birth sent again the same is skipped; sent
 * changed, it is recorded beside the first and counted as a replacement. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CapsMergeIT {

    static final String SESSION = "2026/2027";

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

    /** a made-up JAMB number no list in the session holds */
    private String freeReg() {
        for (int i = 0; i < 200; i++) {
            String reg = "2026" + String.format("%08d", ThreadLocalRandom.current().nextInt(100_000_000)) + "ZQ";
            if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.caps_row WHERE jamb_key = :r)").param("r", reg).query(Boolean.class).single()) {
                return reg;
            }
        }
        throw new IllegalStateException("no free JAMB number");
    }

    private static Map<String, Object> row(String reg, String code, String surname) {
        Map<String, Object> r = new HashMap<>();
        r.put("jambRegNo", reg);
        r.put("surname", surname);
        r.put("otherNames", "Invented Merge");
        r.put("jambCode", code);
        r.put("aggregate", null);
        r.put("sex", "F");
        r.put("stateOfOrigin", "Benue");
        r.put("lga", "Gwer-East");
        r.put("entryMode", "DIRECT_ENTRY");
        r.put("raw", Map.of("RG_NUM", reg, "CO_NAME", code));
        return r;
    }

    private ResponseEntity<Map> load(String token, String file, List<Map<String, Object>> rows) {
        Map<String, Object> b = new HashMap<>();
        b.put("session", SESSION);
        b.put("source", "CAPS_DOWNLOAD");
        b.put("filename", file);
        b.put("fileSha256", "ab".repeat(32));
        b.put("listKind", "DIRECT_ENTRY");
        b.put("downloadedOn", "2026-10-22");
        b.put("rows", rows);
        return it.call(token, HttpMethod.POST, "/api/v1/admissions/caps-batches", b);
    }

    @Test
    void theNextDownloadSkipsTheSameUpdatesTheChangedAndAddsTheNew() {
        String academic = ItSupport.token("academic");
        String other = jdbc.sql("SELECT code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND code <> 'C00061' AND NOT coalesce(archived, false) ORDER BY code LIMIT 1")
                .query(String.class).single();
        String same = freeReg(), moved = freeReg(), fresh = freeReg();

        ResponseEntity<Map> first = load(academic, "CAPS-DE week 1.xlsx", List.of(row(same, "C00061", "ZZMERGEA"), row(moved, "C00061", "ZZMERGEB")));
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(201);
        assertThat(first.getBody()).containsEntry("rowsLoaded", 2).containsEntry("rowsUpdated", 0).containsEntry("rowsUnchanged", 0);
        String firstBatch = String.valueOf(((Map<String, Object>) first.getBody().get("batch")).get("id"));

        // the next week's download: the first candidate the same, the second moved to another course on JAMB, a third new
        ResponseEntity<Map> second = load(academic, "CAPS-DE week 2.xlsx",
                List.of(row(same, "C00061", "ZZMERGEA"), row(moved, other, "ZZMERGEB"), row(fresh, "C00061", "ZZMERGEC")));
        assertThat(second.getStatusCode().value()).as(String.valueOf(second.getBody())).isEqualTo(201);
        assertThat(second.getBody()).containsEntry("rowsLoaded", 1).containsEntry("rowsUpdated", 1).containsEntry("rowsUnchanged", 1);
        List<Map<String, Object>> updated = (List<Map<String, Object>>) second.getBody().get("updated");
        assertThat(updated).hasSize(1);
        assertThat(updated.get(0)).containsEntry("jambRegNo", moved);
        assertThat((Map<String, Object>) ((Map<String, Object>) updated.get(0).get("changes")).get("course"))
                .containsEntry("from", "C00061").containsEntry("to", other);
        Map<String, Object> batch = (Map<String, Object>) second.getBody().get("batch");
        assertThat(batch).containsEntry("rowsRead", 3).containsEntry("rowsAdded", 1).containsEntry("rowsUpdated", 1).containsEntry("rowsUnchanged", 1);

        // one live row a candidate; the moved one updated in place on the list it was on, the change kept with the upload that carried it
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.caps_row WHERE session = :s AND NOT withdrawn AND jamb_key IN (:a, :b, :c)")
                .param("s", SESSION).param("a", same).param("b", moved).param("c", fresh).query(Long.class).single()).isEqualTo(3L);
        Map<String, Object> movedRow = jdbc.sql("SELECT jamb_code, batch_id::text AS batch FROM admissions.caps_row WHERE jamb_key = :k AND NOT withdrawn")
                .param("k", moved).query().singleRow();
        assertThat(movedRow).containsEntry("jamb_code", other).containsEntry("batch", firstBatch);
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.caps_row_change WHERE jamb_key = :k AND batch_id::text = :b AND changes -> 'course' IS NOT NULL")
                .param("k", moved).param("b", String.valueOf(batch.get("id"))).query(Long.class).single()).isEqualTo(1L);

        // the same download once more: everyone on it already, nothing added or changed
        ResponseEntity<Map> third = load(academic, "CAPS-DE week 2 again.xlsx",
                List.of(row(same, "C00061", "ZZMERGEA"), row(moved, other, "ZZMERGEB"), row(fresh, "C00061", "ZZMERGEC")));
        assertThat(third.getStatusCode().value()).as(String.valueOf(third.getBody())).isEqualTo(201);
        assertThat(third.getBody()).containsEntry("rowsLoaded", 0).containsEntry("rowsUpdated", 0).containsEntry("rowsUnchanged", 3);
    }

    @Test
    void aDateOfBirthSentAgainIsSkippedTheSameAndRecordedChanged() {
        String academic = ItSupport.token("academic");
        String reg = freeReg();
        String path = "/api/v1/admissions/sessions/" + SESSION + "/candidate-data";
        java.util.function.Function<String, Map<String, Object>> send = dob -> Map.of("kind", "DATE_OF_BIRTH", "items", List.of(Map.of(
                "sourceName", reg, "jambKey", reg, "readAs", "COLUMN",
                "payload", Map.of("dob", dob, "ambiguous", false, "surname", "ZZDOB", "first", "Invented", "middle", "", "kind", "UTME"))));

        ResponseEntity<Map> once = it.call(academic, HttpMethod.POST, path, send.apply("12-03-2008"));
        assertThat(once.getStatusCode().value()).as(String.valueOf(once.getBody())).isEqualTo(200);
        assertThat(once.getBody()).containsEntry("recorded", 1).containsEntry("skipped", 0).containsEntry("replaced", 0);
        ResponseEntity<Map> again = it.call(academic, HttpMethod.POST, path, send.apply("12-03-2008"));
        assertThat(again.getBody()).containsEntry("recorded", 0).containsEntry("skipped", 1);
        ResponseEntity<Map> changed = it.call(academic, HttpMethod.POST, path, send.apply("21-03-2008"));
        assertThat(changed.getBody()).containsEntry("recorded", 1).containsEntry("replaced", 1);
        // the newest is the one read
        assertThat(jdbc.sql("""
                SELECT payload ->> 'dob' FROM admissions.attachment WHERE session = :s AND kind = 'DATE_OF_BIRTH' AND jamb_key = :k
                 ORDER BY arrived_at DESC LIMIT 1
                """).param("s", SESSION).param("k", reg).query(String.class).single()).isEqualTo("21-03-2008");
    }
}
