package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * V433 through the API: every call to the PAYDirect door is counted by its address; the door is kept to its address list only
 * once an address is listed and one of them has been seen at the door, and the last listed address is never removed while it
 * is kept; the silence watch judges by the door's own rhythm and tells the Directorate of ICT and the Bursary once per silence.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class PayDirectDoorIT {

    private static final String ASK = "<CustomerInformationRequest><CustReference>MOAUM-APP-000000-0000</CustReference></CustomerInformationRequest>";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    String ict;
    String tag;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        tag = Integer.toString(new Random().nextInt(900_000) + 100_000);
        ict = TestTokens.token(it.person("ZZPDD-ICT-" + tag, "ZZPDDICT"), List.of("ict"));
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
        // the door open and its list empty, whatever an earlier run left
        it.db(() -> {
            jdbc.sql("UPDATE finance.paydirect_setting SET restrict_addresses = false WHERE id").update();
            jdbc.sql("DELETE FROM finance.paydirect_allowed_address").update();
            return null;
        });
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> body(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(422);
        return String.valueOf(r.getBody().get("code"));
    }

    /** a knock on the one door as if from the address given: the edge in front of the test server writes the last entry */
    private ResponseEntity<String> knock(String from) {
        return open.post().uri("/api/v1/payments/paydirect/interswitch").header("X-Forwarded-For", from)
                .contentType(MediaType.TEXT_XML).body(ASK).retrieve().toEntity(String.class);
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> door() {
        return (Map<String, Object>) body(it.get(ict, "/api/v1/payments/paydirect")).get("door");
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> seen(Map<String, Object> door, String address) {
        return ((List<Map<String, Object>>) door.get("seen")).stream().filter(s -> address.equals(s.get("address"))).findFirst().orElse(null);
    }

    @SuppressWarnings("unchecked")
    @Test
    void theDoorCountsItsCallersAndIsKeptToItsListOnlyWithCare() {
        int n = new Random().nextInt(200) + 1;
        String liveA = "10.77." + n + "." + (n + 3);       // invented for this run, so "seen in the last seven days" starts clean
        String liveB = "10.78." + n + "." + (n + 5);
        try {
            // open: the knock is answered, and counted against its address
            assertThat(knock(liveA).getStatusCode().value()).isEqualTo(200);
            Map<String, Object> d = door();
            assertThat(d.get("restrict_addresses")).isEqualTo(false);
            assertThat(d.get("state")).isIn("NEVER", "OK", "QUIET", "SILENT");
            Map<String, Object> a = seen(d, liveA);
            assertThat(a).isNotNull();
            assertThat(((Number) a.get("calls")).intValue()).isGreaterThanOrEqualTo(1);
            assertThat(a.get("listed")).isEqualTo(false);
            // kept to the list: refused while nothing is listed, and while no listed address has been seen
            assertThat(code(it.call(ict, HttpMethod.PUT, "/api/v1/payments/paydirect/door", Map.of("restrict", true)))).isEqualTo("PAYDIRECT_NO_ADDRESS");
            assertThat(body(it.call(ict, HttpMethod.POST, "/api/v1/payments/paydirect/door/addresses", Map.of("address", liveB, "label", "Interswitch live 2"))).get("address")).isEqualTo(liveB);
            assertThat(code(it.call(ict, HttpMethod.PUT, "/api/v1/payments/paydirect/door", Map.of("restrict", true)))).isEqualTo("PAYDIRECT_ADDRESS_UNSEEN");
            body(it.call(ict, HttpMethod.POST, "/api/v1/payments/paydirect/door/addresses", Map.of("address", liveA, "label", "Interswitch live 1")));
            assertThat(body(it.call(ict, HttpMethod.PUT, "/api/v1/payments/paydirect/door", Map.of("restrict", true))).get("restrict_addresses")).isEqualTo(true);
            // kept: a stranger is refused and counted as refused; the listed address is answered
            assertThat(knock("203.0.113.9").getStatusCode().value()).isEqualTo(403);
            assertThat(knock(liveA).getStatusCode().value()).isEqualTo(200);
            d = door();
            assertThat(((Number) seen(d, "203.0.113.9").get("refused")).intValue()).isGreaterThanOrEqualTo(1);
            assertThat(seen(d, liveA).get("listed")).isEqualTo(true);
            assertThat(((List<Map<String, Object>>) d.get("addresses")).stream().map(x -> x.get("address"))).contains(liveA, liveB);
            // the last listed address stays while the door is kept
            assertThat(body(it.call(ict, HttpMethod.POST, "/api/v1/payments/paydirect/door/addresses/remove", Map.of("address", liveB))).get("removed")).isEqualTo(1);
            assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/payments/paydirect/door/addresses/remove", Map.of("address", liveA)))).isEqualTo("PAYDIRECT_LAST_ADDRESS");
            assertThat(code(it.call(ict, HttpMethod.POST, "/api/v1/payments/paydirect/door/addresses", Map.of("address", "not an address")))).isEqualTo("PAYDIRECT_ADDRESS_INVALID");
            // a student has no say over the door
            String student = TestTokens.token(it.student("ITPDD" + tag, "C00023", "MOAUM/ADM/87/06" + tag.substring(0, 4), null, 100), List.of("student"));
            assertThat(it.call(student, HttpMethod.PUT, "/api/v1/payments/paydirect/door", Map.of("restrict", false)).getStatusCode().value()).isIn(403, 422);
        } finally {
            // the door open again for every other test
            it.call(ict, HttpMethod.PUT, "/api/v1/payments/paydirect/door", Map.of("restrict", false));
            it.call(ict, HttpMethod.POST, "/api/v1/payments/paydirect/door/addresses/remove", Map.of("address", liveA));
        }
        assertThat(door().get("restrict_addresses")).isEqualTo(false);
        assertThat(knock("203.0.113.9").getStatusCode().value()).isEqualTo(200);
    }

    /** the watch's judgement, proved in one transaction that is undone: the shared log is left as it was */
    @Test
    void theWatchTellsIctAndTheBursaryOncePerSilenceJudgedByTheDoorsOwnRhythm() {
        UUID bursar = it.person("ZZPDD-BURSAR-" + tag, "ZZPDDBURSAR");
        it.db(() -> {
            jdbc.sql("UPDATE iam.person SET email = :e WHERE id = :p").param("e", "pdd-bursar-" + tag + "@example.test").param("p", bursar).update();
            jdbc.sql("INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from) VALUES (gen_random_uuid(), :p, 'bursar', 'institution', NULL, 'IT', :p, current_date)")
                    .param("p", bursar).update();
            return null;
        });
        class Undone extends RuntimeException { }
        Map<String, Object> out = new HashMap<>();
        try {
            it.db(() -> {
                // anything newer on the log moved out of the way (undone with the rest); one call ten hours ago: quiet, but no rhythm to judge by
                jdbc.sql("UPDATE finance.gateway_event SET received_at = received_at - interval '60 days' WHERE gateway = 'paydirect' AND received_at > now() - interval '10 hours'").update();
                jdbc.sql("UPDATE finance.paydirect_setting SET watch_enabled = true, silence_hours = 6, last_alert_seen_at = NULL WHERE id").update();
                jdbc.sql("INSERT INTO finance.gateway_event (gateway, source, event, reference, signature_ok, outcome, received_at) VALUES ('paydirect', 'VALIDATE', 'validate', 'IT-PDD-0', true, 'IGNORED', now() - interval '10 hours')").update();
                out.put("quietState", jdbc.sql("SELECT state FROM finance.paydirect_door_status()").query(String.class).single());
                out.put("quietTold", jdbc.sql("SELECT finance.watch_paydirect()").query(Integer.class).single());
                // twenty-four more, two hours apart before it: a rhythm of two hours, the silence of ten is reported, once
                jdbc.sql("INSERT INTO finance.gateway_event (gateway, source, event, reference, signature_ok, outcome, received_at) "
                        + "SELECT 'paydirect', CASE WHEN i % 2 = 0 THEN 'VALIDATE' ELSE 'WEBHOOK' END, 'validate', 'IT-PDD-' || i, true, 'IGNORED', now() - interval '10 hours' - make_interval(hours => 2 * i) FROM generate_series(1, 24) i").update();
                out.put("status", jdbc.sql("SELECT state, calls_14d, longest_gap_hours, threshold_hours FROM finance.paydirect_door_status()").query().singleRow());
                out.put("told", jdbc.sql("SELECT finance.watch_paydirect()").query(Integer.class).single());
                out.put("again", jdbc.sql("SELECT finance.watch_paydirect()").query(Integer.class).single());
                out.put("toBursar", jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_id = :p AND template_key = 'PAYDIRECT_SILENT'").param("p", bursar).query(Integer.class).single());
                out.put("subject", jdbc.sql("SELECT subject FROM platform.notice WHERE about_id = :p AND template_key = 'PAYDIRECT_SILENT' AND channel = 'EMAIL'").param("p", bursar).query(String.class).single());
                // a call arrives: within its rhythm again, nothing more said
                jdbc.sql("INSERT INTO finance.gateway_event (gateway, source, event, reference, signature_ok, outcome) VALUES ('paydirect', 'WEBHOOK', 'notification', 'IT-PDD-NOW', true, 'IGNORED')").update();
                out.put("afterState", jdbc.sql("SELECT state FROM finance.paydirect_door_status()").query(String.class).single());
                out.put("afterTold", jdbc.sql("SELECT finance.watch_paydirect()").query(Integer.class).single());
                throw new Undone();
            });
        } catch (Undone undone) {
            // as intended
        }
        assertThat(out.get("quietState")).isEqualTo("QUIET");
        assertThat(out.get("quietTold")).isEqualTo(0);
        @SuppressWarnings("unchecked")
        Map<String, Object> status = (Map<String, Object>) out.get("status");
        assertThat(status.get("state")).isEqualTo("SILENT");
        assertThat(((Number) status.get("calls_14d")).intValue()).isEqualTo(25);
        assertThat(((Number) status.get("longest_gap_hours")).doubleValue()).isEqualTo(2.0);
        assertThat(((Number) status.get("threshold_hours")).doubleValue()).isEqualTo(6.0);
        assertThat(((Number) out.get("told")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(out.get("again")).isEqualTo(0);
        assertThat(out.get("toBursar")).isEqualTo(2);    // e-mail and the portal
        assertThat(out.get("subject")).isEqualTo("The Quickteller payment door has gone quiet");
        assertThat(out.get("afterState")).isEqualTo("OK");
        assertThat(out.get("afterTold")).isEqualTo(0);
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM finance.gateway_event WHERE reference LIKE 'IT-PDD-%'").query(Integer.class).single())).isEqualTo(0);
    }

    /** the settings and the watch through the API: the switch, the hours, "check now" by the office; the Bursary may check, not set */
    @Test
    void theOfficeSetsTheWatchAndRunsItNow() {
        Map<String, Object> set = body(it.call(ict, HttpMethod.PUT, "/api/v1/payments/paydirect/door", Map.of("watch", false, "silenceHours", 12)));
        assertThat(set.get("watch_enabled")).isEqualTo(false);
        assertThat(((Number) set.get("silence_hours")).intValue()).isEqualTo(12);
        assertThat(door().get("watch_enabled")).isEqualTo(false);
        Map<String, Object> ran = body(it.call(ict, HttpMethod.POST, "/api/v1/payments/paydirect/door/watch", Map.of()));
        assertThat(((Number) ran.get("told")).intValue()).isEqualTo(0);   // the watch is off
        assertThat(ran.get("door")).isNotNull();
        String bursar = TestTokens.token(it.person("ZZPDD-BUR-" + tag, "ZZPDDBUR"), List.of("bursar"));
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/payments/paydirect/door/watch", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/payments/paydirect/door", Map.of("watch", true)).getStatusCode().value()).isIn(403, 422);
        Map<String, Object> back = body(it.call(ict, HttpMethod.PUT, "/api/v1/payments/paydirect/door", Map.of("watch", true, "silenceHours", 6)));
        assertThat(back.get("watch_enabled")).isEqualTo(true);
        assertThat(((Number) back.get("silence_hours")).intValue()).isEqualTo(6);
    }
}
