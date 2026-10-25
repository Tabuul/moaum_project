package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * V652: the course registration report and examination attendance over the API. Two programmes of the test's own in departments
 * of two faculties, a session of the test's own; Ada and Bola of the first (Ada holds the examination card, Bola carries the core
 * course over), Chi of the second (the GST &amp; EPS permit). A core course of the first department and a GST course, offered in the
 * first semester. The first department's Examinations Officer reads the report of their department only (another department
 * refused), issues the two sheets (their department's students, the card or permit marked), is refused a second issue without a
 * reason and given V2 with one, marks the list, is refused a student of another department, enters a handwritten row whose number
 * names nobody and matches it to Ada, and reconciles. The second department's Head reads Chi's row alone, sees none of the first
 * department's sheets and issues their own. The GST office reads its own course alone, is refused the core course's sheet and issues
 * the GST course's sheets by faculty; the export carries a DBO/REG reference. A lecturer reads none of it; the Bursar issues nothing.
 * Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ExamAttendanceIT {

    private static final String R = "/api/v1/reports/course-registrations";
    private static final String A = "/api/v1/exams/attendance";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private static List<Map<String, Object>> rows(ResponseEntity<Map> r) {
        return (List<Map<String, Object>>) r.getBody().get("rows");
    }

    private static void refused(ResponseEntity<Map> r, String code) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isIn(403, 422);
        if (code != null) assertThat(r.getBody()).as(String.valueOf(r.getBody())).containsEntry("code", code);
    }

    private static void ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
    }

    @Test
    void theReportScopedTheSheetsVersionedTheListMarkedTheHandwrittenRowsMatchedAndReconciled() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        int y = it.freeYear(4500, 4590, 0, 1);
        String session = y + "/" + (y + 1);
        it.session(session, y);
        String yy = String.format("%02d", y % 100);
        int n = 1000 + new Random().nextInt(8999);
        String[] place = it.db(() -> {
            String[] one = jdbc.sql("""
                    SELECT p.dept_code || ',' || p.faculty_code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' ORDER BY p.code LIMIT 1
                    """).query(String.class).single().split(",");
            String[] two = jdbc.sql("""
                    SELECT p.dept_code || ',' || p.faculty_code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' AND p.faculty_code <> :f ORDER BY p.code LIMIT 1
                    """).param("f", one[1]).query(String.class).single().split(",");
            List<String> codes = jdbc.sql("SELECT 'C' || x FROM generate_series(96500, 96999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 2")
                    .query(String.class).list();
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                    VALUES (:c1, 'B.Sc. Attendance Test One', :d1, :f1, 'UNDER GRADUATE', 0, 400, 4), (:c2, 'B.Sc. Attendance Test Two', :d2, :f2, 'UNDER GRADUATE', 0, 400, 4)
                    """).param("c1", codes.get(0)).param("d1", one[0]).param("f1", one[1]).param("c2", codes.get(1)).param("d2", two[0]).param("f2", two[1]).update();
            return new String[] {one[0], one[1], two[0], two[1], codes.get(0), codes.get(1)};
        });
        String d1 = place[0], f1 = place[1], d2 = place[2], f2 = place[3], p1 = place[4], p2 = place[5];
        String matricAda = "MOAUM/ATT/" + yy + "/1" + n, matricBola = "MOAUM/ATT/" + yy + "/2" + n, matricChi = "MOAUM/ATT/" + yy + "/3" + n;
        UUID ada = it.student("ZZATTADA" + n, p1, "MOAUM/ADM/" + yy + "/71" + n, matricAda, 300);
        UUID bola = it.student("ZZATTBOLA" + n, p1, "MOAUM/ADM/" + yy + "/72" + n, matricBola, 300);
        UUID chi = it.student("ZZATTCHI" + n, p2, "MOAUM/ADM/" + yy + "/73" + n, matricChi, 300);
        String core = "ZAT " + (100 + n % 800);
        String gst = "GST " + (900 + n % 99);
        UUID[] off = it.db(() -> {
            jdbc.sql("UPDATE people.student SET sex = CASE WHEN id = :a THEN 'M' ELSE 'F' END WHERE id IN (:a, :b, :c)").param("a", ada).param("b", bola).param("c", chi).update();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES (:c, 'Attendance Test Core', 3, 1, 300, :d, 'Core', 'LIVE'), (:g, 'Attendance Test GST', 2, 1, 300, :d, 'GST', 'LIVE') ON CONFLICT DO NOTHING")
                    .param("c", core).param("g", gst).param("d", d1).update();
            UUID oc = UUID.randomUUID(), og = UUID.randomUUID(), ra = UUID.randomUUID(), rb = UUID.randomUUID(), rc = UUID.randomUUID();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:oc, :c, :s, 1), (:og, :g, :s, 1)")
                    .param("oc", oc).param("og", og).param("c", core).param("g", gst).param("s", session).update();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at) VALUES (:ra, :a, :s, 1, 300, 'SUBMITTED', now()), (:rb, :b, :s, 1, 300, 'SUBMITTED', now()), (:rc, :c, :s, 1, 300, 'SUBMITTED', now())")
                    .param("ra", ra).param("rb", rb).param("rc", rc).param("a", ada).param("b", bola).param("c", chi).param("s", session).update();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, entry_type) VALUES (:ra, :oc, 3, 'CURRENT'), (:ra, :og, 2, 'CURRENT'), (:rb, :oc, 3, 'CARRYOVER'), (:rb, :og, 2, 'CURRENT'), (:rc, :og, 2, 'CURRENT')")
                    .param("ra", ra).param("rb", rb).param("rc", rc).param("oc", oc).param("og", og).update();
            jdbc.sql("INSERT INTO registration.exam_card_issue (student_id, session, semester, times) VALUES (:a, :s, 1, 1)").param("a", ada).param("s", session).update();
            jdbc.sql("INSERT INTO registration.gst_eps_permit (reference, student_id, session, semester, printed) VALUES (:r, :c, :s, 1, 1)")
                    .param("r", "GST-EPS/" + y + "/98" + n).param("c", chi).param("s", session).update();
            return new UUID[] {oc, og};
        });
        UUID oc = off[0], og = off[1];
        String q = "?session=" + session + "&semester=1";

        // ── the first department's Examinations Officer: their department only ──
        String exams = it.officer("exams", "department", d1);
        ResponseEntity<Map> report = it.get(exams, R + q);
        ok(report);
        assertThat(report.getBody()).containsEntry("total", 4);
        assertThat(rows(report)).extracting(r -> r.get("student_id")).containsOnly(ada.toString(), bola.toString());
        assertThat(rows(report)).filteredOn(r -> ada.toString().equals(r.get("student_id")) && core.equals(r.get("course_code")))
                .singleElement().satisfies(r -> assertThat(r).containsEntry("category", "DEPARTMENTAL").containsEntry("eligible", true).containsEntry("fees_paid", false));
        assertThat(rows(report)).filteredOn(r -> bola.toString().equals(r.get("student_id")) && core.equals(r.get("course_code")))
                .singleElement().satisfies(r -> assertThat(r).containsEntry("carry_over", true).containsEntry("eligible", false));
        refused(it.get(exams, R + q + "&dept=" + d2), "SCOPE_DEPARTMENT");
        ResponseEntity<Map> summary = it.get(exams, R + "/summary" + q);
        ok(summary);
        assertThat(rows(summary)).filteredOn(r -> "TOTAL".equals(r.get("dimension"))).singleElement()
                .satisfies(r -> assertThat(r).containsEntry("registrations", 4).containsEntry("students", 2).containsEntry("carry_over", 1).containsEntry("eligible", 1));
        ResponseEntity<Map> courses = it.get(exams, R + "/courses" + q);
        ok(courses);
        assertThat(rows(courses)).extracting(r -> r.get("course_code")).containsExactlyInAnyOrder(core, gst);

        // the sheets: their department's students, the card or permit marked; again only with a reason, as V2
        ResponseEntity<Map> issued = it.call(exams, HttpMethod.POST, A + "/sheets", Map.of("offerings", List.of(oc.toString(), og.toString()), "manualLines", 10));
        ok(issued);
        assertThat(issued.getBody()).containsEntry("issued", 2).containsEntry("students", 4);
        List<Map<String, Object>> sheets = (List<Map<String, Object>>) issued.getBody().get("sheets");
        String coreV1 = sheets.stream().filter(s -> oc.toString().equals(String.valueOf(s.get("offering_id")))).map(s -> String.valueOf(s.get("reference"))).findFirst().orElseThrow();
        assertThat(coreV1).matches("ATT/" + core.replace(" ", "") + "/" + y + "/[0-9]{5}/V1");
        assertThat(sheets).allSatisfy(s -> assertThat(s).containsEntry("scope_dept", d1.toUpperCase()).containsEntry("manual_lines", 10));
        refused(it.call(exams, HttpMethod.POST, A + "/sheets", Map.of("offerings", List.of(oc.toString()), "manualLines", 10)), "ATTENDANCE_REISSUE_REASON");
        ResponseEntity<Map> v2 = it.call(exams, HttpMethod.POST, A + "/sheets", Map.of("offerings", List.of(oc.toString()), "manualLines", 15, "reason", "A correction to the list"));
        ok(v2);
        String coreV2 = String.valueOf(((List<Map<String, Object>>) v2.getBody().get("sheets")).get(0).get("reference"));
        assertThat(coreV2).isEqualTo(coreV1.substring(0, coreV1.length() - 2) + "V2");
        ResponseEntity<Map> printed = it.get(exams, A + "/sheets/by-reference?reference=" + coreV1);
        ok(printed);
        assertThat(printed.getBody()).containsEntry("latest_reference", coreV2).containsEntry("version", 1);
        assertThat((List<Map<String, Object>>) printed.getBody().get("list")).extracting(x -> x.get("eligibility")).containsExactlyInAnyOrder("CARD", "NO_CARD");
        ResponseEntity<Map> gstSheet = it.get(exams, A + "/sheets?offering=" + og);
        ok(gstSheet);
        assertThat((List<Map<String, Object>>) gstSheet.getBody().get("sheets")).singleElement().satisfies(s -> assertThat(s).containsEntry("students", 2));

        // the list marked; a student of another department refused, by the list and by a handwritten number
        ok(it.get(exams, A + "/" + oc));
        assertThat((List<Map<String, Object>>) it.get(exams, A + "/" + oc).getBody().get("students")).hasSize(2);
        ResponseEntity<Map> marked = it.call(exams, HttpMethod.POST, A + "/" + oc + "/marks", Map.of("sheet", coreV2, "invigilator", "Test Invigilator",
                "marks", List.of(Map.of("student", ada.toString(), "status", "PRESENT"), Map.of("student", bola.toString(), "status", "ABSENT"))));
        ok(marked);
        assertThat(marked.getBody()).containsEntry("recorded", 2);
        refused(it.call(exams, HttpMethod.POST, A + "/" + oc + "/marks", Map.of("marks", List.of(Map.of("student", chi.toString(), "status", "PRESENT")))), "SCOPE_STUDENT");
        refused(it.call(exams, HttpMethod.POST, A + "/" + oc + "/manual", Map.of("number", matricChi, "name", "Chi")), "SCOPE_STUDENT");
        refused(it.call(exams, HttpMethod.POST, A + "/" + oc + "/marks", Map.of("marks", List.of(Map.of("student", ada.toString(), "status", "SLEEPING")))), "ATTENDANCE_STATUS");

        // a handwritten row whose number names nobody: held, then matched to Bola (marked absent on the list) by her matriculation number
        ResponseEntity<Map> hand = it.call(exams, HttpMethod.POST, A + "/" + oc + "/manual", Map.of("number", "NO-SUCH-" + n, "name", "Written By Hand", "reason", "Late registration", "sheet", coreV2));
        ok(hand);
        assertThat(hand.getBody()).containsEntry("outcome", "PENDING").containsEntry("why", "NO_MATCH");
        ResponseEntity<Map> pending = it.get(exams, A + "/" + oc + "/pending");
        ok(pending);
        Map<String, Object> row = rows(pending).stream().filter(r -> ("NO-SUCH-" + n).equals(r.get("written_number"))).findFirst().orElseThrow();
        ResponseEntity<Map> decided = it.call(exams, HttpMethod.POST, A + "/pending/" + row.get("id") + "/decide", Map.of("valid", true, "number", matricBola));
        ok(decided);
        assertThat(decided.getBody()).containsEntry("outcome", "MATCHED");
        refused(it.call(exams, HttpMethod.POST, A + "/pending/" + row.get("id") + "/decide", Map.of("valid", false, "note", "Too late now")), "ATTENDANCE_PENDING_DECIDED");

        ResponseEntity<Map> recon = it.get(exams, A + "/" + oc + "/reconciliation");
        ok(recon);
        // Bola sat by the handwritten row without the card: present without it
        assertThat(rows(recon)).extracting(r -> r.get("student_id") + "=" + r.get("finding")).containsExactlyInAnyOrder(ada + "=OK", bola + "=PRESENT_NOT_ELIGIBLE");
        assertThat((Map<String, Object>) recon.getBody().get("figures")).containsEntry("registered", 2).containsEntry("listed", 2).containsEntry("present", 2)
                .containsEntry("absent", 0).containsEntry("manual", 1);
        assertThat(jdbc.sql("SELECT status || '/' || source || '/' || (verified_at IS NOT NULL) FROM assessment.exam_attendance WHERE offering_id = :o AND student_id = :s")
                .param("o", oc).param("s", bola).query(String.class).single()).isEqualTo("MANUAL_PRESENT/MANUAL/true");

        // ── the second department's Head: Chi alone, none of the first department's sheets, their own ──
        String hod = it.officer("hod", "department", d2);
        ResponseEntity<Map> hodReport = it.get(hod, R + q);
        ok(hodReport);
        assertThat(rows(hodReport)).extracting(r -> r.get("student_id") + "/" + r.get("course_code")).containsExactly(chi + "/" + gst);
        assertThat((List<Map<String, Object>>) it.get(hod, A + "/sheets?offering=" + oc).getBody().get("sheets")).isEmpty();
        refused(it.get(hod, A + "/sheets/by-reference?reference=" + coreV1), "SCOPE_SHEET");
        ResponseEntity<Map> hodSheet = it.call(hod, HttpMethod.POST, A + "/sheets", Map.of("offerings", List.of(og.toString()), "manualLines", 5));
        ok(hodSheet);
        assertThat(((List<Map<String, Object>>) hodSheet.getBody().get("sheets")).get(0)).containsEntry("students", 1).containsEntry("scope_dept", d2.toUpperCase());

        // ── the GST office: its own course alone; the core course's sheet refused; the GST course's sheets by faculty; the export's reference ──
        String gstOffice = it.officer("gst", "institution", "University");
        ResponseEntity<Map> gstReport = it.get(gstOffice, R + q);
        ok(gstReport);
        assertThat(rows(gstReport)).extracting(r -> r.get("course_code")).containsOnly(gst).hasSize(3);
        refused(it.call(gstOffice, HttpMethod.POST, A + "/sheets", Map.of("offerings", List.of(oc.toString()), "manualLines", 5)), "ATTENDANCE_NOT_OFFICE_COURSE");
        ResponseEntity<Map> byFaculty = it.call(gstOffice, HttpMethod.POST, A + "/sheets", Map.of("offerings", List.of(og.toString()), "manualLines", 5, "split", "FACULTY"));
        ok(byFaculty);
        assertThat((List<Map<String, Object>>) byFaculty.getBody().get("sheets")).extracting(s -> s.get("scope_fac") + ":" + s.get("students"))
                .containsExactlyInAnyOrder(f1.toUpperCase() + ":2", f2.toUpperCase() + ":1");
        ResponseEntity<Map> export = it.get(gstOffice, R + "/export" + q);
        ok(export);
        assertThat(String.valueOf(export.getBody().get("reference"))).matches("DBO/REG/[0-9]{4}/[0-9]{6}");
        assertThat(rows(export)).hasSize(3);

        // ── a lecturer reads none of it; the Bursar issues nothing ──
        assertThat(it.get(it.officer("lecturer", "department", d1), R + q).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(it.officer("bursar", "institution", "University"), HttpMethod.POST, A + "/sheets", Map.of("offerings", List.of(og.toString()), "manualLines", 5))
                .getStatusCode().value()).isEqualTo(403);
    }
}
