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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V536 through the API: the records check lists an undergraduate with the postgraduate entry mode and one with no state of
 * origin under their issues, names who corrects each, narrows to one issue, and is the Registry's (not the Bursary's).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class RecordIssuesIT {

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
        tag = Integer.toString(it.freeDraw(1_000, 10_000, k -> List.of("MOAUM/RI/36/" + k + "1", "MOAUM/RI/36/" + k + "2", "ZZRIA" + k, "ZZRIB" + k, "ZZRI-REC-" + k, "ZZRI-BUR-" + k)));
    }

    @SuppressWarnings("unchecked")
    @Test
    void theRecordsCheckListsEachInconsistentRecordByIssueWithWhoCorrectsIt() {
        String programme = it.db(() -> jdbc.sql("SELECT code FROM ref.programme WHERE NOT coalesce(archived, false) AND coalesce(category, '') <> 'POST GRADUATE' ORDER BY code LIMIT 1")
                .query(String.class).single());
        UUID pgEntry = it.student("ZZRIA" + tag, programme, null, "MOAUM/RI/36/" + tag + "1", 200);
        UUID noState = it.student("ZZRIB" + tag, programme, null, "MOAUM/RI/36/" + tag + "2", 200);
        it.db(() -> jdbc.sql("UPDATE people.student SET entry_mode = 'POSTGRADUATE', state_of_origin = 'Benue' WHERE id = :a").param("a", pgEntry).update());
        it.db(() -> jdbc.sql("UPDATE people.student SET state_of_origin = NULL WHERE id = :b").param("b", noState).update());
        String records = TestTokens.token(it.person("ZZRI-REC-" + tag, "ZZRIREC"), List.of("records"));
        String bursar = TestTokens.token(it.person("ZZRI-BUR-" + tag, "ZZRIBUR"), List.of("bursar"));

        assertThat(it.get(bursar, "/api/v1/records/issues").getStatusCode().value()).isEqualTo(403);

        ResponseEntity<Map> all = it.get(records, "/api/v1/records/issues");
        assertThat(all.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) all.getBody().get("rows");
        assertThat(rows).anySatisfy(r -> { assertThat(r.get("student_id")).isEqualTo(pgEntry.toString()); assertThat(r.get("issue")).isEqualTo("UG_POSTGRADUATE_ENTRY"); });
        assertThat(rows).anySatisfy(r -> { assertThat(r.get("student_id")).isEqualTo(noState.toString()); assertThat(r.get("issue")).isEqualTo("NO_STATE_OF_ORIGIN"); });
        // every kind says who corrects it, with its count
        List<Map<String, Object>> kinds = (List<Map<String, Object>>) all.getBody().get("kinds");
        assertThat(kinds).hasSize(12).allSatisfy(k -> { assertThat((String) k.get("corrects")).isNotBlank(); assertThat((List<String>) k.get("offices")).isNotEmpty(); });
        assertThat(kinds).anySatisfy(k -> { assertThat(k.get("code")).isEqualTo("UG_POSTGRADUATE_ENTRY"); assertThat(((Number) k.get("students")).intValue()).isPositive(); });

        // one issue: only its rows
        List<Map<String, Object>> one = (List<Map<String, Object>>) it.get(records, "/api/v1/records/issues?issue=UG_POSTGRADUATE_ENTRY").getBody().get("rows");
        assertThat(one).isNotEmpty().allSatisfy(r -> assertThat(r.get("issue")).isEqualTo("UG_POSTGRADUATE_ENTRY"));
        assertThat(one).noneSatisfy(r -> assertThat(r.get("student_id")).isEqualTo(noState.toString()));
    }
}
