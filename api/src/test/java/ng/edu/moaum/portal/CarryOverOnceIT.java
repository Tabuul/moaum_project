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
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.web.client.RestClient;

/**
 * V666: a carry-over once per course, its attempts kept, through the API. A programme of the test's own; a student who failed one
 * course in two sessions, failed another and passed it the session after, missed a third (a recorded absence, an F since V422) and
 * failed an elective of the programme. The dashboard, the results page and the carry-over history each give the twice-failed course
 * once — its last failure, two attempts, the first — and the absence; the passed one and the elective are not owed, though every
 * attempt of each stays in the history. The staff's full record reads the same. The carry-over report counts the student once for
 * the twice-failed course and once for the absence, and neither for the passed course nor the elective. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CarryOverOnceIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String registrar = ItSupport.token("registrar");
    final String academic = ItSupport.token("academic");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    private ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    private String signedIn(UUID student, String matric) {
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 6660")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 6660")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 6660", "next", "Own-Password-6660")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    private static List<String> codes(List<Map<String, Object>> rows) {
        return rows.stream().map(r -> String.valueOf(r.get("course_code"))).toList();
    }

    private static Map<String, Object> rowOf(List<Map<String, Object>> rows, String code) {
        return rows.stream().filter(x -> code.equals(x.get("course_code"))).findFirst().orElseThrow(() -> new AssertionError("no row " + code + " in " + rows));
    }

    @Test
    void aCourseFailedTwiceIsOwedOnceWithEveryAttemptKept() {
        int y = it.freeYear(5000, 5590, 1, 0);
        String first = (y - 1) + "/" + y, second = y + "/" + (y + 1);
        it.session(first, y - 1);
        it.session(second, y);
        int n = 1000 + new Random().nextInt(8999);
        String yy = String.format("%02d", y % 100);
        String hex = UUID.randomUUID().toString().replaceAll("[^a-f]", "").toUpperCase() + "ABCDEF";
        String p = "Z" + hex.substring(0, 2);   // the run's own course prefix
        String[] place = it.db(() -> {
            String[] one = jdbc.sql("""
                    SELECT p.dept_code || ',' || p.faculty_code FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND coalesce(f.college_code, '') <> 'CHS' ORDER BY p.code LIMIT 1
                    """).query(String.class).single().split(",");
            String prog = jdbc.sql("SELECT 'C' || x FROM generate_series(96500, 96999) x WHERE NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = 'C' || x) ORDER BY random() LIMIT 1")
                    .query(String.class).single();
            jdbc.sql("""
                    INSERT INTO ref.programme (code, name, dept_code, faculty_code, category, min_score, final_level, duration_years)
                    VALUES (:c, 'B.Sc. Carry-Over Once Test ' || :c, :d, :f, 'UNDER GRADUATE', 0, 400, 4)
                    """).param("c", prog).param("d", one[0]).param("f", one[1]).update();
            return new String[] {one[0], prog};
        });
        String dept = place[0], prog = place[1];
        String matric = "MOAUM/ITO/" + yy + "/" + n;
        UUID student = it.student("ZZONCE" + n, prog, "MOAUM/ADM/" + yy + "/67" + n, matric, 200);
        String token = signedIn(student, matric);

        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
                        (:p || ' 101', 'Once Failed Twice', 3, 1, 100, :d, 'Core', 'LIVE'), (:p || ' 102', 'Once Passed After', 3, 1, 100, :d, 'Core', 'LIVE'),
                        (:p || ' 104', 'Once Absent', 2, 1, 100, :d, 'Core', 'LIVE'), (:p || ' 105', 'Once Elective', 2, 1, 100, :d, 'Elective', 'LIVE')
                    ON CONFLICT (code) DO NOTHING
                    """).param("p", p).param("d", dept).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis)
                    SELECT :p || ' ' || x.n, :prog, 100, x.b FROM (VALUES ('101', 'Core'), ('102', 'Core'), ('104', 'Core'), ('105', 'Elective')) x(n, b)
                    ON CONFLICT DO NOTHING
                    """).param("p", p).param("prog", prog).update();
            jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester)
                    SELECT gen_random_uuid(), :p || ' ' || c, :a, 1 FROM unnest(ARRAY['101', '102', '104', '105']) c
                    UNION ALL SELECT gen_random_uuid(), :p || ' ' || c, :b, 1 FROM unnest(ARRAY['101', '102']) c
                    ON CONFLICT (course_code, session, semester, stream) DO NOTHING
                    """).param("p", p).param("a", first).param("b", second).update();
            for (String ses : List.of(first, second)) {
                UUID reg = UUID.randomUUID();
                jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :st, :s, 1, :l, 'APPROVED', now(), now())")
                        .param("r", reg).param("st", student).param("s", ses).param("l", ses.equals(first) ? 100 : 200).update();
                jdbc.sql("""
                        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                        SELECT :r, o.id, 3, CASE WHEN :s = :b THEN 'CARRYOVER' ELSE 'CURRENT' END, 'APPROVED'
                          FROM catalogue.offering o WHERE o.session = :s AND o.course_code LIKE :p || ' %'
                        """).param("r", reg).param("s", ses).param("b", second).param("p", p).update();
            }
            jdbc.sql("""
                    INSERT INTO assessment.score_sheet (id, offering_id) SELECT gen_random_uuid(), o.id FROM catalogue.offering o
                     WHERE o.session IN (:a, :b) AND o.course_code LIKE :p || ' %'
                    """).param("a", first).param("b", second).param("p", p).update();
            // an F everywhere, but a pass for 102 in the second session and an absence for 104
            jdbc.sql("""
                    INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome)
                    SELECT sh.id, :st,
                           CASE WHEN o.course_code LIKE '% 104' THEN NULL WHEN o.session = :b AND o.course_code LIKE '% 102' THEN 25 ELSE 10 END,
                           CASE WHEN o.course_code LIKE '% 104' THEN NULL WHEN o.session = :b AND o.course_code LIKE '% 102' THEN 40 ELSE 15 END,
                           CASE WHEN o.course_code LIKE '% 104' THEN 'ABSENT' ELSE 'GRADED' END
                      FROM assessment.score_sheet sh JOIN catalogue.offering o ON o.id = sh.offering_id WHERE o.session IN (:a, :b) AND o.course_code LIKE :p || ' %'
                    """).param("st", student).param("a", first).param("b", second).param("p", p).update();
            jdbc.sql("SELECT set_config('moaum.maintenance', 'on', true)").query().singleRow();
            return jdbc.sql("""
                    UPDATE assessment.score_sheet sh SET stage = 'PUBLISHED', published_at = now(), senate_minute = 'IT V666'
                      FROM catalogue.offering o WHERE o.id = sh.offering_id AND o.session IN (:a, :b) AND o.course_code LIKE :p || ' %'
                    """).param("a", first).param("b", second).param("p", p).update();
        });

        String twice = p + " 101", passed = p + " 102", absent = p + " 104", elective = p + " 105";

        // ── the dashboard and the results page: each course owed once ──
        ResponseEntity<Map> me = it.call(token, HttpMethod.GET, "/api/v1/me", null);
        assertThat(me.getStatusCode().value()).as(String.valueOf(me.getBody())).isEqualTo(200);
        List<Map<String, Object>> owed = (List<Map<String, Object>>) me.getBody().get("carryovers");
        assertThat(codes(owed)).containsExactly(twice, absent);
        assertThat(rowOf(owed, twice)).containsEntry("attempts", 2).containsEntry("failed_in", second + " semester 1").containsEntry("first_failed_in", first + " semester 1");
        assertThat(rowOf(owed, absent)).containsEntry("attempts", 1).containsEntry("failed_in", first + " semester 1");

        ResponseEntity<Map> results = it.call(token, HttpMethod.GET, "/api/v1/me/results", null);
        assertThat(results.getStatusCode().value()).as(String.valueOf(results.getBody())).isEqualTo(200);
        assertThat(codes((List<Map<String, Object>>) results.getBody().get("carryovers"))).containsExactly(twice, absent);

        // ── the history: every attempt kept, the passed course and the elective not owed ──
        ResponseEntity<Map> history = it.call(token, HttpMethod.GET, "/api/v1/me/carryovers/history", null);
        assertThat(history.getStatusCode().value()).as(String.valueOf(history.getBody())).isEqualTo(200);
        assertThat(codes((List<Map<String, Object>>) history.getBody().get("owed"))).containsExactly(twice, absent);
        List<Map<String, Object>> attempts = (List<Map<String, Object>>) history.getBody().get("history");
        assertThat(attempts).extracting(r -> r.get("course_code") + "@" + r.get("session") + "=" + r.get("result") + "/" + r.get("owed"))
                .containsExactly(twice + "@" + first + "=FAILED/true", twice + "@" + second + "=FAILED/true",
                        passed + "@" + first + "=FAILED/false", passed + "@" + second + "=PASSED/false",
                        absent + "@" + first + "=FAILED/true", elective + "@" + first + "=FAILED/false");

        // ── the staff's full record reads the same ──
        ResponseEntity<Map> record = it.call(academic, HttpMethod.GET, "/api/v1/student/students/" + student + "/full/results", null);
        assertThat(record.getStatusCode().value()).as(String.valueOf(record.getBody())).isEqualTo(200);
        assertThat(codes((List<Map<String, Object>>) record.getBody().get("owed"))).containsExactly(twice, absent);
        assertThat((List<Map<String, Object>>) record.getBody().get("carryHistory")).hasSize(6);

        // ── the carry-over report: the student once for each course owed, the absence counted, the passed course and the elective not ──
        ResponseEntity<Map> report = it.get(registrar, u -> u.path("/api/v1/reports/carryovers").queryParam("session", second).build());
        assertThat(report.getStatusCode().value()).as(String.valueOf(report.getBody())).isEqualTo(200);
        List<Map<String, Object>> rows = ((List<Map<String, Object>>) report.getBody().get("rows")).stream()
                .filter(r -> String.valueOf(r.get("course")).startsWith(p + " ")).toList();
        assertThat(rows).extracting(r -> r.get("course") + "=" + r.get("students")).containsExactlyInAnyOrder(twice + "=1", absent + "=1");
    }
}
