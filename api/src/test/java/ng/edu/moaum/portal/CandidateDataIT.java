package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;

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

/** A download recorded for nobody on any list is held, not discarded, and counted. Needs DATABASE_URL. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class CandidateDataIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String academic = ItSupport.token("academic");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @Test
    @SuppressWarnings("unchecked")
    void aDateOfBirthForNobodyIsHeld() {
        ResponseEntity<Map> recorded = it.call(academic, HttpMethod.POST, "/api/v1/admissions/sessions/2091/2092/candidate-data",
                Map.of("kind", "DATE_OF_BIRTH", "items", List.of(Map.of("sourceName", "209999999999ZZ ", "jambKey", "209999999999ZZ",
                        "readAs", "COLUMN", "payload", Map.of("dob", "05-07-2002", "ambiguous", true)))));
        assertThat(recorded.getStatusCode().value()).as(String.valueOf(recorded.getBody())).isEqualTo(200);

        ResponseEntity<Map> state = it.get(academic, "/api/v1/admissions/sessions/2091/2092/candidate-data");
        assertThat(state.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> attachments = (List<Map<String, Object>>) state.getBody().get("attachments");
        assertThat(attachments).anySatisfy(a -> {
            assertThat(a.get("jambKey")).isEqualTo("209999999999ZZ");
            assertThat(a.get("matched")).isEqualTo(false);
        });
        List<Map<String, Object>> findings = (List<Map<String, Object>>) state.getBody().get("findings");
        assertThat(findings.stream().filter(f -> "Arrived for nobody on any list".equals(f.get("finding")))
                .mapToLong(f -> ((Number) f.get("n")).longValue()).sum()).isGreaterThanOrEqualTo(1);

        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/admissions/sessions/2091/2092/candidate-data",
                Map.of("kind", "PHOTO", "items", List.of())).getStatusCode().value()).isEqualTo(422);
    }

    @Test
    @SuppressWarnings("unchecked")
    void oLevelSittingsAreShownAsSentAndTheScoreIsTheAcademicOfficesAlone() {
        String registrar = ItSupport.token("registrar");
        String key = "2026" + String.format("%08d", new java.util.Random().nextInt(100_000_000)) + "OL";

        // the Academic Office states the grading for the session (the same numbers as the defaults)
        Map<String, Object> grading = new java.util.HashMap<>();
        grading.put("subjectsCounted", 5);
        grading.put("bonusOneSitting", 10);
        grading.put("bonusTwoSittings", 6);
        grading.put("points", Map.of("A1", 6, "B2", 5, "B3", 4, "C4", 3, "C5", 2, "C6", 1, "D7", 0, "E8", 0, "F9", 0));
        ResponseEntity<Map> stated = it.call(academic, HttpMethod.PUT, "/api/v1/admissions/sessions/2091/2092/olevel-grading", grading);
        assertThat(stated.getStatusCode().value()).as(String.valueOf(stated.getBody())).isEqualTo(200);
        assertThat(stated.getBody().get("stated")).isEqualTo(true);
        assertThat(((Map<String, Object>) stated.getBody().get("points")).get("A1")).isEqualTo(6);

        // JAMB's O'Level download: two sittings for one candidate, recorded as read
        List<Map<String, Object>> waec = List.of(
                Map.of("subject", "English Language", "grade", "C6"), Map.of("subject", "Mathematics", "grade", "B3"),
                Map.of("subject", "Physics", "grade", "D7"), Map.of("subject", "Chemistry", "grade", "C5"),
                Map.of("subject", "Biology", "grade", "A1"), Map.of("subject", "Geography", "grade", "C4"));
        List<Map<String, Object>> neco = List.of(
                Map.of("subject", "English Language", "grade", "B2"), Map.of("subject", "Physics", "grade", "C4"),
                Map.of("subject", "Agricultural Science", "grade", "B3"));
        Map<String, Object> payload = Map.of("sittings", List.of(
                Map.of("type", "WAEC Only", "year", "2024", "examNumber", "4110001", "subjects", waec),
                Map.of("type", "NECO", "year", "2025", "examNumber", "9920002", "subjects", neco)));
        ResponseEntity<Map> recorded = it.call(academic, HttpMethod.POST, "/api/v1/admissions/sessions/2091/2092/candidate-data",
                Map.of("kind", "OLEVEL", "items", List.of(Map.of("sourceName", key + " two sittings", "jambKey", key, "readAs", "COLUMN", "payload", payload))));
        assertThat(recorded.getStatusCode().value()).as(String.valueOf(recorded.getBody())).isEqualTo(200);

        // the Academic Office sees the sittings apart and the score: best of each subject, top five, two-sitting bonus
        ResponseEntity<Map> mine = it.get(academic, "/api/v1/admissions/sessions/2091/2092/candidate-data/" + key + "/olevel");
        assertThat(mine.getStatusCode().value()).as(String.valueOf(mine.getBody())).isEqualTo(200);
        List<Map<String, Object>> sittings = (List<Map<String, Object>>) mine.getBody().get("sittings");
        assertThat(sittings).hasSize(2);
        assertThat(sittings.stream().map(x -> x.get("body"))).containsExactlyInAnyOrder("WAEC", "NECO");
        Map<String, Object> screening = (Map<String, Object>) mine.getBody().get("screening");
        assertThat(screening).isNotNull();
        assertThat(screening.get("sittings")).isEqualTo(2);
        assertThat(screening.get("points")).isEqualTo(22);
        assertThat(screening.get("bonus")).isEqualTo(6);
        assertThat(screening.get("total")).isEqualTo(28);

        // the Registrar sees the results as JAMB sent them, and no score
        ResponseEntity<Map> theirs = it.get(registrar, "/api/v1/admissions/sessions/2091/2092/candidate-data/" + key + "/olevel");
        assertThat(theirs.getStatusCode().value()).isEqualTo(200);
        assertThat(((List<?>) theirs.getBody().get("sittings"))).hasSize(2);
        assertThat(theirs.getBody().get("screening")).isNull();
        assertThat(theirs.getBody().get("screeningIs")).isEqualTo("Academic Office");
    }
}
