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
 * V455 through the API: a postgraduate student's level is corrected only to 700, 800 or 900 and an undergraduate's never to a
 * postgraduate level; the old-portal Students register upload, carrying a postgraduate student with the old 100 Level, keeps
 * them at their postgraduate level.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class PostgraduateLevelIT {

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
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("MOAUM/ADM/79/" + k + "55", "ZZPGLUG" + k)));
        registrar = TestTokens.token(it.person("ZZPGL-REG-" + tag, "ZZPGLREG"), List.of("registrar"));
        pgProgramme = it.db(() -> jdbc.sql("SELECT code FROM ref.programme WHERE category = 'POST GRADUATE' AND NOT coalesce(archived, false) ORDER BY code LIMIT 1")
                .query(String.class).single());
        pg = UUID.randomUUID();
        pgMatric = "BSU/ZZ/PHD/79/" + tag;
        it.db(() -> jdbc.sql("""
                INSERT INTO people.student (id, matric_no, surname, other_names, programme_code, entry_mode, study_mode, entry_session,
                                            entry_level, current_level, status, matriculated_at)
                VALUES (:id, :m, :s, 'Invented', :p, 'POSTGRADUATE', 'FULL_TIME', policy.university_current_session(), 900, 900, 'ACTIVE', now())
                """).param("id", pg).param("m", pgMatric).param("s", "ZZPGL" + tag).param("p", pgProgramme).update());
    }

    private int level(UUID student) {
        return it.db(() -> jdbc.sql("SELECT current_level FROM people.student WHERE id = :id").param("id", student).query(Integer.class).single());
    }

    private static String code(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        return String.valueOf(r.getBody().get("code"));
    }

    @Test
    void aPostgraduateLevelIsCorrectedOnlyToAPostgraduateLevel() {
        ResponseEntity<Map> ok = it.call(registrar, HttpMethod.PUT, "/api/v1/student/students/" + pg + "/level", Map.of("level", 800, "reason", "IT " + tag));
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
        assertThat(level(pg)).isEqualTo(800);
        ok = it.call(registrar, HttpMethod.PUT, "/api/v1/student/students/" + pg + "/level", Map.of("level", 900, "reason", "IT " + tag));
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
        assertThat(level(pg)).isEqualTo(900);
        assertThat(code(it.call(registrar, HttpMethod.PUT, "/api/v1/student/students/" + pg + "/level", Map.of("level", 100, "reason", "IT " + tag)))).isEqualTo("STU_LEVEL");
        assertThat(level(pg)).isEqualTo(900);
        // an undergraduate is never set to a doctorate's level
        String ugProgramme = it.db(() -> jdbc.sql("SELECT code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND NOT coalesce(archived, false) ORDER BY code LIMIT 1")
                .query(String.class).single());
        UUID ug = it.student("ZZPGLUG" + tag, ugProgramme, "MOAUM/ADM/79/" + tag + "55", null, 200);
        assertThat(code(it.call(registrar, HttpMethod.PUT, "/api/v1/student/students/" + ug + "/level", Map.of("level", 900, "reason", "IT " + tag)))).isEqualTo("STU_LEVEL");
    }

    @Test
    void theStudentsRegisterUploadKeepsAPostgraduateAtTheirLevel() {
        ResponseEntity<Map> r = it.call(registrar, HttpMethod.POST, "/api/v1/results/legacy/students",
                Map.of("rows", List.of(Map.of("matric", pgMatric, "name", "ZZPGL" + tag + ", Invented", "programme", pgProgramme, "level", "100"))));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        assertThat(((Number) r.getBody().get("updated")).intValue()).isEqualTo(1);
        assertThat(level(pg)).isEqualTo(900);
        assertThat(it.db(() -> jdbc.sql("SELECT entry_mode FROM people.student WHERE id = :id").param("id", pg).query(String.class).single()))
                .isEqualTo("POSTGRADUATE");
    }
}
