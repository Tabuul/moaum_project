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
 * status. Needs DATABASE_URL.
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
}
