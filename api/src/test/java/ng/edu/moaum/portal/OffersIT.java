package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

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
 * Offers that lapse (V358), through the API: the Admissions Office (the Academic Office, the Registrar) sets the session's
 * acceptance deadline — never assumed: without one nothing is past it; the offers past it, unaccepted and unpaid, are lapsed
 * when the office says so, each freeing a place; a candidate not on the waiting list is not promoted to it; the Bursary
 * neither reads nor decides. The merit order of the waiting list and the promotion itself are check.sql 202's. Needs
 * DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class OffersIT {

    /** a session no other suite uses: the lapse and the deadline act on a whole session */
    static final String SESSION = "2077/2078";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static int status(ResponseEntity<?> r) {
        return r.getStatusCode().value();
    }

    private UUID application(ItSupport it, String programme, String jamb, String no, String decision) {
        UUID cand = UUID.randomUUID();
        UUID acct = UUID.randomUUID();
        UUID app = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state) "
                    + "VALUES (:id, :s, :j, 'ZZOFFER', :o, (SELECT name FROM ref.programme WHERE code = :p), 'UTME', 100, :st)")
                    .param("id", cand).param("s", SESSION).param("j", jamb).param("o", no).param("p", programme).param("st", "PROPOSED").update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) "
                    + "VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", SESSION).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            return jdbc.sql("""
                    INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at, decision, decision_basis,
                                                        decided_at, decision_released_at)
                    VALUES (:id, :a, :c, :s, :no, now(), now(), :d, :b, now() - interval '20 days', now() - interval '20 days')
                    """).param("id", app).param("a", acct).param("c", cand).param("s", SESSION).param("no", no).param("d", decision)
                    .param("b", "OFFERED".equals(decision) ? "NM" : null, java.sql.Types.VARCHAR).update();
        });
        return app;
    }

    @Test
    void anOfferLapsesOnlyPastADeadlineTheOfficeSetsAndFreesAPlace() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        String registrar = ItSupport.token("registrar");
        String bursar = ItSupport.token("bursar");
        String programme = jdbc.sql("SELECT code FROM ref.programme WHERE NOT archived ORDER BY code LIMIT 1").query(String.class).single();
        String tag = UUID.randomUUID().toString().substring(0, 6);
        int n = new java.util.Random().nextInt(900_000);
        try {
            UUID offered = application(it, programme, "2077OF" + tag, String.format("APP/77/%06d", n), "OFFERED");
            UUID waiting = application(it, programme, "2077WA" + tag, String.format("APP/77/%06d", n + 1), "WAITING");
            String base = "/api/v1/admissions/offers";
            assertThat(status(it.get(bursar, base + "?session=" + SESSION))).isEqualTo(403);
            // no deadline: nothing is past it
            Map<String, Object> v = it.get(registrar, base + "?session=" + SESSION).getBody();
            assertThat(v.get("deadline")).isNull();
            assertThat((List<?>) v.get("pastDeadline")).isEmpty();
            // the office sets fourteen days after release; the Bursary may not
            Map<String, Object> deadline = Map.of("session", SESSION, "daysAfterRelease", 14, "note", "Admissions Committee, check");
            assertThat(status(it.call(bursar, HttpMethod.PUT, base + "/deadline", deadline))).isEqualTo(403);
            ResponseEntity<Map> set = it.call(registrar, HttpMethod.PUT, base + "/deadline", deadline);
            assertThat(status(set)).as(String.valueOf(set.getBody())).isEqualTo(200);
            assertThat((List<Map<String, Object>>) set.getBody().get("pastDeadline")).extracting(r -> r.get("app_id").toString()).containsExactly(offered.toString());
            // lapsed by the office: a place is freed, the candidate's offer state lapsed
            assertThat(status(it.call(bursar, HttpMethod.POST, base + "/lapse", Map.of("session", SESSION)))).isEqualTo(403);
            ResponseEntity<Map> lapsed = it.call(ItSupport.token("academic"), HttpMethod.POST, base + "/lapse", Map.of("session", SESSION));
            assertThat(status(lapsed)).as(String.valueOf(lapsed.getBody())).isEqualTo(200);
            assertThat(lapsed.getBody().get("lapsed")).isEqualTo(1);
            assertThat((List<Map<String, Object>>) lapsed.getBody().get("vacancies")).anySatisfy(x -> {
                assertThat(x.get("vacated_id").toString()).isEqualTo(offered.toString());
                assertThat(x.get("why")).isEqualTo("LAPSED");
                assertThat(x.get("basis")).isEqualTo("NM");
            });
            assertThat(jdbc.sql("SELECT lapsed_at IS NOT NULL FROM admissions.application WHERE id = :a").param("a", offered).query(Boolean.class).single()).isTrue();
            // a lapsed offer is not promoted back, nor anyone not on the programme's waiting list
            ResponseEntity<Map> notWaiting = it.call(registrar, HttpMethod.POST, base + "/promote", Map.of("session", SESSION, "programme", programme, "applicationIds", List.of(offered)));
            assertThat(status(notWaiting)).isEqualTo(422);
            assertThat(notWaiting.getBody().get("code")).isEqualTo("ADMISSION_NOT_WAITING");
            assertThat(status(it.call(bursar, HttpMethod.POST, base + "/promote", Map.of("session", SESSION, "programme", programme, "applicationIds", List.of(waiting))))).isEqualTo(403);
            // cleared, the deadline is gone: nothing more lapses
            ResponseEntity<Map> cleared = it.call(registrar, HttpMethod.PUT, base + "/deadline", Map.of("session", SESSION));
            assertThat(cleared.getBody().get("deadline")).isNull();
        } finally {
            it.db(() -> {
                jdbc.sql("DELETE FROM admissions.offer_deadline WHERE session = :s").param("s", SESSION).update();
                jdbc.sql("DELETE FROM admissions.application WHERE session = :s").param("s", SESSION).update();
                jdbc.sql("DELETE FROM admissions.applicant_account WHERE session = :s").param("s", SESSION).update();
                return jdbc.sql("DELETE FROM admissions.candidate WHERE session = :s").param("s", SESSION).update();
            });
        }
    }
}
