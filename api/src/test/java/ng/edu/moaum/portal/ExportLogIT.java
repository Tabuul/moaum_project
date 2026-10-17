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
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V523: the export log through its doors. A lecturer's export is recorded for the lecturer and the office of the request, with the
 * report, rows, filters, screen and serial; a format the log does not keep is refused; Internal Audit finds it by its serial, and
 * neither the lecturer nor the Students Account Officer reads the log. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ExportLogIT {

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

    @Test
    void anExportIsRecordedForWhoeverMadeItAndInternalAuditFindsItByItsSerial() {
        UUID lecturer = UUID.randomUUID();
        String token = TestTokens.token(lecturer, List.of("lecturer"));
        String serial = "MOAUM/IT/" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        ResponseEntity<Map> logged = it.call(token, HttpMethod.POST, "/api/v1/exports", Map.of("report", "Class list — BIO 101", "format", "XLSX", "rows", 42,
                "filters", Map.of("Session", "2025/2026", "Course", "BIO 101"), "screen", "/lecturer/classes?course=BIO%20101", "serial", serial));
        assertThat(logged.getStatusCode().value()).as(String.valueOf(logged.getBody())).isEqualTo(200);

        Map<String, Object> row = jdbc.sql("SELECT person_id, office, report, format, row_count, filters->>'Course' AS course, screen FROM platform.export_log WHERE serial = :s")
                .param("s", serial).query().singleRow();
        assertThat(row).containsEntry("person_id", lecturer).containsEntry("office", "lecturer").containsEntry("report", "Class list — BIO 101")
                .containsEntry("format", "XLSX").containsEntry("row_count", 42).containsEntry("course", "BIO 101");
        assertThat(jdbc.sql("SELECT count(*) FROM audit.entries WHERE subject_type = 'platform.export_log' AND actor_id = :a").param("a", lecturer).query(Long.class).single())
                .isEqualTo(1L);

        // a format the log does not keep, and nobody signed in
        ResponseEntity<Map> csv = it.call(token, HttpMethod.POST, "/api/v1/exports", Map.of("report", "Class list", "format", "DOCX", "rows", 1));
        assertThat(csv.getStatusCode().value()).isEqualTo(422);
        assertThat(csv.getBody()).containsEntry("code", "EXPORT_LOG_FORMAT");
        assertThat(it.anon(HttpMethod.POST, "/api/v1/exports", Map.of("report", "Class list", "format", "XLSX", "rows", 1)).getStatusCode().value()).isEqualTo(401);

        // Internal Audit finds it; the lecturer and the Students Account Officer do not read the log
        ResponseEntity<Map> found = it.get(ItSupport.token("audit"), u -> u.path("/api/v1/exports").queryParam("q", serial).build());
        assertThat(found.getStatusCode().value()).as(String.valueOf(found.getBody())).isEqualTo(200);
        assertThat(((Number) found.getBody().get("total")).intValue()).isEqualTo(1);
        Map<String, Object> first = ((List<Map<String, Object>>) found.getBody().get("rows")).getFirst();
        assertThat(first).containsEntry("report", "Class list — BIO 101").containsEntry("office", "lecturer").containsEntry("serial", serial);
        assertThat(it.get(ItSupport.token("deputyaudit"), "/api/v1/exports?format=XLSX").getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(token, "/api/v1/exports").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(ItSupport.token("studentaccounts"), "/api/v1/exports").getStatusCode().value()).isEqualTo(403);
    }

    @Test
    void aLargeExportIsMarkedUnusualAndOnlyInternalAuditOrSuperSetsTheWatch() {
        String audit = ItSupport.token("audit");
        Map<String, Object> watch = (Map<String, Object>) it.get(audit, "/api/v1/exports/watch").getBody();
        int large = ((Number) watch.get("large_rows")).intValue();
        String serial = "MOAUM/IT/" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        String lecturer = TestTokens.token(UUID.randomUUID(), List.of("lecturer"));
        assertThat(it.call(lecturer, HttpMethod.POST, "/api/v1/exports", Map.of("report", "Every class list", "format", "PDF", "rows", large + 1, "serial", serial))
                .getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> unusual = it.get(audit, u -> u.path("/api/v1/exports").queryParam("q", serial).queryParam("unusual", "true").build());
        assertThat(((Number) unusual.getBody().get("total")).intValue()).isEqualTo(1);
        assertThat(((List<Map<String, Object>>) unusual.getBody().get("rows")).getFirst()).containsEntry("large", true).containsEntry("format", "PDF");

        // the watch: the Deputy Director of Audit reads it, does not set it; Internal Audit sets it (and it is put back)
        Map<String, Object> same = Map.of("enabled", watch.get("enabled"), "largeRows", large, "burstCount", watch.get("burst_count"), "burstMinutes", watch.get("burst_minutes"));
        assertThat(it.get(ItSupport.token("deputyaudit"), "/api/v1/exports/watch").getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(ItSupport.token("deputyaudit"), HttpMethod.PUT, "/api/v1/exports/watch", same).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.PUT, "/api/v1/exports/watch", same).getStatusCode().value()).isEqualTo(403);
        Map<String, Object> raised = new java.util.HashMap<>(same);
        raised.put("largeRows", large + 1000);
        ResponseEntity<Map> set = it.call(audit, HttpMethod.PUT, "/api/v1/exports/watch", raised);
        try {
            assertThat(set.getStatusCode().value()).as(String.valueOf(set.getBody())).isEqualTo(200);
            assertThat(((Number) set.getBody().get("large_rows")).intValue()).isEqualTo(large + 1000);
            assertThat(set.getBody()).containsEntry("updated_office", "audit");
        } finally {
            assertThat(it.call(audit, HttpMethod.PUT, "/api/v1/exports/watch", same).getStatusCode().value()).isEqualTo(200);
        }
    }
}
