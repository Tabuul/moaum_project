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
 * V675 through the API: made-up old-portal applicants of a session and a postgraduate programme of their own. ICT Support is
 * refused the desk; the School downloads the admitted template's columns and lists, uploads a file of two rows — a new applicant
 * whose application fee the old portal verified, and one admitted there whose acceptance fee it did not verify and whom it cleared
 * at screening — and the check writes nothing. Imported, each has this portal's number and the old one, and both find them; the
 * School may not verify the held fee, the officer who uploaded it neither, and the Bursar's verification accepts the offer and the
 * old portal's screening admits the applicant to the register. The same file again changes nothing. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PgMigrationIT {

    private static final String M = "/api/v1/pg/migration";

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

    /** a row of the template, by its keys */
    private static Map<String, Object> row(String... kv) {
        Map<String, Object> m = new java.util.LinkedHashMap<>();
        for (int i = 0; i + 1 < kv.length; i += 2) m.put(kv[i], kv[i + 1]);
        return m;
    }

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private Map<String, Object> upload(String school, List<Map<String, Object>> rows, String file) {
        Map<String, Object> b = ok(it.call(school, HttpMethod.POST, M + "/batches", Map.of("kind", "ADMITTED", "fileName", file, "rows", rows.size(), "tell", true)));
        String id = String.valueOf(b.get("id"));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + id + "/rows", Map.of("first", 1, "rows", rows)));
        return ok(it.call(school, HttpMethod.POST, M + "/batches/" + id + "/check", Map.of("from", 1, "to", rows.size())));
    }

    @Test
    void oldApplicantsAreMigratedNotReappliedAndTheAdmittedComeInAdmitted() {
        int y = it.freeYear(7600, 7790, 0, 0);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String code = it.db(() -> jdbc.sql("""
                SELECT 'C9' || lpad(g::text, 4, '0') FROM generate_series(8000, 9999) g
                 WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C9' || lpad(g::text, 4, '0')) ORDER BY random() LIMIT 1
                """).query(String.class).single());
        String name = "M.Sc. Migration Check " + y;
        it.db(() -> jdbc.sql("""
                INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_award)
                SELECT :c, :n, d.code, d.faculty_code, 0, false, 'POST GRADUATE', 'MSC' FROM ref.department d ORDER BY d.code LIMIT 1
                """).param("c", code).param("n", name).update());
        String school = it.officer("pgschool", "institution", "University");
        String bursar = it.officer("bursar", "institution", "University");
        String ict = it.officer("ict", "institution", "University");

        // ICT Support is not a migrator; the School reads the template built from the real fields and this portal's lists
        assertThat(it.get(ict, M + "/template?kind=ADMITTED").getStatusCode().value()).isEqualTo(403);
        Map<String, Object> t = ok(it.get(school, M + "/template?kind=ADMITTED"));
        assertThat((List<Map<String, Object>>) t.get("columns")).extracting(c -> c.get("key")).contains("legacyApplicationNo", "admissionStatus", "acceptanceVerification", "screeningDecision");
        assertThat((List<Map<String, Object>>) t.get("programmes")).extracting(p -> p.get("code")).contains(code);

        String old1 = "ITPG/" + y + "/0001", old2 = "ITPG/" + y + "/0002";
        List<Map<String, Object>> rows = List.of(
                row("legacyApplicationNo", old1, "lastName", "Migrationit", "firstName", "Verified", "email", "itpg" + y + "a@example.test",
                        "session", session, "programmeCode", code, "admissionStatus", "Pending", "applicationFeeStatus", "Verified",
                        "applicationFeeReference", "ITPG-APP-" + y, "applicationFeeAmount", "20000"),
                row("legacyApplicationNo", old2, "lastName", "Migrationit", "firstName", "Held", "email", "itpg" + y + "b@example.test",
                        "session", session, "programme", name, "admissionStatus", "Admitted", "acceptanceStatus", "Accepted",
                        "acceptanceFeeReference", "ITPG-ACC-" + y, "acceptanceFeeAmount", "50000", "acceptanceVerification", "Paid", "screeningDecision", "Cleared"));
        // the admitted file: "Pending" is not an admission, so the first row is refused here and goes in the applicants' file
        Map<String, Object> checked = upload(school, rows, "admitted.xlsx");
        assertThat(((Number) checked.get("errors")).intValue()).isEqualTo(1);
        assertThat(((Number) checked.get("readyToImport")).intValue()).isEqualTo(1);
        // the check wrote nothing but its verdicts
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM admissions.pg_legacy_application WHERE legacy_application_no IN (:a, :b)")
                .param("a", old1).param("b", old2).query(Long.class).single())).isZero();
        String b1 = String.valueOf(checked.get("id"));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + b1 + "/import", Map.of("from", 1, "to", 2)));
        Map<String, Object> done = ok(it.call(school, HttpMethod.POST, M + "/batches/" + b1 + "/finish", Map.of()));
        assertThat(((Number) done.get("created")).intValue()).isEqualTo(1);
        assertThat(((Number) done.get("skipped")).intValue()).isEqualTo(1);
        Map<String, Object> report = ok(it.get(school, M + "/batches/" + b1 + "/rows?status=PROBLEMS"));
        assertThat(String.valueOf(report.get("rows"))).contains("NOT_ADMITTED_IN_ADMITTED_FILE");

        // the old number and this portal's both find the admitted applicant, whose offer stands while the acceptance fee is held
        List<Map<String, Object>> byOld = (List<Map<String, Object>>) it.getList(school, M + "/find?q=" + old2).getBody();
        assertThat(byOld).hasSize(1);
        String newNo = String.valueOf(byOld.get(0).get("application_no"));
        assertThat(newNo).matches("PG/" + String.valueOf(y).substring(2) + "/\\d{6}");
        assertThat(byOld.get(0).get("state")).isEqualTo("OFFERED");
        assertThat((List<Map<String, Object>>) it.getList(school, M + "/find?q=" + newNo).getBody()).extracting(r -> r.get("legacy_application_no")).containsExactly(old2);

        // the held fee: not the School's to verify, nor the uploader's; the Bursar's verification accepts and the old screening admits
        Map<String, Object> fees = ok(it.get(bursar, M + "/list?view=fees&size=500"));
        String fee = ((List<Map<String, Object>>) fees.get("rows")).stream().filter(r -> ("ITPG-ACC-" + y).equals(r.get("legacy_reference")))
                .map(r -> String.valueOf(r.get("id"))).findFirst().orElseThrow();
        assertThat(it.call(school, HttpMethod.POST, M + "/fees/" + fee + "/decide", Map.of("verify", true, "note", "IT: seen")).getStatusCode().value()).isEqualTo(403);
        ok(it.call(bursar, HttpMethod.POST, M + "/fees/" + fee + "/decide", Map.of("verify", true, "note", "IT: seen on the statement")));
        Map<String, Object> app = it.db(() -> jdbc.sql("""
                SELECT a.state, a.student_id IS NOT NULL AS student, (SELECT count(*) FROM people.student s WHERE s.surname = 'Migrationit' AND s.other_names = 'Held'
                                                                       AND s.programme_code = :c) AS students
                  FROM admissions.pg_application a WHERE a.application_no = :n
                """).param("c", code).param("n", newNo).query().singleRow());
        assertThat(app.get("state")).isEqualTo("ADMITTED");
        assertThat(app.get("student")).isEqualTo(true);
        assertThat(((Number) app.get("students")).intValue()).isEqualTo(1);

        // the same file again: nothing twice, and the history lists both uploads
        long before = it.db(() -> jdbc.sql("SELECT (SELECT count(*) FROM admissions.pg_application) + (SELECT count(*) FROM people.student) + (SELECT count(*) FROM admissions.pg_fee_reference)")
                .query(Long.class).single());
        Map<String, Object> again = upload(school, rows, "admitted.xlsx");
        String b2 = String.valueOf(again.get("id"));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + b2 + "/import", Map.of("from", 1, "to", 2)));
        Map<String, Object> done2 = ok(it.call(school, HttpMethod.POST, M + "/batches/" + b2 + "/finish", Map.of()));
        assertThat(((Number) done2.get("unchanged")).intValue()).isEqualTo(1);
        assertThat(((Number) done2.get("created")).intValue()).isZero();
        long after = it.db(() -> jdbc.sql("SELECT (SELECT count(*) FROM admissions.pg_application) + (SELECT count(*) FROM people.student) + (SELECT count(*) FROM admissions.pg_fee_reference)")
                .query(Long.class).single());
        assertThat(after).isEqualTo(before);
        assertThat((List<Map<String, Object>>) it.getList(school, M + "/batches").getBody()).extracting(r -> String.valueOf(r.get("id"))).contains(UUID.fromString(b1).toString(), b2);
    }
}
