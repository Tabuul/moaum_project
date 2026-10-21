package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * The course registration history upload (V472): the file is checked against the record first and the check writes nothing;
 * the upload adds only what is missing, at the programme's units; a re-upload never rewrites a course on record — its units
 * and a dropped status stay — and every row not loaded or left as it was comes back with its reason. A past result for a
 * dropped course approves it, as before; past results are the Directorate of ICT's alone to upload (21 Oct 2026). Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class RegistrationHistoryUploadIT {

    /** the run's own session, never another test's fixed one: the upload enrols its student in the session it records, so a fixed
     *  session (2097/2098, CalendarIT's own) carried a student into the next run, where CalendarIT expects its session empty */
    int year;
    String session;

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String records = ItSupport.token("records");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        // and one no other test has opened either (ItSupport.freeYear)
        year = it.freeYear(2300, 2900);
        session = year + "/" + (year + 1);
        it.session(session, year);
    }

    private Map<String, Object> post(String path, List<Map<String, String>> rows) {
        return post(records, path, rows);
    }

    private Map<String, Object> post(String token, String path, List<Map<String, String>> rows) {
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, path, Map.of("session", session, "semester", 1, "rows", rows));
        assertThat(r.getStatusCode().value()).as(path + " → " + r.getBody()).isEqualTo(200);
        return r.getBody();
    }

    private static Map<String, String> statusByLine(Map<String, Object> body) {
        return ((List<Map<String, Object>>) body.get("lines")).stream()
                .collect(Collectors.toMap(l -> String.valueOf(l.get("line")), l -> String.valueOf(l.get("status")), (a, b) -> a));
    }

    private List<Map<String, Object>> entries(UUID student) {
        return jdbc.sql("""
                SELECT o.course_code, e.units, e.status FROM registration.entry e
                  JOIN registration.course_registration r ON r.id = e.registration_id JOIN catalogue.offering o ON o.id = e.offering_id
                 WHERE r.student_id = :s AND r.session = :ses AND r.semester = 1 ORDER BY o.course_code
                """).param("s", student).param("ses", session).query().listOfRows();
    }

    @Test
    void theFileIsCheckedFirstAndWhatIsOnRecordIsNeverRewritten() {
        int n = it.freeDraw(1000, 9000, k -> List.of("MOAUM/MTC/97/" + (30000 + k), "MOAUM/ADM/97/" + (300000 + k), "ZZRH" + k));
        String matric = "MOAUM/MTC/97/" + (30000 + n);
        UUID student = it.student("ZZRH" + n, "C00023", "MOAUM/ADM/97/" + (300000 + n), matric, 100);
        List<Map<String, Object>> courses = jdbc.sql("""
                SELECT code, units FROM catalogue.course WHERE state = 'LIVE' AND NOT both_semesters AND code ~ '^[A-Z]{3} [0-9]{3}$'
                 ORDER BY code LIMIT 2
                """).query().listOfRows();
        String c1 = (String) courses.get(0).get("code"), c2 = (String) courses.get(1).get("code");
        int units2 = ((Number) jdbc.sql("SELECT catalogue.units_for(:c, 'C00023', 100)").param("c", c2).query(Integer.class).single()).intValue();
        List<Map<String, String>> rows = List.of(
                Map.of("line", "2", "matric", matric, "course", c1, "level", "100"),
                Map.of("line", "3", "matric", matric, "course", c1.toLowerCase()),
                Map.of("line", "4", "matric", matric, "course", c2.replace(" ", "")),
                Map.of("line", "5", "matric", "MOAUM/NOPE/97/" + n, "course", c1));

        // the check: each row's status, and nothing written
        Map<String, Object> check = post("/api/v1/results/legacy/registration/preview", rows);
        assertThat(statusByLine(check)).containsEntry("2", "ADDED").containsEntry("3", "DUPLICATE_IN_FILE").containsEntry("4", "ADDED").containsEntry("5", "NO_STUDENT");
        assertThat(((Number) check.get("entries")).intValue()).isEqualTo(2);
        assertThat(entries(student)).isEmpty();
        assertThat(it.call(ItSupport.token("lecturer"), HttpMethod.POST, "/api/v1/results/legacy/registration/preview",
                Map.of("session", session, "semester", 1, "rows", rows)).getStatusCode().value()).isEqualTo(403);

        // the upload: what is missing is added, at the programme's units; the rows not loaded come back with their reason
        Map<String, Object> up = post("/api/v1/results/legacy/registration", rows);
        assertThat(((Number) up.get("entries")).intValue()).isEqualTo(2);
        assertThat(statusByLine(up)).containsOnlyKeys("3", "5");
        assertThat(entries(student)).extracting(e -> e.get("course_code")).containsExactly(c1, c2);
        assertThat(entries(student).get(1).get("units")).isEqualTo(units2);

        // the office's own changes on record: c1 dropped, c2 at other units — a re-upload leaves both as they are
        it.db(() -> jdbc.sql("""
                UPDATE registration.entry e SET status = CASE o.course_code WHEN :c1 THEN 'DROPPED' ELSE e.status END,
                       units = CASE o.course_code WHEN :c2 THEN e.units + 1 ELSE e.units END
                  FROM registration.course_registration r, catalogue.offering o
                 WHERE r.id = e.registration_id AND o.id = e.offering_id AND r.student_id = :s AND r.session = :ses
                """).param("c1", c1).param("c2", c2).param("s", student).param("ses", session).update());
        Map<String, Object> again = post("/api/v1/results/legacy/registration", rows);
        assertThat(statusByLine(again)).containsEntry("2", "DROPPED_ON_RECORD").containsEntry("4", "UNITS_DIFFER");
        assertThat(((Number) again.get("entries")).intValue()).isZero();
        assertThat(entries(student).get(0).get("status")).isEqualTo("DROPPED");
        assertThat(entries(student).get(1).get("units")).isEqualTo(units2 + 1);

        // a past result for the dropped course: the Directorate of ICT's alone to upload (21 Oct 2026) — Records is refused the check,
        // the upload and the postgraduate upload; ICT checks it first (nothing changes), then posts it, which approves it
        List<Map<String, String>> result = List.of(Map.of("line", "2", "matric", matric, "course", c1, "total", "70"));
        for (String path : List.of("/api/v1/results/legacy/results/preview", "/api/v1/results/legacy/results", "/api/v1/results/legacy/pg-results")) {
            assertThat(it.call(records, HttpMethod.POST, path, Map.of("session", session, "semester", 1, "rows", result)).getStatusCode().value())
                    .as(path).isEqualTo(403);
        }
        String ict = ItSupport.token("ict");
        Map<String, Object> rcheck = post(ict, "/api/v1/results/legacy/results/preview", result);
        assertThat(statusByLine(rcheck)).containsEntry("2", "RESULT_POSTED");
        assertThat(entries(student).get(0).get("status")).isEqualTo("DROPPED");
        Map<String, Object> posted = post(ict, "/api/v1/results/legacy/results", result);
        assertThat(((Number) posted.get("results")).intValue()).isEqualTo(1);
        assertThat(entries(student).get(0).get("status")).isEqualTo("APPROVED");
        assertThat(entries(student).get(1).get("units")).isEqualTo(units2 + 1);
    }
}
