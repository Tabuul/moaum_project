package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

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
 * V745 through the API — the independent review of V737 applied. A file's rows are imported a few at a time, each few committed on its
 * own, and a row made to fail (a stand-in trigger) leaves nothing of itself while the rest come in with consecutive application numbers;
 * the batch's import report (scope=all) lists every row with this portal's number, the error report only the rows with a problem
 * (findings 2, 19/24, 21). A document uploaded before a programme correction is read after it from the new programme's desk and by the
 * applicant; each programme's figures follow the import and the correction, and the UTME figures (the cycle, the pipeline) do not count
 * a preliminary applicant admitted on the old portal (finding 21). A migrated applicant's old number is never their password — at the
 * first-password change, through Forgot password, at their own change — whatever its case and spaces (finding 3); the ICT password desk
 * finds them by it; the desk's rows carry the old number and the fee held for the Bursary (contract C2); a Paid row with no amount is held
 * and the Bursary verifies it at the amount it gives (finding 14), the status saying meanwhile that the payment is being verified
 * (finding 9). The Head of ICT Support uploads and corrects only on a posting over the whole University carrying the capability, which only
 * the Director of ICT grants; a faculty's Database Operator does not upload (findings 5, 17). Two siblings of one file are held apart at
 * the check, and the second, confirmed after the batch is finished, comes in there and then; a gateway reference two rows share is a
 * duplicate at the check (finding 1). Made-up people, drawn afresh on every run. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PrelimMigrationFollowUpIT {

    private static final String M = "/api/v1/admissions/preliminary/migration";
    private static final String DESK = "/api/v1/admissions/preliminary/applications";
    private static final String TECH = "PRELIMINARY_TECHNOLOGY";
    private static final String SCI = "PRELIMINARY_SCIENCE";
    static final String PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";

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

    /* ── made-up people, new on every run ── */

    private static String stamp() {
        return String.format("%09d", Math.floorMod(System.nanoTime() + ThreadLocalRandom.current().nextLong(1_000_000_000L), 1_000_000_000L));
    }

    private static String letters(int n) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < n; i++) b.append((char) ('a' + ThreadLocalRandom.current().nextInt(26)));
        return b.toString();
    }

    private static Map<String, Object> person(String old, String tag) {
        ThreadLocalRandom r = ThreadLocalRandom.current();
        java.time.LocalDate dob = java.time.LocalDate.of(1986, 1, 1).plusDays(r.nextInt(0, 365 * 18));
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("legacyApplicationNo", old);
        m.put("surname", "Zv" + letters(9));
        m.put("firstName", "Zw" + letters(9));
        m.put("gender", r.nextBoolean() ? "Female" : "Male");
        m.put("dateOfBirth", String.format("%02d/%02d/%04d", dob.getDayOfMonth(), dob.getMonthValue(), dob.getYear()));
        m.put("email", "prelimfu" + tag + letters(4) + "@example.test");
        m.put("phone", "080" + String.format("%08d", r.nextInt(0, 100_000_000)));
        m.put("stateOfOrigin", "Benue");
        m.put("nationality", "Nigerian");
        m.put("applicationStatus", "Submitted");
        return m;
    }

    private static Map<String, Object> with(Map<String, Object> row, Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>(row);
        for (int i = 0; i + 1 < kv.length; i += 2) {
            if (kv[i + 1] == null) m.remove(String.valueOf(kv[i]));
            else m.put(String.valueOf(kv[i]), kv[i + 1]);
        }
        return m;
    }

    private static Map<String, Object> paid(Map<String, Object> row, String reference, String amount) {
        return with(row, "paymentStatus", "Paid", "paymentReference", reference, "amountPaid", amount, "paymentDate", "15/03/2026");
    }

    /** a number written as a person might type it: lower case, with a space after the first stroke */
    private static String typed(String number) {
        return number.toLowerCase().replaceFirst("/", "/ ");
    }

    /* ── the API ── */

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    private static void refused(ResponseEntity<Map> r, int status, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(status);
        assertThat(code(r)).as(String.valueOf(r.getBody())).isEqualTo(code);
    }

    private static String sha(List<Map<String, Object>> rows) {
        try {
            return HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(String.valueOf(rows).getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** opened, staged and checked (the dry run); the batch's summary after the check */
    private Map<String, Object> upload(String token, String route, List<Map<String, Object>> rows, String file) {
        Map<String, Object> opened = ok(it.call(token, HttpMethod.POST, M + "/batches", Map.of("route", route, "fileName", file, "sha256", sha(rows),
                "rows", rows.size(), "update", false, "tell", false)));
        String id = String.valueOf(opened.get("id"));
        List<Map<String, Object>> staged = new ArrayList<>();
        for (int i = 0; i < rows.size(); i++) staged.add(with(rows.get(i), "sheetRow", String.valueOf(i + 7)));
        ok(it.call(token, HttpMethod.POST, M + "/batches/" + id + "/rows", Map.of("first", 1, "rows", staged)));
        ok(it.call(token, HttpMethod.POST, M + "/batches/" + id + "/check", Map.of("from", 1, "to", rows.size())));
        return ok(it.get(token, M + "/batches/" + id));
    }

    private Map<String, Object> importRows(String token, String id, int n) {
        return ok(it.call(token, HttpMethod.POST, M + "/batches/" + id + "/import", Map.of("from", 1, "to", n)));
    }

    private Map<String, Object> finish(String token, String id) {
        return ok(it.call(token, HttpMethod.POST, M + "/batches/" + id + "/finish", Map.of()));
    }

    private List<Map<String, Object>> rows(String token, String id) {
        return (List<Map<String, Object>>) ok(it.get(token, M + "/batches/" + id + "/rows?size=500")).get("rows");
    }

    private Map<String, Object> rowOf(String token, String id, String old) {
        return rows(token, id).stream().filter(r -> old.equals(r.get("legacy_no"))).findFirst().orElseThrow();
    }

    private static List<String> problemCodes(Map<String, Object> row) {
        return ((List<Map<String, Object>>) row.get("problems")).stream().map(p -> String.valueOf(p.get("code"))).toList();
    }

    private Map<String, Object> desk(String token, String route, String query) {
        return ok(it.get(token, u -> u.path(DESK).queryParam("route", route).queryParam("q", query).queryParam("size", 50).build()));
    }

    private UUID appOf(String old) {
        return it.db(() -> jdbc.sql("SELECT application_id FROM admissions.prelim_legacy_application WHERE legacy_application_no = :o")
                .param("o", old).query(UUID.class).single());
    }

    private String numberOf(UUID app) {
        return it.db(() -> jdbc.sql("SELECT application_no FROM admissions.application WHERE id = :a").param("a", app).query(String.class).single());
    }

    private UUID accountOf(UUID app) {
        return it.db(() -> jdbc.sql("SELECT account_id FROM admissions.application WHERE id = :a").param("a", app).query(UUID.class).single());
    }

    private static String feeOf(Map<String, Object> template) {
        Map<String, Object> f = (Map<String, Object>) template.get("fee");
        java.math.BigDecimal a = new java.math.BigDecimal(String.valueOf(f.get("application")));
        java.math.BigDecimal p = f.get("portal") == null ? java.math.BigDecimal.ZERO : new java.math.BigDecimal(String.valueOf(f.get("portal")));
        return a.add(p).stripTrailingZeros().toPlainString();
    }

    private static String firstTarget(Map<String, Object> template) {
        return String.valueOf(((List<Map<String, Object>>) template.get("targets")).get(0).get("code"));
    }

    /** a programme's figures on the desk (admissions.prelim_stats) for the route's own session */
    private Map<String, Object> stats(String token, String route) {
        return (Map<String, Object>) ok(it.get(token, "/api/v1/admissions/preliminary/summary?route=" + route)).get("stats");
    }

    private static int delta(Map<String, Object> after, Map<String, Object> before, String key) {
        return ((Number) after.get(key)).intValue() - ((Number) before.get(key)).intValue();
    }

    private String applicantSignIn(String identifier, String password) {
        ResponseEntity<Map> in = it.anon(HttpMethod.POST, "/api/v1/applicant/sign-in", Map.of("identifier", identifier, "password", password));
        assertThat(in.getStatusCode().value()).as(String.valueOf(in.getBody())).isEqualTo(200);
        return String.valueOf(in.getBody().get("token"));
    }

    /** an agent of the support desk, made afresh: a person holding the office named (ictagent, helpdeskhead) */
    private UUID supportPerson(String office) {
        UUID p = it.person("ZZ-PMFU-" + stamp(), "ZZPMFU" + office.toUpperCase());
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from)
                VALUES (gen_random_uuid(), :p, :o, 'platform', 'integration test', :p, current_date)
                """).param("p", p).param("o", office).update());
        return p;
    }

    private void endPostings(UUID person) {
        it.db(() -> jdbc.sql("UPDATE helpdesk.agent_assignment SET active = false, effective_to = current_date WHERE person_id = :p AND active")
                .param("p", person).update());
    }

    /* ── the tests ── */

    @Test
    void aFileComesInAFewRowsAtATimeAFailedRowLeavesNothingAndTheImportReportListsEveryRow() {
        String ict = it.officer("ict", "institution", "University");
        String s = stamp();
        String failing = "ZZFAIL/" + s;
        List<Map<String, Object>> rows = new ArrayList<>();
        for (int i = 1; i <= 23; i++) rows.add(person(i == 12 ? failing : "OPI/" + s + "/" + i, s + "i" + i));
        Map<String, Object> checked = upload(ict, TECH, rows, "steps-" + s + ".xlsx");
        String batch = String.valueOf(checked.get("id"));
        assertThat(((Number) checked.get("readyToImport")).intValue()).as(String.valueOf(checked)).isEqualTo(23);

        // a stand-in for a row the database cannot write: the old number's record refused for this one row, whose writes are then undone
        it.db(() -> {
            jdbc.sql("""
                    CREATE OR REPLACE FUNCTION admissions.zz_it_prelim_mig_fail() RETURNS trigger LANGUAGE plpgsql AS $$
                    BEGIN
                        IF NEW.legacy_application_no LIKE 'ZZFAIL/%' THEN RAISE EXCEPTION 'IT: a row made to fail at the import'; END IF;
                        RETURN NEW;
                    END $$
                    """).update();
            jdbc.sql("DROP TRIGGER IF EXISTS trg_zz_it_prelim_mig_fail ON admissions.prelim_legacy_application").update();
            jdbc.sql("""
                    CREATE TRIGGER trg_zz_it_prelim_mig_fail BEFORE INSERT ON admissions.prelim_legacy_application
                    FOR EACH ROW EXECUTE FUNCTION admissions.zz_it_prelim_mig_fail()
                    """).update();
            return null;
        });
        Map<String, Object> imported;
        try {
            imported = importRows(ict, batch, rows.size());
        } finally {
            it.db(() -> {
                jdbc.sql("DROP TRIGGER IF EXISTS trg_zz_it_prelim_mig_fail ON admissions.prelim_legacy_application").update();
                jdbc.sql("DROP FUNCTION IF EXISTS admissions.zz_it_prelim_mig_fail()").update();
                return null;
            });
        }
        // the endpoint's answer as before: the batch's summary with the rows processed
        assertThat(imported).containsEntry("processed", 23).containsEntry("reference", checked.get("reference"));
        assertThat(((Number) imported.get("created")).intValue()).isEqualTo(22);
        assertThat(((Number) imported.get("failed")).intValue()).isEqualTo(1);

        // committed a few rows at a time: each transaction's own time on its rows (10, 10 and 3), not one for the whole call
        assertThat(it.db(() -> jdbc.sql("SELECT count(DISTINCT imported_at) FROM admissions.prelim_migration_row WHERE batch_id = :b")
                .param("b", UUID.fromString(batch)).query(Long.class).single())).isEqualTo(3L);

        // the failed row: FAILED with the reason, and nothing of it left — no candidate, account, application, old number or fee
        Map<String, Object> failed = rowOf(ict, batch, failing);
        assertThat(failed).containsEntry("result", "FAILED");
        assertThat(String.valueOf(failed.get("result_note"))).contains("a row made to fail");
        assertThat(failed.get("application_id")).isNull();
        String failedEmail = String.valueOf(rows.get(11).get("email"));
        String failedSurname = String.valueOf(rows.get(11).get("surname")).toUpperCase();
        assertThat(it.db(() -> jdbc.sql("""
                SELECT (SELECT count(*) FROM admissions.applicant_account a WHERE lower(a.email) = lower(:e))
                     + (SELECT count(*) FROM admissions.candidate c WHERE upper(c.surname) = :s)
                     + (SELECT count(*) FROM admissions.prelim_legacy_application l WHERE l.legacy_application_no = :o)
                     + (SELECT count(*) FROM admissions.prelim_legacy_fee f JOIN admissions.prelim_migration_row r ON r.id = f.row_id WHERE r.legacy_no = :o)
                """).param("e", failedEmail).param("s", failedSurname).param("o", failing).query(Long.class).single())).isZero();
        // the 22 applicants created have consecutive numbers: the failed row's number was given back with the rest of its writes
        List<Integer> numbers = rows(ict, batch).stream().filter(r -> "CREATED".equals(r.get("result")))
                .map(r -> Integer.parseInt(String.valueOf(r.get("application_no")).replaceAll("^.*/", ""))).sorted().toList();
        assertThat(numbers).hasSize(22);
        assertThat(numbers.get(21) - numbers.get(0) + 1).isEqualTo(22);

        // the same range sent again (Continue the import): nothing imported twice
        assertThat(importRows(ict, batch, rows.size())).containsEntry("processed", 0);

        // the import report: every row, the created ones with this portal's number; the error report: only rows with a problem
        ResponseEntity<List> all = it.getList(ict, M + "/batches/" + batch + "/report?scope=all");
        assertThat(all.getStatusCode().value()).isEqualTo(200);
        List<Map<String, Object>> every = all.getBody();
        assertThat(every).hasSize(23);
        assertThat(every.get(0)).containsKeys("row_no", "sheet_row", "legacy_no", "applicant", "verdict", "result", "result_note", "problems",
                "application_id", "application_no");
        assertThat(every).filteredOn(r -> "CREATED".equals(r.get("result"))).hasSize(22)
                .allSatisfy(r -> assertThat(String.valueOf(r.get("application_no"))).matches("APP/\\d{2}/\\d{6}"));
        assertThat(every).filteredOn(r -> ("OPI/" + s + "/1").equals(r.get("legacy_no"))).singleElement()
                .satisfies(r -> assertThat(r.get("application_no")).isEqualTo(numberOf(appOf("OPI/" + s + "/1"))));
        List<Map<String, Object>> problems = it.getList(ict, M + "/batches/" + batch + "/report").getBody();
        assertThat(problems).extracting(r -> r.get("legacy_no")).contains(failing);
        assertThat(problems).noneSatisfy(r -> assertThat("READY".equals(r.get("verdict")) && "CREATED".equals(r.get("result"))).isTrue());
        assertThat(it.getList(ict, M + "/batches/" + batch + "/report?scope=problems").getBody()).hasSameSizeAs(problems);
        ResponseEntity<Map> bogus = it.get(ict, M + "/batches/" + batch + "/report?scope=every");
        refused(bogus, 422, "PRELIMMIG_REPORT_SCOPE");
        finish(ict, batch);
    }

    @Test
    void aDocumentStaysThroughACorrectionAndEachProgrammesFiguresFollowWhileTheUtmeFiguresDoNot() {
        String ict = it.officer("ict", "institution", "University");
        String bursar = it.officer("bursar", "institution", "University");
        String science = it.officer("prelim", "institution", "University");
        String s = stamp();
        Map<String, Object> techTemplate = ok(it.get(ict, M + "/template?route=" + TECH));
        String session = String.valueOf(techTemplate.get("session"));
        String cyclePath = "/api/v1/admissions/sessions/" + session + "/cycle", pipelinePath = "/api/v1/admissions/sessions/" + session + "/pipeline";
        Map<String, Object> cycle0 = ok(it.get(ict, cyclePath)), pipeline0 = ok(it.get(ict, pipelinePath));
        Map<String, Object> tech0 = stats(ict, TECH), sci0 = stats(ict, SCI);

        String oldDraft = "OPD/" + s + "/1", oldAdmitted = "OPD/" + s + "/2", ref = "ITPD-" + s;
        List<Map<String, Object>> rows = List.of(
                paid(with(person(oldDraft, s + "d"), "applicationStatus", "Draft", "target", firstTarget(techTemplate)), ref, feeOf(techTemplate)),
                with(person(oldAdmitted, s + "a"), "admissionStatus", "Admitted", "paymentStatus", "Not Paid"));
        String batch = String.valueOf(upload(ict, TECH, rows, "documents-" + s + ".xlsx").get("id"));
        importRows(ict, batch, rows.size());
        finish(ict, batch);
        UUID app = appOf(oldDraft);
        String number = numberOf(app);

        // the Technology figures take both applicants in, the fee held; the Science figures are untouched
        Map<String, Object> tech1 = stats(ict, TECH), sci1 = stats(ict, SCI);
        assertThat(delta(tech1, tech0, "total")).isEqualTo(2);
        assertThat(delta(tech1, tech0, "migrated")).isEqualTo(2);
        assertThat(delta(tech1, tech0, "admitted")).isEqualTo(1);
        assertThat(delta(tech1, tech0, "feeHeld")).isEqualTo(1);
        assertThat(delta(sci1, sci0, "total")).isZero();
        // a preliminary applicant admitted on the old portal is never among the session's UTME offers, acceptances or the pipeline
        Map<String, Object> cycle1 = ok(it.get(ict, cyclePath)), pipeline1 = ok(it.get(ict, pipelinePath));
        for (String k : List.of("applications", "screened", "offers", "accepted", "onTheRegister", "notYetOnRegister")) {
            assertThat(cycle1.get(k)).as(k).isEqualTo(cycle0.get(k));
        }
        assertThat(pipeline1).isEqualTo(pipeline0);

        // the Bursary verifies the fee; the applicant, on their first sign-in, chooses a password and uploads the passport photograph
        UUID fee = it.db(() -> jdbc.sql("SELECT id FROM admissions.prelim_legacy_fee WHERE legacy_reference = :r").param("r", ref).query(UUID.class).single());
        ok(it.call(bursar, HttpMethod.POST, M + "/fees/" + fee + "/decide", Map.of("verify", true, "note", "IT: seen on the bank statement")));
        String first = applicantSignIn(oldDraft, number);
        String chosen = "Chosen-" + stamp() + "-pw";
        ok(it.call(first, HttpMethod.POST, "/api/v1/applicant/me/password", Map.of("currentPassword", number, "newPassword", chosen)));
        String applicant = applicantSignIn(oldDraft, chosen);
        Map<String, Object> uploaded = ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/documents",
                Map.of("kind", "PASSPORT", "filename", "me.png", "contentType", "image/png", "contentBase64", PIXEL)));
        UUID document = it.db(() -> jdbc.sql("""
                SELECT id FROM admissions.application_document WHERE application_id = :a AND kind = 'PASSPORT' AND superseded_at IS NULL
                """).param("a", app).query(UUID.class).single());
        assertThat(uploaded).isNotNull();

        // the Director of ICT moves the applicant to Science
        ok(it.call(ict, HttpMethod.POST, M + "/applicants/" + app + "/change-programme",
                Map.of("to", SCI, "from", TECH, "reason", "The applicant applied for Preliminary Science on the old portal form")));

        // the document is still the application's: on the Science desk, readable there and by the applicant, not asked for again
        Map<String, Object> detail = ok(it.get(science, DESK + "/" + app));
        assertThat((List<Map<String, Object>>) detail.get("documents")).extracting(d -> String.valueOf(d.get("id"))).contains(document.toString());
        assertThat(it.getBytes(science, DESK + "/" + app + "/documents/" + document + "/content").getStatusCode().value()).isEqualTo(200);
        assertThat(it.getBytes(applicant, "/api/v1/applicant/me/documents/" + document + "/content").getStatusCode().value()).isEqualTo(200);
        assertThat(it.db(() -> jdbc.sql("SELECT superseded_at IS NULL FROM admissions.application_document WHERE id = :d").param("d", document)
                .query(Boolean.class).single())).isTrue();
        Map<String, Object> mine = (Map<String, Object>) ok(it.get(applicant, "/api/v1/applicant/me/preliminary")).get("preliminary");
        assertThat((List<Map<String, Object>>) mine.get("problems")).as(String.valueOf(mine.get("problems")))
                .noneSatisfy(p -> assertThat("DOCUMENTS".equals(p.get("step")) && "PASSPORT".equals(p.get("field"))).isTrue());
        List<Map<String, Object>> changes = (List<Map<String, Object>>) ok(it.get(ict, M + "/applicants/" + app)).get("routeChanges");
        assertThat(changes).filteredOn(c -> "APPLIED".equals(c.get("result"))).singleElement()
                .satisfies(c -> assertThat(String.valueOf(c.get("missing"))).doesNotContain("PASSPORT"));

        // each programme's figures follow the correction: one off Technology, one onto Science, migrated with it
        Map<String, Object> tech2 = stats(ict, TECH), sci2 = stats(ict, SCI);
        assertThat(delta(tech2, tech1, "total")).isEqualTo(-1);
        assertThat(delta(tech2, tech1, "migrated")).isEqualTo(-1);
        assertThat(delta(sci2, sci1, "total")).isEqualTo(1);
        assertThat(delta(sci2, sci1, "migrated")).isEqualTo(1);
    }

    @Test
    void theOldNumberIsNeverThePasswordTheDesksFindItAndAFeeWithNoAmountIsHeldForTheBursary() {
        String ict = it.officer("ict", "institution", "University");
        String bursar = it.officer("bursar", "institution", "University");
        String s = stamp();
        Map<String, Object> techTemplate = ok(it.get(ict, M + "/template?route=" + TECH));
        String old = "OPW/" + s + "/1", ref = "ITPW-" + s;
        // paid on the old portal, the amount not given: held, the amount for the Bursary to confirm (finding 14)
        List<Map<String, Object>> rows = List.of(with(person(old, s + "w"), "applicationStatus", "Draft", "paymentStatus", "Paid",
                "paymentReference", ref, "paymentDate", "15/03/2026", "target", firstTarget(techTemplate)));
        String batch = String.valueOf(upload(ict, TECH, rows, "passwords-" + s + ".xlsx").get("id"));
        Map<String, Object> row = rowOf(ict, batch, old);
        assertThat(row.get("verdict")).as(String.valueOf(row)).isEqualTo("WARNING");
        assertThat(problemCodes(row)).contains("AMOUNT_MISSING");
        importRows(ict, batch, 1);
        finish(ict, batch);
        UUID app = appOf(old), account = accountOf(app);
        String number = numberOf(app);
        Map<String, Object> held = it.db(() -> jdbc.sql("SELECT id, state, amount FROM admissions.prelim_legacy_fee WHERE application_id = :a")
                .param("a", app).query().singleRow());
        assertThat(held).containsEntry("state", "REQUIRES_REVIEW").containsEntry("amount", null);

        // the desk's rows carry the old number and the fee held for the Bursary (contract C2), beside V737's own names
        Map<String, Object> onDesk = ((List<Map<String, Object>>) desk(ict, TECH, old).get("rows")).get(0);
        assertThat(onDesk).containsEntry("legacyApplicationNo", old).containsEntry("feeStatus", "HELD").containsEntry("legacy_no", old)
                .containsEntry("payment", "HELD");

        // the ICT password desk finds the applicant by the old number, however it is typed
        List<Map<String, Object>> found = it.getList(ict, "/api/v1/applicant-passwords/search?q=" + old.toLowerCase()).getBody();
        assertThat(found).filteredOn(f -> account.toString().equals(String.valueOf(f.get("account_id")))).singleElement()
                .satisfies(f -> assertThat(f).containsEntry("legacy_application_no", old).containsEntry("application_no", number));
        assertThat(ok(it.get(ict, "/api/v1/applicant-passwords/" + account))).containsEntry("legacyNo", old);

        // the first sign-in: the old number, or this portal's, is never the password chosen, whatever its case and spaces (finding 3)
        String first = applicantSignIn(old, number);
        refused(it.call(first, HttpMethod.POST, "/api/v1/applicant/me/password", Map.of("currentPassword", number, "newPassword", typed(old))),
                422, "AUTH_PASSWORD_IS_NUMBER");
        refused(it.call(first, HttpMethod.POST, "/api/v1/applicant/me/password", Map.of("currentPassword", number, "newPassword", typed(number))),
                422, "AUTH_PASSWORD_IS_NUMBER");
        String chosen = "Chosen-" + stamp() + "-pw";
        ok(it.call(first, HttpMethod.POST, "/api/v1/applicant/me/password", Map.of("currentPassword", number, "newPassword", chosen)));
        // the status says the old payment is being verified, not "pay the application fee" (finding 9)
        Map<String, Object> status = ok(it.get(applicantSignIn(old, chosen), "/api/v1/applicant/me/admission"));
        assertThat(status.get("next_action")).as(String.valueOf(status)).isEqualTo("Your old-portal payment is being verified by the Bursary");

        // Forgot password: the link's new password is never the old number either
        String token = "it-prelim-forgot-" + UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.password_reset (subject_kind, subject_id, token_hash, expires_at)
                VALUES ('APPLICANT', :s, encode(sha256(convert_to(:t, 'UTF8')), 'hex'), now() + interval '1 hour')
                """).param("s", account).param("t", token).update());
        refused(it.anon(HttpMethod.POST, "/api/v1/auth/reset", Map.of("token", token, "password", typed(old))), 422, "AUTH_PASSWORD_IS_NUMBER");
        refused(it.anon(HttpMethod.POST, "/api/v1/auth/reset", Map.of("token", token, "password", " " + old.toUpperCase() + " ")), 422, "AUTH_PASSWORD_IS_NUMBER");
        String reset = "Reset-" + stamp() + "-pw";
        ok(it.anon(HttpMethod.POST, "/api/v1/auth/reset", Map.of("token", token, "password", reset)));

        // the applicant's own change afterwards: refused the old number too; the old number opens nothing once a password is chosen
        String signed = applicantSignIn(old, reset);
        refused(it.call(signed, HttpMethod.POST, "/api/v1/applicant/me/password", Map.of("currentPassword", reset, "newPassword", typed(old))),
                422, "AUTH_PASSWORD_IS_NUMBER");
        assertThat(code(it.anon(HttpMethod.POST, "/api/v1/applicant/sign-in", Map.of("identifier", number, "password", old))))
                .isEqualTo("AUTH_FIRST_PASSWORD_RETIRED");

        // the Bursary verifies the fee at the amount it gives; the desk then reads it paid
        UUID fee = (UUID) held.get("id");
        ok(it.call(bursar, HttpMethod.POST, M + "/fees/" + fee + "/decide",
                Map.of("verify", true, "note", "IT: seen on the bank statement", "amount", new java.math.BigDecimal(feeOf(techTemplate)))));
        Map<String, Object> verified = it.db(() -> jdbc.sql("""
                SELECT f.state, f.amount, (SELECT a.fee_confirmed_at IS NOT NULL FROM admissions.application a WHERE a.id = f.application_id) AS paid
                  FROM admissions.prelim_legacy_fee f WHERE f.id = :f
                """).param("f", fee).query().singleRow());
        assertThat(verified).containsEntry("state", "VERIFIED").containsEntry("paid", true);
        assertThat(((java.math.BigDecimal) verified.get("amount")).compareTo(new java.math.BigDecimal(feeOf(techTemplate)))).isZero();
        assertThat(((List<Map<String, Object>>) desk(ict, TECH, old).get("rows")).get(0)).containsEntry("feeStatus", "PAID");
    }

    @Test
    void theHeadOfIctSupportActsOnlyOnAPostingTheDirectorGrants() {
        String ict = it.officer("ict", "institution", "University");
        String admin = it.officer("admin", "institution", "University");
        UUID headId = supportPerson("helpdeskhead");
        String head = TestTokens.token(headId, List.of("helpdeskhead"));
        UUID agentId = supportPerson("ictagent");
        String s = stamp();
        try {
            // no implicit right: neither the upload nor the correction, and the desk's capabilities by office leave both out
            assertThat(ok(it.get(head, M + "/access"))).containsEntry("mayMigrate", false).containsEntry("mayChangeProgramme", false);
            refused(it.get(head, M + "/template?route=" + TECH), 403, "PRELIMMIG_CAPABILITY");
            refused(it.call(head, HttpMethod.POST, M + "/batches", Map.of("route", TECH, "fileName", "head-" + s + ".xlsx", "rows", 1)), 403, "PRELIMMIG_CAPABILITY");
            refused(it.call(head, HttpMethod.POST, M + "/applicants/" + UUID.randomUUID() + "/change-programme",
                    Map.of("to", SCI, "from", TECH, "reason", "The applicant applied for the other programme")), 403, "PRELIM_CHANGE_CAPABILITY");
            List<String> caps = (List<String>) ok(it.get(head, "/api/v1/helpdesk/support/students?q=zzpmfu-nobody&size=1")).get("capabilities");
            assertThat(caps).contains("VIEW_STUDENT").doesNotContain("MIGRATE_PRELIM_APPLICANTS", "CHANGE_PRELIM_PROGRAMME");

            // only the Director of ICT (or super) grants either capability on a posting: the Head and Admin are refused
            Map<String, Object> posting = new LinkedHashMap<>(Map.of("personId", agentId.toString(), "queueCode", "STUDENT_BIODATA_SUPPORT",
                    "scopeKind", "GLOBAL", "reason", "integration test", "capabilities", List.of("VIEW_STUDENT", "MIGRATE_PRELIM_APPLICANTS")));
            refused(it.call(head, HttpMethod.POST, "/api/v1/helpdesk/admin/agents", posting), 403, "HELPDESK_GRANT_DIRECTOR");
            refused(it.call(admin, HttpMethod.POST, "/api/v1/helpdesk/admin/agents", posting), 403, "HELPDESK_GRANT_DIRECTOR");
            String postingId = String.valueOf(ok(it.call(ict, HttpMethod.POST, "/api/v1/helpdesk/admin/agents", posting)).get("id"));
            // the Head may keep or take away what the posting carries, never add the other
            ok(it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + postingId,
                    Map.of("capabilities", List.of("VIEW_STUDENT", "VIEW_PAYMENTS", "MIGRATE_PRELIM_APPLICANTS"))));
            refused(it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + postingId,
                    Map.of("capabilities", List.of("VIEW_STUDENT", "MIGRATE_PRELIM_APPLICANTS", "CHANGE_PRELIM_PROGRAMME"))), 403, "HELPDESK_GRANT_DIRECTOR");
            ok(it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + postingId, Map.of("capabilities", List.of("VIEW_STUDENT"))));
            assertThat(it.db(() -> jdbc.sql("SELECT array_to_string(capabilities, ',') FROM helpdesk.agent_assignment WHERE id = :id")
                    .param("id", UUID.fromString(postingId)).query(String.class).single())).isEqualTo("VIEW_STUDENT");

            // nor bring back a posting carrying it once the Director ended it, nor keep it beyond the date the Director gave (a grant again);
            // shortening it, or ending it, stays the Head's
            ok(it.call(ict, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + postingId, Map.of("active", false)));
            java.time.LocalDate today = java.time.LocalDate.now(java.time.ZoneId.of("Africa/Lagos"));
            Map<String, Object> timed = new LinkedHashMap<>(posting);
            timed.put("effectiveTo", today.plusDays(30).toString());
            String timedId = String.valueOf(ok(it.call(ict, HttpMethod.POST, "/api/v1/helpdesk/admin/agents", timed)).get("id"));
            refused(it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + timedId, Map.of("effectiveTo", today.plusDays(400).toString())), 403, "HELPDESK_GRANT_DIRECTOR");
            ok(it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + timedId, Map.of("effectiveTo", today.plusDays(10).toString())));
            ok(it.call(ict, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + timedId, Map.of("active", false)));
            refused(it.call(head, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + timedId, Map.of("active", true)), 403, "HELPDESK_GRANT_DIRECTOR");
            refused(it.call(admin, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + timedId, Map.of("active", true)), 403, "HELPDESK_GRANT_DIRECTOR");
            assertThat(it.db(() -> jdbc.sql("SELECT active FROM helpdesk.agent_assignment WHERE id = :id").param("id", UUID.fromString(timedId))
                    .query(Boolean.class).single())).isFalse();
            ok(it.call(ict, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + timedId, Map.of("active", true)));
            ok(it.call(ict, HttpMethod.PUT, "/api/v1/helpdesk/admin/agents/" + timedId, Map.of("active", false)));

            // the Head on a posting over the whole University carrying the upload only: uploads, and still does not correct
            it.db(() -> jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, capabilities)
                    VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'GLOBAL', ARRAY['MIGRATE_PRELIM_APPLICANTS'])
                    """).param("p", headId).update());
            assertThat(ok(it.get(head, M + "/access"))).containsEntry("mayMigrate", true).containsEntry("mayChangeProgramme", false);
            ok(it.get(head, M + "/template?route=" + TECH));
            Map<String, Object> opened = ok(it.call(head, HttpMethod.POST, M + "/batches", Map.of("route", TECH, "fileName", "head-" + s + ".xlsx",
                    "sha256", sha(List.of(Map.of("head", s))), "rows", 1, "tell", false)));
            ok(it.call(head, HttpMethod.POST, M + "/batches/" + opened.get("id") + "/abandon", Map.of("reason", "IT: an authorised head may open a batch")));
            refused(it.call(head, HttpMethod.POST, M + "/applicants/" + UUID.randomUUID() + "/change-programme",
                    Map.of("to", SCI, "from", TECH, "reason", "The applicant applied for the other programme")), 403, "PRELIM_CHANGE_CAPABILITY");
            assertThat((List<String>) ok(it.get(head, "/api/v1/helpdesk/support/students?q=zzpmfu-nobody&size=1")).get("capabilities"))
                    .contains("MIGRATE_PRELIM_APPLICANTS").doesNotContain("CHANGE_PRELIM_PROGRAMME");
        } finally {
            endPostings(headId);
            endPostings(agentId);
        }

        // a Database Operator held to one faculty does not upload; one over the whole University does
        String faculty = it.db(() -> jdbc.sql("SELECT code FROM ref.faculty ORDER BY code LIMIT 1").query(String.class).single());
        refused(it.get(it.officer("dbops", "faculty", faculty), M + "/template?route=" + TECH), 422, "SCOPE_UNIVERSITY");
        ok(it.get(it.officer("dbops", "institution", "University"), M + "/template?route=" + TECH));
    }

    @Test
    void siblingsOfOneFileAreHeldApartAtTheCheckAndTheSecondIsConfirmedAfterTheBatchIsFinished() {
        String ict = it.officer("ict", "institution", "University");
        String s = stamp();
        Map<String, Object> techTemplate = ok(it.get(ict, M + "/template?route=" + TECH));
        String fee = feeOf(techTemplate);
        String o1 = "OPS/" + s + "/1", o2 = "OPS/" + s + "/2", o3 = "OPS/" + s + "/3", o4 = "OPS/" + s + "/4";
        Map<String, Object> elder = person(o1, s + "x");
        // a sibling: the same surname and the parent's phone, written another way; another first name and birth date
        Map<String, Object> younger = with(person(o2, s + "y"), "surname", String.valueOf(elder.get("surname")).toUpperCase(),
                "phone", "+234 " + String.valueOf(elder.get("phone")).substring(1));
        String gateway = "GW-" + s;
        List<Map<String, Object>> rows = List.of(elder, younger,
                with(paid(person(o3, s + "g"), "ITPS-" + s + "-3", fee), "gatewayReference", gateway),
                with(paid(person(o4, s + "h"), "ITPS-" + s + "-4", fee), "gatewayReference", gateway.toLowerCase()));
        Map<String, Object> checked = upload(ict, TECH, rows, "siblings-" + s + ".xlsx");
        String batch = String.valueOf(checked.get("id"));

        // the dry run says what the import will do: the second sibling held for review, the shared gateway reference a duplicate
        Map<String, Object> second = rowOf(ict, batch, o2);
        assertThat(second.get("verdict")).as(String.valueOf(second)).isEqualTo("REQUIRES_REVIEW");
        assertThat(problemCodes(second)).contains("POSSIBLE_SAME_APPLICANT");
        Map<String, Object> shared = rowOf(ict, batch, o4);
        assertThat(shared.get("verdict")).as(String.valueOf(shared)).isEqualTo("DUPLICATE_IN_FILE");
        assertThat(problemCodes(shared)).contains("FEE_REFERENCE_IN_FILE");
        assertThat(rowOf(ict, batch, o1).get("verdict")).isIn("READY", "WARNING");
        assertThat(checked).containsEntry("newApplicants", 2).containsEntry("paymentsToVerify", 1);

        Map<String, Object> imported = importRows(ict, batch, rows.size());
        assertThat(imported).containsEntry("created", 2).containsEntry("feesHeld", 1);
        assertThat(rowOf(ict, batch, o2)).containsEntry("result", "SKIPPED");
        assertThat(finish(ict, batch).get("state")).isEqualTo("COMPLETED");

        // the officer knows them for two people: the second is confirmed in its own, finished batch, and comes in there and then
        Map<String, Object> confirmed = ok(it.call(ict, HttpMethod.POST, M + "/rows/" + second.get("id") + "/new",
                Map.of("reason", "Siblings: another first name and another birth date")));
        assertThat(confirmed).containsEntry("result", "CREATED");
        UUID app = appOf(o2);
        assertThat(String.valueOf(confirmed.get("applicationId"))).isEqualTo(app.toString());
        assertThat(numberOf(app)).matches("APP/\\d{2}/\\d{6}");
        Map<String, Object> after = ok(it.get(ict, M + "/batches/" + batch));
        assertThat(after).containsEntry("state", "COMPLETED").containsEntry("created", 3);
        // confirmed once: a second word on the row is refused
        ResponseEntity<Map> twice = it.call(ict, HttpMethod.POST, M + "/rows/" + second.get("id") + "/new",
                Map.of("reason", "Siblings: another first name and another birth date"));
        assertThat(twice.getStatusCode().value()).isEqualTo(422);
    }
}
