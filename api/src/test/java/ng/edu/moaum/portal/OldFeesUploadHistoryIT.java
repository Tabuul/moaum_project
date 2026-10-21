package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

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

/**
 * V609: Old Fees History's upload history. The Bursary's file is loaded as an upload — opened with its name and what it states, each
 * part kept (a part sent again adds only what it newly records); the officer may not open one and another Bursary officer may not
 * load its parts; the old door still logs, its parts gathered into one upload; a start over is logged with the payments it deleted;
 * the history is queried by how, the session, the day, the person and the file, with each upload's parts and payments. Needs
 * DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class OldFeesUploadHistoryIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String ses;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @AfterEach
    void clean() {
        if (ses != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", ses).update());
    }

    private static Map<String, Object> row(String number, String session, String amount, String paidOn, String payref) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("matric", number);
        r.put("session", session);
        r.put("semester", "First");
        r.put("amount", amount);
        r.put("purpose", "SCHOOL FEES");
        r.put("paidOn", paidOn);
        r.put("receiptNo", payref);
        r.put("channel", "Interswitch");
        return r;
    }

    private static int n(Object v) {
        return ((Number) v).intValue();
    }

    @Test
    void everyUploadIsLoggedAndQueried() {
        String tag = String.format("%04d", it.freeDraw(0, 10_000, k -> List.of("MOAUM/ADM/88/88" + String.format("%04d", k), "MOAUM/OFH/88/" + String.format("%04d", k),
                "ZZOLDHISTORY" + String.format("%04d", k))));
        int year = it.freeYear(2800, 2900);
        ses = year + "/" + (year + 1);
        it.session(ses, year);
        UUID student = it.student("ZZOLDHISTORY" + tag, "C00023", "MOAUM/ADM/88/88" + tag, "MOAUM/OFH/88/" + tag, 100);
        String number = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 150000, NULL, 'C00023')")
                .param("s", ses).update());
        UUID person = UUID.randomUUID();
        String bursar = TestTokens.token(person, List.of("bursar"));
        String otherBursar = TestTokens.token(UUID.randomUUID(), List.of("bursar"));
        String sao = TestTokens.token(UUID.randomUUID(), List.of("studentaccounts"));
        String file = "old-portal-export-" + tag + "-" + year + ".xlsx";
        String base = "/api/v1/finance/legacy-fees";
        String today = LocalDate.now(ZoneId.of("Africa/Lagos")).toString();

        // the officer's upload waits for approval: the officer opens no load of the Bursary's
        assertThat(it.call(sao, HttpMethod.POST, base + "/loads", Map.of("fileName", file, "rows", 3)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.POST, base + "/loads", Map.of("fileName", file)).getStatusCode().is4xxClientError())
                .as("an upload says how many rows its file has").isTrue();

        // the Bursary's file: opened with what it states, then two parts — the first sent twice
        ResponseEntity<Map> opened = it.call(bursar, HttpMethod.POST, base + "/loads",
                Map.of("fileName", file, "rows", 3, "students", 2, "sessions", ses, "amount", 125000));
        assertThat(opened.getStatusCode().value()).as("%s", opened.getBody()).isEqualTo(200);
        String id = String.valueOf(opened.getBody().get("id"));
        String ref = String.valueOf(opened.getBody().get("ref"));
        assertThat(ref).startsWith("OFL-");
        List<Map<String, Object>> first = List.of(row(number, ses, "100000", year + "-11-02", "PRHI" + year + tag + "01"),
                row("MOAUM/OFH/88/NOSUCH", ses, "5000", year + "-11-03", "PRHI" + year + tag + "02"));
        List<Map<String, Object>> second = List.of(row(number, ses, "20000", (year + 1) + "-01-15", "PRHI" + year + tag + "03"));
        assertThat(it.call(otherBursar, HttpMethod.POST, base + "/loads/" + id + "/rows", Map.of("from", 0, "rows", first)).getStatusCode().value())
                .as("another officer does not load this upload's parts").isEqualTo(403);
        ResponseEntity<Map> p1 = it.call(bursar, HttpMethod.POST, base + "/loads/" + id + "/rows", Map.of("from", 0, "rows", first));
        assertThat(p1.getStatusCode().value()).as("%s", p1.getBody()).isEqualTo(200);
        assertThat(n(p1.getBody().get("cleared"))).isEqualTo(1);
        assertThat(n(p1.getBody().get("no_student"))).isEqualTo(1);
        assertThat(p1.getBody().get("load_ref")).isEqualTo(ref);
        ResponseEntity<Map> again = it.call(bursar, HttpMethod.POST, base + "/loads/" + id + "/rows", Map.of("from", 0, "rows", first));
        assertThat(again.getBody().get("resent")).isEqualTo(true);
        assertThat(n(again.getBody().get("cleared"))).isZero();
        ResponseEntity<Map> p2 = it.call(bursar, HttpMethod.POST, base + "/loads/" + id + "/rows", Map.of("from", 2, "rows", second));
        assertThat(n(p2.getBody().get("cleared"))).isEqualTo(1);
        assertThat(n(p2.getBody().get("rows_loaded"))).isEqualTo(3);

        // the history: the upload loaded, the part sent again counted once
        Map<String, Object> h = it.call(bursar, HttpMethod.GET, base + "/history?q=" + file, null).getBody();
        assertThat(n(h.get("total"))).isEqualTo(1);
        Map<String, Object> u = ((List<Map<String, Object>>) h.get("rows")).get(0);
        assertThat(u.get("ref")).isEqualTo(ref);
        assertThat(u.get("kind")).isEqualTo("DIRECT");
        assertThat(u.get("state")).isEqualTo("LOADED");
        assertThat(n(u.get("parts"))).isEqualTo(2);
        assertThat(n(u.get("file_rows"))).isEqualTo(3);
        assertThat(n(u.get("rows_read"))).isEqualTo(3);
        assertThat(n(u.get("recorded"))).isEqualTo(2);
        assertThat(n(u.get("no_student"))).isEqualTo(1);
        assertThat(n(u.get("students"))).isEqualTo(1);
        assertThat(u.get("sessions")).isEqualTo(ses);
        assertThat(((Number) u.get("amount")).doubleValue()).isEqualTo(120000.0);
        assertThat(((Number) u.get("file_amount")).doubleValue()).isEqualTo(125000.0);
        assertThat(u.get("office")).isEqualTo("bursar");
        Map<String, Object> one = it.call(bursar, HttpMethod.GET, base + "/history/" + id, null).getBody();
        List<Map<String, Object>> parts = (List<Map<String, Object>>) one.get("part_list");
        assertThat(parts).hasSize(2);
        assertThat(n(parts.get(0).get("resent"))).isEqualTo(1);
        assertThat(n(parts.get(0).get("recorded"))).isEqualTo(1);
        assertThat(n(parts.get(1).get("from_row"))).isEqualTo(2);
        Map<String, Object> pays = it.call(bursar, HttpMethod.GET, base + "/history/" + id + "/payments", null).getBody();
        assertThat(n(pays.get("total"))).isEqualTo(2);
        assertThat(((List<Map<String, Object>>) pays.get("rows")).get(0).get("number")).isEqualTo(number);

        // a load that stopped part-way, then left
        ResponseEntity<Map> stopped = it.call(bursar, HttpMethod.POST, base + "/loads", Map.of("fileName", "stopped-" + file, "rows", 1000));
        String stoppedId = String.valueOf(stopped.getBody().get("id"));
        it.call(bursar, HttpMethod.POST, base + "/loads/" + stoppedId + "/rows",
                Map.of("from", 0, "rows", List.of(row(number, ses, "1000", (year + 1) + "-02-01", "PRHI" + year + tag + "04"))));
        it.db(() -> jdbc.sql("UPDATE finance.legacy_fee_load SET last_at = now() - interval '1 hour' WHERE id = :id").param("id", UUID.fromString(stoppedId)).update());
        Map<String, Object> st = ((List<Map<String, Object>>) it.call(bursar, HttpMethod.GET, base + "/history?q=stopped-" + file, null).getBody().get("rows")).get(0);
        assertThat(st.get("state")).isEqualTo("STOPPED");
        assertThat(n(st.get("rows_read"))).isEqualTo(1);

        // the old door still logs: two parts gathered into one upload with no file named
        assertThat(it.call(bursar, HttpMethod.POST, base, Map.of("rows", List.of(row(number, ses, "500", (year + 1) + "-03-01", "PRHI" + year + tag + "05"))))
                .getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(bursar, HttpMethod.POST, base, Map.of("rows", List.of(row(number, ses, "600", (year + 1) + "-03-02", "PRHI" + year + tag + "06"))))
                .getStatusCode().value()).isEqualTo(200);
        Map<String, Object> door = jdbc.sql("SELECT count(*) AS uploads, max(parts) AS parts, max(recorded) AS recorded FROM finance.legacy_fee_load WHERE by_person = :p AND file_rows IS NULL")
                .param("p", person).query().singleRow();
        assertThat(n(door.get("uploads"))).isEqualTo(1);
        assertThat(n(door.get("parts"))).isEqualTo(2);
        assertThat(n(door.get("recorded"))).isEqualTo(2);

        // a start over of the session, logged with what it deleted
        ResponseEntity<Map> reset = it.call(bursar, HttpMethod.POST, base + "/reset", Map.of("session", ses, "confirm", "RESET"));
        assertThat(reset.getStatusCode().value()).as("%s", reset.getBody()).isEqualTo(200);
        Map<String, Object> resets = it.call(bursar, HttpMethod.GET, base + "/history?kind=RESET&session=" + ses + "&person=" + person, null).getBody();
        assertThat(n(resets.get("total"))).isEqualTo(1);
        Map<String, Object> r = ((List<Map<String, Object>>) resets.get("rows")).get(0);
        assertThat(r.get("state")).isEqualTo("DONE");
        assertThat(n(r.get("deleted"))).isEqualTo(5);
        assertThat(n(it.call(bursar, HttpMethod.GET, base + "/history/" + r.get("id") + "/payments", null).getBody().get("total"))).isEqualTo(5);
        assertThat(n(it.call(bursar, HttpMethod.GET, base + "/history/" + id + "/payments", null).getBody().get("total")))
                .as("the upload's payments still on record: none after the start over").isZero();

        // the query: by how, the person, the session, the day; the officer and the audit read it; others do not
        Map<String, Object> mine = it.call(sao, HttpMethod.GET, base + "/history?person=" + person + "&session=" + ses + "&from=" + today + "&to=" + today, null).getBody();
        assertThat(n(mine.get("total"))).isEqualTo(4);
        assertThat(n(((Map<String, Object>) mine.get("by_kind")).get("DIRECT"))).isEqualTo(3);
        assertThat(n(((Map<String, Object>) mine.get("totals")).get("recorded"))).isEqualTo(5);
        assertThat((List<Map<String, Object>>) mine.get("people")).anyMatch(p -> person.toString().equals(p.get("id")));
        assertThat(n(it.call(bursar, HttpMethod.GET, base + "/history?person=" + person + "&from=" + LocalDate.parse(today).plusDays(1), null).getBody().get("total"))).isZero();
        Map<String, Object> paged = it.call(bursar, HttpMethod.GET, base + "/history?person=" + person + "&size=1&page=2", null).getBody();
        assertThat(((List<?>) paged.get("rows"))).hasSize(1);
        assertThat(n(paged.get("total"))).isEqualTo(4);
        assertThat(it.call(ItSupport.token("audit"), HttpMethod.GET, base + "/history?size=1", null).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(ItSupport.token("registrar"), HttpMethod.GET, base + "/history", null).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.GET, base + "/history?kind=SOMETHING", null).getStatusCode().is4xxClientError()).isTrue();
    }
}
