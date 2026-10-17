package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
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
 * V421 — a missing result is not a zero, and never probation, through the API. A student whose registration came over
 * without results (on a sheet the old portal's results published for another) reads no CGPA, a standing that cannot be
 * told and "your result has not yet been uploaded or published" — never "you are on probation, CGPA 0.00"; the other
 * student, with complete published results under the threshold, is on probation with the University's threshold; the
 * offices count both by result status in scope; the threshold is the Academic Office's to set, never a lecturer's. The
 * office side: the Senate broadsheet shows the missing results as NR — not counted, not owed, nothing pronounced — and the
 * pipeline's "Results not yet in" names them, course by course and student by student, within the office's bound. Runs
 * again on the same database. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class AcademicStandingIT {

    static final String SESSION = "2087/2088";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String lecturer = ItSupport.token("lecturer");
    final String records = ItSupport.token("records");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2087);
    }

    private static Map<String, Object> ok(ResponseEntity<Map> r) {
        assertThat(r.getStatusCode().is2xxSuccessful()).as(String.valueOf(r.getBody())).isTrue();
        return r.getBody();
    }

    /** two students of one class: one whose registration came over without results, one with complete published results (E and F) */
    private record Seeded(UUID missing, UUID low, String missingMatric, String lowMatric) {
    }

    private Seeded seed() {
        int n = it.freeDraw(1000, 9000, k -> List.of("MOAUM/STD/87/" + k, "MOAUM/STD/87/" + (k + 1), "MOAUM/ADM/87/10" + k, "MOAUM/ADM/87/20" + k, "ITSTANDNONE" + k, "ITSTANDLOW" + k));
        String missingMatric = "MOAUM/STD/87/" + n;
        String lowMatric = "MOAUM/STD/87/" + (n + 1);
        UUID missing = it.student("ITSTANDNONE" + n, "C00061", "MOAUM/ADM/87/10" + n, missingMatric, 100);
        UUID low = it.student("ITSTANDLOW" + n, "C00061", "MOAUM/ADM/87/20" + n, lowMatric, 100);

        it.db(() -> {
            String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    VALUES ('STD 101', 'Standing Course One', 3, 2, 100, :d, 'Core', 'LIVE'), ('STD 102', 'Standing Course Two', 3, 2, 100, :d, 'Core', 'LIVE')
                    ON CONFLICT DO NOTHING
                    """).param("d", dept).update();
            // the old portal's results, as they came: the low student's two courses (E and F); none for the other
            jdbc.sql("SELECT * FROM assessment.import_legacy_semester(:s, 2, :rows::jsonb, true)").param("s", SESSION)
                    .param("rows", "[{\"matric\":\"" + lowMatric + "\",\"course\":\"STD 101\",\"total\":\"42\",\"level\":\"100\"},"
                            + "{\"matric\":\"" + lowMatric + "\",\"course\":\"STD 102\",\"total\":\"30\",\"level\":\"100\"}]")
                    .query().listOfRows();
            // the other student's registration came over without results: on the same, published, sheets
            UUID reg = UUID.randomUUID();
            jdbc.sql("INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), :st, :s, 100) ON CONFLICT (student_id, session) DO NOTHING")
                    .param("st", missing).param("s", SESSION).update();
            jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                    VALUES (:r, :st, :s, 2, 100, 'APPROVED', now(), now())
                    """).param("r", reg).param("st", missing).param("s", SESSION).update();
            jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                    SELECT :r, o.id, 3, 'CURRENT', 'APPROVED' FROM catalogue.offering o
                     WHERE o.session = :s AND o.semester = 2 AND o.stream = 'REGULAR' AND o.course_code IN ('STD 101', 'STD 102')
                    """).param("r", reg).param("s", SESSION).update();
            return null;
        });
        return new Seeded(missing, low, missingMatric, lowMatric);
    }

    @Test
    void aStudentWhoseResultsAreMissingIsNeverOnProbationAndOneWithLowPublishedResultsIs() {
        Seeded s = seed();

        // the student with no result: no CGPA, no probation, told the result is not available
        Map<String, Object> none = ok(it.call(TestTokens.token(s.missing(), List.of("student")), HttpMethod.GET, "/api/v1/me", null));
        Map<String, Object> st = (Map<String, Object>) none.get("probation");
        assertThat(none.get("cgpa")).isNull();
        assertThat(st.get("standing")).isEqualTo("NOT_AVAILABLE");
        assertThat(st.get("result_status")).isEqualTo("NOT_AVAILABLE");
        assertThat(String.valueOf(st.get("result_message"))).isEqualTo("Your result for the " + SESSION + " second semester has not yet been uploaded or published.");
        assertThat((List) none.get("carryovers")).isEmpty();

        // the student with complete published results under the threshold: on probation, the threshold the University's
        Map<String, Object> lowView = ok(it.call(TestTokens.token(s.low(), List.of("student")), HttpMethod.GET, "/api/v1/me", null));
        Map<String, Object> lowSt = (Map<String, Object>) lowView.get("probation");
        assertThat(lowSt.get("standing")).isEqualTo("PROBATION");
        assertThat(new java.math.BigDecimal(String.valueOf(lowSt.get("cgpa")))).isEqualByComparingTo("0.50");
        assertThat(new java.math.BigDecimal(String.valueOf(lowSt.get("threshold")))).isEqualByComparingTo("1.00");
        assertThat(lowSt.get("pronounced_session")).isEqualTo(SESSION);

        // the offices: students in scope by result status — the missing result counted as not available, not as probation
        Map<String, Object> counts = (Map<String, Object>) ok(it.call(records, HttpMethod.GET, "/api/v1/results/student-status?session=" + SESSION + "&sem=2", null)).get("counts");
        assertThat(((Number) counts.get("NOT_AVAILABLE")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) counts.get("PROBATION")).intValue()).isGreaterThanOrEqualTo(1);

        // the threshold is the Academic Office's to set, never a lecturer's
        assertThat(it.call(lecturer, HttpMethod.PUT, "/api/v1/cohorts/settings/probation", Map.of("probationBelowCgpa", 2.0)).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/cohorts/settings/probation", Map.of("probationBelowCgpa", 0)).getStatusCode().value()).isEqualTo(400);
        Map<String, Object> lowAfter;
        try {
            ok(it.call(academic, HttpMethod.PUT, "/api/v1/cohorts/settings/probation", Map.of("probationBelowCgpa", 0.4)));
            lowAfter = (Map<String, Object>) ok(it.call(TestTokens.token(s.low(), List.of("student")), HttpMethod.GET, "/api/v1/me", null)).get("probation");
        } finally {
            ok(it.call(academic, HttpMethod.PUT, "/api/v1/cohorts/settings/probation", Map.of("probationBelowCgpa", 1.0)));
        }
        assertThat(lowAfter.get("standing")).isEqualTo("GOOD");
    }

    @Test
    void theBroadsheetAndThePipelineNameAMissingResultAndNeverCountIt() {
        Seeded s = seed();

        // the Senate broadsheet: NR for each course, not counted, not owed, nothing pronounced; the other student as before
        Map<String, Object> bs = ok(it.call(records, HttpMethod.GET,
                "/api/v1/results/broadsheet?prog=C00061&level=100&session=" + SESSION + "&sem=2", null));
        List<Map<String, Object>> rows = (List<Map<String, Object>>) bs.get("rows");
        Map<String, Object> none = rows.stream().filter(r -> s.missingMatric().equals(r.get("number"))).findFirst().orElseThrow();
        assertThat(String.valueOf(none.get("remarks"))).contains("NR: STD 101, STD 102").doesNotContain("CO:").doesNotContain("PROBATION");
        assertThat(none.get("standing")).isEqualTo("Incomplete");
        assertThat(none.get("gpa")).isNull();
        assertThat(((Number) none.get("units")).intValue()).isZero();
        assertThat((List<Map<String, Object>>) none.get("marks")).filteredOn(m -> "STD 101".equals(m.get("courseCode"))).singleElement()
                .satisfies(m -> {
                    assertThat(m.get("outcome")).isEqualTo("NO_RESULT");
                    assertThat(m.get("grade")).isNull();
                    assertThat(m.get("counted")).isEqualTo(false);
                });
        Map<String, Object> low = rows.stream().filter(r -> s.lowMatric().equals(r.get("number"))).findFirst().orElseThrow();
        assertThat(String.valueOf(low.get("remarks"))).contains("CO: STD 102").contains("TO GO ON PROBATION").doesNotContain("NR:");

        // the pipeline: the published sets name the candidates without a result, from the old portal's upload
        Map<String, Object> pipe = ok(it.call(records, HttpMethod.GET, "/api/v1/results/pipeline?session=" + SESSION + "&sem=2", null));
        assertThat((List<Map<String, Object>>) pipe.get("missing")).filteredOn(m -> "STD 101".equals(m.get("courseCode"))).singleElement()
                .satisfies(m -> {
                    assertThat(m.get("why")).isEqualTo("NOT_IN_UPLOAD");
                    assertThat(((Number) m.get("missing")).intValue()).isGreaterThanOrEqualTo(1);
                });
        assertThat((List<Map<String, Object>>) pipe.get("alerts")).anySatisfy(a -> {
            assertThat(a.get("courseCode")).isEqualTo("STD 101");
            assertThat(a.get("kind")).isEqualTo("NOT_ON_SHEET");
        });

        // student by student: both courses for the one, nothing for the other
        List<Map<String, Object>> students = (List<Map<String, Object>>) ok(it.call(records, HttpMethod.GET,
                "/api/v1/results/pipeline/missing-students?session=" + SESSION + "&sem=2", null)).get("rows");
        assertThat(students).filteredOn(m -> s.missingMatric().equals(m.get("number")))
                .extracting(m -> m.get("courseCode") + "/" + m.get("why")).containsExactlyInAnyOrder("STD 101/NOT_IN_UPLOAD", "STD 102/NOT_IN_UPLOAD");
        assertThat(students).noneMatch(m -> s.lowMatric().equals(m.get("number")));

        // within the office's bound: a lecturer sees only their own courses, and these are not theirs
        List<Map<String, Object>> mine = (List<Map<String, Object>>) ok(it.call(lecturer, HttpMethod.GET,
                "/api/v1/results/pipeline/missing-students?session=" + SESSION + "&sem=2", null)).get("rows");
        assertThat(mine).noneMatch(m -> s.missingMatric().equals(m.get("number")));
    }

    /**
     * V422: the student not on the published sheet gets a late result — raised by the course's lecturer, approved by each desk
     * in turn, applied by the Registrar on the minute as the first mark; a student not on the roll is refused. A result held
     * for the Senate (withheld) is never counted or owed: the broadsheet names it HELD and pronounces nothing, the student
     * reads it as held.
     */
    @Test
    void aLateResultReachesTheStudentThroughTheChainAndAHeldResultPronouncesNothing() {
        Seeded s = seed();
        String dept = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = 'C00061'").query(String.class).single();
        String faculty = jdbc.sql("SELECT faculty_code FROM ref.department WHERE code = :d").param("d", dept).query(String.class).single();
        UUID teacher = it.person("ZZ-LECTURER-STD101", "ZZLECTURERSTD101");
        UUID sheet = it.db(() -> {
            jdbc.sql("UPDATE catalogue.offering SET lecturer_id = :l WHERE course_code = 'STD 101' AND session = :s AND semester = 2 AND stream = 'REGULAR'")
                    .param("l", teacher).param("s", SESSION).update();
            return jdbc.sql("""
                    SELECT sh.id FROM assessment.score_sheet sh JOIN catalogue.offering o ON o.id = sh.offering_id
                     WHERE o.course_code = 'STD 101' AND o.session = :s AND o.semester = 2 AND o.stream = 'REGULAR'
                    """).param("s", SESSION).query(UUID.class).single();
        });
        String lect = TestTokens.token(teacher, List.of("lecturer"));

        // the candidates on the roll with no mark: the student whose result never came is one
        List<Map<String, Object>> late = (List<Map<String, Object>>) (List<?>) it.getList(lect, "/api/v1/results/sheets/" + sheet + "/late-candidates").getBody();
        assertThat(late).anySatisfy(c -> assertThat(c.get("number")).isEqualTo(s.missingMatric()));

        // a student nowhere on the sheet is refused; the one on its roll gets a late result
        String amend = "/api/v1/results/sheets/" + sheet + "/amendments";
        ResponseEntity<Map> stranger = it.call(lect, HttpMethod.POST, amend,
                Map.of("studentId", UUID.randomUUID().toString(), "ca", 20, "exam", 40, "reason", "a student who is not on this sheet"));
        assertThat(stranger.getStatusCode().value()).isEqualTo(422);
        assertThat(stranger.getBody().get("code")).isEqualTo("RES_AMEND_NO_MARK");
        ResponseEntity<List> raised = it.callList(lect, HttpMethod.POST, amend,
                Map.of("studentId", s.missing().toString(), "ca", 20, "exam", 40, "reason", "Registered on the old portal; the marked script was found"));
        assertThat(raised.getStatusCode().value()).as(String.valueOf(raised.getBody())).isEqualTo(200);
        Map<String, Object> am = ((List<Map<String, Object>>) raised.getBody()).stream()
                .filter(a -> s.missing().toString().equals(String.valueOf(a.get("student_id")))).findFirst().orElseThrow();
        assertThat(am.get("kind")).isEqualTo("LATE");
        assertThat(am.get("was_outcome")).isNull();
        String amId = String.valueOf(am.get("id"));

        Map<String, String> desks = Map.of("exams", it.officer("exams", "programme", "C00061"), "hod", it.officer("hod", "department", dept),
                "facultyexams", it.officer("facultyexams", "faculty", faculty), "facultyofficer", it.officer("facultyofficer", "faculty", faculty),
                "dean", it.officer("dean", "faculty", faculty), "records", records);
        for (String desk : List.of("exams", "hod", "facultyexams", "facultyofficer", "dean", "records")) {
            ResponseEntity<List> r = it.callList(desks.get(desk), HttpMethod.POST, "/api/v1/results/amendments/" + amId + "/advance", Map.of("comment", "seen"));
            assertThat(r.getStatusCode().value()).as(desk + ": " + r.getBody()).isEqualTo(200);
        }
        ResponseEntity<List> applied = it.callList(ItSupport.token("registrar"), HttpMethod.POST, "/api/v1/results/amendments/" + amId + "/advance",
                Map.of("minute", "SEN/2088/42"));
        assertThat(applied.getStatusCode().value()).as(String.valueOf(applied.getBody())).isEqualTo(200);

        // the student now has STD 101 published (60, a C); STD 102 is still no result, so the semester is incomplete
        Map<String, Object> results = ok(it.call(TestTokens.token(s.missing(), List.of("student")), HttpMethod.GET, "/api/v1/me/results", null));
        assertThat((List<Map<String, Object>>) results.get("rows")).filteredOn(r -> "STD 101".equals(r.get("course_code"))).singleElement()
                .satisfies(r -> assertThat(r.get("published")).isEqualTo(true));
        Map<String, Object> st = (Map<String, Object>) ok(it.call(TestTokens.token(s.missing(), List.of("student")), HttpMethod.GET, "/api/v1/me", null)).get("probation");
        assertThat(st.get("result_status")).isEqualTo("INCOMPLETE");
        assertThat(st.get("standing")).isEqualTo("NOT_AVAILABLE");

        // a result withheld: held for the Senate — not counted, not owed, nothing pronounced, the student told it is held
        int n = it.freeDraw(1000, 9000, k -> List.of("MOAUM/STD/87/3" + k, "MOAUM/ADM/87/30" + k, "ITSTANDHELD" + k));
        String heldMatric = "MOAUM/STD/87/3" + n;   // five digits: never one of seed()'s four
        UUID held = it.student("ITSTANDHELD" + n, "C00061", "MOAUM/ADM/87/30" + n, heldMatric, 100);
        it.db(() -> jdbc.sql("SELECT * FROM assessment.import_legacy_semester(:s, 2, :rows::jsonb, true)").param("s", SESSION)
                .param("rows", "[{\"matric\":\"" + heldMatric + "\",\"course\":\"STD 101\",\"outcome\":\"WITHHELD\",\"level\":\"100\"},"
                        + "{\"matric\":\"" + heldMatric + "\",\"course\":\"STD 102\",\"total\":\"30\",\"level\":\"100\"}]")
                .query().listOfRows());
        Map<String, Object> bs = ok(it.call(records, HttpMethod.GET, "/api/v1/results/broadsheet?prog=C00061&level=100&session=" + SESSION + "&sem=2", null));
        Map<String, Object> row = ((List<Map<String, Object>>) bs.get("rows")).stream().filter(r -> heldMatric.equals(r.get("number"))).findFirst().orElseThrow();
        assertThat(String.valueOf(row.get("remarks"))).contains("HELD: STD 101").contains("CO: STD 102").doesNotContain("PROBATION");
        Map<String, Object> heldSt = (Map<String, Object>) ok(it.call(TestTokens.token(held, List.of("student")), HttpMethod.GET, "/api/v1/me", null)).get("probation");
        assertThat(heldSt.get("result_status")).isEqualTo("HELD");
        assertThat(heldSt.get("standing")).isEqualTo("NOT_AVAILABLE");
        assertThat((List<Map<String, Object>>) ok(it.call(TestTokens.token(held, List.of("student")), HttpMethod.GET, "/api/v1/me", null)).get("carryovers"))
                .extracting(c -> c.get("course_code")).containsExactly("STD 102");
    }

    /**
     * V424: the results held for the Senate are listed for the Registry (never for a lecturer), with the days after which the
     * Registry is reminded — days only the Academic Office or the Registry sets, 7 to 365 or 0; the students owing a course only
     * because of a recorded absence are named for the Registry, and the Bursary reads who owes a GST/EPS course again.
     */
    @Test
    void heldResultsAreListedAndWhoTheAbsentRuleTouchesIsNamed() {
        seed();
        int n = it.freeDraw(1000, 9000, k -> List.of("MOAUM/STD/87/4" + k, "MOAUM/STD/87/5" + k, "MOAUM/ADM/87/40" + k, "MOAUM/ADM/87/50" + k, "ITSTANDHOLD" + k, "ITSTANDABS" + k));
        String heldMatric = "MOAUM/STD/87/4" + n;
        String absentMatric = "MOAUM/STD/87/5" + n;
        it.student("ITSTANDHOLD" + n, "C00061", "MOAUM/ADM/87/40" + n, heldMatric, 100);
        it.student("ITSTANDABS" + n, "C00061", "MOAUM/ADM/87/50" + n, absentMatric, 100);
        it.db(() -> jdbc.sql("SELECT * FROM assessment.import_legacy_semester(:s, 2, :rows::jsonb, true)").param("s", SESSION)
                .param("rows", "[{\"matric\":\"" + heldMatric + "\",\"course\":\"STD 101\",\"outcome\":\"MALPRACTICE\",\"level\":\"100\"},"
                        + "{\"matric\":\"" + absentMatric + "\",\"course\":\"STD 102\",\"outcome\":\"ABSENT\",\"level\":\"100\"}]")
                .query().listOfRows());

        // the held results: for the Registry, with the reminder days; never for a lecturer
        Map<String, Object> held = ok(it.call(records, HttpMethod.GET, "/api/v1/results/held?session=" + SESSION, null));
        assertThat(((Number) held.get("remindDays")).intValue()).isEqualTo(30);
        assertThat((List<Map<String, Object>>) held.get("rows")).anySatisfy(r -> {
            assertThat(r.get("number")).isEqualTo(heldMatric);
            assertThat(r.get("outcome")).isEqualTo("MALPRACTICE");
            assertThat(r.get("course_code")).isEqualTo("STD 101");
        });
        assertThat(it.call(lecturer, HttpMethod.GET, "/api/v1/results/held", null).getStatusCode().value()).isEqualTo(403);

        // the reminder days: the Registry's to set, 7 to 365 or 0
        assertThat(it.call(lecturer, HttpMethod.PUT, "/api/v1/cohorts/settings/held-reminder", Map.of("days", 14)).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> tooSoon = it.call(academic, HttpMethod.PUT, "/api/v1/cohorts/settings/held-reminder", Map.of("days", 3));
        assertThat(tooSoon.getStatusCode().value()).isEqualTo(422);
        assertThat(tooSoon.getBody().get("code")).isEqualTo("STANDING_SETTING_HELD_DAYS");
        try {
            ok(it.call(academic, HttpMethod.PUT, "/api/v1/cohorts/settings/held-reminder", Map.of("days", 14)));
            assertThat(((Number) ok(it.call(records, HttpMethod.GET, "/api/v1/results/held?session=" + SESSION, null)).get("remindDays")).intValue()).isEqualTo(14);
        } finally {
            ok(it.call(academic, HttpMethod.PUT, "/api/v1/cohorts/settings/held-reminder", Map.of("days", 30)));
        }

        // who the absent rule touches: the absence is owed; the Bursary reads the GST/EPS side
        List<Map<String, Object>> owed = (List<Map<String, Object>>) (List<?>) it.getList(records, "/api/v1/results/absence-carryovers?prog=C00061").getBody();
        assertThat(owed).anySatisfy(r -> {
            assertThat(r.get("number")).isEqualTo(absentMatric);
            assertThat(r.get("course_code")).isEqualTo("STD 102");
            assertThat(r.get("absent_in")).isEqualTo(SESSION + " semester 2");
        });
        assertThat(owed).noneMatch(r -> heldMatric.equals(r.get("number")));
        assertThat(ok(it.call(ItSupport.token("bursar"), HttpMethod.GET, "/api/v1/gst/fee/absences?session=" + SESSION, null))).containsKey("rows");
        assertThat(it.call(lecturer, HttpMethod.GET, "/api/v1/gst/fee/absences", null).getStatusCode().value()).isEqualTo(403);
    }
}
