package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

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
 * V771: a past result keeps the course as it was taken. An invented programme in a session of the run's own, one course the catalogue
 * holds at 4 units: the old portal's results of four students — A, B and C at 100 Level, G in the final year — loaded at the 3 units
 * the file states; G approved by the Senate on a CGPA of 4.50. A corrected template puts A and G at 2 units: the check says so row by
 * row with each student's units counted before and after and G among the graduates, and writes nothing; the upload corrects both under
 * its reference, the catalogue untouched; the report lists G first for the Registry and A's units counted 3 before and 2 after; the
 * broadsheet heads the column at the 3 units most of its students took it at and shows A's own 2; the graduation audit leaves G's
 * approved CGPA as the Senate approved it. The uploads are confirmed, loaded, closed and read by their offices only. A closed upload is
 * rolled back by the Directorate of ICT alone, once, never while it runs: A's corrected units go back to the 3 first loaded, and the
 * report keeps listing the file's rows that were not a plain load (a row without its title among them) with every row counted by
 * status. The report reads each change's category as the record read it on each side — an elective by the programme's basis filed
 * Core reads ELECTIVE then CORE, a GST course filed Core reads GST — and reads it so still after the course is renamed and
 * reclassified (the ledger keeps the course's kind); a dropped course approved again under a result entered on the portal reads the
 * record's own title on both sides, never the file's (V775). A results file loaded for a student whose result is still held posts the
 * held result first, under the upload that held it, and says so in its check and its answer; meeting a reconcile of the same held rows
 * in a circle, the batch PostgreSQL ends is loaded again by its door (V775). Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class HistoricalCourseAsTakenIT {

    static final String TITLE = "Foundations of Records Kept";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;
    @Autowired
    javax.sql.DataSource dataSource;

    ItSupport it;
    /** one Director of ICT throughout: an upload is loaded and closed by the person who confirmed it */
    final UUID director = UUID.randomUUID();
    final String ict = TestTokens.token(director, List.of("ict"));
    int year;
    String session;
    String prog;
    String course;
    final Map<String, String> matric = new LinkedHashMap<>();
    final Map<String, UUID> id = new HashMap<>();

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        year = it.freeYear(2300, 2900);
        session = year + "/" + (year + 1);
        it.session(session, year);
        String px = it.freeCoursePrefix("Z");
        course = px + " 101";
        String yy = String.format("%02d", year % 100);
        List<String> who = List.of("A", "B", "C", "G");
        int n = it.freeDraw(1000, 9000, k -> {
            List<String> ids = new java.util.ArrayList<>();
            for (int i = 0; i < who.size(); i++) {
                ids.add("ZZHCT" + who.get(i) + k);
                ids.add("MOAUM/HCT/" + yy + "/" + (i + 1) + k);
                ids.add("MOAUM/ADM/" + yy + "/8" + (i + 1) + k);
            }
            return ids;
        });
        prog = it.db(() -> {
            String[] one = jdbc.sql("""
                    SELECT p.dept_code || ',' || p.faculty_code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' ORDER BY p.code LIMIT 1
                    """).query(String.class).single().split(",");
            String code = jdbc.sql("SELECT 'C' || x FROM generate_series(95000, 95999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 1")
                    .query(String.class).single();
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                    VALUES (:c, 'B.Sc. Course As Taken Test ' || :c, :d, :f, 'UNDER GRADUATE', 0, 400, 4)
                    """).param("c", code).param("d", one[0]).param("f", one[1]).update();
            // today's catalogue holds the course at 4 units; the old portal's file says otherwise, and the file is the record
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, ca_max) VALUES (:c, :t, 4, 1, 100, :d, 'Core', 'LIVE', 40)")
                    .param("c", course).param("t", TITLE).param("d", one[0]).update();
            return code;
        });
        for (int i = 0; i < who.size(); i++) {
            String w = who.get(i);
            matric.put(w, "MOAUM/HCT/" + yy + "/" + (i + 1) + n);
            id.put(w, it.student("ZZHCT" + w + n, prog, "MOAUM/ADM/" + yy + "/8" + (i + 1) + n, matric.get(w), "G".equals(w) ? 400 : 100));
        }
        // G is in the final year of the session: a finalist the graduation audit reads
        it.db(() -> jdbc.sql("INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :s, :ses, 400) ON CONFLICT DO NOTHING")
                .param("s", id.get("G")).param("ses", session).update());
    }

    /** a row of the past results template: the course as taken — title, credit units, category — and the mark */
    private Map<String, String> row(String line, String who, int units) {
        return Map.of("line", line, "matric", matric.get(who), "course", course, "title", TITLE, "creditUnits", String.valueOf(units),
                "category", "Core", "level", "G".equals(who) ? "400" : "100", "total", "70");
    }

    private Map<String, Object> body(List<Map<String, String>> rows, Object upload) {
        Map<String, Object> body = new HashMap<>();
        body.put("session", session);
        body.put("semester", 1);
        body.put("rows", rows);
        if (upload != null) body.put("uploadId", String.valueOf(upload));
        return body;
    }

    private static Map<String, Object> confirm(String kind, String reason) {
        return Map.of("kind", kind, "fileName", "as-taken.xlsx", "rows", 1, "reason", reason);
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private static void refused(ResponseEntity<Map> r, int status, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(status);
        if (code != null) assertThat(r.getBody()).as(String.valueOf(r.getBody())).containsEntry("code", code);
    }

    private static Map<String, String> statusByLine(Map<String, Object> body) {
        return ((List<Map<String, Object>>) body.get("lines")).stream()
                .collect(Collectors.toMap(l -> String.valueOf(l.get("line")), l -> String.valueOf(l.get("status")), (a, b) -> a));
    }

    private int units(String who) {
        return jdbc.sql("""
                SELECT e.units FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                  JOIN catalogue.offering o ON o.id = e.offering_id WHERE r.student_id = :s AND r.session = :ses AND o.course_code = :c
                """).param("s", id.get(who)).param("ses", session).param("c", course).query(Integer.class).single();
    }

    /** a row of either template for any course of the run: the course as taken — code, title, credit units, category — and, on a
     *  results file, the mark */
    private Map<String, String> taken(String line, String who, String code, String title, int units, String category, String total) {
        Map<String, String> row = new HashMap<>(Map.of("line", line, "matric", matric.get(who), "course", code, "title", title,
                "creditUnits", String.valueOf(units), "category", category, "level", "100"));
        if (total != null) row.put("total", total);
        return row;
    }

    /** an upload's report read again: its changes of one course — by the code the ledger kept, which a rename does not move — of the
     *  kinds named, in the report's order */
    private List<Map<String, Object>> changes(Object upload, String code, String... kinds) {
        Map<String, Object> report = ok(it.get(ict, "/api/v1/results/legacy/uploads/" + upload));
        return ((List<Map<String, Object>>) report.get("changes")).stream()
                .filter(c -> code.equals(c.get("courseCode")) && List.of(kinds).contains(String.valueOf(c.get("kind")))).collect(Collectors.toList());
    }

    /** those changes, each as "KIND was>now": the category the record read on each side (null where the course was not on record) */
    private List<String> categories(Object upload, String code, String... kinds) {
        return changes(upload, code, kinds).stream().map(c -> c.get("kind") + " " + c.get("wasCategory") + ">" + c.get("nowCategory"))
                .collect(Collectors.toList());
    }

    @Test
    void theUploadsAreConfirmedLoadedClosedAndReadByTheirOfficesOnly() {
        String reason = "HistoricalCourseAsTakenIT: the old portal's records of the semester";
        List<Map<String, String>> rows = List.of(row("2", "A", 3));

        // past results are confirmed by the Directorate of ICT; the migration desk's other offices confirm a registration only
        for (String office : List.of("records", "registrar", "academic")) {
            refused(it.call(ItSupport.token(office), HttpMethod.POST, "/api/v1/results/legacy/uploads", confirm("RESULTS", reason)), 403, null);
        }
        for (String office : List.of("lecturer", "bursar")) {
            refused(it.call(ItSupport.token(office), HttpMethod.POST, "/api/v1/results/legacy/uploads", confirm("REGISTRATION", reason)), 403, null);
        }
        String registrar = ItSupport.token("registrar");
        Map<String, Object> reg = ok(it.call(registrar, HttpMethod.POST, "/api/v1/results/legacy/uploads", confirm("REGISTRATION", reason)));
        assertThat(reg).containsEntry("state", "RUNNING").containsEntry("kind", "REGISTRATION").containsEntry("createdOffice", "registrar");
        refused(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads", confirm("RESULTS", "too short")), 422, "LEGACY_UPLOAD_REASON");
        Map<String, Object> res = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads", confirm("RESULTS", reason)));
        assertThat(res).containsEntry("state", "RUNNING").containsEntry("kind", "RESULTS").containsEntry("rows", 1).containsEntry("fileName", "as-taken.xlsx");

        // an import names its upload — the officer's own, still running, of its kind
        refused(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results", body(rows, null)), 400, "LEGACY_UPLOAD_REQUIRED");
        refused(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results", body(rows, reg.get("id"))), 403, "LEGACY_UPLOAD_OWN");
        refused(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/registration", body(rows, res.get("id"))), 422, "LEGACY_UPLOAD_STATE");
        assertThat(jdbc.sql("SELECT count(*) FROM registration.course_registration WHERE student_id = :s").param("s", id.get("A")).query(Integer.class).single())
                .as("nothing loaded by a refused import").isZero();

        // closed by the person who opened it, once; a closed upload takes no more batches
        refused(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + reg.get("id") + "/finish", Map.of("complete", true)), 403, "LEGACY_UPLOAD_OWN");
        assertThat(ok(it.call(registrar, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + reg.get("id") + "/finish", Map.of("complete", false))))
                .containsEntry("state", "INCOMPLETE");
        refused(it.call(registrar, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + reg.get("id") + "/finish", Map.of("complete", true)), 422, "LEGACY_UPLOAD_STATE");
        ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + res.get("id") + "/finish", Map.of("complete", true)));
        refused(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results", body(rows, res.get("id"))), 422, "LEGACY_UPLOAD_STATE");

        // read by the offices that load them, the Registry and the Academic Office; not by a lecturer or the Bursary
        for (String office : List.of("ict", "super", "records", "academic", "registrar", "dregistrar")) {
            String token = ItSupport.token(office);
            ResponseEntity<List> list = it.getList(token, "/api/v1/results/legacy/uploads?limit=500");
            assertThat(list.getStatusCode().value()).as(office).isEqualTo(200);
            assertThat((List<Map<String, Object>>) list.getBody()).as(office).extracting(u -> u.get("id")).contains(res.get("id"), reg.get("id"));
            Map<String, Object> report = ok(it.get(token, "/api/v1/results/legacy/uploads/" + res.get("id")));
            assertThat((Map<String, Object>) report.get("upload")).containsEntry("ref", res.get("ref")).containsEntry("state", "COMPLETE");
            assertThat(report).containsEntry("changesTotal", 0);
        }
        for (String office : List.of("lecturer", "bursar")) {
            refused(it.get(ItSupport.token(office), "/api/v1/results/legacy/uploads"), 403, null);
            refused(it.get(ItSupport.token(office), "/api/v1/results/legacy/uploads/" + res.get("id")), 403, null);
        }
        refused(it.get(registrar, "/api/v1/results/legacy/uploads/" + UUID.randomUUID()), 404, null);
    }

    @Test
    void aCorrectedTemplateCorrectsTheUnitsAsTakenAndAnApprovedGraduateKeepsTheirCgpa() {
        // ── the old portal's results as first loaded: every student at 3 units ──
        Map<String, Object> first = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads",
                confirm("RESULTS", "HistoricalCourseAsTakenIT: the old portal's results as exported")));
        Map<String, Object> loaded = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results",
                body(List.of(row("2", "A", 3), row("3", "B", 3), row("4", "C", 3), row("5", "G", 3)), first.get("id"))));
        assertThat(((Number) loaded.get("results")).intValue()).isEqualTo(4);
        assertThat(((Number) loaded.get("entries")).intValue()).isEqualTo(4);
        assertThat(loaded).containsEntry("upload", first.get("ref"));
        ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + first.get("id") + "/finish", Map.of("complete", true)));
        assertThat(units("A")).isEqualTo(3);

        // G approved by the Senate on a CGPA of 4.50 (the Senate's figure, whatever the record reads now)
        it.db(() -> jdbc.sql("""
                INSERT INTO records.graduand (id, student_id, session, cgpa, award, senate_state, senate_minute)
                VALUES (gen_random_uuid(), :s, :ses, 4.50, 'B.Sc. Course As Taken Test', 'APPROVED', 'IT V771')
                """).param("s", id.get("G")).param("ses", session).update());

        // ── the corrected template, checked: A and G at 2 units, each student's units before and after, G a graduate; nothing written ──
        List<Map<String, String>> corrected = List.of(row("2", "A", 2), row("3", "G", 2));
        Map<String, Object> check = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results/preview", body(corrected, null)));
        assertThat(statusByLine(check)).containsEntry("2", "UNITS_CORRECTED").containsEntry("3", "UNITS_CORRECTED");
        assertThat((List<Map<String, Object>>) check.get("lines")).allSatisfy(l -> assertThat(l).containsEntry("match", "CODE_AND_TITLE")
                .containsEntry("uploadedTitle", TITLE).containsEntry("currentUnits", 4));
        Map<String, Object> gpaA = ((List<Map<String, Object>>) check.get("gpa")).stream().filter(g -> matric.get("A").equals(g.get("matric"))).findFirst().orElseThrow();
        assertThat((Map<String, Object>) gpaA.get("before")).containsEntry("tcr", 3);
        assertThat((Map<String, Object>) gpaA.get("after")).containsEntry("tcr", 2);
        assertThat((List<String>) check.get("graduates")).containsExactly(matric.get("G"));
        assertThat(units("A")).as("a check writes nothing").isEqualTo(3);

        // ── the corrected template, uploaded under its reference ──
        Map<String, Object> second = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads",
                confirm("RESULTS", "HistoricalCourseAsTakenIT: the template corrected by the department")));
        Map<String, Object> up = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results", body(corrected, second.get("id"))));
        assertThat(((Number) up.get("units_corrected")).intValue()).isEqualTo(2);
        assertThat(((Number) up.get("results")).intValue()).as("the same marks are not posted again").isZero();
        assertThat((List<String>) up.get("graduates")).containsExactly(matric.get("G"));
        Map<String, Object> closed = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + second.get("id") + "/finish", Map.of("complete", true)));
        assertThat((Map<String, Object>) closed.get("counts")).containsEntry("changes", 2).containsEntry("students", 2).containsEntry("graduates", 1);
        assertThat(units("A")).isEqualTo(2);
        assertThat(units("G")).isEqualTo(2);
        assertThat(units("B")).isEqualTo(3);
        assertThat(jdbc.sql("SELECT units FROM catalogue.course WHERE code = :c").param("c", course).query(Integer.class).single())
                .as("today's catalogue untouched").isEqualTo(4);

        // ── the list and the report, as the Registry reads them: G first, kept apart; A's units counted before and after ──
        String registrar = ItSupport.token("registrar");
        ResponseEntity<List> list = it.getList(registrar, "/api/v1/results/legacy/uploads?limit=500");
        assertThat(list.getStatusCode().value()).isEqualTo(200);
        Map<String, Object> listed = ((List<Map<String, Object>>) list.getBody()).stream().filter(u -> second.get("id").equals(u.get("id"))).findFirst().orElseThrow();
        assertThat(listed).containsEntry("ref", second.get("ref")).containsEntry("state", "COMPLETE").containsEntry("createdOffice", "ict").containsEntry("kind", "RESULTS");
        Map<String, Object> report = ok(it.get(registrar, "/api/v1/results/legacy/uploads/" + second.get("id")));
        assertThat((Map<String, Object>) report.get("byKind")).containsExactlyEntriesOf(Map.of("UNITS_CORRECTED", 2));
        assertThat(report).containsEntry("changesTotal", 2);
        List<Map<String, Object>> students = (List<Map<String, Object>>) report.get("students");
        assertThat(students).extracting(s -> s.get("matric")).containsExactly(matric.get("G"), matric.get("A"));
        assertThat(students.get(1)).containsEntry("tcrBefore", 3).containsEntry("tcrAfter", 2).containsEntry("graduate", false);
        assertThat((List<Map<String, Object>>) report.get("graduates")).extracting(s -> s.get("matric")).containsExactly(matric.get("G"));
        // each change with the category the record read on each side (the programme's basis first, never the entry's type alone)
        assertThat((List<Map<String, Object>>) report.get("changes")).allSatisfy(c -> assertThat(c).containsEntry("kind", "UNITS_CORRECTED")
                .containsEntry("wasUnits", 3).containsEntry("nowUnits", 2).containsEntry("courseCode", course)
                .containsEntry("wasCategory", "CORE").containsEntry("nowCategory", "CORE"));

        // ── the broadsheet: the column at the 3 units most of its students took it at, A at their own 2 ──
        Map<String, Object> sheet = ok(it.get(ict, "/api/v1/results/broadsheet?prog=" + prog + "&level=100&session=" + session + "&sem=1"));
        Map<String, Object> column = ((List<Map<String, Object>>) sheet.get("courses")).stream().filter(c -> course.equals(c.get("courseCode"))).findFirst().orElseThrow();
        assertThat(column).containsEntry("units", 3).containsEntry("unitsVary", true).containsEntry("codeAsTaken", course).containsEntry("title", TITLE);
        Map<String, Object> rowA = ((List<Map<String, Object>>) sheet.get("rows")).stream().filter(r -> matric.get("A").equals(r.get("number"))).findFirst().orElseThrow();
        assertThat((List<Map<String, Object>>) rowA.get("marks")).anySatisfy(m -> assertThat(m).containsEntry("courseCode", course).containsEntry("units", 2));
        assertThat(rowA).containsEntry("units", 2);
        Map<String, Object> rowB = ((List<Map<String, Object>>) sheet.get("rows")).stream().filter(r -> matric.get("B").equals(r.get("number"))).findFirst().orElseThrow();
        assertThat((List<Map<String, Object>>) rowB.get("marks")).anySatisfy(m -> assertThat(m).containsEntry("courseCode", course).containsEntry("units", 3));

        // ── the graduation audit: G's approved CGPA stays the Senate's (the University's decision of 15 November 2026) ──
        Map<String, Object> audit = ok(it.call(ItSupport.token("academic"), HttpMethod.POST, "/api/v1/graduation/sessions/" + session + "/audit", null));
        assertThat(((Number) audit.get("audited")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(jdbc.sql("SELECT cgpa FROM records.graduand WHERE student_id = :s AND session = :ses").param("s", id.get("G")).param("ses", session)
                .query(BigDecimal.class).single()).isEqualByComparingTo("4.50");
    }

    @Test
    void aClosedUploadIsRolledBackByTheDirectorateOfIctAndItsReportListsTheRowsNotLoaded() {
        // ── the old portal's results as first loaded: A and B at 3 units; a plain load lists no row ──
        Map<String, Object> first = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads",
                confirm("RESULTS", "HistoricalCourseAsTakenIT: the old portal's results as exported")));
        ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results", body(List.of(row("2", "A", 3), row("3", "B", 3)), first.get("id"))));
        ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + first.get("id") + "/finish", Map.of("complete", true)));
        assertThat(units("A")).isEqualTo(3);
        Map<String, Object> plain = ok(it.get(ict, "/api/v1/results/legacy/uploads/" + first.get("id")));
        assertThat((List<Map<String, Object>>) plain.get("rows")).isEmpty();
        assertThat(plain).containsEntry("rowsTotal", 0);
        assertThat((Map<String, Object>) plain.get("byStatus")).containsExactlyEntriesOf(Map.of("RESULT_POSTED", 2));

        // ── the corrected template: A at 2 units, B's row without its title (refused, nothing taken from today's catalogue) ──
        Map<String, String> untitled = new HashMap<>(row("10", "B", 3));
        untitled.put("title", "");
        Map<String, Object> second = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads",
                confirm("RESULTS", "HistoricalCourseAsTakenIT: the template corrected by the department")));
        assertThat(second).containsEntry("createdBy", director.toString());
        Map<String, Object> up = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results", body(List.of(untitled, row("2", "A", 2)), second.get("id"))));
        assertThat(((Number) up.get("units_corrected")).intValue()).isEqualTo(1);
        assertThat(((Number) up.get("as_taken_missing")).intValue()).isEqualTo(1);
        assertThat(units("A")).isEqualTo(2);

        // never rolled back while it runs: closed first
        String revert = "/api/v1/results/legacy/uploads/" + second.get("id") + "/revert";
        Map<String, Object> why = Map.of("reason", "The department withdrew the corrected template");
        refused(it.call(ict, HttpMethod.POST, revert, why), 422, "LEGACY_UPLOAD_STATE");
        assertThat(units("A")).isEqualTo(2);
        ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + second.get("id") + "/finish", Map.of("complete", true)));

        // ── the report: the rows that were not a plain load, by line in number order; every row counted by status ──
        Map<String, Object> report = ok(it.get(ict, "/api/v1/results/legacy/uploads/" + second.get("id")));
        List<Map<String, Object>> rows = (List<Map<String, Object>>) report.get("rows");
        assertThat(rows).extracting(r -> r.get("line") + " " + r.get("status")).containsExactly("2 UNITS_CORRECTED", "10 AS_TAKEN_MISSING");
        assertThat(rows.get(1)).containsEntry("matric", matric.get("B")).containsEntry("course", course).containsEntry("session", session).containsEntry("semester", 1);
        assertThat(String.valueOf(rows.get(1).get("detail"))).contains("course title");
        assertThat((Map<String, Object>) rows.get(1).get("facts")).containsEntry("uploadedCode", course).containsEntry("uploadedUnits", "3")
                .containsEntry("category", "Core");
        assertThat(report).containsEntry("rowsTotal", 2);
        assertThat((Map<String, Object>) report.get("byStatus")).containsOnly(Map.entry("UNITS_CORRECTED", 1), Map.entry("AS_TAKEN_MISSING", 1));
        assertThat((Map<String, Object>) report.get("byEntryStatus")).as("each entry's fate is its row's status here").isEmpty();

        // ── rolled back by the offices that load past results — not Records, not the Registry — with a reason, once ──
        for (String office : List.of("records", "registrar")) {
            refused(it.call(ItSupport.token(office), HttpMethod.POST, revert, why), 403, null);
        }
        refused(it.call(ict, HttpMethod.POST, revert, Map.of("reason", "too short")), 422, "LEGACY_UPLOAD_REASON");
        assertThat(units("A")).isEqualTo(2);
        Map<String, Object> back = ok(it.call(ItSupport.token("ict"), HttpMethod.POST, revert, why));
        assertThat(back).containsEntry("ref", second.get("ref")).containsEntry("state", "REVERTED").containsEntry("undone", 1).containsEntry("left", 0)
                .containsEntry("heldDropped", 0).containsEntry("earlierUndone", 0).containsEntry("leftChanges", List.of());
        assertThat(units("A")).as("the corrected units back as first loaded").isEqualTo(3);
        assertThat(units("B")).isEqualTo(3);
        refused(it.call(ict, HttpMethod.POST, revert, why), 422, "LEGACY_UPLOAD_STATE");
        assertThat(units("A")).isEqualTo(3);

        // ── the upload read after: rolled back, why, what was undone; each change with when; the rows still listed ──
        Map<String, Object> after = ok(it.get(ItSupport.token("registrar"), "/api/v1/results/legacy/uploads/" + second.get("id")));
        assertThat((Map<String, Object>) after.get("upload")).containsEntry("state", "REVERTED").containsEntry("revertReason", why.get("reason"))
                .containsEntry("revertCounts", Map.of("undone", 1, "left", 0, "heldDropped", 0, "earlierUndone", 0)).containsKey("revertedAt");
        assertThat((List<Map<String, Object>>) after.get("changes")).singleElement()
                .satisfies(c -> assertThat(c).containsEntry("kind", "UNITS_CORRECTED").containsKey("revertedAt"));
        assertThat(after).containsEntry("rowsTotal", 2);
    }

    @Test
    void theReportReadsACategoryAsTheRecordReadItWhateverTheCatalogueSaysSinceAndACourseKeptAsOnRecordByItsOwnTitle() {
        // two more courses of the run's own, in the first one's department: one of kind GST, one for a result entered on the portal
        String px = course.substring(0, 3);
        String gst = px + " 102";
        String renamed = px + " 192";
        String portal = px + " 103";
        String gstTitle = "Use of Records Kept";
        String portalTitle = "Records Entered on the Portal";
        it.db(() -> {
            String dept = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", course).query(String.class).single();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, ca_max) VALUES (:c, :t, 2, 1, 100, :d, 'GST', 'LIVE', 40)")
                    .param("c", gst).param("t", gstTitle).param("d", dept).update();
            return jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, ca_max) VALUES (:c, :t, 2, 1, 100, :d, 'Core', 'LIVE', 40)")
                    .param("c", portal).param("t", portalTitle).param("d", dept).update();
        });

        // ── the registration as the old portal filed it: A's course an elective, C's course core ──
        Map<String, Object> reg = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads",
                confirm("REGISTRATION", "HistoricalCourseAsTakenIT: the old portal's registration as exported")));
        Map<String, Object> registered = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/registration", body(List.of(
                taken("2", "A", course, TITLE, 3, "Elective", null), taken("3", "C", portal, portalTitle, 2, "Core", null)), reg.get("id"))));
        assertThat(registered).as(String.valueOf(registered.get("lines"))).containsEntry("refused", 0).containsEntry("entries", 2);
        ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + reg.get("id") + "/finish", Map.of("complete", true)));

        // A's course typed CURRENT: an elective by the programme's basis alone, which the entry's type does not say
        assertThat(it.db(() -> jdbc.sql("""
                UPDATE registration.entry e SET entry_type = 'CURRENT' FROM registration.course_registration r
                 WHERE r.id = e.registration_id AND r.student_id = :s AND r.session = :ses AND e.entry_type = 'ELECTIVE' AND e.basis = 'Elective'
                """).param("s", id.get("A")).param("ses", session).update())).as("A's course, filed Elective, typed CURRENT").isEqualTo(1);
        // C's course: a result entered on the portal (CA 20, exam 35), and the course then dropped
        assertThat(it.db(() -> {
            UUID sheet = jdbc.sql("""
                    INSERT INTO assessment.score_sheet (id, offering_id)
                    SELECT gen_random_uuid(), o.id FROM catalogue.offering o WHERE o.course_code = :c AND o.session = :ses AND o.semester = 1
                    RETURNING id
                    """).param("c", portal).param("ses", session).query(UUID.class).single();
            jdbc.sql("INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) VALUES (:sh, :s, 20, 35, 'GRADED')")
                    .param("sh", sheet).param("s", id.get("C")).update();
            return jdbc.sql("""
                    UPDATE registration.entry e SET status = 'DROPPED' FROM registration.course_registration r
                     WHERE r.id = e.registration_id AND r.student_id = :s AND r.session = :ses AND e.status = 'APPROVED'
                    """).param("s", id.get("C")).param("ses", session).update();
        })).as("C's course, marked on the portal, dropped").isEqualTo(1);

        // ── the results file: A's course filed Core; the GST course filed Core for B, who has nothing on record; C's dropped course
        //    under another title, with another mark ──
        Map<String, Object> res = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads",
                confirm("RESULTS", "HistoricalCourseAsTakenIT: the old portal's results as exported")));
        Object upload = res.get("id");
        Map<String, Object> up = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results", body(List.of(
                taken("2", "A", course, TITLE, 3, "Core", "70"), taken("3", "B", gst, gstTitle, 2, "Core", "65"),
                taken("4", "C", portal, portalTitle + " Retitled", 2, "Core", "61")), upload)));
        assertThat(up).as(String.valueOf(up.get("lines"))).containsEntry("refused", 0).containsEntry("category_corrected", 1).containsEntry("entries", 1)
                .containsEntry("results", 2).containsEntry("reapproved", 1).containsEntry("results_on_portal", 1);
        ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + upload + "/finish", Map.of("complete", true)));

        // ── each change with the category the record read on each side: the programme's basis first (the entry's type, CURRENT on
        //    both sides, says nothing of it), and a GST course GST whatever the file calls it — nothing before, where it was not on record ──
        assertThat(categories(upload, course, "CATEGORY_CORRECTED", "RESULT_POSTED"))
                .containsExactly("CATEGORY_CORRECTED ELECTIVE>CORE", "RESULT_POSTED ELECTIVE>CORE");
        assertThat(categories(upload, gst, "ENTRY_ADDED", "RESULT_POSTED")).containsExactly("ENTRY_ADDED null>GST", "RESULT_POSTED null>GST");

        // ── the GST course renamed: the report reads as it did, under the code the ledger kept (nothing under the new one) ──
        assertThat(it.db(() -> jdbc.sql("SELECT catalogue.rename_course(:o, :n)").param("o", gst).param("n", renamed).query(String.class).single()))
                .isEqualTo(renamed);
        assertThat(categories(upload, gst, "ENTRY_ADDED", "RESULT_POSTED")).containsExactly("ENTRY_ADDED null>GST", "RESULT_POSTED null>GST");
        assertThat(changes(upload, renamed, "ENTRY_ADDED", "RESULT_POSTED")).isEmpty();

        // ── and reclassified Core: the report STILL reads GST on both changes — the kind the ledger kept, not today's catalogue ──
        assertThat(it.db(() -> jdbc.sql("UPDATE catalogue.course SET kind = 'Core' WHERE code = :c").param("c", renamed).update())).isEqualTo(1);
        assertThat(categories(upload, gst, "ENTRY_ADDED", "RESULT_POSTED")).containsExactly("ENTRY_ADDED null>GST", "RESULT_POSTED null>GST");
        assertThat(categories(upload, course, "CATEGORY_CORRECTED", "RESULT_POSTED"))
                .containsExactly("CATEGORY_CORRECTED ELECTIVE>CORE", "RESULT_POSTED ELECTIVE>CORE");

        // ── V775: C's dropped course is approved again as it stands on record — a result entered on the portal stands on it — so the
        //    change reads the record's code and title on both sides; the file's title was not taken ──
        assertThat(changes(upload, portal, "ENTRY_REAPPROVED")).singleElement().satisfies(c -> assertThat(c)
                .containsEntry("wasStatus", "DROPPED").containsEntry("nowStatus", "APPROVED").containsEntry("wasCode", portal).containsEntry("nowCode", portal)
                .containsEntry("wasTitle", portalTitle).containsEntry("nowTitle", portalTitle));
    }

    /** one statement of the holder's, on its own connection */
    @FunctionalInterface
    private interface Hold {
        void on(java.sql.Connection holder) throws java.sql.SQLException;
    }

    private static void run(java.sql.Connection c, String sql) throws java.sql.SQLException {
        try (java.sql.Statement s = c.createStatement()) {
            s.execute(sql);
        }
    }

    /**
     * The door called while a connection of the test's own has done {@code first}; once the door waits on what that holds, the
     * connection does {@code then}, which waits on what the door holds already: a deadlock. PostgreSQL ends the door's transaction,
     * which waited first (the holder's deadlock_timeout is set long where the role may, so it is never the one ended); the connection's
     * {@code then} goes through once the door's transaction is ended under it, and the connection lets go. Returns the door's answer.
     */
    private ResponseEntity<Map> clash(java.util.function.Supplier<ResponseEntity<Map>> door, Hold first, Hold then) throws Exception {
        java.util.concurrent.ExecutorService pool = java.util.concurrent.Executors.newFixedThreadPool(2);
        try (java.sql.Connection holder = dataSource.getConnection()) {
            holder.setAutoCommit(false);
            try {
                int pid;
                try (java.sql.Statement s = holder.createStatement()) {
                    s.execute("SELECT set_config('deadlock_timeout', '60s', true) FROM pg_roles WHERE rolname = current_user AND rolsuper");
                    try (java.sql.ResultSet r = s.executeQuery("SELECT pg_backend_pid()")) {
                        r.next();
                        pid = r.getInt(1);
                    }
                }
                first.on(holder);
                java.util.concurrent.Future<ResponseEntity<Map>> answer = pool.submit(door::get);
                boolean waiting = false;
                for (int i = 0; i < 1200 && !waiting; i++) {   // up to a minute
                    waiting = jdbc.sql("SELECT EXISTS (SELECT 1 FROM pg_locks l WHERE NOT l.granted AND CAST(:pid AS int) = ANY (pg_blocking_pids(l.pid)))")
                            .param("pid", pid).query(Boolean.class).single();
                    if (!waiting) Thread.sleep(50);
                }
                assertThat(waiting).as("the door waits on what the connection holds").isTrue();
                java.util.concurrent.Future<Object> closed = pool.submit(() -> {
                    then.on(holder);
                    holder.rollback();
                    return null;
                });
                closed.get(90, java.util.concurrent.TimeUnit.SECONDS);
                return answer.get(120, java.util.concurrent.TimeUnit.SECONDS);
            } finally {
                holder.rollback();
            }
        } finally {
            pool.shutdownNow();
        }
    }

    private BigDecimal counted(UUID student) {
        return jdbc.sql("SELECT x.total FROM assessment.student_results(:s) x WHERE x.course_code = :c")
                .param("s", student).param("c", course).query(BigDecimal.class).single();
    }

    @Test
    void aResultsFileForAStudentWhoseResultIsStillHeldPostsItFirstAndIsLoadedAgainWhenItMeetsAReconcile() throws Exception {
        // ── the result goes up before the student is on the register: held under the first upload ──
        String late = it.freeNumber("MOAUM/HCL/" + String.format("%02d", year % 100) + "/", 6);
        matric.put("L", late);
        Map<String, Object> first = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads",
                confirm("RESULTS", "HistoricalCourseAsTakenIT: results uploaded before their student")));
        Map<String, Object> held = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results",
                body(List.of(taken("2", "L", course, TITLE, 3, "Core", "50")), first.get("id"))));
        assertThat(((Number) held.get("held")).intValue()).isEqualTo(1);
        ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + first.get("id") + "/finish", Map.of("complete", true)));
        java.util.function.IntSupplier holds = () -> jdbc.sql("SELECT count(*) FROM assessment.legacy_result_holding WHERE matric = :m")
                .param("m", late).query(Integer.class).single();
        assertThat(holds.getAsInt()).isEqualTo(1);

        // ── the student is put on the register by a route that runs no reconcile; the corrected file is checked ──
        UUID student = it.student(it.freeSurname("ZZHCTL"), prog, null, late, 100);
        List<Map<String, String>> corrected = List.of(taken("2", "L", course, TITLE, 3, "Core", "61"));
        Map<String, Object> check = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results/preview", body(corrected, null)));
        assertThat(((Number) check.get("held_posted_first")).intValue()).as("the check says the held result posts first").isEqualTo(1);
        assertThat(((Number) check.get("results_replaced")).intValue()).isEqualTo(1);
        assertThat((List<String>) check.get("students_affected")).containsExactly(late);
        Map<String, Object> picture = ((List<Map<String, Object>>) check.get("gpa")).get(0);
        assertThat(((Number) ((Map<String, Object>) picture.get("before")).get("tcr")).intValue())
                .as("against the record as it stands: nothing counted yet").isZero();
        assertThat(((Number) ((Map<String, Object>) picture.get("after")).get("tcr")).intValue()).isEqualTo(3);
        assertThat(holds.getAsInt()).as("the check posted nothing").isEqualTo(1);

        // ── the file is loaded while a reconcile has taken the held rows; the reconcile then wants the file's upload (which the batch
        //    holds): a circle. PostgreSQL ends the batch; its door loads it again, and the answer is the load's ──
        Map<String, Object> second = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads",
                confirm("RESULTS", "HistoricalCourseAsTakenIT: the file corrected by the department")));
        Map<String, Object> loaded = ok(clash(
                () -> it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/results", body(corrected, second.get("id"))),
                holder -> run(holder, "SELECT 1 FROM assessment.legacy_result_holding WHERE matric = '" + late + "' FOR UPDATE"),
                holder -> run(holder, "SELECT 1 FROM assessment.past_upload WHERE id = '" + second.get("id") + "' FOR UPDATE")));
        assertThat(((Number) loaded.get("held_posted_first")).intValue()).isEqualTo(1);
        assertThat(((Number) loaded.get("results")).intValue()).isEqualTo(1);
        assertThat(((Number) loaded.get("results_replaced")).intValue()).isEqualTo(1);
        ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + second.get("id") + "/finish", Map.of("complete", true)));

        // the held result is the first upload's, the corrected mark the second's, and the corrected mark is what counts
        assertThat(holds.getAsInt()).isZero();
        assertThat(changes(first.get("id"), course, "RESULT_POSTED")).hasSize(1);
        assertThat(changes(first.get("id"), course, "RESULT_REPLACED")).isEmpty();
        assertThat(changes(second.get("id"), course, "RESULT_REPLACED")).hasSize(1);
        assertThat(counted(student)).isEqualByComparingTo("61");
        // the first upload's counts on the Uploads list follow what posted under it after it was closed
        assertThat(jdbc.sql("SELECT (pu.counts->>'changes')::int FROM assessment.past_upload pu WHERE pu.id = CAST(:u AS uuid)")
                .param("u", String.valueOf(first.get("id"))).query(Integer.class).single()).isEqualTo(4);

        // rolling the second upload back gives the first upload's result back
        Map<String, Object> rolled = ok(it.call(ict, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + second.get("id") + "/revert",
                Map.of("reason", "HistoricalCourseAsTakenIT: the corrected file was the wrong one")));
        assertThat(rolled).containsEntry("state", "REVERTED");
        assertThat(counted(student)).isEqualByComparingTo("50");
    }
}
