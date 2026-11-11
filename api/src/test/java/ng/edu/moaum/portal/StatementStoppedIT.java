package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import java.sql.Statement;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import javax.sql.DataSource;

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
import org.springframework.web.client.RestClient;

/**
 * 11 November 2026: a statement the database stops is answered with what stopped it and kept for ICT's Slow statements page.
 *
 * <p>Made real, not mocked, with a read limit of 1.5 s for this context: a screen's read waits on a table the test holds locked
 * and is cut at the portal's limit (PORTAL_READ_LIMIT, a READ under 1.5 s); the intake, a write, waits on the session's intake
 * lock the test holds and is stopped by a cancel request (CANCEL_REQUEST, a WRITE the portal did not limit). ICT then reads both,
 * newest first, by their routes, with the database's time limits and where each was set; the Bursary may not.
 *
 * <p>Needs a database the migrations have been applied to: set DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET, "moaum.db.request-read-timeout-ms=1500"})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class StatementStoppedIT {

    /** a session of the test's own, never admitted into */
    static final String SESSION = "2147/2148";

    @Value("${local.server.port}")
    int port;

    @Autowired
    DataSource dataSource;

    @Autowired
    JdbcClient jdbc;

    RestClient client;
    String ict = TestTokens.token(UUID.randomUUID(), List.of("ict"));
    String academic = TestTokens.token(UUID.randomUUID(), List.of("academic"));
    String bursar = TestTokens.token(UUID.randomUUID(), List.of("bursar"));

    @BeforeEach
    void setUp() {
        client = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> { })
                .build();
    }

    @Test
    @SuppressWarnings({"rawtypes", "unchecked"})
    void aStoppedStatementNamesWhatStoppedItAndIctReadsIt() throws Exception {
        // 1 · a screen's read waits on a table held locked and is cut at the portal's 1.5 s limit
        try (Connection holder = dataSource.getConnection()) {
            holder.setAutoCommit(false);
            try (Statement s = holder.createStatement()) {
                s.execute("LOCK TABLE platform.statement_screen IN ACCESS EXCLUSIVE MODE");
            }
            ResponseEntity<Map> read = get(ict, "ict", "/api/v1/platform/slow-statements");
            holder.rollback();
            assertThat(read.getStatusCode().value()).as(String.valueOf(read.getBody())).isEqualTo(503);
            assertThat(read.getBody()).containsEntry("code", "QUERY_TOO_LONG").containsEntry("cause", "PORTAL_READ_LIMIT")
                    .containsEntry("title", "This screen took too long to read");
            assertThat((String) read.getBody().get("detail")).contains("(1.5 s)");
        }

        // 2 · the intake, a write, waits on the session's intake lock held here and is stopped by a cancel request
        ExecutorService pool = Executors.newSingleThreadExecutor();
        try (Connection holder = dataSource.getConnection()) {
            holder.setAutoCommit(true);
            try (Statement s = holder.createStatement()) {
                s.execute("SELECT pg_advisory_lock(hashtext('people.intake:" + SESSION + "'))");
            }
            Future<ResponseEntity<Map>> intake = pool.submit(() -> client.post().uri("/api/v1/student/intake/" + SESSION + "?limit=10")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + academic).header("X-Active-Office", "academic")
                    .header("X-Reason", "StatementStoppedIT").contentType(MediaType.APPLICATION_JSON).body(Map.of())
                    .retrieve().toEntity(Map.class));
            Integer waiting = null;
            for (int i = 0; i < 300 && waiting == null; i++) {
                waiting = jdbc.sql("""
                        SELECT pid FROM pg_stat_activity
                         WHERE wait_event_type = 'Lock' AND wait_event = 'advisory' AND query LIKE '%intake_tranche%' AND pid <> pg_backend_pid()
                         LIMIT 1
                        """).query(Integer.class).optional().orElse(null);
                if (waiting == null) Thread.sleep(100);
            }
            assertThat(waiting).as("the intake waiting on the session's lock").isNotNull();
            jdbc.sql("SELECT pg_cancel_backend(:pid)").param("pid", waiting).query(Boolean.class).single();
            ResponseEntity<Map> write = intake.get(2, TimeUnit.MINUTES);
            assertThat(write.getStatusCode().value()).as(String.valueOf(write.getBody())).isEqualTo(503);
            assertThat(write.getBody()).containsEntry("code", "QUERY_CANCELLED").containsEntry("cause", "CANCEL_REQUEST")
                    .containsEntry("title", "This was stopped before it finished");
            try (Statement s = holder.createStatement()) {
                s.execute("SELECT pg_advisory_unlock(hashtext('people.intake:" + SESSION + "'))");
            }
        } finally {
            pool.shutdownNow();
        }

        // 3 · ICT reads both, newest first, with the database's time limits and where each was set
        ResponseEntity<Map> limits = get(ict, "ict", "/api/v1/platform/database-limits");
        assertThat(limits.getStatusCode().value()).as(String.valueOf(limits.getBody())).isEqualTo(200);
        List<Map<String, Object>> settings = (List<Map<String, Object>>) limits.getBody().get("settings");
        assertThat(settings).extracting(m -> m.get("name")).startsWith("statement_timeout", "lock_timeout");
        assertThat(settings.get(0)).containsKeys("setting", "unit", "source", "reset_val", "boot_val");
        // read outside any transaction: the portal's 1.5 s read limit is not mistaken for the database's
        assertThat(settings.get(0).get("source")).isNotEqualTo("session");
        assertThat((String) limits.getBody().get("reading")).contains("The portal limits a screen's read to 1.5 s; it places no limit on a write.");
        assertThat((Map<String, Object>) limits.getBody().get("portal")).containsEntry("readLimitMs", 1500);
        List<Map<String, Object>> stopped = (List<Map<String, Object>>) limits.getBody().get("stopped");
        assertThat(stopped).hasSizeGreaterThanOrEqualTo(2);
        assertThat(stopped.get(0)).containsEntry("cause", "CANCEL_REQUEST").containsEntry("transaction", "WRITE")
                .containsEntry("route", "/api/v1/student/intake/{session}/{year}").containsEntry("method", "POST")
                .containsEntry("office", "academic").containsEntry("databaseSaid", "canceling statement due to user request");
        assertThat(stopped.get(0).get("portalLimitMs")).isNull();
        assertThat(stopped.get(1)).containsEntry("cause", "PORTAL_READ_LIMIT").containsEntry("transaction", "READ")
                .containsEntry("route", "/api/v1/platform/slow-statements").containsEntry("portalLimitMs", 1500).containsEntry("office", "ict");
        assertThat(((Number) stopped.get(1).get("ranForMs")).longValue()).isGreaterThanOrEqualTo(1400L);

        // the Bursary does not read the database's settings
        assertThat(get(bursar, "bursar", "/api/v1/platform/database-limits").getStatusCode().value()).isEqualTo(403);
    }

    @SuppressWarnings("rawtypes")
    ResponseEntity<Map> get(String token, String office, String path) {
        return client.get().uri(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + token).header("X-Active-Office", office)
                .retrieve().toEntity(Map.class);
    }
}
