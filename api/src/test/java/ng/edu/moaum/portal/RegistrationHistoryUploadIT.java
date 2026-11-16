package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashMap;
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
 * the upload adds only what is missing, at the units the file states for each course as taken (15 Nov 2026: Course Title, Credit
 * Units and Category on every row, never today's catalogue); a re-upload by an office outside the Directorate of ICT never rewrites
 * a course on record — its units and a dropped status stay — and every row not loaded or left as it was comes back with its reason.
 * Each import loads under its confirmed upload, named on the call. A past result for a dropped course approves it, as before; past
 * results are the Directorate of ICT's alone to upload (21 Oct 2026). Needs DATABASE_URL.
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

    private Map<String, Object> post(String path, List<Map<String, String>> rows, UUID upload) {
        return post(records, path, rows, upload);
    }

    private Map<String, Object> post(String token, String path, List<Map<String, String>> rows, UUID upload) {
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, path, body(rows, upload));
        assertThat(r.getStatusCode().value()).as(path + " → " + r.getBody()).isEqualTo(200);
        return r.getBody();
    }

    private Map<String, Object> body(List<Map<String, String>> rows, UUID upload) {
        Map<String, Object> body = new HashMap<>();
        body.put("session", session);
        body.put("semester", 1);
        body.put("rows", rows);
        if (upload != null) body.put("uploadId", upload.toString());
        return body;
    }

    /** an upload confirmed with its reason, as the office that loads it */
    private UUID begin(String token, String kind, int rows) {
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, "/api/v1/results/legacy/uploads", Map.of("kind", kind, "fileName", "history.xlsx",
                "rows", rows, "reason", "Integration test: the old portal's records of the semester"));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        assertThat(r.getBody()).containsEntry("state", "RUNNING").containsEntry("kind", kind);
        assertThat(String.valueOf(r.getBody().get("ref"))).matches("PRU-[0-9]{4}-[0-9]{5,}");
        return UUID.fromString(String.valueOf(r.getBody().get("id")));
    }

    private Map<String, Object> finish(String token, UUID upload) {
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, "/api/v1/results/legacy/uploads/" + upload + "/finish", Map.of("complete", true));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        assertThat(r.getBody()).containsEntry("state", "COMPLETE");
        return r.getBody();
    }

    /** a row of the template: the course as taken — its title, credit units and category — on every row */
    private static Map<String, String> row(String line, String matric, String course, String title, int units, String... more) {
        Map<String, String> r = new HashMap<>(Map.of("line", line, "matric", matric, "course", course, "title", title,
                "creditUnits", String.valueOf(units), "category", "Core"));
        for (int i = 0; i + 1 < more.length; i += 2) r.put(more[i], more[i + 1]);
        return r;
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
        // two courses of the run's own, one code each, so a row's code and title name one course; the catalogue at 4 units, the file at 2
        String px = it.freeCoursePrefix("Z");
        String c1 = px + " 101", c2 = px + " 102";
        String t1 = "Registration History One", t2 = "Registration History Two";
        it.db(() -> jdbc.sql("""
                INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, ca_max)
                SELECT x.code, x.title, 4, 1, 100, p.dept_code, 'Core', 'LIVE', 40
                  FROM ref.programme p, (VALUES (:c1, :t1), (:c2, :t2)) x(code, title) WHERE p.code = 'C00023'
                """).param("c1", c1).param("t1", t1).param("c2", c2).param("t2", t2).update());
        int units2 = 2;
        List<Map<String, String>> rows = List.of(
                row("2", matric, c1, t1, 2, "level", "100"),
                row("3", matric, c1.toLowerCase(), t1, 2),
                row("4", matric, c2.replace(" ", ""), t2, units2),
                row("5", "MOAUM/NOPE/97/" + n, c1, t1, 2));

        // the check: each row's status, and nothing written
        Map<String, Object> check = post("/api/v1/results/legacy/registration/preview", rows, null);
        assertThat(statusByLine(check)).containsEntry("2", "ADDED").containsEntry("3", "DUPLICATE_IN_FILE").containsEntry("4", "ADDED").containsEntry("5", "NO_STUDENT");
        assertThat(((Number) check.get("entries")).intValue()).isEqualTo(2);
        assertThat(entries(student)).isEmpty();
        assertThat(it.call(ItSupport.token("lecturer"), HttpMethod.POST, "/api/v1/results/legacy/registration/preview", body(rows, null)).getStatusCode().value())
                .isEqualTo(403);

        // an import names its confirmed upload: without one it is refused before anything is read
        ResponseEntity<Map> unnamed = it.call(records, HttpMethod.POST, "/api/v1/results/legacy/registration", body(rows, null));
        assertThat(unnamed.getStatusCode().value()).as(String.valueOf(unnamed.getBody())).isEqualTo(400);
        assertThat(unnamed.getBody()).containsEntry("code", "LEGACY_UPLOAD_REQUIRED");
        assertThat(entries(student)).isEmpty();

        // the upload: what is missing is added, at the file's units (the catalogue's 4 untouched); the rows not loaded come back with
        // their reason
        UUID first = begin(records, "REGISTRATION", rows.size());
        Map<String, Object> up = post("/api/v1/results/legacy/registration", rows, first);
        assertThat(((Number) up.get("entries")).intValue()).isEqualTo(2);
        assertThat(statusByLine(up)).containsOnlyKeys("3", "5");
        assertThat(entries(student)).extracting(e -> e.get("course_code")).containsExactly(c1, c2);
        assertThat(entries(student).get(1).get("units")).isEqualTo(units2);
        assertThat(jdbc.sql("SELECT units FROM catalogue.course WHERE code = :c").param("c", c2).query(Integer.class).single()).isEqualTo(4);
        // the ledger holds the two entries and the registration and enrolment they were added under, so a rollback can take all four back
        assertThat((Map<String, Object>) finish(records, first).get("counts")).containsEntry("changes", 4)
                .containsEntry("byKind", Map.of("ENTRY_ADDED", 2, "REGISTRATION_ADDED", 1, "ENROLMENT_ADDED", 1));

        // the office's own changes on record: c1 dropped, c2 at other units — a re-upload by Records leaves both as they are
        it.db(() -> jdbc.sql("""
                UPDATE registration.entry e SET status = CASE o.course_code WHEN :c1 THEN 'DROPPED' ELSE e.status END,
                       units = CASE o.course_code WHEN :c2 THEN e.units + 1 ELSE e.units END
                  FROM registration.course_registration r, catalogue.offering o
                 WHERE r.id = e.registration_id AND o.id = e.offering_id AND r.student_id = :s AND r.session = :ses
                """).param("c1", c1).param("c2", c2).param("s", student).param("ses", session).update());
        UUID second = begin(records, "REGISTRATION", rows.size());
        Map<String, Object> again = post("/api/v1/results/legacy/registration", rows, second);
        assertThat(statusByLine(again)).containsEntry("2", "DROPPED_ON_RECORD").containsEntry("4", "AS_TAKEN_DIFFERS");
        assertThat(((Number) again.get("entries")).intValue()).isZero();
        assertThat(entries(student).get(0).get("status")).isEqualTo("DROPPED");
        assertThat(entries(student).get(1).get("units")).isEqualTo(units2 + 1);
        finish(records, second);

        // a past result for the dropped course: the Directorate of ICT's alone to upload (21 Oct 2026) — Records is refused the upload's
        // confirmation, the check, the upload and the postgraduate upload; ICT checks it first (nothing changes), then posts it under its
        // own upload, which approves it
        List<Map<String, String>> result = List.of(row("2", matric, c1, t1, 2, "total", "70"));
        ResponseEntity<Map> notRecords = it.call(records, HttpMethod.POST, "/api/v1/results/legacy/uploads", Map.of("kind", "RESULTS", "rows", 1,
                "reason", "Integration test: the old portal's past results"));
        assertThat(notRecords.getStatusCode().value()).as(String.valueOf(notRecords.getBody())).isEqualTo(403);
        for (String path : List.of("/api/v1/results/legacy/results/preview", "/api/v1/results/legacy/results", "/api/v1/results/legacy/pg-results")) {
            assertThat(it.call(records, HttpMethod.POST, path, body(result, second)).getStatusCode().value()).as(path).isEqualTo(403);
        }
        String ict = ItSupport.token("ict");
        Map<String, Object> rcheck = post(ict, "/api/v1/results/legacy/results/preview", result, null);
        assertThat(statusByLine(rcheck)).containsEntry("2", "RESULT_POSTED");
        assertThat(entries(student).get(0).get("status")).isEqualTo("DROPPED");
        UUID results = begin(ict, "RESULTS", result.size());
        Map<String, Object> posted = post(ict, "/api/v1/results/legacy/results", result, results);
        assertThat(((Number) posted.get("results")).intValue()).isEqualTo(1);
        assertThat(entries(student).get(0).get("status")).isEqualTo("APPROVED");
        assertThat(entries(student).get(1).get("units")).isEqualTo(units2 + 1);
        finish(ict, results);
    }
}
