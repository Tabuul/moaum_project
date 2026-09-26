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
 * The matriculation number by configuration (V263): an Accounting student's number carries the faculty segment, the
 * programme code, the year and the Administration series' next number; a Medicine student's carries the MBBS segment
 * and no programme code, from the College series; a Law student's carries LAW and no code from the General series; two
 * students of one series take consecutive numbers; no number carries an empty segment; a programme set to carry a code
 * without one is refused, and so is a series moved backwards; a code changed after issue leaves the issued number as it
 * was; every issue is on the history; the Bursary reads and cannot change. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class MatricFormatIT {

    static final String SESSION = "2099/2100";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String registrar = ItSupport.token("registrar");
    String bursar = ItSupport.token("bursar");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2099);
    }

    /** an admitted student of the programme, registered and with no fee to pay for the entry session */
    private UUID ready(String surname, String programme) {
        String tag = String.format("%06d", new Random().nextInt(999_999));
        UUID s = it.student(surname + tag, programme, "MOAUM/ADM/99/" + tag, null, 100);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = :sess WHERE id = :s").param("sess", SESSION).param("s", s).update();
            jdbc.sql("INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08033335555', :e, now()) ON CONFLICT (student_id) DO NOTHING").param("s", s).param("e", (surname + tag).toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES ('ZZF 101', 'A course for the format test', 3, 1, 100, 'MTC', 'LIVE') ON CONFLICT (code) DO NOTHING").update();
            UUID offering = jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZF 101', :sess, 1) ON CONFLICT (course_code, session, semester) DO UPDATE SET semester = EXCLUDED.semester RETURNING id").param("sess", SESSION).query(UUID.class).single();
            UUID reg = jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (gen_random_uuid(), :s, :sess, 1, 100, 'APPROVED', now()) ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED' RETURNING id").param("s", s).param("sess", SESSION).query(UUID.class).single();
            return jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED') ON CONFLICT (registration_id, offering_id) DO NOTHING").param("r", reg).param("o", offering).update();
        });
        return s;
    }

    private String issue(UUID student) {
        ResponseEntity<Map> r = it.call(registrar, HttpMethod.POST, "/api/v1/matriculation/sessions/2099/2100/students/" + student + "/matriculate", null);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
    }

    @Test
    void theNumberFollowsTheConfiguration() {
        // ── the configuration as the schedule states it ──
        Map<String, Object> cfg = it.get(registrar, "/api/v1/matriculation/config").getBody();
        Map<String, Object> format = (Map<String, Object>) cfg.get("format");
        assertThat(format.get("university_code")).isEqualTo("MOAU");
        List<Map<String, Object>> programmes = (List<Map<String, Object>>) cfg.get("programmes");
        Map<String, Object> acc = programmes.stream().filter(p -> "C00019".equals(p.get("programme_code"))).findFirst().orElseThrow();
        assertThat(acc.get("matric_code")).isEqualTo("ACC");
        assertThat(acc.get("series_effective")).isEqualTo("ADMIN");
        assertThat(String.valueOf(acc.get("sample"))).matches("MOAU/AD/ACC/\\d{2}/\\d+");
        Map<String, Object> mbbs = programmes.stream().filter(p -> "C00061".equals(p.get("programme_code"))).findFirst().orElseThrow();
        assertThat(mbbs.get("matric_uses_code")).isEqualTo(false);
        assertThat(String.valueOf(mbbs.get("sample"))).matches("MOAU/MBBS/\\d{2}/\\d+").doesNotContain("//");
        assertThat(it.get(bursar, "/api/v1/matriculation/config").getStatusCode().value()).isEqualTo(403);

        // ── Accounting: faculty, programme code, year, the Administration series' next ──
        long adminBefore = jdbc.sql("SELECT last_issued FROM people.matric_series WHERE code = 'ADMIN'").query(Long.class).single();
        UUID a1 = ready("ZZMFACC", "C00019"), a2 = ready("ZZMFACC", "C00019");
        Map<String, Object> preview = it.get(registrar, "/api/v1/matriculation/config/preview/" + a1).getBody();
        assertThat(preview.get("matric_no")).isEqualTo("MOAU/AD/ACC/99/" + (adminBefore + 1));
        String n1 = issue(a1), n2 = issue(a2);
        assertThat(n1).isEqualTo("MOAU/AD/ACC/99/" + (adminBefore + 1));
        assertThat(n2).isEqualTo("MOAU/AD/ACC/99/" + (adminBefore + 2));
        assertThat(jdbc.sql("SELECT last_issued FROM people.matric_series WHERE code = 'ADMIN'").query(Long.class).single()).isEqualTo(adminBefore + 2);

        // ── Medicine: MBBS segment, no programme code, the College series; Law: LAW, no code, the General series ──
        long collegeBefore = jdbc.sql("SELECT last_issued FROM people.matric_series WHERE code = 'COLLEGE'").query(Long.class).single();
        String med = issue(ready("ZZMFMED", "C00061"));
        assertThat(med).isEqualTo("MOAU/MBBS/99/" + (collegeBefore + 1));
        String law = issue(ready("ZZMFLAW", "C00033"));
        assertThat(law).matches("MOAU/LAW/99/\\d+").doesNotContain("//");
        String pharm = issue(ready("ZZMFPHARM", "C73770"));
        assertThat(pharm).matches("MOAU/PHRM/99/\\d+");

        // ── the history holds every issue, with the parts it was built from ──
        List<Map<String, Object>> hist = it.getList(registrar, "/api/v1/matriculation/config/history?q=" + n1).getBody();
        assertThat(hist).hasSize(1);
        assertThat(hist.get(0).get("series_code")).isEqualTo("ADMIN");
        assertThat(String.valueOf(hist.get(0).get("components"))).contains("\"programme\": \"ACC\"");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject = 'Your matriculation number'").param("s", a1).query(Integer.class).single()).isGreaterThanOrEqualTo(1);

        // ── the rules of the configuration: no invented code, no series backwards, the Bursary reads only ──
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/programmes/C00019", Map.of("matricUsesCode", true, "matricCode", "")).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/series/ADMIN", Map.of("name", "Administration and Management series", "lastIssued", 1)).getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/matriculation/config/format", Map.of("universityCode", "XX")).getStatusCode().value()).isEqualTo(403);
        // a code changed after issue leaves the number issued as it was, and the next student takes the new code
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/programmes/C00019", Map.of("matricUsesCode", true, "matricCode", "ACT")).getStatusCode().value()).isEqualTo(200);
        assertThat(jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", a1).query(String.class).single()).isEqualTo(n1);
        String n3 = issue(ready("ZZMFACC", "C00019"));
        assertThat(n3).isEqualTo("MOAU/AD/ACT/99/" + (adminBefore + 3));
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/programmes/C00019", Map.of("matricUsesCode", true, "matricCode", "ACC")).getStatusCode().value()).isEqualTo(200);
        // the series' last number is moved forward by hand, and the next issue follows it
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/matriculation/config/series/ADMIN", Map.of("name", "Administration and Management series", "lastIssued", adminBefore + 10)).getStatusCode().value()).isEqualTo(200);
        String n4 = issue(ready("ZZMFACC", "C00019"));
        assertThat(n4).isEqualTo("MOAU/AD/ACC/99/" + (adminBefore + 11));
        // the number opens the portal as the student's identifier: the shape is on the record
        assertThat(jdbc.sql("SELECT count(*) FROM people.matric_history WHERE matric_no IN (:a, :b)").param("a", n1).param("b", n4).query(Integer.class).single()).isEqualTo(2);
    }
}
