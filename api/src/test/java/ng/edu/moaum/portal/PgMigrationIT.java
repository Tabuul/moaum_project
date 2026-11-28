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
        int y = it.freePgYear(7600, 7790, 0, 0);   // its application numbers must not clash with another session's (PG/yy/…)
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
        // every filter of the rows list answers, not the problems alone: all of them (the default), a verdict, a result, a search
        Map<String, Object> all = ok(it.get(school, M + "/batches/" + b1 + "/rows"));
        assertThat(((Number) all.get("total")).intValue()).isEqualTo(2);
        assertThat((List<Map<String, Object>>) all.get("rows")).extracting(r -> r.get("legacy_no")).containsExactly(old1, old2);
        assertThat((List<Map<String, Object>>) ok(it.get(school, M + "/batches/" + b1 + "/rows?status=ERROR")).get("rows"))
                .extracting(r -> r.get("legacy_no")).containsExactly(old1);
        assertThat((List<Map<String, Object>>) ok(it.get(school, M + "/batches/" + b1 + "/rows?status=CREATED")).get("rows"))
                .extracting(r -> r.get("legacy_no")).containsExactly(old2);
        Map<String, Object> searched = ok(it.get(school, M + "/batches/" + b1 + "/rows?status=ALL&q=" + old2));
        assertThat(((Number) searched.get("total")).intValue()).isEqualTo(1);
        assertThat((List<Map<String, Object>>) searched.get("rows")).extracting(r -> r.get("legacy_no")).containsExactly(old2);

        // the old number and this portal's both find the admitted applicant — V712: on the register at the import, the acceptance fee
        // still held for the Bursary
        List<Map<String, Object>> byOld = (List<Map<String, Object>>) it.getList(school, M + "/find?q=" + old2).getBody();
        assertThat(byOld).hasSize(1);
        String newNo = String.valueOf(byOld.get(0).get("application_no"));
        assertThat(newNo).matches("PG/" + String.valueOf(y).substring(2) + "/\\d{6}");
        assertThat(byOld.get(0).get("state")).isEqualTo("ADMITTED");
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

    /**
     * V783: the University's word of 24 November 2026 on the application fees uploaded from the old portal, "i need the system to auto
     * clear them". An application fee the old portal marked Paid and that reaches the session's application fee is posted at the
     * import — nothing of it waits on the Bursary's desk; one below the fee is held, and the desk says why; the Bursar still verifies
     * the held one.
     */
    @Test
    void aPaidApplicationFeeThatReachesTheFeeClearsOnItsOwnAndAShortOneIsHeldWithItsReason() {
        int y = it.freePgYear(7600, 7790, 0, 0);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String code = it.db(() -> jdbc.sql("""
                SELECT 'C9' || lpad(g::text, 4, '0') FROM generate_series(8000, 9999) g
                 WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C9' || lpad(g::text, 4, '0')) ORDER BY random() LIMIT 1
                """).query(String.class).single());
        it.db(() -> jdbc.sql("""
                INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_award)
                SELECT :c, :n, d.code, d.faculty_code, 0, false, 'POST GRADUATE', 'MSC' FROM ref.department d ORDER BY d.code LIMIT 1
                """).param("c", code).param("n", "M.Sc. Fee Clearing Check " + y).update());
        String school = it.officer("pgschool", "institution", "University");
        String bursar = it.officer("bursar", "institution", "University");
        String clear = "ITPG-CLR-" + y, held = "ITPG-SHT-" + y;
        List<Map<String, Object>> rows = List.of(
                row("legacyApplicationNo", "ITPG/" + y + "/0101", "lastName", "Clearingit", "firstName", "Full", "email", "itpg" + y + "c@example.test",
                        "session", session, "programmeCode", code, "applicationFeeStatus", "Paid", "applicationFeeReference", clear, "applicationFeeAmount", "20000"),
                row("legacyApplicationNo", "ITPG/" + y + "/0102", "lastName", "Clearingit", "firstName", "Short", "email", "itpg" + y + "d@example.test",
                        "session", session, "programmeCode", code, "applicationFeeStatus", "Paid", "applicationFeeReference", held, "applicationFeeAmount", "12000"));
        Map<String, Object> b = ok(it.call(school, HttpMethod.POST, M + "/batches", Map.of("kind", "APPLICANTS", "fileName", "applicants.xlsx", "rows", 2, "tell", true)));
        String id = String.valueOf(b.get("id"));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + id + "/rows", Map.of("first", 1, "rows", rows)));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + id + "/check", Map.of("from", 1, "to", 2)));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + id + "/import", Map.of("from", 1, "to", 2)));
        Map<String, Object> done = ok(it.call(school, HttpMethod.POST, M + "/batches/" + id + "/finish", Map.of()));
        assertThat(((Number) done.get("created")).intValue()).isEqualTo(2);

        // the fee that reaches the application fee is cleared: posted, stamped by the system, and the application reads its fee as paid
        Map<String, Object> cleared = it.db(() -> jdbc.sql("""
                SELECT f.state, f.decided_office, f.decided_by IS NULL AS by_system, a.fee_confirmed_at IS NOT NULL AS paid
                  FROM admissions.pg_legacy_fee f JOIN admissions.pg_application a ON a.id = f.application_id WHERE f.legacy_reference = :r
                """).param("r", clear).query().singleRow());
        assertThat(cleared.get("state")).isEqualTo("POSTED");
        assertThat(cleared.get("decided_office")).isEqualTo("system");
        assertThat(cleared.get("by_system")).isEqualTo(true);
        assertThat(cleared.get("paid")).isEqualTo(true);

        // the desk lists only the held one, with its reason
        Map<String, Object> fees = ok(it.get(bursar, M + "/list?view=fees&size=500"));
        List<Map<String, Object>> waiting = (List<Map<String, Object>>) fees.get("rows");
        assertThat(waiting).extracting(r -> r.get("legacy_reference")).contains(held).doesNotContain(clear);
        Map<String, Object> shortRow = waiting.stream().filter(r -> held.equals(r.get("legacy_reference"))).findFirst().orElseThrow();
        assertThat(String.valueOf(shortRow.get("hold_reason"))).contains("below the application fee");

        // the Bursar still verifies it, and it is posted under the Bursar's name
        ok(it.call(bursar, HttpMethod.POST, M + "/fees/" + shortRow.get("id") + "/decide", Map.of("verify", true, "note", "IT: seen on the statement")));
        Map<String, Object> verified = it.db(() -> jdbc.sql("SELECT f.state, f.decided_office FROM admissions.pg_legacy_fee f WHERE f.legacy_reference = :r")
                .param("r", held).query().singleRow());
        assertThat(verified.get("state")).isEqualTo("POSTED");
        assertThat(verified.get("decided_office")).isEqualTo("bursar");
    }

    /**
     * V786: the University's word of 24 November 2026, "i want to upload those payments in this format". A sheet in the Old Fees History
     * layout whose first column is a PG applicant's application number: the School checks it (nothing is written), the Bursar uploads it,
     * the fee that reaches the application fee is cleared by the system and a short one waits on the Bursary's desk with its reason; the
     * same sheet again records nothing twice. ICT Support, and a Database Operator held to a department, are refused.
     */
    @Test
    void aPaymentsSheetInTheOldFeesLayoutIsCheckedThenUploadedAndClearsPgApplicantsFees() {
        int y = it.freePgYear(7600, 7790, 0, 0);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String code = it.db(() -> jdbc.sql("""
                SELECT 'C9' || lpad(g::text, 4, '0') FROM generate_series(8000, 9999) g
                 WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C9' || lpad(g::text, 4, '0')) ORDER BY random() LIMIT 1
                """).query(String.class).single());
        it.db(() -> jdbc.sql("""
                INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, archived, category, pg_award)
                SELECT :c, :n, d.code, d.faculty_code, 0, false, 'POST GRADUATE', 'MSC' FROM ref.department d ORDER BY d.code LIMIT 1
                """).param("c", code).param("n", "M.Sc. Payments Sheet Check " + y).update());
        String school = it.officer("pgschool", "institution", "University");
        String bursar = it.officer("bursar", "institution", "University");
        String support = it.officer("ictagent", "institution", "University");
        String dept = it.db(() -> jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :c").param("c", code).query(String.class).single());
        String heldOperator = it.officer("dbops", "department", dept);

        // two applicants of this portal, with no application fee yet: the sheet's payments are all the fee they have
        String oldFull = "ITPG/" + y + "/0201", oldShort = "ITPG/" + y + "/0202", oldQuiet = "ITPG/" + y + "/0203";
        List<Map<String, Object>> applicants = List.of(
                row("legacyApplicationNo", oldFull, "lastName", "Paysheetit", "firstName", "Full", "email", "itpgpay" + y + "a@example.test",
                        "session", session, "programmeCode", code),
                row("legacyApplicationNo", oldShort, "lastName", "Paysheetit", "firstName", "Short", "email", "itpgpay" + y + "b@example.test",
                        "session", session, "programmeCode", code),
                row("legacyApplicationNo", oldQuiet, "lastName", "Paysheetit", "firstName", "Quiet", "email", "itpgpay" + y + "c@example.test",
                        "session", session, "programmeCode", code));
        Map<String, Object> mb = ok(it.call(school, HttpMethod.POST, M + "/batches", Map.of("kind", "APPLICANTS", "fileName", "payers.xlsx", "rows", 3, "tell", false)));
        String mid = String.valueOf(mb.get("id"));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + mid + "/rows", Map.of("first", 1, "rows", applicants)));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + mid + "/check", Map.of("from", 1, "to", 3)));
        ok(it.call(school, HttpMethod.POST, M + "/batches/" + mid + "/import", Map.of("from", 1, "to", 3)));
        assertThat(((Number) ok(it.call(school, HttpMethod.POST, M + "/batches/" + mid + "/finish", Map.of())).get("created")).intValue()).isEqualTo(3);
        java.util.function.Function<String, String> numberOf = old -> it.db(() -> jdbc.sql("""
                SELECT a.application_no FROM admissions.pg_legacy_application l JOIN admissions.pg_application a ON a.id = l.application_id
                 WHERE l.legacy_application_no = :o
                """).param("o", old).query(String.class).single());
        String fullNo = numberOf.apply(oldFull), shortNo = numberOf.apply(oldShort), quietNo = numberOf.apply(oldQuiet);
        assertThat(fullNo).matches("PG/" + String.valueOf(y).substring(2) + "/\\d{6}");

        // the sheet as the Old Fees History upload reads it: the application number where the matriculation number goes
        String clear = "ITPAY-CLR-" + y, shortRef = "ITPAY-SHT-" + y, file = "payments-" + y + ".xlsx";
        List<Map<String, Object>> sheet = List.of(
                row("matric", fullNo, "session", session, "amount", "20000", "purpose", "PG APPLICATION", "paidOn", "2026-03-09", "channel", "Interswitch", "receiptNo", clear),
                row("matric", shortNo, "session", session, "amount", "12000", "purpose", "PG APPLICATION", "paidOn", "2026-03-09", "channel", "Interswitch", "receiptNo", shortRef),
                row("matric", "PG/" + String.valueOf(y).substring(2) + "/999999", "session", session, "amount", "20000", "purpose", "PG APPLICATION", "receiptNo", "ITPAY-NONE-" + y));
        java.util.function.Function<Boolean, Map<String, Object>> body = apply -> {
            Map<String, Object> b = new java.util.LinkedHashMap<>();
            b.put("fileName", file);
            b.put("rows", java.util.stream.IntStream.range(0, sheet.size()).mapToObj(i -> {
                Map<String, Object> r = new java.util.LinkedHashMap<>(sheet.get(i));
                r.put("row", i + 2);
                return r;
            }).toList());
            b.put("apply", apply);
            return b;
        };
        java.util.function.Function<String, Long> recorded = ref -> it.db(() -> jdbc.sql("SELECT count(*) FROM admissions.pg_legacy_fee WHERE legacy_reference = :r")
                .param("r", ref).query(Long.class).single());

        // ICT Support is not an uploader; a Database Operator held to a department does not work the University's migration
        assertThat(it.call(support, HttpMethod.POST, M + "/fees/payments", body.apply(false)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> heldScope = it.call(heldOperator, HttpMethod.POST, M + "/fees/payments", body.apply(false));
        assertThat(heldScope.getStatusCode().value()).isEqualTo(422);
        assertThat(heldScope.getBody().get("code")).isEqualTo("SCOPE_UNIVERSITY");
        // the database's own refusals reach the officer with their codes
        Map<String, Object> notExcel = body.apply(false);
        notExcel.put("fileName", "payments.csv");
        ResponseEntity<Map> csv = it.call(school, HttpMethod.POST, M + "/fees/payments", notExcel);
        assertThat(csv.getStatusCode().value()).isEqualTo(422);
        assertThat(csv.getBody().get("code")).isEqualTo("PGFEES_FILE_TYPE");
        Map<String, Object> noRows = body.apply(false);
        noRows.put("rows", List.of());
        assertThat(it.call(school, HttpMethod.POST, M + "/fees/payments", noRows).getStatusCode().value()).isEqualTo(400);

        // the Check, by the School: each row as the upload will answer it, and nothing written
        Map<String, Object> checked = ok(it.call(school, HttpMethod.POST, M + "/fees/payments", body.apply(false)));
        assertThat(checked.get("applied")).isEqualTo(false);
        assertThat(checked.get("batchId")).isNull();
        assertThat(((Number) checked.get("rows")).intValue()).isEqualTo(3);
        assertThat(((Number) checked.get("cleared")).intValue()).isEqualTo(1);
        assertThat(((Number) checked.get("held")).intValue()).isEqualTo(1);
        assertThat(((Number) checked.get("refused")).intValue()).isEqualTo(1);
        List<Map<String, Object>> verdicts = (List<Map<String, Object>>) checked.get("results");
        assertThat(verdicts).extracting(r -> r.get("result")).containsExactly("CLEARED", "HELD", "NOT_FOUND");
        assertThat(verdicts).extracting(r -> ((Number) r.get("rowNo")).intValue()).containsExactly(2, 3, 4);
        assertThat(verdicts.get(0).get("applicationNo")).isEqualTo(fullNo);
        assertThat(String.valueOf(verdicts.get(1).get("reason"))).contains("below the application fee");
        assertThat(recorded.apply(clear)).isZero();
        assertThat(recorded.apply(shortRef)).isZero();
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM admissions.pg_migration_batch WHERE file_name = :f").param("f", file).query(Long.class).single())).isZero();
        assertThat(it.db(() -> jdbc.sql("SELECT fee_confirmed_at IS NOT NULL FROM admissions.pg_application WHERE application_no = :n").param("n", fullNo).query(Boolean.class).single())).isFalse();

        // the Upload, by the Bursar: the same answers, written
        Map<String, Object> uploaded = ok(it.call(bursar, HttpMethod.POST, M + "/fees/payments", body.apply(true)));
        assertThat(uploaded.get("applied")).isEqualTo(true);
        assertThat(uploaded.get("batchId")).isNotNull();
        assertThat(String.valueOf(uploaded.get("batchReference"))).startsWith("PG-MIG/");
        assertThat(((Number) uploaded.get("cleared")).intValue()).isEqualTo(1);
        assertThat(((Number) uploaded.get("held")).intValue()).isEqualTo(1);
        assertThat(((List<Map<String, Object>>) uploaded.get("results"))).extracting(r -> r.get("result")).containsExactly("CLEARED", "HELD", "NOT_FOUND");
        Map<String, Object> cleared = it.db(() -> jdbc.sql("""
                SELECT f.state, f.decided_office, f.decided_by IS NULL AS by_system, a.fee_confirmed_at IS NOT NULL AS paid
                  FROM admissions.pg_legacy_fee f JOIN admissions.pg_application a ON a.id = f.application_id WHERE f.legacy_reference = :r
                """).param("r", clear).query().singleRow());
        assertThat(cleared.get("state")).isEqualTo("POSTED");
        assertThat(cleared.get("decided_office")).isEqualTo("system");
        assertThat(cleared.get("by_system")).isEqualTo(true);
        assertThat(cleared.get("paid")).isEqualTo(true);
        Map<String, Object> batch = it.db(() -> jdbc.sql("SELECT b.kind, b.state FROM admissions.pg_migration_batch b WHERE b.id = :b::uuid")
                .param("b", String.valueOf(uploaded.get("batchId"))).query().singleRow());
        assertThat(batch.get("kind")).isEqualTo("FEES");
        assertThat(batch.get("state")).isEqualTo("COMPLETED");

        // the short one waits on the Bursary's desk with its reason, and the cleared one is not there
        List<Map<String, Object>> waiting = (List<Map<String, Object>>) ok(it.get(bursar, M + "/list?view=fees&size=500")).get("rows");
        assertThat(waiting).extracting(r -> r.get("legacy_reference")).contains(shortRef).doesNotContain(clear);
        Map<String, Object> shortRow = waiting.stream().filter(r -> shortRef.equals(r.get("legacy_reference"))).findFirst().orElseThrow();
        assertThat(String.valueOf(shortRow.get("hold_reason"))).contains("below the application fee");

        // the same sheet again: the cleared payment is already recorded, nothing is cleared or written twice
        Map<String, Object> again = ok(it.call(bursar, HttpMethod.POST, M + "/fees/payments", body.apply(true)));
        assertThat(((Number) again.get("cleared")).intValue()).isZero();
        assertThat(((Number) again.get("already")).intValue()).isEqualTo(1);
        assertThat(((List<Map<String, Object>>) again.get("results"))).extracting(r -> r.get("result")).containsExactly("ALREADY", "HELD", "NOT_FOUND");
        assertThat(recorded.apply(clear)).isEqualTo(1L);
        assertThat(recorded.apply(shortRef)).isEqualTo(1L);

        // the applicant whose fee cleared is told, unless the officer asks for no notices
        java.util.function.Function<String, Long> told = no -> it.db(() -> jdbc.sql("""
                SELECT count(*) FROM platform.notice n JOIN admissions.pg_application a ON a.id = n.about_id
                 WHERE a.application_no = :n AND n.event_key LIKE 'pg-fee-verified:%'
                """).param("n", no).query(Long.class).single());
        assertThat(told.apply(fullNo)).isPositive();
        Map<String, Object> quiet = new java.util.LinkedHashMap<>();
        quiet.put("fileName", "payments-quiet-" + y + ".xlsx");
        quiet.put("rows", List.of(row("matric", quietNo, "session", session, "amount", "20000", "purpose", "PG APPLICATION", "receiptNo", "ITPAY-QUIET-" + y)));
        quiet.put("apply", true);
        quiet.put("notify", false);
        Map<String, Object> hushed = ok(it.call(school, HttpMethod.POST, M + "/fees/payments", quiet));
        assertThat(((Number) hushed.get("cleared")).intValue()).isEqualTo(1);
        assertThat(told.apply(quietNo)).isZero();
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
        int y = it.freePgYear(7600, 7790, 0, 0);   // its application numbers must not clash with another session's (PG/yy/…)
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
        // V712: admitted on the old portal, on the register at the import
        assertThat(offer.get("state")).isEqualTo("ADMITTED");
        assertThat(offer.get("admission_no")).isNotNull();
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
        // V712: the applicant portal asks no application or acceptance fee of one admitted on the old portal
        assertThat(ok(it.get(token, "/api/v1/pg/me"))).containsEntry("oldPortalAdmitted", true).containsEntry("state", "ADMITTED");
        ResponseEntity<Map> acceptance = it.call(token, HttpMethod.POST, "/api/v1/pg/fee-reference?kind=ACCEPTANCE", Map.of());
        assertThat(acceptance.getStatusCode().value()).isEqualTo(422);
        assertThat(acceptance.getBody().get("code")).isEqualTo("PG_FEE_NOT_NEEDED");
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
