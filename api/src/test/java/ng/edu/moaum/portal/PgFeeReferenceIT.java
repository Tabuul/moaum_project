package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashMap;
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
 * V564: a postgraduate fee reference is drawn until free. The reference (MOAUM-PGAPP-000123) names no session while its number
 * comes from the session's own series, so a new intake session drew numbers an earlier session had issued, and every new applicant
 * was told "An application already exists for this email". Here the intake session's series is put back to a number already issued:
 * a new applicant is still taken, on a reference past every number used; the applicant's own email applying again is still told it
 * already applied. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgFeeReferenceIT {

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

    /** V694: each applicant a person no run has made — one application is taken from a person in a session */
    private Map<String, Object> form(String email, String programme, ItSupport.PgPerson who) {
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("surname", who.surname()); f.put("otherNames", who.otherNames()); f.put("sex", "M"); f.put("dob", who.dob());
        f.put("email", email); f.put("phone", who.phone()); f.put("password", "08160054171"); f.put("programme", programme);
        f.put("priorInstitution", "Benue State University"); f.put("priorAward", "B.Sc."); f.put("priorClass", "Second Class Upper");
        f.put("referees", List.of(Map.of("name", "Prof. Referee", "institution", "BSU", "position", "Professor")));
        return f;
    }

    @Test
    void aNewApplicantIsTakenWhenTheSessionsSeriesRedrawsAnIssuedReference() {
        String programme = jdbc.sql("SELECT code FROM ref.programme WHERE category = 'POST GRADUATE' AND NOT archived ORDER BY code LIMIT 1").query(String.class).single();
        String first = "zzpgref." + UUID.randomUUID().toString().substring(0, 8) + "@example.com";
        ItSupport.PgPerson ada = ItSupport.pgPerson("ZZPGFEEREF");
        ResponseEntity<Map> one = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form(first, programme, ada));
        assertThat(one.getStatusCode().value()).as(String.valueOf(one.getBody())).isEqualTo(200);
        String issued = String.valueOf(one.getBody().get("reference"));
        assertThat(issued).matches("MOAUM-PGAPP-[0-9]{6}");
        String session = jdbc.sql("SELECT session FROM admissions.pg_application WHERE id = :a").param("a", UUID.fromString(String.valueOf(one.getBody().get("application_id"))))
                .query(String.class).single();

        // the session's series put back to a number already issued — as a new intake session's series begins at 1
        long number = Long.parseLong(issued.substring("MOAUM-PGAPP-".length()));
        it.db(() -> jdbc.sql("UPDATE platform.number_series SET next_value = :n WHERE kind = 'PG_FEEREF' AND scope = 'UNIVERSITY' AND session = :s")
                .param("n", number).param("s", session).update());

        // a new applicant is taken, on a reference past every number used
        String second = "zzpgref." + UUID.randomUUID().toString().substring(0, 8) + "@example.com";
        ResponseEntity<Map> two = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form(second, programme, ItSupport.pgPerson("ZZPGFEEREF")));
        assertThat(two.getStatusCode().value()).as(String.valueOf(two.getBody())).isEqualTo(200);
        String drawn = String.valueOf(two.getBody().get("reference"));
        assertThat(drawn).isNotEqualTo(issued);
        // the portal's own series only, as pg_new_fee_reference reads it: an old-portal reference (V675) is no number of it
        long top = jdbc.sql("SELECT max(substring(reference FROM '-([0-9]+)$')::bigint) FROM admissions.pg_fee_reference WHERE reference <> :r AND reference ~ '^MOAUM-PG(APP|CHK|ACC)-[0-9]+$'")
                .param("r", drawn).query(Long.class).single();
        assertThat(Long.parseLong(drawn.substring("MOAUM-PGAPP-".length()))).isGreaterThan(top);

        // the applicant's own email applying again is told it already applied
        ResponseEntity<Map> again = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form(first, programme, ada));
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody()).containsEntry("code", "PG_APP_EXISTS").containsEntry("title", "Already applied with this email");
    }
}
