package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;

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
import org.springframework.transaction.support.TransactionTemplate;

/**
 * The application windows (V312): Post-UTME registration and the postgraduate application are open until the Director of ICT
 * first acts; closed, a new registration or application is refused at the API with the Director's closure message and again
 * straight against the database; reopened, it goes through; the public endpoint the login page, the apply pages and the
 * University's website read follows every act within its cache; the closure message is the Director's plain text; and only
 * the Director acts. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ApplicationWindowsIT {

    static final String SESSION = "2109/2110";
    static final String WINDOWS = "/api/v1/portal-windows";
    static final String PUBLIC = "/api/v1/public/application-windows";
    static final String PUTME = "POST_UTME_REGISTRATION";
    static final String PG = "POSTGRADUATE_APPLICATION";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String ict = ItSupport.token("ict");
    String registrar = ItSupport.token("registrar");
    String pgSession;
    String putmeMessage;
    String pgMessage;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2109);
        pgSession = jdbc.sql("SELECT policy.application_session(:t)").param("t", PG).query(String.class).single();
        it.session(pgSession, Integer.parseInt(pgSession.substring(0, 4)));
        putmeMessage = message(PUTME);
        pgMessage = message(PG);
        clean();
    }

    @AfterEach
    void tearDown() {
        clean();
        it.db(() -> {
            jdbc.sql("UPDATE policy.portal_window_message SET message = :m WHERE window_type = :t").param("m", putmeMessage).param("t", PUTME).update();
            jdbc.sql("UPDATE policy.portal_window_message SET message = :m WHERE window_type = :t").param("m", pgMessage).param("t", PG).update();
            return null;
        });
    }

    /** the residue of an earlier run: the test's own windows, so both are open by default again */
    private void clean() {
        it.db(() -> {
            jdbc.sql("DELETE FROM policy.portal_window_event WHERE window_type IN (:a, :b) AND session IN (:s, :p)").param("a", PUTME).param("b", PG).param("s", SESSION).param("p", pgSession).update();
            jdbc.sql("DELETE FROM policy.portal_window WHERE window_type IN (:a, :b) AND session IN (:s, :p)").param("a", PUTME).param("b", PG).param("s", SESSION).param("p", pgSession).update();
            return null;
        });
    }

    private String message(String type) {
        return jdbc.sql("SELECT message FROM policy.portal_window_message WHERE window_type = :t").param("t", type).query(String.class).single();
    }

    private ResponseEntity<Map> act(String type, String session, String action, String reason) {
        return it.call(ict, HttpMethod.POST, WINDOWS + "/" + type, Map.of("session", session, "action", action, "reason", reason, "lateFeeEnabled", false));
    }

    private Map<String, Object> publicWindows(String session) {
        ResponseEntity<Map> r = it.anon(HttpMethod.GET, PUBLIC + (session == null ? "" : "?session=" + session), null);
        assertThat(r.getStatusCode().value()).isEqualTo(200);
        assertThat(r.getHeaders().getCacheControl()).contains("max-age=60");
        return r.getBody();
    }

    private ResponseEntity<Map> register() {
        return it.anon(HttpMethod.POST, "/api/v1/applicant/register",
                Map.of("session", SESSION, "jambKey", "210912345678AB", "email", "closed.window@example.com", "phone", "08012345678", "password", "Password-2109"));
    }

    private ResponseEntity<Map> pgApply() {
        return it.anon(HttpMethod.POST, "/api/v1/pg/apply",
                Map.of("surname", "Window", "otherNames", "Closed", "email", "closed.pg.window@example.com", "password", "Password-2109", "programme", "NOSUCH"));
    }

    @Test
    void postUtmeRegistrationIsRefusedWhileClosedAndTakenAgainWhenReopened() {
        // open by default: the public endpoint says so, and registration reaches the list (where this number is not)
        Map<String, Object> pub = publicWindows(SESSION);
        Map<String, Object> putme = (Map<String, Object>) pub.get("postUtme");
        assertThat(putme.get("status")).isEqualTo("OPEN");
        assertThat(putme.get("open")).isEqualTo(true);
        assertThat(putme.get("session")).isEqualTo(SESSION);
        assertThat(putme.get("message")).isNull();
        assertThat(String.valueOf(putme.get("applicationUrl"))).endsWith("/apply");
        ResponseEntity<Map> open = register();
        assertThat(open.getBody().get("code")).isNotEqualTo("APPLICATION_CLOSED");

        // the Director closes it: the API refuses with the closure message, the public endpoint says CLOSED and carries the message
        ResponseEntity<Map> closed = act(PUTME, SESSION, "CLOSE", "integration test: registration closed");
        assertThat(closed.getStatusCode().value()).isEqualTo(200);
        assertThat(((Map) closed.getBody().get("after")).get("state")).isEqualTo("CLOSED");
        assertThat(closed.getBody().get("told")).isEqualTo(0);
        ResponseEntity<Map> refused = register();
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("APPLICATION_CLOSED");
        assertThat(String.valueOf(refused.getBody().get("detail"))).contains("CLOSED");
        putme = (Map<String, Object>) publicWindows(SESSION).get("postUtme");
        assertThat(putme.get("status")).isEqualTo("CLOSED");
        assertThat(putme.get("open")).isEqualTo(false);
        assertThat(String.valueOf(putme.get("message"))).contains("POST-UTME REGISTRATION IS CURRENTLY CLOSED");

        // the backstop: straight into the database as the applicant, the account is refused before any constraint is reached
        assertThatThrownBy(() -> it.db(() -> {
            jdbc.sql("SELECT set_config('moaum.actor_office', 'applicant', true)").query().listOfRows();
            return jdbc.sql("""
                    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
                    VALUES (gen_random_uuid(), :s, gen_random_uuid(), '210912345678AB', 'closed.window@example.com', '08012345678', 'x')
                    """).param("s", SESSION).update();
        })).hasMessageContaining("APPLICATION_CLOSED");

        // reopened: registration reaches the list again, and the history has both acts with their reasons
        ResponseEntity<Map> reopened = act(PUTME, SESSION, "REOPEN", "integration test: registration reopened");
        assertThat(reopened.getStatusCode().value()).isEqualTo(200);
        assertThat(((Map) reopened.getBody().get("after")).get("state")).isEqualTo("OPEN");
        assertThat(register().getBody().get("code")).isNotEqualTo("APPLICATION_CLOSED");
        assertThat(((Map) publicWindows(SESSION).get("postUtme")).get("status")).isEqualTo("OPEN");
        ResponseEntity<Map> page = it.get(ict, WINDOWS + "/applications?session=" + SESSION);
        assertThat(page.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> windows = (List<Map<String, Object>>) page.getBody().get("windows");
        Map<String, Object> w = windows.stream().filter(x -> PUTME.equals(x.get("type"))).findFirst().orElseThrow();
        assertThat(w.get("state")).isEqualTo("OPEN");
        assertThat(w.get("path")).isEqualTo("/apply");
        List<Map<String, Object>> events = (List<Map<String, Object>>) w.get("events");
        assertThat(events).extracting(e -> e.get("action")).containsExactly("REOPEN", "CLOSE");
        assertThat(events.get(1).get("reason")).isEqualTo("integration test: registration closed");
        assertThat(events.get(1).get("previous_state")).isEqualTo("OPEN (default)");
    }

    @Test
    void postgraduateApplicationIsRefusedWhileClosed() {
        assertThat(((Map) publicWindows(null).get("postgraduate")).get("status")).isEqualTo("OPEN");
        assertThat(act(PG, pgSession, "CLOSE", "integration test: postgraduate application closed").getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> refused = pgApply();
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody().get("code")).isEqualTo("APPLICATION_CLOSED");
        Map<String, Object> pg = (Map<String, Object>) publicWindows(null).get("postgraduate");
        assertThat(pg.get("status")).isEqualTo("CLOSED");
        assertThat(pg.get("session")).isEqualTo(pgSession);
        assertThat(String.valueOf(pg.get("applicationUrl"))).endsWith("/pg/apply");
        assertThat(String.valueOf(pg.get("message"))).contains("POSTGRADUATE APPLICATION IS CURRENTLY CLOSED");
        // the backstop, straight into the database as the applicant
        assertThatThrownBy(() -> it.db(() -> {
            jdbc.sql("SELECT set_config('moaum.actor_office', 'applicant', true)").query().listOfRows();
            return jdbc.sql("""
                    INSERT INTO admissions.pg_application (applicant_id, session, application_no, programme_code, entry_level)
                    VALUES (gen_random_uuid(), :s, 'PG/CLOSED/2109', 'NOSUCH', 800)
                    """).param("s", pgSession).update();
        })).hasMessageContaining("APPLICATION_CLOSED");
        // reopened: the door answers something other than the closed window
        assertThat(act(PG, pgSession, "REOPEN", "integration test: postgraduate application reopened").getStatusCode().value()).isEqualTo(200);
        assertThat(pgApply().getBody().get("code")).isNotEqualTo("APPLICATION_CLOSED");
    }

    @Test
    void scheduledWindowIsNotOpenYetAndTheMessageIsTheDirectorsPlainText() {
        // scheduled for later: not open, and the public endpoint carries the opening
        ResponseEntity<Map> scheduled = it.call(ict, HttpMethod.POST, WINDOWS + "/" + PUTME,
                Map.of("session", SESSION, "action", "SCHEDULE", "opensAt", "2109-10-01T08:00:00Z", "closesAt", "2109-11-30T23:00:00Z", "lateFeeEnabled", false));
        assertThat(scheduled.getStatusCode().value()).isEqualTo(200);
        assertThat(((Map) scheduled.getBody().get("after")).get("state")).isEqualTo("SCHEDULED");
        Map<String, Object> putme = (Map<String, Object>) publicWindows(SESSION).get("postUtme");
        assertThat(putme.get("status")).isEqualTo("SCHEDULED");
        assertThat(String.valueOf(putme.get("opensAt"))).startsWith("2109-10-01");
        ResponseEntity<Map> refused = register();
        assertThat(refused.getBody().get("code")).isEqualTo("APPLICATION_CLOSED");
        assertThat(String.valueOf(((Map) refused.getBody().get("remedy")).get("message"))).contains("opens on");

        // a late period or a semester is not an application window's to have
        ResponseEntity<Map> late = it.call(ict, HttpMethod.POST, WINDOWS + "/" + PUTME,
                Map.of("session", SESSION, "action", "EXTEND", "lateUntil", "2109-12-31T23:00:00Z", "lateFeeEnabled", true));
        assertThat(late.getStatusCode().value()).isEqualTo(422);
        assertThat(late.getBody().get("code")).isEqualTo("WINDOW_APPLICATION_SESSION");

        // the closure message: tags stripped, paragraphs kept, blank refused, read back by the public while not open
        ResponseEntity<Map> saved = it.call(ict, HttpMethod.POST, WINDOWS + "/applications/" + PUTME + "/message?session=" + SESSION,
                Map.of("message", "  Registration opens <b>1 October</b>.\n\nWatch the website.  "));
        assertThat(saved.getStatusCode().value()).isEqualTo(200);
        assertThat(message(PUTME)).isEqualTo("Registration opens 1 October.\n\nWatch the website.");
        putme = (Map<String, Object>) publicWindows(SESSION).get("postUtme");
        assertThat(putme.get("message")).isEqualTo("Registration opens 1 October.\n\nWatch the website.");
        assertThat(register().getBody().get("detail")).isEqualTo("Registration opens 1 October.\n\nWatch the website.");
        ResponseEntity<Map> blank = it.call(ict, HttpMethod.POST, WINDOWS + "/applications/" + PUTME + "/message", Map.of("message", "<p></p>"));
        assertThat(blank.getStatusCode().value()).isEqualTo(422);
        assertThat(message(PUTME)).isEqualTo("Registration opens 1 October.\n\nWatch the website.");
        List<Map<String, Object>> events = (List<Map<String, Object>>) it.get(ict, WINDOWS + "/history?session=" + SESSION + "&type=" + PUTME).getBody().get("events");
        assertThat(events).extracting(e -> e.get("action")).contains("SCHEDULE");
    }

    @Test
    void onlyTheDirectorActs() {
        assertThat(it.call(registrar, HttpMethod.POST, WINDOWS + "/" + PUTME, Map.of("session", SESSION, "action", "CLOSE", "reason", "not mine")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(registrar, WINDOWS + "/applications").getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(registrar, HttpMethod.POST, WINDOWS + "/applications/" + PUTME + "/message", Map.of("message", "not mine")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.anon(HttpMethod.GET, WINDOWS + "/applications", null).getStatusCode().value()).isEqualTo(401);
        assertThat(((Map) publicWindows(SESSION).get("postUtme")).get("status")).isEqualTo("OPEN");
    }

    /** V378: Post-UTME is filed under the intake session — the first planned session after the current one — while JUPEB, naming
     *  no session of its own, keeps the University's current one. Set up in a transaction that is rolled back, so the calendar
     *  every other test reads is left as it was. */
    @Test
    void postUtmeIsFiledUnderTheIntakeSessionNotTheCurrentOne() {
        // the public page, the login page and the website read what the database says, with no session named
        String intake = jdbc.sql("SELECT policy.intake_session()").query(String.class).single();
        assertThat(((Map) publicWindows(null).get("postUtme")).get("session")).isEqualTo(intake);

        TransactionTemplate tx = new TransactionTemplate(transactions);
        AuditContextHolder.with(new AuditContext(UUID.randomUUID(), "ict", "integration test: the intake session", null, null), () -> tx.execute(status -> {
            status.setRollbackOnly();
            jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED', completed_at = now() WHERE state = 'CURRENT'").update();
            jdbc.sql("""
                    INSERT INTO policy.academic_session (id, name, starts_on, ends_on, state, senate_minute) VALUES
                      (gen_random_uuid(), '2139/2140', '2139-10-01', '2140-08-31', 'PLANNED', NULL),
                      (gen_random_uuid(), '2141/2142', '2141-10-01', '2142-09-30', 'CURRENT', 'SEN/TEST/2141/01'),
                      (gen_random_uuid(), '2142/2143', '2142-09-01', '2143-08-31', 'PLANNED', NULL),
                      (gen_random_uuid(), '2143/2144', '2143-10-01', '2144-08-31', 'PLANNED', NULL)
                    ON CONFLICT (name) DO NOTHING
                    """).update();
            // admitted into the next session, while the current one still runs (V377: 2142/2143 begins before 2141/2142 ends)
            assertThat(jdbc.sql("SELECT policy.application_session('POST_UTME_REGISTRATION')").query(String.class).single()).isEqualTo("2142/2143");
            assertThat(jdbc.sql("SELECT policy.university_current_session()").query(String.class).single()).isEqualTo("2141/2142");
            // JUPEB with no session named by its office falls back to the University's current session, as before
            jdbc.sql("UPDATE jupeb.setting SET current_session = NULL WHERE session = '*'").update();
            assertThat(jdbc.sql("SELECT policy.application_session('JUPEB_APPLICATION')").query(String.class).single()).isEqualTo("2141/2142");
            // nothing planned after the current session: the current one is the intake
            jdbc.sql("UPDATE policy.academic_session SET state = 'DRAFT' WHERE name IN ('2142/2143', '2143/2144')").update();
            assertThat(jdbc.sql("SELECT policy.application_session('POST_UTME_REGISTRATION')").query(String.class).single()).isEqualTo("2141/2142");
            return null;
        }));
        assertThat(jdbc.sql("SELECT policy.intake_session()").query(String.class).single()).isEqualTo(intake);
    }
}
