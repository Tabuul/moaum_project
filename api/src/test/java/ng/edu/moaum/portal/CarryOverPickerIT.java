package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
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
 * V663: the carry-over picker through the API. A programme of the test's own; a 300 Level student who entered at 100, with a 100
 * Level course failed on a published sheet, one passed, one registered with no result here, and the programme's 200 Level courses
 * never taken here (a first-semester one and a second-semester one). The student reads every earlier course with what it is now, adds
 * three at once by course id — the failed one, the one with no result and the one with no record, all carry-overs, the two without a
 * result declared — while the passed one and a course of another student's programme are refused with their reasons; the same click
 * again adds nothing twice; the registration of carry-overs alone, below the minimum, is submitted and approved; the course
 * registration report reads it as CARRY-OVER. An officer cannot reach the student's picker. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CarryOverPickerIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    RestClient open;
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");
    final String academic = ItSupport.token("academic");
    final String instrument = "BUR/IT/CARRY663";
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        open = RestClient.builder().baseUrl("http://localhost:" + port).defaultStatusHandler(s -> true, (q, r) -> { }).build();
    }

    @AfterEach
    void clean() {
        it.db(() -> {
            if (session != null) jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update();
            jdbc.sql("DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            jdbc.sql("DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument = :i)").param("i", instrument).update();
            return jdbc.sql("DELETE FROM policy.version WHERE instrument = :i").param("i", instrument).update();
        });
    }

    private ResponseEntity<Map> post(String path, Object body) {
        return open.post().uri(path).contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toEntity(Map.class);
    }

    private String signedIn(UUID student, String matric) {
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/student-auth/accounts/" + student, Map.of("password", "first password 6630")).getStatusCode().value()).isEqualTo(200);
        String t = String.valueOf(post("/api/v1/student-auth/sign-in", Map.of("matricNo", matric, "password", "first password 6630")).getBody().get("token"));
        assertThat(it.call(t, HttpMethod.POST, "/api/v1/student-auth/change-password", Map.of("current", "first password 6630", "next", "Own-Password-6630")).getStatusCode().value()).isEqualTo(200);
        return t;
    }

    private static Map<String, Object> rowOf(List<Map<String, Object>> rows, String code) {
        return rows.stream().filter(x -> code.equals(x.get("course_code"))).findFirst().orElseThrow(() -> new AssertionError("no row " + code + " in " + rows));
    }

    @Test
    void aStudentSeesEveryEarlierCourseAndAddsSeveralCarryOversAtOnce() {
        int y = it.freeYear(4400, 4990, 1, 0);
        String earlier = (y - 1) + "/" + y;
        session = y + "/" + (y + 1);
        it.session(earlier, y - 1);
        it.session(session, y);
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
                    VALUES (:c, 'B.Sc. Carry-Over Picker Test', :d, :f, 'UNDER GRADUATE', 0, 400, 4)
                    """).param("c", prog).param("d", one[0]).param("f", one[1]).update();
            String other = jdbc.sql("SELECT code FROM ref.programme WHERE category = 'UNDER GRADUATE' AND NOT archived AND code <> :c ORDER BY code LIMIT 1")
                    .param("c", prog).query(String.class).single();
            return new String[] {one[0], prog, other};
        });
        String dept = place[0], prog = place[1];
        String matric = "MOAUM/ITP/" + yy + "/" + n;
        UUID student = it.student("ZZPICKER" + n, prog, "MOAUM/ADM/" + yy + "/66" + n, matric, 300);
        String token = signedIn(student, matric);

        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/sessions/" + session + "/schedule", Map.of("item", "School fees", "amount", 100000, "level", 300)).getStatusCode().value()).isEqualTo(200);
        String foreign = it.db(() -> {
            jdbc.sql("""
                    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
                    SELECT gen_random_uuid(), 'clearance', 'UNIVERSITY',
                           daterange(current_date, (SELECT min(lower(validity)) FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date)),
                           :i, 'bursar'
                     WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL
                    """).param("i", instrument).update();
            jdbc.sql("INSERT INTO policy.clearance_scheme SELECT id, true FROM policy.version WHERE instrument = :i ON CONFLICT DO NOTHING").param("i", instrument).update();
            jdbc.sql("""
                    INSERT INTO policy.clearance_rule SELECT v.id, p.code, CASE p.code WHEN 'HOSTEL' THEN 'NEVER_GATED' ELSE 'INSTALMENT_1' END
                      FROM policy.version v, ref.clearance_purpose p WHERE v.instrument = :i ON CONFLICT DO NOTHING
                    """).param("i", instrument).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
                        (:p || ' 101', 'Picker Failed', 3, 1, 100, :d, 'Core', 'LIVE'), (:p || ' 102', 'Picker Passed', 3, 1, 100, :d, 'Core', 'LIVE'),
                        (:p || ' 103', 'Picker No Result', 2, 1, 100, :d, 'Core', 'LIVE'), (:p || ' 201', 'Picker No Record', 3, 1, 200, :d, 'Core', 'LIVE'),
                        (:p || ' 202', 'Picker No Record Second', 3, 2, 200, :d, 'Core', 'LIVE'), (:p || ' 301', 'Picker Current', 3, 1, 300, :d, 'Core', 'LIVE'),
                        (:p || ' 109', 'Picker Of Another Programme', 3, 1, 100, :d, 'Core', 'LIVE')
                    ON CONFLICT (code) DO NOTHING
                    """).param("p", p).param("d", dept).update();
            jdbc.sql("""
                    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis)
                    SELECT :p || ' ' || x.n, :prog, x.l, 'Core' FROM (VALUES ('101', 100), ('102', 100), ('103', 100), ('201', 200), ('202', 200), ('301', 300)) x(n, l)
                    UNION ALL SELECT :p || ' 109', :other, 100, 'Core'
                    ON CONFLICT DO NOTHING
                    """).param("p", p).param("prog", prog).param("other", place[2]).update();
            jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester)
                    SELECT gen_random_uuid(), :p || ' ' || c, :e, 1 FROM unnest(ARRAY['101', '102', '103']) c
                    UNION ALL SELECT gen_random_uuid(), :p || ' 301', :s, 1
                    ON CONFLICT (course_code, session, semester, stream) DO NOTHING
                    """).param("p", p).param("e", earlier).param("s", session).update();
            UUID reg = UUID.randomUUID();
            jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (:r, :st, :e, 1, 100, 'APPROVED', now(), now())")
                    .param("r", reg).param("st", student).param("e", earlier).update();
            jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                    SELECT :r, o.id, 3, 'CURRENT', 'APPROVED' FROM catalogue.offering o WHERE o.session = :e AND o.course_code IN (:p || ' 101', :p || ' 102', :p || ' 103')
                    """).param("r", reg).param("e", earlier).param("p", p).update();
            // the failed and the passed course on published sheets; the third has none
            jdbc.sql("""
                    INSERT INTO assessment.score_sheet (id, offering_id) SELECT gen_random_uuid(), o.id FROM catalogue.offering o
                     WHERE o.session = :e AND o.course_code IN (:p || ' 101', :p || ' 102')
                    """).param("e", earlier).param("p", p).update();
            jdbc.sql("""
                    INSERT INTO assessment.score (sheet_id, student_id, ca, exam)
                    SELECT sh.id, :st, CASE WHEN o.course_code LIKE '% 101' THEN 10 ELSE 30 END, CASE WHEN o.course_code LIKE '% 101' THEN 15 ELSE 40 END
                      FROM assessment.score_sheet sh JOIN catalogue.offering o ON o.id = sh.offering_id WHERE o.session = :e AND o.course_code LIKE :p || ' %'
                    """).param("st", student).param("e", earlier).param("p", p).update();
            jdbc.sql("SELECT set_config('moaum.maintenance', 'on', true)").query().singleRow();
            jdbc.sql("""
                    UPDATE assessment.score_sheet sh SET stage = 'PUBLISHED', published_at = now(), senate_minute = 'IT V663'
                      FROM catalogue.offering o WHERE o.id = sh.offering_id AND o.session = :e AND o.course_code LIKE :p || ' %'
                    """).param("e", earlier).param("p", p).update();
            return jdbc.sql("SELECT id::text FROM catalogue.course WHERE code = :c").param("c", p + " 109").query(String.class).single();
        });
        Map<String, Object> ref = it.call(token, HttpMethod.POST, "/api/v1/me/fees/references", Map.of("session", session, "amount", 100000)).getBody();
        assertThat(it.call(bursar, HttpMethod.POST, "/api/v1/finance/references/" + ref.get("reference") + "/confirm", Map.of("channel", "Bank transfer", "note", "carry-over picker test"))
                .getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/registration/approval/rules", Map.of("session", session, "mode", "AUTO_APPROVAL", "allowStudentReset", true,
                "cardOnApproval", true, "reason", "Integration test: automatic approval")).getStatusCode().value()).isEqualTo(200);

        // ── every earlier course, with what it is now ──
        ResponseEntity<Map> listed = it.get(token, u -> u.path("/api/v1/me/registration/carry-overs").queryParam("session", session).queryParam("semester", 1).build());
        assertThat(listed.getStatusCode().value()).as(String.valueOf(listed.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) listed.getBody().get("student")).containsEntry("matricNo", matric).containsEntry("level", 300);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) listed.getBody().get("rows");
        assertThat(rowOf(rows, p + " 101")).containsEntry("status", "OUTSTANDING").containsEntry("selectable", true).containsEntry("last_grade", "F").containsEntry("origin_session", earlier);
        assertThat(rowOf(rows, p + " 102")).containsEntry("status", "CLEARED").containsEntry("selectable", false);
        assertThat(rowOf(rows, p + " 103")).containsEntry("status", "NO_RESULT").containsEntry("selectable", true);
        assertThat(rowOf(rows, p + " 201")).containsEntry("status", "NO_RECORD").containsEntry("selectable", true).containsEntry("level", 200);
        assertThat(rowOf(rows, p + " 202")).containsEntry("status", "NO_RECORD").containsEntry("selectable", false);
        assertThat(String.valueOf(rowOf(rows, p + " 202").get("reason"))).contains("second semester");
        assertThat(rows).noneMatch(r -> (p + " 301").equals(r.get("course_code")) || (p + " 109").equals(r.get("course_code")));

        // ── three added at once by course id; the passed one and another programme's course refused with their reasons ──
        List<String> ids = List.of(String.valueOf(rowOf(rows, p + " 101").get("course_id")), String.valueOf(rowOf(rows, p + " 103").get("course_id")),
                String.valueOf(rowOf(rows, p + " 201").get("course_id")), String.valueOf(rowOf(rows, p + " 102").get("course_id")), foreign);
        ResponseEntity<Map> added = it.call(token, HttpMethod.POST, "/api/v1/me/registration/carry-overs", Map.of("session", session, "semester", 1, "courses", ids));
        assertThat(added.getStatusCode().value()).as(String.valueOf(added.getBody())).isEqualTo(200);
        assertThat(added.getBody()).containsEntry("addedCount", 3).containsEntry("refusedCount", 2);
        List<Map<String, Object>> results = (List<Map<String, Object>>) added.getBody().get("results");
        assertThat(results).filteredOn(r -> Boolean.TRUE.equals(r.get("added"))).extracting(r -> r.get("courseCode"))
                .containsExactlyInAnyOrder(p + " 101", p + " 103", p + " 201");
        assertThat(results).filteredOn(r -> Boolean.TRUE.equals(r.get("added"))).allSatisfy(r -> assertThat(r.get("offering")).isNotNull());
        assertThat(results).filteredOn(r -> (p + " 102").equals(r.get("courseCode"))).singleElement().satisfies(r -> assertThat(r).containsEntry("code", "CARRY_CLEARED"));
        assertThat(results).filteredOn(r -> foreign.equals(String.valueOf(r.get("courseId")))).singleElement().satisfies(r -> assertThat(r).containsEntry("code", "CARRY_NOT_YOURS"));
        String types = jdbc.sql("""
                SELECT string_agg(o.course_code || '=' || e.entry_type || ':' || coalesce(e.added_as, '-'), ',' ORDER BY o.course_code)
                  FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                  JOIN catalogue.offering o ON o.id = e.offering_id
                 WHERE r.student_id = :st AND r.session = :s AND r.semester = 1
                """).param("st", student).param("s", session).query(String.class).single();
        assertThat(types).isEqualTo(p + " 101=CARRYOVER:-," + p + " 103=CARRYOVER:CARRY_OVER_DECLARED," + p + " 201=CARRYOVER:CARRY_OVER_DECLARED");

        // ── the same click again: nothing twice ──
        ResponseEntity<Map> again = it.call(token, HttpMethod.POST, "/api/v1/me/registration/carry-overs", Map.of("session", session, "semester", 1, "courses", ids.subList(0, 3)));
        assertThat(again.getStatusCode().value()).isEqualTo(200);
        assertThat(again.getBody()).containsEntry("addedCount", 0);
        assertThat((List<Map<String, Object>>) again.getBody().get("results")).allSatisfy(r -> assertThat(r).containsEntry("code", "CARRY_ALREADY_REGISTERED"));
        assertThat(jdbc.sql("""
                SELECT count(*) FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                 WHERE r.student_id = :st AND r.session = :s AND r.semester = 1
                """).param("st", student).param("s", session).query(Integer.class).single()).isEqualTo(3);

        // ── the registration of carry-overs alone, below the minimum, submitted and approved ──
        List<String> offerings = results.stream().filter(r -> Boolean.TRUE.equals(r.get("added"))).map(r -> String.valueOf(r.get("offering"))).toList();
        assertThat(it.call(token, HttpMethod.PUT, "/api/v1/me/registration", Map.of("session", session, "semester", 1, "offerings", offerings)).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> submitted = it.call(token, HttpMethod.POST, "/api/v1/me/registration/submit", Map.of("session", session, "semester", 1));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("result")).isEqualTo("approved");

        // ── the report reads the type ──
        ResponseEntity<Map> carry = it.get(registrar, u -> u.path("/api/v1/reports/course-registrations").queryParam("session", session).queryParam("semester", 1)
                .queryParam("prog", prog).queryParam("type", "CARRY_OVER").build());
        assertThat(carry.getStatusCode().value()).as(String.valueOf(carry.getBody())).isEqualTo(200);
        assertThat(carry.getBody()).containsEntry("total", 3);
        assertThat(it.get(registrar, u -> u.path("/api/v1/reports/course-registrations").queryParam("session", session).queryParam("semester", 1)
                .queryParam("prog", prog).queryParam("type", "CURRENT").build()).getBody()).containsEntry("total", 0);

        // ── an officer cannot reach the student's picker ──
        assertThat(it.get(academic, "/api/v1/me/registration/carry-overs").getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/me/registration/carry-overs", Map.of("session", session, "semester", 1, "courses", ids)).getStatusCode().value()).isEqualTo(403);
    }
}
