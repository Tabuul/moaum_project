package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
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
 * The QR check codes (V360), through the API: the student's own receipt, examination card and course form carry a code
 * the API signed; the public verifier answers it in full. A code of the old kind — the plain digest anyone could make —
 * is honoured only for a record made before the change: a receipt in full, the card of an examination session still
 * open in full and of a closed one without the details, a course form without the details; for a record made after, it
 * verifies nothing. A session no other suite uses. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class CheckCodesIT {

    static final String SESSION = "2079/2080";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    /** the code a document carried before V360: sha256 of its printed facts, twelve upper-case hex digits */
    private static String old(String payload) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(payload.getBytes(StandardCharsets.UTF_8))).substring(0, 12).toUpperCase();
    }

    @Test
    void theApiSignsTheCodeAndAnOldOneIsHonouredOnlyForWhatCameBefore() throws Exception {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2079);
        String tag = UUID.randomUUID().toString().substring(0, 6).toUpperCase();
        String matric = "MOAUM/MTC/79/" + String.format("%04d", new java.util.Random().nextInt(9000) + 1000);
        UUID student = it.student("ZZCHECK" + tag, "C00023", null, matric, 100);
        matric = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        String me = TestTokens.token(student, List.of("student"));
        String reference = "ZZC-" + tag;
        String receiptNo = "RCT/79/" + tag;
        String m = matric;
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO finance.payment_reference (id, student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                    VALUES (gen_random_uuid(), :s, :ses, :r, 'School fees (full session)', 1000, now() + interval '30 days', now(), :s, 'BANK', :rc)
                    """).param("s", student).param("ses", SESSION).param("r", reference).param("rc", receiptNo).update();
            return jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                    VALUES (gen_random_uuid(), :s, :ses, 1, 100, 'APPROVED', now(), now())
                    """).param("s", student).param("ses", SESSION).update();
        });

        // ── the receipt: the code comes with the receipt, and the verifier answers it in full ──
        Map<String, Object> receipt = it.get(me, "/api/v1/me/fees/receipts/" + reference).getBody();
        String signed = String.valueOf(receipt.get("checkCode"));
        assertThat(signed).matches("[0-9A-F]{12}");
        Map<String, Object> v = it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + reference + "?c=" + signed, null).getBody();
        assertThat(v).containsEntry("genuine", true).containsKey("name").doesNotContainKey("legacy");
        String oldReceipt = old(reference + "|" + receiptNo);
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + reference + "?c=" + oldReceipt, null).getBody()).containsEntry("genuine", false);
        // confirmed before the change, its old code still answers in full (it needs the receipt number, printed only on it)
        it.db(() -> jdbc.sql("UPDATE finance.payment_reference SET confirmed_at = (SELECT cut_over_at FROM platform.check_code_cutover) - interval '1 day' WHERE reference = :r")
                .param("r", reference).update());
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + reference + "?c=" + oldReceipt, null).getBody())
                .containsEntry("genuine", true).containsEntry("legacy", true).containsKey("name");

        // ── the course form: the student's own code; the old one verifies nothing for a registration made after the change ──
        ResponseEntity<Map> bad = it.get(me, "/api/v1/me/check-code?kind=TRANSCRIPT&session=" + SESSION + "&semester=1");
        assertThat(bad.getStatusCode().value()).isEqualTo(422);
        Map<String, Object> reg = it.get(me, "/api/v1/me/check-code?kind=REG&session=" + SESSION + "&semester=1").getBody();
        assertThat(reg.get("number")).isEqualTo(m);
        String regPath = "/api/v1/verify/registration?matric=" + m + "&session=" + SESSION + "&semester=1&c=";
        assertThat(it.anon(HttpMethod.GET, regPath + reg.get("code"), null).getBody()).containsEntry("genuine", true).containsKey("name");
        String oldReg = old("REG|" + m + "|" + SESSION + "|1");
        assertThat(it.anon(HttpMethod.GET, regPath + oldReg, null).getBody()).containsEntry("genuine", false);
        // approved before the change: the old code says it is genuine, and names no one
        it.db(() -> jdbc.sql("""
                UPDATE registration.course_registration SET submitted_at = (SELECT cut_over_at FROM platform.check_code_cutover) - interval '2 days',
                       approved_at = (SELECT cut_over_at FROM platform.check_code_cutover) - interval '1 day'
                 WHERE student_id = :s AND session = :ses
                """).param("s", student).param("ses", SESSION).update());
        assertThat(it.anon(HttpMethod.GET, regPath + oldReg, null).getBody())
                .containsEntry("genuine", true).containsEntry("limited", true).doesNotContainKeys("name", "courses");

        // ── the examination card: signed, in full; old, only for cards released before the change — in full while that session is open ──
        Map<String, Object> exam = it.get(me, "/api/v1/me/check-code?kind=EXAM&session=" + SESSION + "&semester=1").getBody();
        String examPath = "/api/v1/verify/exam?matric=" + m + "&session=" + SESSION + "&semester=1&c=";
        assertThat(it.anon(HttpMethod.GET, examPath + exam.get("code"), null).getBody()).containsEntry("genuine", true).containsKeys("name", "courses");
        String oldExam = old("EXAM|" + m + "|" + SESSION + "|1");
        assertThat(it.anon(HttpMethod.GET, examPath + oldExam, null).getBody()).containsEntry("genuine", false);
        UUID examSession = UUID.randomUUID();
        it.db(() -> jdbc.sql("""
                INSERT INTO assessment.exam_session (id, session, semester, kind, exams_from, exams_to, sheets_due, state, cards_released_at)
                VALUES (:id, :ses, 1, 'MAIN', DATE '2080-01-10', DATE '2080-01-20', DATE '2080-02-10', 'OPEN',
                        (SELECT cut_over_at FROM platform.check_code_cutover) - interval '1 day')
                ON CONFLICT DO NOTHING
                """).param("id", examSession).param("ses", SESSION).update());
        assertThat(it.anon(HttpMethod.GET, examPath + oldExam, null).getBody()).containsEntry("genuine", true).containsEntry("legacy", true).containsKey("name");
        it.db(() -> jdbc.sql("UPDATE assessment.exam_session SET state = 'CLOSED' WHERE session = :ses AND semester = 1").param("ses", SESSION).update());
        assertThat(it.anon(HttpMethod.GET, examPath + oldExam, null).getBody())
                .containsEntry("genuine", true).containsEntry("limited", true).doesNotContainKeys("name", "photo", "courses");
        // a code for one student does not open another's
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/exam?matric=MOAUM/MTC/79/0000&session=" + SESSION + "&semester=1&c=" + exam.get("code"), null).getBody())
                .containsEntry("genuine", false);
    }
}
