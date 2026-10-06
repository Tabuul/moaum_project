package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import java.util.List;
import java.util.Map;
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
 * Examination cards and score sheets are released by Portal Management, each by its own act (V335): opening a session
 * releases nothing; the cards reach students only when released, and are withdrawn and released again; the sheets are
 * made only when released, once; only the Director of ICT does either. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class ExamReleaseIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    private boolean onDocket(ItSupport it, String studentToken, String examId) {
        ResponseEntity<Map> d = it.get(studentToken, "/api/v1/me/docket");
        assertThat(d.getStatusCode().value()).as(String.valueOf(d.getBody())).isEqualTo(200);
        return ((List<Map>) d.getBody().get("examSessions")).stream().anyMatch(x -> examId.equals(String.valueOf(x.get("id"))));
    }

    @Test
    void cardsAndSheetsAreReleasedByTheirOwnActs() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        // the session the student's docket reads (the current one, or the portal's fallback), on the calendar
        UUID student = it.student("ZZEXREL", "C00023", null, "MOAUM/MTC/95/9841", 200);
        String st = TestTokens.token(student, List.of("student"));
        String current = String.valueOf(it.get(st, "/api/v1/me/docket").getBody().get("session"));
        int y = Integer.parseInt(current.substring(0, 4));
        it.db(() -> jdbc.sql("""
                INSERT INTO policy.academic_session (id, name, starts_on, ends_on, state)
                SELECT gen_random_uuid(), :s, make_date(:y, 10, 1), make_date(:y + 1, 9, 30), 'PLANNED'
                 WHERE NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = :s)
                """).param("s", current).param("y", y).update());
        // a special third-semester sitting of the current session, made afresh by this test
        it.db(() -> jdbc.sql("""
                DELETE FROM assessment.exam_session x WHERE x.session = :s AND x.semester = 3 AND x.kind = 'SPECIAL'
                   AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.exam_session_id = x.id)
                """).param("s", current).update());
        String ict = ItSupport.token("ict");
        ResponseEntity<Map> made = it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions",
                Map.of("session", current, "semester", 3, "kind", "SPECIAL", "examsFrom", (y + 1) + "-07-01", "examsTo", (y + 1) + "-07-10", "sheetsDue", (y + 1) + "-07-30"));
        assumeTrue(made.getStatusCode().value() == 200, "the special sitting already carries sheets from an earlier run");
        String exam = String.valueOf(made.getBody().get("id"));

        // opening releases nothing
        ResponseEntity<Map> opened = it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam + "/open", null);
        assertThat(opened.getStatusCode().value()).as(String.valueOf(opened.getBody())).isEqualTo(200);
        assertThat(((Number) opened.getBody().get("sheetsMade")).intValue()).isZero();
        assertThat(onDocket(it, st, exam)).as("cards not yet released").isFalse();

        // only the Director of ICT releases
        assertThat(it.call(ItSupport.token("academic"), HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam + "/release-cards", null).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(ItSupport.token("exams"), HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam + "/release-sheets", null).getStatusCode().value()).isEqualTo(403);

        // the cards: released, withdrawn, released again
        ResponseEntity<Map> cards = it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam + "/release-cards", null);
        assertThat(cards.getStatusCode().value()).as(String.valueOf(cards.getBody())).isEqualTo(200);
        assertThat(cards.getBody().get("released")).isEqualTo(true);
        assertThat(onDocket(it, st, exam)).isTrue();
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam + "/withdraw-cards", null).getStatusCode().value()).isEqualTo(200);
        assertThat(onDocket(it, st, exam)).isFalse();
        assertThat(it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam + "/release-cards", null).getStatusCode().value()).isEqualTo(200);
        assertThat(onDocket(it, st, exam)).isTrue();

        // the sheets: released once, and refused a second time
        ResponseEntity<Map> sheets = it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam + "/release-sheets", null);
        assertThat(sheets.getStatusCode().value()).as(String.valueOf(sheets.getBody())).isEqualTo(200);
        ResponseEntity<Map> again = it.call(ict, HttpMethod.POST, "/api/v1/results/exam-sessions/" + exam + "/release-sheets", null);
        assertThat(again.getStatusCode().value()).isEqualTo(422);
        assertThat(again.getBody().get("code")).isEqualTo("EXAM_SHEETS_RELEASED");

        // the listing says when each was released
        List<Map> list = it.callList(ict, HttpMethod.GET, "/api/v1/results/exam-sessions?session=" + current, null).getBody();
        Map row = list.stream().filter(x -> exam.equals(String.valueOf(x.get("id")))).findFirst().orElseThrow();
        assertThat(row.get("cardsReleasedAt")).isNotNull();
        assertThat(row.get("sheetsReleasedAt")).isNotNull();
    }
}
