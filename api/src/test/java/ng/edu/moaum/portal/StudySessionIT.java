package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
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
 * V733 — an MBBS student's own academic session (the University's master prompt of 12 November 2026, part A), through the API: the
 * student reads the session they stand in, their level and the approved sessions; chooses the one behind the University's, confirmed;
 * every /me page then opens on it (GET /api/v1/me), the level unchanged and the change recorded; a student of another programme cannot;
 * a session off the calendar is refused; the College reads every change and sets the session back with a reason, a reader may not. The
 * test makes a session of its own CURRENT (an IT database has none) and puts the calendar back.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class StudySessionIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    String student(UUID id) {
        return TestTokens.token(id, List.of("student"));
    }

    @Test
    void anMbbsStudentStandsInTheSessionBehindTheUniversitysAndTheCollegeReadsAndSetsIt() {
        String before = "2960/2961", latest = "2961/2962";
        it.session(before, 2960);
        it.session(latest, 2961);
        String beforeState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", before).query(String.class).single();
        String latestState = jdbc.sql("SELECT state FROM policy.academic_session WHERE name = :n").param("n", latest).query(String.class).single();
        String previousCurrent = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1").query(String.class).optional().orElse(null);
        String mbbs = jdbc.sql("SELECT programme_code FROM college.programme_rule ORDER BY programme_code LIMIT 1").query(String.class).single();
        String other = jdbc.sql("SELECT p.code FROM ref.programme p WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND NOT college.runs_programme(p.code) ORDER BY p.code LIMIT 1")
                .query(String.class).single();
        int n = it.freeDraw(1000, 9000, k -> List.of("ZZSESSMBBS" + k, "ZZSESSOTHER" + k, "MOAU/V733/" + k, "MOAU/V733/" + (k + 1)));
        try {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE state = 'CURRENT'").update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CLOSED' WHERE name = :n").param("n", before).update();
                jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = coalesce(senate_minute, 'SEN/IT/733') WHERE name = :n").param("n", latest).update();
                return null;
            });
            UUID med = it.student("ZZSESSMBBS" + n, mbbs, null, "MOAU/V733/" + n, 200);
            UUID plain = it.student("ZZSESSOTHER" + n, other, null, "MOAU/V733/" + (n + 1), 200);
            it.db(() -> jdbc.sql("UPDATE people.student SET entry_session = :e, entry_level = 100 WHERE id IN (:a, :b)")
                    .param("e", before).param("a", med).param("b", plain).update());

            // ── the MBBS student's page: the University's session now, the one behind offered ──
            ResponseEntity<Map> page = it.get(student(med), "/api/v1/me/study-session");
            assertThat(page.getStatusCode().value()).as(String.valueOf(page.getBody())).isEqualTo(200);
            assertThat(page.getBody()).containsEntry("eligible", true).containsEntry("own", false).containsEntry("session", latest).containsEntry("university", latest);
            List<Map<String, Object>> options = (List<Map<String, Object>>) page.getBody().get("options");
            assertThat(options).extracting(o -> o.get("session"), o -> o.get("selectable"), o -> o.get("is_own"))
                    .contains(org.assertj.core.groups.Tuple.tuple(latest, true, true), org.assertj.core.groups.Tuple.tuple(before, true, false));

            // ── another programme's student may not; a session off the calendar is refused ──
            Map<String, Object> plainPage = it.get(student(plain), "/api/v1/me/study-session").getBody();
            assertThat(plainPage).containsEntry("eligible", false).containsEntry("refusal", "NOT_COLLEGE_PROGRAMME");
            ResponseEntity<Map> notYours = it.call(student(plain), HttpMethod.POST, "/api/v1/me/study-session", Map.of("session", before));
            assertThat(notYours.getStatusCode().value()).isEqualTo(422);
            assertThat(String.valueOf(notYours.getBody())).contains("STUDY_SESSION_NOT_YOURS");
            ResponseEntity<Map> off = it.call(student(med), HttpMethod.POST, "/api/v1/me/study-session", Map.of("session", "1901/1902"));
            assertThat(off.getStatusCode().value()).isEqualTo(422);
            assertThat(String.valueOf(off.getBody())).contains("STUDY_SESSION_NOT_APPROVED");

            // ── chosen: the student stands in it everywhere a /me page reads, the level unchanged, the change recorded ──
            ResponseEntity<Map> chosen = it.call(student(med), HttpMethod.POST, "/api/v1/me/study-session", Map.of("session", before));
            assertThat(chosen.getStatusCode().value()).as(String.valueOf(chosen.getBody())).isEqualTo(200);
            assertThat(chosen.getBody()).containsEntry("own", true).containsEntry("session", before);
            assertThat(it.get(student(med), "/api/v1/me").getBody()).containsEntry("session", before);
            assertThat(it.get(student(plain), "/api/v1/me").getBody()).containsEntry("session", latest);
            assertThat(jdbc.sql("SELECT people.student_current_session(:s)").param("s", med).query(String.class).single()).isEqualTo(before);
            assertThat(jdbc.sql("SELECT current_level FROM people.student WHERE id = :s").param("s", med).query(Integer.class).single()).isEqualTo(200);
            List<Map<String, Object>> history = (List<Map<String, Object>>) chosen.getBody().get("history");
            assertThat(history).hasSize(1);
            assertThat(history.get(0)).containsEntry("to_session", before).containsEntry("approval", "NOT_REQUIRED").containsEntry("office", "student")
                    .containsEntry("by_name", "The student");
            ResponseEntity<Map> again = it.call(student(med), HttpMethod.POST, "/api/v1/me/study-session", Map.of("session", before));
            assertThat(again.getStatusCode().value()).isEqualTo(422);
            assertThat(String.valueOf(again.getBody())).contains("STUDY_SESSION_UNCHANGED");

            // ── the College reads every change; a reader may not set; the Provost sets it back with a reason ──
            String provost = it.officer("provost", "college", "CHS");
            assertThat(it.get(ItSupport.token("bursar"), "/api/v1/study-sessions").getStatusCode().value()).isEqualTo(403);
            Map<String, Object> list = it.get(provost, "/api/v1/study-sessions?search=ZZSESSMBBS" + n).getBody();
            assertThat(((List<Map<String, Object>>) list.get("standing"))).extracting(x -> x.get("session")).containsExactly(before);
            assertThat(((List<Map<String, Object>>) list.get("changes"))).extracting(x -> x.get("to_session")).containsExactly(before);
            Map<String, Object> found = it.get(provost, "/api/v1/study-sessions/student?number=MOAU/V733/" + n).getBody();
            assertThat(found).containsEntry("own", true).containsEntry("session", before);
            String studentId = String.valueOf(((Map<String, Object>) found.get("student")).get("id"));
            assertThat(it.call(ItSupport.token("dean"), HttpMethod.POST, "/api/v1/study-sessions/" + studentId,
                    Map.of("reason", "The Dean may read, not set")).getStatusCode().value()).isEqualTo(403);
            assertThat(it.call(provost, HttpMethod.POST, "/api/v1/study-sessions/" + studentId, Map.of("reason", "short")).getStatusCode().value()).isEqualTo(400);
            ResponseEntity<Map> back = it.call(provost, HttpMethod.POST, "/api/v1/study-sessions/" + studentId,
                    Map.of("reason", "The College Board confirms the student in the University's session"));
            assertThat(back.getStatusCode().value()).as(String.valueOf(back.getBody())).isEqualTo(200);
            assertThat(back.getBody()).containsEntry("own", false).containsEntry("session", latest);
            assertThat(it.get(student(med), "/api/v1/me").getBody()).containsEntry("session", latest);
            List<Map<String, Object>> after = (List<Map<String, Object>>) back.getBody().get("history");
            assertThat(after.get(0)).containsEntry("from_session", before).containsEntry("approval", "SET_BY_OFFICE").containsEntry("office", "provost");
            assertThat(after.get(0).get("to_session")).isNull();
        } finally {
            it.db(() -> {
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", latestState).param("n", latest).update();
                jdbc.sql("UPDATE policy.academic_session SET state = :st WHERE name = :n").param("st", beforeState).param("n", before).update();
                if (previousCurrent != null && !previousCurrent.equals(latest)) jdbc.sql("UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = :n").param("n", previousCurrent).update();
                return null;
            });
        }
    }
}
