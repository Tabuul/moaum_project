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
 * V737 through the API: old-portal applicants of Preliminary Technology & Industrial Studies and of Preliminary Science, each file
 * uploaded in its own programme's section. Each programme's template is its own (Science has no specialisation). A Technology file
 * of made-up rows — two good applicants (one whose fee the old portal says is paid, one admitted there), one with no surname, the
 * same old number twice, and one whose Programme cell names Preliminary Science — is checked without a write: the missing field is
 * an error, the twin is a duplicate in the file, the Science row is a conflict. Imported, the two good applicants are on the
 * Technology desk with this portal's number and the old one, the admitted one published admitted; the Science file's applicant is on
 * the Science desk. The fee the old portal called paid is held: the applicant is not asked to pay again (a new reference is refused),
 * the officer who uploaded it may not verify it, and the Bursar's verification posts the old reference itself and no other. The same
 * file again creates nothing. The applicant signs in on the old number with the application number as the first password, and is
 * asked to choose their own. The Director of ICT moves an applicant from Technology to Science — the same record, number and fee, off
 * one desk and onto the other, written down; a stale correction is refused and written down too; a published outcome stands. ICT
 * Support is refused both the upload and the correction until the Director posts the agent over the whole University with the
 * capabilities. A fee the Bursary rejected is not held again when the file comes again to update the applicants, so the applicant
 * draws a reference; an old number shaped like this portal's own is refused; Forgot password knows the old number; a programme's
 * office finds only its own applicants; an agent who may only change a programme finds an applicant and never reads the uploads or
 * the fees. Made-up numbers, names, emails, phones and dates of birth are drawn afresh on every run. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class PrelimMigrationIT {

    private static final String M = "/api/v1/admissions/preliminary/migration";
    private static final String DESK = "/api/v1/admissions/preliminary/applications";
    private static final String TECH = "PRELIMINARY_TECHNOLOGY";
    private static final String SCI = "PRELIMINARY_SCIENCE";

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

    /** nine digits no earlier run drew: the clock's nanoseconds and a random draw */
    private static String stamp() {
        return String.format("%09d", Math.floorMod(System.nanoTime() + ThreadLocalRandom.current().nextLong(1_000_000_000L), 1_000_000_000L));
    }

    private static String letters(int n) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < n; i++) b.append((char) ('a' + ThreadLocalRandom.current().nextInt(26)));
        return b.toString();
    }

    /** a row of the template, by its keys; a person's name, date of birth (day first, as the old portal writes it), phone and email */
    private static Map<String, Object> person(String old, String tag) {
        ThreadLocalRandom r = ThreadLocalRandom.current();
        java.time.LocalDate dob = java.time.LocalDate.of(1986, 1, 1).plusDays(r.nextInt(0, 365 * 18));
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("legacyApplicationNo", old);
        m.put("surname", "Zp" + letters(9));
        m.put("firstName", "Zq" + letters(9));
        m.put("gender", r.nextBoolean() ? "Female" : "Male");
        m.put("dateOfBirth", String.format("%02d/%02d/%04d", dob.getDayOfMonth(), dob.getMonthValue(), dob.getYear()));
        m.put("email", "prelimmig" + tag + letters(4) + "@example.test");
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

    /* ── the API ── */

    private Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static String code(ResponseEntity<Map> r) {
        return r.getBody() == null ? null : String.valueOf(r.getBody().get("code"));
    }

    private static String sha(List<Map<String, Object>> rows) {
        try {
            return HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(String.valueOf(rows).getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** opened, staged and checked (the dry run); the batch's summary as opened, with its id */
    private Map<String, Object> upload(String token, String route, List<Map<String, Object>> rows, String file, boolean update) {
        Map<String, Object> opened = ok(it.call(token, HttpMethod.POST, M + "/batches", Map.of("route", route, "fileName", file, "sha256", sha(rows),
                "rows", rows.size(), "update", update, "tell", true)));
        String id = String.valueOf(opened.get("id"));
        List<Map<String, Object>> staged = new ArrayList<>();
        for (int i = 0; i < rows.size(); i++) staged.add(with(rows.get(i), "sheetRow", String.valueOf(i + 7)));
        ok(it.call(token, HttpMethod.POST, M + "/batches/" + id + "/rows", Map.of("first", 1, "rows", staged)));
        ok(it.call(token, HttpMethod.POST, M + "/batches/" + id + "/check", Map.of("from", 1, "to", rows.size())));
        return opened;
    }

    private Map<String, Object> importAll(String token, String id, int n) {
        ok(it.call(token, HttpMethod.POST, M + "/batches/" + id + "/import", Map.of("from", 1, "to", n)));
        return ok(it.call(token, HttpMethod.POST, M + "/batches/" + id + "/finish", Map.of()));
    }

    private Map<String, Object> rows(String token, String id, String status) {
        return ok(it.get(token, M + "/batches/" + id + "/rows?size=500" + (status == null ? "" : "&status=" + status)));
    }

    private long total(String token, String id, String status) {
        return ((Number) rows(token, id, status).get("total")).longValue();
    }

    private Map<String, Object> rowOf(String token, String id, String old) {
        return ((List<Map<String, Object>>) rows(token, id, null).get("rows")).stream().filter(r -> old.equals(r.get("legacy_no"))).findFirst().orElseThrow();
    }

    private static List<String> problemCodes(Map<String, Object> row) {
        return ((List<Map<String, Object>>) row.get("problems")).stream().map(p -> String.valueOf(p.get("code"))).toList();
    }

    /** the desk of a route, searched for one number */
    private Map<String, Object> desk(String token, String route, String query) {
        // the URI builder encodes the old number once (a String URL is encoded again by the client: "/" would reach the desk as "%2F")
        return ok(it.get(token, u -> u.path(DESK).queryParam("route", route).queryParam("q", query).queryParam("size", 50).build()));
    }

    private UUID appOf(String old) {
        return it.db(() -> jdbc.sql("SELECT application_id FROM admissions.prelim_legacy_application WHERE legacy_application_no = :o")
                .param("o", old).query(UUID.class).single());
    }

    private String numberOf(UUID app) {
        return it.db(() -> jdbc.sql("SELECT application_no FROM admissions.application WHERE id = :a").param("a", app).query(String.class).single());
    }

    /** the applicant signed in on the old number with the application number as the first password — and their own chosen at once
     *  if the portal requires it, so the rest of the portal opens */
    private String applicantToken(String old, String appNo) {
        ResponseEntity<Map> in = it.anon(HttpMethod.POST, "/api/v1/applicant/sign-in", Map.of("identifier", old, "password", appNo));
        assertThat(in.getStatusCode().value()).as(String.valueOf(in.getBody())).isEqualTo(200);
        String token = String.valueOf(in.getBody().get("token"));
        if (Boolean.TRUE.equals(in.getBody().get("mustChange"))) {
            ok(it.call(token, HttpMethod.POST, "/api/v1/applicant/me/password", Map.of("currentPassword", appNo, "newPassword", "Chosen-" + stamp() + "-pw")));
        }
        return token;
    }

    private String nameOf(String route) {
        return it.db(() -> jdbc.sql("SELECT name FROM admissions.prelim_programme WHERE route = :r").param("r", route).query(String.class).single());
    }

    /** the application fee the Bursary stated for the route, as the template states it (the fee and the portal charge) */
    private static String feeOf(Map<String, Object> template) {
        Map<String, Object> f = (Map<String, Object>) template.get("fee");
        java.math.BigDecimal a = new java.math.BigDecimal(String.valueOf(f.get("application")));
        java.math.BigDecimal p = f.get("portal") == null ? java.math.BigDecimal.ZERO : new java.math.BigDecimal(String.valueOf(f.get("portal")));
        return a.add(p).stripTrailingZeros().toPlainString();
    }

    private static String firstTarget(Map<String, Object> template) {
        return String.valueOf(((List<Map<String, Object>>) template.get("targets")).get(0).get("code"));
    }

    /* ── the tests ── */

    @Test
    void eachProgrammeHasItsOwnTemplateAndTheDoorsAreHeld() {
        String ict = it.officer("ict", "institution", "University");
        String registrar = it.officer("registrar", "institution", "University");
        String science = it.officer("prelim", "institution", "University");

        Map<String, Object> tech = ok(it.get(ict, M + "/template?route=" + TECH));
        assertThat(tech.get("fileName")).isEqualTo("PRELIMINARY_TECHNOLOGY_INDUSTRIAL_STUDIES_APPLICANTS_TEMPLATE.xlsx");
        assertThat((List<Map<String, Object>>) tech.get("columns")).extracting(c -> c.get("key"))
                .contains("legacyApplicationNo", "surname", "firstName", "gender", "dateOfBirth", "phone", "programme", "target", "specialisation",
                        "olevel1Body", "olevel1Results", "paymentReference", "paymentStatus", "applicationStatus", "admissionStatus");
        assertThat((List<Map<String, Object>>) tech.get("columns")).filteredOn(c -> "legacyApplicationNo".equals(c.get("key"))).singleElement()
                .satisfies(c -> assertThat(c.get("required")).isEqualTo(true));
        assertThat((List<Map<String, Object>>) tech.get("targets")).isNotEmpty();
        assertThat((List<String>) tech.get("grades")).contains("A1", "C6", "F9");
        Map<String, Object> sci = ok(it.get(ict, M + "/template?route=" + SCI));
        assertThat(sci.get("fileName")).isEqualTo("PRELIMINARY_SCIENCES_APPLICANTS_TEMPLATE.xlsx");
        assertThat((List<Map<String, Object>>) sci.get("columns")).extracting(c -> c.get("key")).contains("legacyApplicationNo", "target").doesNotContain("specialisation");
        assertThat(it.get(ict, M + "/template?route=PROFICIENCY_CERTIFICATE").getStatusCode().value()).isEqualTo(422);

        // the Director of ICT may upload and change a programme, never verify a fee; the Science office reads its own programme only
        Map<String, Object> access = ok(it.get(ict, M + "/access"));
        assertThat(access).containsEntry("mayMigrate", true).containsEntry("mayChangeProgramme", true).containsEntry("mayDecideFees", false)
                .containsEntry("mayReadDesk", true);
        assertThat((List<Map<String, Object>>) access.get("routes")).extracting(r -> r.get("route")).containsExactly(TECH, SCI);
        Map<String, Object> own = ok(it.get(science, M + "/access"));
        assertThat((List<Map<String, Object>>) own.get("routes")).extracting(r -> r.get("route")).containsExactly(SCI);
        assertThat(own).containsEntry("mayMigrate", false);
        assertThat(it.get(science, M + "/batches?route=" + TECH).getStatusCode().value()).isEqualTo(403);
        ok(it.get(science, M + "/batches?route=" + SCI));

        // the Registry reads and does not upload
        assertThat(it.get(registrar, M + "/template?route=" + TECH).getStatusCode().value()).isEqualTo(403);
        ok(it.get(registrar, M + "/batches"));

        // an ICT Support Agent the Director has not authorised: neither the upload nor the correction
        UUID agent = it.person("ZZ-PMIG-" + stamp(), "ZZPMIGAGENT");
        String support = TestTokens.token(agent, List.of("ictagent"));
        ResponseEntity<Map> template = it.get(support, M + "/template?route=" + TECH);
        assertThat(template.getStatusCode().value()).isEqualTo(403);
        assertThat(code(template)).isEqualTo("PRELIMMIG_CAPABILITY");
        assertThat(ok(it.get(support, M + "/access"))).containsEntry("mayMigrate", false).containsEntry("mayChangeProgramme", false)
                .containsEntry("mayReadDesk", false);
        ResponseEntity<Map> change = it.call(support, HttpMethod.POST, M + "/applicants/" + UUID.randomUUID() + "/change-programme",
                Map.of("to", SCI, "from", TECH, "reason", "The applicant applied for the other programme"));
        assertThat(change.getStatusCode().value()).isEqualTo(403);
        assertThat(code(change)).isEqualTo("PRELIM_CHANGE_CAPABILITY");
    }

    @Test
    void oldApplicantsComeInOnTheirOwnDeskAndTheOldFeeWaitsForTheBursary() {
        String uploader = it.officer("super", "institution", "University");   // an uploader who could otherwise verify a fee
        String bursar = it.officer("bursar", "institution", "University");
        String ict = it.officer("ict", "institution", "University");
        String s = stamp();
        Map<String, Object> techTemplate = ok(it.get(ict, M + "/template?route=" + TECH));
        Map<String, Object> sciTemplate = ok(it.get(ict, M + "/template?route=" + SCI));
        String techFee = feeOf(techTemplate), sciFee = feeOf(sciTemplate);
        String oldA = "OPT/" + s + "/1", oldB = "OPT/" + s + "/2", oldErr = "OPT/" + s + "/3", oldDup = "OPT/" + s + "/4", oldSci = "OPT/" + s + "/5";
        String refA = "ITPT-" + s + "-A";
        List<Map<String, Object>> techRows = List.of(
                paid(with(person(oldA, s + "a"), "programme", techTemplate.get("name"), "target", firstTarget(techTemplate)), refA, techFee),
                with(person(oldB, s + "b"), "programme", "pre-tech", "paymentStatus", "Not Paid", "admissionStatus", "Admitted"),
                with(person(oldErr, s + "c"), "surname", null),
                person(oldDup, s + "d"),
                person(oldDup, s + "e"),
                with(person(oldSci, s + "f"), "programme", sciTemplate.get("name")));

        // the dry run writes nothing but its verdicts: the missing surname an error, the twin a duplicate, the Science row a conflict
        Map<String, Object> opened = upload(uploader, TECH, techRows, "tech-" + s + ".xlsx", false);
        String batch = String.valueOf(opened.get("id"));
        assertThat(problemCodes(rowOf(uploader, batch, oldErr))).contains("MISSING_SURNAME");
        assertThat(rowOf(uploader, batch, oldErr).get("verdict")).isEqualTo("ERROR");
        Map<String, Object> dups = rows(uploader, batch, "DUPLICATE_IN_FILE");
        assertThat(((Number) dups.get("total")).intValue()).isPositive();
        assertThat((List<Map<String, Object>>) dups.get("rows")).allSatisfy(r -> assertThat(r.get("legacy_no")).isEqualTo(oldDup));
        Map<String, Object> mismatch = rowOf(uploader, batch, oldSci);
        assertThat(mismatch.get("verdict")).isEqualTo("CONFLICT");
        assertThat(problemCodes(mismatch)).contains("PROGRAMME_MISMATCH");
        assertThat(rowOf(uploader, batch, oldA).get("verdict")).as(String.valueOf(rowOf(uploader, batch, oldA))).isIn("READY", "WARNING");
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM admissions.prelim_legacy_application WHERE legacy_application_no LIKE :p")
                .param("p", "OPT/" + s + "/%").query(Long.class).single())).isZero();
        ResponseEntity<List> report = it.getList(uploader, M + "/batches/" + batch + "/report");
        assertThat(report.getStatusCode().value()).isEqualTo(200);
        assertThat(String.valueOf(report.getBody())).contains(oldErr, "MISSING_SURNAME", oldSci, "PROGRAMME_MISMATCH");

        // imported: the two good applicants and the first of the twins created (the repeat is the duplicate), the rest set aside
        importAll(uploader, batch, techRows.size());
        assertThat(total(uploader, batch, "CREATED")).isEqualTo(3);
        assertThat(total(uploader, batch, "SKIPPED")).isEqualTo(3);
        UUID appA = appOf(oldA), appB = appOf(oldB);
        String noA = numberOf(appA);
        assertThat(noA).matches("APP/\\d{2}/\\d{6}");
        // the row names the application's own programme and session, where its link goes
        String sessionA = it.db(() -> jdbc.sql("SELECT session FROM admissions.application WHERE id = :a").param("a", appA).query(String.class).single());
        assertThat(rowOf(uploader, batch, oldA)).containsEntry("appRoute", TECH).containsEntry("appSession", sessionA);

        // the Science file's applicant, on the Science desk
        String oldS = "OPS/" + s + "/1";
        List<Map<String, Object>> sciRows = List.of(paid(with(person(oldS, s + "s"), "target", firstTarget(sciTemplate), "olevel1Body", "WAEC",
                "olevel1Qualification", "SSCE", "olevel1Year", "2023", "olevel1Number", "4" + s, "olevel1Results",
                "English Language:C4; Mathematics:B3; Biology:C5; Chemistry:C6; Physics:C5"), "ITPS-" + s, sciFee));
        String sciBatch = String.valueOf(upload(ict, SCI, sciRows, "science-" + s + ".xlsx", false).get("id"));
        importAll(ict, sciBatch, 1);
        assertThat(total(ict, sciBatch, "CREATED")).isEqualTo(1);

        // each on its own programme's desk, with both numbers; the old number finds them; the fee held for the Bursary
        Map<String, Object> onTech = desk(ict, TECH, oldA);
        assertThat(((Number) onTech.get("total")).intValue()).isEqualTo(1);
        Map<String, Object> rowA = ((List<Map<String, Object>>) onTech.get("rows")).get(0);
        assertThat(rowA).containsEntry("application_no", noA).containsEntry("legacy_no", oldA).containsEntry("payment", "HELD").containsEntry("migrated", true);
        assertThat(((Number) desk(ict, SCI, oldA).get("total")).intValue()).isZero();
        assertThat(((Number) desk(ict, SCI, oldS).get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) desk(ict, TECH, oldS).get("total")).intValue()).isZero();
        assertThat(((Number) ok(it.get(ict, DESK + "?route=" + TECH + "&view=feeHeld&appNo=" + oldA)).get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) ok(it.get(ict, DESK + "?route=" + TECH + "&migrated=true&payment=HELD&q=" + oldA)).get("total")).intValue()).isEqualTo(1);
        assertThat(String.valueOf(it.getList(ict, M + "/find?q=" + oldA).getBody())).contains(noA);
        Map<String, Object> detail = ok(it.get(ict, "/api/v1/admissions/preliminary/applications/" + appA));
        assertThat(((Map<String, Object>) detail.get("legacy")).get("number")).isEqualTo(oldA);
        assertThat(detail.get("mayChangeProgramme")).isEqualTo(true);
        assertThat(((Map<String, Object>) detail.get("preliminary")).get("feeHeld")).isNotNull();
        ResponseEntity<List> overview = it.getList(ict, "/api/v1/admissions/preliminary/overview");
        assertThat(overview.getStatusCode().value()).as(String.valueOf(overview.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) overview.getBody()).extracting(o -> o.get("route")).containsExactly(TECH, SCI);
        assertThat((List<Map<String, Object>>) overview.getBody()).allSatisfy(o -> assertThat((Map<String, Object>) o.get("stats")).containsKeys("total", "migrated", "feeHeld"));

        // admitted on the old portal: published admitted here, with no second review
        Map<String, Object> b = it.db(() -> jdbc.sql("""
                SELECT r.state, r.published_at IS NOT NULL AS published, c.offer_state, r.route, c.entry_mode, c.jamb_reg_no IS NULL AS no_jamb
                  FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id JOIN admissions.candidate c ON c.id = a.candidate_id
                 WHERE r.application_id = :a
                """).param("a", appB).query().singleRow());
        assertThat(b).containsEntry("state", "ADMITTED").containsEntry("published", true).containsEntry("offer_state", "ADMITTED")
                .containsEntry("route", TECH).containsEntry("entry_mode", "PRELIMINARY").containsEntry("no_jamb", true);
        // an outcome published stands: its programme is not corrected
        ResponseEntity<Map> published = it.call(ict, HttpMethod.POST, M + "/applicants/" + appB + "/change-programme",
                Map.of("to", SCI, "from", TECH, "reason", "The applicant applied for Preliminary Science on the old portal"));
        assertThat(code(published)).as(String.valueOf(published.getBody())).isEqualTo("PRELIM_CHANGE_PUBLISHED");

        // told once, with both numbers
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM platform.notice WHERE event_key = 'prelim-migrated:' || :a").param("a", appA.toString())
                .query(Long.class).single())).isPositive();

        // the fee the old portal called paid is held: the applicant, signed in on the old number with the application number as the
        // first password (and asked to choose their own at once), is not asked to pay it again
        ResponseEntity<Map> first = it.anon(HttpMethod.POST, "/api/v1/applicant/sign-in", Map.of("identifier", oldA, "password", noA));
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
        assertThat(first.getBody().get("mustChange")).isEqualTo(true);
        String applicant = applicantToken(oldA, noA);
        ResponseEntity<Map> again = it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION"));
        assertThat(code(again)).as(String.valueOf(again.getBody())).isEqualTo("PRELIM_FEE_UNDER_REVIEW");
        assertThat(ok(it.get(applicant, "/api/v1/applicant/me/preliminary")).get("preliminary")).satisfies(p ->
                assertThat(((Map<String, Object>) p).get("feeHeld")).isNotNull());

        // the same file again: nothing created twice, and the history names the first upload
        long before = it.db(() -> jdbc.sql("""
                SELECT (SELECT count(*) FROM admissions.application) + (SELECT count(*) FROM admissions.fee_reference)
                     + (SELECT count(*) FROM admissions.prelim_legacy_fee) + (SELECT count(*) FROM admissions.prelim_legacy_application)
                """).query(Long.class).single());
        Map<String, Object> second = upload(uploader, TECH, techRows, "tech-" + s + ".xlsx", false);
        assertThat(String.valueOf(second.get("importedBefore"))).contains(String.valueOf(opened.get("reference")));
        String batch2 = String.valueOf(second.get("id"));
        importAll(uploader, batch2, techRows.size());
        assertThat(total(uploader, batch2, "UNCHANGED")).isEqualTo(3);
        assertThat(total(uploader, batch2, "CREATED")).isZero();
        long after = it.db(() -> jdbc.sql("""
                SELECT (SELECT count(*) FROM admissions.application) + (SELECT count(*) FROM admissions.fee_reference)
                     + (SELECT count(*) FROM admissions.prelim_legacy_fee) + (SELECT count(*) FROM admissions.prelim_legacy_application)
                """).query(Long.class).single());
        assertThat(after).isEqualTo(before);
        assertThat(String.valueOf(ok(it.get(uploader, M + "/batches?route=" + TECH + "&size=500")).get("rows"))).contains(String.valueOf(opened.get("reference")));

        // the officer who uploaded the fee does not verify it; another officer of the Bursary does — the old reference itself is posted,
        // and no other
        UUID fee = it.db(() -> jdbc.sql("SELECT id FROM admissions.prelim_legacy_fee WHERE legacy_reference = :r").param("r", refA).query(UUID.class).single());
        Map<String, Object> list = ok(it.get(uploader, M + "/fees?route=" + TECH + "&state=REQUIRES_REVIEW&size=500"));
        assertThat((List<Map<String, Object>>) list.get("rows")).filteredOn(r -> fee.toString().equals(String.valueOf(r.get("id")))).singleElement()
                .satisfies(r -> assertThat(r).containsEntry("uploadedByYou", true).containsEntry("mayDecide", false));
        ResponseEntity<Map> own = it.call(uploader, HttpMethod.POST, M + "/fees/" + fee + "/decide", Map.of("verify", true, "note", "IT: seen on the statement"));
        assertThat(code(own)).as(String.valueOf(own.getBody())).isEqualTo("PRELIMMIG_SAME_OFFICER");
        assertThat(it.call(ict, HttpMethod.POST, M + "/fees/" + fee + "/decide", Map.of("verify", true, "note", "IT: seen on the statement")).getStatusCode().value())
                .isEqualTo(403);
        ok(it.call(bursar, HttpMethod.POST, M + "/fees/" + fee + "/decide", Map.of("verify", true, "note", "IT: seen on the bank statement")));
        Map<String, Object> posted = it.db(() -> jdbc.sql("""
                SELECT (SELECT a.fee_confirmed_at IS NOT NULL FROM admissions.application a WHERE a.id = :a) AS paid,
                       (SELECT count(*) FROM admissions.fee_reference f WHERE f.application_id = :a AND f.kind = 'APPLICATION') AS refs,
                       (SELECT string_agg(f.reference, ',') FROM admissions.fee_reference f WHERE f.application_id = :a AND f.confirmed_at IS NOT NULL) AS reference,
                       (SELECT l.state FROM admissions.prelim_legacy_fee l WHERE l.id = :f) AS state
                """).param("a", appA).param("f", fee).query().singleRow());
        assertThat(posted).containsEntry("paid", true).containsEntry("reference", refA).containsEntry("state", "VERIFIED");
        assertThat(((Number) posted.get("refs")).intValue()).isEqualTo(1);
        assertThat(desk(ict, TECH, oldA).get("rows")).satisfies(r -> assertThat(((List<Map<String, Object>>) r).get(0)).containsEntry("payment", "PAID"));
    }

    @Test
    void theDirectorOfIctMovesAnApplicantToTheOtherProgrammeTheRecordAndFeeKept() {
        String ict = it.officer("ict", "institution", "University");
        String bursar = it.officer("bursar", "institution", "University");
        String s = stamp();
        Map<String, Object> techTemplate = ok(it.get(ict, M + "/template?route=" + TECH));
        String old = "OPC/" + s + "/1", ref = "ITPC-" + s;
        List<Map<String, Object>> rows = List.of(paid(with(person(old, s + "m"), "target", firstTarget(techTemplate)), ref, feeOf(techTemplate)));
        String batch = String.valueOf(upload(ict, TECH, rows, "correction-" + s + ".xlsx", false).get("id"));
        importAll(ict, batch, 1);
        UUID app = appOf(old);
        String number = numberOf(app);
        UUID fee = it.db(() -> jdbc.sql("SELECT id FROM admissions.prelim_legacy_fee WHERE legacy_reference = :r").param("r", ref).query(UUID.class).single());
        ok(it.call(bursar, HttpMethod.POST, M + "/fees/" + fee + "/decide", Map.of("verify", true, "note", "IT: seen on the bank statement")));
        String feesBefore = it.db(() -> jdbc.sql("""
                SELECT string_agg(f.id || ':' || f.reference || ':' || coalesce(f.confirmed_at::text, '-'), ',' ORDER BY f.id) || '|' || a.fee_confirmed_at::text
                  FROM admissions.application a LEFT JOIN admissions.fee_reference f ON f.application_id = a.id WHERE a.id = :a GROUP BY a.fee_confirmed_at
                """).param("a", app).query(String.class).single());

        // the record and what the change would do
        Map<String, Object> record = ok(it.get(ict, M + "/applicants/" + app));
        assertThat(record).containsEntry("route", TECH).containsEntry("applicationNo", number).containsEntry("legacyNo", old).containsEntry("may", true);
        assertThat(((Map<String, Object>) record.get("fee")).get("status")).isEqualTo("PAID");
        Map<String, Object> check = ok(it.get(ict, M + "/applicants/" + app + "/change-check?to=" + SCI));
        assertThat(check.get("may")).as(String.valueOf(check)).isEqualTo(true);

        // the Director of ICT moves the applicant: one record, the same number, the fee as it was
        ok(it.call(ict, HttpMethod.POST, M + "/applicants/" + app + "/change-programme",
                Map.of("to", SCI, "from", TECH, "reason", "The applicant applied for Preliminary Science on the old portal form")));
        Map<String, Object> now = it.db(() -> jdbc.sql("""
                SELECT r.route, a.application_no, c.programme,
                       (SELECT count(*) FROM admissions.prelim_route_change x WHERE x.application_id = a.id AND x.result = 'APPLIED') AS changes,
                       (SELECT count(*) FROM admissions.application y WHERE y.account_id = a.account_id) AS applications
                  FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id JOIN admissions.candidate c ON c.id = a.candidate_id
                 WHERE a.id = :a
                """).param("a", app).query().singleRow());
        assertThat(now).containsEntry("route", SCI).containsEntry("application_no", number).containsEntry("programme", nameOf(SCI));
        assertThat(((Number) now.get("changes")).intValue()).isEqualTo(1);
        assertThat(((Number) now.get("applications")).intValue()).isEqualTo(1);
        String feesAfter = it.db(() -> jdbc.sql("""
                SELECT string_agg(f.id || ':' || f.reference || ':' || coalesce(f.confirmed_at::text, '-'), ',' ORDER BY f.id) || '|' || a.fee_confirmed_at::text
                  FROM admissions.application a LEFT JOIN admissions.fee_reference f ON f.application_id = a.id WHERE a.id = :a GROUP BY a.fee_confirmed_at
                """).param("a", app).query(String.class).single());
        assertThat(feesAfter).isEqualTo(feesBefore);
        assertThat(((Number) desk(ict, SCI, old).get("total")).intValue()).isEqualTo(1);
        assertThat(((Number) desk(ict, TECH, old).get("total")).intValue()).isZero();
        assertThat(((Number) ok(it.get(ict, M + "/corrections?route=" + SCI + "&size=500")).get("total")).intValue()).isPositive();
        assertThat((List<Map<String, Object>>) ok(it.get(ict, M + "/applicants/" + app)).get("routeChanges")).isNotEmpty();
        // the applicant's own pages name the new programme
        String applicant = applicantToken(old, number);
        Map<String, Object> me = ok(it.get(applicant, "/api/v1/applicant/me"));
        assertThat(me).containsEntry("programme", nameOf(SCI)).containsEntry("route", SCI);

        // a correction made on what the record no longer says is refused, and written down
        ResponseEntity<Map> stale = it.call(ict, HttpMethod.POST, M + "/applicants/" + app + "/change-programme",
                Map.of("to", SCI, "from", TECH, "reason", "The applicant applied for Preliminary Science on the old portal form"));
        assertThat(stale.getStatusCode().value()).isEqualTo(422);
        assertThat(code(stale)).startsWith("PRELIM_CHANGE_");
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM admissions.prelim_route_change WHERE application_id = :a AND result = 'REFUSED'")
                .param("a", app).query(Long.class).single())).isPositive();

        // ICT Support: refused both until the Director posts the agent over the whole University with the capabilities
        UUID agent = it.person("ZZ-PMIG-" + stamp(), "ZZPMIGAGENT");
        String support = TestTokens.token(agent, List.of("ictagent"));
        Map<String, Object> back = Map.of("to", TECH, "from", SCI, "reason", "The University corrected the programme back to Technology");
        ResponseEntity<Map> refused = it.call(support, HttpMethod.POST, M + "/applicants/" + app + "/change-programme", back);
        assertThat(refused.getStatusCode().value()).isEqualTo(403);
        assertThat(code(refused)).isEqualTo("PRELIM_CHANGE_CAPABILITY");
        ResponseEntity<Map> upload = it.call(support, HttpMethod.POST, M + "/batches", Map.of("route", TECH, "fileName", "agent.xlsx", "rows", 1));
        assertThat(upload.getStatusCode().value()).isEqualTo(403);
        assertThat(code(upload)).isEqualTo("PRELIMMIG_CAPABILITY");
        // a posting over one faculty does not reach an applicant
        String faculty = it.db(() -> jdbc.sql("SELECT code FROM ref.faculty ORDER BY code LIMIT 1").query(String.class).single());
        it.db(() -> jdbc.sql("""
                INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities)
                VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'FACULTY', :f, ARRAY['MIGRATE_PRELIM_APPLICANTS', 'CHANGE_PRELIM_PROGRAMME'])
                """).param("p", agent).param("f", faculty).update());
        assertThat(code(it.get(support, M + "/template?route=" + TECH))).isEqualTo("PRELIMMIG_CAPABILITY");
        try {
            it.db(() -> jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, capabilities)
                    VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'GLOBAL', ARRAY['MIGRATE_PRELIM_APPLICANTS', 'CHANGE_PRELIM_PROGRAMME'])
                    """).param("p", agent).update());
            assertThat(ok(it.get(support, M + "/access"))).containsEntry("mayMigrate", true).containsEntry("mayChangeProgramme", true);
            ok(it.get(support, M + "/template?route=" + TECH));
            Map<String, Object> byAgent = ok(it.call(support, HttpMethod.POST, M + "/batches", Map.of("route", TECH, "fileName", "agent-" + s + ".xlsx",
                    "sha256", sha(List.of(Map.of("agent", s))), "rows", 1, "tell", false)));
            ok(it.call(support, HttpMethod.POST, M + "/batches/" + byAgent.get("id") + "/abandon", Map.of("reason", "IT: an authorised agent may open a batch")));
            ok(it.call(support, HttpMethod.POST, M + "/applicants/" + app + "/change-programme", back));
            assertThat(it.db(() -> jdbc.sql("SELECT route FROM admissions.prelim_review WHERE application_id = :a").param("a", app).query(String.class).single()))
                    .isEqualTo(TECH);
        } finally {
            it.db(() -> jdbc.sql("UPDATE helpdesk.agent_assignment SET active = false, effective_to = current_date WHERE person_id = :p AND active")
                    .param("p", agent).update());
        }
    }

    @Test
    void aFeeTheBursaryRejectedIsNotHeldAgainAndEachOfficeFindsItsOwnApplicants() {
        String ict = it.officer("ict", "institution", "University");
        String bursar = it.officer("bursar", "institution", "University");
        String science = it.officer("prelim", "institution", "University");
        String s = stamp();
        Map<String, Object> sciTemplate = ok(it.get(ict, M + "/template?route=" + SCI));
        Map<String, Object> techTemplate = ok(it.get(ict, M + "/template?route=" + TECH));
        String shared = "Zr" + letters(10);   // a surname the two programmes' applicants share
        String old = "OPR/" + s + "/1", oldTech = "OPR/" + s + "/2", portalShaped = "APP/99/" + s.substring(3);
        // paid on the old portal with no reference given; and a row whose old number is shaped like this portal's application number
        List<Map<String, Object>> sciRows = List.of(
                with(person(old, s + "r"), "surname", shared + "s", "target", firstTarget(sciTemplate), "olevel1Body", "WAEC", "olevel1Qualification", "SSCE",
                        "olevel1Year", "2023", "olevel1Number", "5" + s, "olevel1Results", "English Language:C4; Mathematics:B3; Biology:C5; Chemistry:C6; Physics:C5",
                        "paymentStatus", "Paid", "amountPaid", feeOf(sciTemplate), "paymentDate", "15/03/2026"),
                person(portalShaped, s + "p"));
        String batch = String.valueOf(upload(ict, SCI, sciRows, "rejected-" + s + ".xlsx", false).get("id"));
        Map<String, Object> shaped = rowOf(ict, batch, portalShaped);
        assertThat(shaped.get("verdict")).as(String.valueOf(shaped)).isEqualTo("ERROR");
        assertThat(problemCodes(shaped)).contains("LEGACY_NO_IS_PORTAL_NUMBER");
        importAll(ict, batch, sciRows.size());
        assertThat(total(ict, batch, "CREATED")).isEqualTo(1);
        assertThat(total(ict, batch, "SKIPPED")).isEqualTo(1);
        UUID app = appOf(old);
        String number = numberOf(app);

        // the Bursary finds no such payment; the same file uploaded again to update the applicants does not hold the fee again
        UUID fee = it.db(() -> jdbc.sql("SELECT id FROM admissions.prelim_legacy_fee WHERE application_id = :a AND state = 'REQUIRES_REVIEW'")
                .param("a", app).query(UUID.class).single());
        Map<String, Object> rejected = ok(it.call(bursar, HttpMethod.POST, M + "/fees/" + fee + "/decide",
                Map.of("verify", false, "note", "IT: no such payment on the bank statement")));
        assertThat(rejected.get("state")).isEqualTo("REJECTED");
        String again = String.valueOf(upload(ict, SCI, sciRows, "rejected-" + s + "-again.xlsx", true).get("id"));
        importAll(ict, again, sciRows.size());
        Map<String, Object> fees = it.db(() -> jdbc.sql("""
                SELECT count(*) FILTER (WHERE f.state <> 'REJECTED') AS held, admissions.prelim_fee_status(:a) AS status
                  FROM admissions.prelim_legacy_fee f WHERE f.application_id = :a
                """).param("a", app).query().singleRow());
        assertThat(((Number) fees.get("held")).intValue()).isZero();
        assertThat(fees.get("status")).isEqualTo("UNPAID");

        // so the applicant, signed in on the old number and asked to choose a password, draws a reference and pays here
        ResponseEntity<Map> first = it.anon(HttpMethod.POST, "/api/v1/applicant/sign-in", Map.of("identifier", old, "password", number));
        assertThat(first.getStatusCode().value()).as(String.valueOf(first.getBody())).isEqualTo(200);
        assertThat(first.getBody().get("mustChange")).isEqualTo(true);
        String applicant = applicantToken(old, number);
        Map<String, Object> drawn = ok(it.call(applicant, HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "APPLICATION")));
        assertThat(String.valueOf(drawn.get("reference"))).isNotBlank().isNotEqualTo("null");

        // a password forgotten: the Forgot-password door knows the old number, however its letters are typed
        UUID account = it.db(() -> jdbc.sql("SELECT account_id FROM admissions.application WHERE id = :a").param("a", app).query(UUID.class).single());
        assertThat(it.anon(HttpMethod.POST, "/api/v1/auth/forgot", Map.of("identifier", old.toLowerCase())).getStatusCode().value()).isEqualTo(202);
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) FROM iam.password_reset WHERE subject_kind = 'APPLICANT' AND subject_id = :s")
                .param("s", account).query(Long.class).single())).isPositive();

        // a Technology applicant of the same surname: the Director of ICT finds both, the Science office its own only
        List<Map<String, Object>> techRows = List.of(with(person(oldTech, s + "t"), "surname", shared + "t", "target", firstTarget(techTemplate)));
        String techBatch = String.valueOf(upload(ict, TECH, techRows, "shared-" + s + ".xlsx", false).get("id"));
        importAll(ict, techBatch, 1);
        assertThat((List<Map<String, Object>>) it.getList(ict, M + "/find?q=" + shared).getBody()).extracting(r -> r.get("route")).contains(TECH, SCI);
        List<Map<String, Object>> own = it.getList(science, M + "/find?q=" + shared).getBody();
        assertThat(own).extracting(r -> r.get("route")).containsOnly(SCI);
        assertThat(own).extracting(r -> r.get("application_no")).contains(number);

        // an ICT Support Agent who may only change a programme finds the applicant and reads the corrections, never the uploads or the fees
        UUID agent = it.person("ZZ-PMIG-" + stamp(), "ZZPMIGAGENT");
        String support = TestTokens.token(agent, List.of("ictagent"));
        try {
            it.db(() -> jdbc.sql("""
                    INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, capabilities)
                    VALUES (:p, 'STUDENT_BIODATA_SUPPORT', 'GLOBAL', ARRAY['CHANGE_PRELIM_PROGRAMME'])
                    """).param("p", agent).update());
            assertThat(ok(it.get(support, M + "/access"))).containsEntry("mayChangeProgramme", true).containsEntry("mayRead", false)
                    .containsEntry("mayReadCorrections", true).containsEntry("mayReadDesk", false);
            assertThat(code(it.get(support, M + "/batches"))).isEqualTo("PRELIMMIG_CAPABILITY");
            assertThat(code(it.get(support, M + "/batches/" + batch + "/rows"))).isEqualTo("PRELIMMIG_CAPABILITY");
            assertThat(code(it.get(support, M + "/fees"))).isEqualTo("PRELIMMIG_CAPABILITY");
            ResponseEntity<List> found = it.getList(support, M + "/find?q=" + shared);
            assertThat(found.getStatusCode().value()).isEqualTo(200);
            assertThat((List<Map<String, Object>>) found.getBody()).extracting(r -> r.get("route")).contains(TECH, SCI);
            ok(it.get(support, M + "/corrections"));
        } finally {
            it.db(() -> jdbc.sql("UPDATE helpdesk.agent_assignment SET active = false, effective_to = current_date WHERE person_id = :p AND active")
                    .param("p", agent).update());
        }
    }
}
