package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
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
 * V548 through the API: the state a student chooses on the Biodata form reaches the record; the Registry tells the students with
 * no state of origin once a week and reads where they stand; the School of Postgraduate Studies moves a postgraduate record on an
 * undergraduate programme to a postgraduate programme with a reason — and the Bursar does neither.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class RecordsFollowThroughIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String tag;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("MOAUM/RF/48/" + k + "1", "MOAUM/RF/48/" + k + "2", "MOAUM/RF/48/" + k + "3",
                "ZZRFA" + k, "ZZRFB" + k, "ZZRFC" + k, "ZZRF-REC-" + k, "ZZRF-PGS-" + k, "ZZRF-BUR-" + k)));
    }

    @SuppressWarnings("unchecked")
    @Test
    void theStudentsAreToldTheirAnswerReachesTheRecordAndAPostgraduateRecordIsMoved() {
        Map<String, Object> prog = it.db(() -> jdbc.sql("""
                SELECT code, faculty_code FROM ref.programme WHERE NOT coalesce(archived, false) AND coalesce(category, '') <> 'POST GRADUATE'
                 ORDER BY code LIMIT 1""").query().singleRow());
        String programme = (String) prog.get("code"), faculty = (String) prog.get("faculty_code");
        UUID own = it.student("ZZRFA" + tag, programme, null, "MOAUM/RF/48/" + tag + "1", 200);
        UUID silent = it.student("ZZRFB" + tag, programme, null, "MOAUM/RF/48/" + tag + "2", 200);
        UUID pg = it.student("ZZRFC" + tag, programme, null, "MOAUM/RF/48/" + tag + "3", 200);
        it.db(() -> jdbc.sql("UPDATE people.student SET state_of_origin = NULL, entry_mode = 'UTME', candidate_id = NULL WHERE id IN (:a, :b)")
                .param("a", own).param("b", silent).update());
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_mode = 'POSTGRADUATE', current_level = 700, state_of_origin = 'Benue' WHERE id = :p").param("p", pg).update());
        String records = TestTokens.token(it.person("ZZRF-REC-" + tag, "ZZRFREC"), List.of("records"));
        String school = TestTokens.token(it.person("ZZRF-PGS-" + tag, "ZZRFPGS"), List.of("pgschool"));
        String bursar = TestTokens.token(it.person("ZZRF-BUR-" + tag, "ZZRFBUR"), List.of("bursar"));
        String student = TestTokens.token(own, List.of("student"));

        // the student's own answer on the Biodata form reaches the record
        ResponseEntity<Map> wrote = it.call(student, HttpMethod.PUT, "/api/v1/me/biodata/state_of_origin", Map.of("value", "kogi"));
        assertThat(wrote.getStatusCode().value()).isEqualTo(200);
        assertThat(it.db(() -> jdbc.sql("SELECT state_of_origin FROM people.student WHERE id = :s").param("s", own).query(String.class).single())).isEqualTo("Kogi");

        // the Registry tells the students with none, once a week; the Bursar does not
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/records/issues/notices", Map.of("issue", "NO_STATE_OF_ORIGIN", "faculty", faculty)).getStatusCode().value())
                .isEqualTo(403);
        ResponseEntity<Map> told = it.call(records, HttpMethod.POST, "/api/v1/records/issues/notices", Map.of("issue", "NO_STATE_OF_ORIGIN", "faculty", faculty));
        assertThat(told.getStatusCode().value()).isEqualTo(200);
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM people.record_issue_notice WHERE student_id = :s").param("s", silent).query(Long.class).single())).isEqualTo(1L);
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM people.record_issue_notice WHERE student_id = :s").param("s", own).query(Long.class).single())).isZero();
        Map<String, Object> again = it.call(records, HttpMethod.POST, "/api/v1/records/issues/notices", Map.of("issue", "NO_STATE_OF_ORIGIN", "faculty", faculty)).getBody();
        assertThat(((Number) again.get("told")).intValue()).isZero();
        Map<String, Object> progress = it.get(records, "/api/v1/records/issues/notices?issue=NO_STATE_OF_ORIGIN&faculty=" + faculty).getBody();
        assertThat(((Number) progress.get("told")).intValue()).isPositive();
        assertThat(((Number) progress.get("toTell")).intValue()).isZero();
        assertThat(it.call(records, HttpMethod.POST, "/api/v1/records/issues/notices", Map.of("issue", "UG_POSTGRADUATE_ENTRY")).getStatusCode().value()).isEqualTo(422);

        // the School moves the postgraduate record, with a reason; the Bursar may not
        Map<String, Object> options = it.get(school, "/api/v1/records/issues/move/" + pg).getBody();
        assertThat(options.get("movable")).isEqualTo(true);
        List<Map<String, Object>> programmes = (List<Map<String, Object>>) options.get("options");
        if (programmes.isEmpty()) {
            return; // no postgraduate programme on this register
        }
        String target = (String) programmes.get(0).get("code");
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/records/issues/move/" + pg, Map.of("programme", target, "level", 800, "reason", "The School's admission list"))
                .getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(school, HttpMethod.POST, "/api/v1/records/issues/move/" + pg, Map.of("programme", target, "level", 800, "reason", "short"))
                .getStatusCode().is4xxClientError()).isTrue();
        ResponseEntity<Map> moved = it.call(school, HttpMethod.POST, "/api/v1/records/issues/move/" + pg, Map.of("programme", target, "level", 800, "reason", "The School's admission list"));
        assertThat(moved.getStatusCode().value()).isEqualTo(200);
        assertThat(it.db(() -> jdbc.sql("SELECT programme_code || '/' || current_level || '/' || entry_mode FROM people.student WHERE id = :s").param("s", pg).query(String.class).single()))
                .isEqualTo(target + "/800/POSTGRADUATE");
        assertThat(it.db(() -> jdbc.sql("SELECT reason FROM people.record_move WHERE student_id = :s").param("s", pg).query(String.class).single()))
                .isEqualTo("The School's admission list");
        // an undergraduate record is not moved here
        ResponseEntity<Map> refused = it.call(school, HttpMethod.POST, "/api/v1/records/issues/move/" + silent, Map.of("programme", target, "level", 800, "reason", "not a postgraduate record"));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("RECORD_MOVE_NOT_POSTGRADUATE");
    }
}
