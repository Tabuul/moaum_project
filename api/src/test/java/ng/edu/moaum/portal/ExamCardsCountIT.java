package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V524: the examination cards available on the approvals overview, worked out for the session's approved students at once
 * (finance.session_clears_for), agree with the count of each student's own clearance (finance.clears), the way it was read before —
 * for the session and for a semester. Two students on approved registrations, one paid. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes"})
class ExamCardsCountIT {

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String session;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @AfterEach
    void clean() {
        if (session != null) it.db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", session).update());
    }

    @Test
    void theCardsCountedAtOnceAgreeWithEachStudentsOwnClearance() {
        int y = 6400 + new Random().nextInt(300);
        session = y + "/" + (y + 1);
        it.session(session, y);
        UUID paid = it.student(it.freeSurname("ZZCARDSPAID"), "C00061", it.freeNumber("MOAUM/ADM/64/", 6), it.freeNumber("MOAUM/CRD/64/", 6), 100);
        UUID unpaid = it.student(it.freeSurname("ZZCARDSUNPAID"), "C00061", it.freeNumber("MOAUM/ADM/64/", 6), it.freeNumber("MOAUM/CRD/64/", 6), 100);
        it.db(() -> {
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:s, 'School fees (cards count)', 40000, 100, 'C00061')")
                    .param("s", session).update();
            jdbc.sql("""
                    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                    VALUES (:st, :s, :r, 'School fees (cards count)', 40000, now() + interval '1 day', now(), gen_random_uuid(), 'BANK', :r)
                    """).param("st", paid).param("s", session).param("r", "MOAUM-FEE-CC" + UUID.randomUUID().toString().substring(0, 8).toUpperCase()).update();
            for (UUID s : new UUID[] {paid, unpaid}) {
                jdbc.sql("""
                        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                        VALUES (gen_random_uuid(), :st, :s, 1, 100, 'APPROVED', now(), now())
                        """).param("st", s).param("s", session).update();
            }
            return null;
        });
        String academic = ItSupport.token("academic");
        for (String semester : new String[] {"", "&semester=1", "&semester=2"}) {
            ResponseEntity<Map> cards = it.get(academic, "/api/v1/registration/approval/overview/cards?session=" + session + semester);
            assertThat(cards.getStatusCode().value()).as(String.valueOf(cards.getBody())).isEqualTo(200);
            Map<String, Object> before = jdbc.sql("""
                    SELECT count(*) FILTER (WHERE policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL OR finance.clears(r.student_id, r.session, 'EXAMINATION')) AS available,
                           count(*) AS approved
                      FROM registration.course_registration r
                     WHERE r.session = :s AND (CAST(:m AS integer) IS NULL OR r.semester = CAST(:m AS integer)) AND r.status IN ('APPROVED', 'LOCKED')
                    """).param("s", session).param("m", semester.isEmpty() ? null : Integer.valueOf(semester.substring(semester.length() - 1)), java.sql.Types.INTEGER)
                    .query().singleRow();
            assertThat(((Number) cards.getBody().get("available")).longValue()).as(semester).isEqualTo(((Number) before.get("available")).longValue());
            assertThat(((Number) cards.getBody().get("approved")).longValue()).as(semester).isEqualTo(((Number) before.get("approved")).longValue());
        }
        assertThat(((Number) it.get(academic, "/api/v1/registration/approval/overview/cards?session=" + session).getBody().get("approved")).intValue()).isEqualTo(2);
    }
}
