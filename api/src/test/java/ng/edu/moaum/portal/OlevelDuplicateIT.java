package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;

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
 * An O'Level upload is checked for duplicates (V298), through the Candidate Data door the University uploads JAMB's O'Level file by:
 * the same file again is skipped; the same results sent again (with the series the screen now sends) bring nothing new and are
 * skipped; a changed file under the same name is recorded beside the first and its second WAEC result for the same May/June
 * examination is held, not recorded; another applicant's upload with the first one's exam number is recorded and flagged; the
 * Office uses the held result in place of the one on record, with how it was verified, and records the verification of the
 * shared number; the candidate's O'Level view carries the findings. The doors hold.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class OlevelDuplicateIT {

    static final String SESSION = "2117/2118";
    static final String PATH = "/api/v1/admissions/sessions/2117/2118/candidate-data";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");
    final String housing = ItSupport.token("housing");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2117);
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    @SuppressWarnings("unchecked")
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    static Map<String, Object> g(String subject, String grade) { return Map.of("subject", subject, "grade", grade); }

    ResponseEntity<Map> record(String name, String key, Map<String, Object> payload) {
        ResponseEntity<Map> r = it.call(academic, HttpMethod.POST, PATH,
                Map.of("kind", "OLEVEL", "items", List.of(Map.of("sourceName", name, "jambKey", key, "readAs", "COLUMN", "payload", payload))));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r;
    }

    static long dup(ResponseEntity<Map> r, String kind) { return ((Number) m(r.getBody().get("duplicates")).get(kind)).longValue(); }

    @Test
    void aDuplicateOlevelUploadIsSkippedHeldOrFlaggedAndDecidedWithItsVerification() {
        int n = new Random().nextInt(9_000_000) + 1_000_000;
        String k1 = "2117" + n + "0AOL", k2 = "2117" + n + "0BOL";
        String waecNo = "42" + n + "1", otherNo = "42" + n + "2";
        Map<String, Object> first = Map.of("sittings", List.of(
                Map.of("type", "WASSCE", "year", "2023", "examNumber", waecNo, "subjects", List.of(g("English Language", "C6"), g("Mathematics", "B3"), g("Physics", "C5"))),
                Map.of("type", "NECO", "year", "2023", "examNumber", "N" + n, "subjects", List.of(g("Chemistry", "C4")))));

        // recorded as read
        ResponseEntity<Map> r1 = record(k1 + " WASSCE 2023", k1, first);
        assertThat(r1.getBody().get("recorded")).isEqualTo(1);
        assertThat(dup(r1, "SAME_SITTING") + dup(r1, "SAME_RESULT") + dup(r1, "NUMBER_ELSEWHERE")).isZero();
        // the same file again: skipped
        ResponseEntity<Map> r2 = record(k1 + " WASSCE 2023", k1, first);
        assertThat(r2.getBody().get("recorded")).isEqualTo(0);
        assertThat(r2.getBody().get("skipped")).isEqualTo(1);
        // the same results sent again with the series the screen now sends, the number written with spaces: nothing new, skipped
        Map<String, Object> again = Map.of("sittings", List.of(
                Map.of("type", "WASSCE", "series", "MAY/JUNE", "year", "2023", "examNumber", waecNo.substring(0, 4) + " " + waecNo.substring(4), "subjects", List.of(g("English Language", "C6"), g("Mathematics", "B3"), g("Physics", "C5"))),
                Map.of("type", "NECO", "series", "JUNE/JULY", "year", "2023", "examNumber", "N" + n, "subjects", List.of(g("Chemistry", "C4")))));
        ResponseEntity<Map> r3 = record(k1 + " WASSCE 2023", k1, again);
        assertThat(r3.getBody().get("recorded")).isEqualTo(0);
        assertThat(r3.getBody().get("skipped")).isEqualTo(1);
        // a changed file under the same name: recorded beside the first; its second WAEC May/June 2023 result is held, not recorded
        Map<String, Object> changed = Map.of("sittings", List.of(
                Map.of("type", "WASSCE", "series", "MAY/JUNE", "year", "2023", "examNumber", otherNo, "subjects", List.of(g("English Language", "B2"), g("Mathematics", "A1"), g("Physics", "B3")))));
        ResponseEntity<Map> r4 = record(k1 + " WASSCE 2023", k1, changed);
        assertThat(r4.getBody().get("recorded")).isEqualTo(1);
        assertThat(dup(r4, "SAME_SITTING")).isEqualTo(1);
        assertThat(jdbc.sql("SELECT admissions.olevel_sittings(:s, :k)").param("s", SESSION).param("k", k1).query(Integer.class).single()).isEqualTo(2);
        // another applicant with the first one's WAEC number: recorded for them, and flagged
        ResponseEntity<Map> r5 = record(k2 + " WAEC 2022", k2, Map.of("sittings", List.of(
                Map.of("type", "WAEC", "year", "2022", "examNumber", waecNo.substring(0, 3) + "-" + waecNo.substring(3), "subjects", List.of(g("English Language", "A1"))))));
        assertThat(r5.getBody().get("recorded")).isEqualTo(1);
        assertThat(dup(r5, "NUMBER_ELSEWHERE")).isEqualTo(1);

        // the findings: one held, one open
        List<Map<String, Object>> rows = l(it.get(academic, PATH + "/olevel-duplicates").getBody().get("rows"));
        Map<String, Object> held = rows.stream().filter(x -> k1.equals(x.get("jamb_key")) && "SAME_SITTING".equals(x.get("kind"))).findFirst().orElseThrow();
        Map<String, Object> open = rows.stream().filter(x -> k2.equals(x.get("jamb_key")) && "NUMBER_ELSEWHERE".equals(x.get("kind"))).findFirst().orElseThrow();
        assertThat(held.get("state")).isEqualTo("HELD");
        assertThat(held.get("exam_number")).isEqualTo(otherNo);
        assertThat(held.get("other_exam_number")).isEqualTo(waecNo);
        assertThat(open.get("state")).isEqualTo("OPEN");
        assertThat(open.get("other_jamb_key")).isEqualTo(k1);
        assertThat(it.get(housing, PATH + "/olevel-duplicates").getStatusCode().value()).isEqualTo(403);

        // the Office's word: never without how it was verified, never by an office outside the admissions desk
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/olevel-duplicates/" + held.get("id") + "/USE", Map.of("note", " ")).getStatusCode().value()).isIn(400, 422);
        assertThat(it.call(bursar, HttpMethod.POST, PATH + "/olevel-duplicates/" + held.get("id") + "/USE", Map.of("note", "x")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/olevel-duplicates/" + held.get("id") + "/MERGE", Map.of("note", "x")).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> used = it.call(academic, HttpMethod.POST, PATH + "/olevel-duplicates/" + held.get("id") + "/USE",
                Map.of("note", "Checked on the WAEC result checker: " + otherNo + " is the candidate's"));
        assertThat(used.getStatusCode().value()).as(String.valueOf(used.getBody())).isEqualTo(200);
        assertThat(l(used.getBody().get("rows")).stream().filter(x -> held.get("id").equals(x.get("id"))).findFirst().orElseThrow().get("state")).isEqualTo("USED");
        ResponseEntity<Map> twice = it.call(registrar, HttpMethod.POST, PATH + "/olevel-duplicates/" + held.get("id") + "/KEEP", Map.of("note", "x"));
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
        assertThat(twice.getBody().get("code")).isEqualTo("OLEVEL_DUPLICATE_DECIDED");
        ResponseEntity<Map> verified = it.call(registrar, HttpMethod.POST, PATH + "/olevel-duplicates/" + open.get("id") + "/VERIFIED",
                Map.of("note", "WAEC confirms the number is the first candidate's; the second referred to the Registrar"));
        assertThat(verified.getStatusCode().value()).as(String.valueOf(verified.getBody())).isEqualTo(200);

        // the candidate's O'Level: the uploaded result in place of the one on record, the findings beside it
        Map<String, Object> olevel = it.get(academic, "/api/v1/admissions/sessions/2117/2118/candidate-data/" + k1 + "/olevel").getBody();
        List<Map<String, Object>> sittings = l(olevel.get("sittings"));
        assertThat(sittings).hasSize(2);
        assertThat(sittings.stream().map(x -> x.get("examNumber"))).contains(otherNo).doesNotContain(waecNo);
        assertThat(l(olevel.get("duplicates")).stream().map(x -> x.get("kind"))).contains("SAME_SITTING", "NUMBER_ELSEWHERE");
    }
}
