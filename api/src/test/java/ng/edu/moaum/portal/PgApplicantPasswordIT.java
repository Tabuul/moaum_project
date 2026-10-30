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
 * V706: a postgraduate applicant's password reset by the School of Postgraduate Studies (the Dean, the Secretary), the Director of ICT
 * or ICT Support. A made-up applicant applies and signs in; the Registry is refused the desk; a short reason is refused; ICT Support
 * resets the password to the application number — the applicant's open session ends, the old password opens nothing, the application
 * number (in small letters too) signs them in to a session that may only change it, the application number is refused as the new
 * password and their own is taken, and the same session goes on; the application number opens nothing after. The Secretary resets
 * once more; both resets on the history, and the applicant told. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgApplicantPasswordIT {

    static final String DESK = "/api/v1/pg/applicant-passwords";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String school;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        school = TestTokens.token(it.person("ZZPG-PWD", "ZZPGPWDSCHOOL"), List.of("pgschool"));
    }

    private static Map<String, Object> form(ItSupport.PgPerson p, String email, String programme) {
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("surname", p.surname()); f.put("otherNames", p.otherNames()); f.put("sex", "F");
        if (p.dob() != null) f.put("dob", p.dob());
        f.put("email", email); f.put("phone", p.phone()); f.put("password", "Candidate2026!"); f.put("programme", programme);
        f.put("nationality", "Nigerian"); f.put("contactAddress", "No. 1 Test Road, Makurdi");
        f.put("priorInstitution", "Benue State University"); f.put("priorAward", "B.Sc."); f.put("priorClass", "Second Class Upper");
        return f;
    }

    private ResponseEntity<Map> signIn(String identifier, String password) {
        return it.anon(HttpMethod.POST, "/api/v1/pg/sign-in", Map.of("identifier", identifier, "password", password));
    }

    @Test
    void theSchoolOrIctResetsTheApplicantsPasswordToTheApplicationNumberAndTheApplicantChoosesTheirOwn() {
        String programme = jdbc.sql("""
                SELECT code FROM ref.programme WHERE category = 'POST GRADUATE' AND NOT archived AND admissions.pg_award_level(pg_award) = 800 ORDER BY code LIMIT 1
                """).query(String.class).single();
        String email = "zzpgpwd." + UUID.randomUUID().toString().substring(0, 8) + "@example.com";
        ResponseEntity<Map> applied = it.anon(HttpMethod.POST, "/api/v1/pg/apply", form(ItSupport.pgPerson("ZZPGPWD"), email, programme));
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);
        UUID application = UUID.fromString(String.valueOf(applied.getBody().get("application_id")));
        Map<String, Object> row = jdbc.sql("SELECT applicant_id, application_no FROM admissions.pg_application WHERE id = :a").param("a", application).query().singleRow();
        UUID applicant = (UUID) row.get("applicant_id");
        String appNo = String.valueOf(row.get("application_no"));

        ResponseEntity<Map> first = signIn(email, "Candidate2026!");
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
        assertThat(first.getBody().get("mustChange")).isEqualTo(false);
        String firstToken = String.valueOf(first.getBody().get("token"));
        assertThat(it.get(firstToken, "/api/v1/pg/me").getStatusCode().value()).isEqualTo(200);

        // the desk: the Registry is refused; the School finds the applicant by the application number, the email and the name
        assertThat(it.getList(ItSupport.token("registrar"), DESK + "/search?q=" + appNo).getStatusCode().value()).isEqualTo(403);
        assertThat(it.getList(ItSupport.token("dbops"), DESK + "/search?q=" + appNo).getStatusCode().value()).isEqualTo(403);
        assertThat((List<Map<String, Object>>) it.getList(school, DESK + "/search?q=" + appNo.toLowerCase()).getBody())
                .extracting(h -> h.get("applicant_id")).containsExactly(applicant.toString());
        assertThat((List<Map<String, Object>>) it.getList(school, DESK + "/search?q=" + email.toUpperCase()).getBody())
                .extracting(h -> h.get("application_no")).containsExactly(appNo);
        Map<String, Object> account = it.get(school, DESK + "/" + applicant).getBody();
        assertThat(account.get("applicationNo")).isEqualTo(appNo);
        assertThat(account.get("mustChange")).isEqualTo(false);
        assertThat(account).doesNotContainKey("password_hash");

        // a reason is said in ten characters or more
        String support = ItSupport.token("ictagent");
        assertThat(it.call(support, HttpMethod.POST, DESK + "/" + applicant + "/reset", Map.of("reason", "forgot")).getBody().get("code")).isEqualTo("APW_REASON");
        ResponseEntity<Map> reset = it.call(support, HttpMethod.POST, DESK + "/" + applicant + "/reset",
                Map.of("reason", "The applicant forgot the password; identity checked by phone"));
        assertThat(reset.getStatusCode().value()).as(String.valueOf(reset.getBody())).isEqualTo(200);
        assertThat(reset.getBody().get("applicationNo")).isEqualTo(appNo);
        assertThat(reset.getBody().get("sessionsEnded")).isEqualTo(1);
        assertThat(it.get(firstToken, "/api/v1/pg/me").getStatusCode().value()).as("the open session ended").isEqualTo(401);
        assertThat(jdbc.sql("""
                SELECT count(*) FROM platform.notice n WHERE n.about_id = :a AND n.channel = 'EMAIL' AND n.subject = 'Your application password was reset'
                   AND n.body LIKE '%' || :no || '%'
                """).param("a", application).param("no", appNo).query(Long.class).single()).as("the applicant told").isEqualTo(1L);

        // the old password opens nothing; the application number (in small letters too) opens a session that may only change it
        assertThat(signIn(email, "Candidate2026!").getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> onNumber = signIn(email, appNo.toLowerCase());
        assertThat(onNumber.getStatusCode().value()).as(String.valueOf(onNumber.getBody())).isEqualTo(200);
        assertThat(onNumber.getBody().get("mustChange")).isEqualTo(true);
        String token = String.valueOf(onNumber.getBody().get("token"));
        ResponseEntity<Map> held = it.get(token, "/api/v1/pg/me");
        assertThat(held.getStatusCode().value()).isEqualTo(403);
        assertThat(held.getBody().get("code")).isEqualTo("PASSWORD_CHANGE_REQUIRED");
        Map<String, Object> state = it.get(token, "/api/v1/pg/me/password").getBody();
        assertThat(state.get("mustChange")).isEqualTo(true);
        assertThat(state.get("applicationNo")).isEqualTo(appNo);
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/pg/me/password", Map.of("currentPassword", "not the number", "newPassword", "my chosen password"))
                .getBody().get("code")).isEqualTo("AUTH_CURRENT_PASSWORD");
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/pg/me/password", Map.of("currentPassword", appNo, "newPassword", appNo.toLowerCase()))
                .getBody().get("code")).isEqualTo("AUTH_PASSWORD_IS_NUMBER");
        assertThat(it.call(token, HttpMethod.POST, "/api/v1/pg/me/password", Map.of("currentPassword", appNo, "newPassword", "short"))
                .getBody().get("code")).isEqualTo("APP_PASSWORD_SHORT");
        ResponseEntity<Map> changed = it.call(token, HttpMethod.POST, "/api/v1/pg/me/password", Map.of("currentPassword", appNo, "newPassword", "my chosen password"));
        assertThat(changed.getStatusCode().value()).as(String.valueOf(changed.getBody())).isEqualTo(200);
        assertThat(it.get(token, "/api/v1/pg/me").getStatusCode().value()).as("the same session goes on").isEqualTo(200);
        assertThat(signIn(email, appNo).getStatusCode().value()).as("the application number opens nothing now").isEqualTo(422);
        ResponseEntity<Map> chosen = signIn(appNo, "my chosen password");
        assertThat(chosen.getStatusCode().value()).isEqualTo(200);
        assertThat(chosen.getBody().get("mustChange")).isEqualTo(false);

        // the Secretary resets too; both resets on the history, newest first, kept
        ResponseEntity<Map> again = it.call(ItSupport.token("pgsecretary"), HttpMethod.POST, DESK + "/" + applicant + "/reset",
                Map.of("reason", "The applicant asked the School's office again"));
        assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(200);
        List<Map<String, Object>> history = (List<Map<String, Object>>) it.getList(ItSupport.token("ict"), DESK + "/history?applicant=" + applicant).getBody();
        assertThat(history).extracting(h -> h.get("reset_office")).containsExactly("pgsecretary", "ictagent");
        assertThat(history).extracting(h -> h.get("method")).containsOnly("DEFAULT_NUMBER");
        assertThat(it.get(school, DESK + "/" + applicant).getBody().get("mustChange")).isEqualTo(true);
    }
}
