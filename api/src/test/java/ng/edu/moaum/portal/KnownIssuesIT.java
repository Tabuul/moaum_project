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
 * The status report's known issues, closed (V286): the Registrar reads the audit trail; the chain is verified on demand and the
 * run is logged and read back; the two public verifiers answer, refusing what they do not know; a held candidate is told what
 * holds them; a change of status on the register is told to the student. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class KnownIssuesIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String registrar = ItSupport.token("registrar");
    String ict = ItSupport.token("ict");
    String bursar = ItSupport.token("bursar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @Test
    void theAuditTrailTheChainTheVerifiersAndTheNoticesWork() {
        // the Registrar's Audit Trail answers, and the chain verified now is logged and read back
        assertThat(it.get(registrar, "/api/v1/audit/entries?limit=5").getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> run = it.call(ict, HttpMethod.POST, "/api/v1/audit/chain/verify", Map.of());
        assertThat(run.getStatusCode().value()).as(String.valueOf(run.getBody())).isEqualTo(200);
        assertThat(run.getBody().get("ok")).isEqualTo(true);
        Map<String, Object> chain = it.get(registrar, "/api/v1/audit/chain").getBody();
        assertThat(((List<Map<String, Object>>) chain.get("runs"))).isNotEmpty();
        assertThat(String.valueOf(((Map<String, Object>) chain.get("last")).get("run_ref"))).isEqualTo(String.valueOf(run.getBody().get("runRef")));
        Map<String, Object> posture = it.get(registrar, "/api/v1/governance/security").getBody();
        assertThat(((Map<String, Object>) posture.get("audit")).get("chain_last_run")).isNotNull();

        // the two verifiers answer the public, and refuse what they do not know
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/deferment/DEF-NOPE-000", null).getBody().get("genuine")).isEqualTo(false);
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/pg-offer/PG-NOPE?t=ABCDEF012345", null).getBody().get("genuine")).isEqualTo(false);

        // a held candidate is told what holds them, by the unit that holds
        int n = new Random().nextInt(9000) + 1000;
        UUID s = it.student("ZZHELD" + n, "C00023", "MOAUM/ADM/97/" + String.format("%06d", n), "MOAUM/SCI/97/" + n, 400);
        it.db(() -> jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08044446666', :e, now()) ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email").param("s", s).param("e", "zzheld" + n + "@example.edu").update());
        ResponseEntity<Map> hold = it.call(bursar, HttpMethod.POST, "/api/v1/clearance/students/" + s + "/BURSARY/hold", Map.of("purpose", "CONVOCATION", "item", "Convocation fee", "note", "Unpaid"));
        assertThat(hold.getStatusCode().value()).as(String.valueOf(hold.getBody())).isEqualTo(200);
        ResponseEntity<Map> told = it.call(bursar, HttpMethod.POST, "/api/v1/clearance/notify-held", Map.of("students", List.of(s.toString()), "purpose", "CONVOCATION"));
        assertThat(told.getStatusCode().value()).as(String.valueOf(told.getBody())).isEqualTo(200);
        assertThat(((Number) told.getBody().get("notified")).intValue()).isEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject LIKE 'Clearance held%'").param("s", s).query(Long.class).single()).isGreaterThanOrEqualTo(1);

        // a change of status on the register is told to the student, with the instrument
        it.db(() -> jdbc.sql("SELECT people.change_status(:s, 'SUSPENDED', 'Senate minute S/97/12', current_date, 'Examination misconduct, first offence')").param("s", s).query().listOfRows());
        assertThat(jdbc.sql("SELECT body FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND channel = 'EMAIL' AND subject LIKE 'Your status on the University register%' ORDER BY created_at DESC LIMIT 1").param("s", s).query(String.class).single())
                .contains("S/97/12").contains("Suspended");
    }
}
