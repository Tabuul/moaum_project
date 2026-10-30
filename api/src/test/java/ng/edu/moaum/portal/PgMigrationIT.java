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
 * old portal's screening admits the applicant to the register. The same file again changes nothing. V709: an applicant the migration
 * creates signs in on either number, with either as the first password, and chooses their own before anything else; one the old
 * portal screened opens the student portal on the admission number first, or on the password chosen on the applicant portal.
 * Needs DATABASE_URL.
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
        String support = it.officer("ictagent", "institution", "University");
        // V679 (27 Oct 2026): the Director of ICT and a Database Operator over the whole University migrate too; one held to a
        // department is refused (SCOPE_UNIVERSITY), and ICT Support is not a migrator
        String ict = it.officer("ict", "institution", "University");
        String operator = it.officer("dbops", "institution", "University");
        String dept = it.db(() -> jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :c").param("c", code).query(String.class).single());
        String heldOperator = it.officer("dbops", "department", dept);

        // ICT Support is not a migrator; the School reads the template built from the real fields and this portal's lists
        assertThat(it.get(support, M + "/template?kind=ADMITTED").getStatusCode().value()).isEqualTo(403);
        assertThat(ok(it.get(ict, M + "/template?kind=ADMITTED")).get("columns")).isNotNull();
        assertThat(ok(it.get(operator, M + "/template?kind=ADMITTED")).get("columns")).isNotNull();
        assertThat(ok(it.get(operator, M + "/figures"))).containsKey("migrated");
        ResponseEntity<Map> held = it.get(heldOperator, M + "/template?kind=ADMITTED");
        assertThat(held.getStatusCode().value()).isEqualTo(422);
        assertThat(held.getBody().get("code")).isEqualTo("SCOPE_UNIVERSITY");
        // the database's own door (admissions.pg_mig_writer): the Director of ICT opens a batch and sets it aside
        Map<String, Object> byIct = ok(it.call(ict, HttpMethod.POST, M + "/batches", Map.of("kind", "APPLICANTS", "fileName", "ict.xlsx", "rows", 1, "tell", false)));
        ok(it.call(ict, HttpMethod.POST, M + "/batches/" + byIct.get("id") + "/abandon", Map.of("reason", "IT: the Director of ICT may open a batch")));
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

    private ResponseEntity<Map> pgSignIn(String identifier, String password) {
        return it.anon(HttpMethod.POST, "/api/v1/pg/sign-in", Map.of("identifier", identifier, "password", password));
    }

    private ResponseEntity<Map> studentSignIn(String number, String password) {
        return it.anon(HttpMethod.POST, "/api/v1/student-auth/sign-in", Map.of("matricNo", number, "password", password));
    }

    /** V709: the University's word of 30 October 2026, "pg admitted … cant login from the migrated lagacy data" */
    @Test
    void aMigratedApplicantSignsInOnEitherNumberFirstAndChoosesTheirOwn() {
        int y = it.freeYear(7600, 7790, 0, 0);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String code = it.db(() -> jdbc.sql("""
                SELECT 'C9' || lpad(g::text, 4, '0') FROM generate_series(8000, 9999) g
                 WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C9' || lpad(g::text, 4, '0')) ORDER BY random() LIMIT 1
                """).query(String.class).single());
        it.db(() -> jdbc.sql("""
                INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_award)
                SELECT :c, :n, d.code, d.faculty_code, 0, false, 'POST GRADUATE', 'MSC' FROM ref.department d ORDER BY d.code LIMIT 1
                """).param("c", code).param("n", "M.Sc. First Sign-in Check " + y).update());
        String school = it.officer("pgschool", "institution", "University");
        // the old portal's numbers, as the University's sign-in page showed one (S00220260204082731)
        String stamp = String.format("%09d", Math.floorMod(System.nanoTime(), 1_000_000_000L));
        String oldOffer = "S002" + y + stamp + "1", oldFirst = "S002" + y + stamp + "2", oldCarried = "S002" + y + stamp + "3";
        List<Map<String, Object>> rows = List.of(
                row("legacyApplicationNo", oldOffer, "lastName", "Firstsignin", "firstName", "Offered", "email", "itpgfs" + stamp + "a@example.test", "phone", "080" + stamp.substring(1),
                        "session", session, "programmeCode", code, "admissionStatus", "Admitted"),
                row("legacyApplicationNo", oldFirst, "lastName", "Firstsignin", "firstName", "Studentdoor", "email", "itpgfs" + stamp + "b@example.test",
                        "session", session, "programmeCode", code, "admissionStatus", "Admitted", "acceptanceStatus", "Accepted",
                        "acceptanceFeeReference", "ITPGFS-B-" + stamp, "acceptanceFeeAmount", "50000", "acceptanceVerification", "Verified", "screeningDecision", "Cleared"),
                row("legacyApplicationNo", oldCarried, "lastName", "Firstsignin", "firstName", "Carried", "email", "itpgfs" + stamp + "c@example.test",
                        "session", session, "programmeCode", code, "admissionStatus", "Admitted", "acceptanceStatus", "Accepted",
                        "acceptanceFeeReference", "ITPGFS-C-" + stamp, "acceptanceFeeAmount", "50000", "acceptanceVerification", "Verified", "screeningDecision", "Cleared"));
        Map<String, Object> checked = upload(school, rows, "first-sign-in.xlsx");
        assertThat(((Number) checked.get("readyToImport")).intValue()).as(String.valueOf(checked)).isEqualTo(3);
        String batch = String.valueOf(checked.get("id"));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + batch + "/import", Map.of("from", 1, "to", 3)));
        assertThat(((Number) ok(it.call(school, HttpMethod.POST, M + "/batches/" + batch + "/finish", Map.of())).get("created")).intValue()).isEqualTo(3);
        java.util.function.Function<String, Map<String, Object>> byOld = old -> it.db(() -> jdbc.sql("""
                SELECT a.id, a.application_no, a.state, s.admission_no, sa.must_change AS student_first, p.must_change_password AS first,
                       (SELECT n.body FROM platform.notice n WHERE n.event_key = 'pg-migrated:' || a.id AND n.channel = 'EMAIL' LIMIT 1) AS told,
                       (SELECT n.body FROM platform.notice n WHERE n.event_key = 'pg-migrated:' || a.id AND n.channel = 'SMS' LIMIT 1) AS sms
                  FROM admissions.pg_legacy_application l JOIN admissions.pg_application a ON a.id = l.application_id
                  JOIN admissions.pg_applicant p ON p.id = a.applicant_id
                  LEFT JOIN people.student s ON s.id = a.student_id LEFT JOIN iam.student_account sa ON sa.student_id = a.student_id
                 WHERE l.legacy_application_no = :o
                """).param("o", old).query().singleRow());

        // an offer: on either number until they choose their own, and the notice says so
        Map<String, Object> offer = byOld.apply(oldOffer);
        String newOffer = String.valueOf(offer.get("application_no"));
        assertThat(offer.get("state")).isEqualTo("OFFERED");
        assertThat(offer.get("first")).isEqualTo(true);
        assertThat(String.valueOf(offer.get("told"))).contains(oldOffer, newOffer, "Your first password is either application number");
        assertThat(String.valueOf(offer.get("sms"))).contains("either number as your first password");
        ResponseEntity<Map> in = pgSignIn(oldOffer, " " + oldOffer.toLowerCase() + " ");
        assertThat(in.getStatusCode().value()).as(String.valueOf(in.getBody())).isEqualTo(200);
        assertThat(in.getBody().get("mustChange")).isEqualTo(true);
        assertThat(pgSignIn(oldOffer, newOffer).getStatusCode().value()).isEqualTo(200);
        assertThat(pgSignIn(newOffer, oldOffer).getStatusCode().value()).isEqualTo(200);
        assertThat(pgSignIn(oldOffer, "Not-" + oldOffer).getStatusCode().value()).isEqualTo(422);
        String token = String.valueOf(in.getBody().get("token"));
        ResponseEntity<Map> gated = it.get(token, "/api/v1/pg/me");
        assertThat(gated.getStatusCode().value()).isEqualTo(403);
        assertThat(gated.getBody().get("code")).isEqualTo("PASSWORD_CHANGE_REQUIRED");
        // the change: the old number is the one they have; neither number is the new one
        ResponseEntity<Map> asNumber = it.call(token, HttpMethod.POST, "/api/v1/pg/me/password", Map.of("currentPassword", oldOffer, "newPassword", newOffer));
        assertThat(asNumber.getBody().get("code")).isEqualTo("AUTH_PASSWORD_IS_NUMBER");
        String chosen = "Chosen-" + y + "-pw";
        ok(it.call(token, HttpMethod.POST, "/api/v1/pg/me/password", Map.of("currentPassword", oldOffer, "newPassword", chosen)));
        assertThat(pgSignIn(oldOffer, oldOffer).getStatusCode().value()).isEqualTo(422);
        assertThat(pgSignIn(newOffer, newOffer).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> again = pgSignIn(oldOffer, chosen);
        assertThat(again.getStatusCode().value()).isEqualTo(200);
        assertThat(again.getBody().get("mustChange")).isEqualTo(false);

        // screened on the old portal: on the register, the student door opens on the admission number first
        Map<String, Object> first = byOld.apply(oldFirst);
        assertThat(first.get("state")).isEqualTo("ADMITTED");
        assertThat(first.get("student_first")).isEqualTo(true);
        String admissionNo = String.valueOf(first.get("admission_no"));
        assertThat(String.valueOf(first.get("told"))).contains(admissionNo, "with your admission number, which is also your first password");
        ResponseEntity<Map> student = studentSignIn(admissionNo, admissionNo);
        assertThat(student.getStatusCode().value()).as(String.valueOf(student.getBody())).isEqualTo(200);
        assertThat(student.getBody().get("mustChange")).isEqualTo(true);

        // the password chosen on the applicant portal opens the student portal never signed into, and the number no longer does
        Map<String, Object> carried = byOld.apply(oldCarried);
        String carriedAdmission = String.valueOf(carried.get("admission_no"));
        String pgToken = String.valueOf(pgSignIn(oldCarried, oldCarried).getBody().get("token"));
        ok(it.call(pgToken, HttpMethod.POST, "/api/v1/pg/me/password", Map.of("currentPassword", oldCarried, "newPassword", chosen)));
        assertThat(byOld.apply(oldCarried).get("student_first")).isEqualTo(false);
        ResponseEntity<Map> carriedIn = studentSignIn(carriedAdmission, chosen);
        assertThat(carriedIn.getStatusCode().value()).as(String.valueOf(carriedIn.getBody())).isEqualTo(200);
        assertThat(carriedIn.getBody().get("mustChange")).isEqualTo(false);
        assertThat(studentSignIn(carriedAdmission, carriedAdmission).getStatusCode().value()).isNotEqualTo(200);
    }
}
