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
 * V623: the audit trail screen reads the end of the trail and counts it from the chain. A made-up member of staff written now by the
 * Directorate of ICT and a made-up student sign-in refused now are among the latest entries; the total equals the entries, staff
 * sign-ins and student sign-ins counted one by one; a filter by office or by domain returns only what it names, from the latest
 * entries (the window is stated), and the filters' counts name the domains and offices present; the Bursary may not read the trail.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class AuditTrailIT {

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

    private long counted() {
        return jdbc.sql("SELECT (SELECT count(*) FROM audit.entries) + (SELECT count(*) FROM iam.sign_in_event) + (SELECT count(*) FROM iam.student_event)")
                .query(Long.class).single();
    }

    private static List<Map<String, Object>> entries(ResponseEntity<Map> r) {
        return (List<Map<String, Object>>) r.getBody().get("entries");
    }

    @Test
    void theTrailIsReadFromItsEndAndCountedFromTheChain() {
        String registrar = ItSupport.token("registrar");
        String base = "/api/v1/audit";

        // a made-up member of staff written now (an attributed write by the Directorate of ICT) and a made-up student sign-in refused now
        String tag = it.freeSurname("ZZAUDTRL");
        UUID person = it.person("ZZ-ATL-" + tag.substring(8), tag);
        String identifier = "ZZ/ATL/" + tag.substring(8);
        jdbc.sql("INSERT INTO iam.student_event (student_id, identifier, outcome, ip) VALUES (NULL, :i, 'NO_ACCOUNT', '10.9.9.9')")
                .param("i", identifier).update();

        // the latest entries carry both; the total is every entry and sign-in, counted from the chain
        long before = counted();
        ResponseEntity<Map> latest = it.get(registrar, base + "/entries?limit=100");
        long after = counted();
        assertThat(latest.getStatusCode().value()).as(String.valueOf(latest.getBody())).isEqualTo(200);
        assertThat(entries(latest)).anySatisfy(e -> {
            assertThat(e).containsEntry("subject_id", person.toString()).containsEntry("actor_office", "ict").containsEntry("action", "INSERT");
        });
        assertThat(entries(latest)).anySatisfy(e -> {
            assertThat(e).containsEntry("subject_type", "student_sign_in").containsEntry("action", "auth:NO_ACCOUNT");
            assertThat(String.valueOf(e.get("reason"))).startsWith(identifier);
        });
        long total = ((Number) ((Map<String, Object>) latest.getBody().get("tiles")).get("total")).longValue();
        assertThat(total).isBetween(before, after);
        assertThat(latest.getBody().get("filterWindow")).isEqualTo(50_000);

        // a filter by office returns that office's entries alone; by domain, that domain's
        ResponseEntity<Map> byOffice = it.get(registrar, base + "/entries?office=ict&limit=500");
        assertThat(entries(byOffice)).isNotEmpty().allSatisfy(e -> assertThat(e).containsEntry("actor_office", "ict"))
                .anySatisfy(e -> assertThat(e).containsEntry("subject_id", person.toString()));
        ResponseEntity<Map> byDomain = it.get(registrar, base + "/entries?action=auth&limit=500");
        assertThat(entries(byDomain)).isNotEmpty().allSatisfy(e -> assertThat(String.valueOf(e.get("action"))).startsWith("auth:"))
                .anySatisfy(e -> assertThat(String.valueOf(e.get("reason"))).startsWith(identifier));

        // the filters' counts, over the same latest entries
        Map<String, Object> facets = it.get(registrar, base + "/facets").getBody();
        assertThat(facets).containsEntry("window", 50_000);
        assertThat((List<Map<String, Object>>) facets.get("actions")).extracting(a -> a.get("domain")).contains("INSERT", "auth");
        assertThat((List<Map<String, Object>>) facets.get("offices")).extracting(o -> o.get("actor_office")).contains("ict");

        // the Bursary does not read the trail
        assertThat(it.get(ItSupport.token("bursary"), base + "/entries").getStatusCode().value()).isEqualTo(403);
    }
}
