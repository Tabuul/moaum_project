package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * The Bursar's dashboard: the users with the Bursar's role (and the Students Account Officer's) and the Bursary's audit trail. An
 * invented Bursar in post is listed with the office and the account; a fee line the Bursar states is on the trail as an addition
 * to a fee line, under the Bursar's office, with the reason and the line's key facts; ending it is on the trail as a change with
 * what changed; the trail is filtered by the user, the kind of change, the record and the reason. Internal Audit reads it; the
 * Registrar and the Students Account Officer do not. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class BursaryAuditIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @AfterEach
    void clean() {
        if (session != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update());
    }

    @Test
    void theBursarSeesTheUsersWithTheRoleAndTheBursarysTrail() {
        String surname = it.freeSurname("ZZBURSAUDIT");
        UUID bursarId = it.person("ZZ-BAT-" + surname.substring(11), surname);
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, 'bursar', 'platform', NULL, 'integration test: Bursar in post', :p, current_date)
                """).param("p", bursarId).update());
        String bursar = TestTokens.token(bursarId, List.of("bursar"));
        int y = it.freeYear(6300, 6600);
        session = y + "/" + (y + 1);
        it.session(session, y);
        String path = "/api/v1/finance/sessions/" + y + "/" + (y + 1);

        // the users with the role: the invented Bursar in post, under the Bursar's office
        ResponseEntity<Map> users = it.get(bursar, "/api/v1/finance/bursary/users");
        assertThat(users.getStatusCode().value()).as(String.valueOf(users.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) users.getBody().get("rows")).anySatisfy(u -> {
            assertThat(u.get("person_id")).isEqualTo(bursarId.toString());
            assertThat(u).containsEntry("office_code", "bursar").containsEntry("in_post", true).containsEntry("scope_kind", "platform");
        });

        // a fee line stated, then ended, by the Bursar
        Map<String, Object> line = new HashMap<>(Map.of("item", "School fees (audit trail test)", "amount", 45000, "level", 100, "programmeCode", "C00061"));
        ResponseEntity<Map> added = it.call(bursar, HttpMethod.POST, path + "/schedule", line);
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
        UUID id = jdbc.sql("SELECT id FROM finance.fee_schedule WHERE session = :s AND item = 'School fees (audit trail test)' AND ended_at IS NULL")
                .param("s", session).query(UUID.class).single();
        assertThat(it.call(bursar, HttpMethod.POST, path + "/schedule/" + id + "/end", Map.of()).getStatusCode().value()).isEqualTo(200);

        // the trail: the addition and the change, under the Bursar's office, with the reason, the key facts and what changed
        String base = "/api/v1/finance/bursary/audit?person=" + bursarId + "&subject=finance.fee_schedule";
        ResponseEntity<Map> trail = it.get(bursar, base);
        assertThat(trail.getStatusCode().value()).as(String.valueOf(trail.getBody())).isEqualTo(200);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) trail.getBody().get("rows");
        assertThat(rows).anySatisfy(r -> {
            assertThat(r).containsEntry("kind", "CHANGE").containsEntry("action", "INSERT").containsEntry("office", "bursar").containsEntry("subject_id", id.toString());
            assertThat(String.valueOf(r.get("reason"))).isNotBlank();   // the reason the request carried (ItSupport's)
            assertThat((Map<String, Object>) r.get("summary")).containsEntry("item", "School fees (audit trail test)");
        });
        assertThat(rows).anySatisfy(r -> {
            assertThat(r).containsEntry("action", "UPDATE").containsEntry("subject_id", id.toString());
            assertThat((List<Map<String, Object>>) r.get("changes")).extracting(c -> c.get("field")).contains("ended_at");
        });
        assertThat(((Number) ((Map) trail.getBody().get("tiles")).get("changes")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat((List<Map<String, Object>>) it.get(bursar, base + "&action=UPDATE").getBody().get("rows")).allSatisfy(r -> assertThat(r).containsEntry("action", "UPDATE"));
        assertThat(((Number) it.get(bursar, base + "&q=integration").getBody().get("total")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) it.get(bursar, base + "&office=studentaccounts").getBody().get("total")).intValue()).isZero();
        assertThat(((Number) it.get(bursar, "/api/v1/finance/bursary/audit?person=" + bursarId + "&kind=SIGN_INS").getBody().get("total")).intValue()).isZero();

        // Internal Audit reads it; the Registrar and the Students Account Officer do not
        assertThat(it.get(ItSupport.token("audit"), base).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(ItSupport.token("registrar"), base).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("studentaccounts"), "/api/v1/finance/bursary/users").getStatusCode().value()).isEqualTo(403);
    }
}
