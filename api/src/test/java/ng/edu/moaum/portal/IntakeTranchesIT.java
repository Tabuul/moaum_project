package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.client.RestClient;

/**
 * V722: the register intake in one pass and in tranches.
 *
 * <p>Five invented admitted candidates stand on a committed CAPS list of a session of the test's own. The Academic Office
 * brings them onto the register two at a time: the first call brings two (by surname) and says three remain, each of the two
 * with an academic position written by the run's one refresh; the plain call brings the rest and says none remain; a further
 * call brings nobody. A reader office is refused.
 *
 * <p>Needs a database the migrations have been applied to: set DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class IntakeTranchesIT {

    /** A session of the test's own, which nobody else admits into. */
    static final String SESSION = "2143/2144";
    static final String PATH = "/api/v1/student/intake/2143/2144";
    static final String SURNAME = "INTAKETRANCHE";
    static final List<String> NAMES = List.of("DELTA", "ALPHA", "ECHO", "CHARLIE", "BRAVO");

    @Value("${local.server.port}")
    int port;

    @Autowired
    JdbcClient jdbc;

    @Autowired
    PlatformTransactionManager transactions;

    RestClient client;
    UUID academic = UUID.randomUUID();
    String token = TestTokens.token(academic, List.of("academic"));
    String bursar = TestTokens.token(UUID.randomUUID(), List.of("bursar"));

    @BeforeEach
    void setUp() {
        client = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { })
                .build();
        onTheList();
    }

    /** The five candidates, admitted on a committed list; a previous run's students and candidates taken away first. */
    void onTheList() {
        TransactionTemplate tx = new TransactionTemplate(transactions);
        AuditContext context = new AuditContext(academic, "academic",
                "IntakeTranchesIT: five invented admitted candidates for " + SESSION, null, null);
        AuditContextHolder.with(context, () -> tx.execute(status -> {
            jdbc.sql("INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), :s, date '2143-10-01', date '2144-08-31') ON CONFLICT (name) DO NOTHING")
                    .param("s", SESSION).update();
            jdbc.sql("DELETE FROM people.academic_position WHERE student_id IN (SELECT id FROM people.student WHERE entry_session = :s)").param("s", SESSION).update();
            jdbc.sql("DELETE FROM people.biodata WHERE student_id IN (SELECT id FROM people.student WHERE entry_session = :s)").param("s", SESSION).update();
            jdbc.sql("DELETE FROM people.student WHERE entry_session = :s").param("s", SESSION).update();
            jdbc.sql("DELETE FROM admissions.candidate WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("DELETE FROM admissions.caps_row WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("DELETE FROM admissions.caps_batch WHERE session = :s").param("s", SESSION).update();
            UUID batch = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office, committed_at)
                    VALUES (:b, :s, 'CAPS_DOWNLOAD', 'UTME', '\\x2143'::bytea, 5, current_date, :who, 'academic', now())
                    """).param("b", batch).param("s", SESSION).param("who", academic).update();
            for (int i = 0; i < NAMES.size(); i++) {
                UUID row = UUID.randomUUID();
                String reg = "21430000000" + i + "ZZ";
                jdbc.sql("""
                        INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode)
                        VALUES (:r, :b, :s, :reg, '{}'::jsonb, :surname, 'Invented', 'C00023', 200, 'UTME')
                        """).param("r", row).param("b", batch).param("s", SESSION).param("reg", reg).param("surname", SURNAME + NAMES.get(i)).update();
                jdbc.sql("""
                        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
                        VALUES (gen_random_uuid(), :s, :reg, :surname, 'Invented', (SELECT name FROM ref.programme WHERE code = 'C00023'), 'UTME', 100, 'ADMITTED', :r)
                        """).param("s", SESSION).param("reg", reg).param("surname", SURNAME + NAMES.get(i)).param("r", row).update();
            }
            return null;
        }));
    }

    @Test
    @SuppressWarnings("rawtypes")
    void theAdmittedAreBroughtOntoTheRegisterInTranchesWithTheirPositionsWrittenOnce() {
        // a tranche of two: Alpha and Bravo by surname; three remain
        ResponseEntity<Map> first = post(PATH + "?limit=2");
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
        assertThat(first.getBody().get("session")).isEqualTo(SESSION);
        assertThat(first.getBody().get("broughtOnto")).isEqualTo(2);
        assertThat(first.getBody().get("remaining")).isEqualTo(3);
        assertThat(taken()).containsExactly(SURNAME + "ALPHA", SURNAME + "BRAVO");
        assertThat(positions()).isEqualTo(2L);

        // the rest, with no limit: Charlie, Delta, Echo; none remain, every one with a position and an admission number of the session
        ResponseEntity<Map> rest = post(PATH);
        assertThat(rest.getStatusCode().value()).as(String.valueOf(rest.getBody())).isEqualTo(200);
        assertThat(rest.getBody().get("broughtOnto")).isEqualTo(3);
        assertThat(rest.getBody().get("remaining")).isEqualTo(0);
        assertThat(taken()).containsExactly(SURNAME + "ALPHA", SURNAME + "BRAVO", SURNAME + "CHARLIE", SURNAME + "DELTA", SURNAME + "ECHO");
        assertThat(positions()).isEqualTo(5L);
        assertThat(jdbc.sql("SELECT count(*) FROM people.student WHERE entry_session = :s AND admission_no !~ '^MOAUM/ADM/43/[0-9]{6}$'")
                .param("s", SESSION).query(Long.class).single()).isEqualTo(0L);

        // a further call brings nobody; a limit under one is no limit
        ResponseEntity<Map> none = post(PATH + "?limit=0");
        assertThat(none.getStatusCode().value()).as(String.valueOf(none.getBody())).isEqualTo(200);
        assertThat(none.getBody().get("broughtOnto")).isEqualTo(0);
        assertThat(none.getBody().get("remaining")).isEqualTo(0);

        // the Bursary does not bring anyone onto the register
        ResponseEntity<Map> refused = client.post().uri(PATH + "?limit=2").header(HttpHeaders.AUTHORIZATION, "Bearer " + bursar)
                .header("X-Reason", "IntakeTranchesIT").contentType(MediaType.APPLICATION_JSON).body(Map.of()).retrieve().toEntity(Map.class);
        assertThat(refused.getStatusCode().value()).isEqualTo(403);
    }

    /** Two runs of the same session at once: the second waits for the first (the advisory lock per session) and takes what is
     *  still off the register — between them the five, none twice, no refusal. */
    @Test
    @SuppressWarnings("rawtypes")
    void twoRunsOfOneSessionAtOnceTakeTurnsAndBringEveryoneOnOnce() throws Exception {
        java.util.concurrent.ExecutorService pool = java.util.concurrent.Executors.newFixedThreadPool(2);
        try {
            List<java.util.concurrent.Future<ResponseEntity<Map>>> runs = List.of(
                    pool.submit(() -> post(PATH + "?limit=3")), pool.submit(() -> post(PATH + "?limit=3")));
            int brought = 0;
            for (java.util.concurrent.Future<ResponseEntity<Map>> run : runs) {
                ResponseEntity<Map> r = run.get(2, java.util.concurrent.TimeUnit.MINUTES);
                assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
                brought += ((Number) r.getBody().get("broughtOnto")).intValue();
            }
            assertThat(brought).isEqualTo(5);
        } finally {
            pool.shutdownNow();
        }
        assertThat(taken()).containsExactly(SURNAME + "ALPHA", SURNAME + "BRAVO", SURNAME + "CHARLIE", SURNAME + "DELTA", SURNAME + "ECHO");
        assertThat(positions()).isEqualTo(5L);
        assertThat(post(PATH).getBody().get("remaining")).isEqualTo(0);
    }

    List<String> taken() {
        return jdbc.sql("SELECT surname FROM people.student WHERE entry_session = :s ORDER BY admission_no").param("s", SESSION).query(String.class).list();
    }

    long positions() {
        return jdbc.sql("""
                SELECT count(*) FROM people.academic_position ap JOIN people.student s ON s.id = ap.student_id
                 WHERE s.entry_session = :s AND ap.entry_session = :s
                """).param("s", SESSION).query(Long.class).single();
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> post(String path) {
        return client.post().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                .header("X-Reason", "IntakeTranchesIT").contentType(MediaType.APPLICATION_JSON).body(Map.of())
                .retrieve().toEntity(Map.class);
    }
}
