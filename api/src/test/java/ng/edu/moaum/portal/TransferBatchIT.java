package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * V587: bulk inter-departmental transfer over the API. The Academic Office takes its department's students as a template, uploads
 * three rows — one right, one naming another department as the student's old one (SOURCE PROGRAMME MISMATCH), one naming a
 * programme that does not exist — sees each checked, is refused while a row is invalid, prepares the valid row alone as a batch
 * (IDT/…) of programme swaps; nothing changes on the students; the officer who prepared it cannot approve it; the Registry approves,
 * and the student is in the new department with the same matriculation number. The Bursary has none of it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class TransferBatchIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static final String BASE = "/api/v1/transfers/bulk";

    private static Map<String, Object> row(String matric, Map<String, Object> from, Map<String, Object> to, String level) {
        Map<String, Object> r = new HashMap<>();
        r.put("matric_no", matric);
        r.put("old_faculty", from.get("faculty_code")); r.put("old_dept", from.get("dept_code")); r.put("old_programme", from.get("code")); r.put("old_level", "200");
        r.put("new_faculty", to.get("faculty_code")); r.put("new_dept", to.get("dept_code")); r.put("new_programme", to.get("code")); r.put("new_level", level);
        return r;
    }

    @Test
    void aDepartmentsTransfersAreUploadedCheckedPreparedAndDecidedByAnotherOfficer() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = 10000 + new Random().nextInt(89999);
        Map<String, Object> from = jdbc.sql("SELECT code, dept_code, faculty_code FROM ref.programme WHERE code = 'C00023'").query().singleRow();
        Map<String, Object> to = jdbc.sql("""
                SELECT code, dept_code, faculty_code FROM ref.programme
                 WHERE category = 'UNDER GRADUATE' AND NOT coalesce(archived, false) AND dept_code <> :d AND dept_code IS NOT NULL
                   AND 200 = ANY (people.programme_levels(code)) ORDER BY code LIMIT 1
                """).param("d", from.get("dept_code")).query().singleRow();
        String m1 = "MOAU/SC/IDT/26/" + n, m2 = "MOAU/SC/IDS/26/" + n, m3 = "MOAU/SC/IDU/26/" + n;
        UUID s1 = it.student("ZZIDTA" + n, "C00023", "MOAUM/ADM/89/" + (100000 + n), m1, 200);
        it.student("ZZIDTB" + n, "C00023", "MOAUM/ADM/89/" + (200000 + n), m2, 200);
        it.student("ZZIDTC" + n, "C00023", "MOAUM/ADM/89/" + (300000 + n), m3, 200);
        String preparer = TestTokens.token(it.person("ZZ-IDT-AC-" + n, "ZZIDTAC" + n), List.of("academic"));
        String registrar = TestTokens.token(it.person("ZZ-IDT-RG-" + n, "ZZIDTRG" + n), List.of("registrar"));

        // the template: the department's students as they stand
        ResponseEntity<List> template = it.getList(preparer, BASE + "/template?department=" + from.get("dept_code") + "&programme=C00023&level=200");
        assertThat(template.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) template.getBody()).extracting(r -> r.get("matric_no")).contains(m1, m2, m3);

        // three rows: right, the wrong old department, a programme that does not exist
        Map<String, Object> wrongOld = new HashMap<>(row(m2, from, to, "200"));
        wrongOld.put("old_dept", to.get("dept_code"));
        Map<String, Object> noSuch = new HashMap<>(row(m3, from, to, "200"));
        noSuch.put("new_programme", "C99999");
        List<Map<String, Object>> rows = List.of(row(m1, from, to, "200"), wrongOld, noSuch);
        Map<String, Object> check = it.call(preparer, HttpMethod.POST, BASE + "/validate", Map.of("rows", rows)).getBody();
        assertThat(check).containsEntry("total", 3).containsEntry("invalid", 2);
        Map<Integer, String> codes = new HashMap<>();
        ((List<Map<String, Object>>) check.get("rows")).forEach(r -> codes.put((Integer) r.get("row"), r.get("status") + ":"
                + ((List<Map<String, Object>>) r.get("problems")).stream().map(p -> String.valueOf(p.get("code"))).sorted().toList()));
        assertThat(codes.get(1)).matches("(VALID|WARNING):\\[\\]");
        assertThat(codes.get(2)).isEqualTo("INVALID:[SOURCE_PROGRAMME_MISMATCH]");
        assertThat(codes.get(3)).isEqualTo("INVALID:[TARGET_UNKNOWN]");

        // the Bursary has none of it
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, BASE + "/validate", Map.of("rows", rows)).getStatusCode().value()).isEqualTo(403);

        // refused while a row is invalid; prepared for the valid row alone when asked
        Map<String, Object> body = new HashMap<>(Map.of("rows", rows, "reason", "The Senate approved these transfers", "approvalRef", "SEN/26/" + n, "filename", "transfers.xlsx"));
        ResponseEntity<Map> refused = it.call(preparer, HttpMethod.POST, BASE, body);
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody()).containsEntry("code", "TRANSFER_BATCH_INVALID");
        body.put("validRowsOnly", true);
        ResponseEntity<Map> made = it.call(preparer, HttpMethod.POST, BASE, body);
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        String batch = String.valueOf(made.getBody().get("id"));
        assertThat(String.valueOf(made.getBody().get("ref"))).matches("IDT/\\d{4}/\\d{6}");
        assertThat(made.getBody()).containsEntry("prepared", 1).containsEntry("status", "PENDING_APPROVAL");
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", s1).query(String.class).single()).isEqualTo("C00023");

        // the officer who prepared it does not approve it; the Registry does
        Map<String, Object> own = it.call(preparer, HttpMethod.POST, "/api/v1/programme-swaps/batches/" + batch + "/decide", Map.of("approve", true)).getBody();
        assertThat((List<?>) own.get("decided")).isEmpty();
        assertThat((List<?>) own.get("skipped")).hasSize(1);
        Map<String, Object> decided = it.call(registrar, HttpMethod.POST, "/api/v1/programme-swaps/batches/" + batch + "/decide",
                Map.of("approve", true, "note", "Checked against the Senate minutes")).getBody();
        assertThat((List<?>) decided.get("decided")).hasSize(1);
        assertThat(jdbc.sql("SELECT programme_code || '|' || current_level || '|' || matric_no FROM people.student WHERE id = :s").param("s", s1).query(String.class).single())
                .isEqualTo(to.get("code") + "|200|" + m1);

        // the batch as it stands, every row kept with its result
        Map<String, Object> view = it.get(registrar, BASE + "/" + batch).getBody();
        assertThat(view).containsEntry("status", "COMPLETED_WITH_EXCEPTIONS").containsEntry("completed", 1);
        assertThat((List<Map<String, Object>>) view.get("rows")).extracting(r -> r.get("row_no") + ":" + r.get("status")).containsExactly("1:PREPARED", "2:INVALID", "3:INVALID");
        assertThat((List<Map<String, Object>>) it.getList(registrar, BASE).getBody()).extracting(b -> b.get("id")).contains(batch);
    }
}
