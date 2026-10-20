package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * V588: inter-university transfer over the API. The Academic Office adds a university to the list, uploads four rows — a student
 * going out, two coming in who are not on the register, and one going out whose programme is not the record's (SOURCE PROGRAMME
 * MISMATCH) — sees each checked, is refused while a row is invalid, prepares the valid rows alone as a batch (IUT/…); nothing
 * changes on any record; the officer who prepared it cannot decide it; the Registry rejects one incoming transfer with a note and
 * approves the batch: the student going out is TRANSFERRED_OUT with the matriculation number kept, the student coming in is on the
 * register ADMITTED by TRANSFER at the level stated, the rejected one is not. The Bursary has none of it. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class UniversityTransferIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static final String BASE = "/api/v1/transfers/inter-university";

    private static Map<String, Object> placed(Map<String, Object> r, Map<String, Object> programme, String level) {
        Map<String, Object> out = new HashMap<>(r);
        out.put("faculty", programme.get("faculty_code")); out.put("dept", programme.get("dept_code")); out.put("programme", programme.get("code")); out.put("level", level);
        return out;
    }

    @Test
    void transfersInAndOutAreUploadedCheckedPreparedAndDecidedByAnotherOfficer() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int n = it.freeDraw(10000, 99999, k -> List.of("MOAU/SC/IUO/26/" + k, "MOAU/SC/IUP/26/" + k, "MOAUM/ADM/89/" + (400000 + k), "MOAUM/ADM/89/" + (500000 + k),
                "ZZIUTA" + k, "ZZIUTB" + k, "ZZIUTN" + k, "ZZIUTR" + k, "ZZ-IUT-AC-" + k, "ZZ-IUT-RG-" + k));
        Map<String, Object> here = jdbc.sql("SELECT code, dept_code, faculty_code FROM ref.programme WHERE code = 'C00023'").query().singleRow();
        Map<String, Object> to = jdbc.sql("""
                SELECT code, dept_code, faculty_code FROM ref.programme
                 WHERE category = 'UNDER GRADUATE' AND NOT coalesce(archived, false) AND dept_code <> :d AND dept_code IS NOT NULL
                   AND 200 = ANY (people.programme_levels(code)) ORDER BY code LIMIT 1
                """).param("d", here.get("dept_code")).query().singleRow();
        String m1 = "MOAU/SC/IUO/26/" + n, m2 = "MOAU/SC/IUP/26/" + n;
        UUID out = it.student("ZZIUTA" + n, "C00023", "MOAUM/ADM/89/" + (400000 + n), m1, 200);
        it.student("ZZIUTB" + n, "C00023", "MOAUM/ADM/89/" + (500000 + n), m2, 200);
        String jambIn = "ZQIUTN" + n, jambRejected = "ZQIUTR" + n;
        String preparer = TestTokens.token(it.person("ZZ-IUT-AC-" + n, "ZZIUTAC" + n), List.of("academic"));
        String registrar = TestTokens.token(it.person("ZZ-IUT-RG-" + n, "ZZIUTRG" + n), List.of("registrar"));

        // the list of universities: kept by the Academic Office, refused to the Bursary
        String code = "ZQU" + n;
        ResponseEntity<Map> saved = it.call(preparer, HttpMethod.POST, BASE + "/universities", Map.of("code", code, "name", "Invented University " + n));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat(saved.getBody()).containsEntry("code", code).containsEntry("active", true);
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, BASE + "/universities", Map.of("code", "ZQV" + n, "name", "Another " + n)).getStatusCode().value()).isEqualTo(403);
        assertThat((List<Map<String, Object>>) it.getList(preparer, BASE + "/universities").getBody()).extracting(u -> u.get("code")).contains(code, "UNIJOS");

        // four rows: out, in, in, and out on a programme that is not the record's
        List<Map<String, Object>> rows = List.of(
                placed(Map.of("direction", "OUTGOING", "matric_no", m1, "university_code", code, "other_programme", "B.Sc. Physics"), here, "200"),
                placed(Map.of("direction", "INCOMING", "jamb_reg_no", jambIn, "student", "ZZIUTN" + n + ", Invented", "university_code", code,
                        "other_programme", "B.Sc. Physics", "other_level", "200", "sex", "M"), to, "200"),
                placed(Map.of("direction", "INCOMING", "jamb_reg_no", jambRejected, "student", "ZZIUTR" + n + ", Invented", "university_code", code), to, "200"),
                placed(Map.of("direction", "OUTGOING", "matric_no", m2, "university_code", code), to, "200"));
        Map<String, Object> check = it.call(preparer, HttpMethod.POST, BASE + "/validate", Map.of("rows", rows)).getBody();
        assertThat(check).containsEntry("total", 4).containsEntry("invalid", 1).containsEntry("incoming", 2).containsEntry("outgoing", 2).containsEntry("newRecords", 2);
        Map<Integer, String> codes = new HashMap<>();
        ((List<Map<String, Object>>) check.get("rows")).forEach(r -> codes.put((Integer) r.get("row"), r.get("status") + ":" + r.get("action") + ":"
                + ((List<Map<String, Object>>) r.get("problems")).stream().map(p -> String.valueOf(p.get("code"))).sorted().toList()));
        assertThat(codes).containsEntry(1, "VALID:TRANSFER_OUT:[]").containsEntry(2, "VALID:CREATE:[]").containsEntry(3, "VALID:CREATE:[]")
                .containsEntry(4, "INVALID:TRANSFER_OUT:[SOURCE_PROGRAMME_MISMATCH]");

        // the Bursary has none of it
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, BASE + "/validate", Map.of("rows", rows)).getStatusCode().value()).isEqualTo(403);

        // refused while a row is invalid; prepared for the valid rows alone when asked
        Map<String, Object> body = new HashMap<>(Map.of("rows", rows, "reason", "The Senate approved these transfers", "approvalRef", "SEN/IUT/" + n, "filename", "iut.xlsx"));
        ResponseEntity<Map> refused = it.call(preparer, HttpMethod.POST, BASE, body);
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(refused.getBody()).containsEntry("code", "UNIVERSITY_TRANSFER_INVALID");
        body.put("validRowsOnly", true);
        ResponseEntity<Map> made = it.call(preparer, HttpMethod.POST, BASE, body);
        assertThat(made.getStatusCode().value()).as(String.valueOf(made.getBody())).isEqualTo(200);
        String batch = String.valueOf(made.getBody().get("id"));
        String ref = String.valueOf(made.getBody().get("ref"));
        assertThat(ref).matches("IUT/\\d{4}/\\d{6}");
        assertThat(made.getBody()).containsEntry("prepared", 3).containsEntry("left_out", 1).containsEntry("status", "PENDING_APPROVAL");
        assertThat((List<?>) made.getBody().get("leftOut")).hasSize(1);
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", out).query(String.class).single()).isEqualTo("ACTIVE");
        assertThat(jdbc.sql("SELECT count(*) FROM people.student WHERE upper(jamb_reg_no) IN (:a, :b)").param("a", jambIn).param("b", jambRejected)
                .query(Integer.class).single()).isZero();

        // the officer who prepared it does not decide it
        ResponseEntity<Map> own = it.call(preparer, HttpMethod.POST, BASE + "/" + batch + "/decide", Map.of("approve", true));
        assertThat(own.getStatusCode().value()).isEqualTo(403);
        assertThat(own.getBody()).containsEntry("code", "UNIVERSITY_TRANSFER_SAME_OFFICER");

        // the Registry rejects one incoming transfer (a note is required) and approves the rest
        List<Map<String, Object>> transfers = (List<Map<String, Object>>) made.getBody().get("transfers");
        String rejectId = String.valueOf(transfers.stream().filter(t -> jambRejected.equals(t.get("jamb_reg_no"))).findFirst().orElseThrow().get("id"));
        ResponseEntity<Map> noNote = it.call(registrar, HttpMethod.POST, BASE + "/transfers/" + rejectId + "/decide", Map.of("approve", false));
        assertThat(noNote.getStatusCode().value()).isEqualTo(422);
        assertThat(noNote.getBody()).containsEntry("code", "UNIVERSITY_TRANSFER_NOTE");
        assertThat(it.call(registrar, HttpMethod.POST, BASE + "/transfers/" + rejectId + "/decide",
                Map.of("approve", false, "note", "The transcript from the other university has not come")).getBody()).containsEntry("status", "REJECTED");
        Map<String, Object> decided = it.call(registrar, HttpMethod.POST, BASE + "/" + batch + "/decide", Map.of("approve", true, "note", "Checked against the Senate minutes")).getBody();
        assertThat((List<?>) decided.get("decided")).hasSize(2);
        assertThat((List<?>) decided.get("skipped")).isEmpty();

        // out: TRANSFERRED_OUT on the batch's instrument, the record and its number kept
        assertThat(jdbc.sql("SELECT status || '|' || matric_no || '|' || programme_code FROM people.student WHERE id = :s").param("s", out).query(String.class).single())
                .isEqualTo("TRANSFERRED_OUT|" + m1 + "|C00023");
        assertThat(jdbc.sql("SELECT instrument FROM people.status_change WHERE student_id = :s AND to_status = 'TRANSFERRED_OUT'").param("s", out).query(String.class).single())
                .isEqualTo(ref + " (SEN/IUT/" + n + ")");
        // in: one record, ADMITTED by TRANSFER at the level stated; the rejected one never made
        assertThat(jdbc.sql("SELECT entry_mode || '|' || status || '|' || programme_code || '|' || current_level || '|' || coalesce(sex, '-') FROM people.student WHERE upper(jamb_reg_no) = :j")
                .param("j", jambIn).query(String.class).list()).containsExactly("TRANSFER|ADMITTED|" + to.get("code") + "|200|M");
        assertThat(jdbc.sql("SELECT count(*) FROM people.student WHERE upper(jamb_reg_no) = :j").param("j", jambRejected).query(Integer.class).single()).isZero();

        // the batch as it stands, and the transfers found by the reference
        Map<String, Object> view = it.get(registrar, BASE + "/" + batch).getBody();
        assertThat(view).containsEntry("status", "COMPLETED_WITH_EXCEPTIONS").containsEntry("completed", 2).containsEntry("rejected", 1);
        assertThat((List<Map<String, Object>>) view.get("transfers")).extracting(t -> t.get("row_no") + ":" + t.get("direction") + ":" + t.get("status") + ":" + t.get("created_student"))
                .containsExactly("1:OUTGOING:COMPLETED:false", "2:INCOMING:COMPLETED:true", "3:INCOMING:REJECTED:false");
        assertThat((List<Map<String, Object>>) it.getList(registrar, BASE + "/transfers?q=" + ref).getBody()).hasSize(3);
        assertThat((List<Map<String, Object>>) it.getList(registrar, BASE).getBody()).extracting(b -> b.get("id")).contains(batch);
    }
}
