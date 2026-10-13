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
        int n = new Random().nextInt(8000) + 1000;
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
}
