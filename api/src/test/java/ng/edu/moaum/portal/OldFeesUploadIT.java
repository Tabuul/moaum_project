package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * V607: the Students Account Officer's Old Fees History upload is written to the records only when the Bursar approves it. The
 * officer opens an upload with its item codes, sends the rows in parts and sends it to the Bursar — no payment is recorded; the
 * officer may not load directly or approve, the Bursar may not open one; the rows are read back and fixed; the Bursar's check
 * counts what approving would do and writes nothing; the person who uploaded never approves; the approval loads a part at a time
 * and the payments are recorded; a second upload is rejected with the reason and a third withdrawn. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {"moaum.auth.hmac-secret=" + TestTokens.SECRET})
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"unchecked", "rawtypes"})
class OldFeesUploadIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    /** the run's own session: its fee line is taken away after the test, as OldFeesIT does */
    String ses;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @AfterEach
    void clean() {
        if (ses != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", ses).update());
    }

    private static Map<String, Object> row(String number, String session, String amount, String item, String paidOn, String payref) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("matric", number);
        r.put("session", session);
        r.put("semester", "First");
        r.put("level", "100");
        r.put("amount", amount);
        r.put("purpose", item);
        r.put("paidOn", paidOn);
        r.put("receiptNo", payref);
        r.put("channel", "Interswitch");
        r.put("note", "");
        return r;
    }

    private long payments(UUID student) {
        return jdbc.sql("SELECT count(*) FROM finance.payment_reference WHERE student_id = :s AND channel = 'Legacy'").param("s", student).query(Long.class).single();
    }

    @Test
    void theOfficersUploadIsWrittenToTheRecordsOnlyWhenTheBursarApprovesIt() {
        String tag = String.format("%04d", it.freeDraw(0, 10_000, k -> List.of("MOAUM/ADM/87/87" + String.format("%04d", k), "MOAUM/OFU/87/" + String.format("%04d", k),
                "ZZOLDUPLOAD" + String.format("%04d", k))));
        int year = it.freeYear(2900, 3000);
        ses = year + "/" + (year + 1);
        it.session(ses, year);
        UUID student = it.student("ZZOLDUPLOAD" + tag, "C00023", "MOAUM/ADM/87/87" + tag, "MOAUM/OFU/87/" + tag, 100);
        String number = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        it.db(() -> jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees', 150000, NULL, 'C00023')")
                .param("s", ses).update());
        UUID officer = UUID.randomUUID();
        String sao = TestTokens.token(officer, List.of("studentaccounts"));
        String officerAsBursar = TestTokens.token(officer, List.of("bursar"));
        String bursar = ItSupport.token("bursar");
        String base = "/api/v1/finance/legacy-fees/uploads";
        List<Map<String, Object>> first = List.of(row(number, ses, "100000", "SCHOOL FEES", year + "-11-02", "PRUP" + year + tag + "01"));
        List<Map<String, Object>> second = List.of(row(number, ses, "20000", "SCHOOL FEES MAKE UP", (year + 1) + "-01-15", "PRUP" + year + tag + "02"),
                row("MOAUM/OFU/87/NOSUCH", ses, "5000", "SCHOOL FEES", year + "-11-04", "PRUP" + year + tag + "03"));

        // the officer neither loads directly nor approves; the Bursary does not open an upload for approval
        assertThat(it.call(sao, HttpMethod.POST, "/api/v1/finance/legacy-fees", Map.of("rows", first)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(bursar, HttpMethod.POST, base, Map.of("fileName", "x.xlsx")).getStatusCode().value()).isEqualTo(403);

        // opened with the item codes, the rows in two parts, sent to the Bursar: nothing on the records
        ResponseEntity<Map> opened = it.call(sao, HttpMethod.POST, base, Map.of("fileName", "old-portal.xlsx", "itemCodes",
                List.of(Map.of("code", "9" + tag, "description", "SCHOOL FEES", "school", ""))));
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        String id = String.valueOf(opened.getBody().get("id"));
        assertThat(String.valueOf(opened.getBody().get("ref"))).startsWith("OFU-");
        assertThat(it.call(sao, HttpMethod.POST, base + "/" + id + "/rows", Map.of("rows", first)).getBody()).containsEntry("rows", 1);
        assertThat(it.call(sao, HttpMethod.POST, base + "/" + id + "/rows", Map.of("rows", second)).getBody()).containsEntry("rows", 3);
        assertThat(it.call(sao, HttpMethod.POST, base + "/" + id + "/approve", Map.of("parts", 1)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> sent = it.call(sao, HttpMethod.POST, base + "/" + id + "/submit", Map.of());
        assertThat(sent.getStatusCode().value()).as(String.valueOf(sent.getBody())).isEqualTo(200);
        assertThat(sent.getBody()).containsEntry("state", "PENDING").containsEntry("row_count", 3).containsEntry("students", 2).containsEntry("parts", 2);
        assertThat(payments(student)).isZero();
        ResponseEntity<Map> late = it.call(sao, HttpMethod.POST, base + "/" + id + "/rows", Map.of("rows", first));
        assertThat(late.getStatusCode().value()).isEqualTo(422);
        assertThat(late.getBody()).containsEntry("code", "LEGACY_UPLOAD_STATE");

        // the Bursar reads it: in the list, its rows; checks what approving would do, nothing written
        List<Map<String, Object>> listed = (List<Map<String, Object>>) it.get(bursar, base + "?state=PENDING").getBody().get("rows");
        assertThat(listed).extracting(r -> r.get("id")).contains(id);
        List<Map<String, Object>> read = (List<Map<String, Object>>) it.get(bursar, base + "/" + id + "/rows?limit=10").getBody().get("rows");
        assertThat(read).hasSize(3);
        assertThat(read.get(0)).containsEntry("matric", number);
        ResponseEntity<Map> checked = it.call(bursar, HttpMethod.POST, base + "/" + id + "/check", Map.of("fromPart", 1, "parts", 2));
        assertThat(checked.getStatusCode().value()).as(String.valueOf(checked.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) checked.getBody().get("totals")).containsEntry("rows", 3).containsEntry("cleared", 2).containsEntry("no_student", 1);
        assertThat(payments(student)).isZero();

        // the person who uploaded never approves, even acting as the Bursar; the Bursar approves a part at a time
        ResponseEntity<Map> own = it.call(officerAsBursar, HttpMethod.POST, base + "/" + id + "/approve", Map.of("parts", 1));
        assertThat(own.getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> one = it.call(bursar, HttpMethod.POST, base + "/" + id + "/approve", Map.of("parts", 1, "note", "Checked against the old portal"));
        assertThat(one.getStatusCode().value()).as(String.valueOf(one.getBody())).isEqualTo(200);
        assertThat(one.getBody()).containsEntry("state", "APPROVING").containsEntry("remaining", 1);
        assertThat(payments(student)).isEqualTo(1L);
        ResponseEntity<Map> two = it.call(bursar, HttpMethod.POST, base + "/" + id + "/approve", Map.of("parts", 2));
        assertThat(two.getBody()).containsEntry("state", "APPROVED").containsEntry("remaining", 0);
        assertThat((Map<String, Object>) two.getBody().get("result")).containsEntry("rows", 3).containsEntry("cleared", 2).containsEntry("no_student", 1);
        assertThat(payments(student)).isEqualTo(2L);
        assertThat(jdbc.sql("SELECT description FROM finance.legacy_item_code WHERE code = :c").param("c", "9" + tag).query(String.class).single()).isEqualTo("SCHOOL FEES");
        assertThat(it.get(sao, base + "/" + id).getBody()).containsEntry("state", "APPROVED").containsEntry("decision_note", "Checked against the old portal");

        // a second upload rejected with the reason (a short one refused), a third withdrawn by the officer
        String id2 = String.valueOf(it.call(sao, HttpMethod.POST, base, Map.of("fileName", "second.xlsx")).getBody().get("id"));
        it.call(sao, HttpMethod.POST, base + "/" + id2 + "/rows", Map.of("rows", first));
        it.call(sao, HttpMethod.POST, base + "/" + id2 + "/submit", Map.of());
        assertThat(it.call(bursar, HttpMethod.POST, base + "/" + id2 + "/reject", Map.of("reason", "no")).getBody()).containsEntry("code", "LEGACY_UPLOAD_REASON");
        assertThat(it.call(bursar, HttpMethod.POST, base + "/" + id2 + "/reject", Map.of("reason", "The amounts do not match the old portal")).getBody())
                .containsEntry("state", "REJECTED");
        String id3 = String.valueOf(it.call(sao, HttpMethod.POST, base, Map.of("fileName", "third.xlsx")).getBody().get("id"));
        assertThat(it.call(sao, HttpMethod.POST, base + "/" + id3 + "/withdraw", Map.of("reason", "Wrong file chosen")).getBody()).containsEntry("state", "WITHDRAWN");
        assertThat(payments(student)).isEqualTo(2L);
    }
}
