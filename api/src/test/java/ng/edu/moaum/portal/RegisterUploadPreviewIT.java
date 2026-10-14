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
 * V459 through the API: an old-portal register upload is previewed before it changes anyone — the preview counts the rows,
 * the refused numbers and the students it leaves alone, lists each change it would make, and writes nothing; only the
 * migrating offices may ask; the postgraduate upload with no level leaves a PhD student at 900.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class RegisterUploadPreviewIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String tag;
    String registrar;
    String pgProgramme;
    UUID pg;
    String pgMatric;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(9_000) + 1_000);
        registrar = TestTokens.token(it.person("ZZRUP-REG-" + tag, "ZZRUPREG"), List.of("registrar"));
        pgProgramme = it.db(() -> jdbc.sql("SELECT code FROM ref.programme WHERE category = 'POST GRADUATE' AND NOT coalesce(archived, false) ORDER BY code LIMIT 1")
                .query(String.class).single());
        pg = UUID.randomUUID();
        pgMatric = "BSU/ZZ/PHD/59/" + tag;
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, matric_no, surname, other_names, programme_code, entry_mode, study_mode, entry_session,
                                            entry_level, current_level, status, matriculated_at)
                VALUES (:id, :m, :s, 'Invented', :p, 'POSTGRADUATE', 'FULL_TIME', policy.university_current_session(), 900, 900, 'ACTIVE', now())
                """).param("id", pg).param("m", pgMatric).param("s", "ZZRUP" + tag).param("p", pgProgramme).update());
    }

    private int level() {
        return it.db(() -> jdbc.sql("SELECT current_level FROM people.student WHERE id = :id").param("id", pg).query(Integer.class).single());
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private Map<String, Object> row(String level) {
        return Map.of("matric", pgMatric, "surname", "ZZRUP" + tag, "otherNames", "Invented", "programme", pgProgramme, "level", level);
    }

    @SuppressWarnings("unchecked")
    @Test
    void anUploadIsPreviewedBeforeItChangesAnyone() {
        // the Students register with the old 100 for the PhD and a bad number: nothing would change, and nothing does
        Map<String, Object> p = ok(it.call(registrar, HttpMethod.POST, "/api/v1/results/legacy/students/preview",
                Map.of("rows", List.of(row("100"), Map.of("matric", "NOT A NUMBER", "surname", "X")))));
        assertThat(((Number) p.get("rows")).intValue()).isEqualTo(2);
        assertThat(((Number) p.get("badNumber")).intValue()).isEqualTo(1);
        assertThat(((Number) p.get("existing")).intValue()).isEqualTo(1);
        assertThat(((Number) p.get("unchanged")).intValue()).isEqualTo(1);
        assertThat((List<Object>) p.get("changes")).isEmpty();
        // the postgraduate upload stating 800: the lowering is listed, and the preview writes nothing
        p = ok(it.call(registrar, HttpMethod.POST, "/api/v1/results/legacy/pg-students/preview", Map.of("rows", List.of(row("800")))));
        assertThat(((Number) p.get("levelLowered")).intValue()).isEqualTo(1);
        Map<String, Object> change = ((List<Map<String, Object>>) p.get("changes")).get(0);
        assertThat(change.get("matric")).isEqualTo(pgMatric);
        assertThat(change.get("field")).isEqualTo("level");
        assertThat(change.get("from")).isEqualTo("900");
        assertThat(change.get("to")).isEqualTo("800");
        assertThat(level()).isEqualTo(900);
        // only the migrating offices may ask
        String student = TestTokens.token(pg, List.of("student"));
        assertThat(it.call(student, HttpMethod.POST, "/api/v1/results/legacy/biodata/preview", Map.of("rows", List.of(row("")))).getStatusCode().value())
                .isEqualTo(403);
    }

    @Test
    void thePostgraduateUploadWithNoLevelLeavesAPhdAt900() {
        ok(it.call(registrar, HttpMethod.POST, "/api/v1/results/legacy/pg-students", Map.of("rows", List.of(row("")))));
        assertThat(level()).isEqualTo(900);
    }
}
